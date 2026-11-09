#pragma once
#include <stdint.h>
#include <stddef.h>

// Localist audio wire protocol: fixed-size fields; no kernel/user pointers.
static const uint32_t LOCALIST_AUDIO_MAGIC = 0x4c4d4943;
static const uint32_t LOCALIST_AUDIO_ABI = 1;
static const uint32_t LOCALIST_AUDIO_SLOTS = 4;
static const uint32_t LOCALIST_AUDIO_RATE = 48000;
static const uint32_t LOCALIST_AUDIO_MAX_FRAMES = 960;
static const uint32_t LOCALIST_AUDIO_RESET = 1;
struct LocalistAudioHeader {
  uint32_t magic, version, slot, frames, sample_rate, channels, bits, flags;
};
struct LocalistAudioPacket {
  LocalistAudioHeader header;
  int16_t samples[LOCALIST_AUDIO_MAX_FRAMES];
};
static_assert(sizeof(LocalistAudioHeader) == 32, "Driver ABI must remain stable");
inline bool LocalistValidAudioPacket(const void* data, size_t length) {
  if (!data || length < sizeof(LocalistAudioHeader)) return false;
  const auto& h = *static_cast<const LocalistAudioHeader*>(data);
  if (h.magic != LOCALIST_AUDIO_MAGIC || h.version != LOCALIST_AUDIO_ABI ||
      h.slot >= LOCALIST_AUDIO_SLOTS || h.sample_rate != LOCALIST_AUDIO_RATE ||
      h.channels != 1 || h.bits != 16 || h.frames > LOCALIST_AUDIO_MAX_FRAMES ||
      h.flags > LOCALIST_AUDIO_RESET) return false;
  if (h.flags == LOCALIST_AUDIO_RESET && h.frames != 0) return false;
  if (!h.flags && h.frames == 0) return false;
  return length == sizeof(h) + h.frames * sizeof(int16_t);
}
// FILE_DEVICE_UNKNOWN, METHOD_BUFFERED, FILE_WRITE_DATA. Device ACL is admin/SYSTEM.
static const uint32_t LOCALIST_AUDIO_WRITE_IOCTL = (0x22u << 16) | (2u << 14) | (0xb00u << 2);
