> Superseded by [6.0.0 validation](VALIDATION_6.0.0.md). Correction: the current Windows DLL has software codecs (`flutter` only), not `hwcodec/vram`. A refused HTTP API on 21114 is not a session-connectivity blocker. Real protocol/session tests are recorded in the newer report.

# Localist 5.0.11 validation

Validation was run on Windows 11 with the bundled Localist engine and on the
`localist-api35-qa` Pixel 5 Android 15 API 35 x86_64 emulator. The installed
official RustDesk client was left running and was not used as a fallback.

## Automated checks

- `dart analyze`: clean.
- `flutter test --no-pub`: 61 tests passed.
- `python tools/verify_remote_runtime.py`: 25 engine, dependency and source
  files verified.
- `python tools/check_remote_exports.py`: 317 bridge exports present.
- `python tools/verify_remote_apk.py`: Debug and arm64, armeabi-v7a and x86_64
  release APKs contain the expected native engine, JNI types and C++ runtime.
- Windows Debug build completed with software codecs. Android Debug build completed.

## Runtime checks

The Android Release APK launched with fresh Localist UI, showed the Remote
Control destination, opened the embedded engine, and displayed the local ID
card. The card has separate Copy ID and Copy password controls, a smart Copy
connection action, and an explicit Paste & connect action. The smart payload is
parsed in tests with percent-encoded passwords, labelled ID/password text,
malformed links and unsafe values. Clipboard parsing never starts a session by
itself.

The Android native Share screen reached Ready after the user-approved
MediaProjection flow. The actual emulator accessibility service was enabled and
the native callback reported input permission. The Windows credential command was exercised against the packaged `LocalistRemote.exe`; the bundled host stayed alive and connected to the configured rendezvous endpoint. The server HTTP API probe on 21114 refused the connection. This did not establish a fault in desktop/file session connectivity; those protocols were not tested in that earlier run.

## Scope limits

The Android check is emulator evidence, not acceptance on a physical Android or
iPhone. No physical TV, console, Miracast receiver, Windows driver installation,
audio capture, unattended access, or real cross-device session was claimed from
this run. Windows hardware codec acceleration is not compiled into the packaged DLL. Server, relay, firewall,
OS permissions and device drivers can still affect individual RustDesk features.

