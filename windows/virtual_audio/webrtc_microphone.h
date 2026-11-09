#pragma once
#include <stdint.h>
#include "rtc_audio_track.h"
bool LocalistMicrophoneSetTrack(int slot,libwebrtc::scoped_refptr<libwebrtc::RTCAudioTrack> track);
void LocalistMicrophonesStop();
uint64_t LocalistMicrophoneFrames(int slot);
unsigned long LocalistMicrophoneError(int slot);
