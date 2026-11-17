# Localist Developer Bridge — Repository Audit

## Scope and source identity

- Workspace: `D:\androidStudioProject\fluter\localist-master\localist-master`
- Source is the user-provided extracted tree. No `.git` directory is present, so branch, commit, and upstream freshness cannot be established locally.
- Before editing, a file-for-file baseline was copied to `D:\androidStudioProject\fluter\localist-master\_localist-master-original` (1,411 files, matching source file count).
- `pubspec.yaml` declares Localist `7.3.2+2079`, Dart `^3.12.0`. The README release badge still says `6.0.6`; treat that badge as stale rather than a source identity.

## Existing application architecture

- Flutter entry point and product navigation are in `lib/main.dart`. Windows and Android share the `LocalistShell`; page order and navigation items are assembled together.
- Feature UI follows `FeaturePageLayout`, `GlassBackground`, and `GlassPanel` in `lib/widgets/` and `lib/screens/`.
- Platform work is split between Dart services, Android `MainActivity.kt` MethodChannel handlers, and `windows/runner/windows_native_bridge.cpp`.
- Android's main MethodChannel is `com.prs.localist.vpn`. It already exposes LAN interface records, local-only hotspot controls, VPN/proxy, transfer, and OS-settings actions.
- Windows LAN interface discovery in `lib/services/lan_network_service.dart` uses a fixed PowerShell query and falls back to Dart interfaces. It reports IPv4 address, prefix and interface name; it does not identify the phone's ADB endpoint or guarantee that a gateway is the phone.
- `LocalistDiscoveryService` broadcasts Localist's own UDP discovery protocol. It discovers compatible Localist peers, not arbitrary Android ADB services.
- Existing pages and services cover Quick Send, VPN/proxy sharing, capture, streaming, remote desktop, file transfer, and remote connection settings. The Developer Bridge is appended only to Windows navigation; no unrelated feature flow was changed.

## ADB and Android integration

- Before this change, the app had no ADB process adapter, ADB endpoint model, or Developer Bridge screen.
- The new Windows adapter starts the user-selected `adb.exe` directly with structured arguments (`runInShell: false`). It searches `ANDROID_SDK_ROOT`, `ANDROID_HOME`, `%LOCALAPPDATA%\Android\Sdk`, then `PATH`; it does not download Platform-Tools.
- The Developer Bridge has a per-launch opt-in switch that defaults off. No ADB command runs before the user enables it; turning it off disconnects endpoints this page connected.
- The adapter implements explicit ADB version/device-list/connect/disconnect commands. It does not run `adb tcpip`, change Android settings, or accept Android system authorization prompts.
- Pairing code is passed through process stdin, not the command line, kept only for the operation, redacted from displayed diagnostics, and cleared from the UI after use.
- Endpoint parsing rejects malformed hosts, invalid ports, option-like leading hyphens, and shell metacharacters. No shell is involved.
- Android's existing manifest already includes `INTERNET`, `ACCESS_NETWORK_STATE`, and local-network-related entries for other app features. This Windows-only implementation adds no Android permission and no Kotlin bridge.
- Android `MainActivity.kt` includes LAN interface inspection and settings navigation, but no Android ADB daemon control or authorized ADB socket adapter.
- Android device authorization remains owned by Android/ADB. Localist only displays ADB's result and lets the user initiate commands.

## RustDesk and TCP forwarding

- `lib/services/rustdesk_debug_service.dart` already exposes a Windows `port-forward`/“Network tunnel” connection mode through the retained `LocalistRemote.exe` process.
- `third_party/localist_remote/lib/desktop/pages/port_forward_page.dart` starts an `FFI` session with `isPortForward: true` and calls `sessionAddPortForward`/`sessionRemovePortForward` for mappings.
- The pinned native source archive contains `src/port_forward.rs`: its Windows-side listener binds to `127.0.0.1`. `src/server/connection.rs` normalizes the requested target and opens a TCP stream to it; the multiplexed implementation checks that a channel target matches the authorized session target and checks the tunnel permission.
- This is evidence that the bundled engine contains a generic desktop-initiated TCP forwarding path. It is not evidence that an Android app process can reach the phone's active ADB daemon endpoint, or that ADB pairing/install/debug works through that path.
- The Android incoming session model already receives a `port_forward` target. Its consent path previously treated that request as screen sharing; it has been corrected to identify the target and avoid requesting screen capture/input for a network tunnel.
- No TCP echo proof, ADB handshake through RustDesk, relay test, remote install, or remote debugger session was available in this run.

## Authentication, credentials, and trust

- `RemoteCredentialStore` stores RustDesk peer passwords using `flutter_secure_storage`, scoped to the configured ID server and peer ID. The session password field is documented as not saved.
- Existing Android remote hosting asks the user to accept incoming sessions. Developer Bridge tunnel consent now displays the exact RustDesk tunnel target.
- RustDesk's `enable-tunnel` setting is present in Localist's remote-control settings. The remote path depends on the host's tunnel permission, session authentication, and user consent.
- No Google OAuth client ID, OAuth flow, Firebase authentication, or Developer Bridge device registry was found. The implementation does not create a cloud service or add a new identity provider.

## Error handling and logging

- The new ADB adapter maps common command outcomes to stable error codes, applies command timeouts, kills a timed-out process, and exposes command output only in the local diagnostics panel.
- It does not write ADB payloads, pairing codes, or private keys to Localist logs or preferences.
- Existing app logging is in `lib/services/log_service.dart`; the Developer Bridge avoids logging raw ADB output.
- The current screen is manually operated. It does not yet provide background monitoring, automatic reconnect, service lifecycle notifications, or exportable redacted diagnostics.

## Reusable components, gaps, and risks

| Area | Existing evidence | Status / risk |
|---|---|---|
| Windows interfaces | `LanNetworkService` returns IPv4/prefix/interface | Reusable context only; no gateway-to-phone inference |
| Localist peer discovery | UDP discovery and known devices | Does not discover ADB endpoints |
| Official ADB | Windows adapter, device list, and explicit endpoint connect/disconnect | Flutter analysis/model tests pass; no phone ADB endpoint is currently exposed |
| Wireless debugging | Not toggled or controlled by Localist | Android's documented no-cable ADB mode requires it and same Wi-Fi; user says it cannot be enabled in this setup |
| Legacy TCP/IP | Only connects to an endpoint already exposed by Android | Official legacy setup requires initial USB, which the user rules out |
| RustDesk tunnel | Existing Windows port-forward session launched from Developer Bridge | Carries an existing endpoint only; remote ADB remains unverified |
| Android tunnel consent | RustDesk client exposes a target string | Consent flow fixed; requires device regression test |
| Google account trust | No OAuth/configuration found | External product/service work would be needed; none is created |
| Windows build | Flutter project and runner exist | C++ toolchain was not found on PATH; Flutter Windows build unverified |
| Android build | SDK, Platform-Tools, Gradle distribution, Java and attached device exist | Flutter package cache is incomplete; offline dependency resolution fails |

## License inventory

- `third_party/localist_remote/LICENSE` is GNU AGPL-3.0. `UPSTREAM.json` pins RustDesk source version 1.5.1 and a native-source archive/bridge build. Redistribution or a source submission must preserve the license and notices and satisfy applicable corresponding-source obligations for distributed modified binaries