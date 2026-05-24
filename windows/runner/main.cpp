#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <cctype>
#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <exception>
#include <sstream>
#include <string>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

namespace {

constexpr const wchar_t kSingleInstanceMutexName[] =
    L"Local\\PRS.Localist.SingleInstance";
constexpr const wchar_t kDebugLogFileName[] = L"debug.log";
constexpr const wchar_t kRunMarkerFileName[] = L"localist-running.marker";
constexpr const char kDebugPreferenceKey[] = "\"flutter.debug.activeMode\"";

bool IsAnotherInstanceRunning(HANDLE mutex) {
  if (mutex == nullptr) {
    return ::GetLastError() == ERROR_ACCESS_DENIED;
  }
  return ::GetLastError() == ERROR_ALREADY_EXISTS;
}

void ShowAlreadyRunningMessage() {
  ::MessageBoxW(nullptr, L"Localist is already open.", L"Localist",
                MB_OK | MB_ICONINFORMATION | MB_SETFOREGROUND);
}

std::wstring ModulePath() {
  std::vector<wchar_t> buffer(MAX_PATH);
  DWORD length = 0;
  while (true) {
    length = ::GetModuleFileNameW(nullptr, buffer.data(),
                                  static_cast<DWORD>(buffer.size()));
    if (length == 0) {
      return L"";
    }
    if (length < buffer.size() - 1) {
      return std::wstring(buffer.data(), length);
    }
    buffer.resize(buffer.size() * 2);
  }
}

std::wstring ParentDirectory(const std::wstring& path) {
  const size_t slash = path.find_last_of(L"\\/");
  if (slash == std::wstring::npos) {
    return L"";
  }
  if (slash <= 2) {
    return path.substr(0, slash + 1);
  }
  return path.substr(0, slash);
}

std::wstring JoinPath(const std::wstring& directory,
                      const std::wstring& name) {
  if (directory.empty()) {
    return name;
  }
  const wchar_t last = directory.back();
  if (last == L'\\' || last == L'/') {
    return directory + name;
  }
  return directory + L"\\" + name;
}

std::wstring ExeDirectory() {
  return ParentDirectory(ModulePath());
}

std::wstring DebugLogPath() {
  return JoinPath(ExeDirectory(), kDebugLogFileName);
}

std::wstring RunMarkerPath() {
  return JoinPath(ExeDirectory(), kRunMarkerFileName);
}

std::string WideToUtf8(const std::wstring& value) {
  return Utf8FromUtf16(value.c_str());
}

std::string Timestamp() {
  SYSTEMTIME time{};
  ::GetLocalTime(&time);
  char buffer[64];
  sprintf_s(buffer, "%04u-%02u-%02uT%02u:%02u:%02u.%03u",
            time.wYear, time.wMonth, time.wDay, time.wHour, time.wMinute,
            time.wSecond, time.wMilliseconds);
  return buffer;
}

std::string LastErrorText(DWORD error) {
  if (error == 0) {
    return "none";
  }
  std::ostringstream stream;
  stream << "0x" << std::hex << error;
  return stream.str();
}

bool ReadTextFile(const std::wstring& path, std::string* output) {
  FILE* file = nullptr;
  if (_wfopen_s(&file, path.c_str(), L"rb") != 0 || file == nullptr) {
    return false;
  }
  fseek(file, 0, SEEK_END);
  const long size = ftell(file);
  rewind(file);
  output->clear();
  if (size > 0) {
    output->resize(static_cast<size_t>(size));
    fread(output->data(), 1, static_cast<size_t>(size), file);
  }
  fclose(file);
  return true;
}

bool WriteTextFile(const std::wstring& path, const std::string& text) {
  FILE* file = nullptr;
  if (_wfopen_s(&file, path.c_str(), L"wb") != 0 || file == nullptr) {
    return false;
  }
  fwrite(text.data(), 1, text.size(), file);
  fclose(file);
  return true;
}

void AppendTextFile(const std::wstring& path, const std::string& text) {
  FILE* file = nullptr;
  if (_wfopen_s(&file, path.c_str(), L"ab") != 0 || file == nullptr) {
    return;
  }
  fwrite(text.data(), 1, text.size(), file);
  fclose(file);
}

bool DirectoryExists(const std::wstring& path) {
  const DWORD attributes = ::GetFileAttributesW(path.c_str());
  return attributes != INVALID_FILE_ATTRIBUTES &&
         (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
}

void EnsureDirectory(const std::wstring& path) {
  if (path.empty() || DirectoryExists(path)) {
    return;
  }
  const std::wstring parent = ParentDirectory(path);
  if (!parent.empty() && parent != path) {
    EnsureDirectory(parent);
  }
  ::CreateDirectoryW(path.c_str(), nullptr);
}

std::wstring EnvironmentVariable(const wchar_t* name) {
  const DWORD size = ::GetEnvironmentVariableW(name, nullptr, 0);
  if (size == 0) {
    return L"";
  }
  std::wstring value(size, L'\0');
  const DWORD written = ::GetEnvironmentVariableW(name, value.data(), size);
  if (written == 0) {
    return L"";
  }
  value.resize(written);
  return value;
}

std::wstring CurrentDirectory() {
  const DWORD size = ::GetCurrentDirectoryW(0, nullptr);
  if (size == 0) {
    return L"";
  }
  std::wstring value(size, L'\0');
  const DWORD written =
      ::GetCurrentDirectoryW(static_cast<DWORD>(value.size()), value.data());
  if (written == 0) {
    return L"";
  }
  value.resize(written);
  return value;
}

std::wstring PreferencesPath() {
  const std::wstring app_data = EnvironmentVariable(L"APPDATA");
  if (app_data.empty()) {
    return L"";
  }
  return JoinPath(JoinPath(JoinPath(app_data, L"PRS"), L"Localist"),
                  L"shared_preferences.json");
}

bool IsDebugPreferenceEnabled() {
  std::string preferences;
  if (!ReadTextFile(PreferencesPath(), &preferences)) {
    return false;
  }
  const size_t key = preferences.find(kDebugPreferenceKey);
  if (key == std::string::npos) {
    return false;
  }
  const size_t colon = preferences.find(':', key);
  if (colon == std::string::npos) {
    return false;
  }
  size_t value = colon + 1;
  while (value < preferences.size() &&
         isspace(static_cast<unsigned char>(preferences[value]))) {
    ++value;
  }
  return preferences.compare(value, 4, "true") == 0;
}

void SetDebugPreferenceEnabled(bool enabled) {
  const std::wstring path = PreferencesPath();
  if (path.empty()) {
    return;
  }
  EnsureDirectory(ParentDirectory(path));
  std::string preferences;
  if (!ReadTextFile(path, &preferences) || preferences.empty()) {
    preferences = "{}";
  }
  const std::string replacement = enabled ? "true" : "false";
  const size_t key = preferences.find(kDebugPreferenceKey);
  if (key == std::string::npos) {
    const size_t brace = preferences.rfind('}');
    if (brace == std::string::npos) {
      preferences = std::string("{") + kDebugPreferenceKey + ":" +
                    replacement + "}";
    } else {
      const bool has_values = preferences.find(':') != std::string::npos;
      preferences.insert(brace, std::string(has_values ? "," : "") +
                                    kDebugPreferenceKey + ":" + replacement);
    }
  } else {
    const size_t colon = preferences.find(':', key);
    if (colon != std::string::npos) {
      size_t value_start = colon + 1;
      while (value_start < preferences.size() &&
             isspace(static_cast<unsigned char>(preferences[value_start]))) {
        ++value_start;
      }
      size_t value_end = value_start;
      while (value_end < preferences.size() &&
             isalpha(static_cast<unsigned char>(preferences[value_end]))) {
        ++value_end;
      }
      preferences.replace(value_start, value_end - value_start, replacement);
    }
  }
  WriteTextFile(path, preferences);
}

void AppendNativeDebugLog(const std::string& message) {
  AppendTextFile(DebugLogPath(),
                 "[" + Timestamp() + "] Native: " + message + "\r\n");
}

std::string ArchitectureName() {
  SYSTEM_INFO info{};
  ::GetNativeSystemInfo(&info);
  switch (info.wProcessorArchitecture) {
    case PROCESSOR_ARCHITECTURE_AMD64:
      return "x64";
    case PROCESSOR_ARCHITECTURE_ARM64:
      return "arm64";
    case PROCESSOR_ARCHITECTURE_INTEL:
      return "x86";
    case PROCESSOR_ARCHITECTURE_ARM:
      return "arm";
    default:
      return "unknown";
  }
}

void AppendBootDiagnostics() {
  std::ostringstream stream;
  stream << "Process start pid=" << ::GetCurrentProcessId()
         << " exe=" << WideToUtf8(ModulePath())
         << " cwd=" << WideToUtf8(CurrentDirectory())
         << " arch=" << ArchitectureName()
         << " appData=" << WideToUtf8(EnvironmentVariable(L"APPDATA"))
         << " prefs=" << WideToUtf8(PreferencesPath())
         << " commandLine=" << WideToUtf8(::GetCommandLineW());
  AppendNativeDebugLog(stream.str());
}

struct RunMarker {
  bool exists = false;
  bool debug_at_start = false;
  std::string text;
};

RunMarker ReadRunMarker() {
  RunMarker marker;
  marker.exists = ReadTextFile(RunMarkerPath(), &marker.text);
  marker.debug_at_start =
      marker.text.find("debugAtStart=1") != std::string::npos;
  return marker;
}

void WriteRunMarker(bool debug_at_start) {
  std::ostringstream stream;
  stream << "startedAt=" << Timestamp() << "\n"
         << "pid=" << ::GetCurrentProcessId() << "\n"
         << "debugAtStart=" << (debug_at_start ? "1" : "0") << "\n"
         << "exe=" << WideToUtf8(ModulePath()) << "\n";
  WriteTextFile(RunMarkerPath(), stream.str());
}

void DeleteRunMarker() {
  ::DeleteFileW(RunMarkerPath().c_str());
}

void ShowCrashDebugEnabledMessage() {
  ::MessageBoxW(
      nullptr,
      L"Localist crashed during the previous run.\n\n"
      L"Debug mode was enabled automatically.\n"
      L"Open Localist again so startup logs are saved as debug.log next to "
      L"Localist.exe.",
      L"Localist crash detected",
      MB_OK | MB_ICONWARNING | MB_SETFOREGROUND);
}

void ShowCrashLogSavedMessage() {
  const std::wstring message =
      L"Localist crashed while debug mode was active.\n\n"
      L"The debug log was saved here:\n" +
      DebugLogPath() +
      L"\n\nSend debug.log to the developer so the crash can be traced.";
  ::MessageBoxW(nullptr, message.c_str(), L"Localist debug log saved",
                MB_OK | MB_ICONWARNING | MB_SETFOREGROUND);
}

void HandlePreviousAbnormalExit(bool* debug_preference_enabled) {
  const RunMarker marker = ReadRunMarker();
  if (!marker.exists) {
    return;
  }
  if (marker.debug_at_start || *debug_preference_enabled) {
    AppendNativeDebugLog(
        "Previous run ended abnormally while debug mode was active.");
    ShowCrashLogSavedMessage();
    return;
  }
  SetDebugPreferenceEnabled(true);
  *debug_preference_enabled = true;
  AppendNativeDebugLog(
      "Previous run ended abnormally. Debug mode was enabled automatically.");
  ShowCrashDebugEnabledMessage();
}

LONG WINAPI HandleUnhandledException(EXCEPTION_POINTERS* exception_info) {
  std::ostringstream stream;
  stream << "Unhandled SEH exception";
  if (exception_info != nullptr && exception_info->ExceptionRecord != nullptr) {
    stream << " code=0x" << std::hex
           << exception_info->ExceptionRecord->ExceptionCode
           << " address=" << exception_info->ExceptionRecord->ExceptionAddress;
  }
  AppendNativeDebugLog(stream.str());
  return EXCEPTION_EXECUTE_HANDLER;
}

void HandleTerminate() {
  AppendNativeDebugLog("std::terminate called.");
  std::abort();
}

void HandleSignal(int signal) {
  std::ostringstream stream;
  stream << "Process signal received signal=" << signal;
  AppendNativeDebugLog(stream.str());
  std::_Exit(EXIT_FAILURE);
}

void InstallCrashHandlers() {
  ::SetUnhandledExceptionFilter(HandleUnhandledException);
  std::set_terminate(HandleTerminate);
  std::signal(SIGABRT, HandleSignal);
  std::signal(SIGSEGV, HandleSignal);
  std::signal(SIGILL, HandleSignal);
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  HANDLE single_instance_mutex =
      ::CreateMutexW(nullptr, TRUE, kSingleInstanceMutexName);
  if (IsAnotherInstanceRunning(single_instance_mutex)) {
    ShowAlreadyRunningMessage();
    if (single_instance_mutex != nullptr) {
      ::CloseHandle(single_instance_mutex);
    }
    return EXIT_SUCCESS;
  }

  bool debug_preference_enabled = IsDebugPreferenceEnabled();
  HandlePreviousAbnormalExit(&debug_preference_enabled);
  if (debug_preference_enabled) {
    AppendBootDiagnostics();
  }
  WriteRunMarker(debug_preference_enabled);
  InstallCrashHandlers();

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  const HRESULT com_result = ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  const bool com_initialized = SUCCEEDED(com_result);
  if (debug_preference_enabled) {
    std::ostringstream stream;
    stream << "CoInitializeEx result=0x" << std::hex << com_result
           << " lastError=" << LastErrorText(::GetLastError());
    AppendNativeDebugLog(stream.str());
  }

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments = GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(440, 680);
  if (!window.Create(L"Localist", origin, size)) {
    AppendNativeDebugLog("Flutter window creation failed.");
    SetDebugPreferenceEnabled(true);
    ShowCrashDebugEnabledMessage();
    if (com_initialized) {
      ::CoUninitialize();
    }
    if (single_instance_mutex != nullptr) {
      ::CloseHandle(single_instance_mutex);
    }
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  if (debug_preference_enabled) {
    AppendNativeDebugLog("Process exited normally.");
  }
  DeleteRunMarker();
  if (com_initialized) {
    ::CoUninitialize();
  }
  if (single_instance_mutex != nullptr) {
    ::CloseHandle(single_instance_mutex);
  }
  return EXIT_SUCCESS;
}
