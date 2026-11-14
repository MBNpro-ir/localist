#include "virtual_devices.h"
#include <windows.h>
#include <shellapi.h>
#include <vector>
#include <filesystem>

namespace {
std::wstring CameraKey(int slot) {
  wchar_t key[160];
  swprintf_s(key, L"Software\\Classes\\CLSID\\{58BC%04X-E9D9-4BB9-A460-6630C82A5301}\\InprocServer32", 0x2225 + slot);
  return key;
}
std::wstring RegisteredPath(bool x64, int slot) {
  HKEY key = nullptr;
  if (RegOpenKeyExW(HKEY_LOCAL_MACHINE, CameraKey(slot).c_str(), 0, KEY_QUERY_VALUE |
      (x64 ? KEY_WOW64_64KEY : KEY_WOW64_32KEY), &key) != ERROR_SUCCESS) return {};
  wchar_t path[32768] = {}; DWORD size = sizeof(path);
  const auto status = RegQueryValueExW(key, nullptr, nullptr, nullptr, reinterpret_cast<BYTE*>(path), &size);
  RegCloseKey(key);
  return status == ERROR_SUCCESS ? path : L"";
}
bool RunHidden(const std::wstring& executable, const std::wstring& parameters) {
  const std::wstring command = L"\"" + executable + L"\" " + parameters;
  std::vector<wchar_t> arguments(command.begin(), command.end()); arguments.push_back(0);
  STARTUPINFOW startup{}; startup.cb = sizeof(startup);
  PROCESS_INFORMATION process{};
  if (!CreateProcessW(executable.c_str(), arguments.data(), nullptr, nullptr, FALSE,
      CREATE_NO_WINDOW, nullptr, nullptr, &startup, &process)) return false;
  const DWORD wait = WaitForSingleObject(process.hProcess, 30000);
  DWORD result = 1;
  if (wait == WAIT_OBJECT_0) GetExitCodeProcess(process.hProcess, &result);
  else if (wait == WAIT_TIMEOUT) {
    TerminateProcess(process.hProcess, 1);
    WaitForSingleObject(process.hProcess, 5000);
  }
  CloseHandle(process.hThread); CloseHandle(process.hProcess);
  return wait == WAIT_OBJECT_0 && result == 0;
}
bool Register(const std::wstring& dll, bool x64, bool install) {
  wchar_t windows[32768] = {};
  if (!GetWindowsDirectoryW(windows, 32768)) return false;
  const std::wstring executable = std::wstring(windows) + (x64 ? L"\\System32\\regsvr32.exe" : L"\\SysWOW64\\regsvr32.exe");
  return RunHidden(executable, L"/s " + std::wstring(install ? L"" : L"/u ") + L"\"" + dll + L"\"");
}
}
bool ConfigureLocalistLanAccess(const std::wstring& directory, bool install) {
  wchar_t windows[32768] = {};
  if (!GetWindowsDirectoryW(windows, 32768)) return false;
  const auto executable = std::wstring(windows) + L"\\System32\\netsh.exe";
  const auto selector = L" name=\"Localist LAN\" program=\"" + directory + L"\\Localist.exe\"";
  // Scope the rule to this executable and local subnets, also on USB networks
  // Windows classifies as Public. Never disable or reconfigure the firewall.
  RunHidden(executable, L"advfirewall firewall delete rule" + selector);
  return !install || RunHidden(executable, L"advfirewall firewall add rule" + selector +
      L" dir=in action=allow enable=yes profile=any protocol=any remoteip=localsubnet");
}
std::wstring LocalistCameraFileName(bool x64, int slot) {
  return std::wstring(x64 ? L"LocalistCamera64" : L"LocalistCamera32") + (slot > 0 ? L"-" + std::to_wstring(slot + 1) : L"") + L"-" + LOCALIST_CAMERA_VERSION + L".dll";
}
bool IsLocalistCameraInstalled(const std::wstring& directory, int slot) {
  if (slot < 0 || slot >= 4) return false;
  for (bool x64 : {true, false}) {
    const auto expected = directory + L"\\" + LocalistCameraFileName(x64, slot);
    if (_wcsicmp(RegisteredPath(x64, slot).c_str(), expected.c_str()) != 0) return false;
  }
  return true;
}
int InstalledLocalistCameraCount(const std::wstring& directory) {
  int count = 0;
  // Migration from older installs may have no capture-devices.ini. Keep every
  // registered slot owned by this installation, regardless of DLL version.
  for (int slot = 0; slot < 4; ++slot) {
    for (bool x64 : {true, false}) {
      const auto path = std::filesystem::path(RegisteredPath(x64, slot));
      if (!path.empty() && _wcsicmp(path.parent_path().c_str(), directory.c_str()) == 0)
        count = slot + 1;
    }
  }
  return count;
}
bool ConfigureLocalistCamera(const std::wstring& directory, bool install, int slot) {
  if (slot < 0 || slot >= 4) return false;
  if (install && IsLocalistCameraInstalled(directory, slot)) return true;
  bool success = true;
  for (bool x64 : {true, false}) {
    auto dll = directory + L"\\" + LocalistCameraFileName(x64, slot);
    // An old portable copy must never uninstall the active copy's registration.
    if (!install) {
      const auto registered=RegisteredPath(x64,slot);
      const std::filesystem::path path(registered);
      const auto prefix=std::wstring(x64?L"LocalistCamera64":L"LocalistCamera32")+(slot>0?L"-"+std::to_wstring(slot+1):L"")+L"-";
      if(_wcsicmp(path.parent_path().c_str(),directory.c_str())!=0 || path.filename().wstring().rfind(prefix,0)!=0)continue;
      dll=registered;
    }
    const DWORD attributes = GetFileAttributesW(dll.c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES || (attributes & FILE_ATTRIBUTE_DIRECTORY)) { success = false; continue; }
    if (!Register(dll, x64, install)) success = false;
  }
  return success && (!install || IsLocalistCameraInstalled(directory, slot));
}
bool InstallLocalistCameras(const std::wstring& directory, int count) {
  if (count < 1 || count > 4) return false;
  std::vector<std::wstring> previous;
  for (int slot = 0; slot < 4; ++slot)
    for (bool x64 : {true, false}) previous.push_back(RegisteredPath(x64, slot));
  for (int slot = 0; slot < count; ++slot) {
    if (ConfigureLocalistCamera(directory, true, slot)) continue;
    // Roll back only our camera identities if registration is incomplete.
    for (int restore = 0; restore < 4; ++restore) {
      ConfigureLocalistCamera(directory, false, restore);
      for (int arch = 0; arch < 2; ++arch) {
        const auto& path = previous[restore * 2 + arch];
        if (!path.empty() && GetFileAttributesW(path.c_str()) != INVALID_FILE_ATTRIBUTES)
          Register(path, arch == 0, true);
      }
    }
    return false;
  }
  for (int slot = count; slot < 4; ++slot)
    if (!ConfigureLocalistCamera(directory, false, slot)) return false;
  return true;
}
