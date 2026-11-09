#pragma once
#include <stdint.h>
#include <stddef.h>
#include <string.h>

// Caller serializes access. Fixed nonpaged storage, bounded work, no allocations.
struct LocalistPcmRing {
  static const size_t capacity = 4800; // 100ms, 48kHz mono.
  int16_t samples[capacity]{};
  size_t read = 0, count = 0;
  void Clear() { read = count = 0; memset(samples, 0, sizeof(samples)); }
  void Push(const int16_t* source, size_t frames) {
    if (!source || !frames) return;
    if (frames > capacity) { source += frames - capacity; frames = capacity; }
    if (count + frames > capacity) {
      const size_t discarded = count + frames - capacity;
      read = (read + discarded) % capacity; count -= discarded;
    }
    const size_t write = (read + count) % capacity;
    const size_t first = frames < capacity - write ? frames : capacity - write;
    memcpy(samples + write, source, first * sizeof(int16_t));
    memcpy(samples, source + first, (frames - first) * sizeof(int16_t));
    count += frames;
  }
  size_t Pull(int16_t* target, size_t frames) {
    const size_t available = frames < count ? frames : count;
    const size_t first = available < capacity - read ? available : capacity - read;
    memcpy(target, samples + read, first * sizeof(int16_t));
    memcpy(target + first, samples, (available - first) * sizeof(int16_t));
    memset(target + available, 0, (frames - available) * sizeof(int16_t));
    read = (read + available) % capacity; count -= available;
    return available;
  }
};
