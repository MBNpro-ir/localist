#pragma once
#include <stdint.h>
#include <stddef.h>

// Packetizer/downmixer used by native WebRTC sinks. No default-device changes.
class LocalistPcmConverter {
 public:
  void Reset() { phase_=0; previous_=0; ready_=false; rate_=0; }
  template<class Emit> bool Convert(const void* data,int bits,int rate,size_t channels,size_t frames,Emit emit) {
    if (!data || bits!=16 || rate<8000 || rate>48000 || channels<1 || channels>8 || frames>rate/5u) return false;
    if (rate_!=rate) { Reset(); rate_=rate; }
    const auto input=static_cast<const int16_t*>(data);
    for (size_t i=0;i<frames;++i) {
      int32_t sum=0;for (size_t c=0;c<channels;++c)sum+=input[i*channels+c];
      const int32_t mono=sum/static_cast<int32_t>(channels);
      if (!ready_) { previous_=mono;ready_=true; }
      phase_+=48000;
      while(phase_>=static_cast<uint32_t>(rate)) {
        const int64_t fraction=48000-(phase_-rate);
        emit(static_cast<int16_t>(previous_+(mono-previous_)*fraction/48000));
        phase_-=rate;
      }
      previous_=mono;
    }
    return true;
  }
 private:
  uint32_t phase_=0;
  int32_t previous_=0,rate_=0;
  bool ready_=false;
};
