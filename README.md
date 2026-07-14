<p align="center">
  <img src="ico/logo.png" alt="Localist" width="112" />
</p>

<h1 align="center">Localist</h1>

<p align="center">
  Smart local VPN sharing and fast file transfer between Android and Windows.
</p>

<p align="center">
  <a href="README.fa.md">فارسی</a> | <strong>English</strong>
</p>

<p align="center">
  <a href="https://flutter.dev"><img alt="Flutter" src="https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white"></a>
  <a href="https://developer.android.com"><img alt="Android" src="https://img.shields.io/badge/Android-8.0%2B-3DDC84?logo=android&logoColor=white"></a>
  <a href="https://learn.microsoft.com/windows/apps/"><img alt="Windows" src="https://img.shields.io/badge/Windows-Desktop-0078D4?logo=windows&logoColor=white"></a>
  <a href="https://github.com/MBNpro-ir/localist/actions/workflows/release.yml"><img alt="Release" src="https://github.com/MBNpro-ir/localist/actions/workflows/release.yml/badge.svg"></a>
  <a href="https://github.com/MBNpro-ir/localist/releases"><img alt="Version" src="https://img.shields.io/badge/version-3.7.0-blue"></a>
</p>

## User Guide

### What Localist does

Localist lets devices on the same local network share VPN/proxy access and transfer files without sending data through a cloud service.

- Smart VPN handoff discovers the sharing device, checks its advertised network addresses, and connects through a reachable address automatically.
- Android uses one Smart QR/manual configuration containing every allowed endpoint, so Localist can choose the reachable IP. The iPhone/Xray view keeps a separate configuration for each IP.
- The Sharing screen shows the number and identity of connected Localist devices.
- Quick Send selects files, media, clipboard text, typed text, or complete folders and is compatible with the LocalSend v2.1 protocol and legacy v1 routes.
- English and Persian, light/dark themes, Android dynamic colors, and Windows accent colors are supported.

### Download and install

Download the latest package from [GitHub Releases](https://github.com/MBNpro-ir/localist/releases/latest).

- Android: use the universal APK when you do not know the device architecture. ABI-specific APKs are available for smaller downloads.
- Windows: extract the complete x64 ZIP before running `Localist.exe`. Keep all DLL and tool files beside the executable.
- Put both devices on the same Wi-Fi, Ethernet, or hotspot network. Client isolation on guest Wi-Fi can prevent local discovery and connections.

### Share VPN or proxy access

On the device that already has the desired internet/VPN connection:

1. Open **Sharing**.
2. Select the proxy protocols and allowed local network addresses.
3. Start Sharing.
4. Keep this screen available to see connected Localist devices and their count.

On the receiving device:

1. Open **Receiving**.
2. Select the sharing device under Nearby Devices, scan its QR code, or paste its smart configuration.
3. Localist tests the allowed routes and selects a reachable IP automatically.
4. Start the available VPN, system proxy, or local proxy mode.

Raw `http://` and `socks5://` configurations are still accepted. A raw configuration can only use the exact host entered by the user; Localist never substitutes an unrelated nearby device merely because it uses the same port.

### Transfer files with Quick Send

1. Open **Quick Send** on both devices.
2. Choose **File**, **Media**, **Paste**, **Text**, or **Folder**.
3. Tap a destination, or press and hold devices to select several recipients and send concurrently.
4. Accept the request on the receiving device unless Quick Save is enabled.

Use Refresh to repeat multicast, directed-broadcast, and active subnet discovery across eligible Wi-Fi, Ethernet, hotspot, and USB-tethering interfaces. A charge-only USB cable does not create an IP network; enable USB tethering when the cable should carry Quick Send traffic.

Quick Send settings include:

- Device name, receive port, and multicast group. Android advertises the actual phone model automatically instead of `localhost`.
- Destination folder and duplicate-file overwrite behavior. On Android, the default is `/storage/emulated/0/Localist`, with `Images`, `Videos`, `Audio`, `Documents`, `Archives`, `Apps`, and `Other` subfolders. Choosing a custom destination disables this automatic grouping.
- HTTPS encryption with certificate fingerprint verification.
- Optional receiver PIN.
- Favorite devices and Quick Save for all devices or favorites only.
- Manual IP/hostname targets when multicast discovery is unavailable.

Quick Save accepts files without asking. Enable it only on trusted local networks. Text messages always require an explicit acceptance.

### Platform modes

| Platform | Sharing | Receiving | Quick Send |
| --- | --- | --- | --- |
| Android | HTTP/SOCKS5 proxy, hotspot/manual network flow, optional root routing | Android VPN or local proxy | Send and receive files/messages |
| Windows | HTTP/SOCKS5 proxy, optional local v2rayN upstream | Windows VPN with Wintun, system proxy, or local proxy | Send and receive files/messages |

Windows VPN mode requires administrator access plus `tun2socks.exe` and `wintun.dll`. If those tools are absent, development packages can still use system/local proxy modes.

### Permissions and local data

- Android asks for notifications and battery-optimization access so long-running VPN/proxy transfers can continue in the background.
- Camera access is requested only when the QR scanner is opened.
- Android VPN permission is requested only when VPN Receiving is started.
- Android requests file-management access only when the default root-level `/Localist` receive folder is used.
- Files sent through Quick Send stay on the local network. HTTPS mode verifies the destination certificate fingerprint.
- Preferences, favorites, certificate identity, and transfer settings are stored in the platform app-data directory.

### Logs and troubleshooting

- Open **Logs** to inspect, copy, or save a diagnostic report.
- Active Debug Mode records detailed service, native bridge, and network events.
- On Windows, Debug Mode writes `debug.log` beside `Localist.exe`. Individual messages and the file itself are size-limited and oversized logs are rotated.
- Recoverable Flutter UI diagnostics are logged without being reported as repeated process crashes. Fatal errors are de-duplicated before showing a crash notice.
- If Nearby Devices is empty, confirm both devices are on the same subnet (or USB tethering is enabled), disable guest/client isolation, and use Refresh or a manual target.
- If Windows VPN cannot start, verify that Localist is elevated and the Wintun files from the release package were not removed by extraction or antivirus software.

## Developer Guide

### Repository layout

```text
lib/                       Flutter UI, smart VPN discovery, Quick Send, settings and services
android/                   Android VPN/proxy bridge, updater, widgets and Gradle project
windows/                   Windows runner, Win32 bridge, Wintun packaging and resources
test/                      Flutter regression and protocol-focused checks
.github/workflows/         Android/Windows release and GitHub publishing workflow
ico/                       Application icons
```

### Toolchain

- Flutter stable with Windows desktop support.
- Android SDK Platform 35 or newer and JDK 17.
- Visual Studio 2022 with **Desktop development with C++**.
- Windows 10/11 WebView2 Runtime for webcam QR scanning.
- 7-Zip for local Windows release packaging.

Prepare a fresh checkout:

```powershell
flutter doctor -v
flutter config --enable-windows-desktop
flutter pub get
flutter doctor --android-licenses
```

### Android builds

Debug APK:

```powershell
flutter build apk --debug
```

ABI-specific release APKs:

```powershell
flutter build apk --release `
  --split-per-abi `
  --target-platform android-arm,android-arm64,android-x64 `
  --obfuscate `
  --split-debug-info=build\symbols\android `
  --tree-shake-icons
```

Universal APK and App Bundle:

```powershell
flutter build apk --release `
  --target-platform android-arm,android-arm64,android-x64 `
  --obfuscate `
  --split-debug-info=build\symbols\android-universal `
  --tree-shake-icons

flutter build appbundle --release `
  --obfuscate `
  --split-debug-info=build\symbols\android-aab `
  --tree-shake-icons
```

### Windows build

```powershell
flutter build windows --release `
  --obfuscate `
  --split-debug-info=build\symbols\windows-x64 `
  --tree-shake-icons
```

The compiled application is written to `build/windows/x64/runner/Release/`. A distributable package must include the entire directory, including the Flutter runtime and Wintun tools.

### Release workflow

`.github/workflows/release.yml` can be started manually or by pushing a `v*` tag. It reads the application version from `pubspec.yaml`, builds Android and Windows in parallel, stages compiled files, and publishes or updates the matching GitHub Release.

Published assets include:

- Android universal, armeabi-v7a, arm64-v8a, and x86_64 APKs.
- Android universal AAB.
- Windows x64 ZIP.
- Separate Android and Windows symbol archives.

Start a tag-based release:

```powershell
$version = ((Select-String -Path pubspec.yaml -Pattern '^version:\s*(.+)$').Matches[0].Groups[1].Value -split '\+')[0]
git tag "v$version"
git push origin "v$version"
```

For a manual release, open the repository Actions page, run **Release**, and leave `release_tag` empty to use the version from `pubspec.yaml`.

### Architecture notes

- Localist discovery and connected-device heartbeats use separate UDP ports from the shared proxy endpoints.
- Smart configurations include a stable device identity. The receiver may rewrite an advertised endpoint only with the source address of that same discovered device.
- SOCKS5 probes perform a protocol handshake; HTTP probes verify a proxy-form HTTP response before a route is selected.
- Quick Send binds multicast listeners per eligible interface, announces from concrete interface addresses, falls back to directed broadcast and bounded concurrent `/24` registration scans, and never sends discovery from `0.0.0.0`.
- Android excludes Localist's own process from its TUN interface so Quick Send discovery and transfers continue over the underlying LAN while the VPN is active; other applications remain routed through the VPN.
- Quick Send validates upload tokens and source addresses, bounds request metadata, preserves safe relative folder paths, sanitizes traversal attempts, and expires inactive receive sessions.
- The Windows release job downloads signed Wintun and tun2socks runtime files before compiling the package.

### License and attribution

Quick Send is based on the Apache-2.0-licensed LocalSend project. Attribution and the complete license are included in `THIRD_PARTY_NOTICES.md` and bundled with application assets.
