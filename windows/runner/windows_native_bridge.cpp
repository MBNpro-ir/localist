#include "windows_native_bridge.h"

#include <dwmapi.h>
#include <commdlg.h>
#include <fstream>
#include <mfapi.h>
#include <mfidl.h>
#include <shellapi.h>
#include <wininet.h>
#include <windows.h>

#include <iomanip>
#include <sstream>
#include <string>
#include <variant>
#include <vector>

#include <flutter/standard_method_codec.h>

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResult;

constexpr wchar_t kThemeRegKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize";
constexpr wchar_t kAppsUseLightTheme[] = L"AppsUseLightTheme";

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) {
    return std::wstring();
  }
  const int size = MultiByteToWideChar(CP_UTF8, 0, value.c_str(),
                                       static_cast<int>(value.size()), nullptr,
                                       0);
  std::wstring result(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.c_str(),
                      static_cast<int>(value.size()), result.data(), size);
  return result;
}

std::string WideToUtf8(const std::wstring& value) {
  if (value.empty()) {
    return std::string();
  }
  const int size = WideCharToMultiByte(CP_UTF8, 0, value.c_str(),
                                       static_cast<int>(value.size()), nullptr,
                                       0, nullptr, nullptr);
  std::string result(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.c_str(),
                      static_cast<int>(value.size()), result.data(), size,
                      nullptr, nullptr);
  return result;
}

const EncodableMap* GetArgumentsMap(const EncodableValue* arguments) {
  if (arguments == nullptr) {
    return nullptr;
  }
  return std::get_if<EncodableMap>(arguments);
}

bool GetBoolArgument(const EncodableValue* arguments, const char* key,
                     bool fallback = false) {
  const EncodableMap* map = GetArgumentsMap(arguments);
  if (map == nullptr) {
    return fallback;
  }
  const auto it = map->find(EncodableValue(std::string(key)));
  if (it == map->end()) {
    return fallback;
  }
  const bool* value = std::get_if<bool>(&it->second);
  return value == nullptr ? fallback : *value;
}

std::string GetStringArgument(const EncodableValue* arguments, const char* key) {
  const EncodableMap* map = GetArgumentsMap(arguments);
  if (map == nullptr) {
    return std::string();
  }
  const auto it = map->find(EncodableValue(std::string(key)));
  if (it == map->end()) {
    return std::string();
  }
  const std::string* value = std::get_if<std::string>(&it->second);
  return value == nullptr ? std::string() : *value;
}

std::string GetEnvironmentString(const wchar_t* name) {
  const DWORD size = GetEnvironmentVariableW(name, nullptr, 0);
  if (size == 0) {
    return std::string();
  }
  std::wstring value(size, L'\0');
  const DWORD written = GetEnvironmentVariableW(name, value.data(), size);
  if (written == 0) {
    return std::string();
  }
  value.resize(written);
  return WideToUtf8(value);
}

EncodableValue BoolMap(bool available, bool enabled, bool launched = false,
                       const std::string& last_error = std::string()) {
  EncodableMap map;
  map[EncodableValue("available")] = EncodableValue(available);
  map[EncodableValue("enabled")] = EncodableValue(enabled);
  map[EncodableValue("active")] = EncodableValue(enabled);
  map[EncodableValue("launched")] = EncodableValue(launched);
  map[EncodableValue("vpnInterface")] =
      EncodableValue(available ? "Windows administrator" : "");
  map[EncodableValue("clientSubnets")] = EncodableValue(EncodableList());
  map[EncodableValue("availableClientSubnets")] =
      EncodableValue(EncodableList());
  map[EncodableValue("availableLocalIps")] = EncodableValue(EncodableList());
  map[EncodableValue("lastError")] = EncodableValue(last_error);
  return EncodableValue(map);
}

bool IsRunningElevated() {
  HANDLE token = nullptr;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) {
    return false;
  }
  TOKEN_ELEVATION elevation{};
  DWORD size = sizeof(elevation);
  const BOOL ok =
      GetTokenInformation(token, TokenElevation, &elevation, sizeof(elevation),
                          &size);
  CloseHandle(token);
  return ok && elevation.TokenIsElevated != 0;
}

bool LaunchElevatedSelf(HWND window) {
  wchar_t path[MAX_PATH];
  const DWORD length = GetModuleFileNameW(nullptr, path, MAX_PATH);
  if (length == 0 || length >= MAX_PATH) {
    return false;
  }
  HINSTANCE result = ShellExecuteW(window, L"runas", path, L"--enable-admin",
                                   nullptr, SW_SHOWNORMAL);
  return reinterpret_cast<intptr_t>(result) > 32;
}

bool OpenUri(HWND window, const std::string& uri) {
  const std::wstring wide_uri = Utf8ToWide(uri);
  HINSTANCE result =
      ShellExecuteW(window, L"open", wide_uri.c_str(), nullptr, nullptr,
                    SW_SHOWNORMAL);
  return reinterpret_cast<intptr_t>(result) > 32;
}

std::string WindowsSettingsSignature() {
  DWORD light_mode = 1;
  DWORD light_mode_size = sizeof(light_mode);
  RegGetValueW(HKEY_CURRENT_USER, kThemeRegKey, kAppsUseLightTheme,
               RRF_RT_REG_DWORD, nullptr, &light_mode, &light_mode_size);

  DWORD color = 0;
  BOOL opaque = FALSE;
  DwmGetColorizationColor(&color, &opaque);

  std::ostringstream stream;
  stream << "appsLight=" << light_mode << ";accent=0x" << std::uppercase
         << std::hex << std::setw(8) << std::setfill('0') << color
         << ";opaque=" << (opaque ? 1 : 0);
  return stream.str();
}

EncodableValue GetWindowsProxySettings() {
  INTERNET_PER_CONN_OPTIONW options[3]{};
  options[0].dwOption = INTERNET_PER_CONN_FLAGS;
  options[1].dwOption = INTERNET_PER_CONN_PROXY_SERVER;
  options[2].dwOption = INTERNET_PER_CONN_PROXY_BYPASS;

  INTERNET_PER_CONN_OPTION_LISTW list{};
  list.dwSize = sizeof(list);
  list.pszConnection = nullptr;
  list.dwOptionCount = 3;
  list.dwOptionError = 0;
  list.pOptions = options;

  DWORD size = sizeof(list);
  const BOOL ok = InternetQueryOptionW(
      nullptr, INTERNET_OPTION_PER_CONNECTION_OPTION, &list, &size);

  EncodableMap map;
  if (!ok) {
    map[EncodableValue("enabled")] = EncodableValue(false);
    map[EncodableValue("server")] = EncodableValue("");
    map[EncodableValue("bypass")] = EncodableValue("");
    return EncodableValue(map);
  }

  const DWORD flags = options[0].Value.dwValue;
  map[EncodableValue("enabled")] =
      EncodableValue((flags & PROXY_TYPE_PROXY) != 0);
  map[EncodableValue("server")] = EncodableValue(
      options[1].Value.pszValue == nullptr
          ? ""
          : WideToUtf8(options[1].Value.pszValue));
  map[EncodableValue("bypass")] = EncodableValue(
      options[2].Value.pszValue == nullptr
          ? ""
          : WideToUtf8(options[2].Value.pszValue));

  if (options[1].Value.pszValue != nullptr) {
    GlobalFree(options[1].Value.pszValue);
  }
  if (options[2].Value.pszValue != nullptr) {
    GlobalFree(options[2].Value.pszValue);
  }
  return EncodableValue(map);
}

bool SetWindowsProxySettings(bool enabled, const std::string& server,
                             const std::string& bypass) {
  std::wstring wide_server = Utf8ToWide(server);
  std::wstring wide_bypass = Utf8ToWide(bypass);

  INTERNET_PER_CONN_OPTIONW options[3]{};
  options[0].dwOption = INTERNET_PER_CONN_FLAGS;
  options[0].Value.dwValue =
      enabled ? (PROXY_TYPE_DIRECT | PROXY_TYPE_PROXY) : PROXY_TYPE_DIRECT;
  options[1].dwOption = INTERNET_PER_CONN_PROXY_SERVER;
  options[1].Value.pszValue = wide_server.empty() ? nullptr : wide_server.data();
  options[2].dwOption = INTERNET_PER_CONN_PROXY_BYPASS;
  options[2].Value.pszValue = wide_bypass.empty() ? nullptr : wide_bypass.data();

  INTERNET_PER_CONN_OPTION_LISTW list{};
  list.dwSize = sizeof(list);
  list.pszConnection = nullptr;
  list.dwOptionCount = 3;
  list.dwOptionError = 0;
  list.pOptions = options;

  const BOOL ok = InternetSetOptionW(
      nullptr, INTERNET_OPTION_PER_CONNECTION_OPTION, &list, sizeof(list));
  InternetSetOptionW(nullptr, INTERNET_OPTION_SETTINGS_CHANGED, nullptr, 0);
  InternetSetOptionW(nullptr, INTERNET_OPTION_REFRESH, nullptr, 0);
  return ok;
}

EncodableValue GetWindowsCameraDevices() {
  EncodableList devices;
  if (FAILED(MFStartup(MF_VERSION))) {
    return EncodableValue(devices);
  }

  IMFAttributes* attributes = nullptr;
  if (SUCCEEDED(MFCreateAttributes(&attributes, 1))) {
    attributes->SetGUID(MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE,
                        MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_GUID);

    IMFActivate** sources = nullptr;
    UINT32 count = 0;
    if (SUCCEEDED(MFEnumDeviceSources(attributes, &sources, &count))) {
      for (UINT32 i = 0; i < count; ++i) {
        wchar_t* name = nullptr;
        UINT32 name_length = 0;
        if (SUCCEEDED(sources[i]->GetAllocatedString(
                MF_DEVSOURCE_ATTRIBUTE_FRIENDLY_NAME, &name, &name_length))) {
          devices.emplace_back(WideToUtf8(name));
          CoTaskMemFree(name);
        }
        sources[i]->Release();
      }
      CoTaskMemFree(sources);
    }
    attributes->Release();
  }

  MFShutdown();
  return EncodableValue(devices);
}

std::string ProcessorArchitectureName(WORD architecture) {
  switch (architecture) {
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

EncodableValue GetWindowsDeviceDetails() {
  SYSTEM_INFO system_info{};
  GetNativeSystemInfo(&system_info);

  MEMORYSTATUSEX memory_status{};
  memory_status.dwLength = sizeof(memory_status);
  GlobalMemoryStatusEx(&memory_status);

  EncodableMap map;
  map[EncodableValue("computerName")] =
      EncodableValue(GetEnvironmentString(L"COMPUTERNAME"));
  map[EncodableValue("userName")] =
      EncodableValue(GetEnvironmentString(L"USERNAME"));
  map[EncodableValue("userDomain")] =
      EncodableValue(GetEnvironmentString(L"USERDOMAIN"));
  map[EncodableValue("osEnvironment")] =
      EncodableValue(GetEnvironmentString(L"OS"));
  map[EncodableValue("processorArchitecture")] =
      EncodableValue(ProcessorArchitectureName(
          system_info.wProcessorArchitecture));
  map[EncodableValue("processorArchitectureEnv")] =
      EncodableValue(GetEnvironmentString(L"PROCESSOR_ARCHITECTURE"));
  map[EncodableValue("processorIdentifier")] =
      EncodableValue(GetEnvironmentString(L"PROCESSOR_IDENTIFIER"));
  map[EncodableValue("numberOfProcessors")] =
      EncodableValue(static_cast<int>(system_info.dwNumberOfProcessors));
  map[EncodableValue("pageSize")] =
      EncodableValue(static_cast<int>(system_info.dwPageSize));
  map[EncodableValue("allocationGranularity")] =
      EncodableValue(static_cast<int>(system_info.dwAllocationGranularity));
  map[EncodableValue("memoryLoadPercent")] =
      EncodableValue(static_cast<int>(memory_status.dwMemoryLoad));
  map[EncodableValue("totalPhysicalMemoryMb")] = EncodableValue(
      static_cast<int64_t>(memory_status.ullTotalPhys / 1024 / 1024));
  map[EncodableValue("availablePhysicalMemoryMb")] = EncodableValue(
      static_cast<int64_t>(memory_status.ullAvailPhys / 1024 / 1024));
  map[EncodableValue("remoteSession")] =
      EncodableValue(GetSystemMetrics(SM_REMOTESESSION) != 0);
  map[EncodableValue("primaryScreenWidth")] =
      EncodableValue(GetSystemMetrics(SM_CXSCREEN));
  map[EncodableValue("primaryScreenHeight")] =
      EncodableValue(GetSystemMetrics(SM_CYSCREEN));
  map[EncodableValue("windowsSettingsSignature")] =
      EncodableValue(WindowsSettingsSignature());
  return EncodableValue(map);
}

EncodableValue SaveTextFile(HWND window, const EncodableValue* arguments) {
  const std::string text = GetStringArgument(arguments, "text");
  const std::string suggested_name =
      GetStringArgument(arguments, "suggestedName").empty()
          ? "localist-debug-log.txt"
          : GetStringArgument(arguments, "suggestedName");
  std::wstring file_name = Utf8ToWide(suggested_name);
  if (file_name.empty()) {
    file_name = L"localist-debug-log.txt";
  }
  std::vector<wchar_t> buffer(MAX_PATH, L'\0');
  wcsncpy_s(buffer.data(), buffer.size(), file_name.c_str(), _TRUNCATE);

  OPENFILENAMEW open_file_name{};
  open_file_name.lStructSize = sizeof(open_file_name);
  open_file_name.hwndOwner = window;
  open_file_name.lpstrFile = buffer.data();
  open_file_name.nMaxFile = static_cast<DWORD>(buffer.size());
  open_file_name.lpstrFilter =
      L"Text files (*.txt)\0*.txt\0Log files (*.log)\0*.log\0All files (*.*)\0*.*\0";
  open_file_name.lpstrDefExt = L"txt";
  open_file_name.Flags =
      OFN_OVERWRITEPROMPT | OFN_PATHMUSTEXIST | OFN_NOCHANGEDIR;

  EncodableMap map;
  if (!GetSaveFileNameW(&open_file_name)) {
    const DWORD error = CommDlgExtendedError();
    map[EncodableValue("saved")] = EncodableValue(false);
    map[EncodableValue("canceled")] = EncodableValue(error == 0);
    if (error != 0) {
      map[EncodableValue("errorCode")] =
          EncodableValue(static_cast<int>(error));
    }
    return EncodableValue(map);
  }

  std::ofstream output(buffer.data(), std::ios::binary | std::ios::trunc);
  if (!output.is_open()) {
    map[EncodableValue("saved")] = EncodableValue(false);
    map[EncodableValue("canceled")] = EncodableValue(false);
    map[EncodableValue("error")] = EncodableValue("Could not open output file.");
    return EncodableValue(map);
  }
  output.write(text.data(), static_cast<std::streamsize>(text.size()));
  output.close();

  map[EncodableValue("saved")] = EncodableValue(output.good());
  map[EncodableValue("canceled")] = EncodableValue(false);
  map[EncodableValue("path")] = EncodableValue(WideToUtf8(buffer.data()));
  return EncodableValue(map);
}

void HandleMethodCall(HWND window, const MethodCall<EncodableValue>& call,
                      std::unique_ptr<MethodResult<EncodableValue>> result) {
  const std::string& method = call.method_name();
  const EncodableValue* arguments = call.arguments();

  if (method == "checkRootAccess") {
    const bool elevated = IsRunningElevated();
    result->Success(BoolMap(elevated, elevated));
    return;
  }

  if (method == "setRootRoutingEnabled") {
    const bool enabled = GetBoolArgument(arguments, "enabled", false);
    const bool elevated = IsRunningElevated();
    if (!enabled) {
      result->Success(BoolMap(elevated, false));
      return;
    }
    if (elevated) {
      result->Success(BoolMap(true, true));
      return;
    }
    const bool launched = LaunchElevatedSelf(window);
    result->Success(BoolMap(false, false, launched,
                            launched ? "Approve the Windows admin prompt."
                                     : "Windows admin prompt could not open."));
    return;
  }

  if (method == "openUri") {
    result->Success(EncodableValue(OpenUri(
        window, GetStringArgument(arguments, "uri"))));
    return;
  }

  if (method == "getWindowsSettingsSignature") {
    result->Success(EncodableValue(WindowsSettingsSignature()));
    return;
  }

  if (method == "getWindowsSystemProxy") {
    result->Success(GetWindowsProxySettings());
    return;
  }

  if (method == "setWindowsSystemProxy") {
    const bool ok = SetWindowsProxySettings(
        GetBoolArgument(arguments, "enabled", false),
        GetStringArgument(arguments, "server"),
        GetStringArgument(arguments, "bypass"));
    result->Success(EncodableValue(ok));
    return;
  }

  if (method == "getWindowsCameraDevices") {
    result->Success(GetWindowsCameraDevices());
    return;
  }

  if (method == "saveTextFile") {
    result->Success(SaveTextFile(window, arguments));
    return;
  }

  if (method == "getDeviceDetails") {
    result->Success(GetWindowsDeviceDetails());
    return;
  }

  result->NotImplemented();
}

}  // namespace

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
CreateLocalistMethodChannel(flutter::BinaryMessenger* messenger, HWND window) {
  auto channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "com.prs.localist.vpn",
      &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(
      [window](const MethodCall<EncodableValue>& call,
               std::unique_ptr<MethodResult<EncodableValue>> result) {
        HandleMethodCall(window, call, std::move(result));
      });
  return channel;
}
