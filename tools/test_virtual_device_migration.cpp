// Exercise legacy camera-count migration against isolated registry fixtures.
// No camera DLL is loaded and no production device registration is changed.
#define LOCALIST_CAMERA_VERSION L"migration-test"
#include "../windows/runner/virtual_devices.cpp"
#include <iostream>

int wmain() {
  const auto key = L"Software\\Localist\\DeviceMigrationQA-" +
      std::to_wstring(GetCurrentProcessId());
  HKEY fixture = nullptr;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, key.c_str(), 0, nullptr, 0,
      KEY_ALL_ACCESS, nullptr, &fixture, nullptr) != ERROR_SUCCESS) return 1;
  if (RegOverridePredefKey(HKEY_LOCAL_MACHINE, fixture) != ERROR_SUCCESS) {
    RegCloseKey(fixture); RegDeleteTreeW(HKEY_CURRENT_USER, key.c_str()); return 2;
  }
  bool ok = true;
  const std::wstring directory = L"C:\\Localist migration fixture";
  auto require = [&](bool value) { ok = value && ok; };
  auto set = [&](int slot, bool x64, const std::wstring& owner) {
    HKEY camera = nullptr;
    const auto path = owner + L"\\" + LocalistCameraFileName(x64, slot);
    if (RegCreateKeyExW(HKEY_LOCAL_MACHINE, CameraKey(slot).c_str(), 0, nullptr, 0,
        KEY_SET_VALUE | (x64 ? KEY_WOW64_64KEY : KEY_WOW64_32KEY), nullptr,
        &camera, nullptr) != ERROR_SUCCESS) { require(false); return; }
    require(RegSetValueExW(camera, nullptr, 0, REG_SZ,
        reinterpret_cast<const BYTE*>(path.c_str()),
        static_cast<DWORD>((path.size() + 1) * sizeof(wchar_t))) == ERROR_SUCCESS);
    RegCloseKey(camera);
  };
  require(InstalledLocalistCameraCount(directory) == 0);
  for (int slot = 0; slot < 4; ++slot) {
    for (bool x64 : {true, false}) set(slot, x64, directory);
    require(InstalledLocalistCameraCount(directory) == slot + 1);
  }
  require(InstalledLocalistCameraCount(L"C:\\Other installation") == 0);
  for (int slot = 2; slot < 4; ++slot)
    for (bool x64 : {true, false}) set(slot, x64, L"C:\\Other installation");
  require(InstalledLocalistCameraCount(directory) == 2);
  // A partially registered highest slot must be preserved for repair as well.
  set(3, true, directory);
  require(InstalledLocalistCameraCount(directory) == 4);
  RegOverridePredefKey(HKEY_LOCAL_MACHINE, nullptr);
  RegCloseKey(fixture);
  require(RegDeleteTreeW(HKEY_CURRENT_USER, key.c_str()) == ERROR_SUCCESS);
  if (ok) std::cout << "DEVICE_MIGRATION_OK: empty, 1-4 slots, ownership and partial registration preserved\n";
  return ok ? 0 : 3;
}
