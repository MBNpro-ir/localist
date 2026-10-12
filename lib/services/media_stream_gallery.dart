import 'dart:convert';

/// Only generated relative routes reach this renderer. Local paths and file
/// names are never used as URLs, and metadata is escaped as HTML text.
String buildMediaGalleryHtml({
  required List<
    ({String name, String mime, String playerPath, String mediaPath})
  >
  items,
  bool persian = false,
}) {
  String escape(String value) =>
      const HtmlEscape(HtmlEscapeMode.attribute).convert(value);
  final title = persian ? 'گالری استریم لوکالیست' : 'Localist Stream gallery';
  final hint = persian
      ? 'برای تماشا یا پخش، یکی از رسانه‌ها را انتخاب کنید.'
      : 'Choose a photo, video or song to open its player.';
  final cards = items.map((item) {
    final name = escape(item.name);
    final path = escape(item.mediaPath);
    final image = item.mime.startsWith('image/');
    final video = item.mime.startsWith('video/');
    final type = image
        ? (persian ? 'عکس' : 'Photo')
        : video
        ? (persian ? 'فیلم' : 'Video')
        : (persian ? 'موسیقی' : 'Audio');
    final preview = image
        ? '<img src="$path" alt="$name" loading="lazy" decoding="async">'
        : video
        ? '<video data-src="$path" preload="none" muted playsinline aria-label="$name"></video><span class="play" aria-hidden="true">▶</span>'
        : '<span class="music" aria-hidden="true">♫</span>';
    return '<a class="card" href="${escape(item.playerPath)}"><div class="preview">$preview</div><div class="caption"><span class="type">$type</span><strong>$name</strong></div></a>';
  }).join();
  return '''<!doctype html>
<html lang="${persian ? 'fa" dir="rtl' : 'en'}"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="theme-color" content="#17131e"><title>$title</title>
<style>
:root{color-scheme:dark;font-family:system-ui,-apple-system,Segoe UI,sans-serif;background:#17131e;color:#f7f3ff}
body{margin:0;min-height:100vh;background:radial-gradient(circle at 15% 0,#3a2757 0,#17131e 42%,#0d0b12 100%)}
main{max-width:1200px;margin:auto;padding:clamp(16px,4vw,42px)}h1{font-size:clamp(1.4rem,3vw,2.2rem);margin:0 0 8px}.hint{color:#cfc6dc;margin:0 0 24px}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(min(100%,220px),1fr));gap:18px}
.card{display:block;min-width:0;color:inherit;text-decoration:none;border:1px solid #544565;border-radius:16px;background:#211a2b;overflow:hidden;transition:transform .15s,border-color .15s}
.card:hover{transform:translateY(-3px);border-color:#bd82f6}.card:focus-visible{outline:3px solid #dcb8ff;outline-offset:3px}
.preview{position:relative;aspect-ratio:16/10;display:flex;align-items:center;justify-content:center;background:#09080c;overflow:hidden}
.preview img,.preview video{width:100%;height:100%;object-fit:cover}.play{position:absolute;font-size:28px;background:#0009;padding:8px 14px;border-radius:50%}.music{font-size:64px;color:#bd82f6}
.caption{padding:14px}.type{display:block;color:#c8a4eb;font-size:.85rem;margin-bottom:6px}strong{display:block;overflow-wrap:anywhere;line-height:1.4}
@media(prefers-reduced-motion:reduce){.card{transition:none}}
</style></head><body><main><h1>$title</h1><p class="hint">${items.length} ${persian ? 'رسانه' : 'items'} · $hint</p><div class="grid">$cards</div></main>
<script>
(function(){
  const videos=document.querySelectorAll('video[data-src]');
  const load=v=>{v.src=v.dataset.src;v.preload='metadata';delete v.dataset.src;};
  if('IntersectionObserver' in window){
    const observer=new IntersectionObserver(entries=>{for(const entry of entries){if(entry.isIntersecting){load(entry.target);observer.unobserve(entry.target);}}},{rootMargin:'100px'});
    videos.forEach(v=>observer.observe(v));
  }else{videos.forEach(load);}
})();
</script></body></html>''';
}
