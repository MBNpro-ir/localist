#include "elevated_startup.h"
#include <windows.h>
#include <sddl.h>
#include <taskschd.h>
#include <comdef.h>
#include <wrl/client.h>
#include <vector>

using Microsoft::WRL::ComPtr;
namespace {
std::wstring UserSid() {
  HANDLE token = nullptr;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) return {};
  DWORD bytes = 0;
  GetTokenInformation(token, TokenUser, nullptr, 0, &bytes);
  std::vector<BYTE> storage(bytes);
  const bool read = GetTokenInformation(token, TokenUser, storage.data(), bytes, &bytes) != FALSE;
  CloseHandle(token);
  if (!read) return {};
  LPWSTR sid = nullptr;
  if (!ConvertSidToStringSidW(reinterpret_cast<TOKEN_USER*>(storage.data())->User.Sid, &sid)) return {};
  const std::wstring result(sid);
  LocalFree(sid);
  return result;
}

struct Scheduler {
  HRESULT com = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  ComPtr<ITaskService> service;
  ComPtr<ITaskFolder> folder;
  std::wstring sid = UserSid();
  Scheduler() {
    if ((FAILED(com) && com != RPC_E_CHANGED_MODE) || sid.empty()) return;
    if (FAILED(CoCreateInstance(CLSID_TaskScheduler, nullptr, CLSCTX_INPROC_SERVER,
                               IID_PPV_ARGS(service.GetAddressOf())))) return;
    if (FAILED(service->Connect(_variant_t(), _variant_t(), _variant_t(), _variant_t()))) return;
    service->GetFolder(_bstr_t(L"\\"), folder.GetAddressOf());
  }
  ~Scheduler() {
    folder.Reset(); service.Reset();
    if (SUCCEEDED(com)) CoUninitialize();
  }
  std::wstring name(const std::wstring& suffix) const { return L"Localist-" + sid + suffix; }
};
bool Equal(BSTR actual, const std::wstring& expected) {
  const bool result = actual && _wcsicmp(actual, expected.c_str()) == 0;
  SysFreeString(actual);
  return result;
}
bool EqualUser(BSTR actual, const std::wstring& expected_sid) {
  // Task Scheduler may return DOMAIN\name after accepting a SID at creation.
  if (!actual) return false;
  if (_wcsicmp(actual, expected_sid.c_str()) == 0) { SysFreeString(actual); return true; }
  DWORD sid_size = 0, domain_size = 0; SID_NAME_USE use;
  LookupAccountNameW(nullptr, actual, nullptr, &sid_size, nullptr, &domain_size, &use);
  std::vector<BYTE> sid(sid_size);
  std::vector<wchar_t> domain(domain_size);
  PSID expected = nullptr;
  bool same = false;
  if (sid_size && LookupAccountNameW(nullptr, actual, sid.data(), &sid_size, domain.data(), &domain_size, &use) &&
      ConvertStringSidToSidW(expected_sid.c_str(), &expected)) same = EqualSid(sid.data(), expected) != FALSE;
  if (expected) LocalFree(expected);
  SysFreeString(actual);
  return same;
}
bool Matches(Scheduler& scheduler, const std::wstring& executable, const std::wstring& suffix) {
  if (!scheduler.folder) return false;
  ComPtr<IRegisteredTask> task;
  if (FAILED(scheduler.folder->GetTask(_bstr_t(scheduler.name(suffix).c_str()), task.GetAddressOf()))) return false;
  VARIANT_BOOL enabled = VARIANT_FALSE;
  if (FAILED(task->get_Enabled(&enabled)) || !enabled) return false;
  ComPtr<ITaskDefinition> definition;
  ComPtr<IPrincipal> principal;
  ComPtr<IActionCollection> actions;
  ComPtr<IAction> action;
  ComPtr<IExecAction> exec;
  ComPtr<ITriggerCollection> triggers;
  ComPtr<ITrigger> trigger;
  ComPtr<ILogonTrigger> logon;
  if (FAILED(task->get_Definition(definition.GetAddressOf())) ||
      FAILED(definition->get_Principal(principal.GetAddressOf())) ||
      FAILED(definition->get_Actions(actions.GetAddressOf())) ||
      FAILED(definition->get_Triggers(triggers.GetAddressOf()))) return false;
  TASK_RUNLEVEL_TYPE level;
  TASK_LOGON_TYPE method;
  BSTR user = nullptr;
  if (FAILED(principal->get_RunLevel(&level)) || level != TASK_RUNLEVEL_HIGHEST ||
      FAILED(principal->get_LogonType(&method)) || method != TASK_LOGON_INTERACTIVE_TOKEN ||
      FAILED(principal->get_UserId(&user)) || !EqualUser(user, scheduler.sid)) return false;
  LONG count = 0;
  if (FAILED(actions->get_Count(&count)) || count != 1 ||
      FAILED(actions->get_Item(1, action.GetAddressOf())) || FAILED(action.As(&exec))) return false;
  BSTR path = nullptr, arguments = nullptr, directory = nullptr;
  if (FAILED(exec->get_Path(&path)) || !Equal(path, executable) ||
      FAILED(exec->get_Arguments(&arguments)) || !Equal(arguments, L"--startup") ||
      FAILED(exec->get_WorkingDirectory(&directory)) ||
      !Equal(directory, executable.substr(0, executable.find_last_of(L"\\/")))) return false;
  if (FAILED(triggers->get_Count(&count)) || count != 1 ||
      FAILED(triggers->get_Item(1, trigger.GetAddressOf())) || FAILED(trigger.As(&logon))) return false;
  user = nullptr;
  return SUCCEEDED(logon->get_UserId(&user)) && EqualUser(user, scheduler.sid);
}
}

bool IsLocalistProcessElevated() {
  HANDLE token = nullptr;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) return false;
  TOKEN_ELEVATION elevation{}; DWORD bytes = 0;
  const bool result = GetTokenInformation(token, TokenElevation, &elevation, sizeof(elevation), &bytes) && elevation.TokenIsElevated;
  CloseHandle(token);
  return result;
}

bool IsElevatedStartupEnabled(const std::wstring& executable, const std::wstring& test_suffix) {
  Scheduler scheduler;
  return Matches(scheduler, executable, test_suffix);
}

bool MigrateLegacyLocalistStartup(const std::wstring& executable) {
  constexpr auto run = L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
  constexpr auto approved = L"Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\StartupApproved\\Run";
  wchar_t command[32768] = {}; DWORD bytes = sizeof(command);
  if (RegGetValueW(HKEY_CURRENT_USER, run, L"Localist", RRF_RT_REG_SZ,
      nullptr, command, &bytes) != ERROR_SUCCESS) return true;
  const auto expected = L"\"" + executable + L"\" --startup";
  if (_wcsicmp(command, expected.c_str()) != 0) return true;
  BYTE status[12] = {}; bytes = sizeof(status);
  if (RegGetValueW(HKEY_CURRENT_USER, approved, L"Localist", RRF_RT_REG_BINARY,
      nullptr, status, &bytes) == ERROR_SUCCESS && (status[0] == 3 || status[0] == 7)) return true;
  if (!ConfigureElevatedStartup(true, executable)) return false;
  RegDeleteKeyValueW(HKEY_CURRENT_USER, run, L"Localist");
  RegDeleteKeyValueW(HKEY_CURRENT_USER, approved, L"Localist");
  return true;
}

bool ConfigureElevatedStartup(bool enabled, const std::wstring& executable, const std::wstring& test_suffix) {
  Scheduler scheduler;
  if (!scheduler.folder) return false;
  const auto name = scheduler.name(test_suffix);
  if (!enabled) {
    const HRESULT result = scheduler.folder->DeleteTask(_bstr_t(name.c_str()), 0);
    return SUCCEEDED(result) || result == HRESULT_FROM_WIN32(ERROR_FILE_NOT_FOUND);
  }
  if (Matches(scheduler, executable, test_suffix)) return true;
  if (!IsLocalistProcessElevated()) return false;
  ComPtr<ITaskDefinition> definition;
  ComPtr<IRegistrationInfo> registration;
  ComPtr<IPrincipal> principal;
  ComPtr<ITaskSettings> settings;
  ComPtr<ITriggerCollection> triggers;
  ComPtr<ITrigger> trigger;
  ComPtr<ILogonTrigger> logon;
  ComPtr<IActionCollection> actions;
  ComPtr<IAction> action;
  ComPtr<IExecAction> exec;
  ComPtr<IRegisteredTask> registered;
  if (FAILED(scheduler.service->NewTask(0, definition.GetAddressOf())) ||
      FAILED(definition->get_RegistrationInfo(registration.GetAddressOf())) ||
      FAILED(registration->put_Author(_bstr_t(L"Localist"))) ||
      FAILED(registration->put_Description(_bstr_t(L"Localist elevated interactive startup for this user"))) ||
      FAILED(definition->get_Principal(principal.GetAddressOf())) ||
      FAILED(principal->put_UserId(_bstr_t(scheduler.sid.c_str()))) ||
      FAILED(principal->put_LogonType(TASK_LOGON_INTERACTIVE_TOKEN)) ||
      FAILED(principal->put_RunLevel(TASK_RUNLEVEL_HIGHEST)) ||
      FAILED(definition->get_Settings(settings.GetAddressOf())) ||
      FAILED(settings->put_DisallowStartIfOnBatteries(VARIANT_FALSE)) ||
      FAILED(settings->put_StopIfGoingOnBatteries(VARIANT_FALSE)) ||
      FAILED(settings->put_StartWhenAvailable(VARIANT_TRUE)) ||
      FAILED(settings->put_RunOnlyIfNetworkAvailable(VARIANT_FALSE)) ||
      FAILED(settings->put_ExecutionTimeLimit(_bstr_t(L"PT0S"))) ||
      FAILED(settings->put_MultipleInstances(TASK_INSTANCES_IGNORE_NEW)) ||
      FAILED(definition->get_Triggers(triggers.GetAddressOf())) ||
      FAILED(triggers->Create(TASK_TRIGGER_LOGON, trigger.GetAddressOf())) ||
      FAILED(trigger.As(&logon)) ||
      FAILED(logon->put_UserId(_bstr_t(scheduler.sid.c_str()))) ||
      FAILED(logon->put_Delay(_bstr_t(L"PT10S"))) ||
      FAILED(definition->get_Actions(actions.GetAddressOf())) ||
      FAILED(actions->Create(TASK_ACTION_EXEC, action.GetAddressOf())) ||
      FAILED(action.As(&exec)) ||
      FAILED(exec->put_Path(_bstr_t(executable.c_str()))) ||
      FAILED(exec->put_Arguments(_bstr_t(L"--startup"))) ||
      FAILED(exec->put_WorkingDirectory(_bstr_t(executable.substr(0, executable.find_last_of(L"\\/")).c_str()))) ||
      FAILED(scheduler.folder->RegisterTaskDefinition(_bstr_t(name.c_str()), definition.Get(),
          TASK_CREATE_OR_UPDATE, _variant_t(scheduler.sid.c_str()), _variant_t(),
          TASK_LOGON_INTERACTIVE_TOKEN, _variant_t(), registered.GetAddressOf()))) return false;
  return Matches(scheduler, executable, test_suffix);
}
