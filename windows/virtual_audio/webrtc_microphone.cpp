#include "webrtc_microphone.h"
#include "audio_protocol.h"
#include "pcm_converter.h"
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
  bool Start(libwebrtc::scoped_refptr<libwebrtc::RTCAudioTrack> track) {
    if (track_==track && file_!=INVALID_HANDLE_VALUE && !error_.load()) return true;
    Stop();if (!track) return true;
#ifdef LOCALIST_AUDIO_QA
    wchar_t name[128];swprintf_s(name,L"\\\\.\\pipe\\LocalistAudioQA-%lu-%d",GetCurrentProcessId(),slot_);
    file_=CreateFileW(name,GENERIC_WRITE,0,nullptr,OPEN_EXISTING,0,nullptr);
#else
    file_=CreateFileW(L"\\\\.\\LocalistAudioControl",GENERIC_WRITE,FILE_SHARE_READ|FILE_SHARE_WRITE,
      nullptr,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,nullptr);
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
      CloseHandle(file_);file_=INVALID_HANDLE_VALUE;
    }
    packet_.header.frames=0;packet_.header.flags=0;converter_.Reset();
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
  DWORD Error() const { return error_.load(); }
 private:
  void Send() {
    DWORD bytes=0;const DWORD length=sizeof(LocalistAudioHeader)+packet_.header.frames*sizeof(int16_t);
#ifdef LOCALIST_AUDIO_QA
    const bool ok=WriteFile(file_,&packet_,length,&bytes,nullptr)!=FALSE;
#else
    const bool ok=DeviceIoControl(file_,LOCALIST_AUDIO_WRITE_IOCTL,&packet_,length,nullptr,0,&bytes,nullptr)!=FALSE;
#endif
    if(ok) { frames_+=packet_.header.frames;error_=0; } else error_=GetLastError();
  }
  int slot_;HANDLE file_=INVALID_HANDLE_VALUE;
  libwebrtc::scoped_refptr<libwebrtc::RTCAudioTrack> track_;
  LocalistAudioPacket packet_{};LocalistPcmConverter converter_;
  std::atomic<uint64_t> frames_{0};std::atomic<DWORD> error_{0};
  std::mutex callback_;
};
std::mutex control;
std::array<std::unique_ptr<Sink>,4> sinks;
}
bool LocalistMicrophoneSetTrack(int slot,libwebrtc::scoped_refptr<libwebrtc::RTCAudioTrack> track) {
  if(slot<0||slot>=4)return false;
  std::lock_guard<std::mutex> lock(control);
  if(!sinks[slot])sinks[slot]=std::make_unique<Sink>(slot);
  return sinks[slot]->Start(track);
}
void LocalistMicrophonesStop() { std::lock_guard<std::mutex> lock(control);for(auto& sink:sinks)if(sink)sink->Stop(); }
uint64_t LocalistMicrophoneFrames(int slot) { std::lock_guard<std::mutex> lock(control);return slot>=0&&slot<4&&sinks[slot]?sinks[slot]->Frames():0; }
unsigned long LocalistMicrophoneError(int slot) { std::lock_guard<std::mutex> lock(control);return slot>=0&&slot<4&&sinks[slot]?sinks[slot]->Error():0; }
