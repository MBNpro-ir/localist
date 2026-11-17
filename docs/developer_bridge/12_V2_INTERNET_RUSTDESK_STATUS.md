# Developer Bridge V2 — Internet / RustDesk Status

Date: 2026-11-17

## Internet path is the primary Windows flow

The Developer Bridge page now opens on **Internet / RustDesk**. The visible sequence is:

1. Keep Localist open on Android and start **Android Developer Agent**.
2. Enter the phone's RustDesk ID and session password on Windows, then open the network tunnel.
3. RustDesk creates the mapping `Windows 127.0.0.1:15555` → `Android 127.0.0.1:48291`.
4. Approve that exact tunnel destination on the Android consent prompt.
5. Enter the current 8-digit Agent pairing code and TLS SHA-256 fingerprint on Windows; connect and run Echo before transferring an APK.
6. On Android, approve installation in Package Installer. Android does not grant Localist silent-install privileges.

The Android Agent listener uses a stable port `48291`, TLS, certificate pinning, a short-lived pairing code, and HMAC authentication. The listener starts only after the user presses **Start Agent** and the app remains open. Both Local LAN and RustDesk use the same application protocol and the same APK validation path.

## RustDesk support inspection

Inspection of the bundled RustDesk native source and Localist Android host confirms the required TCP-tunnel pieces exist:

- The Windows port-forward listener is created on `127.0.0.1`, so the Android Agent is not exposed on other Windows interfaces.
- The Android side connects the requested target host/port after the RustDesk tunnel is accepted.
- Localist Android displays the requested target and requires explicit user approval.
- Localist validates the Developer Bridge target as loopback and rejects arbitrary destination hosts.
- Reopening a RustDesk port-forward tab now reapplies the initial Developer Agent mapping to the existing tab instead of silently ignoring the new route.

This is source-level support evidence. It is not a live Internet-session result.

## Reproducible checks completed

### Android Agent on emulator

Device: `emulator-5554`, Android API 36, x86_64. The Agent was started from its Android UI and reported `*:48291` listening. No physical phone or USB cable was used.

`tools/developer_agent_transport_poc.dart` passed through emulator-only `adb forward`:

- wrong TLS pin rejected;
- wrong pairing code rejected;
- authenticated TLS session and Echo passed;
- APK transferred and parsed by Android, returning package metadata and SHA-256;
- disconnect and immediate reconnect passed.

### RustDesk transport adapter

`tools/developer_agent_rustdesk_transport_poc.dart` passed through emulator-only `adb forward tcp:15555 tcp:48291`:

- `RustDeskRemoteTransport` connected to the same loopback port RustDesk exposes on Windows;
- TLS pin and pairing passed;
- Echo passed;
- APK transfer and Android package validation passed;
- disconnect and reconnect passed.

This forward was test plumbing standing in for RustDesk's local listener. It proves the adapter's protocol and port behavior, not the RustDesk peer/relay path over the Internet.

Repeat on an emulator while the Agent is running:

```powershell
adb -s emulator-5554 forward --no-rebind tcp:15555 tcp:48291
dart run tools/developer_agent_rustdesk_transport_poc.dart 15555 <pairing-code> <certificate-sha256> build/app/outputs/flutter-apk/app-debug.apk
adb -s emulator-5554 forward --remove tcp:15555
```

For an actual Internet acceptance run, use a physical Android phone reachable by its RustDesk ID, approve its tunnel prompt, then run Echo and transfer an APK from the Windows page. Do not use the ADB-forward command for that acceptance result.

## Independent acceptance matrix

| Capability | Result | Evidence / limit |
| --- | --- | --- |
| Official ADB enumerates the synthetic Localist endpoint | PASS | Stage 1 ADB 1.0.41 integration evidence in `10_V2_STAGE1_VIRTUAL_ADB.md` |
| Android Studio recognizes it as a deployable phone | FAIL | Android Studio 2026.2.1 sees the transport but reports no provisioner; shell and JDWP services are not available |
| Android Agent listener and authenticated Echo | PASS on emulator | API 36 emulator; not a hotspot or Internet test |
| APK transfer and package validation | PASS on emulator | Android returned real package metadata and SHA-256 |
| APK installation | PASS with OS confirmation on emulator | Package Installer was used; no silent installation |
| Agent-side install verification/launch buttons | NOT VERIFIED in latest session | Package verification and process reporting are implemented but these specific controls were not exercised after install |
| Real Android Logcat | NOT IMPLEMENTED | Only Agent/session events and permitted app status are exposed |
| JDWP debugger / breakpoint / step | NOT IMPLEMENTED | No system debugger access; JVMTI PoC remains separate research |
| Phone hotspot with Windows connected to that hotspot | NOT TESTED | Requires the user's physical phone and hotspot network |
| RustDesk tunnel over a real Internet peer or relay | NOT TESTED | Adapter mock passed; real RustDesk Android↔Windows session remains the priority live test |

## Windows runtime status

- The final Windows Dart bundle builds successfully, including the Internet-first page and the reused-tab tunnel fix; its kernel SHA-256 matches the isolated runtime bundle.
- Windows UAC was approved and the isolated `Localist` runtime started. This confirms the desktop process launches; it does not confirm an end-to-end RustDesk tunnel or Android Studio recognition.
- The normal runner output still contains mapped Flutter assets from an existing Localist Remote process, and the native build previously failed while replacing the locked `WebView2Loader.dll`. The isolated runtime avoids changing that active output.
- A full Windows UI click-through and a successful physical-phone RustDesk Agent handshake remain unverified. A prior tunnel attempt created a local forward listener, but the Agent TLS handshake terminated; a later retry was refused because the listener was no longer active.

Before creating the requested review branch, no other push, PR, release, or remote publication was performed.
