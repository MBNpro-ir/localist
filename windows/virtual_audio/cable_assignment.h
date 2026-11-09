#pragma once
#include <algorithm>
#include <string>
#include <vector>

inline int SelectLocalistCable(const std::vector<std::string>& available,
    const std::vector<std::string>& occupied, const std::string& requested) {
  for(size_t i=0;i<available.size();++i) {
    if(available[i].empty() || (!requested.empty()&&available[i]!=requested))continue;
    if(std::find(occupied.begin(),occupied.end(),available[i])==occupied.end())return static_cast<int>(i);
  }
  return -1; // Never fall back to sharing an occupied cable or a physical speaker.
}
