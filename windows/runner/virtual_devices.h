#pragma once
#include <string>
bool IsLocalistCameraInstalled(const std::wstring& directory);
bool ConfigureLocalistCamera(const std::wstring& directory, bool install);
bool LaunchSignedMicrophoneInstaller(const std::wstring& path);
std::wstring LocalistCameraFileName(bool x64);
