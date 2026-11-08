import 'media_stream_web.dart';

/// Native media controls remain usable when JavaScript is unavailable.
String buildMediaPlayerHtml({
  required String name,
  required String mime,
  required String mediaPath,
  bool persian = false,
  String? galleryPath,
  String? previousPath,
  String? nextPath,
  List<StreamWebItem> items = const [],
  int currentIndex = 0,
}) {
  String t(String fa, String en) => persian ? fa : en;
  final kind = streamWebKind(mime);
  final image = kind == 'image', audio = kind == 'audio';
  final path = streamWebPath(mediaPath), safeName = streamWebEscape(name);
  final controls = image
      ? '''<div class="image-controls" id="enhanced-controls" hidden>
    ${streamWebButton('zoomOut', 'minus', t('کوچک‌نمایی', 'Zoom out'))}<output id="zoomValue" dir="ltr">100%</output>${streamWebButton('zoomIn', 'plus', t('بزرگ‌نمایی', 'Zoom in'))}
    ${streamWebButton('fit', 'fit', t('اندازهٔ صفحه', 'Fit image'))}<span class="control-spacer"></span>${streamWebButton('fullscreen', 'fullscreen', t('تمام‌صفحه', 'Fullscreen'))}</div>'''
      : '''
    <div class="playback-controls" id="enhanced-controls" hidden>
      <div class="timeline"><label class="sr-only" for="seek">${t('زمان پخش', 'Seek')}</label><input id="seek" type="range" min="0" max="0" step="0.01" value="0" disabled></div>
      <div class="control-row" dir="ltr">
        ${streamWebButton('play', 'play', t('پخش', 'Play'))}${streamWebButton('back', 'back', t('ده ثانیه عقب', 'Back 10 seconds'), classes: 'skip-control')}${streamWebButton('forward', 'forward', t('ده ثانیه جلو', 'Forward 10 seconds'), classes: 'skip-control')}
        <span class="time-display"><span id="current">0:00</span><span class="time-divider"> / </span><span id="duration">0:00</span></span><span class="control-spacer"></span>
        ${streamWebButton('mute', 'volume', t('قطع صدا', 'Mute'))}<label class="volume-control"><span class="sr-only">${t('بلندی صدا', 'Volume')}</span><input id="volume" type="range" min="0" max="1" step="0.01" value="1"></label>
        <label class="speed-control"><span class="sr-only">${t('سرعت پخش', 'Playback speed')}</span><select id="speed" aria-label="${t('سرعت پخش', 'Playback speed')}"><option value="0.5">0.5×</option><option value="0.75">0.75×</option><option value="1" selected>1×</option><option value="1.25">1.25×</option><option value="1.5">1.5×</option><option value="2">2×</option></select></label>
        ${streamWebButton('pip', 'pip', t('تصویر در تصویر', 'Picture in picture'), extra: 'hidden')}${streamWebButton('fullscreen', 'fullscreen', t('تمام‌صفحه', 'Fullscreen'))}
      </div></div>''';
  final media = image
      ? '<img id="media" alt="$safeName" src="$path" draggable="false">'
      : audio
      ? '<div class="audio-art" aria-hidden="true"><span class="audio-disc">${streamWebIcon('audio')}</span><div class="audio-bars"><i></i><i></i><i></i><i></i><i></i><i></i><i></i></div></div><audio id="media" controls preload="metadata" src="$path"></audio>'
      : '<video id="media" controls preload="metadata" playsinline src="$path" aria-label="$safeName"></video>';
  String navigation(String? route, String rel, String icon, String label) =>
      route == null
      ? '<span class="nav-link disabled" aria-disabled="true">${streamWebIcon(icon)}<span>$label</span></span>'
      : '<a class="nav-link" rel="$rel" href="${streamWebPath(route)}">${streamWebIcon(icon)}<span>$label</span></a>';
  final playlist = items.length < 2
      ? ''
      : '''<aside class="playlist" aria-label="${t('رسانه‌های این مجموعه', 'Shared collection')}"><div class="playlist-heading"><h2>${t('در این مجموعه', 'In this collection')}</h2><span class="count-badge">${items.length}</span></div>
    <div class="playlist-items">${[for (var i = 0; i < items.length; i++) '<a class="queue-item${i == currentIndex ? ' is-current' : ''}" href="${streamWebPath(items[i].playerPath)}" ${i == currentIndex ? 'aria-current="page"' : ''}><span class="queue-preview">${streamWebKind(items[i].mime) == 'image' ? '<img src="${streamWebPath(items[i].mediaPath)}" alt="" loading="lazy">' : streamWebIcon(streamWebKind(items[i].mime))}</span><span class="queue-caption"><strong dir="auto">${streamWebEscape(items[i].name)}</strong><small>${streamWebType(streamWebKind(items[i].mime), persian)}</small></span><span class="queue-number">${i == currentIndex ? streamWebIcon('play') : '${i + 1}'.padLeft(2, '0')}</span></a>'].join()}</div>
    ${galleryPath == null ? '' : '<a class="collection-link" href="${streamWebPath(galleryPath)}">${streamWebIcon('grid')}${t('نمایش همهٔ رسانه‌ها', 'Browse all media')}</a>'}</aside>''';
  return streamWebPage(
    title: name,
    persian: persian,
    page: 'player-$kind',
    body:
        '''
  <nav class="player-navigation" aria-label="${t('پیمایش رسانه‌ها', 'Media navigation')}">${galleryPath == null ? '<span class="eyebrow">${t('پخش‌کنندهٔ شما', 'YOUR PLAYER')}</span>' : '<a class="back-link" href="${streamWebPath(galleryPath)}">${streamWebIcon(persian ? 'right' : 'left')}<span>${t('بازگشت به گالری', 'Back to collection')}</span></a>'}<span class="position-label">${items.isEmpty ? streamWebType(kind, persian) : '${currentIndex + 1} / ${items.length}'}</span></nav>
  <div class="watch-layout${playlist.isEmpty ? ' solo' : ''}"><article class="watch-main">
    <section class="player-stage $kind-stage" id="player" tabindex="0" aria-label="${t('پخش‌کنندهٔ رسانه', 'Media player')}"><div class="media-surface">$media</div>
    ${image || audio ? '' : '<button class="center-play" id="center-play" type="button" aria-label="${t('پخش ویدیو', 'Play video')}" hidden>${streamWebIcon('play')}</button>'}
    <div class="buffering" id="buffering" aria-hidden="true" hidden><span></span></div>
    <div class="player-error" id="player-error" role="alert" hidden>${streamWebIcon('alert')}<h2>${t('پخش انجام نشد', 'Unable to play')}</h2><p id="error-message"></p><button id="retry" class="button" type="button">${streamWebIcon('retry')}${t('تلاش دوباره', 'Try again')}</button></div>$controls</section>
    <div class="media-heading"><div class="media-title"><span class="eyebrow">${streamWebType(kind, persian)}${streamWebFormat(name).isEmpty ? '' : ' <span aria-hidden="true">/</span> <bdi>${streamWebFormat(name)}</bdi>'}</span><h1 dir="auto">$safeName</h1></div><a class="download-link" href="$path" download="$safeName" aria-label="${t('دریافت فایل', 'Download file')}">${streamWebIcon('download')}<span>${t('دریافت', 'Download')}</span></a></div>
    <nav class="item-navigation" aria-label="${t('رسانهٔ قبلی و بعدی', 'Previous and next media')}">${navigation(previousPath, 'prev', persian ? 'right' : 'left', t('قبلی', 'Previous'))}<span class="keyboard-hint">${image ? t('برای بزرگ‌نمایی دوبار بزنید', 'Double-click to zoom') : t('Space پخش و توقف · ← → جابه‌جایی', 'Space to play · ← → to seek')}</span>${navigation(nextPath, 'next', persian ? 'left' : 'right', t('بعدی', 'Next'))}</nav>
    <p class="player-status" id="player-status" aria-live="polite"></p></article>$playlist</div>''',
  );
}
