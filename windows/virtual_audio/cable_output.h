#pragma once
#include <windows.h>
#include <atomic>
#include <condition_variable>
#include <mutex>
#include <string>
#include <thread>
#include <vector>
#include "pcm_ring.h"

struct LocalistCableEndpoint { std::wstring id, name; };
std::vector<LocalistCableEndpoint> LocalistCableEndpoints(bool recording = false);
std::vector<LocalistCableEndpoint> LocalistConfiguredCableEndpoints();

// Native received PCM -> a specific WASAPI render endpoint. Never changes the
// default device; no WebRTC global output selection, loopback or speaker playback.
class LocalistCableOutput {
 public:
  ~LocalistCableOutput() { Stop(); }
  bool Start(const std::wstring& endpointId);
  void Stop();
  void Push(const int16_t* samples, size_t frames);
  uint64_t Frames() const { return frames_.load(); }
  unsigned long Error() const { return error_.load(); }
 private:
  void Run();
  std::thread worker_;
  HANDLE stop_ = nullptr;
  std::mutex queue_lock_, ready_lock_;
  std::condition_variable ready_;
  bool started_ = false;
  LocalistPcmRing queue_;
  std::atomic<unsigned long> error_{0};
  std::atomic<uint64_t> frames_{0};
  std::wstring endpoint_id_;
};
