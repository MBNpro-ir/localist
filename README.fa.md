<p align="center">
  <img src="ico/logo.png" alt="Localist" width="112" />
</p>

<h1 align="center">Localist</h1>

<p align="center" dir="rtl">
  اشتراک‌گذاری و دریافت پروکسی محلی بین اندروید و ویندوز با QR، کشف دستگاه‌های نزدیک، آپدیتر، گزارش کرش و ویجت اندروید.
</p>

<p align="center">
  <strong>فارسی</strong> | <a href="README.md">English</a>
</p>

<p align="center">
  <a href="https://flutter.dev"><img alt="Flutter" src="https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white"></a>
  <a href="https://developer.android.com"><img alt="Android" src="https://img.shields.io/badge/Android-8.0%2B-3DDC84?logo=android&logoColor=white"></a>
  <a href="https://learn.microsoft.com/windows/apps/"><img alt="Windows" src="https://img.shields.io/badge/Windows-Desktop-0078D4?logo=windows&logoColor=white"></a>
  <a href="https://github.com/MBNpro-ir/localist/actions"><img alt="Release workflow" src="https://img.shields.io/badge/release-passing-brightgreen?logo=github"></a>
  <a href="https://github.com/MBNpro-ir/localist/releases"><img alt="Version" src="https://img.shields.io/badge/version-3.1.0-blue"></a>
</p>

## معرفی

Localist یک برنامه Flutter برای اشتراک‌گذاری و دریافت دسترسی پروکسی محلی روی اندروید و ویندوز است.

- اندروید می‌تواند endpointهای HTTP/SOCKS5 را share کند، endpoint ریموت را به صورت VPN یا local proxy دریافت کند، QR را اسکن کند، دستگاه‌های نزدیک را پیدا کند، آپدیت‌های GitHub release را نصب کند و با ویجت صفحه اصلی Sending/Receiving را کنترل کند.
- ویندوز می‌تواند endpointها را share کند، آن‌ها را برای local discovery تبلیغ کند، QR نشان دهد، با webcam اسکن کند، در UI جمع‌وجور و tray اجرا شود، از رنگ accent ویندوز پیروی کند و در صورت وجود Wintun/tun2socks حالت Receiving VPN را اجرا کند.
- در ورود اولیه فقط permissionهای ضروری شروع برنامه درخواست می‌شوند. permission دوربین فقط هنگام باز کردن QR scanner درخواست می‌شود.
- گزارش کرش، email client کاربر را با اطلاعات کرش، لاگ برنامه، اطلاعات پلتفرم، مدل دستگاه و stack trace باز می‌کند.
- تنظیمات در محل استاندارد هر پلتفرم ذخیره می‌شود تا بعد از نصب مجدد، preferenceها باقی بمانند.

## تغییرات جدید

- 🔐 FA: دسترسی دوربین از ورود اولیه حذف شد و فقط هنگام اسکن QR درخواست می‌شود.  
  EN: Camera permission was removed from first launch and is requested only for QR scanning.
- 🪟 FA: در ویندوز مرحله permissions از ورود اولیه حذف شد.  
  EN: Windows onboarding no longer shows the permissions step.
- 🏳️ FA: نمایش پرچم‌ها پایدار و اصلاح شد.  
  EN: Language flags now render with a stable custom painter.
- ⬇️ FA: آپدیتر اندروید فایل APK را در مسیر درست ذخیره می‌کند و نصب‌کننده اندروید را درست باز می‌کند.  
  EN: Android updater downloads APKs into an installable app cache path and opens the Android package installer correctly.
- 🎨 FA: گزینه‌های تم تمام‌عرض شدند و رنگ‌های بیشتری به App color اضافه شد.  
  EN: Theme controls are full-width like language controls, and the App color palette has more choices.
- 🧩 FA: ویجت اندروید برای خاموش و روشن کردن Sending و Receiving اضافه شد.  
  EN: Android home widget was added for Sending and Receiving quick controls.
- 🧯 FA: ماژول گزارش کرش برای Dart و کرش‌های native اندروید اضافه شد.  
  EN: Crash reporting module was added for Dart and Android native crashes.
- 🏷️ FA: App Info و Updater فقط نسخه مثل `3.1.0` را نمایش می‌دهند و build number حذف شد.  
  EN: App Info and Updater show only semantic versions such as `3.1.0`, without build numbers.

## تاریخچه نسخه‌ها

- 🚀 `v1.0.0` - راه‌اندازی release workflow و خروجی‌های بسته‌بندی‌شده اندروید/ویندوز.
- 🧰 `v1.0.2` - `v1.0.5` - اصلاحات بسته‌بندی release، badgeهای README و تمیزکاری pipeline.
- ⚡ `v1.1.0` - بهبود کارایی روی دستگاه‌های اندرویدی قدیمی‌تر.
- 🪟 `v1.1.2` - اصلاح اندازه پنجره portrait در ویندوز.
- 📦 `v1.5.0` - بهبود بسته‌بندی release و polish برنامه.
- 🌉 `v1.6.0` - اضافه شدن Receiving VPN ویندوز با Wintun/tun2socks.
- 🛠️ `v1.6.4` - اصلاح Android VPN و portهای تنظیمات.
- 📡 `v2.0.0` - کشف دستگاه‌های نزدیک، اصلاحات Wintun و بهبود publish release.
- 🔋 `v2.1.0` - بهبود مصرف باتری scanner و noticeهای theme شده.
- 🌐 `v3.0.0` - onboarding زبان و updater هوشمند GitHub.
- ✅ `v3.1.0` - اصلاح navigation onboarding، localization فارسی و badge نسخه.
- 🧩 شاخه فعلی `master` - پاک‌سازی permissionها، تعمیر updater، ویجت، crash reporter، پرچم‌ها، رنگ‌ها و به‌روزرسانی README.

## ساختار پروژه

```text
lib/                       UI فلاتر، تنظیمات، QR، وضعیت پروکسی، crash reporting و سرویس‌های Dart ویندوز
android/                   bridge اندروید برای VPN/proxy، نصب updater، ویجت، crash reporter و Gradle
windows/                   runner ویندوز، bridge Win32 MethodChannel و resource/icon
test/                      تست‌های Flutter
.github/workflows/         pipeline انتشار GitHub Actions
ico/                       آیکن‌های برنامه
```

## پیش‌نیازها

برای build از clone تازه این ابزارها را نصب کنید:

- Flutter stable SDK با desktop support.
- Android Studio یا Android command-line tools همراه Android SDK Platform 35+.
- JDK 17.
- Visual Studio 2022 با workload مربوط به "Desktop development with C++" برای build ویندوز.
- Windows 10/11 WebView2 Runtime برای scanner ویندوز.
- 7-Zip برای ساخت ZIP فشرده ویندوز.

بررسی ابزارها:

```powershell
flutter doctor -v
flutter config --enable-windows-desktop
flutter pub get
```

در صورت نیاز licenseهای اندروید را قبول کنید:

```powershell
flutter doctor --android-licenses
```

## چک‌های توسعه

قبل از publish تغییرات:

```powershell
flutter pub get
flutter analyze
flutter test
```

## دستورهای Build اندروید

Debug APK:

```powershell
flutter build apk --debug
```

APKهای release کوچک و جداشده بر اساس CPU:

```powershell
flutter build apk --release `
  --split-per-abi `
  --target-platform android-arm,android-arm64,android-x64 `
  --obfuscate `
  --split-debug-info=build\symbols\android `
  --tree-shake-icons
```

Android App Bundle:

```powershell
flutter build appbundle --release `
  --obfuscate `
  --split-debug-info=build\symbols\android-aab `
  --tree-shake-icons
```

خروجی‌های اندروید:

```text
build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk
build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
build/app/outputs/flutter-apk/app-x86_64-release.apk
build/app/outputs/bundle/release/app-release.aab
```

## دستورهای Build ویندوز

Build نسخه release:

```powershell
flutter build windows --release `
  --obfuscate `
  --split-debug-info=build\symbols\windows-x64 `
  --tree-shake-icons
```

پوشه خروجی:

```text
build/windows/x64/runner/Release/
```

ساخت ZIP با فشرده‌سازی بالا:

```powershell
$version = ((Select-String -Path pubspec.yaml -Pattern '^version:\s*(.+)$').Matches[0].Groups[1].Value -split '\+')[0]
New-Item -ItemType Directory -Force "release\v$version" | Out-Null
& "$env:ProgramFiles\7-Zip\7z.exe" a -tzip -mx=9 `
  "release\v$version\localist-v$version-windows-x64.zip" `
  .\build\windows\x64\runner\Release\*
```

## انتشار با GitHub Actions

workflow انتشار، مقدار `version:` را از `pubspec.yaml` می‌خواند و این فایل‌ها را upload می‌کند:

- `localist-v<version>-android-armeabi-v7a.apk`
- `localist-v<version>-android-arm64-v8a.apk`
- `localist-v<version>-android-x86_64.apk`
- `localist-v<version>-android-universal.aab`
- `localist-v<version>-windows-x64.zip`

برای ساخت release، tag مطابق نسخه `pubspec.yaml` را push کنید:

```powershell
$version = ((Select-String -Path pubspec.yaml -Pattern '^version:\s*(.+)$').Matches[0].Groups[1].Value -split '\+')[0]
git tag "v$version"
git push origin "v$version"
```

همچنین می‌توانید workflow را دستی از تب GitHub Actions اجرا کنید و `release_tag` را خالی بگذارید تا نسخه از `pubspec.yaml` خوانده شود.

## حالت‌های Localist

Sharing:

- اندروید: سرویس پروکسی به همراه hotspot/manual network sharing.
- ویندوز: فقط proxy service؛ بدون hotspot controls و بدون دکمه share APK.
- Sharing ویندوز می‌تواند ترافیک share شده را از v2rayN SOCKS proxy محلی عبور دهد، به صورت پیش‌فرض `127.0.0.1:10808`.

Receiving:

- اندروید: discovery خودکار، QR/manual config، draftهای ذخیره‌شده، اعتبارسنجی host/port، local proxy mode یا Android `VpnService`.
- ویندوز: discovery خودکار، QR/manual config، draftهای ذخیره‌شده، اعتبارسنجی host/port، local proxy mode یا VPN mode با Wintun در صورت وجود ابزارهای bundled.

Settings:

- root routing فقط اندروید است.
- ویندوز برای VPN mode با administrator privileges شروع می‌شود، بنابراین toggle admin در Settings ندارد.
- رفتار دکمه close ویندوز می‌تواند ask، رفتن به taskbar tray یا exit کامل باشد.
- portهای proxy هنگام فعال بودن Sharing قفل می‌شوند.
- theme از Android dynamic colors یا Windows accent colors پیروی می‌کند و palette رنگ سفارشی گسترده‌تر شده است.

## Permission، آپدیتر، ویجت و گزارش کرش اندروید

در ورود اولیه اندروید فقط permissionهای ضروری شروع برنامه درخواست می‌شود:

- Notifications برای foreground serviceهای VPN/proxy.
- Battery optimization exemption برای جلوگیری از توقف انتقال طولانی هنگام خاموش شدن صفحه.

permission دوربین فقط هنگام باز کردن QR scanner در Receiving درخواست می‌شود. permission VPN فقط هنگام شروع حالت Android VPN Receiving درخواست می‌شود.

آپدیتر اندروید releaseهای GitHub را بررسی می‌کند، APK مناسب ABI دستگاه را انتخاب می‌کند، آن را در cache برنامه دانلود می‌کند، اندازه دانلود را اعتبارسنجی می‌کند و نصب‌کننده اندروید را باز می‌کند.

ویجت اندروید در اندازه‌های کوچک و بزرگ home screen کار می‌کند. وضعیت سرویس را نشان می‌دهد و کنترل سریع Sending و Receiving دارد. اگر Receiving تنظیمات remote proxy ذخیره‌شده نداشته باشد، ویجت برنامه را باز می‌کند.

گزارش کرش شامل نوع کرش، زمان، نسخه semantic، پلتفرم، Android SDK/ABI، stack trace و لاگ‌های Localist است و email client را با متن آماده ارسال به پشتیبانی باز می‌کند.

## Windows VPN و Wintun

حالت Windows Receiving VPN وقتی `tun2socks.exe` و `wintun.dll` کنار `Localist.exe` باشند آن‌ها را اجرا می‌کند. workflow انتشار هر دو ابزار را برای بسته Windows x64 دانلود می‌کند و برنامه interface مربوط به Wintun، DNS، routeهای default split و bypass route برای upstream proxy انتخاب‌شده را تنظیم می‌کند.

اگر `tun2socks.exe` یا `wintun.dll` موجود نباشد، Windows Receiving به مسیر قبلی system-proxy fallback می‌کند تا buildهای development از checkout تمیز هم قابل استفاده باشند.

## نکته‌ها

حالت Windows TUN driver نیاز به administrator privileges و runtime امضاشده Wintun دارد. هنگام بسته‌بندی خارج از GitHub Actions، فایل‌های `tun2socks.exe` و `wintun.dll` را کنار executable ویندوز نگه دارید.
