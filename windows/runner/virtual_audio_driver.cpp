#include "virtual_audio_driver.h"
#include <windows.h>
#include <setupapi.h>
#include <cfgmgr32.h>
#include <newdev.h>
#include <devguid.h>
#include <softpub.h>
#include <mscat.h>
#include <wintrust.h>
#include <vector>
#include <cwctype>

namespace {
constexpr wchar_t kHardwareId[] = L"ROOT\\LocalistAudio";
constexpr wchar_t kOwnerKey[] = L"Software\\Localist\\VirtualAudio";
constexpr wchar_t kInf[] = L"LocalistAudio.inf";

std::wstring ReadOwner(const wchar_t* name) {
  wchar_t value[32768]{}; DWORD size = sizeof(value);
  if (RegGetValueW(HKEY_LOCAL_MACHINE, kOwnerKey, name,
      RRF_RT_REG_SZ | RRF_SUBKEY_WOW6464KEY, nullptr, value, &size) != ERROR_SUCCESS) return {};
  return value;
}
bool SaveOwner(const std::wstring& directory, const std::wstring& inf) {
  HKEY key = nullptr;
  if (RegCreateKeyExW(HKEY_LOCAL_MACHINE, kOwnerKey, 0, nullptr, 0,
      KEY_SET_VALUE | KEY_WOW64_64KEY, nullptr, &key, nullptr) != ERROR_SUCCESS) return false;
  const auto put = [key](const wchar_t* name, const std::wstring& value) {
    return RegSetValueExW(key, name, 0, REG_SZ, reinterpret_cast<const BYTE*>(value.c_str()),
        static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t))) == ERROR_SUCCESS;
  };
  const bool ok = put(L"Inf", inf) && put(L"Directory", directory);
  RegCloseKey(key); return ok;
}
// Validate catalog membership too: trusting a signed CAT beside modified files
// is insufficient. Windows SetupAPI additionally enforces kernel signing policy.
bool TrustedMember(const std::wstring& file, const std::wstring& catalog) {
  HANDLE input = CreateFileW(file.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr,
      OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (input == INVALID_HANDLE_VALUE) return false;
  HCATADMIN admin = nullptr; GUID subsystem = DRIVER_ACTION_VERIFY;
  bool trusted = false;
  if (CryptCATAdminAcquireContext2(&admin, &subsystem, L"SHA256", nullptr, 0)) {
    DWORD length = 0;
    CryptCATAdminCalcHashFromFileHandle2(admin, input, &length, nullptr, 0);
    std::vector<BYTE> digest(length);
    if (length && CryptCATAdminCalcHashFromFileHandle2(admin, input, &length, digest.data(), 0)) {
      std::wstring tag; constexpr wchar_t hex[] = L"0123456789ABCDEF";
      for (BYTE byte : digest) { tag += hex[byte >> 4]; tag += hex[byte & 15]; }
      WINTRUST_CATALOG_INFO member{}; member.cbStruct = sizeof(member);
      member.pcwszCatalogFilePath = catalog.c_str(); member.pcwszMemberTag = tag.c_str();
      member.pcwszMemberFilePath = file.c_str(); member.hMemberFile = input;
      member.pbCalculatedFileHash = digest.data(); member.cbCalculatedFileHash = length;
      member.hCatAdmin = admin;
      WINTRUST_DATA trust{}; trust.cbStruct = sizeof(trust);
      trust.dwUIChoice = WTD_UI_NONE; trust.fdwRevocationChecks = WTD_REVOKE_NONE;
      trust.dwUnionChoice = WTD_CHOICE_CATALOG; trust.pCatalog = &member;
      trust.dwStateAction = WTD_STATEACTION_VERIFY;
      trust.dwProvFlags = WTD_CACHE_ONLY_URL_RETRIEVAL;
      GUID policy = WINTRUST_ACTION_GENERIC_VERIFY_V2;
      trusted = WinVerifyTrust(nullptr, &policy, &trust) == ERROR_SUCCESS;
      trust.dwStateAction = WTD_STATEACTION_CLOSE; WinVerifyTrust(nullptr, &policy, &trust);
    }
    CryptCATAdminReleaseContext(admin, 0);
  }
  CloseHandle(input); return trusted;
}
bool IsOurDevice(HDEVINFO devices, SP_DEVINFO_DATA& device) {
  wchar_t ids[4096]{}; DWORD type = 0;
  if (!SetupDiGetDeviceRegistryPropertyW(devices, &device, SPDRP_HARDWAREID,
      &type, reinterpret_cast<BYTE*>(ids), sizeof(ids) - sizeof(wchar_t), nullptr) || type != REG_MULTI_SZ) return false;
  for (const wchar_t* id = ids; *id; id += wcslen(id) + 1)
    if (_wcsicmp(id, kHardwareId) == 0) return true;
  return false;
}
bool HasDevice() {
  HDEVINFO devices = SetupDiGetClassDevsW(&GUID_DEVCLASS_MEDIA, nullptr, nullptr, 0);
  if (devices == INVALID_HANDLE_VALUE) return false;
  SP_DEVINFO_DATA device{}; device.cbSize = sizeof(device); bool found = false;
  for (DWORD index = 0; SetupDiEnumDeviceInfo(devices, index, &device); ++index)
    if (IsOurDevice(devices, device)) { found = true; break; }
  SetupDiDestroyDeviceInfoList(devices); return found;
}
bool PublishedInfName(const std::wstring& name) {
  if (name.size() < 8 || name.substr(0, 3) != L"oem" || name.substr(name.size() - 4) != L".inf") return false;
  for (size_t i = 3; i < name.size() - 4; ++i) if (!iswdigit(name[i])) return false;
  return true;
}
}

LocalistMicrophoneStatus GetLocalistMicrophoneStatus() {
  LocalistMicrophoneStatus status;
  status.installed = HasDevice();
  HANDLE handle = CreateFileW(L"\\\\.\\LocalistAudioControl", GENERIC_WRITE,
      FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING, 0, nullptr);
  status.available = handle != INVALID_HANDLE_VALUE;
  if (status.available) CloseHandle(handle); else status.error = GetLastError();
  return status;
}

bool InstallLocalistMicrophones(const std::wstring& directory) {
  const auto package = directory + L"\\drivers\\LocalistAudio\\";
  const auto inf = package + kInf;
  if (!TrustedMember(inf, package + L"localistaudio.cat") ||
      !TrustedMember(package + L"LocalistAudio.sys", package + L"localistaudio.cat")) return false;
  wchar_t published[MAX_PATH]{};
  if (!SetupCopyOEMInfW(inf.c_str(), package.c_str(), SPOST_PATH, 0,
      published, MAX_PATH, nullptr, nullptr)) return false;
  GUID deviceClass{}; wchar_t className[MAX_CLASS_NAME_LEN]{};
  if (!SetupDiGetINFClassW(inf.c_str(), &deviceClass, className, MAX_CLASS_NAME_LEN, nullptr) ||
      !IsEqualGUID(deviceClass, GUID_DEVCLASS_MEDIA)) return false;
  HDEVINFO devices = SetupDiCreateDeviceInfoList(&deviceClass, nullptr);
  if (devices == INVALID_HANDLE_VALUE) return false;
  SP_DEVINFO_DATA created{}; created.cbSize = sizeof(created); bool newDevice = false;
  if (!HasDevice()) {
    const wchar_t multiId[] = L"ROOT\\LocalistAudio\0";
    newDevice = SetupDiCreateDeviceInfoW(devices, className, &deviceClass,
        L"Localist Virtual Microphones", nullptr, DICD_GENERATE_ID, &created) &&
      SetupDiSetDeviceRegistryPropertyW(devices, &created, SPDRP_HARDWAREID,
          reinterpret_cast<const BYTE*>(multiId), sizeof(multiId)) &&
      SetupDiCallClassInstaller(DIF_REGISTERDEVICE, devices, &created);
    if (!newDevice) { SetupDiDestroyDeviceInfoList(devices); return false; }
  }
  BOOL reboot = FALSE;
  const bool updated = UpdateDriverForPlugAndPlayDevicesW(nullptr, kHardwareId,
      inf.c_str(), INSTALLFLAG_FORCE | INSTALLFLAG_NONINTERACTIVE, &reboot) != FALSE;
  if (!updated && newDevice) SetupDiCallClassInstaller(DIF_REMOVE, devices, &created);
  SetupDiDestroyDeviceInfoList(devices);
  if (!updated) return false;
  const std::wstring path(published);
  // A previous installation must never remove a newer installation's device.
  if (!SaveOwner(directory, path.substr(path.find_last_of(L"\\/") + 1))) return false;
  if (reboot) { SetLastError(ERROR_SUCCESS_REBOOT_REQUIRED); return true; }
  const bool available = GetLocalistMicrophoneStatus().available;
  if (available) SetLastError(ERROR_SUCCESS);
  return available;
}

bool RemoveLocalistMicrophones(const std::wstring& directory) {
  if (_wcsicmp(ReadOwner(L"Directory").c_str(), directory.c_str()) != 0) return true;
  HDEVINFO devices = SetupDiGetClassDevsW(&GUID_DEVCLASS_MEDIA, nullptr, nullptr, 0);
  if (devices == INVALID_HANDLE_VALUE) return false;
  SP_DEVINFO_DATA device{}; device.cbSize = sizeof(device); bool ok = true;
  // Walk backwards because removal can compact the device list.
  std::vector<SP_DEVINFO_DATA> owned;
  for (DWORD index = 0; SetupDiEnumDeviceInfo(devices, index, &device); ++index)
    if (IsOurDevice(devices, device)) owned.push_back(device);
  for (auto it = owned.rbegin(); it != owned.rend(); ++it)
    ok = (SetupDiCallClassInstaller(DIF_REMOVE, devices, &*it) != FALSE) && ok;
  SetupDiDestroyDeviceInfoList(devices);
  const auto inf = ReadOwner(L"Inf");
  if (ok && PublishedInfName(inf))
    ok = SetupUninstallOEMInfW(inf.c_str(), 0, nullptr) != FALSE;
  if (ok) RegDeleteKeyExW(HKEY_LOCAL_MACHINE, kOwnerKey, KEY_WOW64_64KEY, 0);
  return ok;
}
