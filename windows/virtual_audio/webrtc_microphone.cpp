#include "webrtc_microphone.h"
#include "audio_protocol.h"
#include "pcm_converter.h"
#include "cable_output.h"
#include "cable_assignment.h"
#include "pcm_packet.h"
#include <windows.h>
#include <array>
#include <atomic>
#include <memory>
#include <mutex>
#include <cmath>

namespace {
class Sink final : public libwebrtc::AudioTrackSink {
 public:
  explicit Sink(int slot) : slot_(slot) { packet_.header={LOCALIST_AUDIO_MAGIC,LOCALIST_AUDIO_ABI,
    static_cast<uint32_t>(slot),0,48000,1,16,0}; }
  ~Sink() override { Stop(); }
  bool Start(libwebrtc::scoped_refptr<libwebrtc::RTCAudioTrack> track, const LocalistCableEndpoint& endpoint,
      const LocalistAudioRenderOptions& options={}) {
    Stop();if (!track) return true;
    endpoint_=endpoint;options_=options;sequence_ready_=false;
#ifdef LOCALIST_AUDIO_QA_PIPE
    wchar_t name[128];swprintf_s(name,L"\\\\.\\pipe\\LocalistAudioQA-%lu-%d",GetCurrentProcessId(),slot_);
    file_=CreateFileW(name,GENERIC_WRITE,0,nullptr,OPEN_EXISTING,0,nullptr);
#else
    if (!cable_.Start(endpoint.id,options)) { error_=cable_.Error();return false; }
    file_=reinterpret_cast<HANDLE>(1); // Active WASAPI output; not an OS handle.
#endif
    if (file_==INVALID_HANDLE_VALUE) { error_=GetLastError();return false; }
    error_=0;frames_=0;converter_.Reset();packet_.header.frames=0;
    track_=track;track_->AddSink(this);return true;
  }
  void Stop() {
    if (track_) { track_->RemoveSink(this);track_=nullptr; }
    std::lock_guard<std::mutex> lock(callback_);
    if (file_!=INVALID_HANDLE_VALUE) {
      packet_.header.frames=0;packet_.header.flags=LOCALIST_AUDIO_RESET;Send();
#ifdef LOCALIST_AUDIO_QA_PIPE
      CloseHandle(file_);file_=INVALID_HANDLE_VALUE;
#else
      cable_.Stop();file_=INVALID_HANDLE_VALUE;
#endif
    }
    packet_.header.frames=0;packet_.header.flags=0;converter_.Reset();endpoint_={};
  }
  void OnData(const void* data,int bits,int rate,size_t channels,size_t frames) override {
    std::lock_guard<std::mutex> lock(callback_);
    if (file_==INVALID_HANDLE_VALUE || options_.pcm) return;
    const bool valid=converter_.Convert(data,bits,rate,channels,frames,[this](int16_t sample) {
      packet_.samples[packet_.header.frames++]=sample;
      if(packet_.header.frames==480) { Send();packet_.header.frames=0; }
    });
    if (!valid) error_=ERROR_BAD_FORMAT;
  }
  uint64_t Frames() const { return frames_.load(); }
  DWORD Error() const { return error_.load() ? error_.load() : cable_.Error(); }
  bool Active() const { return track_!=nullptr; }
  const LocalistCableEndpoint& Endpoint() const { return endpoint_; }
  void Fail(DWORD error) { error_=error; }
  bool Pcm(const std::vector<uint8_t>& bytes) {
    std::lock_guard<std::mutex> lock(callback_);
    LocalistNetworkPcmHeader header;
    if(!options_.pcm||file_==INVALID_HANDLE_VALUE||!ReadLocalistNetworkPcm(bytes.data(),bytes.size(),header))return false;
    if(sequence_ready_&&static_cast<int32_t>(header.sequence-last_sequence_)<=0)return true;
    sequence_ready_=true;last_sequence_=header.sequence;
    std::array<int16_t,1920> samples{};
    std::memcpy(samples.data(),bytes.data()+sizeof(header),header.frames*sizeof(int16_t));
    return converter_.Convert(samples.data(),16,header.rate,1,header.frames,[this](int16_t sample){
      packet_.samples[packet_.header.frames++]=sample;
      if(packet_.header.frames==480){Send();packet_.header.frames=0;}
    });
  }
  LocalistAudioQueueStatus Queue() { return cable_.QueueStatus(); }
 private:
  void Send() {
#ifdef LOCALIST_AUDIO_QA_PIPE
    DWORD bytes=0;const DWORD length=sizeof(LocalistAudioHeader)+packet_.header.frames*sizeof(int16_t);
    const bool ok=WriteFile(file_,&packet_,length,&bytes,nullptr)!=FALSE;
#else
    if (packet_.header.frames) cable_.Push(packet_.samples,packet_.header.frames);
    const bool ok=cable_.Error()==0;
#endif
    if(ok) { frames_+=packet_.header.frames;error_=0; } else error_=cable_.Error() ? cable_.Error() : GetLastError();
  }
  int slot_;HANDLE file_=INVALID_HANDLE_VALUE;
  libwebrtc::scoped_refptr<libwebrtc::RTCAudioTrack> track_;
  LocalistAudioPacket packet_{};LocalistPcmConverter converter_;
  std::atomic<uint64_t> frames_{0};std::atomic<DWORD> error_{0};
  std::mutex callback_;
  LocalistCableOutput cable_;
  LocalistCableEndpoint endpoint_;
  LocalistAudioRenderOptions options_;
  uint32_t last_sequence_=0;
  bool sequence_ready_=false;
};
std::mutex control;
std::array<std::unique_ptr<Sink>,4> sinks;
std::string silent_playout_endpoint;
class CaptureProcessor final : public libwebrtc::RTCAudioProcessing::CustomProcessing {
 public:
  std::atomic<double> gain{1};
  std::atomic<bool> pcm{false};
  std::mutex emitter_mutex;
  std::function<void(const std::vector<uint8_t>&)> emit;
  void Initialize(int rate,int) override {rate_=rate;count_=0;}
  void Reset(int rate) override {rate_=rate;count_=0;}
  void Release() override {}
  void Process(int,int frames,int size,float* samples) override {
    if(!samples||rate_<8000||rate_>48000)return;
    const auto factor=gain.load();
    for(int i=0;i<std::min(frames,size);++i){
      const double input=static_cast<double>(samples[i])*factor;
      const auto value=std::isfinite(input)?std::clamp(input,-32768.0,32767.0):0;
      samples[i]=static_cast<float>(value);
      if(!pcm.load())continue;
      buffer_[count_++]=static_cast<int16_t>(value);
      if(count_>=static_cast<size_t>(rate_/50)){
        LocalistNetworkPcmHeader header;header.rate=rate_;header.frames=static_cast<uint32_t>(count_);header.sequence=sequence_++;
        std::vector<uint8_t> packet(sizeof(header)+count_*sizeof(int16_t));
        std::memcpy(packet.data(),&header,sizeof(header));std::memcpy(packet.data()+sizeof(header),buffer_.data(),count_*sizeof(int16_t));
        {std::lock_guard<std::mutex> lock(emitter_mutex);if(emit)emit(packet);}count_=0;
      }
    }
  }
  void ProcessPcm(int16_t* data,int rate,int channels,size_t frames) {
    if(!data||rate<8000||rate>48000||channels!=1||frames>480)return;
    if(rate_!=rate)Initialize(rate,1);
    std::array<float,480> samples{};
    for(size_t i=0;i<frames;++i)samples[i]=data[i];
    Process(1,static_cast<int>(frames),static_cast<int>(frames),samples.data());
    for(size_t i=0;i<frames;++i)data[i]=static_cast<int16_t>(samples[i]);
  }
 private:
  int rate_=48000;size_t count_=0;uint32_t sequence_=0;
  std::array<int16_t,960> buffer_{};
} capture_processor,loopback_processor;
}
void LocalistPrepareCaptureAudio(libwebrtc::scoped_refptr<libwebrtc::RTCAudioDevice> device,
    libwebrtc::scoped_refptr<libwebrtc::RTCAudioProcessing> processing,
    std::function<void(const std::vector<uint8_t>&)> pcm) {
  std::lock_guard<std::mutex> lock(control);
  {std::lock_guard<std::mutex> emit_lock(capture_processor.emitter_mutex);capture_processor.emit=pcm;}
  {std::lock_guard<std::mutex> emit_lock(loopback_processor.emitter_mutex);loopback_processor.emit=std::move(pcm);}
  processing->SetCapturePostProcessing(&capture_processor);
  // Received audio is consumed by our raw sinks, never by physical speakers.
  // Route WebRTC's muted hardware playout to a cable too, so its communications
  // session cannot duck the user's speaker endpoint during connect/retry.
  // This is internal routing only: no Windows default or volume is changed.
  const auto cables = LocalistCableEndpoints();
  for (uint16_t i = 0; i < device->PlayoutDevices(); ++i) {
    char name[libwebrtc::RTCAudioDevice::kAdmMaxDeviceNameSize]{};
    char id[libwebrtc::RTCAudioDevice::kAdmMaxGuidSize]{};
    if (device->PlayoutDeviceName(i, name, id) != 0) continue;
    const int size = MultiByteToWideChar(CP_UTF8, 0, id, -1, nullptr, 0);
    std::wstring wide(size, 0);
    if (size) { MultiByteToWideChar(CP_UTF8, 0, id, -1, wide.data(), size); wide.pop_back(); }
    for (const auto& cable : cables) {
      if (_wcsicmp(cable.id.c_str(), wide.c_str()) == 0) {
        if (device->SetPlayoutDevice(i) == 0) silent_playout_endpoint = id;
        return;
      }
    }
  }
}
void LocalistConfigureCaptureAudio(double gainDb,bool pcm) {
  capture_processor.gain=std::pow(10.0,std::clamp(gainDb,-30.0,40.0)/20.0);
  capture_processor.pcm=pcm;
  loopback_processor.gain=capture_processor.gain.load();
  loopback_processor.pcm=pcm;
}
void LocalistProcessLoopbackAudio(int16_t* data,int rate,int channels,size_t frames) {
  // Custom desktop loopback bypasses WebRTC's microphone processing graph.
  // Feed the same bounded postprocessor explicitly, once per capture block.
  loopback_processor.ProcessPcm(data,rate,channels,frames);
}
std::string LocalistCapturePlayoutEndpoint() {
  std::lock_guard<std::mutex> lock(control);
  return silent_playout_endpoint;
}
std::string Utf8(const std::wstring& value) {
  if(value.empty())return {};
  const int size=WideCharToMultiByte(CP_UTF8,0,value.c_str(),static_cast<int>(value.size()),nullptr,0,nullptr,nullptr);
  std::string result(size,0);WideCharToMultiByte(CP_UTF8,0,value.c_str(),static_cast<int>(value.size()),result.data(),size,nullptr,nullptr);return result;
}
bool LocalistMicrophoneSetTrack(int slot,libwebrtc::scoped_refptr<libwebrtc::RTCAudioTrack> track,const std::string& requested,const LocalistAudioRenderOptions& options) {
  if(slot<0||slot>=4)return false;
  std::lock_guard<std::mutex> lock(control);
  if(!sinks[slot])sinks[slot]=std::make_unique<Sink>(slot);
  if(!track)return sinks[slot]->Start(nullptr,{});
#ifdef LOCALIST_AUDIO_QA_PIPE
  return sinks[slot]->Start(track,{});
#else
  const auto endpoints=options.playback?LocalistCableEndpoints(false,true):LocalistConfiguredCableEndpoints();
  std::vector<std::string> available,occupied;
  for(const auto& endpoint:endpoints)available.push_back(Utf8(endpoint.id));
  for(int i=0;i<4;++i)if(!options.playback&&i!=slot&&sinks[i]&&sinks[i]->Active())occupied.push_back(Utf8(sinks[i]->Endpoint().id));
  const auto wanted=options.playback&&requested.empty()?Utf8(LocalistDefaultPlaybackEndpoint()):requested;
  const int selected=SelectLocalistCable(available,occupied,wanted);
  if(selected>=0)return sinks[slot]->Start(track,endpoints[selected],options);
  sinks[slot]->Stop();sinks[slot]->Fail(HRESULT_FROM_WIN32(endpoints.empty()?ERROR_NOT_FOUND:ERROR_BUSY));return false;
#endif
}
bool LocalistMicrophonePcm(int slot,const std::vector<uint8_t>& bytes){
  std::lock_guard<std::mutex> lock(control);return slot>=0&&slot<4&&sinks[slot]&&sinks[slot]->Pcm(bytes);
}
LocalistAudioQueueStatus LocalistMicrophoneQueue(int slot){
  std::lock_guard<std::mutex> lock(control);return slot>=0&&slot<4&&sinks[slot]?sinks[slot]->Queue():LocalistAudioQueueStatus{};
}
std::string LocalistMicrophoneName(int slot) {
  std::lock_guard<std::mutex> lock(control);
  if(slot<0||slot>=4||!sinks[slot])return {};
  auto name=sinks[slot]->Endpoint().name;const auto pos=name.find(L"Input");if(pos!=std::wstring::npos)name.replace(pos,5,L"Output");return Utf8(name);
}
void LocalistMicrophonesStop() {
  std::lock_guard<std::mutex> lock(control);
  capture_processor.pcm=false;loopback_processor.pcm=false;
  {std::lock_guard<std::mutex> emit_lock(capture_processor.emitter_mutex);capture_processor.emit=nullptr;}
  {std::lock_guard<std::mutex> emit_lock(loopback_processor.emitter_mutex);loopback_processor.emit=nullptr;}
  for(auto& sink:sinks)if(sink)sink->Stop();
}
uint64_t LocalistMicrophoneFrames(int slot) { std::lock_guard<std::mutex> lock(control);return slot>=0&&slot<4&&sinks[slot]?sinks[slot]->Frames():0; }
unsigned long LocalistMicrophoneError(int slot) { std::lock_guard<std::mutex> lock(control);return slot>=0&&slot<4&&sinks[slot]?sinks[slot]->Error():0; }
