#include "../windows/runner/virtual_audio_driver.h"
#include <iostream>

int wmain(int argc, wchar_t** argv) {
  if (argc != 2) return 2;
  const auto before = GetLocalistMicrophoneStatus();
  // The harness supplies an unsigned fixture only. No UAC or signature bypass.
  if (InstallLocalistMicrophones(argv[1])) return 3;
  if (!RemoveLocalistMicrophones(L"Z:\\Localist-NonOwning-QA-Copy")) return 4;
  const auto after = GetLocalistMicrophoneStatus();
  if (before.installed != after.installed || before.available != after.available) return 5;
  std::cout << "LOCALIST_AUDIO_UNSIGNED_NATIVE_INSTALL_REJECTED_NO_DEVICE_CHANGES\n";
  return 0;
}
