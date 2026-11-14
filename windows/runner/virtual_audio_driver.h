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
bool InstallLocalistVbCable(const std::wstring& directory);
int InstalledLocalistCableCount();
bool InstallLocalistCableCount(const std::wstring& directory, int count, const std::wstring& extraPackages);
