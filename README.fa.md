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
  <a href="https://github.com/MBNpro-ir/localist/releases"><img alt="Version" src="https://img.shields.io/badge/version-3.5.4-blue"></a>
</p>

## معرفی

Localist یک برنامه Flutter برای اشتراک‌گذاری و دریافت دسترسی پروکسی محلی روی اندروید و ویندوز است.

- اندروید می‌تواند endpointهای HTTP/SOCKS5 را share کند، endpoint ریموت را به صورت VPN یا local proxy دریافت کند، QR را اسکن کند، دستگاه‌های نزدیک را پیدا کند، آپدیت‌های GitHub release را نصب کند و با ویجت صفحه اصلی Sending/Receiving را کنترل کند.
- ویندوز می‌تواند endpointها را share کند، آن‌ها را برای local discovery تبلیغ کند، QR نشان دهد، با webcam اسکن کند، در UI جمع‌وجور و tray اجرا شود، از رنگ accent ویندوز پیروی کند و در صورت وجود Wintun/tun2socks حالت Receiving VPN را اجرا کند.
- در ورود اولیه فقط permissionهای ضروری شروع برنامه درخواست می‌شوند. permission دوربین فقط هنگام باز کردن QR scanner درخواست می‌شود.
- گزارش کرش، email client کاربر را با اطلاعات کرش، لاگ برنامه، اطلاعات پلتفرم، مدل دستگاه و stack trace باز می‌کند.
- تنظیمات در محل استاندارد هر پلتفرم ذخیره می‌شود تا بعد از نصب مجدد، preferenceها باقی بمانند.

## تغییرات جدید

- 🐞 حالت Active Debug Mode سطح لاگ DEBUG را برای اکشن‌های برنامه، تنظیمات، native bridge، چرخه سرویس‌ها و مسیرهای شبکه اضافه می‌کند.
- 💾 در اندروید و ویندوز می‌توانید لاگ را با جزئیات کامل برنامه، پلتفرم، دستگاه، runtime و کارت‌های شبکه روی مسیر دلخواه ذخیره کنید.
- 📡 لاگ‌های native اندروید برای proxy، VPN و discovery وقتی debug mode فعال است داخل صفحه Logs نمایش داده می‌شوند.
- 🔁 بخش Nearby Devices دکمه Retry دارد و حتی وسط جست‌وجو می‌تواند discovery را از اول شروع کند.
- 📱 در Sharing اگر IP داخل محدوده iPhone Personal Hotspot باشد، برنامه هشدار می‌دهد که آیفون میزبان معمولاً نمی‌تواند به دستگاه وصل‌شده برگردد.
- 📦 GitHub Actions حالا کنار APKهای جداشده و AAB، یک Android universal APK هم منتشر می‌کند.
- 📲 QRهای Xray به جای JSON حالا لینک سازگار با v2rayNG با فرمت `socks://Og@host:port#name` می‌سازند.
- 🧯 relay پروکسی ویندوز حالا backpressure دارد و ذخیره آمار ترافیک throttle شده تا هنگام انتقال سریع، RAM/CPU از کنترل خارج نشود.
- 🛠️ build ویندوز از C++/WinRT projection تولیدشده استفاده می‌کند تا `webview_windows` روی این toolchain پایدار کامپایل شود.
- 🧭 Nearby discovery دیگر اعلان Sharing خود همان گوشی را در Receiving نشان نمی‌دهد.
- 🖤 ویجت‌های اندروید با طراحی مشکی بازطراحی شدند و ویجت‌های جدا برای Sending و Receiving اضافه شد.
- 🔔 اندروید هنگام باز شدن برنامه آپدیت را بررسی می‌کند و فقط وقتی نسخه جدید قابل نصب باشد اعلان داخلی نشان می‌دهد.
- 🏷️ اکشن انتشار GitHub فقط با تگ‌های `v*` کامپایل می‌کند، نه با هر push روی branch.

- 📱 FA: تب iOS برای همه IPهای فعال Sharing کانفیگ SOCKS مخصوص Xray و sing-box می‌سازد.
  EN: iOS QR tab now generates Xray and sing-box SOCKS configs for every active Sharing IP.
- 🧭 FA: بخش Proxy QR codes حالا تب‌های جدا برای Proxy و iOS دارد و QRها فقط با کلیک روی کارت باز می‌شوند.
  EN: Proxy QR codes now keep Proxy and iOS flows in separate tabs with click-to-open cards.
- 🪟 FA: در Receiving ویندوز گزینه Start as system proxy اضافه شد و حالت دستی به Start as local proxy تغییر نام داد.
  EN: Windows Receiving adds Start as system proxy and renames the manual mode to Start as local proxy.
- 🧹 FA: با توقف system proxy، تنظیمات پروکسی ویندوز به صورت خودکار پاک می‌شود.
  EN: Stopping Windows system proxy clears the Windows proxy settings automatically.
- 🛠️ FA: راه‌اندازی Wintun/tun2socks دسترسی ادمین را چک می‌کند، سطح لاگ درست `warn` را می‌فرستد و خطاهای مفید را نگه می‌دارد.
  EN: Wintun/tun2socks startup now checks administrator access, uses the correct `warn` log level, and preserves useful failure logs.
- 🚀 FA: اکشن انتشار GitHub خروجی‌های کامپایل‌شده را قبل از انتشار داخل `compiled` آماده می‌کند.
  EN: GitHub Actions release packaging keeps compiled assets staged in `compiled` before publishing.

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
- 🧩 `v3.2.0` - پاک‌سازی permissionها، تعمیر updater، ویجت، crash reporter، پرچم‌ها، رنگ‌ها و به‌روزرسانی README.
- 📱 `v3.3.0` - QR کانفیگ iOS برای Xray/sing-box، حالت system proxy ویندوز، اصلاح Wintun و آماده‌سازی بهتر release.
- 🧭 `v3.4.0` - فیلتر self-discovery، ویجت‌های مشکی اندروید، ویجت جدا برای Sending/Receiving، اعلان آپدیت هنگام شروع، و release build فقط با tag.
- 📲 `v3.5.0` - لینک SOCKS سازگار با v2rayNG برای QRهای Xray، backpressure ویندوز، throttle آمار ترافیک و پایداری build C++/WinRT.
- 🐞 `v3.5.4` - Active Debug Mode، ذخیره لاگ همراه جزئیات دستگاه، Retry در Nearby، راهنمایی iPhone hotspot، لاگ native اندروید و universal APK.

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

Universal release APK:

```powershell
flutter build apk --release `
  --target-platform android-arm,android-arm64,android-x64 `
  --obfuscate `
  --split-debug-info=build\symbols\android-universal `
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
build/app/outputs/flutter-apk/app-release.apk
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

workflow انتشار فقط با push تگ‌های `v*` یا اجرای دستی شروع می‌شود، مقدار `version:` را از `pubspec.yaml` می‌خواند و این فایل‌ها را upload می‌کند:

- `localist-v<version>-android-armeabi-v7a.apk`
- `localist-v<version>-android-arm64-v8a.apk`
- `localist-v<version>-android-x86_64.apk`
- `localist-v<version>-android-universal.apk`
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

- اندروید: discovery خودکار همراه Retry/Restart دستی، QR/manual config، draftهای ذخیره‌شده، اعتبارسنجی host/port، local proxy mode یا Android `VpnService`.
- ویندوز: discovery خودکار همراه Retry/Restart دستی، QR/manual config، draftهای ذخیره‌شده، اعتبارسنجی host/port، local proxy mode یا VPN mode با Wintun در صورت وجود ابزارهای bundled.

Settings:

- root routing فقط اندروید است.
- ویندوز برای VPN mode با administrator privileges شروع می‌شود، بنابراین toggle admin در Settings ندارد.
- رفتار دکمه close ویندوز می‌تواند ask، رفتن به taskbar tray یا exit کامل باشد.
- portهای proxy هنگام فعال بودن Sharing قفل می‌شوند.
- theme از Android dynamic colors یا Windows accent colors پیروی می‌کند و palette رنگ سفارشی گسترده‌تر شده است.
- Active Debug Mode فیلتر DEBUG را در Logs فعال می‌کند و trace دقیق سرویس‌ها، دکمه‌ها، native callها و شبکه را ثبت می‌کند.

Logs:

- Copy متن فعلی لاگ‌های داخل حافظه را کپی می‌کند.
- Save log دیالوگ ذخیره اندروید یا ویندوز را باز می‌کند و گزارش کامل شامل نسخه برنامه، build mode، جزئیات دستگاه، runtime، کارت‌های شبکه و لاگ‌های برنامه را می‌نویسد.

## Permission، آپدیتر، ویجت و گزارش کرش اندروید

در ورود اولیه اندروید فقط permissionهای ضروری شروع برنامه درخواست می‌شود:

- Notifications برای foreground serviceهای VPN/proxy.
- Battery optimization exemption برای جلوگیری از توقف انتقال طولانی هنگام خاموش شدن صفحه.

permission دوربین فقط هنگام باز کردن QR scanner در Receiving درخواست می‌شود. permission VPN فقط هنگام شروع حالت Android VPN Receiving درخواست می‌شود.

آپدیتر اندروید releaseهای GitHub را بررسی می‌کند، APK مناسب ABI دستگاه را انتخاب می‌کند، آن را در cache برنامه دانلود می‌کند، اندازه دانلود را اعتبارسنجی می‌کند و نصب‌کننده اندروید را باز می‌کند.

ویجت‌های اندروید در اندازه‌های کوچک و بزرگ home screen کار می‌کنند. ویجت کامل وضعیت سرویس را همراه کنترل‌های Sending و Receiving نشان می‌دهد و ویجت‌های تک‌دکمه‌ای برای Sending-only و Receiving-only اضافه شده‌اند. اگر Receiving تنظیمات remote proxy ذخیره‌شده نداشته باشد، ویجت برنامه را باز می‌کند. بررسی آپدیت هنگام شروع برنامه در صورت خطا چیزی نمایش نمی‌دهد و فقط وقتی آپدیت قابل نصب وجود داشته باشد اعلان داخلی نشان می‌دهد.

گزارش کرش شامل نوع کرش، زمان، نسخه semantic، پلتفرم، Android SDK/ABI، stack trace و لاگ‌های Localist است و email client را با متن آماده ارسال به پشتیبانی باز می‌کند.

## Windows VPN و Wintun

حالت Windows Receiving VPN وقتی `tun2socks.exe` و `wintun.dll` کنار `Localist.exe` باشند آن‌ها را اجرا می‌کند. workflow انتشار هر دو ابزار را برای بسته Windows x64 دانلود می‌کند و برنامه interface مربوط به Wintun، DNS، routeهای default split و bypass route برای upstream proxy انتخاب‌شده را تنظیم می‌کند.

اگر `tun2socks.exe` یا `wintun.dll` موجود نباشد، Windows Receiving به مسیر قبلی system-proxy fallback می‌کند تا buildهای development از checkout تمیز هم قابل استفاده باشند.

## نکته‌ها

حالت Windows TUN driver نیاز به administrator privileges و runtime امضاشده Wintun دارد. هنگام بسته‌بندی خارج از GitHub Actions، فایل‌های `tun2socks.exe` و `wintun.dll` را کنار executable ویندوز نگه دارید.
