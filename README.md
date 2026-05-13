# Localist

Localist is a Flutter Android app prototype for sharing a device VPN connection through a local proxy and Android hotspot flow.

## Current Build Notes

- Flutter SDK is installed at `C:\tools\flutter`.
- This project was created with `flutter create --org com.yourcompany localist`.
- Android is configured with `minSdk = 26` (Android 8.0+) and `targetSdk = 35`.
- `flutter doctor -v` reports a healthy Flutter/Android toolchain with Android SDK `36.1.0`.
- Dart analysis, unit tests, and `flutter build apk --debug` pass.
- Debug APK output: `build\app\outputs\flutter-apk\app-debug.apk`.

## Toolchain Setup on Windows

1. Install Android Studio from the official Android developer site.
2. Open Android Studio once and install Android SDK Platform 35+, Android SDK Build-Tools, Android SDK Platform-Tools, and a JDK 17 runtime.
3. Accept Android SDK licenses:

   ```powershell
   C:\tools\flutter\bin\flutter.bat doctor --android-licenses
   ```

4. Add Flutter to PATH for normal shell use:

   ```powershell
   setx PATH "$env:PATH;C:\tools\flutter\bin"
   ```

5. Reopen PowerShell and verify:

   ```powershell
   flutter doctor -v
   flutter build apk --debug
   ```

If Android SDK is installed somewhere custom, point Flutter at it:

```powershell
C:\tools\flutter\bin\flutter.bat config --android-sdk C:\Path\To\Android\Sdk
```

## Implemented

- Material 3 Flutter UI with glass panels, safe bottom navigation, and four tabs: Home, Hotspot, Logs, Settings.
- Material You dynamic theme integration through `material_you_dynamic_theme`, plus manual System/Light/Dark selection.
- Settings persistence for proxy protocol, port, and selective sharing.
- QR code proxy URL generation with `qr_flutter`.
- Optional rooted VPN sharing mode that disables proxy mode and applies reversible routing/NAT rules from local client subnets to the active VPN interface.
- Runtime permission requests for location and notification access.
- `MethodChannel` bridge named `com.localist.vpn`.
- Kotlin `VpnService` declaration and foreground service lifecycle.
- Ongoing notification with Stop and Restart actions.
- Local TCP proxy implementation for HTTP, SOCKS4, and SOCKS5 CONNECT-style forwarding.
- Data counters persisted with Android `SharedPreferences`.
- Android local-only hotspot integration through `WifiManager.startLocalOnlyHotspot`.

## Platform Limits

Android does not allow ordinary third-party apps to fully configure the system portable hotspot SSID/password or force tethering on modern Android releases. Localist uses Android's supported local-only hotspot API, which can expose SSID/passphrase but does not replace privileged carrier/OEM tethering APIs.

The included `VpnService` creates a TUN interface and records packets, but production VPN forwarding needs a real packet forwarding engine such as a tun2socks/native routing layer. The proxy server is functional as a local TCP proxy, while full "route every connected client through VPN" behavior depends on completing that forwarding path.

Rooted mode is a separate source-device path: when root is granted and a VPN interface is already active, Localist applies best-effort `ip rule` and `iptables` forwarding/NAT rules for hotspot/local client subnets. Hotspot clients normally receive the phone as their gateway automatically; devices on a home router may still need the phone set as their gateway because Android cannot change another device's default route by itself.
