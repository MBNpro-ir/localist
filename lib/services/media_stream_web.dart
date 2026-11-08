import 'dart:convert';

typedef StreamWebItem = ({
  String name,
  String mime,
  String playerPath,
  String mediaPath,
});

String streamWebEscape(String value) =>
    const HtmlEscape(HtmlEscapeMode.attribute).convert(value);
String streamWebPath(String path) {
  if (!path.startsWith('/') ||
      path.startsWith('//') ||
      path.contains(RegExp(r'[\x00-\x20\\]'))) {
    throw const FormatException('Expected a local media route.');
  }
  return streamWebEscape(path);
}

String streamWebKind(String mime) => mime.startsWith('image/')
    ? 'image'
    : mime.startsWith('audio/')
    ? 'audio'
    : 'video';
String streamWebType(String kind, bool fa) => switch (kind) {
  'image' => fa ? 'عکس' : 'Photo',
  'audio' => fa ? 'موسیقی' : 'Audio',
  _ => fa ? 'ویدیو' : 'Video',
};
String streamWebFormat(String name) {
  final extension = name.split('.').last;
  return RegExp(r'^[a-zA-Z0-9]{1,8}$').hasMatch(extension)
      ? extension.toUpperCase()
      : '';
}

String streamWebIcon(String name) =>
    '<svg class="icon" aria-hidden="true" focusable="false"><use href="#i-$name"></use></svg>';
String streamWebButton(
  String id,
  String icon,
  String label, {
  String extra = '',
  String classes = '',
}) =>
    '<button id="$id" type="button" class="icon-button $classes" aria-label="${streamWebEscape(label)}" title="${streamWebEscape(label)}" $extra>${streamWebIcon(icon)}<span class="sr-only">${streamWebEscape(label)}</span></button>';

String streamWebPage({
  required String title,
  required String body,
  required bool persian,
  required String page,
}) =>
    '''<!doctype html>
<html lang="${persian ? 'fa" dir="rtl' : 'en" dir="ltr'}"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="color-scheme" content="dark light"><meta name="theme-color" content="#0c1218">
<meta name="referrer" content="no-referrer"><title>${streamWebEscape(title)} · Localist</title>
<link rel="stylesheet" href="/_localist/stream.css?v=3"><script src="/_localist/stream.js?v=3" defer></script></head>
<body data-page="$page">$_streamWebIcons
<a class="skip-link" href="#content">${persian ? 'رفتن به محتوا' : 'Skip to content'}</a>
<header class="site-header"><div class="header-inner">
<a class="brand" href="/" aria-label="Localist Stream"><span class="brand-symbol">${streamWebIcon('broadcast')}</span><span>Localist<span class="brand-caption">STREAM</span></span></a>
<div class="header-actions"><span class="network-badge">${streamWebIcon('wifi')}<span>${persian ? 'شبکهٔ محلی' : 'Local network'}</span></span>
${streamWebButton('theme', 'sun', persian ? 'تغییر حالت روشن و تیره' : 'Switch light and dark theme', extra: 'disabled')}</div></div></header>
<main id="content" class="page-shell">$body</main>
<footer class="site-footer"><span>${persian ? 'اشتراک‌گذاری مستقیم با' : 'Shared directly with'} <b>Localist</b></span><span>${persian ? 'رسانه‌های شما، روی شبکهٔ شما.' : 'Your media. Your network.'}</span></footer>
<noscript><p class="no-script">${persian ? 'برای کنترل‌های بیشتر، جاوااسکریپت را فعال کنید. کنترل‌های اصلی پخش همچنان در دسترس‌اند.' : 'Enable JavaScript for enhanced controls. Native playback controls remain available.'}</p></noscript>
</body></html>''';

const _streamWebIcons =
    r'''<svg class="icon-defs" aria-hidden="true" xmlns="http://www.w3.org/2000/svg"><defs>
<symbol id="i-play" viewBox="0 0 24 24"><path d="m8 5 11 7-11 7Z" fill="currentColor" stroke="none"/></symbol>
<symbol id="i-pause" viewBox="0 0 24 24"><path d="M8 5v14M16 5v14" stroke-width="4"/></symbol>
<symbol id="i-video" viewBox="0 0 24 24"><rect x="3" y="5" width="13" height="14" rx="3"/><path d="m16 10 5-3v10l-5-3"/></symbol>
<symbol id="i-image" viewBox="0 0 24 24"><rect x="3" y="3" width="18" height="18" rx="4"/><circle cx="8.5" cy="8.5" r="1.5"/><path d="m3 17 5-5 4 4 3-3 6 6"/></symbol>
<symbol id="i-audio" viewBox="0 0 24 24"><path d="M9 18V5l11-2v13M9 8l11-2"/><ellipse cx="6" cy="18" rx="3" ry="3"/><ellipse cx="17" cy="16" rx="3" ry="3"/></symbol>
<symbol id="i-grid" viewBox="0 0 24 24"><rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/></symbol>
<symbol id="i-list" viewBox="0 0 24 24"><path d="M9 6h12M9 12h12M9 18h12M3 6h1M3 12h1M3 18h1"/></symbol>
<symbol id="i-search" viewBox="0 0 24 24"><circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 5 5"/></symbol>
<symbol id="i-wifi" viewBox="0 0 24 24"><path d="M3 8a15 15 0 0 1 18 0M6 12a10 10 0 0 1 12 0M9 16a5 5 0 0 1 6 0"/><circle cx="12" cy="20" r="1" fill="currentColor" stroke="none"/></symbol>
<symbol id="i-broadcast" viewBox="0 0 24 24"><path d="M5 5a10 10 0 0 0 0 14M19 5a10 10 0 0 1 0 14M8 8a6 6 0 0 0 0 8M16 8a6 6 0 0 1 0 8"/><circle cx="12" cy="12" r="2" fill="currentColor" stroke="none"/></symbol>
<symbol id="i-sun" viewBox="0 0 24 24"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M2 12h2M20 12h2M5 5l1 1M18 18l1 1M5 19l1-1M18 6l1-1"/></symbol>
<symbol id="i-moon" viewBox="0 0 24 24"><path d="M20 15A9 9 0 0 1 9 4a9 9 0 1 0 11 11Z"/></symbol>
<symbol id="i-left" viewBox="0 0 24 24"><path d="m14 6-6 6 6 6"/></symbol><symbol id="i-right" viewBox="0 0 24 24"><path d="m10 6 6 6-6 6"/></symbol>
<symbol id="i-back" viewBox="0 0 24 24"><path d="M4 10a8 8 0 1 1 1 8M4 5v5h5"/><path d="M10 11v5M14 11h3v5h-3Z" stroke-width="1.3"/></symbol>
<symbol id="i-forward" viewBox="0 0 24 24"><path d="M20 10a8 8 0 1 0-1 8M20 5v5h-5"/><path d="M10 11v5M14 11h3v5h-3Z" stroke-width="1.3"/></symbol>
<symbol id="i-volume" viewBox="0 0 24 24"><path d="m11 4-6 5H2v6h3l6 5ZM15 8a6 6 0 0 1 0 8M18 4a11 11 0 0 1 0 16"/></symbol>
<symbol id="i-muted" viewBox="0 0 24 24"><path d="m11 4-6 5H2v6h3l6 5ZM16 9l6 6M22 9l-6 6"/></symbol>
<symbol id="i-fullscreen" viewBox="0 0 24 24"><path d="M8 3H3v5M16 3h5v5M3 16v5h5M21 16v5h-5"/></symbol>
<symbol id="i-exit" viewBox="0 0 24 24"><path d="M3 8h5V3M16 3v5h5M3 16h5v5M16 21v-5h5"/></symbol>
<symbol id="i-pip" viewBox="0 0 24 24"><rect x="2" y="4" width="20" height="16" rx="3"/><rect x="12" y="11" width="7" height="6" rx="1" fill="currentColor" stroke="none"/></symbol>
<symbol id="i-download" viewBox="0 0 24 24"><path d="M12 3v12m-4-4 4 4 4-4M4 16v4h16v-4"/></symbol>
<symbol id="i-plus" viewBox="0 0 24 24"><path d="M12 5v14M5 12h14"/></symbol><symbol id="i-minus" viewBox="0 0 24 24"><path d="M5 12h14"/></symbol>
<symbol id="i-fit" viewBox="0 0 24 24"><rect x="3" y="4" width="18" height="16" rx="2"/><path d="m7 9 3 3-3 3M17 9l-3 3 3 3"/></symbol>
<symbol id="i-retry" viewBox="0 0 24 24"><path d="M20 11a8 8 0 1 0-2 7M20 4v7h-7"/></symbol><symbol id="i-alert" viewBox="0 0 24 24"><path d="m12 3 10 18H2ZM12 9v5M12 17v1"/></symbol>
</defs></svg>''';
