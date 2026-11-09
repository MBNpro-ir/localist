#pragma once
#include <stdint.h>
#include <string>
#include "rtc_audio_track.h"
bool LocalistMicrophoneSetTrack(int slot,libwebrtc::scoped_refptr<libwebrtc::RTCAudioTrack> track, const std::string& endpoint = "");
std::string LocalistMicrophoneName(int slot);
void LocalistMicrophonesStop();
uint64_t LocalistMicrophoneFrames(int slot);
unsigned long LocalistMicrophoneError(int slot);
