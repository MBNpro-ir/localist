# Localist 6.0.4+66 validation

Validated on Windows on 2026-10-12. This release changes Windows session dispatch,
hidden-host window callbacks, saved-device layout and native peer presence.

## Automated and build evidence

- `flutter analyze --no-pub`: no issues.
- The new upstream-package hidden-host handler was also analyzed explicitly
  because the root analyzer excludes vendored source: no issues.
- `flutter test --no-pub`: all 102 tests passed. Added coverage includes
  authenticated loopback dispatch for every session mode, malformed/oversized
  requests, browser-origin rejection, serialized creation and failure recovery
  without replay, real hide/show method-channel callbacks, presence expiry,
  server-change invalidation, offline versus unknown, network failures,
  normalized IDs, full-width multicolumn layout, bounded pagination, view
  persistence and 360px layouts with 2x text in light/dark themes.
- Windows x64 Debug and Android Debug APK builds passed.
- `tools/verify_remote_runtime.py`: all 25 pinned files verified.
- `tools/check_remote_exports.py`: all 317 native bridge exports present.
- `tools/verify_remote_apk.py`: final Debug APK native engines, C++ runtime and
  JNI types verified for ARM32, ARM64 and x86_64.

Command logs and sanitized runtime reports are in `.runlogs/` (ignored by Git).
Existing CMake policy and Kotlin migration warnings did not prevent either build.

## Live runtime checks

The updated Windows Debug hidden host initialized and registered with the
configured server. Four read-only presence commands over 12 seconds returned
initially unknown states followed by genuine native online/offline responses.
ID `183976` was online in all three subsequent samples; the two queried phone
IDs were offline. The same host PID remained alive, native registration stayed
active (`statusNum: 1`) and the atomically replaced status file stayed fresh
(under one second old). No session or standalone home window was opened by
these probes. The command token was omitted from logs and this report.

## Acceptance limits

No Computer Use test was performed. A real remote screen connection, subsequent
session close/reopen, additional monitors and file-transfer session windows
still require two-device acceptance testing. The old intermittent crash had no
captured stack trace: this change removes per-click native process dispatch and
restores the omitted host callbacks; build/test/presence results alone do not
prove that every possible native session crash is resolved.

The user's server and phone settings were not changed. The native engine, relay
configuration, consent and permissions remain in use; a successful presence
query establishes server reachability, not an approved remote-control session.
