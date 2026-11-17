# گزارش فارسی Developer Bridge V2 برای بازبینی

تاریخ: ۱۴۰۵/۰۸/۲۶

## سناریویی که می‌خواهیم حل کنیم

هدف این قابلیت، توسعهٔ Android با گوشی سامسونگ بدون اتصال USB و بدون نیاز به Wireless Debugging است. دو مسیر در نظر گرفته شده‌اند:

1. گوشی هات‌اسپات می‌دهد و رایانه به همان هات‌اسپات متصل است.
2. گوشی و رایانه در شبکه‌های جدا هستند و ارتباط از اینترنت با RustDesk برقرار می‌شود.

در هر دو مسیر باید یک Android Developer Agent روی Localist Android اجرا شود و همان پروتکل کاربردی را به Localist Windows بدهد. در مسیر اینترنت، RustDesk باید TCP را از `127.0.0.1:15555` ویندوز به `127.0.0.1:48291` گوشی تونل کند. سپس Android Studio باید از طریق ADB رسمی، endpoint محلی ویندوز را ببیند.

خواستهٔ فعلی کاربر برای آزمایش اینترنت محدودتر است: کافی است Android Studio دستگاه را بشناسد؛ لازم نیست همین حالا Tunneler یا APK دیگری روی گوشی اجرا شود.

## معماری و کدهای ایجادشده

### عامل توسعهٔ Android

- `android/app/src/main/kotlin/com/prs/localist/AndroidDeveloperAgent.kt` یک Listener کاربردی TLS روی پورت ثابت `48291` فراهم می‌کند. Listener فقط پس از شروع صریح کاربر فعال می‌شود.
- جفت‌سازی با کد کوتاه‌عمر، HMAC و اثرانگشت گواهی انجام می‌شود؛ سرور در معرض شبکه قرار نمی‌گیرد مگر وقتی Agent فعال است.
- APK دریافتی از نظر اندازه، SHA-256 و اطلاعات بسته بررسی می‌شود. نصب بی‌صدا انجام نمی‌شود؛ Package Installer اندروید و تأیید کاربر لازم است.
- `android/app/src/main/kotlin/com/prs/localist/MainActivity.kt` کانال Native/Flutter را برای شروع، توقف و وضعیت Agent و بررسی بسته، وضعیت فرآیند و اجرای Intent مجاز فراهم می‌کند. اجرای برنامه به foreground بودن Activity و وجود Launch Intent وابسته است.
- `lib/screens/android_developer_agent_page.dart` صفحهٔ کنترل Agent در Localist Android است.

### انتقال مشترک Local LAN و RustDesk

- `lib/services/developer_agent_transport.dart` پروتکل کاربردی TLS، pin کردن گواهی، جفت‌سازی، Echo، انتقال APK و قطع ارتباط را برای هر دو Adapter مشترک می‌کند: `LocalLanTransport` و `RustDeskRemoteTransport`.
- `lib/screens/developer_bridge_page.dart` رابط ویندوز است؛ مسیر اینترنت را پیش‌فرض می‌گذارد و مقصد تونل Agent را روی `127.0.0.1:48291` تنظیم می‌کند.
- `lib/services/rustdesk_debug_service.dart` ساخت نشست RustDesk از نوع port-forward را به UI Developer Bridge متصل می‌کند.
- `lib/remote/desktop_host_bridge.dart` درخواست نشست را اعتبارسنجی می‌کند و فقط مقصد loopback برای تونل Agent می‌پذیرد. `lib/remote/embedded_remote_app.dart` درخواست را به میزبان RustDesk می‌سپارد.
- `lib/remote/android_remote_host.dart` و `third_party/localist_remote/lib/models/server_model.dart` رضایت تونل را جدا از کنترل صفحه نمایش می‌دهند و مقصد درخواستی را نشان می‌دهند.
- `third_party/localist_remote/lib/desktop/pages/port_forward_page.dart`, `port_forward_tab_page.dart` و `third_party/localist_remote/lib/utils/multi_window_manager.dart` نگاشت اولیهٔ پورت را در نشست تازه و نشست/تب از قبل بازشده اعمال می‌کنند.

### Virtual ADB ویندوز

- `lib/services/virtual_adb_endpoint_service.dart` یک endpoint آزمایشی ADB را فقط روی Loopback ویندوز باز می‌کند و پیام CNXN و قاب‌بندی پایهٔ ADB را پاسخ می‌دهد.
- این PoC فعلاً هویت نمونهٔ Localist دارد و به Android Developer Agent یا سامسونگ متصل نشده است. درخواست‌های shell، sync، install و JDWP را موفق جلوه نمی‌دهد؛ سرویس‌های پشتیبانی‌نشده با بستن stream رد می‌شوند.
- `lib/services/developer_bridge_adb_service.dart` مدیریت ADB رسمی ویندوز و نمایش endpoint را پشتیبانی می‌کند.
- `tools/virtual_adb_endpoint_poc.dart` و `tools/developer_bridge_model_check.dart` برای بررسی مستقل پروتکل و مدل‌ها هستند.

### مستندات و آزمون‌های قابل تکرار

- اسناد مراحل و بررسی‌های قبلی در `docs/developer_bridge/01` تا `12` قرار دارند.
- `tools/developer_agent_transport_poc.dart` و `tools/developer_agent_rustdesk_transport_poc.dart` برای Echo، جفت‌سازی، انتقال و اعتبارسنجی فایل، قطع و اتصال مجدد استفاده می‌شوند.
- `test/developer_bridge_models_test.dart` آزمون مدل‌های قابلیت است؛ تغییر `test/remote_host_presence_test.dart` نیز بخش مربوط به میزبان ویندوز را پوشش می‌دهد.

## شواهدی که تا اینجا داریم

موارد زیر از اجراهای ثبت‌شدهٔ قبلی‌اند و در این نوبت دوباره اجرا نشده‌اند:

- آزمون مدل‌های Developer Bridge و آزمون‌های میزبان RustDesk اجرا شده‌اند؛ اجرای آخر آزمون `remote_host_presence_test.dart` با ۱۳ مورد موفق گزارش شده است.
- ساخت Windows انجام شده و باندل ایزوله اجرا شده است.
- Agent روی Emulator با ADB forwarding آزمایشگاهی جفت‌سازی، Echo، انتقال/اعتبارسنجی APK، قطع و اتصال مجدد را گذرانده است. نصب آزمایشی Emulator از Package Installer و تأیید سیستم هم ثبت شده است.
- این ADB forwarding آزمایشگاهی، مسیر واقعی اینترنت یا اتصال USB-free گوشی را اثبات نمی‌کند.
- اجرای رسمی `adb devices -l` در یک آزمایش قبلی endpoint نمونه را فهرست کرده؛ Android Studio 2026.2.1 آن را به‌عنوان دستگاه قابل استقرار/دیباگ نپذیرفته و گزارش کرده که transport توسط provisioner پشتیبانی‌شده claim نشده است.
- RustDesk گوشی Online دیده شده و کاربر درخواست کنترل صفحه را تأیید کرده است؛ بااین‌حال در آزمایش پورت‌فوروارد واقعی، اتصال TLS Agent برقرار نشد: یک بار handshake قطع شد و در تلاش بعدی listener محلی وجود نداشت و اتصال رد شد.
- هات‌اسپات واقعی و ارتباط Agent از اینترنت هنوز قبولی عملی ندارند. مشاهدهٔ Samsung در ADB مستقیمِ ویندوز، مدرک مسیر اینترنت نیست.
- نصب یا اجرای Tunneler از Android Studio روی سامسونگ، Logcat واقعی، breakpoint، Step و JDWP هنوز پیاده‌سازی/اثبات نشده‌اند.

## محدودیت مهم سازگاری

فهرست‌شدن در `adb devices` با شناسایی به‌عنوان دستگاه قابل اجرا در Android Studio یکسان نیست. شناسایی ساده با پاسخ ADB ممکن است، اما چرخهٔ توسعهٔ Android Studio به سرویس‌های واقعی دستگاه مثل shell و کشف package/process وابسته است. Agent معمولی Localist مجوز `adbd`، shell سیستمی 