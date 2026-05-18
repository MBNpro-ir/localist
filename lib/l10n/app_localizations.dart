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

  String get appName => 'Localist';
  String get sharing => isPersian ? 'اشتراک گذاری' : 'Sharing';
  String get receiving => isPersian ? 'دریافت' : 'Receiving';
  String get settings => isPersian ? 'تنظیمات' : 'Settings';
  String get logs => isPersian ? 'گزارش ها' : 'Logs';
  String get stats => isPersian ? 'آمار' : 'Stats';
  String get appGuide => isPersian ? 'راهنمای برنامه' : 'App guide';
  String get shareApk => isPersian ? 'اشتراک گذاری APK' : 'Share APK';
  String get lightMode => isPersian ? 'حالت روشن' : 'Light mode';
  String get darkMode => isPersian ? 'حالت تاریک' : 'Dark mode';
  String get cancel => isPersian ? 'لغو' : 'Cancel';
  String get ok => isPersian ? 'باشه' : 'OK';
  String get openSettings => isPersian ? 'باز کردن تنظیمات' : 'Open settings';
  String get refresh => isPersian ? 'تازه سازی' : 'Refresh';
  String get close => isPersian ? 'بستن' : 'Close';

  String get languageStep => isPersian ? 'زبان' : 'Language';
  String get permissionsStep => isPersian ? 'دسترسی ها' : 'Permissions';
  String get mainStep => isPersian ? 'برنامه' : 'App';
  String get languageTitle =>
      isPersian ? 'زبان Localist را انتخاب کنید' : 'Choose Localist language';
  String get languageSubtitle => isPersian
      ? 'می توانید زبان برنامه را همین حالا انتخاب کنید یا بگذارید با زبان دستگاه هماهنگ شود.'
      : 'Pick a language now, or let Localist follow your device language.';
  String get languageSystem => isPersian ? 'زبان دستگاه' : 'Device language';
  String get languageSystemSubtitle => isPersian
      ? 'Localist بین فارسی و انگلیسی بر اساس دستگاه جابه جا می شود.'
      : 'Localist switches between Persian and English from your device.';
  String get languageEnglish => isPersian ? 'English' : 'English';
  String get languageEnglishSubtitle =>
      isPersian ? 'رابط برنامه انگلیسی می ماند.' : 'Keep the app in English.';
  String get languagePersian => isPersian ? 'فارسی' : 'Persian';
  String get languagePersianSubtitle =>
      isPersian ? 'رابط برنامه فارسی می شود.' : 'Use the Persian interface.';
  String get continueButton => isPersian ? 'ادامه' : 'Continue';
  String get languageSettingsTitle => isPersian ? 'زبان' : 'Language';
  String get languageSettingsSubtitle => isPersian
      ? 'زبان برنامه را تغییر دهید یا از زبان دستگاه استفاده کنید.'
      : 'Change the app language or follow your device.';
  String get updates => isPersian ? 'به روزرسانی ها' : 'Updates';
  String get updateSubtitle => isPersian
      ? 'نسخه های جدید GitHub را بررسی، دانلود و نصب کنید.'
      : 'Check GitHub releases, download, and install new builds.';
  String get currentVersion => isPersian ? 'نسخه فعلی' : 'Current version';
  String get latestVersion => isPersian ? 'آخرین نسخه' : 'Latest version';
  String get checkForUpdates =>
      isPersian ? 'بررسی به روزرسانی' : 'Check for updates';
  String get checkingForUpdates =>
      isPersian ? 'در حال بررسی...' : 'Checking...';
  String get downloadAndInstall =>
      isPersian ? 'دانلود و نصب' : 'Download and install';
  String get downloadingUpdate =>
      isPersian ? 'در حال دانلود...' : 'Downloading...';
  String get installUpdate => isPersian ? 'نصب به روزرسانی' : 'Install update';
  String get allowInstallPermission => isPersian
      ? 'اجازه نصب از Localist را فعال کنید'
      : 'Allow installs from Localist';
  String get updaterAndroidOnly => isPersian
      ? 'به روزرسان داخلی فقط روی نسخه اندروید فعال است.'
      : 'The built-in updater is available on Android builds.';
  String get updaterNoRelease => isPersian
      ? 'نسخه GitHub پیدا نشد. کمی بعد دوباره تلاش کنید.'
      : 'No GitHub release was found. Try again later.';
  String get updaterNoCompatibleApk => isPersian
      ? 'برای معماری این گوشی APK مناسب پیدا نشد.'
      : 'No compatible APK was found for this device ABI.';
  String get updaterUpToDate =>
      isPersian ? 'Localist به روز است.' : 'Localist is up to date.';
  String updaterAvailable(String version) => isPersian
      ? 'نسخه $version آماده نصب است.'
      : 'Version $version is ready to install.';
  String updaterDownloadProgress(int percent) =>
      isPersian ? 'دانلود: $percent%' : 'Download: $percent%';
  String get updaterDownloaded => isPersian
      ? 'دانلود کامل شد. نصب را تایید کنید.'
      : 'Download complete. Confirm the installer prompt.';
  String get updaterInstallPermissionNeeded => isPersian
      ? 'برای نصب به روزرسانی، اجازه نصب از Localist را در تنظیمات اندروید فعال کنید.'
      : 'Enable install permission for Localist in Android settings to install updates.';
  String get updaterInstallStarted =>
      isPersian ? 'پنجره نصب اندروید باز شد.' : 'Android installer opened.';
  String get updaterFailed => isPersian
      ? 'بررسی یا دانلود به روزرسانی ناموفق بود.'
      : 'Update check or download failed.';
  String get openGithubRelease =>
      isPersian ? 'باز کردن GitHub Release' : 'Open GitHub release';

  String get localistPermissions =>
      isPersian ? 'دسترسی های Localist' : 'Localist permissions';
  String get requiredAndroidAccess =>
      isPersian ? 'دسترسی های لازم اندروید' : 'Required Android access';
  String get permissionsIntro => isPersian
      ? 'قبل از ورود به برنامه، این دسترسی ها برای اتصال پایدار لازم هستند.'
      : 'Localist needs these permissions before opening the app.';
  String get notifications => isPersian ? 'اعلان ها' : 'Notifications';
  String get notificationsSubtitle => isPersian
      ? 'وضعیت سرویس VPN و پروکسی را در پس زمینه نمایش می دهد.'
      : 'Shows the foreground VPN/proxy service status.';
  String get camera => isPersian ? 'دوربین' : 'Camera';
  String get cameraSubtitle => isPersian
      ? 'کدهای QR برنامه را اسکن می کند.'
      : 'Scans Localist QR configs.';
  String get backgroundTransfer =>
      isPersian ? 'انتقال در پس زمینه' : 'Background transfer';
  String get backgroundTransferSubtitle => isPersian
      ? 'وقتی صفحه خاموش است اتصال پروکسی و VPN را زنده نگه می دارد.'
      : 'Keeps proxy/VPN traffic alive when the screen is off.';
  String get enterLocalist => isPersian ? 'ورود به Localist' : 'Enter Localist';
  String get grantEveryItem => isPersian
      ? 'برای ادامه، همه موارد بالا را اجازه دهید.'
      : 'Grant every item above to continue.';
  String get granted => isPersian ? 'داده شده' : 'Granted';
  String get grant => isPersian ? 'اجازه دادن' : 'Grant';
  String get notificationsRequired =>
      isPersian ? 'اعلان ها لازم است' : 'Notifications required';
  String get notificationsRequiredBody => isPersian
      ? 'Localist برای اجرای سرویس های VPN و پروکسی در پس زمینه به اعلان نیاز دارد.'
      : 'Localist needs notifications to run VPN and proxy services as foreground services.';
  String get cameraRequired =>
      isPersian ? 'دوربین لازم است' : 'Camera required';
  String get cameraRequiredBody => isPersian
      ? 'برای اسکن کدهای QR پروکسی به دسترسی دوربین نیاز است.'
      : 'Camera access is needed to scan Localist QR configs.';
  String get backgroundTransferRequired => isPersian
      ? 'انتقال در پس زمینه لازم است'
      : 'Background transfer required';
  String get backgroundTransferRequiredBody => isPersian
      ? 'بهینه سازی باتری می تواند بعد از خاموش شدن صفحه، ترافیک پروکسی و VPN را متوقف کند.'
      : 'Battery optimization can stop proxy/VPN traffic after the screen turns off.';

  String get closeLocalist => isPersian ? 'بستن Localist' : 'Close Localist';
  String get rememberMyChoice =>
      isPersian ? 'انتخاب من را به خاطر بسپار' : 'Remember my choice';
  String get taskbarTray => isPersian ? 'کنار ساعت ویندوز' : 'Taskbar tray';
  String get exit => isPersian ? 'خروج' : 'Exit';
  String get taskbarTrayNotReady => isPersian
      ? 'کنار ساعت ویندوز آماده نیست. Localist باز ماند.'
      : 'Taskbar tray is not ready. Localist stayed open.';
  String get nearbySearchCouldNotStart => isPersian
      ? 'جست و جوی دستگاه های نزدیک شروع نشد. فایروال یا دسترسی شبکه را بررسی کنید.'
      : 'Nearby device search could not start. Check firewall or network permissions.';
  String get nearbySearchFailed => isPersian
      ? 'جست و جوی دستگاه های نزدیک ناموفق بود. شبکه را بررسی کنید.'
      : 'Nearby device search failed. Check the network.';
  String get selectAtLeastOneLocalIp => isPersian
      ? 'حداقل یک IP محلی را انتخاب کنید.'
      : 'Select at least one local IP.';
  String get notificationPermissionRequired =>
      isPersian ? 'دسترسی اعلان لازم است' : 'Notification permission required';
  String get notificationPermissionRequiredBody => isPersian
      ? 'Localist برای نگه داشتن سرویس پروکسی اندروید در پس زمینه به اعلان نیاز دارد.'
      : 'Localist needs notifications to keep the Android proxy service running in the foreground.';
  String get vpnPermissionRequired =>
      isPersian ? 'دسترسی VPN لازم است' : 'VPN permission required';
  String get vpnPermissionRequiredBody => isPersian
      ? 'Localist برای شروع دریافت به صورت VPN به دسترسی VPN اندروید نیاز دارد.'
      : 'Localist needs Android VPN permission to start Receiving as VPN.';
  String get hotspotSettingsCouldNotOpen => isPersian
      ? 'تنظیمات Hotspot باز نشد.'
      : 'Hotspot settings could not be opened.';
  String get apkSharingUnavailable => isPersian
      ? 'اشتراک گذاری APK روی این پلتفرم در دسترس نیست.'
      : 'APK sharing is unavailable on this platform.';
  String get apkSharingFailed => isPersian
      ? 'اشتراک گذاری APK ناموفق بود. گزارش ها را بررسی کنید.'
      : 'Failed to share APK. Check Logs for details.';
  String serviceConflict(String activeService, String targetService) =>
      isPersian
      ? '$activeService فعال است. قبل از شروع $targetService آن را متوقف کنید.'
      : '$activeService is active. Stop it before starting $targetService.';
  String get sharingActiveLock => isPersian
      ? 'Sharing فعال است. قبل از استفاده از Receiving آن را متوقف کنید.'
      : 'Sharing is active. Stop Sharing before using Receiving.';
  String get receivingActiveLock => isPersian
      ? 'Receiving فعال است. قبل از استفاده از Sharing آن را متوقف کنید.'
      : 'Receiving is active. Stop Receiving before using Sharing.';
  String nearbyDeviceFound(String name) =>
      isPersian ? 'دستگاه نزدیک پیدا شد: $name' : 'Nearby device found: $name';
  String get openReceiving =>
      isPersian ? 'باز کردن Receiving' : 'Open Receiving';
  String proxyNotReachable(String host) => isPersian
      ? 'پروکسی در دسترس نیست: $host'
      : 'Proxy is not reachable: $host';

  String get nearbyDevices => isPersian ? 'دستگاه های نزدیک' : 'Nearby devices';
  String get searchAgain => isPersian ? 'جست و جوی دوباره' : 'Search again';
  String get nearbySearchDisabled => isPersian
      ? 'جست و جوی دستگاه های نزدیک غیر فعال شده است.'
      : 'Nearby device search is disabled.';
  String get searchingLocalNetwork =>
      isPersian ? 'در حال جست و جوی شبکه محلی' : 'Searching the local network';
  String get noSharingDeviceFound =>
      isPersian ? 'دستگاه اشتراک گذاری پیدا نشد' : 'No sharing device found';
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
