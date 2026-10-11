#include "windows_native_bridge.h"

#include <dwmapi.h>
#include <commdlg.h>
#include <fstream>
#include <mfapi.h>
#include <mfidl.h>
#include <mmsystem.h>
#include <shellapi.h>
#include <wininet.h>
#include <windows.h>
#include <wlanapi.h>
#include <shobjidl.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <algorithm>
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
constexpr wchar_t kStartupRegKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
constexpr wchar_t kStartupValueName[] = L"Localist";

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

bool OpenUri(HWND window, const std::string& uri) {
  const std::wstring wide_uri = Utf8ToWide(uri);
  HINSTANCE result =
      ShellExecuteW(window, L"open", wide_uri.c_str(), nullptr, nullptr,
                    SW_SHOWNORMAL);
  return reinterpret_cast<intptr_t>(result) > 32;
}

std::wstring GetModulePath() {
  std::vector<wchar_t> buffer(MAX_PATH, L'\0');
  while (true) {
    const DWORD length = GetModuleFileNameW(nullptr, buffer.data(),
                                              static_cast<DWORD>(buffer.size()));
    if (length == 0) {
      return std::wstring();
    }
    if (length < buffer.size() - 1) {
      return std::wstring(buffer.data(), length);
    }
    buffer.resize(buffer.size() * 2, L'\0');
  }
}

std::wstring ParentDirectory(const std::wstring& path) {
  const size_t separator = path.find_last_of(L"\\/");
  return separator == std::wstring::npos ? std::wstring()
                                         : path.substr(0, separator);
}

bool IsRegularFile(const std::wstring& path) {
  const DWORD attributes = GetFileAttributesW(path.c_str());
  return attributes != INVALID_FILE_ATTRIBUTES &&
         (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

std::wstring QuoteArgument(const std::wstring& value) {
  return L"\"" + value + L"\"";
}

bool SetLaunchAtStartup(bool enabled) {
  if (!enabled) {
    const LSTATUS status = RegDeleteKeyValueW(
        HKEY_CURRENT_USER, kStartupRegKey, kStartupValueName);
    return status == ERROR_SUCCESS || status == ERROR_FILE_NOT_FOUND;
  }
  const std::wstring command = QuoteArgument(GetModulePath()) + L" --startup";
  const bool written = RegSetKeyValueW(
             HKEY_CURRENT_USER, kStartupRegKey, kStartupValueName, REG_SZ,
             command.c_str(),
             static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t))) ==
         ERROR_SUCCESS;
  if (!written) return false;
  // A valid Run entry can still be disabled in Startup Apps/Task Manager.
  // The explicit Enable action must repair that state as well as the path.
  const BYTE approved[12] = {2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
  HKEY startup_approved = nullptr;
  if (RegCreateKeyExW(HKEY_CURRENT_USER,
      L"Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\StartupApproved\\Run",
      0, nullptr, 0, KEY_SET_VALUE, nullptr, &startup_approved, nullptr) != ERROR_SUCCESS) return false;
  const bool enabled_approved = RegSetValueExW(startup_approved,
      kStartupValueName, 0, REG_BINARY, approved, sizeof(approved)) == ERROR_SUCCESS;
  RegCloseKey(startup_approved);
  return enabled_approved;
}

bool GetLaunchAtStartup() {
  BYTE approved[12] = {};
  DWORD approved_size = sizeof(approved);
  if (RegGetValueW(HKEY_CURRENT_USER,
      L"Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\StartupApproved\\Run",
      kStartupValueName, RRF_RT_REG_BINARY, nullptr, approved, &approved_size) == ERROR_SUCCESS &&
      (approved[0] == 3 || approved[0] == 7)) return false;
  wchar_t value[32768] = {};
  DWORD size = sizeof(value);
  const LSTATUS status =
      RegGetValueW(HKEY_CURRENT_USER, kStartupRegKey, kStartupValueName,
                   RRF_RT_REG_SZ, nullptr, value, &size);
  const std::wstring command = QuoteArgument(GetModulePath());
  return status == ERROR_SUCCESS &&
         (_wcsicmp(value, command.c_str()) == 0 ||
          _wcsicmp(value, (command + L" --startup").c_str()) == 0);
}

HANDLE hosted_network_client = nullptr;

EncodableValue StartWindowsLocalNetwork() {
  EncodableMap map;
  map[EncodableValue("supported")] = EncodableValue(false);
  map[EncodableValue("active")] = EncodableValue(false);
  map[EncodableValue("managed")] = EncodableValue(false);
  HANDLE client = nullptr;
  DWORD version = 0;
  DWORD error = WlanOpenHandle(2, nullptr, &version, &client);
  WLAN_HOSTED_NETWORK_REASON reason = wlan_hosted_network_reason_unspecified;
  if (error == ERROR_SUCCESS) {
    error = WlanHostedNetworkInitSettings(client, &reason, nullptr);
  }
  if (error == ERROR_SUCCESS) {
    BOOL enabled = TRUE;
    error = WlanHostedNetworkSetProperty(client,
        wlan_hosted_network_opcode_enable, sizeof(enabled), &enabled, &reason, nullptr);
  }
  if (error == ERROR_SUCCESS) {
    map[EncodableValue("supported")] = EncodableValue(true);
    GUID guid{};
    CoCreateGuid(&guid);
    wchar_t guid_text[40] = {};
    StringFromGUID2(guid, guid_text, 40);
    std::wstring key;
    for (const wchar_t c : std::wstring(guid_text)) {
      if (iswxdigit(c)) key.push_back(c);
    }
    const std::string password = WideToUtf8(key.substr(0, 24));
    const std::string ssid = "Localist_" + WideToUtf8(key.substr(24, 6));
    WLAN_HOSTED_NETWORK_CONNECTION_SETTINGS settings{};
    settings.hostedNetworkSSID.uSSIDLength = static_cast<ULONG>(ssid.size());
    memcpy(settings.hostedNetworkSSID.ucSSID, ssid.data(), ssid.size());
    settings.dwMaxNumberOfPeers = 32;
    error = WlanHostedNetworkSetProperty(client,
        wlan_hosted_network_opcode_connection_settings, sizeof(settings),
        &settings, &reason, nullptr);
    if (error == ERROR_SUCCESS) {
      error = WlanHostedNetworkSetSecondaryKey(client,
          static_cast<DWORD>(password.size() + 1),
          reinterpret_cast<PUCHAR>(const_cast<char*>(password.c_str())),
          TRUE, FALSE, &reason, nullptr);
    }
    if (error == ERROR_SUCCESS) {
      error = WlanHostedNetworkStartUsing(client, &reason, nullptr);
    }
    if (error == ERROR_SUCCESS) {
      map[EncodableValue("active")] = EncodableValue(true);
      map[EncodableValue("managed")] = EncodableValue(true);
      map[EncodableValue("ssid")] = EncodableValue(ssid);
      map[EncodableValue("password")] = EncodableValue(password);
      hosted_network_client = client;
      client = nullptr;
    }
  }
  if (client != nullptr) WlanCloseHandle(client, nullptr);
  map[EncodableValue("permissionRequired")] = EncodableValue(error == ERROR_ACCESS_DENIED);
  map[EncodableValue("errorCode")] = EncodableValue(std::to_string(error));
  map[EncodableValue("message")] = EncodableValue(error == ERROR_SUCCESS
    ? "Private Windows hosted network created. Connect the other devices to this Wi-Fi."
    : error == ERROR_ACCESS_DENIED
    ? "Administrator access is required to configure the hosted network. Reopen Localist as administrator, or use Windows Mobile hotspot settings."
    : "This Wi-Fi driver cannot start a hosted network (Windows error " + std::to_string(error) +
      "). Use Mobile hotspot, a router, USB tethering or an access-point-capable Wi-Fi adapter.");
  return EncodableValue(map);
}

bool StopWindowsLocalNetwork() {
  HANDLE client = hosted_network_client;
  if (client == nullptr) return true;
  hosted_network_client = nullptr;
  WLAN_HOSTED_NETWORK_REASON reason = wlan_hosted_network_reason_unspecified;
  const DWORD error = WlanHostedNetworkStopUsing(client, &reason, nullptr);
  WlanCloseHandle(client, nullptr);
  return error == ERROR_SUCCESS;
}

bool OpenWirelessDisplay() {
  INPUT input[4] = {};
  for (auto& event : input) event.type = INPUT_KEYBOARD;
  input[0].ki.wVk = VK_LWIN;
  input[1].ki.wVk = 'K';
  input[2].ki.wVk = 'K'; input[2].ki.dwFlags = KEYEVENTF_KEYUP;
  input[3].ki.wVk = VK_LWIN; input[3].ki.dwFlags = KEYEVENTF_KEYUP;
  return SendInput(4, input, sizeof(INPUT)) == 4;
}

std::vector<uint8_t> MediaThumbnail(const std::string& path) {
  using Microsoft::WRL::ComPtr;
  ComPtr<IShellItemImageFactory> factory;
  const auto wide = Utf8ToWide(path);
  if (!IsRegularFile(wide) || FAILED(SHCreateItemFromParsingName(
      wide.c_str(), nullptr, IID_PPV_ARGS(factory.GetAddressOf())))) return {};
  HBITMAP bitmap = nullptr;
  if (FAILED(factory->GetImage({320, 180},
      static_cast<SIIGBF>(SIIGBF_THUMBNAILONLY | SIIGBF_RESIZETOFIT), &bitmap))) return {};
  ComPtr<IWICImagingFactory> imaging;
  ComPtr<IWICBitmap> source;
  ComPtr<IStream> stream;
  ComPtr<IWICBitmapEncoder> encoder;
  ComPtr<IWICBitmapFrameEncode> frame;
  std::vector<uint8_t> data;
  HRESULT hr = CoCreateInstance(CLSID_WICImagingFactory, nullptr,
      CLSCTX_INPROC_SERVER, IID_PPV_ARGS(imaging.GetAddressOf()));
  if (SUCCEEDED(hr)) hr = imaging->CreateBitmapFromHBITMAP(bitmap, nullptr,
      WICBitmapUseAlpha, source.GetAddressOf());
  if (SUCCEEDED(hr)) hr = CreateStreamOnHGlobal(nullptr, TRUE, stream.GetAddressOf());
  if (SUCCEEDED(hr)) hr = imaging->CreateEncoder(GUID_ContainerFormatPng, nullptr, encoder.GetAddressOf());
  if (SUCCEEDED(hr)) hr = encoder->Initialize(stream.Get(), WICBitmapEncoderNoCache);
  if (SUCCEEDED(hr)) hr = encoder->CreateNewFrame(frame.GetAddressOf(), nullptr);
  if (SUCCEEDED(hr)) hr = frame->Initialize(nullptr);
  UINT width = 0, height = 0;
  if (SUCCEEDED(hr)) hr = source->GetSize(&width, &height);
  if (SUCCEEDED(hr)) hr = frame->SetSize(width, height);
  WICPixelFormatGUID format = GUID_WICPixelFormat32bppBGRA;
  if (SUCCEEDED(hr)) hr = frame->SetPixelFormat(&format);
  if (SUCCEEDED(hr)) hr = frame->WriteSource(source.Get(), nullptr);
  if (SUCCEEDED(hr)) hr = frame->Commit();
  if (SUCCEEDED(hr)) hr = encoder->Commit();
  STATSTG stat{};
  if (SUCCEEDED(hr)) hr = stream->Stat(&stat, STATFLAG_NONAME);
  if (SUCCEEDED(hr) && stat.cbSize.QuadPart <= 4 * 1024 * 1024) {
    data.resize(static_cast<size_t>(stat.cbSize.QuadPart));
    LARGE_INTEGER start{};
    stream->Seek(start, STREAM_SEEK_SET, nullptr);
    ULONG read = 0;
    if (FAILED(stream->Read(data.data(), static_cast<ULONG>(data.size()), &read))) data.clear();
    else data.resize(read);
  }
  DeleteObject(bitmap);
  return data;
}

bool PlayAppSound(const std::string& event) {
  static const std::vector<std::string> allowed = {
      "request", "accepted", "cancelled", "completed", "failed"};
  if (std::find(allowed.begin(), allowed.end(), event) == allowed.end()) {
    return false;
  }
  const std::wstring path =
      ParentDirectory(GetModulePath()) +
      L"\\data\\flutter_assets\\assets\\sounds\\" + Utf8ToWide(event) +
      L".wav";
  return IsRegularFile(path) &&
         PlaySoundW(path.c_str(), nullptr,
                    SND_FILENAME | SND_ASYNC | SND_NODEFAULT) != FALSE;
}

bool OpenFile(HWND window, const std::string& path) {
  const std::wstring wide_path = Utf8ToWide(path);
  if (!IsRegularFile(wide_path)) {
    return false;
  }
  const HINSTANCE result = ShellExecuteW(window, L"open", wide_path.c_str(),
                                          nullptr, nullptr, SW_SHOWNORMAL);
  return reinterpret_cast<intptr_t>(result) > 32;
}

bool OpenContainingFolder(HWND window, const std::string& path) {
  const std::wstring wide_path = Utf8ToWide(path);
  if (!IsRegularFile(wide_path)) {
    return false;
  }
  const std::wstring parameters = L"/select," + QuoteArgument(wide_path);
  const HINSTANCE result = ShellExecuteW(window, L"open", L"explorer.exe",
                                          parameters.c_str(), nullptr,
                                          SW_SHOWNORMAL);
  return reinterpret_cast<intptr_t>(result) > 32;
}

bool StartWindowsUpdate(HWND window, const EncodableValue* arguments) {
  const std::wstring archive_path =
      Utf8ToWide(GetStringArgument(arguments, "archivePath"));
  const std::wstring version = Utf8ToWide(GetStringArgument(arguments, "version"));
  const std::wstring bundle_path = Utf8ToWide(GetStringArgument(arguments, "bundlePath"));
  const std::wstring executable_path = GetModulePath();
  const std::wstring executable_directory = ParentDirectory(executable_path);
  if (!IsRegularFile(archive_path) || executable_path.empty() ||
      executable_directory.empty()) {
    return false;
  }

  const std::wstring bundled_updater =
      executable_directory + L"\\LocalistUpdater.exe";
  if (!IsRegularFile(bundled_updater)) {
    return false;
  }

  wchar_t temp_path[MAX_PATH];
  const DWORD temp_length = GetTempPathW(MAX_PATH, temp_path);
  if (temp_length == 0 || temp_length >= MAX_PATH) {
    return false;
  }
  const std::wstring temporary_updater =
      std::wstring(temp_path) + L"LocalistUpdater-" +
      std::to_wstring(GetCurrentProcessId()) + L"-" +
      std::to_wstring(GetTickCount64()) + L".exe";
  if (!CopyFileW(bundled_updater.c_str(), temporary_updater.c_str(), FALSE)) {
    return false;
  }

  std::wstring command_line =
      QuoteArgument(temporary_updater) + L" --wait-pid " +
      std::to_wstring(GetCurrentProcessId()) + L" --archive " +
      QuoteArgument(archive_path) + L" --target " +
      QuoteArgument(executable_directory) + L" --launch " +
      QuoteArgument(executable_path) + L" --version " + QuoteArgument(version);
  if (!bundle_path.empty()) command_line += L" --bundle " + QuoteArgument(bundle_path);
  std::vector<wchar_t> command_line_buffer(command_line.begin(), command_line.end());
  command_line_buffer.push_back(L'\0');
  STARTUPINFOW startup_info{};
  startup_info.cb = sizeof(startup_info);
  PROCESS_INFORMATION process_info{};
  const BOOL started = CreateProcessW(
      temporary_updater.c_str(), command_line_buffer.data(), nullptr, nullptr,
      FALSE, CREATE_UNICODE_ENVIRONMENT, nullptr, nullptr, &startup_info,
      &process_info);
  if (!started) {
    DeleteFileW(temporary_updater.c_str());
    return false;
  }
  CloseHandle(process_info.hThread);
  CloseHandle(process_info.hProcess);
  MoveFileExW(temporary_updater.c_str(), nullptr, MOVEFILE_DELAY_UNTIL_REBOOT);
  return true;
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

  if (method == "getMediaThumbnail") {
    result->Success(EncodableValue(MediaThumbnail(GetStringArgument(arguments, "path"))));
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
    // Privileged network operations use their scoped worker. Never replace
    // the primary Flutter process just to grant a feature permission.
    result->Success(BoolMap(false, false, false,
        "Administrator approval is requested by each operation when needed."));
    return;
  }

  if (method == "openUri") {
    result->Success(EncodableValue(OpenUri(
        window, GetStringArgument(arguments, "uri"))));
    return;
  }

  if (method == "openFile") {
    result->Success(EncodableValue(OpenFile(
        window, GetStringArgument(arguments, "path"))));
    return;
  }

  if (method == "openContainingFolder") {
    result->Success(EncodableValue(OpenContainingFolder(
        window, GetStringArgument(arguments, "path"))));
    return;
  }

  if (method == "openHotspotSettings") {
    result->Success(
        EncodableValue(OpenUri(window, "ms-settings:network-mobilehotspot")));
    return;
  }

  if (method == "startWindowsUpdate") {
    const bool started = StartWindowsUpdate(window, arguments);
    result->Success(EncodableValue(started));
    if (started) {
      PostMessageW(window, kLocalistApplyUpdateMessage, 0, 0);
    }
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

  if (method == "showWindowsMessage") {
    const std::string title = GetStringArgument(arguments, "title").empty()
                                  ? "Localist"
                                  : GetStringArgument(arguments, "title");
    const std::string message = GetStringArgument(arguments, "message");
    const bool warning = GetBoolArgument(arguments, "warning", true);
    ::MessageBoxW(window, Utf8ToWide(message).c_str(),
                  Utf8ToWide(title).c_str(),
                  MB_OK | (warning ? MB_ICONWARNING : MB_ICONINFORMATION) |
                      MB_SETFOREGROUND);
    result->Success(EncodableValue(true));
    return;
  }

  if (method == "applyRemoteOption") {
#ifdef _DEBUG
    const auto key = GetStringArgument(arguments, "key");
    const auto value = GetStringArgument(arguments, "value");
    const auto path = Utf8ToWide(GetStringArgument(arguments, "path"));
    const std::vector<std::string> allowed = {
      "custom-rendezvous-server", "relay-server", "api-server", "key",
      "direct-server", "direct-access-port", "enable-lan-discovery",
      "enable-keyboard", "enable-clipboard", "enable-file-transfer",
      "enable-audio", "enable-camera", "enable-terminal", "enable-tunnel",
      "enable-remote-restart", "enable-record-session", "enable-block-input",
      "enable-privacy-mode", "enable-remote-printer",
      "allow-remote-config-modification", "enable-hwcodec", "force-always-relay",
      "allow-always-software-render", "access-mode", "verification-method",
      "approve-mode", "enable-abr", "allow-remove-wallpaper",
      "enable-directx-capture", "enable-tcp-punch", "enable-udp-punch",
      "enable-ipv6-punch", "enable-webrtc", "relay-fallback-delay",
      "allow-sync-clipboard-between-sessions", "allow-ask-for-note",
      "allow-monitor-switch-main-toolbar", "allow-websocket",
      "allow-insecure-tls-fallback", "disable-udp", "whitelist", "id-whitelist",
      "allow-auto-disconnect", "auto-disconnect-timeout",
      "keep-awake-during-incoming-sessions", "allow-only-conn-window-open",
      "keep-awake-during-outgoing-sessions", "allow-auto-update",
    };
    const bool safe = IsRegularFile(path) &&
        std::find(allowed.begin(), allowed.end(), key) != allowed.end() &&
        value.size() <= 4096 && value.find_first_of("\r\n\0") == std::string::npos;
    if (!safe) { result->Success(EncodableValue(false)); return; }
    const std::wstring parameters = L"--option " + QuoteArgument(Utf8ToWide(key)) +
      L" " + QuoteArgument(Utf8ToWide(value));
    const auto launched = ShellExecuteW(window, L"runas", path.c_str(), parameters.c_str(),
      ParentDirectory(path).c_str(), SW_HIDE);
    result->Success(EncodableValue(reinterpret_cast<intptr_t>(launched) > 32));
#else
    result->NotImplemented();
#endif
    return;
  }

  if (method == "applyRustDeskOption") {
#ifdef _DEBUG
    const auto key = GetStringArgument(arguments, "key");
    const auto value = GetStringArgument(arguments, "value");
    const auto path = Utf8ToWide(GetStringArgument(arguments, "path"));
    const std::vector<std::string> allowed = {
      "direct-server", "enable-lan-discovery", "enable-keyboard", "enable-clipboard",
      "enable-file-transfer", "enable-audio", "enable-camera", "enable-terminal",
      "enable-tunnel", "enable-remote-restart", "enable-record-session",
      "enable-block-input", "enable-privacy-mode", "enable-remote-printer",
      "allow-remote-config-modification", "enable-hwcodec", "force-always-relay",
      "allow-always-software-render"};
    if (!IsRegularFile(path) || std::find(allowed.begin(), allowed.end(), key) == allowed.end() ||
        (value != "Y" && value != "N")) { result->Success(EncodableValue(false)); return; }
    const std::wstring parameters = L"--option " + Utf8ToWide(key) + L" " + Utf8ToWide(value);
    const auto launched = ShellExecuteW(window, L"runas", path.c_str(), parameters.c_str(),
      ParentDirectory(path).c_str(), SW_HIDE);
    result->Success(EncodableValue(reinterpret_cast<intptr_t>(launched) > 32));
#else
    result->NotImplemented();
#endif
    return;
  }
  if (method == "startWindowsLocalNetwork") {
    result->Success(StartWindowsLocalNetwork());
    return;
  }
  if (method == "stopWindowsLocalNetwork") {
    result->Success(EncodableValue(StopWindowsLocalNetwork()));
    return;
  }
  if (method == "openWirelessDisplay") {
    result->Success(EncodableValue(OpenWirelessDisplay()));
    return;
  }
  if (method == "playAppSound") {
    result->Success(
        EncodableValue(PlayAppSound(GetStringArgument(arguments, "event"))));
    return;
  }

  if (method == "setWindowsLaunchAtStartup") {
    result->Success(EncodableValue(SetLaunchAtStartup(
        GetBoolArgument(arguments, "enabled", false))));
    return;
  }

  if (method == "getWindowsLaunchAtStartup") {
    result->Success(EncodableValue(GetLaunchAtStartup()));
    return;
  }

  if (method == "flashWindowsTaskbar") {
    FLASHWINFO flash = {};
    flash.cbSize = sizeof(FLASHWINFO);
    flash.hwnd = window;
    flash.dwFlags = FLASHW_CAPTION | FLASHW_TRAY;
    flash.uCount = 3;
    flash.dwTimeout = 0;
    result->Success(EncodableValue(FlashWindowEx(&flash) != FALSE));
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
