<p align="center">
  <img src="ico/logo.png" alt="Localist" width="112" />
</p>

<h1 align="center">Localist</h1>

<p align="center">
  Share a local proxy between Android and Windows with QR handoff, compact desktop UI, and release builds for GitHub.
</p>

<p align="center">
  <a href="https://flutter.dev"><img alt="Flutter" src="https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white"></a>
  <a href="https://developer.android.com"><img alt="Android" src="https://img.shields.io/badge/Android-8.0%2B-3DDC84?logo=android&logoColor=white"></a>
  <a href="https://learn.microsoft.com/windows/apps/"><img alt="Windows" src="https://img.shields.io/badge/Windows-Desktop-0078D4?logo=windows&logoColor=white"></a>
  <a href="https://github.com/MBNpro-ir/localist/actions"><img alt="Release workflow" src="https://img.shields.io/badge/release-passing-brightgreen?logo=github"></a>
  <a href="https://github.com/MBNpro-ir/localist/releases"><img alt="Version" src="https://img.shields.io/badge/version-1.6.4-blue"></a>
</p>

## Overview

Localist is a Flutter app for moving proxy/VPN access between Android and Windows:

- Android can share HTTP/SOCKS5 proxy endpoints and receive a remote endpoint as VPN or local proxy, with first-run setup and background-transfer protection.
- Windows can share proxy endpoints, show QR codes, scan proxy QR codes with a webcam, run with administrator privileges, minimize to the taskbar tray, and start Receiving VPN mode with bundled Wintun/tun2socks tools when they are available.
- Settings are persisted in each platform's standard app-support storage so reinstalling the app keeps user preferences.
- Windows uses the Android app icon, starts at `440x680`, keeps width fixed at `440`, allows taller vertical resizing, has no maximize button, and follows Windows accent colors.

## Repository Layout

```text
lib/                       Flutter UI, settings, QR, proxy state, Windows Dart services
android/                   Android Kotlin VPN/proxy bridge and Gradle project
windows/                   Windows runner, Win32 MethodChannel bridge, app icon/resource setup
test/                      Flutter unit tests
.github/workflows/         GitHub Actions release pipeline
ico/                       Localist app icon assets
```

## Requirements

Install these tools before building from a fresh clone:

- Flutter stable SDK with desktop support enabled.
- Android Studio or Android command-line tools with Android SDK Platform 35+.
- JDK 17.
- Visual Studio 2022 with "Desktop development with C++" for Windows builds.
- Windows 10/11 WebView2 Runtime for the Windows QR scanner.
- 7-Zip if you want the smallest local Windows ZIP package.

Verify the toolchain:

```powershell
flutter doctor -v
flutter config --enable-windows-desktop
flutter pub get
```

Accept Android licenses when needed:

```powershell
flutter doctor --android-licenses
```

## Development Checks

Run these before opening a pull request:

```powershell
flutter pub get
flutter analyze
flutter test
```

## Android Build Commands

Debug APK:

```powershell
flutter build apk --debug
```

Smallest release APKs split by Android CPU architecture:

```powershell
flutter build apk --release `
  --split-per-abi `
  --target-platform android-arm,android-arm64,android-x64 `
  --obfuscate `
  --split-debug-info=build\symbols\android `
  --tree-shake-icons
```

Release Android App Bundle:

```powershell
flutter build appbundle --release `
  --obfuscate `
  --split-debug-info=build\symbols\android-aab `
  --tree-shake-icons
```

Android release outputs:

```text
build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk
build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
build/app/outputs/flutter-apk/app-x86_64-release.apk
build/app/outputs/bundle/release/app-release.aab
```

The current Gradle release config enables code minification, resource shrinking, icon tree-shaking, and compressed native libraries. Replace the debug signing config with your production keystore before publishing to a store.

## Windows Build Commands

Release build with Dart symbol splitting and icon tree-shaking:

```powershell
flutter build windows --release `
  --obfuscate `
  --split-debug-info=build\symbols\windows-x64 `
  --tree-shake-icons
```

Windows release output folder:

```text
build/windows/x64/runner/Release/
```

Create a maximum-compression ZIP package:

```powershell
$version = ((Select-String -Path pubspec.yaml -Pattern '^version:\s*(.+)$').Matches[0].Groups[1].Value -split '\+')[0]
New-Item -ItemType Directory -Force "release\v$version" | Out-Null
& "$env:ProgramFiles\7-Zip\7z.exe" a -tzip -mx=9 `
  "release\v$version\localist-v$version-windows-x64.zip" `
  .\build\windows\x64\runner\Release\*
```

Flutter's Windows desktop build in this toolchain produces an x64 runner. Android release builds are split into `armeabi-v7a`, `arm64-v8a`, and `x86_64` APKs.

## GitHub Actions Release

The release workflow reads `version:` from `pubspec.yaml`, then builds and uploads:

- `localist-v<version>-android-armeabi-v7a.apk`
- `localist-v<version>-android-arm64-v8a.apk`
- `localist-v<version>-android-x86_64.apk`
- `localist-v<version>-android-universal.aab`
- `localist-v<version>-windows-x64.zip`

Create a release from GitHub by pushing a tag that matches the `pubspec.yaml` version:

```powershell
$version = ((Select-String -Path pubspec.yaml -Pattern '^version:\s*(.+)$').Matches[0].Groups[1].Value -split '\+')[0]
git tag "v$version"
git push origin "v$version"
```

You can also run the workflow manually from the GitHub Actions tab and leave `release_tag` empty to use the `pubspec.yaml` version.

## Localist Modes

Sharing:

- Android: proxy service plus Android hotspot/manual network sharing flow.
- Windows: proxy service only; no hotspot controls and no APK share button.
- Windows Sharing can optionally route shared traffic through a local v2rayN SOCKS proxy, defaulting to `127.0.0.1:10808`.

Receiving:

- Android: QR/manual config, persisted receiving drafts, validated manual host/port input, local proxy mode, or Android `VpnService` receiving mode.
- Windows: QR/manual config, persisted receiving drafts, validated manual host/port input, local proxy mode, or Windows VPN mode through system proxy.

Settings:

- Android root routing is still Android-only.
- Windows starts with administrator privileges for VPN mode, so there is no admin toggle in Settings.
- Windows close behavior can ask each time, move the window to the taskbar tray, or fully exit.
- Proxy ports are locked while Sharing is active.
- Theme follows Android dynamic colors or Windows accent colors.

## Android Permissions and Background Transfer

On first launch, Android opens a setup screen before the main UI. Localist asks for:

- Notifications, so VPN/proxy services can remain foreground services.
- Camera, so QR configs can be scanned.
- Battery optimization exemption, so long proxy/VPN transfers are not paused when the screen turns off.

VPN permission is requested only when the user taps `Start as VPN + proxy` in Receiving. Localist does not check or request Android VPN permission while opening the app, so an already running VPN is left alone until the user explicitly starts Localist VPN mode.

While Android sharing, receiving VPN, or local proxy modes are active, the foreground service also holds a partial CPU wake lock and a high-performance Wi-Fi lock. This keeps socket forwarding and TUN forwarding alive when the app is backgrounded or the display turns off.

## Windows VPN and Wintun

Windows Receiving VPN mode starts `tun2socks.exe` with `wintun.dll` when those tools are bundled next to `Localist.exe`. The release workflow downloads both tools for the Windows x64 package, and the app configures the Wintun interface, DNS, split default routes, and a bypass route for the selected upstream proxy before marking VPN mode active.

If `tun2socks.exe` or `wintun.dll` is missing, Windows Receiving falls back to the previous system-proxy route so development builds remain usable from a clean Flutter checkout.

## Notes

Windows TUN driver mode requires administrator privileges and the signed Wintun runtime. Keep `tun2socks.exe` and `wintun.dll` beside the Windows executable when packaging outside GitHub Actions.
