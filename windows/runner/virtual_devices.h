#pragma once
#include <string>
bool IsLocalistCameraInstalled(const std::wstring& directory, int slot = 0);
int InstalledLocalistCameraCount(const std::wstring& directory);
bool ConfigureLocalistCamera(const std::wstring& directory, bool install, int slot = 0);
bool InstallLocalistCameras(const std::wstring& directory, int count = 4);
bool ConfigureLocalistLanAccess(const std::wstring& directory, bool install);
std::wstring LocalistCameraFileName(bool x64, int slot = 0);
