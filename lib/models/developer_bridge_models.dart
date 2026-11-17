import 'dart:io';

enum DeveloperBridgeErrorCode {
  adbExecutableNotFound,
  invalidAdbExecutable,
  invalidEndpoint,
  phoneIpUnavailable,
  deviceNotDetected,
  invalidPairingCode,
  pairingRequired,
  pairingRejected,
  wirelessDebuggingUnsupported,
  tlsAuthenticationFailed,
  deviceUnauthorized,
  deviceOffline,
  endpointUnreachable,
  adbServerConflict,
  commandTimedOut,
  adbCommandFailed,
  unsupportedPlatform,
}

class DeveloperBridgeFailure implements Exception {
  const DeveloperBridgeFailure(this.code, this.output);

  final DeveloperBridgeErrorCode code;
  final String output;

  String message(bool persian) => switch ((code, persian)) {
    (DeveloperBridgeErrorCode.adbExecutableNotFound, true) =>
      'فایل ADB پیدا نشد. Android SDK Platform-Tools را از مسیر موجود Android Studio انتخاب کنید.',
    (DeveloperBridgeErrorCode.adbExecutableNotFound, false) =>
      'ADB was not found. Select the existing Android Studio Platform-Tools executable.',
    (DeveloperBridgeErrorCode.invalidAdbExecutable, true) =>
      'مسیر انتخاب‌شده فایل ADB معتبر نیست.',
    (DeveloperBridgeErrorCode.invalidAdbExecutable, false) =>
      'The selected path is not a valid ADB executable.',
    (DeveloperBridgeErrorCode.invalidEndpoint, true) =>
      'نشانی باید به شکل IP:port یا [IPv6]:port باشد و پورت آن بین ۱ تا ۶۵۵۳۵ باشد.',
    (DeveloperBridgeErrorCode.invalidEndpoint, false) =>
      'Enter an endpoint as IP:port or [IPv6]:port with a port from 1 to 65535.',
    (DeveloperBridgeErrorCode.phoneIpUnavailable, true) =>
      'نشانی IP گوشی در دسترس نیست. آن را از صفحه Wireless debugging وارد کنید.',
    (DeveloperBridgeErrorCode.phoneIpUnavailable, false) =>
      'The phone IP is unavailable. Read it from the Wireless debugging screen.',
    (DeveloperBridgeErrorCode.deviceNotDetected, true) =>
      'ADB دستگاهی پیدا نکرد. Debugging را روی گوشی فعال کنید یا endpoint را وصل کنید.',
    (DeveloperBridgeErrorCode.deviceNotDetected, false) =>
      'ADB did not detect a device. Enable debugging on the phone or connect its endpoint.',
    (DeveloperBridgeErrorCode.invalidPairingCode, true) =>
      'کد جفت‌سازی باید فقط شامل رقم باشد.',
    (DeveloperBridgeErrorCode.invalidPairingCode, false) =>
      'The pairing code must contain digits only.',
    (DeveloperBridgeErrorCode.pairingRejected, true) =>
      'جفت‌سازی رد شد. پورت و کد فعلی نمایش‌داده‌شده در Wireless debugging را بررسی کنید.',
    (DeveloperBridgeErrorCode.pairingRejected, false) =>
      'Pairing was rejected. Check the current port and code shown in Wireless debugging.',
    (DeveloperBridgeErrorCode.pairingRequired, true) =>
      'این دستگاه هنوز جفت‌سازی نشده است. ابتدا Pair using pairing code را انجام دهید.',
    (DeveloperBridgeErrorCode.pairingRequired, false) =>
      'This device is not paired yet. Complete Pair using pairing code first.',
    (DeveloperBridgeErrorCode.wirelessDebuggingUnsupported, true) =>
      'نسخه ADB یا گوشی از این روش Wireless debugging پشتیبانی نمی‌کند.',
    (DeveloperBridgeErrorCode.wirelessDebuggingUnsupported, false) =>
      'This ADB version or phone does not support this Wireless debugging operation.',
    (DeveloperBridgeErrorCode.tlsAuthenticationFailed, true) =>
      'احراز هویت امن ADB ناموفق بود. Pairing گوشی را بررسی و در صورت نیاز دوباره جفت‌سازی کنید.',
    (DeveloperBridgeErrorCode.tlsAuthenticationFailed, false) =>
      'ADB secure authentication failed. Check the phone pairing and pair again if needed.',
    (DeveloperBridgeErrorCode.deviceUnauthorized, true) =>
      'گوشی اتصال این رایانه را مجاز نکرده است. درخواست مجوز ADB را روی گوشی بررسی کنید.',
    (DeveloperBridgeErrorCode.deviceUnauthorized, false) =>
      'The phone has not authorized this workstation. Review the ADB authorization prompt on the phone.',
    (DeveloperBridgeErrorCode.deviceOffline, true) =>
      'دستگاه ADB آفلاین است. اتصال شبکه یا Wireless debugging را بررسی کنید.',
    (DeveloperBridgeErrorCode.deviceOffline, false) =>
      'The ADB device is offline. Check the network connection or Wireless debugging state.',
    (DeveloperBridgeErrorCode.endpointUnreachable, true) =>
      'به نشانی ADB دسترسی نیست. IP، پورت و اتصال شبکه را بررسی کنید.',
    (DeveloperBridgeErrorCode.endpointUnreachable, false) =>
      'The ADB endpoint is unreachable. Check its IP, port, and network connection.',
    (DeveloperBridgeErrorCode.adbServerConflict, true) =>
      'سرور ADB با خطا روبه‌رو شد. مسیر Platform-Tools مورد استفاده Android Studio را انتخاب کنید.',
    (DeveloperBridgeErrorCode.adbServerConflict, false) =>
      'The ADB server reported a conflict. Select the Platform-Tools path used by Android Studio.',
    (DeveloperBridgeErrorCode.commandTimedOut, true) =>
      'زمان اجرای فرمان ADB تمام شد. وضعیت دستگاه و شبکه را بررسی کنید و دوباره تلاش کنید.',
    (DeveloperBridgeErrorCode.commandTimedOut, false) =>
      'The ADB command timed out. Check the device and network, then try again.',
    (DeveloperBridgeErrorCode.adbCommandFailed, true) =>
      'فرمان ADB انجام نشد. جزئیات تشخیصی را بررسی کنید.',
    (DeveloperBridgeErrorCode.adbCommandFailed, false) =>
      'The ADB command failed. Review the diagnostic output.',
    (DeveloperBridgeErrorCode.unsupportedPlatform, true) =>
      'Developer Bridge در این نسخه فقط روی Windows در دسترس است.',
    (DeveloperBridgeErrorCode.unsupportedPlatform, false) =>
      'Developer Bridge is available on Windows only in this build.',
  };
}

class AdbEndpoint {
  const AdbEndpoint({required this.host, required this.port});

  final String host;
  final int port;

  String get value => host.contains(':') ? '[$host]:$port' : '$host:$port';

  static AdbEndpoint? tryParse(String input) {
    final value = input.trim();
    final ipv6 = RegExp(r'^\[([^\]]+)\]:(\d{1,5})$').firstMatch(value);
    if (ipv6 != null) {
      final address = InternetAddress.tryParse(ipv6.group(1)!);
      final port = int.tryParse(ipv6.group(2)!);
      if (address?.type == InternetAddressType.IPv6 && _validPort(port)) {
        return AdbEndpoint(host: address!.address, port: port!);
      }
      return null;
    }

    final ipv4OrHost = RegExp(
      r'^([A-Za-z0-9.-]+):(\d{1,5})$',
    ).firstMatch(value);
    if (ipv4OrHost == null) return null;
    final host = ipv4OrHost.group(1)!;
    final port = int.tryParse(ipv4OrHost.group(2)!);
    if (!_validPort(port) ||
        host.startsWith('-') ||
        host.startsWith('.') ||
        host.endsWith('.') ||
        host.contains('..')) {
      return null;
    }
    if (RegExp(r'^[0-9.]+$').hasMatch(host)) {
      if (InternetAddress.tryParse(host)?.type != InternetAddressType.IPv4) {
        return null;
      }
    } else {
      final labels = host.split('.');
      if (host.length > 253 ||
          labels.any(
            (label) =>
                label.isEmpty ||
                label.length > 63 ||
                label.startsWith('-') ||
                label.endsWith('-'),
          )) {
        return null;
      }
    }
    return AdbEndpoint(host: host, port: port!);
  }

  static bool _validPort(int? port) =>
      port != null && port >= 1 && port <= 65535;
}

enum AdbDeviceStatus { device, unauthorized, offline, other }

class AdbDevice {
  const AdbDevice({
    required this.serial,
    required this.status,
    required this.details,
  });

  final String serial;
  final AdbDeviceStatus status;
  final String details;

  String get model {
    for (final part 