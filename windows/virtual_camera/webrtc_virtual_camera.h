#pragma once
#include <cstdint>
#include "rtc_video_frame.h"
void LocalistVirtualCameraFrame(int64_t texture, libwebrtc::scoped_refptr<libwebrtc::RTCVideoFrame> frame);
void LocalistVirtualCameraRelease(int64_t texture);
