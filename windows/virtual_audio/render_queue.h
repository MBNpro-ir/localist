#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <vector>

// Bounded, configurable jitter queue. Ownership/locking stays with the output.
class LocalistRenderQueue {
 public:
  void Configure(int minimum_ms, int maximum_ms, double gain_db) {
    const auto size = static_cast<size_t>(std::clamp(maximum_ms,10,1000))*48;
    samples_.assign(size,0); read_=count_=0;
    minimum_=static_cast<size_t>(std::clamp(minimum_ms,0,maximum_ms))*48;
    waiting_=minimum_>0; gain_=std::pow(10.0,std::clamp(gain_db,-30.0,40.0)/20.0);
    dropped_=underruns_=clipped_=0;
  }
  void Clear() { read_=count_=0; waiting_=minimum_>0; }
  void Push(const int16_t* data,size_t count) {
    if (!data||!count||samples_.empty())return;
    if(count>samples_.size()){dropped_+=count-samples_.size();data+=count-samples_.size();count=samples_.size();}
    if(count_+count>samples_.size()){
      const auto excess=count_+count-samples_.size();read_=(read_+excess)%samples_.size();count_-=excess;dropped_+=excess;
    }
    for(size_t i=0;i<count;++i){
      const double value=data[i]*gain_;
      if(value>32767||value< -32768)++clipped_;
      samples_[(read_+count_+i)%samples_.size()]=static_cast<int16_t>(std::clamp(value,-32768.0,32767.0));
    }
    count_+=count;
  }
  size_t Pull(int16_t* out,size_t frames){
    if(waiting_&&count_<minimum_){std::fill(out,out+frames,static_cast<int16_t>(0));return 0;}
    waiting_=false;
    const auto size=std::min(frames,count_);
    for(size_t i=0;i<size;++i)out[i]=samples_[(read_+i)%samples_.size()];
    std::fill(out+size,out+frames,static_cast<int16_t>(0));
    if(!samples_.empty())read_=(read_+size)%samples_.size();count_-=size;
    if(size<frames){++underruns_;waiting_=minimum_>0;}
    return size;
  }
  uint64_t Dropped()const{return dropped_;}
  uint64_t Underruns()const{return underruns_;}
  uint64_t Clipped()const{return clipped_;}
  size_t Buffered()const{return count_;}
 private:
  std::vector<int16_t> samples_;
  size_t read_=0,count_=0,minimum_=0;
  bool waiting_=false;
  double gain_=1;
  uint64_t dropped_=0,underruns_=0,clipped_=0;
};
