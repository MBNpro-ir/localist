#include "embedded_remote.h"
#include <flutter/dart_project.h>
#include <shellapi.h>
#include <algorithm>
#include <string>
#include <vector>
#include "flutter_window.h"
#include "utils.h"

namespace {
std::wstring ExecutableDirectory() {
  wchar_t path[32768] = {};
  GetModuleFileNameW(nullptr, path, 32768);
  const std::wstring name(path);
  return name.substr(0, name.find_last_of(L"\\/"));
}
}

bool IsEmbeddedRemoteExecutable() {
  wchar_t path[32768] = {};
  GetModuleFileNameW(nullptr, path, 32768);
  const std::wstring name(path);
  return _wcsicmp(name.substr(name.find_last_of(L"\\/") + 1).c_str(), L"LocalistRemote.exe") == 0;
}

int RunEmbeddedRemote(HINSTANCE instance) {
  const auto directory = ExecutableDirectory();
  SetCurrentDirectoryW(directory.c_str());
  const auto command_arguments = GetCommandLineArguments();
  // This helper is not a second app entry point. An accidental double-click
  // opens Localist instead of the upstream desktop shell.
  if (command_arguments.empty()) {
    const auto app = directory + L"\\Localist.exe";
    return reinterpret_cast<INT_PTR>(ShellExecuteW(nullptr, L"open", app.c_str(),
        nullptr, directory.c_str(), SW_SHOWNORMAL)) > 32 ? EXIT_SUCCESS : EXIT_FAILURE;
  }
  // --noinstall is consumed by upstream before its elevated portable-service
  // bootstrap. A custom nonempty command skips that bootstrap. Keep the legacy
  // command accepted for existing callers, without treating service children
  // or individual session windows as the retained GUI host.
  const bool is_host = command_arguments.size() == 1 &&
      (command_arguments.front() == "--noinstall" ||
       command_arguments.front() == "--localist-host");
  HANDLE host_mutex = nullptr;
  if (is_host) {
    host_mutex = CreateMutexW(nullptr, TRUE, L"Local\\PRS.Localist.RemoteHost");
    if (host_mutex == nullptr || GetLastError() == ERROR_ALREADY_EXISTS) {
      if (host_mutex != nullptr) CloseHandle(host_mutex);
      return EXIT_SUCCESS;
    }
  }
  const HRESULT com = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  const auto library = LoadLibraryW((directory + L"\\librustdesk.dll").c_str());
  if (!library) {
    MessageBoxW(nullptr, L"The bundled Remote Control engine could not be loaded.", L"Localist", MB_ICONERROR);
    if (SUCCEEDED(com)) CoUninitialize();
    if (host_mutex != nullptr) CloseHandle(host_mutex);
    return EXIT_FAILURE;
  }
  using CoreMain = char** (*)(int*);
  using FreeArgs = void (*)(char**, int);
  const auto core = reinterpret_cast<CoreMain>(GetProcAddress(library, "rustdesk_core_main_args"));
  const auto free_args = reinterpret_cast<FreeArgs>(GetProcAddress(library, "free_c_args"));
  if (!core || !free_args) {
    if (host_mutex != nullptr) CloseHandle(host_mutex);
    return EXIT_FAILURE;
  }
  int count = 0;
  char** native_args = core(&count);
  // Service, CLI and session-dispatch commands are handled by the native core.
  if (!native_args) {
    if (host_mutex != nullptr) CloseHandle(host_mutex);
    if (SUCCEEDED(com)) CoUninitialize();
    return EXIT_SUCCESS;
  }
  auto arguments = command_arguments;
  arguments.insert(arguments.end(), native_args, native_args + count);
  free_args(native_args, count);
  flutter::DartProject project(directory + L"\\data");
  project.set_dart_entrypoint_arguments(std::move(arguments));
  FlutterWindow window(project, false);
  if (!window.Create(L"Localist Remote Control", Win32Window::Point(30, 30), Win32Window::Size(1050, 720))) {
    if (host_mutex != nullptr) CloseHandle(host_mutex);
    if (SUCCEEDED(com)) CoUninitialize();
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);
  MSG message;
  while (GetMessage(&message, nullptr, 0, 0)) { TranslateMessage(&message); DispatchMessage(&message); }
  if (host_mutex != nullptr) CloseHandle(host_mutex);
  if (SUCCEEDED(com)) CoUninitialize();
  return EXIT_SUCCESS;
}
