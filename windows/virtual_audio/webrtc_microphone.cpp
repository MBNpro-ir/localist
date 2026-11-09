#include "webrtc_microphone.h"
#include "audio_protocol.h"
#include "pcm_converter.h"
#include "cable_output.h"
#include "cable_assignment.h"
#include <windows.h>
#include <array>
#include <atomic>
#include <memory>
#include <mutex>

namespace {
class Sink final : public libwebrtc::AudioTrackSink {
 public:
  explicit Sink(int slot) : slot_(slot) { packet_.header={LOCALIST_AUDIO_MAGIC,LOCALIST_AUDIO_ABI,
    static_cast<uint32_t>(slot),0,48000,1,16,0}; }
  ~Sink() override { Stop(); }
  bool Start(libwebrtc::scoped_refptr<libwebrtc::RTCAudioTrack> track, const LocalistCableEndpoint& endpoint) {
    if (track_==track && endpoint_.id==endpoint.id && file_!=INVALID_HANDLE_VALUE && !Error()) return true;
    Stop();if (!track) return true;
    endpoint_=endpoint;
#ifdef LOCALIST_AUDIO_QA_PIPE
    wchar_t name[128];swprintf_s(name,L"\\\\.\\pipe\\LocalistAudioQA-%lu-%d",GetCurrentProcessId(),slot_);
    file_=CreateFileW(name,GENERIC_WRITE,0,nullptr,OPEN_EXISTING,0,nullptr);
#else
    if (!cable_.Start(endpoint.id)) { error_=cable_.Error();return false; }
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
    if (file_==INVALID_HANDLE_VALUE) return;
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
};
std::mutex control;
std::array<std::unique_ptr<Sink>,4> sinks;
}
std::string Utf8(const std::wstring& value) {
  if(value.empty())return {};
  const int size=WideCharToMultiByte(CP_UTF8,0,value.c_str(),static_cast<int>(value.size()),nullptr,0,nullptr,nullptr);
  std::string result(size,0);WideCharToMultiByte(CP_UTF8,0,value.c_str(),static_cast<int>(value.size()),result.data(),size,nullptr,nullptr);return result;
}
bool LocalistMicrophoneSetTrack(int slot,libwebrtc::scoped_refptr<libwebrtc::RTCAudioTrack> track,const std::string& requested) {
  if(slot<0||slot>=4)return false;
  std::lock_guard<std::mutex> lock(control);
  if(!sinks[slot])sinks[slot]=std::make_unique<Sink>(slot);
  if(!track)return sinks[slot]->Start(nullptr,{});
#ifdef LOCALIST_AUDIO_QA_PIPE
  return sinks[slot]->Start(track,{});
#else
  const auto endpoints=LocalistConfiguredCableEndpoints();
  std::vector<std::string> available,occupied;
  for(const auto& endpoint:endpoints)available.push_back(Utf8(endpoint.id));
  for(int i=0;i<4;++i)if(i!=slot&&sinks[i]&&sinks[i]->Active())occupied.push_back(Utf8(sinks[i]->Endpoint().id));
  const int selected=SelectLocalistCable(available,occupied,requested);
  if(selected>=0)return sinks[slot]->Start(track,endpoints[selected]);
  sinks[slot]->Stop();sinks[slot]->Fail(HRESULT_FROM_WIN32(endpoints.empty()?ERROR_NOT_FOUND:ERROR_BUSY));return false;
#endif
}
std::string LocalistMicrophoneName(int slot) {
  std::lock_guard<std::mutex> lock(control);
  if(slot<0||slot>=4||!sinks[slot])return {};
  auto name=sinks[slot]->Endpoint().name;const auto pos=name.find(L"Input");if(pos!=std::wstring::npos)name.replace(pos,5,L"Output");return Utf8(name);
}
void LocalistMicrophonesStop() { std::lock_guard<std::mutex> lock(control);for(auto& sink:sinks)if(sink)sink->Stop(); }
uint64_t LocalistMicrophoneFrames(int slot) { std::lock_guard<std::mutex> lock(control);return slot>=0&&slot<4&&sinks[slot]?sinks[slot]->Frames():0; }
unsigned long LocalistMicrophoneError(int slot) { std::lock_guard<std::mutex> lock(control);return slot>=0&&slot<4&&sinks[slot]?sinks[slot]->Error():0; }
