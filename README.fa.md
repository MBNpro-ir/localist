<p align="center">
  <img src="ico/logo.png" alt="Localist" width="112" />
</p>

<h1 align="center">Localist</h1>

<p align="center" dir="rtl">
  اشتراک‌گذاری هوشمند VPN و انتقال سریع فایل بین اندروید و ویندوز.
</p>

<p align="center">
  <strong>فارسی</strong> | <a href="README.md">English</a>
</p>

<p align="center">
  <a href="https://flutter.dev"><img alt="Flutter" src="https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white"></a>
  <a href="https://developer.android.com"><img alt="Android" src="https://img.shields.io/badge/Android-8.0%2B-3DDC84?logo=android&logoColor=white"></a>
  <a href="https://learn.microsoft.com/windows/apps/"><img alt="Windows" src="https://img.shields.io/badge/Windows-Desktop-0078D4?logo=windows&logoColor=white"></a>
  <a href="https://github.com/MBNpro-ir/localist/actions/workflows/release.yml"><img alt="Release" src="https://github.com/MBNpro-ir/localist/actions/workflows/release.yml/badge.svg"></a>
  <a href="https://github.com/MBNpro-ir/localist/releases"><img alt="Version" src="https://img.shields.io/badge/version-3.6.0-blue"></a>
</p>

## راهنمای کاربران

### Localist چه کاری انجام می‌دهد؟

Localist به دستگاه‌های داخل یک شبکه محلی اجازه می‌دهد دسترسی VPN/Proxy را به اشتراک بگذارند و بدون ارسال اطلاعات به سرویس ابری، فایل منتقل کنند.

- اتصال هوشمند VPN دستگاه Shareکننده را پیدا می‌کند، آدرس‌های مجاز آن را آزمایش می‌کند و خودکار از IP قابل دسترس استفاده می‌کند.
- QR و کانفیگ هوشمند همه endpointهای موجود را همراه دارند و کاربر مجبور نیست IP درست را حدس بزند.
- صفحه Sharing تعداد و مشخصات دستگاه‌های Localist متصل را نشان می‌دهد.
- Quick Send چند فایل یا پیام متنی را منتقل می‌کند و با پروتکل LocalSend v2.1 و مسیرهای قدیمی v1 سازگار است.
- زبان فارسی و انگلیسی، تم روشن و تیره، رنگ پویا در اندروید و رنگ Accent ویندوز پشتیبانی می‌شوند.

### دانلود و نصب

جدیدترین بسته را از [GitHub Releases](https://github.com/MBNpro-ir/localist/releases/latest) دانلود کنید.

- اندروید: اگر معماری دستگاه را نمی‌دانید از Universal APK استفاده کنید. APKهای مخصوص هر ABI حجم کمتری دارند.
- ویندوز: فایل ZIP نسخه x64 را کامل Extract کنید و سپس `Localist.exe` را اجرا کنید. همه DLLها و ابزارهای کنار فایل اجرایی باید حفظ شوند.
- هر دو دستگاه باید به یک Wi-Fi، Ethernet یا Hotspot مشترک وصل باشند. قابلیت Client Isolation در شبکه مهمان می‌تواند discovery و اتصال محلی را مسدود کند.

### اشتراک‌گذاری VPN یا Proxy

روی دستگاهی که اینترنت یا VPN موردنظر روی آن فعال است:

1. بخش **Sharing** را باز کنید.
2. پروتکل‌ها و آدرس‌های شبکه مجاز را انتخاب کنید.
3. Sharing را شروع کنید.
4. در همین صفحه می‌توانید تعداد و نام دستگاه‌های Localist متصل را ببینید.

روی دستگاه دریافت‌کننده:

1. بخش **Receiving** را باز کنید.
2. دستگاه را از Nearby Devices انتخاب کنید، QR آن را اسکن کنید یا کانفیگ هوشمند را Paste کنید.
3. Localist مسیرهای مجاز را آزمایش کرده و IP قابل دسترس را خودکار انتخاب می‌کند.
4. یکی از حالت‌های VPN، System Proxy یا Local Proxy موجود را شروع کنید.

کانفیگ خام `http://` و `socks5://` نیز پذیرفته می‌شود. کانفیگ خام فقط از همان Host واردشده استفاده می‌کند و Localist هیچ‌وقت دستگاه دیگری را صرفاً به‌دلیل پورت یکسان جایگزین مقصد نمی‌کند.

### انتقال فایل با Quick Send

1. روی هر دو دستگاه **Quick Send** را باز کنید.
2. یک یا چند فایل انتخاب کنید یا **Send message** را بزنید.
3. دستگاه مقصد پیدا‌شده در شبکه محلی را انتخاب کنید.
4. اگر Quick Save فعال نیست، درخواست را روی دستگاه دریافت‌کننده تأیید کنید.

تنظیمات Quick Send شامل موارد زیر است:

- نام دستگاه، پورت دریافت و گروه Multicast.
- پوشه مقصد و رفتار جایگزینی فایل تکراری.
- رمزنگاری HTTPS همراه تطبیق Fingerprint گواهی.
- PIN اختیاری برای دستگاه دریافت‌کننده.
- دستگاه‌های موردعلاقه و Quick Save عمومی یا فقط برای Favorites.
- مقصد دستی با IP یا Hostname برای شبکه‌هایی که Multicast در آن‌ها کار نمی‌کند.

Quick Save فایل‌ها را بدون سؤال می‌پذیرد؛ آن را فقط در شبکه‌های قابل اعتماد فعال کنید. دریافت پیام متنی همیشه نیازمند تأیید صریح است.

### حالت‌های هر پلتفرم

| پلتفرم | Sharing | Receiving | Quick Send |
| --- | --- | --- | --- |
| Android | پروکسی HTTP/SOCKS5، مسیر Hotspot/Manual و Root Routing اختیاری | Android VPN یا Local Proxy | ارسال و دریافت فایل/پیام |
| Windows | پروکسی HTTP/SOCKS5 و Upstream اختیاری v2rayN | VPN با Wintun، System Proxy یا Local Proxy | ارسال و دریافت فایل/پیام |

حالت VPN ویندوز به دسترسی Administrator و فایل‌های `tun2socks.exe` و `wintun.dll` نیاز دارد. بدون این ابزارها همچنان می‌توان از System Proxy یا Local Proxy استفاده کرد.

### Permission و اطلاعات محلی

- اندروید برای ادامه سرویس‌های VPN/Proxy در پس‌زمینه، Notification و Battery Optimization access درخواست می‌کند.
- دسترسی دوربین فقط هنگام باز کردن QR Scanner درخواست می‌شود.
- مجوز Android VPN فقط هنگام شروع VPN در Receiving درخواست می‌شود.
- فایل‌های Quick Send داخل شبکه محلی باقی می‌مانند و حالت HTTPS اثرانگشت گواهی مقصد را بررسی می‌کند.
- تنظیمات، Favorites، هویت گواهی و تنظیمات انتقال در پوشه App Data همان پلتفرم ذخیره می‌شوند.

### لاگ و رفع مشکل

- صفحه **Logs** امکان مشاهده، Copy و ذخیره گزارش تشخیصی را می‌دهد.
- Active Debug Mode رویدادهای دقیق سرویس، Native Bridge و شبکه را ثبت می‌کند.
- در ویندوز فایل `debug.log` کنار `Localist.exe` ساخته می‌شود. اندازه پیام‌ها و فایل محدود است و لاگ بزرگ خودکار Rotate می‌شود.
- خطاهای قابل‌بازیابی UI فقط ثبت می‌شوند و دیگر پنجره Crash را پشت‌سرهم باز نمی‌کنند. گزارش خطای Fatal نیز تکراری نمایش داده نمی‌شود.
- اگر Nearby Devices خالی است، یکسان بودن Subnet، خاموش بودن Guest/Client Isolation و دکمه Retry را بررسی کنید یا مقصد را دستی وارد کنید.
- اگر VPN ویندوز شروع نمی‌شود، دسترسی Administrator و باقی‌ماندن فایل‌های Wintun داخل بسته Extractشده را بررسی کنید.

## راهنمای توسعه‌دهندگان

### ساختار مخزن

```text
lib/                       رابط Flutter، کشف هوشمند VPN، Quick Send، تنظیمات و سرویس‌ها
android/                   Bridge اندروید، VPN/Proxy، آپدیتر، ویجت و Gradle
windows/                   Runner ویندوز، Win32 Bridge، بسته‌بندی Wintun و منابع
test/                      بررسی‌های رگرسیون و پروتکل
.github/workflows/         Build اندروید/ویندوز و انتشار GitHub Release
ico/                       آیکن‌های برنامه
```

### ابزارهای لازم

- Flutter Stable با Windows Desktop Support.
- Android SDK Platform 35 یا جدیدتر و JDK 17.
- Visual Studio 2022 با **Desktop development with C++**.
- WebView2 Runtime روی Windows 10/11 برای QR Scanner وب‌کم.
- 7-Zip برای بسته‌بندی محلی نسخه ویندوز.

آماده‌سازی Clone تازه:

```powershell
flutter doctor -v
flutter config --enable-windows-desktop
flutter pub get
flutter doctor --android-licenses
```

### Build اندروید

Debug APK:

```powershell
flutter build apk --debug
```

APKهای Release جدا برای هر ABI:

```powershell
flutter build apk --release `
  --split-per-abi `
  --target-platform android-arm,android-arm64,android-x64 `
  --obfuscate `
  --split-debug-info=build\symbols\android `
  --tree-shake-icons
```

Universal APK و Android App Bundle:

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

### Build ویندوز

```powershell
flutter build windows --release `
  --obfuscate `
  --split-debug-info=build\symbols\windows-x64 `
  --tree-shake-icons
```

خروجی داخل `build/windows/x64/runner/Release/` قرار می‌گیرد. بسته قابل انتشار باید تمام این پوشه، Flutter Runtime و ابزارهای Wintun را همراه داشته باشد.

### Workflow انتشار

فایل `.github/workflows/release.yml` با اجرای دستی یا Push تگ `v*` شروع می‌شود. نسخه را از `pubspec.yaml` می‌خواند، Android و Windows را هم‌زمان Build می‌کند، فایل‌های کامپایل‌شده را Stage می‌کند و GitHub Release متناظر را می‌سازد یا به‌روزرسانی می‌کند.

خروجی‌های انتشار:

- Universal، armeabi-v7a، arm64-v8a و x86_64 APK.
- Universal Android AAB.
- ZIP نسخه Windows x64.
- آرشیوهای جداگانه Symbol برای Android و Windows.

شروع Release با Tag:

```powershell
$version = ((Select-String -Path pubspec.yaml -Pattern '^version:\s*(.+)$').Matches[0].Groups[1].Value -split '\+')[0]
git tag "v$version"
git push origin "v$version"
```

برای اجرای دستی، از صفحه Actions مخزن workflow با نام **Release** را اجرا کنید و `release_tag` را خالی بگذارید تا نسخه `pubspec.yaml` استفاده شود.

### نکات معماری

- Discovery برنامه و Heartbeat دستگاه‌های متصل از پورت‌های UDP جدا از Endpointهای Proxy استفاده می‌کنند.
- کانفیگ هوشمند یک Device Identity پایدار دارد. Receiver فقط اجازه دارد Host یک Endpoint را با Source Address همان دستگاه کشف‌شده بازنویسی کند.
- بررسی SOCKS5 شامل Handshake پروتکل است و بررسی HTTP قبل از انتخاب مسیر، پاسخ Proxy-Form را اعتبارسنجی می‌کند.
- Quick Send از Multicast و مسیرهای HTTP(S) پروتکل LocalSend استفاده می‌کند، Token و Source Address آپلود را بررسی می‌کند، اندازه Metadata را محدود می‌کند، نام مقصد را پاک‌سازی می‌کند و Session بدون فعالیت را منقضی می‌کند.
- Job ویندوز قبل از Build، فایل‌های امضاشده Wintun و Runtime مربوط به tun2socks را دریافت می‌کند.

### مجوز و Attribution

Quick Send بر پایه پروژه LocalSend با مجوز Apache-2.0 ساخته شده است. Attribution و متن کامل مجوز داخل `THIRD_PARTY_NOTICES.md` قرار دارد و همراه Assetهای برنامه بسته‌بندی می‌شود.
