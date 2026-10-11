# Localist 6.0.1 validation

Version: `6.0.1+63`. Validation uses Windows builds, automated Flutter tests,
native updater fixtures and a headless Android API 35 emulator. Computer Use
and desktop UI automation were not performed, as requested.

## Changes checked

- Automatic update checks and settings share one preparation controller.
  Downloads use partial files, expected asset size and available GitHub SHA256
  digests. Completed Windows staging checks the app, updater, remote engine,
  Flutter DLL and bundled version before allowing restart. Cached incomplete
  staging is rebuilt. Android installation remains subject to OS consent.
- The actual native Windows updater waits for the old process, copies a
  backed-up bundle and relaunches the new executable. Its test uses temporary,
  windowless fixture executables in both archive and prepared-bundle modes.
  Existing installed Localist and official clients are not replaced by this test.
  Rollback after a failed copy is implemented but not fault-injected in this run.
- Server configuration enables relay when any private-server field is populated,
  including the supplied ID/relay server `81.30.108.248`. The API field remains
  empty by default. The user identified relay being disabled as the cause of the
  reported `183976` lookup error. No server configuration or credentials were changed.
- Upstream native display toggles use an empty value for off. The previous `N`
  value enabled presence-based options, including mouse-button swapping. The
  profile encoder and legacy peer options now use the correct representation.
- Temporary passwords are used when no permanent password exists. The initial
  approval mode and a one-time profile migration allow either a password or
  manual Accept. An explicitly chosen password-only mode explains its behavior.
  The incoming connection manager now shows, restores and focuses its window.
  Session latency and actual Accept interaction were not measured in this run.
- Printer choices come from the native Windows printer enumerator. Empty lists
  and removed printers are handled. Real remote printing is not validated here.
- The persistent local Address Book retains custom names, tags and favorites;
  search, combined filters, ordering, direct card connection and exclusion of
  the current device have automated coverage. Cloud/Pro address-book sync is
  not implemented by this local Address Book.
- The animated Ready state uses native registration/hosting state and selected
  server. Copy notices use Localist's bottom in-app notification. Update notices
  open `SettingsSection.updates`.
- Relaunch routes to the existing HWND and Dart tray restore handler without
  showing the previous modal. Its native code is compiled; foreground and tray
  behavior remain a manual acceptance check.
- Abnormal-exit handling, window-creation failure and Flutter crashes never
  enable Debug. Running a Debug build also preserves the user-selected setting.
  The crash regression test verifies that fatal error reporting does not change
  preferences or invoke native dialogs/mail. Previously saved manual preferences
  are preserved; an existing enabled value is not forcibly reset.

## Automated and build evidence

- Flutter analyzer: no issues.
- Flutter tests: 78 passed on Windows, including actual native FFI access,
  updater HTTP download/cache/integrity/staging, Address Book persistence and
  responsive widgets, relay defaults, approval migration, and crash preferences.
- Windows Debug and Release and Android Debug and split Release builds are
  checked for this version. Android Debug is installed and launched on the
  headless API 35 x86_64 emulator.
- Pinned runtime/source manifest: 25 files verified. Native engine binaries and
  their corresponding-source archive are unchanged in this release.
- Native bridge exports: 317 checked, none missing.
- Both native updater fixture modes passed parent-process wait, installed-file
  replacement, user-file/log preservation and relaunch with the requested version.
- Android Debug and all three Release APKs passed archive integrity, packaged
  engine/C++/Flutter library and retained JNI-type verification.

Build and test logs remain in the ignored `.runlogs` directory. Tests for this
patch do not establish new physical-device interoperability or visual acceptance.
The real Localist/official-client interoperability results in
[6.0.0 validation](VALIDATION_6.0.0.md) belong to that earlier version. Printing,
elevated control, physical-device sessions and any reported connection latency
still need user/device acceptance tests.
