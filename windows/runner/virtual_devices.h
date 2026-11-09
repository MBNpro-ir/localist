#pragma once
#include <string>
bool IsLocalistCameraInstalled(const std::wstring& directory, int slot = 0);
bool ConfigureLocalistCamera(const std::wstring& directory, bool install, int slot = 0);
bool InstallLocalistCameras(const std::wstring& directory);
bool ConfigureLocalistLanAccess(const std::wstring& directory, bool install);
bool LaunchSignedMicrophoneInstaller(const std::wstring& path);
std::wstring LocalistCameraFileName(bool x64, int slot = 0);
