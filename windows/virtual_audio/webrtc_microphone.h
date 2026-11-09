#pragma once
#include <stdint.h>
#include <string>
#include "rtc_audio_track.h"
#include "rtc_audio_device.h"
#include "rtc_audio_processing.h"
#include "cable_output.h"
#include <functional>
void LocalistPrepareCaptureAudio(libwebrtc::scoped_refptr<libwebrtc::RTCAudioDevice> device,
    libwebrtc::scoped_refptr<libwebrtc::RTCAudioProcessing> processing,
    std::function<void(const std::vector<uint8_t>&)> pcm);
void LocalistConfigureCaptureAudio(double gainDb,bool pcm);
void LocalistProcessLoopbackAudio(int16_t* data,int rate,int channels,size_t frames);
std::string LocalistCapturePlayoutEndpoint();
bool LocalistMicrophoneSetTrack(int slot,libwebrtc::scoped_refptr<libwebrtc::RTCAudioTrack> track, const std::string& endpoint = "", const LocalistAudioRenderOptions& options = {});
bool LocalistMicrophonePcm(int slot,const std::vector<uint8_t>& bytes);
LocalistAudioQueueStatus LocalistMicrophoneQueue(int slot);
std::string LocalistMicrophoneName(int slot);
void LocalistMicrophonesStop();
uint64_t LocalistMicrophoneFrames(int slot);
unsigned long LocalistMicrophoneError(int slot);
