import 'package:flutter/widgets.dart';

/// Turns implementation errors from the camera, audio and transport layers
/// into one user-facing language. The original error remains in debug logs.
///
/// Some platform and protocol errors still contain an older "Persian / English"
/// message. Recognize those until every native sender is updated.
String captureErrorText(BuildContext context, String message) {
  final persian = Localizations.localeOf(context).languageCode == 'fa';
  final text = message.trim().replaceFirst(
    RegExp(r'^(?:Bad state|FormatException|Exception):\s*'),
    '',
  );
  if (text.isEmpty) return '';

  final separator = text.indexOf(' / ');
  if (separator > 0) {
    final first = text.substring(0, separator).trim();
    final second = text.substring(separator + 3).trim();
    if (RegExp(r'[\u0600-\u06ff]').hasMatch(first) &&
        RegExp(r'[A-Za-z]').hasMatch(second)) {
      return persian ? first : second;
    }
  }

  // Preserve a complete, already localized Persian message. It often has
  // more useful instructions than a generic platform-error explanation.
  if (persian &&
      RegExp(r'[\u0600-\u06ff]').hasMatch(text) &&
      !RegExp(r'[A-Za-z]').hasMatch(text)) {
    return text;
  }

  // Messages supplied by plugins, Android and Windows cannot be assumed to be
  // localized. Explain what the user can do without exposing technical text.
  final lower = text.toLowerCase();
  String tr(String fa, String en) => persian ? fa : en;
  if (RegExp(
    r'active service|another feature|سرویس فعال|سرویس دیگری',
  ).hasMatch(lower)) {
    return tr(
      'برای شروع دوربین یا میکروفون، ابتدا سرویس فعال دیگر را متوقف کنید.',
      'Stop the other active service before starting the camera or microphone.',
    );
  }
  if (RegExp(r'out of memory|not enough memory|حافظه').hasMatch(lower)) {
    return tr(
      'حافظهٔ دستگاه برای این کیفیت کافی نیست. کیفیت پایین‌تری انتخاب کنید.',
      'The device does not have enough memory for this quality. Choose a lower quality.',
    );
  }
  if (RegExp(r'unavailable or busy|busy|مشغول').hasMatch(lower)) {
    return tr(
      'دوربین یا میکروفون در حال استفاده است. عملیات فعلی را تمام کنید و دوباره تلاش کنید.',
      'Camera or microphone is busy. Finish the current operation and try again.',
    );
  }
  if (RegExp(r'permission|denied|دسترسی|مجوز').hasMatch(lower)) {
    return tr(
      'دسترسی لازم برای دوربین یا میکروفون داده نشده است. مجوزهای برنامه را بررسی کنید.',
      'Camera or microphone access was denied. Check the app permissions.',
    );
  }
  if (RegExp(r'timeout|timed out|مهلت').hasMatch(lower)) {
    return tr(
      'مهلت اتصال به پایان رسید. شبکه را بررسی کنید و دوباره تلاش کنید.',
      'The connection timed out. Check the network and try again.',
    );
  }
  if (RegExp(
    r'input|microphone|camera|device|میکروفون|دوربین|ورودی',
  ).hasMatch(lower)) {
    return tr(
      'دوربین یا میکروفون در دسترس نیست. اتصال دستگاه و انتخاب ورودی را بررسی کنید.',
      'Camera or microphone is unavailable. Check the device and input selection.',
    );
  }
  if (RegExp(
    r'network|connect|socket|signaling|ارتباط|اتصال|گیرنده|فرستنده',
  ).hasMatch(lower)) {
    return tr(
      'ارتباط با دستگاه برقرار نشد. اتصال شبکه و وضعیت دستگاه دیگر را بررسی کنید.',
      'Could not connect to the device. Check the network and the other device.',
    );
  }
  if (RegExp(
    r'bitrate|frame|resolution|codec|encoder|setting|quality|کیفیت|نرخ|بیت',
  ).hasMatch(lower)) {
    return tr(
      'تنظیمات انتقال با دستگاه سازگار نیست. کیفیت یا نرخ تصویر را تغییر دهید.',
      'The device does not support these capture settings. Try another quality or frame rate.',
    );
  }
  return tr(
    'عملیات دوربین یا میکروفون انجام نشد. دوباره تلاش کنید و در صورت تکرار، گزارش خطا تهیه کنید.',
    'The camera or microphone operation failed. Try again and collect a debug report if the problem continues.',
  );
}
