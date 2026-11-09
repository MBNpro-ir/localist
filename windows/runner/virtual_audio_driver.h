#pragma once
#include <string>
struct LocalistMicrophoneStatus {
  bool installed = false;
  bool available = false;
  unsigned long error = 0;
};
LocalistMicrophoneStatus GetLocalistMicrophoneStatus();
bool InstallLocalistMicrophones(const std::wstring& directory);
bool RemoveLocalistMicrophones(const std::wstring& directory);
