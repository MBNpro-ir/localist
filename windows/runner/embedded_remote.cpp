#include "embedded_remote.h"
#include <flutter/dart_project.h>
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
  const bool is_host = std::find(command_arguments.begin(), command_arguments.end(),
                                 "--localist-host") != command_arguments.end();
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
