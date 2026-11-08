#include <windows.h>
#include <taskschd.h>
#include <comdef.h>
#include <wrl/client.h>
#include <fstream>
#include <string>
#include "elevated_startup.h"
using Microsoft::WRL::ComPtr;

int wmain(int argc, wchar_t** argv) {
  wchar_t image[32768] = {};
  GetModuleFileNameW(nullptr, image, 32768);
  const std::wstring path(image);
  const auto marker = path.substr(0, path.find_last_of(L"\\/")) + L"\\startup-token.json";
  if (argc == 2 && std::wstring(argv[1]) == L"--startup") {
    std::ofstream output(marker.c_str());
    output << "{\"elevated\":" << (IsLocalistProcessElevated() ? "true" : "false") << "}";
    return IsLocalistProcessElevated() ? 0 : 1;
  }
  if (argc != 3 || std::wstring(argv[1]) != L"--exercise" || !IsLocalistProcessElevated()) return 2;
  const auto suffix = L"-QA-" + std::to_wstring(GetCurrentProcessId());
  DeleteFileW(marker.c_str());
  bool registered = false, token = false, repaired = false, removed = false;
  const HRESULT initialized = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  {
    ComPtr<ITaskService> service;
    ComPtr<ITaskFolder> folder;
    ComPtr<IRegisteredTaskCollection> tasks;
    ComPtr<IRegisteredTask> target;
    registered = ConfigureElevatedStartup(true, path, suffix);
    if (registered && SUCCEEDED(CoCreateInstance(CLSID_TaskScheduler, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(service.GetAddressOf()))) &&
        SUCCEEDED(service->Connect(_variant_t(), _variant_t(), _variant_t(), _variant_t())) &&
        SUCCEEDED(service->GetFolder(_bstr_t(L"\\"), folder.GetAddressOf())) &&
        SUCCEEDED(folder->GetTasks(TASK_ENUM_HIDDEN, tasks.GetAddressOf()))) {
      LONG count = 0; tasks->get_Count(&count);
      for (LONG i = 1; i <= count; ++i) {
        ComPtr<IRegisteredTask> task; BSTR name = nullptr;
        if (FAILED(tasks->get_Item(_variant_t(i), task.GetAddressOf())) || FAILED(task->get_Name(&name))) continue;
        const std::wstring value(name); SysFreeString(name);
        if (value.size() >= suffix.size() && value.substr(value.size() - suffix.size()) == suffix) { target = task; break; }
      }
      if (target) {
        ComPtr<IRunningTask> running;
        if (SUCCEEDED(target->Run(_variant_t(), running.GetAddressOf()))) {
          for (int i = 0; i < 100; ++i) {
            std::ifstream input(marker.c_str());
            std::string result((std::istreambuf_iterator<char>(input)), {});
            if (result.find("true") != std::string::npos) { token = true; break; }
            Sleep(100);
          }
        }
        if (SUCCEEDED(target->put_Enabled(VARIANT_FALSE)) && !IsElevatedStartupEnabled(path, suffix))
          repaired = ConfigureElevatedStartup(true, path, suffix) && IsElevatedStartupEnabled(path, suffix);
      }
    }
    removed = ConfigureElevatedStartup(false, path, suffix) && !IsElevatedStartupEnabled(path, suffix);
  }
  if (SUCCEEDED(initialized)) CoUninitialize();
  const bool success = registered && token && repaired && removed;
  std::ofstream report(argv[2]);
  report << "{\"registered\":" << (registered ? "true" : "false")
         << ",\"scheduledProcessElevated\":" << (token ? "true" : "false")
         << ",\"disabledTaskRepaired\":" << (repaired ? "true" : "false")
         << ",\"qaTaskRemoved\":" << (removed ? "true" : "false") << "}";
  return success ? 0 : 3;
}
