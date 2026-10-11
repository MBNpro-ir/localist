# Localist 6.0.3+65 validation

Validated on Windows on 2026-10-11. This release changes Android permission
management, incoming remote approval, return from sessions, Windows startup
registration, scoped VPN elevation and remote IPC initialization recovery.

## Automated and build evidence

- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub`: 88 tests passed. New cases cover denial and revocation,
  all three Welcome requests despite a denial, concurrent permission requests,
  incoming Accept/Decline/password sharing, closing only the session Activity,
  private/public relay selection, and PowerShell worker parsing and failure
  reporting with untrusted arguments treated as data.
- Windows x64 Debug build and Android Debug APK build passed.
- `tools/verify_remote_runtime.py`: all 25 pinned runtime files verified.
- `tools/check_remote_exports.py`: all 317 bridge exports present.
- `tools/verify_remote_apk.py` verified the final Debug APK's native engine, C++
  runtime and JNI types for ARM32, ARM64 and x86_64.

Local command logs are in `.runlogs/` (ignored by Git). CI performs analysis,
tests, signed ARM32/ARM64 release builds and Windows release packaging.

## Runtime and machine checks

- A headless Android API 35 emulator loaded Flutter, initialized the native/global
  FFI once, and bound the foreground listening `MainService` without enabling
  capture. No fatal Android/Flutter startup error was observed in that check.
- Read-only inspection of the connected API 36 phone showed Android restricting
  sideloaded access (`ACCESS_RESTRICTED_SETTINGS: ignore`). The app now explains
  how the user can allow restricted settings; the phone was not modified.
- On this Windows account, the installed Run entry was valid but
  `StartupApproved\Run\Localist` was disabled. The approval state was repaired
  to enabled, preserving the installed application path.
- The Windows manifest remains `asInvoker`. Generic whole-app elevation was
  removed; routing is delegated to a scoped elevated worker.

## Acceptance limits

No Computer Use test was performed. Real incoming approval/screen transmission
between two devices, return from a real remote session, actual UAC/VPN routing,
and launch after a Windows reboot still require device acceptance testing.
Automated tests, APK inspection and the emulator startup check do not establish
those behaviors on a physical phone. The user's server was not changed.

Private ID/relay settings automatically force relay. Clearing private settings
selects the native public servers; a private-server ID is not retried against an
unrelated public server namespace.
