# Localist Developer Bridge — Technical Feasibility

## Current constraints and evidence

- Official Windows ADB is installed (Platform-Tools 37.0.0).
- The Windows hotspot network was previously observed at `192.168.172.0/24` with the PC's gateway on that network. No current Android ADB device is enumerated.
- A previous Galaxy A52 / Android 14 Localist debug APK was installed, but the phone is not attached to ADB now.
- No `adb tcpip`, `adb usb`, phone settings change, or ADB connect attempt has been run in this turn.
- `flutter analyze --no-pub` passes for the changed Dart files and model test. `flutter test --no-pub test/developer_bridge_models_test.dart` passes all six tests.
- The current-source Windows Debug build completed successfully after stale `LocalistRemote.exe` child processes released `WebView2Loader.dll`; the `Localist` window is running and responsive.

## Platform feasibility

| Scenario | Android prerequisite | Localist/RustDesk role | Status |
|---|---|---|---|
| Phone hotspot, no cable | Android must expose an authorized ADB TCP endpoint. Android's documented no-cable workflow is Wireless debugging, enabled on the phone, with phone and workstation on the same Wi-Fi network. | ADB on Windows can connect only after that endpoint exists. A hotspot association alone does not start `adbd`. | **BLOCKED under current phone settings** |
| Legacy `adb tcpip` without Wireless debugging | Android's documented flow requires an initial USB connection to run `adb tcpip 5555`. | Not allowed by the user's no-cable requirement. | **NOT AN OPTION** |
| RustDesk over Internet | An ADB TCP endpoint must already be listening on the Android device and reachable by the RustDesk host process. | RustDesk forwards the TCP stream; it does not enable Android debugging or create `adbd`. | Tunnel UI implemented; ADB endpoint absent/untested |
| Android Studio install/Run/debug | ADB must authenticate to Android's system `adbd`. | RustDesk can transport the endpoint but cannot substitute for it. | **NOT TESTED** |

Android's official ADB instructions state that Android 11+ Wireless debugging requires the workstation and device on the same wireless network. The documented legacy TCP/IP flow starts by connecting USB and running `adb tcpip 5555`. See [Android Debug Bridge](https://developer.android.com/tools/adb).

## RustDesk and application sandbox

The project already contains the desktop `port-forward` session and a loopback listener. The Developer Bridge now launches that session and gives the user the mapping fields. Source inspection proves that a generic TCP tunnel exists. It does not prove that a phone-side ADB endpoint exists, that the Android host can reach it, or that ADB auth/install/debug works through the tunnel.

## Results

- Targeted Flutter analysis: **PASS**.
- Model tests: **PASS**, six tests.
- Current no-cable local ADB endpoint: **not available**. This run had empty `adb devices -l` and `adb mdns services`; the phone hotspot gateway rejected TCP port 5555. The screen explains why and accepts a user-provided active endpoint.
- Current RustDesk Internet ADB path: **NOT TESTED** because no phone-side ADB endpoint is available under the stated constraints.
- Android build/install and Android Studio Run/Logcat/debugger: **NOT TESTED** in this turn.
- The user must choose an Android-supported way to expose `adbd` before either transport can work. Localist will not bypass Android's authorization or sandbox.

