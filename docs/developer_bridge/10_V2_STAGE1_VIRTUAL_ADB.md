# Developer Bridge V2 — Stage 1 Evidence

## Result

**ADB transport enumeration: PASS. Android Studio run-device compatibility: FAIL (expected at this stage).**

Localist now has a synthetic ADB device endpoint in its Windows process. It binds to an ephemeral `127.0.0.1` TCP port only, completes the initial ADB `CNXN` exchange, advertises a clearly synthetic Localist identity, and explicitly closes unsupported ADB `OPEN` streams. It does not expose a phone, shell, package install, logcat, file sync, JDWP, or debugger service.

This proves that official Platform-Tools can enumerate a transport. It does **not** prove that Android Studio can deploy to or debug a phone through it.

## Repeatable integration check

From the project root, with Windows Android SDK Platform-Tools installed:

```powershell
dart run tools/virtual_adb_endpoint_poc.dart --self-test
```

The check starts a loopback endpoint, calls the installed official `adb.exe` using its normal shared server, verifies the device state in `adb devices -l`, asks for a shell service and verifies that ADB reports `closed`, then disconnects the endpoint. It never runs `adb kill-server` and never changes a phone setting.

Successful output from this machine:

```text
PASS adb connect: 127.0.0.1:<ephemeral-port>
PASS adb devices -l: device state
PASS unsupported shell rejected and recorded
PASS adb disconnect: session cleanup
```

## Live Windows / Android Studio evidence

- Official ADB: `Android Debug Bridge version 1.0.41`, `Version 37.0.0-14910828`.
- Localist Windows Debug build: `build/windows/x64/runner/Debug/Localist.exe` built and launched. The app requested elevation because its existing manifest is `requireAdministrator`; it was launched after Windows approval.
- APK build: `build/app/outputs/flutter-apk/app-debug.apk` built successfully after moving the already-configured, Android-group-filtered Aliyun Google Maven mirror ahead of `google()`. In this environment Google Maven returned HTTP 404 for cached AndroidX AAR URLs.
- Windows Localist listened on `127.0.0.1:62010`; `Get-NetTCPConnection` attributed that listener to the running `Localist` process.
- `adb devices -l` reported `127.0.0.1:62010 device product:localist model:Localist_Virtual device:localist`.
- `adb -s 127.0.0.1:62010 get-state` returned `device`.
- `adb -s 127.0.0.1:62010 shell getprop ro.product.model` returned `error: closed`; the endpoint recorded and rejected `shell:getprop ro.product.model`.
- `adb install -r build/app/outputs/flutter-apk/app-debug.apk` failed with `connect failed: closed` and a nonzero exit. No APK was installed by the Virtual ADB endpoint.
- Android Studio installed on this machine is `2026.2.1` (`AI-262.9437.185.2621.16467767`). Its live `idea.log` records the endpoint as “has come online” and “Offering 127.0.0.1:62010”, then “Device ... not claimed by any provisioner”. It also records failures for `shell:echo foo` and `track-jdwp`. Thus Android Studio sees the ADB transport but does not accept it as a deployable/debuggable phone.
- Android Studio opened the Localist Android project and used the same machine ADB server. No server restart or port change was done by this PoC.

## Services observed

Android Studio 2026.2.1 attempted these device services on this PoC:

| Service | Purpose | PoC result |
| --- | --- | --- |
| `shell:echo foo` | Device responsiveness/provisioning probe | Explicitly closed |
| `track-jdwp` | Track debuggable VM processes | Explicitly closed |
| `shell:getprop ...` | Device metadata query | Explicitly closed |
| `sync:` / package install stream | APK push/install path | Explicitly closed; install fails |

The ADB server also exposes `host:track-devices-proto-binary` to Android Studio as a **host-side** service. That request is handled by the existing ADB server, not by the synthetic device endpoint.

## Protocol and security limits

The implementation follows AOSP's 24-byte little-endian message header and handles `A_CNXN`, `A_OPEN`, and stream closure for the enumeration-only proof. ADB 1.0.41 negotiates the skip-checksum protocol version. The listener is loopback-only and is not a remote tunnel endpoint.

ADB RSA `AUTH` and TLS `STLS` are deliberately not implemented yet. The transport is a synthetic, non-sensitive local proof device; it must not be exposed to LAN or RustDesk. The later Android Agent needs its own authenticated and encrypted application protocol, explicit on-device consent, and must not treat this PoC as a phone identity.

References:

- [AOSP ADB protocol](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/docs/dev/protocol.md)
- [AOSP ADB constants and protocol versions](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/adb.h)
- [AOSP ADB services](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/docs/dev/services.md)
- [AOSP ADB pipeline internals](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/docs/dev/internals.md)

## Follow-up status

Stage 1 remains an enumeration-only synthetic endpoint. Android Agent protocol, APK transfer, and the RustDesk adapter emulator checks are recorded separately in [Stage 2](11_V2_STAGE2_ANDROID_AGENT.md) and [Internet/RustDesk status](12_V2_INTERNET_RUSTDESK_STATUS.md). These later checks do not extend the synthetic ADB endpoint into a real phone or debugger.
