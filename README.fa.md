<p align="center">
  <img src="ico/logo.png" alt="Localist" width="112" />
</p>

<h1 align="center">Localist</h1>

<p align="center" dir="rtl">
  اشتراک‌گذاری هوشمند VPN و انتقال سریع فایل بین Android، Windows و مرورگر دستگاه‌های Apple.
</p>

<p align="center">
  <strong>فارسی</strong> | <a href="README.md">English</a>
</p>

<p align="center">
  <a href="https://flutter.dev"><img alt="Flutter" src="https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white"></a>
  <a href="https://developer.android.com"><img alt="Android" src="https://img.shields.io/badge/Android-8.0%2B-3DDC84?logo=android&logoColor=white"></a>
  <a href="https://learn.microsoft.com/windows/apps/"><img alt="Windows" src="https://img.shields.io/badge/Windows-Desktop-0078D4?logo=windows&logoColor=white"></a>
  <a href="https://github.com/MBNpro-ir/localist/actions/workflows/release.yml"><img alt="Release" src="https://github.com/MBNpro-ir/localist/actions/workflows/release.yml/badge.svg"></a>
  <a href="https://github.com/MBNpro-ir/localist/releases"><img alt="Version" src="https://img.shields.io/badge/version-5.0.7-blue"></a>
</p>

## راهنمای کاربران

### Localist چه کاری انجام می‌دهد؟

Localist به دستگاه‌های داخل یک شبکه محلی اجازه می‌دهد دسترسی VPN/Proxy را به اشتراک بگذارند و بدون ارسال اطلاعات به سرویس ابری، فایل منتقل کنند.

- اتصال هوشمند VPN دستگاه Shareکننده را پیدا می‌کند، آدرس‌های مجاز آن را آزمایش می‌کند و خودکار از IP قابل دسترس استفاده می‌کند.
- بخش Android فقط یک QR/کانفیگ هوشمند شامل همه endpointهای مجاز دارد تا Localist خودکار IP قابل دسترس را انتخاب کند؛ بخش iPhone/Xray برای هر IP کانفیگ جدا نگه می‌دارد.
- صفحه Sharing تعداد و مشخصات دستگاه‌های Localist متصل را نشان می‌دهد.
- Quick Send فایل، رسانه، متن Clipboard، متن تایپی یا یک پوشه کامل را انتخاب و منتقل می‌کند و با پروتکل LocalSend v2.1 و مسیرهای قدیمی v1 سازگار است.
- Android می‌تواند یک Local-only Hotspot و صفحه انتقال مرورگری محافظت‌شده با Token بسازد تا بدون نصب Localist روی دستگاه اپل، فایل به‌صورت دوطرفه با iPhone، iPad و Mac جابه‌جا شود.
- Windows نیز همین صفحه انتقال مرورگری محافظت‌شده با Token را روی Wi-Fi، Ethernet، مودم یا Windows Mobile Hotspot اجرا می‌کند و QR ورود مستقیم را برای iPhone، iPad و Mac نشان می‌دهد.
- زبان فارسی و انگلیسی، تم روشن و تیره، رنگ پویا در اندروید و رنگ Accent ویندوز پشتیبانی می‌شوند.

### رابط و تنظیمات نسخه ۵.۰.۷

- در Windows، نوار عنوان برنامه با Flutter رسم می‌شود، اما Minimize، Maximize/Restore، Close و مدیریت خود پنجره همچنان native ویندوز هستند. نوار سمت چپ به‌صورت آیکن فشرده است و با Hover، متن دکمه‌ها را بدون جابه‌جایی یا Reflow صفحه نشان می‌دهد.
- Quick Send صفحهٔ آغازین برنامه است. در Android متن هر سه دکمهٔ ناوبری همیشه دیده می‌شود، فقط مقصد فعال آیکن دارد و جابه‌جایی صفحه و تغییر تم/رنگ نرم انجام می‌شود؛ مگر اینکه Animation سیستم خاموش باشد.
- در اولین اجرا، نام پیشنهادی دستگاه قابل ویرایش است و کاربر می‌تواند آواتار رنگی Material یا عکس محلی انتخاب کند. همین تنظیمات هویت بعداً نیز در Settings در دسترس است.
- گزینه **Settings** در بالای سمت راست Android و Windows قرار دارد و یک نمای مستقل و دسته‌بندی‌شده برای Profile، Quick Send، Network/Proxy، Appearance/Language، رفتار برنامه و Updates/About باز می‌کند.
- تغییرات معتبر Quick Send خودکار ذخیره می‌شوند. اگر نام دستگاه، پورت، آدرس Multicast، پوشه مقصد یا PIN لازم نامعتبر باشد، Localist آن را مشخص می‌کند و پیش از خروج از Settings یا بستن پنجره، امکان بازگردانی آخرین مقدار معتبر را می‌دهد.
- [تغییرات کامل نسخه ۵.۰.۷](CHANGELOG.md#507---2026-09-07) و [مقایسهٔ کامل GitHub از v5.0.0 تا v5.0.7](https://github.com/MBNpro-ir/localist/compare/v5.0.0...v5.0.7) را ببینید.

### دانلود و نصب

جدیدترین بسته را از [GitHub Releases](https://github.com/MBNpro-ir/localist/releases/latest) دانلود کنید.

- اندروید: APK نسخه **32-bit** برای `armeabi-v7a` و APK نسخه **64-bit** برای `arm64-v8a` منتشر می‌شود.
- ویندوز: فایل ZIP نسخه x64 را کامل Extract کنید و سپس `Localist.exe` را اجرا کنید. همه DLLها، ابزارها و `LocalistUpdater.exe` باید کنار فایل اجرایی باقی بمانند. آپدیت ویندوز از Settings دانلود، نصب و سپس Localist را خودکار اجرا می‌کند.
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

پیش از انتقال فایل، VPN خود دستگاه را خاموش کنید. هنگام فعال بودن هر VPN، هشدار قرمز نمایش داده می‌شود و سرویس‌های شبکه Quick Send تا خاموش شدن VPN متوقف می‌مانند.

1. روی هر دو دستگاه **Quick Send** را باز کنید؛ این صفحه هنگام شروع Localist به‌صورت پیش‌فرض باز می‌شود.
2. یکی از گزینه‌های **File**، **Media**، **Paste**، **Text** یا **Folder** را انتخاب کنید.
3. روی یک مقصد بزنید؛ یا روی دستگاه‌ها نگه دارید تا چند مقصد انتخاب شوند و انتقال هم‌زمان انجام شود.
4. اگر Quick Save فعال نیست، درخواست را روی دستگاه دریافت‌کننده تأیید کنید.

در Android می‌توانید از منوی Share برنامه‌های دیگر، **Localist** را انتخاب کنید تا فایل‌ها خودکار در Quick Send آماده شوند. در Windows می‌توانید فایل یا پوشه را روی هر قسمت پنجره Localist رها کنید؛ Quick Send خودکار باز می‌شود و موارد Drop‌شده انتخاب‌شده باقی می‌مانند. صفحهٔ **Transfer history** برای فایل‌های دریافتی گزارش کوتاه وضعیت و دکمه‌های **Share** و **Open** هر فایل را نشان می‌دهد. فقط یک گزینهٔ **Open received folder** برای کل پوشه مقصد وجود دارد و پاک‌کردن تاریخچه فقط رکوردها را حذف می‌کند، نه فایل‌های دانلودشده. فهرست زندهٔ **Transfers** نیز دکمهٔ **Clear** دارد.

برای اتصال دستی Quick Send، در دستگاه مقصد Quick Send را باز کنید و یکی از IPهای بخش **آدرس اتصال دستی این دستگاه** را کپی کنید. در دستگاه فرستنده کنار **Nearby devices** روی **+** بزنید و همان IP را همراه پورت و حالت HTTP/HTTPS نمایش‌داده‌شده در مقصد وارد کنید. هر دو دستگاه باید روی یک Wi-Fi یا Hotspot مشترک باشند و VPN آن‌ها خاموش باشد.

برای iPhone، iPad یا Mac از کارت **Send to iPhone or Mac** در انتهای صفحهٔ Quick Send استفاده کنید.

در Android:

1. سرویس هات‌اسپات خصوصی را شروع کنید.
2. QR شبکه Wi-Fi را با دستگاه اپل اسکن کنید. نداشتن اینترنت در این شبکه طبیعی و عمدی است.
3. QR جداگانه صفحه انتقال را اسکن کنید یا آدرس محلی را در Safari وارد کنید.
4. فایل‌های انتخاب‌شده در Localist را دانلود کنید یا فایل‌های دستگاه اپل را به پوشه دریافت Android بفرستید. فایل و متنی که پس از بازشدن Safari انتخاب می‌شود، بدون Refresh صفحه به‌صورت خودکار نمایش داده خواهد شد.

ممکن است سازنده دستگاه، سیاست Administrator یا روشن بودن Tethering دیگر، Local-only Hotspot خودکار را رد کند. در این حالت Localist وب‌سرور را فعال نگه می‌دارد، تنظیمات Hotspot سیستم را باز می‌کند و آدرس‌های شبکه را خودکار تازه می‌کند.

در Windows:

1. کامپیوتر و دستگاه اپل را به یک Wi-Fi/مودم وصل کنید؛ یا **Windows Mobile hotspot** را روشن و دستگاه اپل را به آن متصل کنید.
2. فایل، متن یا پوشه Drop‌شده را انتخاب و روی **Start web transfer and create QR** بزنید.
3. QR صفحه انتقال را با دوربین دستگاه اپل اسکن کنید یا یکی از آدرس‌های محلی نمایش‌داده‌شده را در Safari وارد کنید.
4. فایل‌های Windows را دانلود کنید یا فایل‌های Apple را به مسیر دریافت Quick Send بفرستید. با تغییر انتخاب‌ها در Windows، صفحه مرورگر خودکار به‌روزرسانی می‌شود.

دکمه Refresh کشف Multicast، Broadcast مستقیم و اسکن فعال Subnet را روی رابط‌های مجاز Wi-Fi، Ethernet، Hotspot و USB Tethering تکرار می‌کند. کابل USB در حالت فقط شارژ شبکه IP ایجاد نمی‌کند؛ برای انتقال از کابل، USB Tethering را فعال کنید.

تنظیمات Quick Send شامل موارد زیر است:

- پروفایل دستگاه، پورت دریافت و گروه Multicast. Localist مدل Android را پیشنهاد می‌دهد، اما کاربر می‌تواند یک نام معتبر تا ۳۲ کاراکتر قابل‌درک برای کاربر، همراه ایموجی، و یک آواتار یا عکس انتخاب کند.
- پوشه مقصد و رفتار جایگزینی فایل تکراری. مسیر پیش‌فرض Android برابر `/storage/emulated/0/Localist` است و فایل‌ها داخل پوشه‌های `Images`، `Videos`، `Audio`، `Documents`، `Archives`، `Apps` و `Other` قرار می‌گیرند؛ با انتخاب مسیر سفارشی این دسته‌بندی خودکار غیرفعال می‌شود.
- رمزنگاری HTTPS همراه تطبیق Fingerprint گواهی.
- PIN اختیاری برای دستگاه دریافت‌کننده.
- دستگاه‌های موردعلاقه و Quick Save عمومی یا فقط برای Favorites.
- مقصد دستی با IP یا Hostname برای شبکه‌هایی که Multicast در آن‌ها کار نمی‌کند.

Quick Save فایل‌ها را بدون سؤال می‌پذیرد؛ آن را فقط در شبکه‌های قابل اعتماد فعال کنید. دریافت پیام متنی همیشه نیازمند تأیید صریح است.

درخواست دستی دریافتی به‌صورت Popup تأیید/رد روی صفحهٔ فعال نمایش داده می‌شود و دیگر کارت غیرفعال داخل صفحه نیست. در استفادهٔ عادی پس‌زمینه، Android سرویس دریافت را فعال نگه می‌دارد و وقتی Localist پشت برنامه‌های دیگر است، Android یا Windows اعلان سیستمی می‌فرستد. با زدن روی اعلان، Localist به جلو می‌آید، Quick Send باز می‌شود و درخواست در انتظار نمایش داده می‌شود. Quick Save Popup دستی ندارد؛ اگر دریافت خودکار زمانی انجام شود که کاربر در صفحه‌ای دیگر داخل Localist است، یک اعلان داخلی کوچک نمایش داده می‌شود.

### حالت‌های هر پلتفرم

| پلتفرم | Sharing | Receiving | Quick Send |
| --- | --- | --- | --- |
| Android | پروکسی HTTP/SOCKS5، مسیر Hotspot/Manual و Root Routing اختیاری | Android VPN یا Local Proxy | ارسال و دریافت فایل/پیام و پل محلی Safari برای دستگاه اپل |
| Windows | پروکسی HTTP/SOCKS5 و Upstream اختیاری v2rayN | VPN با Wintun، System Proxy یا Local Proxy | ارسال و دریافت فایل/پیام، Drag & Drop و پل محلی Safari برای دستگاه اپل |

حالت VPN ویندوز به دسترسی Administrator و فایل‌های `tun2socks.exe` و `wintun.dll` نیاز دارد. بدون این ابزارها همچنان می‌توان از System Proxy یا Local Proxy استفاده کرد.

### Permission و اطلاعات محلی

- اندروید برای ادامه سرویس‌های VPN/Proxy در پس‌زمینه، Notification و Battery Optimization access درخواست می‌کند. هنگام فعال بودن دریافت Quick Send، یک Foreground Service کم‌اهمیت از نوع Connected Device اجرا می‌شود.
- Android 17 پیش از Discovery و دریافت، مجوز Local Network را درخواست می‌کند؛ نسخه‌های قدیمی‌تر این مجوز Runtime را ندارند.
- دسترسی دوربین فقط هنگام باز کردن QR Scanner درخواست می‌شود.
- مجوز Android VPN فقط هنگام شروع VPN در Receiving درخواست می‌شود.
- برای ساخت هات‌اسپات خصوصی انتقال به Apple/Mac، دسترسی Nearby Wi-Fi درخواست می‌شود؛ در Android 12 و قدیمی‌تر مجوز Location جای آن استفاده می‌شود.
- مجوز مدیریت فایل Android فقط برای استفاده از پوشه پیش‌فرض `/Localist` در ریشه حافظه مشترک درخواست می‌شود.
- فایل‌های Quick Send داخل شبکه محلی باقی می‌مانند و حالت HTTPS اثرانگشت گواهی مقصد را بررسی می‌کند.
- تنظیمات، هویت Profile، Favorites، هویت گواهی، تنظیمات انتقال و تاریخچهٔ فایل دریافتی در App Data همان پلتفرم ذخیره می‌شوند. عکس Profile به یک Thumbnail محلی کوچک تبدیل می‌شود.

### لاگ و رفع مشکل

- صفحه **Logs** امکان مشاهده، Copy و ذخیره گزارش تشخیصی را می‌دهد.
- Active Debug Mode رویدادهای دقیق سرویس، Native Bridge و شبکه را ثبت می‌کند.
- در ویندوز فایل `debug.log` کنار `Localist.exe` ساخته می‌شود. اندازه پیام‌ها و فایل محدود است و لاگ بزرگ خودکار Rotate می‌شود.
- اگر بررسی آپدیت ویندوز با خطای اعتبارسنجی گواهی روبه‌رو شود، Localist درخواست GitHub را فقط از طریق `curl.exe` و Certificate Store ویندوز دوباره امتحان می‌کند. خطاهای دیگر شبکه همچنان به‌شکل عادی گزارش می‌شوند.
- خطاهای قابل‌بازیابی UI فقط ثبت می‌شوند و دیگر پنجره Crash را پشت‌سرهم باز نمی‌کنند. گزارش خطای Fatal نیز تکراری نمایش داده نمی‌شود.
- اگر Nearby Devices خالی است، یکسان بودن Subnet یا فعال بودن USB Tethering، خاموش بودن Guest/Client Isolation و دکمه Refresh را بررسی کنید یا مقصد را دستی وارد کنید.
- اگر هشدار قرمز VPN دیده می‌شود، پیش از تلاش دوباره برای Quick Send یا سرویس مرورگری Apple/Mac، VPN دستگاه را متوقف کنید.
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

- Flutter 3.47.2 Stable با Windows Desktop Support و Dart 3.12 یا جدیدتر.
- Android SDK Platform 37 و JDK 17.
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

APKهای Release برای دو معماری منتشرشده:

```powershell
flutter build apk --release `
  --split-per-abi `
  --target-platform android-arm,android-arm64 `
  --tree-shake-icons
```

### Build ویندوز

```powershell
flutter build windows --release `
  --tree-shake-icons
```

خروجی داخل `build/windows/x64/runner/Release/` قرار می‌گیرد. بسته قابل انتشار باید تمام این پوشه، Flutter Runtime، ابزارهای Wintun و `LocalistUpdater.exe` را همراه داشته باشد. Runner در هر Build فایل Updater را کنار `Localist.exe` کپی می‌کند؛ هنگام آپدیت، Helper از یک کپی موقت خصوصی اجرا شده و محتوای ZIP جدید را جایگزین می‌کند.

### Workflow انتشار

فایل `.github/workflows/release.yml` با اجرای دستی روی `master` یا Push تگ `v*` شروع می‌شود. نسخه را از `pubspec.yaml` می‌خواند، Android و Windows را هم‌زمان Build می‌کند، فایل‌های کامپایل‌شده را Stage می‌کند و GitHub Release متناظر را می‌سازد یا به‌روزرسانی می‌کند. متن کوتاه GitHub Release از بخش متناظر `## [x.y.z]` در `RELEASE_NOTES.md` خوانده می‌شود و changelog کامل همچنان داخل `CHANGELOG.md` می‌ماند. اگر بخش Release Notes وجود نداشته باشد، انتشار قبل از Publish متوقف می‌شود.

خروجی‌های انتشار:

- APK نسخه Android 32-bit برای `armeabi-v7a`.
- APK نسخه Android 64-bit برای `arm64-v8a`.
- ZIP نسخه Windows 64-bit.

شروع Release با Tag:

```powershell
$version = ((Select-String -Path pubspec.yaml -Pattern '^version:\s*(.+)$').Matches[0].Groups[1].Value -split '\+')[0]
git tag "v$version"
git push origin "v$version"
```

برای اجرای دستی، از صفحه Actions مخزن workflow با نام **Release** را اجرا کنید و `release_tag` را خالی بگذارید تا نسخه `pubspec.yaml` استفاده شود.

برای انتشار صریح یک نسخه از `master`، ابتدا کامیت انتشار را Push کنید و سپس اجرا کنید:

```powershell
gh workflow run release.yml --repo MBNpro-ir/localist --ref master -f release_tag="v5.0.7"
```

### نکات معماری

- Discovery برنامه و Heartbeat دستگاه‌های متصل از پورت‌های UDP جدا از Endpointهای Proxy استفاده می‌کنند.
- کانفیگ هوشمند یک Device Identity پایدار دارد. Receiver فقط اجازه دارد Host یک Endpoint را با Source Address همان دستگاه کشف‌شده بازنویسی کند.
- بررسی SOCKS5 شامل Handshake پروتکل است و بررسی HTTP قبل از انتخاب مسیر، پاسخ Proxy-Form را اعتبارسنجی می‌کند.
- Quick Send برای هر رابط مجاز Listener جدا می‌سازد، اعلان را از IP واقعی همان رابط می‌فرستد، سپس از Broadcast مستقیم و اسکن هم‌زمان و محدود `/24` استفاده می‌کند؛ Discovery هیچ‌وقت از `0.0.0.0` ارسال نمی‌شود.
- در Android پردازش Localist برای ایمنی Control Plane از TUN خودش مستثنا می‌ماند، اما Quick Send هنگام فعال بودن هر VPN عمداً HTTP/UDP خود را می‌بندد و فقط بعد از خاموش شدن VPN دوباره آن‌ها را راه‌اندازی می‌کند.
- Quick Send، Token و Source Address آپلود را بررسی می‌کند، اندازه Metadata را محدود می‌کند، ساختار امن پوشه را حفظ و تلاش برای Path Traversal را پاک‌سازی می‌کند و Session بدون فعالیت را منقضی می‌کند.
- پل Apple/Mac از URL دارای Token تصادفی، آپلود Multipart استریم‌شده و همان سیاست دسته‌بندی پوشه دریافت استفاده می‌کند. Android علاوه بر آن می‌تواند `LocalOnlyHotspot` و QR جدا برای Wi-Fi و صفحه مرورگر بسازد؛ Windows نیز QR مرورگر را روی رابط‌های مجاز Wi-Fi، Ethernet، مودم یا Mobile Hotspot ارائه می‌کند و رابط‌های مجازی/VPN را کنار می‌گذارد.
- Runner ویندوز هم پنجره اصلی و هم سطح Flutter را به‌عنوان Drop Target ثبت می‌کند، پیام‌های لازم UIPI را برای اجرای Administrator می‌پذیرد و فایل‌های Drop‌شده را تا آماده‌شدن Quick Send در صف نگه می‌دارد.
- Job ویندوز قبل از Build، فایل‌های امضاشده Wintun و Runtime مربوط به tun2socks را دریافت می‌کند.

### مجوز و Attribution

Quick Send بر پایه پروژه LocalSend با مجوز Apache-2.0 ساخته شده است. Attribution و متن کامل مجوز داخل `THIRD_PARTY_NOTICES.md` قرار دارد و همراه Assetهای برنامه بسته‌بندی می‌شود.
