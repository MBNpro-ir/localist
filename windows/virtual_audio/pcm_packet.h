#pragma once
#include <cstdint>
#include <cstring>
#include <vector>
#pragma pack(push,1)
struct LocalistNetworkPcmHeader {
  uint32_t magic=0x4143504c;
  uint16_t version=1, channels=1;
  uint32_t rate=48000, frames=0, sequence=0;
};
#pragma pack(pop)
static_assert(sizeof(LocalistNetworkPcmHeader)==20,"PCM wire ABI");
inline bool ReadLocalistNetworkPcm(const uint8_t* data,size_t size,LocalistNetworkPcmHeader& header) {
  if(!data||size<sizeof(header)||size>3860)return false;
  std::memcpy(&header,data,sizeof(header));
  return header.magic==0x4143504c&&header.version==1&&header.channels==1&&
    header.rate>=8000&&header.rate<=48000&&header.frames>0&&header.frames<=header.rate/25&&
    size==sizeof(header)+header.frames*sizeof(int16_t);
}
