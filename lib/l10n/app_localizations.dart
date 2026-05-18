import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AppLocalizations {
  const AppLocalizations(this.locale);

  final Locale locale;

  static const supportedLocales = [Locale('en'), Locale('fa')];

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static Locale? resolve(Locale? locale, Iterable<Locale> supportedLocales) {
    if (locale == null) {
      return supportedLocales.first;
    }
    for (final supported in supportedLocales) {
      if (supported.languageCode == locale.languageCode) {
        return supported;
      }
    }
    return supportedLocales.first;
  }

  bool get isPersian => locale.languageCode == 'fa';

  String _s(String fa, String en) => isPersian ? fa : en;

  String get appName => 'Localist';
  String get sharing => _s('اشتراک‌گذاری', 'Sharing');
  String get receiving => _s('دریافت', 'Receiving');
  String get settings => _s('تنظیمات', 'Settings');
  String get logs => _s('گزارش‌ها', 'Logs');
  String get stats => _s('آمار', 'Stats');
  String get appGuide => _s('راهنمای برنامه', 'App guide');
  String get shareApk => _s('اشتراک‌گذاری APK', 'Share APK');
  String get lightMode => _s('حالت روشن', 'Light mode');
  String get darkMode => _s('حالت تاریک', 'Dark mode');
  String get cancel => _s('لغو', 'Cancel');
  String get ok => _s('باشه', 'OK');
  String get openSettings => _s('باز کردن تنظیمات', 'Open settings');
  String get refresh => _s('تازه‌سازی', 'Refresh');
  String get close => _s('بستن', 'Close');
  String get active => _s('فعال', 'Active');
  String get ready => _s('آماده', 'Ready');
  String get detected => _s('شناسایی شد', 'Detected');
  String get inactive => _s('غیرفعال', 'Inactive');
  String get idle => _s('آماده به کار', 'Idle');
  String get loading => _s('در حال بارگذاری', 'Loading');
  String get required => _s('الزامی است', 'Required');
  String get numbersOnly => _s('فقط عدد وارد کنید', 'Numbers only');
  String get portRange1To65535 => _s('از 1 تا 65535 وارد کنید', 'Use 1-65535');
  String get portRange1024To65535 =>
      _s('از 1024 تا 65535 وارد کنید', 'Use 1024-65535');
  String get useDifferentPort =>
      _s('یک پورت دیگر انتخاب کنید', 'Use a different port');
  String get noSpaces => _s('فاصله مجاز نیست', 'No spaces');
  String get hostOnly => _s('فقط میزبان را وارد کنید', 'Host only');
  String get invalidHost => _s('میزبان نامعتبر است', 'Invalid host');

  String get languageStep => _s('زبان', 'Language');
  String get permissionsStep => _s('دسترسی‌ها', 'Permissions');
  String get mainStep => _s('برنامه', 'App');
  String get languageTitle =>
      _s('زبان Localist را انتخاب کنید', 'Choose Localist language');
  String get languageSubtitle => _s(
    'می‌توانید زبان برنامه را همین حالا انتخاب کنید یا بگذارید با زبان دستگاه هماهنگ شود.',
    'Pick a language now, or let Localist follow your device language.',
  );
  String get languageSystem => _s('زبان دستگاه', 'Device language');
  String get languageSystemSubtitle => _s(
    'Localist بین فارسی و انگلیسی بر اساس زبان دستگاه جابه‌جا می‌شود.',
    'Localist switches between Persian and English from your device.',
  );
  String get languageEnglish => _s('انگلیسی', 'English');
  String get languageEnglishSubtitle =>
      _s('رابط برنامه انگلیسی می‌ماند.', 'Keep the app in English.');
  String get languagePersian => _s('فارسی', 'Persian');
  String get languagePersianSubtitle =>
      _s('رابط برنامه فارسی می‌شود.', 'Use the Persian interface.');
  String get continueButton => _s('ادامه', 'Continue');
  String get languageSettingsTitle => _s('زبان', 'Language');
  String get languageSettingsSubtitle => _s(
    'زبان برنامه را تغییر دهید یا از زبان دستگاه استفاده کنید.',
    'Change the app language or follow your device.',
  );

  String get updates => _s('به‌روزرسانی‌ها', 'Updates');
  String get updateSubtitle => _s(
    'نسخه‌های جدید GitHub را بررسی، دانلود و نصب کنید.',
    'Check GitHub releases, download, and install new builds.',
  );
  String get currentVersion => _s('نسخه فعلی', 'Current version');
  String get latestVersion => _s('آخرین نسخه', 'Latest version');
  String get checkForUpdates => _s('بررسی به‌روزرسانی', 'Check for updates');
  String get checkingForUpdates => _s('در حال بررسی...', 'Checking...');
  String get downloadAndInstall => _s('دانلود و نصب', 'Download and install');
  String get downloadingUpdate => _s('در حال دانلود...', 'Downloading...');
  String get installUpdate => _s('نصب به‌روزرسانی', 'Install update');
  String get allowInstallPermission =>
      _s('اجازه نصب از Localist را فعال کنید', 'Allow installs from Localist');
  String get updaterAndroidOnly => _s(
    'به‌روزرسان داخلی فقط روی نسخه اندروید فعال است.',
    'The built-in updater is available on Android builds.',
  );
  String get updaterNoRelease => _s(
    'نسخه GitHub پیدا نشد. کمی بعد دوباره تلاش کنید.',
    'No GitHub release was found. Try again later.',
  );
  String get updaterNoCompatibleApk => _s(
    'برای معماری این گوشی APK مناسب پیدا نشد.',
    'No compatible APK was found for this device ABI.',
  );
  String get updaterUpToDate =>
      _s('Localist به‌روز است.', 'Localist is up to date.');
  String updaterAvailable(String version) => _s(
    'نسخه $version آماده نصب است.',
    'Version $version is ready to install.',
  );
  String updaterDownloadProgress(int percent) =>
      _s('دانلود: $percent٪', 'Download: $percent%');
  String get updaterDownloaded => _s(
    'دانلود کامل شد. نصب را تایید کنید.',
    'Download complete. Confirm the installer prompt.',
  );
  String get updaterInstallPermissionNeeded => _s(
    'برای نصب به‌روزرسانی، اجازه نصب از Localist را در تنظیمات اندروید فعال کنید.',
    'Enable install permission for Localist in Android settings to install updates.',
  );
  String get updaterInstallStarted =>
      _s('پنجره نصب اندروید باز شد.', 'Android installer opened.');
  String get updaterFailed => _s(
    'بررسی یا دانلود به‌روزرسانی ناموفق بود.',
    'Update check or download failed.',
  );
  String get openGithubRelease =>
      _s('باز کردن نسخه GitHub', 'Open GitHub release');

  String get requiredAndroidAccess =>
      _s('دسترسی‌های لازم اندروید', 'Required Android access');
  String get permissionsIntro => _s(
    'قبل از ورود به برنامه، این دسترسی‌ها برای اتصال پایدار لازم هستند.',
    'Localist needs these permissions before opening the app.',
  );
  String get notifications => _s('اعلان‌ها', 'Notifications');
  String get notificationsSubtitle => _s(
    'وضعیت سرویس VPN و پروکسی را در پس‌زمینه نمایش می‌دهد.',
    'Shows the foreground VPN/proxy service status.',
  );
  String get camera => _s('دوربین', 'Camera');
  String get cameraSubtitle =>
      _s('کدهای QR برنامه را اسکن می‌کند.', 'Scans Localist QR configs.');
  String get backgroundTransfer =>
      _s('انتقال در پس‌زمینه', 'Background transfer');
  String get backgroundTransferSubtitle => _s(
    'وقتی صفحه خاموش است اتصال پروکسی و VPN را زنده نگه می‌دارد.',
    'Keeps proxy/VPN traffic alive when the screen is off.',
  );
  String get enterLocalist => _s('ورود به Localist', 'Enter Localist');
  String get grantEveryItem => _s(
    'برای ادامه، همه موارد بالا را اجازه دهید.',
    'Grant every item above to continue.',
  );
  String get granted => _s('داده شده', 'Granted');
  String get grant => _s('اجازه دادن', 'Grant');
  String get notificationsRequired =>
      _s('دسترسی اعلان لازم است', 'Notifications required');
  String get notificationsRequiredBody => _s(
    'Localist برای اجرای سرویس‌های VPN و پروکسی در پس‌زمینه به اعلان نیاز دارد.',
    'Localist needs notifications to run VPN and proxy services as foreground services.',
  );
  String get cameraRequired => _s('دوربین لازم است', 'Camera required');
  String get cameraRequiredBody => _s(
    'برای اسکن کدهای QR پروکسی به دسترسی دوربین نیاز است.',
    'Camera access is needed to scan Localist QR configs.',
  );
  String get backgroundTransferRequired =>
      _s('انتقال در پس‌زمینه لازم است', 'Background transfer required');
  String get backgroundTransferRequiredBody => _s(
    'بهینه‌سازی باتری می‌تواند بعد از خاموش شدن صفحه، ترافیک پروکسی و VPN را متوقف کند.',
    'Battery optimization can stop proxy/VPN traffic after the screen turns off.',
  );

  String get closeLocalist => _s('بستن Localist', 'Close Localist');
  String get rememberMyChoice =>
      _s('انتخاب من را به خاطر بسپار', 'Remember my choice');
  String get taskbarTray => _s('کنار ساعت ویندوز', 'Taskbar tray');
  String get exit => _s('خروج', 'Exit');
  String get exitLocalist => _s('خروج از Localist', 'Exit Localist');
  String get taskbarTrayNotReady => _s(
    'کنار ساعت ویندوز آماده نیست. Localist باز ماند.',
    'Taskbar tray is not ready. Localist stayed open.',
  );
  String get nearbySearchCouldNotStart => _s(
    'جست‌وجوی دستگاه‌های نزدیک شروع نشد. فایروال یا دسترسی شبکه را بررسی کنید.',
    'Nearby device search could not start. Check firewall or network permissions.',
  );
  String get nearbySearchFailed => _s(
    'جست‌وجوی دستگاه‌های نزدیک ناموفق بود. شبکه را بررسی کنید.',
    'Nearby device search failed. Check the network.',
  );
  String get selectAtLeastOneLocalIp =>
      _s('حداقل یک IP محلی را انتخاب کنید.', 'Select at least one local IP.');
  String get notificationPermissionRequired =>
      _s('دسترسی اعلان لازم است', 'Notification permission required');
  String get notificationPermissionRequiredBody => _s(
    'Localist برای نگه داشتن سرویس پروکسی اندروید در پس‌زمینه به اعلان نیاز دارد.',
    'Localist needs notifications to keep the Android proxy service running in the foreground.',
  );
  String get vpnPermissionRequired =>
      _s('دسترسی VPN لازم است', 'VPN permission required');
  String get vpnPermissionRequiredBody => _s(
    'Localist برای شروع دریافت به صورت VPN به دسترسی VPN اندروید نیاز دارد.',
    'Localist needs Android VPN permission to start Receiving as VPN.',
  );
  String get hotspotSettingsCouldNotOpen =>
      _s('تنظیمات Hotspot باز نشد.', 'Hotspot settings could not be opened.');
  String get apkSharingUnavailable => _s(
    'اشتراک‌گذاری APK روی این پلتفرم در دسترس نیست.',
    'APK sharing is unavailable on this platform.',
  );
  String get apkSharingFailed => _s(
    'اشتراک‌گذاری APK ناموفق بود. گزارش‌ها را بررسی کنید.',
    'Failed to share APK. Check Logs for details.',
  );
  String serviceConflict(String activeService, String targetService) => _s(
    '$activeService فعال است. قبل از شروع $targetService آن را متوقف کنید.',
    '$activeService is active. Stop it before starting $targetService.',
  );
  String get sharingActiveLock => _s(
    'اشتراک‌گذاری فعال است. قبل از استفاده از دریافت، آن را متوقف کنید.',
    'Sharing is active. Stop Sharing before using Receiving.',
  );
  String get receivingActiveLock => _s(
    'دریافت فعال است. قبل از استفاده از اشتراک‌گذاری، آن را متوقف کنید.',
    'Receiving is active. Stop Receiving before using Sharing.',
  );
  String nearbyDeviceFound(String name) =>
      _s('دستگاه نزدیک پیدا شد: $name', 'Nearby device found: $name');
  String get openReceiving => _s('باز کردن دریافت', 'Open Receiving');
  String proxyNotReachable(String host) =>
      _s('پروکسی در دسترس نیست: $host', 'Proxy is not reachable: $host');

  String get portUnavailable => _s(
    'پورت مشغول است. پورت پروتکل را در تنظیمات تغییر دهید.',
    'Port is busy. Change the protocol port in Settings.',
  );
  String get localProxyPortUnavailable => _s(
    'پورت محلی 3781 مشغول است. اول برنامه‌ای که از آن استفاده می‌کند را ببندید.',
    'Local port 3781 is busy. Close the app using it first.',
  );
  String get internalVpnProxyUnavailable => _s(
    'پروکسی داخلی VPN در دسترس نیست. v2rayN و پورت را بررسی کنید.',
    'Internal VPN proxy is not reachable. Check v2rayN and the port.',
  );
  String get vpnPermissionRequiredNotice => _s(
    'قبل از شروع دریافت، دسترسی VPN لازم است.',
    'VPN permission is required before Receiving can start.',
  );
  String get vpnPermissionPending => _s(
    'درخواست دسترسی VPN باز است. پیام دسترسی اندروید را کامل کنید.',
    'VPN permission is already open. Finish the Android permission prompt.',
  );
  String get missingProxyHost =>
      _s('میزبان پروکسی لازم است.', 'Proxy host is required.');
  String get wintunStartFailed => _s(
    'Wintun شروع نشد. Localist را با دسترسی مدیر اجرا کنید.',
    'Wintun could not start. Try running Localist as admin.',
  );
  String get wintunInterfaceMissing => _s(
    'رابط Wintun ظاهر نشد. wintun.dll و دسترسی مدیر را بررسی کنید.',
    'Wintun interface did not appear. Check wintun.dll and administrator access.',
  );
  String get netshFailed => _s(
    'تنظیم مسیر شبکه ویندوز ناموفق بود. Localist را با دسترسی مدیر اجرا کنید.',
    'Windows network route setup failed. Try running Localist as admin.',
  );
  String get windowsProxyFailed => _s(
    'پروکسی سیستمی ویندوز برای حالت پشتیبان فعال نشد.',
    'Windows system proxy could not be enabled for fallback mode.',
  );
  String get androidServiceStartFailed => _s(
    'اندروید نتوانست سرویس پس‌زمینه Localist را شروع کند.',
    'Android could not start the Localist foreground service.',
  );
  String get failedToStartProxyService =>
      _s('شروع سرویس پروکسی ناموفق بود.', 'Failed to start proxy service.');
  String get rootVpnDidNotStart =>
      _s('اشتراک‌گذاری VPN روت شروع نشد.', 'Root VPN sharing did not start');
  String get failedToStopSharing => _s(
    'توقف اشتراک‌گذاری ناموفق بود. گزارش‌ها را بررسی کنید.',
    'Failed to stop sharing. Check Logs for details.',
  );
  String get failedToStopReceiving => _s(
    'توقف دریافت ناموفق بود. گزارش‌ها را بررسی کنید.',
    'Failed to stop receiving. Check Logs for details.',
  );
  String get failedToStartReceivingVpn =>
      _s('شروع VPN دریافت ناموفق بود.', 'Failed to start receiving VPN.');
  String get failedToStartLocalProxy =>
      _s('شروع پروکسی محلی ناموفق بود.', 'Failed to start local proxy.');

  String get nearbyDevices => _s('دستگاه‌های نزدیک', 'Nearby devices');
  String get searchAgain => _s('جست‌وجوی دوباره', 'Search again');
  String get nearbySearchDisabled => _s(
    'جست‌وجوی دستگاه‌های نزدیک غیرفعال شده است.',
    'Nearby device search is disabled.',
  );
  String get searchingLocalNetwork =>
      _s('در حال جست‌وجوی شبکه محلی', 'Searching the local network');
  String get noSharingDeviceFound =>
      _s('دستگاه اشتراک‌گذاری پیدا نشد', 'No sharing device found');

  String get guideWelcome => _s('به Localist خوش آمدید', 'Welcome to Localist');
  String get guideSharingTitle => _s('اشتراک‌گذاری', 'Sharing');
  String get guideSharingWindows => _s(
    'در کامپیوتر مبدا، سرویس پروکسی را شروع کنید و QR را با گوشی اسکن کنید.',
    'On the source computer, tap Start proxy service and scan the QR from your phone.',
  );
  String get guideSharingAndroid => _s(
    'در دستگاه مبدا، Hotspot اندروید را دستی روشن کنید و سپس سرویس پروکسی را شروع کنید.',
    'On the source device, turn on Android Hotspot manually, then tap Start proxy service.',
  );
  String get guideQrTitle => _s('کدهای QR', 'QR codes');
  String get guideQrBody => _s(
    'Smart QR را باز کنید تا همه نشانی‌های پروکسی در دسترس با دستگاه مقصد به اشتراک گذاشته شوند.',
    'Open Smart QR to share every available proxy address with the destination device.',
  );
  String get guideReceivingTitle => _s('دریافت', 'Receiving');
  String get guideReceivingBody => _s(
    'در دستگاه مقصد، QR را اسکن کنید یا تنظیمات را بچسبانید و سپس آن را بارگذاری کنید.',
    'On the destination device, scan the QR or paste a config, then tap Load config.',
  );
  String get guideStartVpnTitle => _s('شروع VPN', 'Start VPN');
  String get guideStartVpnBody => _s(
    'بعد از پر شدن تنظیمات پروکسی، برای کل دستگاه VPN را شروع کنید یا برای برنامه‌های دارای پروکسی دستی از حالت پروکسی استفاده کنید.',
    'After Proxy Config is filled, tap Start as VPN for the whole device, Start as system proxy for Windows, or Start as local proxy for apps with manual proxy settings.',
  );
  String get guideMenusTitle => _s('منوها', 'Menus');
  String get guideMenusBody => _s(
    'از اشتراک‌گذاری، دریافت، گزارش‌ها و تنظیمات برای کنترل، بررسی و تنظیم اتصال استفاده کنید.',
    'Use Sharing, Receiving, Logs, and Settings from the bottom menu to control, inspect, and tune the connection.',
  );
  String get gotIt => _s('متوجه شدم', 'Got it');

  String get sharingControl => _s('کنترل اشتراک‌گذاری', 'Sharing Control');
  String get stoppingSharing =>
      _s('در حال توقف اشتراک‌گذاری...', 'Stopping sharing...');
  String get startingRootVpn =>
      _s('در حال شروع VPN روت...', 'Starting root VPN...');
  String get startingProxyService =>
      _s('در حال شروع سرویس پروکسی...', 'Starting proxy service...');
  String get stopSharing => _s('توقف اشتراک‌گذاری', 'Stop sharing');
  String get startRootVpnSharing =>
      _s('شروع اشتراک‌گذاری VPN روت', 'Start root VPN sharing');
  String get startProxyService =>
      _s('شروع سرویس پروکسی', 'Start proxy service');
  String get shareAllRouteIps =>
      _s('اشتراک‌گذاری روی همه IPهای مسیر', 'Share on all route IPs');
  String get allDetectedLocalIpsCanServeProxy => _s(
    'همه IPهای محلی شناسایی‌شده می‌توانند پروکسی را ارائه کنند.',
    'All detected local IPs can serve proxy',
  );
  String get chooseExactLocalIps => _s(
    'IPهای محلی مجاز برای ارائه پروکسی را انتخاب کنید.',
    'Choose the exact local IPs that should serve proxy',
  );
  String get connectPcThenRefresh => _s(
    'این کامپیوتر را به شبکه وصل کنید، سپس تازه‌سازی کنید.',
    'Connect this PC to a network, then refresh.',
  );
  String get turnOnHotspotThenRefresh => _s(
    'Hotspot اندروید را روشن کنید، سپس تازه‌سازی کنید.',
    'Turn on Android Hotspot, then refresh.',
  );
  String get allowedProxyIps => _s('IPهای مجاز پروکسی', 'Allowed proxy IPs');
  String get localIps => _s('IPهای محلی', 'Local IPs');
  String get noLocalIpsDetected =>
      _s('هیچ IP محلی شناسایی نشد', 'No local IPs detected');
  String rootVia(String vpnInterface) =>
      _s('روت از طریق $vpnInterface', 'Root via $vpnInterface');
  String get rootVpnSharing => _s('اشتراک‌گذاری VPN روت', 'Root VPN sharing');
  String vpnProxyPort(int port) => _s('پروکسی VPN: $port', 'VPN proxy :$port');
  String get internalVpnProxy => _s('پروکسی داخلی VPN', 'Internal VPN proxy');
  String get useInternalVpnProxy =>
      _s('استفاده از پروکسی داخلی VPN', 'Use internal VPN proxy');
  String get usesV2raynSocks => _s(
    'از SOCKS v2rayN روی 127.0.0.1 استفاده می‌کند',
    'Uses v2rayN SOCKS on 127.0.0.1',
  );
  String get sharingUsesWindowsRoute => _s(
    'خاموش است؛ اشتراک‌گذاری از مسیر ویندوز استفاده می‌کند',
    'Off; sharing uses the Windows route',
  );
  String get lockedWhileSharingActive => _s(
    'تا وقتی اشتراک‌گذاری فعال است قفل است',
    'Locked while sharing is active',
  );
  String get saveVpnProxy => _s('ذخیره پروکسی VPN', 'Save VPN proxy');
  String get enterValidVpnProxyPortFirst => _s(
    'اول یک پورت معتبر برای پروکسی VPN وارد کنید.',
    'Enter a valid VPN proxy port first.',
  );
  String get vpnProxySaved => _s('پروکسی VPN ذخیره شد', 'VPN proxy saved');
  String get localProxyIps => _s('IPهای پروکسی محلی', 'Local proxy IPs');
  String get hotspot => _s('Hotspot', 'Hotspot');
  String get hotspotInstructions => _s(
    'Hotspot اندروید را دستی روشن کنید، دستگاه دریافت‌کننده را به آن وصل کنید و سپس Localist را تازه‌سازی کنید.',
    'Turn on Android Hotspot manually, connect the receiving device to it, then refresh Localist.',
  );
  String get openAndroidHotspotSettings =>
      _s('باز کردن تنظیمات Hotspot اندروید', 'Open Android hotspot settings');
  String get refreshHotspot => _s('تازه‌سازی Hotspot', 'Refresh hotspot');
  String get androidHotspot => _s('Hotspot اندروید', 'Android hotspot');
  String get proxyIp => _s('IP پروکسی', 'Proxy IP');
  String get availableAfterHotspotOn => _s(
    'بعد از روشن شدن Hotspot در دسترس است',
    'Available after hotspot is on',
  );
  String get proxyQrCodes => _s('کدهای QR پروکسی', 'Proxy QR codes');
  String get proxyQr => _s('QR پروکسی', 'Proxy QR');
  String get noProxyEndpointOpen =>
      _s('هیچ نقطه پایانی پروکسی باز نیست', 'No proxy endpoint is open');
  String get smart => _s('هوشمند', 'Smart');
  String get allProxyEndpoints =>
      _s('همه نقطه‌های پایانی پروکسی', 'All proxy endpoints');
  String get ios => _s('iOS', 'iOS');
  String get xrayCore => _s('Xray', 'Xray');
  String get singBoxCore => _s('sing-box', 'sing-box');
  String get closeQrCode => _s('بستن کد QR', 'Close QR code');
  String qrCodeSemantic(String title) => _s('کد QR $title', '$title QR code');
  String get configCopied => _s('تنظیمات کپی شد', 'Config copied');
  String get copyConfig => _s('کپی تنظیمات', 'Copy config');
  String get shareConfig => _s('اشتراک‌گذاری تنظیمات', 'Share config');

  String get receivingIntro => _s(
    'یک تنظیم هوشمند را بچسبانید یا QR Localist را اسکن کنید، سپس آن را در تنظیمات پروکسی بارگذاری کنید.',
    'Paste a Smart config or scan a Localist QR, then load it into Proxy Config.',
  );
  String get smartManualConfig =>
      _s('تنظیم هوشمند یا دستی', 'Smart/manual config');
  String get configHint => _s(
    'localist://smart?... یا http://host:2060',
    'localist://smart?... or http://host:2060',
  );
  String get clearConfig => _s('پاک کردن تنظیمات', 'Clear config');
  String get loadConfig => _s('بارگذاری تنظیمات', 'Load config');
  String get scanProxyQr => _s('اسکن QR پروکسی', 'Scan proxy QR');
  String get closeScanner => _s('بستن اسکنر', 'Close scanner');
  String get proxyConfig => _s('تنظیمات پروکسی', 'Proxy Config');
  String get proxyHost => _s('میزبان پروکسی', 'Proxy host');
  String get clearHost => _s('پاک کردن میزبان', 'Clear host');
  String get proxyPort => _s('پورت پروکسی', 'Proxy port');
  String get clearPort => _s('پاک کردن پورت', 'Clear port');
  String get stopWindowsVpn => _s('توقف VPN ویندوز', 'Stop Windows VPN');
  String get stopVpn => _s('توقف VPN', 'Stop VPN');
  String get startWindowsVpnProxy =>
      _s('شروع VPN ویندوز و پروکسی', 'Start Windows VPN + proxy');
  String get startVpnProxy =>
      _s('شروع به صورت VPN و پروکسی', 'Start as VPN + proxy');
  String get stopProxy => _s('توقف پروکسی', 'Stop proxy');
  String get stopSystemProxy => _s('توقف پروکسی سیستم', 'Stop system proxy');
  String get startSystemProxy =>
      _s('شروع به صورت پروکسی سیستم', 'Start as system proxy');
  String get startProxy =>
      _s('شروع به صورت پروکسی محلی', 'Start as local proxy');
  String get proxyApps => _s('برنامه‌های پروکسی', 'Proxy Apps');
  String get proxyAppsDescription => _s(
    'برنامه‌هایی که تنظیم پروکسی جداگانه دارند، بعد از شروع VPN یا پروکسی می‌توانند از 127.0.0.1:3781 استفاده کنند.',
    'Apps with their own proxy setting can use 127.0.0.1:3781 after Start as VPN or Start as local proxy.',
  );
  String get openTelegramDesktopProxy =>
      _s('باز کردن پروکسی Telegram Desktop', 'Open Telegram Desktop proxy');
  String get openTelegramProxy =>
      _s('باز کردن پروکسی Telegram', 'Open Telegram proxy');
  String get telegramCouldNotOpen =>
      _s('Telegram باز نشد.', 'Telegram could not be opened.');
  String get scannerCouldNotStart =>
      _s('اسکنر شروع نشد.', 'Scanner could not start.');
  String get scannerDevice => _s('دستگاه اسکنر', 'Scanner device');
  String get useDefaultWindowsCamera => _s(
    'از دوربین پیش‌فرض ویندوز استفاده شود؟',
    'Use the default Windows camera device?',
  );
  String get defaultCamera => _s('دوربین پیش‌فرض', 'Default camera');
  String get localistQr => _s('QR Localist', 'Localist QR');
  String get configReadyTip => _s(
    'تنظیمات پروکسی آماده است. هر زمان آماده بودید VPN و پروکسی یا فقط پروکسی را شروع کنید.',
    'Proxy Config is ready. Use Start as VPN + proxy, Start as system proxy, or Start as local proxy when you are ready.',
  );
  String get configLoadedNotice => _s(
    'تنظیمات بارگذاری شد. شروع VPN و پروکسی یا شروع پروکسی را انتخاب کنید.',
    'Config loaded. Choose Start as VPN + proxy, Start as system proxy, or Start as local proxy.',
  );
  String get invalidConfig => _s('تنظیمات معتبر نیست.', 'Config is not valid.');
  String get chooseProxyEndpoint =>
      _s('نقطه پایانی پروکسی را انتخاب کنید', 'Choose proxy endpoint');
  String get vpnCompatible => _s('سازگار با VPN', 'VPN compatible');
  String get manualProxyEndpoint =>
      _s('نقطه پایانی پروکسی دستی', 'manual proxy endpoint');
  String get now => _s('اکنون', 'now');
  String vpnProxyRunningStatus({required bool windows}) => windows
      ? _s(
          'حالت VPN ویندوز و پروکسی محلی روی 127.0.0.1:3781 فعال هستند.',
          'Windows VPN mode and local proxy are active on 127.0.0.1:3781.',
        )
      : _s(
          'VPN prstun و پروکسی محلی روی 127.0.0.1:3781 فعال هستند.',
          'prstun VPN and local proxy are active on 127.0.0.1:3781.',
        );
  String get localProxyRunningStatus => _s(
    'پروکسی محلی روی 127.0.0.1:3781 فعال است.',
    'Local proxy is active on 127.0.0.1:3781.',
  );
  String get systemProxyRunningStatus => _s(
    'پروکسی سیستم ویندوز روی 127.0.0.1:3781 فعال است.',
    'Windows system proxy is active on 127.0.0.1:3781.',
  );
  String vpnRunningStatus({required bool windows}) => windows
      ? _s('حالت VPN ویندوز فعال است.', 'Windows VPN mode is active.')
      : _s(
          'حالت دریافت VPN prstun فعال است.',
          'prstun VPN receiving mode is active.',
        );

  String get proxy => _s('پروکسی', 'Proxy');
  String get root => _s('روت', 'Root');
  String get theme => _s('ظاهر', 'Theme');
  String get themeSystem => _s('سیستم', 'System');
  String get themeLight => _s('روشن', 'Light');
  String get themeDark => _s('تاریک', 'Dark');
  String get useMaterialYouColors =>
      _s('استفاده از رنگ‌های Material You', 'Use Material You colors');
  String get usesWindowsAccentColors => _s(
    'از رنگ‌های تاکیدی ویندوز استفاده می‌کند',
    'Uses Windows accent colors',
  );
  String get usesAndroidWallpaperColors => _s(
    'از رنگ‌های تصویر زمینه اندروید استفاده می‌کند',
    'Uses Android wallpaper colors',
  );
  String get unavailableWindows => _s(
    'روی این نسخه ویندوز در دسترس نیست',
    'Unavailable on this Windows version',
  );
  String get unavailableAndroid => _s(
    'روی این نسخه اندروید در دسترس نیست',
    'Unavailable on this Android version',
  );
  String get appInfo => _s('اطلاعات برنامه', 'App info');
  String developedBy(String developer) =>
      _s('توسعه‌دهنده: $developer', 'Developed by $developer');
  String get version => _s('نسخه', 'Version');
  String get platform => _s('پلتفرم', 'Platform');
  String get package => _s('بسته', 'Package');
  String get windowsDesktop => _s('دسکتاپ ویندوز', 'Windows Desktop');
  String get appId => _s('شناسه برنامه', 'App ID');
  String get developer => _s('توسعه‌دهنده', 'Developer');
  String get settingsPath => _s('تنظیمات', 'Settings');
  String get development => _s('نسخه توسعه', 'Development');
  String get proxyModeDisabled =>
      _s('حالت پروکسی غیرفعال است', 'Proxy mode is disabled');
  String get useProxyModeWithoutRoot =>
      _s('استفاده از حالت پروکسی بدون روت', 'Use proxy mode without root');
  String get savePorts => _s('ذخیره پورت‌ها', 'Save ports');
  String get windowClose => _s('بستن پنجره', 'Window close');
  String get closeButton => _s('دکمه بستن', 'Close button');
  String get askEveryTime => _s('هر بار بپرس', 'Ask every time');
  String get stopSharingBeforeChangingPorts => _s(
    'قبل از تغییر پورت‌ها، اشتراک‌گذاری را متوقف کنید.',
    'Stop sharing before changing ports.',
  );
  String get enterValidPortsFirst =>
      _s('اول پورت‌های معتبر وارد کنید.', 'Enter valid ports first.');
  String get portsSaved => _s('پورت‌ها ذخیره شدند', 'Ports saved');
  String get approveWindowsAdminPrompt => _s(
    'برای ادامه، درخواست دسترسی مدیر ویندوز را تایید کنید.',
    'Approve the Windows admin prompt to continue.',
  );
  String get rootAccessWasNotGranted =>
      _s('دسترسی روت داده نشد', 'Root access was not granted');
  String get unableToChangeRootRouting => _s(
    'تغییر مسیر روت ممکن نبود. گزارش‌ها را بررسی کنید.',
    'Unable to change root routing. Check Logs.',
  );
  String protocolPort(String protocol) =>
      _s('پورت $protocol', '$protocol port');
  String defaultPort(int port) => _s('پیش‌فرض: $port', 'Default: $port');
  String get lockedPortsNotice => _s(
    'قبل از تغییر پروتکل‌ها یا پورت‌ها، اشتراک‌گذاری را متوقف کنید.',
    'Stop sharing before changing protocols or ports.',
  );
  String get appColor => _s('رنگ برنامه', 'App color');

  String get receivingActive => _s('دریافت فعال است', 'Receiving active');
  String get sharingActive => _s('اشتراک‌گذاری فعال است', 'Sharing active');
  String get liveConnection => _s('اتصال زنده', 'Live connection');
  String get localProxy => _s('پروکسی محلی', 'Local proxy');
  String get remote => _s('راه دور', 'Remote');
  String get remoteHost => _s('میزبان راه دور', 'Remote host');
  String get traffic => _s('ترافیک', 'Traffic');
  String get session => _s('نشست', 'Session');
  String get total => _s('کل', 'Total');
  String get upload => _s('ارسال', 'Upload');
  String get download => _s('دریافت', 'Download');
  String get closeStats => _s('بستن آمار', 'Close stats');
  String ipCount(int count) => _s('$count IP', '$count IPs');
  String endpointSummary(String protocols, int hostCount) => _s(
    '$protocols روی ${ipCount(hostCount)}',
    '$protocols on ${ipCount(hostCount)}',
  );

  String get all => _s('همه', 'All');
  String get copyLogs => _s('کپی گزارش‌ها', 'Copy logs');
  String get clearLogs => _s('پاک کردن گزارش‌ها', 'Clear logs');
  String get noLogsYet => _s('هنوز گزارشی وجود ندارد', 'No logs yet');
  String get logInfo => _s('اطلاع', 'Info');
  String get logWarning => _s('هشدار', 'Warning');
  String get logError => _s('خطا', 'Error');
}

extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return AppLocalizations.supportedLocales.any(
      (supported) => supported.languageCode == locale.languageCode,
    );
  }

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture(AppLocalizations(locale));
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
