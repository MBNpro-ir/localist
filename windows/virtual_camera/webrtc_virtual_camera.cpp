#include "webrtc_virtual_camera.h"
#include <windows.h>
#include <mutex>
#include <vector>
#include "shared-memory-queue.h"

namespace {
std::mutex mutex;
int64_t chosen = -1;
uint64_t frames = 0;
int fps = 30, width = 0, height = 0;
video_queue_t* queue = nullptr;
std::vector<uint8_t> nv12;
void Close() {
  video_queue_close(queue); queue = nullptr;
  width = height = 0;
  nv12.clear();
}
uint64_t Timestamp() {
  LARGE_INTEGER current, frequency;
  QueryPerformanceCounter(&current); QueryPerformanceFrequency(&frequency);
  return static_cast<uint64_t>(static_cast<double>(current.QuadPart) * 10000000.0 / static_cast<double>(frequency.QuadPart));
}
void Rotate(const uint8_t* source, int stride, uint8_t* dest, int w, int h, int rotation, int step = 1) {
  const int out_width = rotation == 90 || rotation == 270 ? h : w;
  for (int y = 0; y < h; ++y) for (int x = 0; x < w; ++x) {
    int dx = x, dy = y;
    if (rotation == 90) { dx = h - y - 1; dy = x; }
    else if (rotation == 180) { dx = w - x - 1; dy = h - y - 1; }
    else if (rotation == 270) { dx = y; dy = w - x - 1; }
    dest[(dy * out_width + dx) * step] = source[y * stride + x];
  }
}
}

extern "C" __declspec(dllexport) int LocalistVirtualCameraSetTexture(int64_t texture, int requested_fps) {
  std::lock_guard<std::mutex> lock(mutex);
  if (requested_fps < 1 || requested_fps > 60) return 0;
  if (chosen != texture || fps != requested_fps) Close();
  chosen = texture; fps = requested_fps; frames = 0;
  return 1;
}
extern "C" __declspec(dllexport) uint64_t LocalistVirtualCameraFrames() {
  std::lock_guard<std::mutex> lock(mutex);
  return frames;
}
void LocalistVirtualCameraRelease(int64_t texture) {
  std::lock_guard<std::mutex> lock(mutex);
  if (chosen == texture) { chosen = -1; Close(); }
}
void LocalistVirtualCameraFrame(int64_t texture, libwebrtc::scoped_refptr<libwebrtc::RTCVideoFrame> frame) {
  std::lock_guard<std::mutex> lock(mutex);
  if (texture != chosen || chosen < 0 || !frame) return;
  const int source_width = frame->width() & ~1, source_height = frame->height() & ~1;
  const int rotation = static_cast<int>(frame->rotation());
  const int w = rotation == 90 || rotation == 270 ? source_height : source_width;
  const int h = rotation == 90 || rotation == 270 ? source_width : source_height;
  if (w < 2 || h < 2 || w > 4096 || h > 4096 || !frame->DataY() || !frame->DataU() || !frame->DataV()) return;
  if (queue && (width != w || height != h)) Close();
  if (!queue) {
    queue = video_queue_create(static_cast<uint32_t>(w), static_cast<uint32_t>(h), 10000000ULL / static_cast<uint64_t>(fps));
    if (!queue) return; // Readers release the previous-size queue asynchronously.
    width = w; height = h; nv12.resize(static_cast<size_t>(w) * h * 3 / 2);
  }
  const size_t y_size = static_cast<size_t>(w) * h;
  Rotate(frame->DataY(), frame->StrideY(), nv12.data(), source_width, source_height, rotation);
  Rotate(frame->DataU(), frame->StrideU(), nv12.data() + y_size, source_width / 2, source_height / 2, rotation, 2);
  Rotate(frame->DataV(), frame->StrideV(), nv12.data() + y_size + 1, source_width / 2, source_height / 2, rotation, 2);
  uint8_t* planes[] = {nv12.data(), nv12.data() + y_size};
  uint32_t strides[] = {static_cast<uint32_t>(w), static_cast<uint32_t>(w)};
  video_queue_write(queue, planes, strides, Timestamp());
  ++frames;
}
