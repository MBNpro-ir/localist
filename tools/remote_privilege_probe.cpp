// Isolated, windowless native bootstrap probe. No connection or password changes.
#include <windows.h>
#include <tlhelp32.h>
#include <fstream>
#include <string>
#include <vector>

bool Elevated() {
  HANDLE token = nullptr; TOKEN_ELEVATION elevation{}; DWORD size = sizeof(elevation);
  const bool ok = OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token) &&
      GetTokenInformation(token, TokenElevation, &elevation, size, &size) && elevation.TokenIsElevated;
  if (token) CloseHandle(token);
  return ok;
}

bool SystemProcess(HANDLE process) {
  HANDLE token = nullptr; DWORD size = 0;
  if (!OpenProcessToken(process, TOKEN_QUERY, &token)) return false;
  GetTokenInformation(token, TokenUser, nullptr, 0, &size);
  std::vector<BYTE> bytes(size);
  const bool system = GetTokenInformation(token, TokenUser, bytes.data(), size, &size) &&
      IsWellKnownSid(reinterpret_cast<TOKEN_USER*>(bytes.data())->User.Sid, WinLocalSystemSid);
  CloseHandle(token);
  return system;
}

HANDLE FindOwnSystemHelper(const std::wstring& image) {
  HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snapshot == INVALID_HANDLE_VALUE) return nullptr;
  PROCESSENTRY32W entry{sizeof(entry)}; HANDLE result = nullptr;
  if (Process32FirstW(snapshot, &entry)) do {
    if (entry.th32ProcessID == GetCurrentProcessId() || _wcsicmp(entry.szExeFile, L"LocalistRemote.exe")) continue;
    HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE | PROCESS_TERMINATE, FALSE, entry.th32ProcessID);
    if (!process) continue;
    wchar_t path[32768] = {}; DWORD length = 32768;
    if (QueryFullProcessImageNameW(process, 0, path, &length) && !_wcsicmp(path, image.c_str()) && SystemProcess(process)) {
      result = process; break;
    }
    CloseHandle(process);
  } while (Process32NextW(snapshot, &entry));
  CloseHandle(snapshot);
  return result;
}

int wmain(int argc, wchar_t** argv) {
  wchar_t own_path[32768] = {}, report_path[32768] = {};
  GetModuleFileNameW(nullptr, own_path, 32768);
  const std::wstring image(own_path), directory = image.substr(0, image.find_last_of(L"\\/"));
  const bool probe = argc > 1 && (std::wstring(argv[1]) == L"--noinstall" || std::wstring(argv[1]) == L"--localist-host");
  const bool elevated = Elevated();
  if (probe && !elevated) return 5; // Never trigger a UAC flow from an unelevated test.
  SetCurrentDirectoryW(directory.c_str());
  HMODULE library = LoadLibraryW((directory + L"\\librustdesk.dll").c_str());
  if (!library) return 2;
  using Core = char** (*)(int*); using Free = void (*)(char**, int);
  const auto core = reinterpret_cast<Core>(GetProcAddress(library, "rustdesk_core_main_args"));
  const auto free_args = reinterpret_cast<Free>(GetProcAddress(library, "free_c_args"));
  if (!core || !free_args) return 3;
  int count = 0; char** arguments = core(&count);
  if (!arguments) return 0; // Upstream handles the SYSTEM helper's entire lifecycle.
  free_args(arguments, count);
  if (!probe || !GetEnvironmentVariableW(L"LOCALIST_PRIVILEGE_REPORT", report_path, 32768)) return 4;
  HANDLE helper = nullptr;
  const bool expected = std::wstring(argv[1]) == L"--noinstall";
  for (int i = 0; i < (expected ? 100 : 20); ++i) {
    helper = FindOwnSystemHelper(image);
    if (helper) break;
    Sleep(150);
  }
  // Authentication failures exit the helper early. Require it to remain alive.
  const bool stable_system = helper && WaitForSingleObject(helper, 6000) == WAIT_TIMEOUT;
  bool cleaned = true;
  if (helper) {
    cleaned = TerminateProcess(helper, 0) && WaitForSingleObject(helper, 3000) == WAIT_OBJECT_0;
    CloseHandle(helper);
  }
  std::ofstream report(report_path);
  report << "{\"elevated\":" << (elevated ? "true" : "false")
         << ",\"systemHelperStable\":" << (stable_system ? "true" : "false")
         << ",\"ownHelperStopped\":" << (cleaned ? "true" : "false") << "}";
  return stable_system == expected && cleaned ? 0 : 6;
}
