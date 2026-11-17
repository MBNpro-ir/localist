# Developer Bridge V2 — Stage 2 Android Agent

Date: 2026-11-17

## Implemented

- The Android Developer Agent serves a versioned, length-prefixed application protocol over TLS. Pairing uses a short-lived code, HMAC challenge response, and a SHA-256 certificate pin.
- The app exposes the session listener only while the user has started the Agent and Localist remains open. The UI shows the session's IPv4 endpoints, pairing code, certificate pin, and received APK metadata.
- APK transfer is bounded, SHA-256 checked, parsed with Android's package archive API, and reported as a receive/validation result. It does not silently install or launch anything.
- Installation is an explicit user action. Localist opens Android's unknown-app-source settings when needed and then opens the system Package Installer. Android's own confirmation screen remains required.
- Closing a session now has an acknowledgement. Android frees its single-session slot before replying `session.closed`, which makes reconnect deterministic. The Dart reader subscription is cancelled during close.
- The Windows-side Local LAN adapter shares the protocol implementation with the RustDesk transport adapter. Latest emulator runs passed both adapter harnesses through local port forwarding; a real RustDesk peer session is still required to prove Internet transport.
- Session errors are now logged with a `LocalistDevAgent` tag and surfaced in the Agent page instead of being overwritten by the following disconnect event.

## Verification evidence

### Android Agent protocol on emulator

Device: `Pixel_9a_Android36` / `emulator-5554`, Android API 36, x86_64. No physical phone or USB connection was used.

For this emulator-only test, `adb forward` exposed the guest listener to a Windows loopback port. This is test plumbing, not a phone-side USB or Wireless Debugging requirement.

The repeatable harness `tools/developer_agent_transport_poc.dart` passed:

1. Wrong TLS certificate pin was rejected by certificate verification.
2. Wrong pairing code was rejected after TLS handshake.
3. Correct code and certificate authenticated.
4. Echo payload round-tripped unchanged.
5. A real debug APK was transferred and Android returned package name, version, size, and SHA-256 metadata.
6. Session disconnect completed, and an immediate second authenticated session echoed successfully.

The latest repeatable run passed all seven checks: wrong TLS pin rejection, wrong pairing code rejection, authenticated session, Echo, APK transfer and package validation, disconnect, and reconnect. A previous run had failed during APK transfer after the host ADB server restarted; that historical failure is retained here, but the latest complete run passed.

### Install and launch

- The Agent transferred the debug APK and validated it as `com.prs.localist`, version `7.3.2` (version code `2079`).
- The first install request correctly opened Android Settings to enable installs from Localist. After enabling it on the emulator, the Agent opened the OS Package Installer.
- Android displayed `Update this app?`; the update was confirmed. The installer displayed `App updated`, and Package Manager continued to report the expected package/version.
- Localist was launched from the Android launcher/monkey command and its main activity appeared. Install verification through the Agent's in-page button and the Agent's own launch/process buttons were not completed after the OS update restarted its process.

### Build and static analysis

- `flutter build apk --debug --no-pub` completed successfully, and the APK was installed on the emulator.
- `dart analyze tools/developer_agent_transport_poc.dart lib/services/developer_agent_transport.dart lib/screens/android_developer_agent_page.dart` reported no issues.
- `pubspec.lock` SHA-256 remained `E2D8C0C46305E3343AF32C9420AC1E4E7F6D15E3B93B8E9AAC6C7B6EED9A1C5D`.

## Not established

- A real Android phone connected to the phone's hotspot was not available for testing. Emulator loopback forwarding does not prove the hotspot path.
- Internet transport through RustDesk was not exercised end to end. The Android build of RustDesk and its remote TCP port-forward behavior still require a live session test.
- Android Studio does not treat the Virtual ADB endpoint as a deployable device: it enumerates the endpoint but reports no provisioner and fails shell/JDWP requests. APK install and app launch therefore use the Android Developer Agent directly, not standard Android Studio deployment/debugging.
- Full ADB, Logcat, JDWP, and JVMTI debugging were not established. The Agent can expose its own limited status and session events; it does not claim system-level access.

See [Internet/RustDesk status](12_V2_INTERNET_RUSTDESK_STATUS.md) for current transport evidence and the separate Internet acceptance gate.

## Next repeatable run

1. Keep Localist open on the emulator and start **Android Developer Agent**.
2. Read its current endpoint, code, and fingerprint from the Agent page.
3. For the emulator only, forward the displayed guest port with `adb -s emulator-5554 forward tcp:50011 tcp:<agent-port>`.
4. Run `dart run tools/developer_agent_transport_poc.dart 127.0.0.1 50011 <pairing-code> <certificate-sha256> build/app/outputs/flutter-apk/app-debug.apk`.
5. If APK transfer succeeds, use the Agent page to verify installation and launch the package. Record the Android activity/process result separately from ADB enumeration.
