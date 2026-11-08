#include "virtual_devices.h"
#include <windows.h>
#include <shellapi.h>
#include <bcrypt.h>
#include <wintrust.h>
#include <softpub.h>
#include <vector>

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
bool Register(const std::wstring& dll, bool x64, bool install) {
  wchar_t windows[32768] = {};
  if (!GetWindowsDirectoryW(windows, 32768)) return false;
  const std::wstring executable = std::wstring(windows) + (x64 ? L"\\System32\\regsvr32.exe" : L"\\SysWOW64\\regsvr32.exe");
  const std::wstring command = L"\"" + executable + L"\" /s " + (install ? L"" : L"/u ") + L"\"" + dll + L"\"";
  std::vector<wchar_t> arguments(command.begin(), command.end()); arguments.push_back(0);
  STARTUPINFOW startup{}; startup.cb = sizeof(startup);
  PROCESS_INFORMATION process{};
  if (!CreateProcessW(executable.c_str(), arguments.data(), nullptr, nullptr, FALSE,
      CREATE_NO_WINDOW, nullptr, nullptr, &startup, &process)) return false;
  const DWORD wait = WaitForSingleObject(process.hProcess, 30000);
  DWORD result = 1;
  if (wait == WAIT_OBJECT_0) GetExitCodeProcess(process.hProcess, &result);
  CloseHandle(process.hThread); CloseHandle(process.hProcess);
  return wait == WAIT_OBJECT_0 && result == 0;
}
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
bool ConfigureLocalistCamera(const std::wstring& directory, bool install, int slot) {
  if (slot < 0 || slot >= 4) return false;
  if (install && IsLocalistCameraInstalled(directory, slot)) return true;
  bool success = true;
  for (bool x64 : {true, false}) {
    const auto dll = directory + L"\\" + LocalistCameraFileName(x64, slot);
    // An old portable copy must never uninstall the active copy's registration.
    if (!install && _wcsicmp(RegisteredPath(x64, slot).c_str(), dll.c_str()) != 0) continue;
    const DWORD attributes = GetFileAttributesW(dll.c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES || (attributes & FILE_ATTRIBUTE_DIRECTORY)) { success = false; continue; }
    if (!Register(dll, x64, install)) success = false;
  }
  return success && (!install || IsLocalistCameraInstalled(directory, slot));
}

bool LaunchSignedMicrophoneInstaller(const std::wstring& path) {
  // Pin both vendor package (Dart) and executable (native). Hold a non-writable
  // handle through verification/launch so another process cannot replace it.
  HANDLE file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, 0, nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  LARGE_INTEGER size{};
  bool valid = GetFileSizeEx(file, &size) && size.QuadPart > 0 && size.QuadPart <= 4 * 1024 * 1024;
  std::vector<BYTE> data(valid ? static_cast<size_t>(size.QuadPart) : 0);
  DWORD read = 0;
  if (valid) valid = ReadFile(file, data.data(), static_cast<DWORD>(data.size()), &read, nullptr) && read == data.size();
  BCRYPT_ALG_HANDLE algorithm = nullptr;
  BYTE digest[32] = {};
  if (valid) valid = BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, 0) == 0;
  if (valid) valid = BCryptHash(algorithm, nullptr, 0, data.data(), static_cast<ULONG>(data.size()), digest, sizeof(digest)) == 0;
  if (algorithm) BCryptCloseAlgorithmProvider(algorithm, 0);
  const BYTE expected[] = {0x73,0x4c,0x35,0xdf,0xa6,0xd9,0x8f,0x48,0x78,0x2a,0x45,0x16,0x33,0xce,0xb4,0x71,0x16,0x6e,0xc7,0x0d,0x60,0x48,0x2f,0xd8,0x9a,0x11,0x23,0xd0,0xee,0x3c,0x4f,0x41};
  valid = valid && memcmp(digest, expected, sizeof(digest)) == 0;
  if (valid) {
    SetFilePointer(file, 0, nullptr, FILE_BEGIN);
    WINTRUST_FILE_INFO info{}; info.cbStruct = sizeof(info); info.pcwszFilePath = path.c_str(); info.hFile = file;
    WINTRUST_DATA trust{}; trust.cbStruct = sizeof(trust); trust.dwUIChoice = WTD_UI_NONE;
    trust.dwUnionChoice = WTD_CHOICE_FILE; trust.pFile = &info;
    trust.dwStateAction = WTD_STATEACTION_VERIFY;
    GUID policy = WINTRUST_ACTION_GENERIC_VERIFY_V2;
    valid = WinVerifyTrust(nullptr, &policy, &trust) == ERROR_SUCCESS;
    trust.dwStateAction = WTD_STATEACTION_CLOSE;
    WinVerifyTrust(nullptr, &policy, &trust);
  }
  if (valid) {
    const auto directory = path.substr(0, path.find_last_of(L"\\/"));
    valid = reinterpret_cast<INT_PTR>(ShellExecuteW(nullptr, L"open", path.c_str(), nullptr, directory.c_str(), SW_SHOWNORMAL)) > 32;
  }
  CloseHandle(file);
  return valid;
}
