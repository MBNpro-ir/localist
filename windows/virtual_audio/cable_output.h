#pragma once
#include <windows.h>
#include <atomic>
#include <condition_variable>
#include <mutex>
#include <string>
#include <thread>
#include <vector>
#include "render_queue.h"

struct LocalistCableEndpoint { std::wstring id, name; };
std::vector<LocalistCableEndpoint> LocalistCableEndpoints(bool recording = false, bool all = false);
std::vector<LocalistCableEndpoint> LocalistConfiguredCableEndpoints();
std::wstring LocalistDefaultPlaybackEndpoint();
struct LocalistAudioRenderOptions {
  int minimum_ms=0, maximum_ms=100;
  double gain_db=0;
  bool event_sync=true, pcm=false, playback=false;
};
struct LocalistAudioQueueStatus { uint64_t buffered=0,dropped=0,underruns=0,clipped=0; };

// Native received PCM -> a specific WASAPI render endpoint. Never changes the
// default device; no WebRTC global output selection, loopback or speaker playback.
class LocalistCableOutput {
 public:
  ~LocalistCableOutput() { Stop(); }
  bool Start(const std::wstring& endpointId, const LocalistAudioRenderOptions& options = {});
  void Stop();
  void Push(const int16_t* samples, size_t frames);
  uint64_t Frames() const { return frames_.load(); }
  unsigned long Error() const { return error_.load(); }
  LocalistAudioQueueStatus QueueStatus();
 private:
  void Run();
  std::thread worker_;
  HANDLE stop_ = nullptr;
  std::mutex queue_lock_, ready_lock_;
  std::condition_variable ready_;
  bool started_ = false;
  LocalistRenderQueue queue_;
  LocalistAudioRenderOptions options_;
  std::atomic<unsigned long> error_{0};
  std::atomic<uint64_t> frames_{0};
  std::wstring endpoint_id_;
};
