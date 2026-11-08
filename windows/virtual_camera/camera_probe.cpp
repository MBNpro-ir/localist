#include <windows.h>
#include <fstream>
#include <string>
#include <vector>
#include "webrtc_virtual_camera.h"
extern "C" int LocalistVirtualCameraSetTexture(int64_t, int);
extern "C" uint64_t LocalistVirtualCameraFrames();

int wmain(int argc, wchar_t** argv) {
  if (argc != 3) return 1;
  const std::wstring command = argv[1];
  if (command == L"--register" || command == L"--unregister") {
    // QA uses HKCU only; production registration is independently exercised by
    // the elevated app. Never override an existing per-user Localist filter.
    HKEY classes = nullptr;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, L"Software\\Classes", 0, nullptr, 0,
        KEY_ALL_ACCESS, nullptr, &classes, nullptr) != ERROR_SUCCESS) return 2;
    HKEY existing = nullptr;
    if (command == L"--register" && RegOpenKeyExW(classes,
        L"CLSID\\{58BC2225-E9D9-4BB9-A460-6630C82A5301}", 0, KEY_READ, &existing) == ERROR_SUCCESS) {
      RegCloseKey(existing); RegCloseKey(classes); return 3;
    }
    if (RegOverridePredefKey(HKEY_CLASSES_ROOT, classes) != ERROR_SUCCESS) { RegCloseKey(classes); return 4; }
    HMODULE dll = LoadLibraryW(argv[2]);
    if (!dll) { RegOverridePredefKey(HKEY_CLASSES_ROOT, nullptr); RegCloseKey(classes); return 5; }
    using Registration = HRESULT(STDAPICALLTYPE*)();
    const auto entry = reinterpret_cast<Registration>(GetProcAddress(dll,
        command == L"--register" ? "DllRegisterServer" : "DllUnregisterServer"));
    const HRESULT result = entry ? entry() : E_FAIL;
    FreeLibrary(dll); RegOverridePredefKey(HKEY_CLASSES_ROOT, nullptr); RegCloseKey(classes);
    return SUCCEEDED(result) ? 0 : 6;
  }
  if (command != L"--produce") return 7;
  const int width = 640, height = 480;
  std::vector<uint8_t> y(width * height, 81), u(width * height / 4, 90), v(width * height / 4, 240);
  auto frame = libwebrtc::RTCVideoFrame::Create(width, height, y.data(), width, u.data(), width / 2, v.data(), width / 2);
  if (!frame || LocalistVirtualCameraSetTexture(42, 30) != 1) return 8;
  for (int i = 0; i < 450; ++i) { LocalistVirtualCameraFrame(42, frame); Sleep(33); }
  const auto count = LocalistVirtualCameraFrames();
  LocalistVirtualCameraSetTexture(-1, 30);
  std::ofstream output(argv[2]); output << "{\"publishedFrames\":" << count << ",\"stopped\":true}";
  return count > 400 ? 0 : 9;
}
