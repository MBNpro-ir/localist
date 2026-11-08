#ifndef RUNNER_ELEVATED_STARTUP_H_
#define RUNNER_ELEVATED_STARTUP_H_
#include <string>

// Per-user interactive logon task. No password or UAC-policy changes are stored.
bool ConfigureElevatedStartup(bool enabled, const std::wstring& executable,
                              const std::wstring& test_suffix = L"");
bool IsElevatedStartupEnabled(const std::wstring& executable,
                              const std::wstring& test_suffix = L"");
bool IsLocalistProcessElevated();
bool MigrateLegacyLocalistStartup(const std::wstring& executable);
#endif
