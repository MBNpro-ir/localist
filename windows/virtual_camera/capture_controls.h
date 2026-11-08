#pragma once
#include <windows.h>
#include <dshow.h>
#include <cstdint>

inline const CLSID CLSID_LocalistControls = {0xcc7c10e5,0x899c,0x4b6a,{0xad,0x0a,0x8d,0x04,0x3e,0x7c,0x2f,0x91}};
struct LocalistCaptureState {
  int persian = 0;
  int enabled = 0, width = 640, height = 480, fps = 30, bitrate = 2500;
  int noise = 1, echo = 1, gain = 1, zoom = 100, max_zoom = 100;
  int torch_available = 0, torch = 0, microphone = -1, microphones = 0;
  wchar_t microphone_names[12][128] = {};
  wchar_t message[256] = {};
};
bool PublishLocalistCaptureState(const LocalistCaptureState& state);
bool ReadLocalistCaptureState(LocalistCaptureState& state);
bool SubmitLocalistCaptureCommand(const char* json);
bool TakeLocalistCaptureCommand(char* json, size_t size);
HRESULT CreateLocalistControlsPage(REFIID iid, void** out);
