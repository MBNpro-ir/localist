import 'media_stream_web.dart';

/// Filenames are text, and only generated relative routes reach media tags.
String buildMediaGalleryHtml({
  required List<StreamWebItem> items,
  bool persian = false,
}) {
  String t(String fa, String en) => persian ? fa : en;
  final counts = {'video': 0, 'image': 0, 'audio': 0};
  for (final item in items) {
    final kind = streamWebKind(item.mime);
    counts[kind] = counts[kind]! + 1;
  }
  final cards = [
    for (var i = 0; i < items.length; i++)
      () {
        final item = items[i], kind = streamWebKind(items[i].mime);
        final name = streamWebEscape(item.name),
            path = streamWebPath(item.mediaPath);
        final preview = kind == 'image'
            ? '<img src="$path" alt="" loading="lazy" decoding="async">'
            : kind == 'video'
            ? '<video data-src="$path" preload="none" muted playsinline aria-hidden="true"></video>'
            : '';
        return '''<a class="card" href="${streamWebPath(item.playerPath)}" data-kind="$kind" data-name="$name" data-order="$i" title="$name">
      <div class="preview $kind-preview"><span class="preview-placeholder">${streamWebIcon(kind)}</span>$preview<span class="type-badge">${streamWebIcon(kind)}${streamWebType(kind, persian)}</span><span class="card-open" aria-hidden="true">${streamWebIcon(kind == 'image' ? 'plus' : 'play')}</span></div>
      <div class="card-caption"><span class="card-number">${'${i + 1}'.padLeft(2, '0')}</span><div><h2 dir="auto">$name</h2><p>${streamWebType(kind, persian)}${streamWebFormat(item.name).isEmpty ? '' : ' <span>·</span> <bdi>${streamWebFormat(item.name)}</bdi>'}</p></div>${streamWebIcon(persian ? 'left' : 'right')}</div></a>''';
      }(),
  ].join();
  String filter(String kind, String title, int count) =>
      '<button class="filter" type="button" data-filter="$kind" aria-pressed="${kind == 'all'}">$title<span>$count</span></button>';
  return streamWebPage(
    title: t('گالری استریم لوکالیست', 'Localist Stream gallery'),
    persian: persian,
    page: 'gallery',
    body:
        '''
    <section class="library-heading"><div><p class="eyebrow">${t('مجموعهٔ اشتراک‌گذاشته‌شده', 'SHARED COLLECTION')}</p><h1>${t('یک مجموعه، هر صفحه‌نمایش.', 'One collection. Any screen.')}</h1><p class="intro">${t('رسانه‌ای را انتخاب کنید و همین‌جا تماشا کنید.', 'Choose something to watch, listen to, or explore.')}</p></div><div class="library-stat"><strong>${items.length}</strong><span>${t('رسانه در مجموعه', 'items to explore')}</span></div></section>
    <section class="library-tools" id="library-tools" hidden aria-label="${t('جست‌وجو و فیلتر', 'Search and filters')}">
      <label class="search-box">${streamWebIcon('search')}<input id="search" type="search" placeholder="${t('جست‌وجو در مجموعه…', 'Search this collection…')}" aria-label="${t('جست‌وجوی رسانه', 'Search media')}" aria-controls="media-grid" autocomplete="off"></label>
      <div class="library-options"><label class="sort-label"><span>${t('مرتب‌سازی', 'Sort by')}</span><select id="sort"><option value="original">${t('ترتیب انتخاب', 'Collection order')}</option><option value="name">${t('نام فایل', 'File name')}</option><option value="type">${t('نوع رسانه', 'Media type')}</option></select></label><div class="view-switch" role="group" aria-label="${t('نمایش مجموعه', 'Collection view')}">${streamWebButton('grid-view', 'grid', t('نمای شبکه‌ای', 'Grid view'), extra: 'aria-pressed="true"')}${streamWebButton('list-view', 'list', t('نمای فهرستی', 'List view'), extra: 'aria-pressed="false"')}</div></div>
    </section>
    <div class="collection-toolbar"><div class="filters" id="filters" hidden role="group" aria-label="${t('نوع رسانه', 'Media type')}">${filter('all', t('همه', 'All media'), items.length)}${filter('video', t('ویدیو', 'Videos'), counts['video']!)}${filter('image', t('عکس', 'Photos'), counts['image']!)}${filter('audio', t('موسیقی', 'Audio'), counts['audio']!)}</div><p id="result-count" aria-live="polite">${items.length} ${t('رسانه', 'items')}</p></div>
    <div id="media-grid" class="media-grid">$cards</div>
    <section class="empty-state" id="empty-state" hidden>${streamWebIcon('search')}<h2>${t('رسانه‌ای پیدا نشد', 'Nothing found')}</h2><p>${t('عبارت جست‌وجو یا فیلتر را تغییر دهید.', 'Try another search or filter.')}</p><button id="reset-filters" class="button" type="button">${t('نمایش همه', 'Show all media')}</button></section>
  ''',
  );
}
