<p align="center">
  <img src="ico/logo.png" alt="Localist" width="112" />
</p>

<h1 align="center">Localist</h1>

<p align="center">
  Share a local proxy between Android and Windows with QR handoff, nearby discovery, updater support, crash reporting, and home-screen controls.
</p>

<p align="center">
  <a href="README.fa.md">فارسی</a> | <strong>English</strong>
</p>

<p align="center">
  <a href="https://flutter.dev"><img alt="Flutter" src="https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white"></a>
  <a href="https://developer.android.com"><img alt="Android" src="https://img.shields.io/badge/Android-8.0%2B-3DDC84?logo=android&logoColor=white"></a>
  <a href="https://learn.microsoft.com/windows/apps/"><img alt="Windows" src="https://img.shields.io/badge/Windows-Desktop-0078D4?logo=windows&logoColor=white"></a>
  <a href="https://github.com/MBNpro-ir/localist/actions"><img alt="Release workflow" src="https://img.shields.io/badge/release-passing-brightgreen?logo=github"></a>
  <a href="https://github.com/MBNpro-ir/localist/releases"><img alt="Version" src="https://img.shields.io/badge/version-3.5.0-blue"></a>
</p>

## Overview

Localist is a Flutter app for sharing and receiving local proxy access across Android and Windows.

- Android can share HTTP/SOCKS5 proxy endpoints, receive a remote endpoint as VPN or local proxy, scan QR codes, discover nearby Localist devices without listing itself, install GitHub release updates, and expose full or single-action home-screen widgets for Sending/Receiving controls.
- Windows can share proxy endpoints, advertise them for local discovery, show and scan QR codes with a webcam, run compactly with tray behavior, follow Windows accent colors, and use bundled Wintun/tun2socks tools for Receiving VPN mode when available.
- First-run setup now asks only for permissions needed at startup. Camera permission is requested only when the QR scanner is opened.
- Crash reporting opens the user's email client with crash details, app logs, platform data, device information, and stack traces.
- Settings are persisted in each platform's standard app-support storage so reinstalling the app keeps user preferences.

## What's New

- 📲 Xray QR codes now use v2rayNG-compatible `socks://Og@host:port#name` links instead of raw JSON.
- 🧯 Windows proxy relays now apply socket backpressure and throttle traffic-stat saves to prevent high-speed transfer RAM/CPU runaway.
- 🛠️ Windows release builds prefer the generated C++/WinRT projection so `webview_windows` compiles reliably on this toolchain.
- 🧭 Nearby discovery now ignores the current phone's own Sharing announcements.
- 🖤 Android widgets now use a darker redesigned style with separate Sending and Receiving widgets.
- 🔔 Android checks for updates on startup and shows an in-app notice only when a newer installable release exists.
- 🏷️ GitHub Actions release builds now run from `v*` tags, not every branch push.

- 📱 EN: iOS QR tab now generates Xray and sing-box SOCKS configs for every active Sharing IP.
  FA: تب iOS برای همه IPهای فعال Sharing کانفیگ SOCKS مخصوص Xray و sing-box می‌سازد.
- 🧭 EN: Proxy QR codes now keep Proxy and iOS flows in separate tabs with click-to-open cards.
  FA: بخش Proxy QR codes حالا تب‌های جدا برای Proxy و iOS دارد و QRها فقط با کلیک روی کارت باز می‌شوند.
- 🪟 EN: Windows Receiving adds Start as system proxy and renames the manual mode to Start as local proxy.
  FA: در Receiving ویندوز گزینه Start as system proxy اضافه شد و حالت دستی به Start as local proxy تغییر نام داد.
- 🧹 EN: Stopping Windows system proxy clears the Windows proxy settings automatically.
  FA: با توقف system proxy، تنظیمات پروکسی ویندوز به صورت خودکار پاک می‌شود.
- 🛠️ EN: Wintun/tun2socks startup now checks administrator access, uses the correct `warn` log level, and preserves useful failure logs.
  FA: راه‌اندازی Wintun/tun2socks دسترسی ادمین را چک می‌کند، سطح لاگ درست `warn` را می‌فرستد و خطاهای مفید را نگه می‌دارد.
- 🚀 EN: GitHub Actions release packaging keeps compiled assets staged in `compiled` before publishing.
  FA: اکشن انتشار GitHub خروجی‌های کامپایل‌شده را قبل از انتشار داخل `compiled` آماده می‌کند.

## Version History

- 🚀 `v1.0.0` - Initial release workflow and packaged Android/Windows builds.
- 🧰 `v1.0.2` - `v1.0.5` - Release packaging fixes, README badges, and early build pipeline cleanup.
- ⚡ `v1.1.0` - Performance improvements for older Android devices.
- 🪟 `v1.1.2` - Windows portrait window sizing fixes.
- 📦 `v1.5.0` - Broader Localist release packaging and app polish.
- 🌉 `v1.6.0` - Windows Receiving VPN support through Wintun/tun2socks.
- 🛠️ `v1.6.4` - Android VPN and settings port fixes.
- 📡 `v2.0.0` - Nearby discovery, Wintun fixes, and release publishing improvements.
- 🔋 `v2.1.0` - QR scanner battery behavior and themed in-app notices.
- 🌐 `v3.0.0` - Language onboarding and smart GitHub updater.
- ✅ `v3.1.0` - Onboarding navigation, Persian localization, and version badge updates.
- 🧩 `v3.2.0` - Permission cleanup, updater repair, widgets, crash reporting, flags, color settings, and README refresh.
- 📱 `v3.3.0` - iOS Xray/sing-box QR configs, Windows system proxy mode, Wintun startup fixes, and release staging polish.
- 🧭 `v3.4.0` - Self-discovery filtering, black Android widgets, separate Sending/Receiving widgets, startup update notices, and tag-only release builds.
- 📲 `v3.5.0` - v2rayNG SOCKS QR links for Xray, Windows relay backpressure, throttled traffic stats, and C++/WinRT build reliability.

## Repository Layout

```text
lib/                       Flutter UI, settings, QR, proxy state, crash reporting, Windows Dart services
android/                   Android Kotlin VPN/proxy bridge, updater install bridge, widget, crash reporter, Gradle project
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

Run these before publishing changes:

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

## GitHub Actions Release

The release workflow runs only for `v*` tag pushes or manual dispatch. It reads `version:` from `pubspec.yaml`, then builds and uploads:

- `localist-v<version>-android-armeabi-v7a.apk`
- `localist-v<version>-android-arm64-v8a.apk`
- `localist-v<version>-android-x86_64.apk`
- `localist-v<version>-android-universal.aab`
- `localist-v<version>-windows-x64.zip`

Create a release by pushing a tag that matches the `pubspec.yaml` version:

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

- Android: automatic nearby-device discovery, QR/manual config, persisted receiving drafts, validated manual host/port input, local proxy mode, or Android `VpnService` receiving mode.
- Windows: automatic nearby-device discovery, QR/manual config, persisted receiving drafts, validated manual host/port input, local proxy mode, or Windows VPN mode through Wintun when bundled tools are available.

Settings:

- Android root routing is still Android-only.
- Windows starts with administrator privileges for VPN mode, so there is no admin toggle in Settings.
- Windows close behavior can ask each time, move the window to the taskbar tray, or fully exit.
- Proxy ports are locked while Sharing is active.
- Theme follows Android dynamic colors or Windows accent colors, with an expanded custom seed-color palette.

## Android Permissions, Updater, Widget, and Crash Reports

On first launch, Android asks only for startup-critical permissions:

- Notifications, so VPN/proxy services can remain foreground services.
- Battery optimization exemption, so long proxy/VPN transfers are not paused when the screen turns off.

Camera permission is requested only when the user opens QR scanning in Receiving. VPN permission is requested only when the user starts Android VPN Receiving mode.

The Android updater checks GitHub releases, chooses the matching APK for the device ABI, downloads it to the app cache, validates the download length, and opens the Android package installer.

The Android widgets support small and larger home-screen sizes. The full widget shows service status with Sending and Receiving controls, while the single-action widgets provide dedicated Sending-only and Receiving-only buttons. If Receiving has no saved remote proxy config, the widget opens the app. Startup update checks stay quiet on errors and only show an in-app notice when an installable update is available.

Crash reporting collects the crash type, time, semantic version, platform, Android SDK/ABIs, stack trace, and Localist app logs, then opens the user's email client with a ready-to-send support report.

## Windows VPN and Wintun

Windows Receiving VPN mode starts `tun2socks.exe` with `wintun.dll` when those tools are bundled next to `Localist.exe`. The release workflow downloads both tools for the Windows x64 package, and the app configures the Wintun interface, DNS, split default routes, and a bypass route for the selected upstream proxy before marking VPN mode active.

If `tun2socks.exe` or `wintun.dll` is missing, Windows Receiving falls back to the previous system-proxy route so development builds remain usable from a clean Flutter checkout.

## Notes

Windows TUN driver mode requires administrator privileges and the signed Wintun runtime. Keep `tun2socks.exe` and `wintun.dll` beside the Windows executable when packaging outside GitHub Actions.
