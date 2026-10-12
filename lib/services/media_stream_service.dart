import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';
import 'http_file_stream.dart';
import 'feature_activity_service.dart';
import 'apple_web_transfer_service.dart';

/// Serves one local media file with HTTP range support.
///
/// This is intentionally protocol-light: phones, consoles, TVs and wireless
/// display receivers that can open a local URL can play the same stream. The
/// UI keeps the URL visible so a receiver's built-in browser can be used when
/// native casting is unavailable.
class MediaStreamService extends ChangeNotifier {
  MediaStreamService._();
  static final instance = MediaStreamService._();

  HttpServer? _server;
  File? _file;
  String _name = '';
  String _token = '';
  List<String> _addresses = const [];

  bool get active => _server != null && _file != null;
  String get name => _name;
  List<String> get addresses => List.unmodifiable(_addresses);
  int get port => _server?.port ?? 0;
  List<String> get urls => [
    for (final address in _addresses)
      Uri(
        scheme: 'http',
        host: address,
        port: port,
        path: '/$_token/media',
      ).toString(),
  ];
  List<String> get playerUrls => [
    for (final address in _addresses) 'http://$address:$port',
  ];

  /// The first local player URL is convenient for opening the page on the
  /// host. Other URLs are kept in [playerUrls] for devices on other network
  /// interfaces.
  String? get playerUrl => playerUrls.isEmpty ? null : playerUrls.first;

  bool persian = false;
  Future<void> start(File file) async {
    if (!FeatureActivityService.instance.allows(LocalistFeature.stream)) {
      throw StateError(
        persian
            ? 'ابتدا سرویس فعال را متوقف کنید.'
            : 'Stop the active service first.',
      );
    }
    await stop();
    FeatureActivityService.instance.reserve(this, LocalistFeature.stream);
    try {
      if (!await file.exists()) {
        throw const FileSystemException('Media file does not exist.');
      }
      _file = file;
      _token = List.generate(
        24,
        (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      _name = file.uri.pathSegments.isEmpty
          ? 'Media'
          : file.uri.pathSegments.last;
      _server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        0,
        shared: false,
      );
      _server!.listen(
        (request) => unawaited(_handleRequest(request)),
        onError: (_) {},
      );
      _addresses = await _privateAddresses();
      notifyListeners();
    } catch (_) {
      await stop();
      rethrow;
    }
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _file = null;
    _name = '';
    _addresses = const [];
    FeatureActivityService.instance.setActive(
      this,
      LocalistFeature.stream,
      false,
    );
    notifyListeners();
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final response = request.response;
    final file = _file;
    try {
      if (request.method != 'GET' && request.method != 'HEAD') {
        response.statusCode = HttpStatus.methodNotAllowed;
        return;
      }
      if (file != null &&
          (request.uri.path == '/' || request.uri.path == '/$_token/')) {
        final mime = lookupMimeType(_name) ?? '';
        response.headers
          ..contentType = ContentType.html
          ..set(HttpHeaders.cacheControlHeader, 'no-store')
          ..set('X-Content-Type-Options', 'nosniff')
          ..set(
            'Content-Security-Policy',
            "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; media-src 'self'; img-src 'self' data:",
          );
        if (request.method == 'GET') {
          response.write(
            buildMediaPlayerHtml(
              name: _name,
              mime: mime,
              mediaPath: '/$_token/media',
              persian: persian,
            ),
          );
        }
        return;
      }
      if (file == null || request.uri.path != '/$_token/media') {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      await serveMediaFile(request, file, _name);
    } catch (_) {
      try {
        response.statusCode = HttpStatus.internalServerError;
      } catch (_) {}
    } finally {
      await response.close().catchError((_) {});
    }
  }

  static Future<List<String>> _privateAddresses() async {
    final values = <String>{};
    try {
      for (final interface in await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      )) {
        if (AppleWebTransferService.isIgnoredNetworkInterface(interface.name)) {
          continue;
        }
        for (final address in interface.addresses) {
          final p = address.address.split('.').map(int.tryParse).toList();
          if (p.length == 4 &&
              p.every((v) => v != null) &&
              (p[0] == 10 ||
                  (p[0] == 172 && p[1]! >= 16 && p[1]! <= 31) ||
                  (p[0] == 192 && p[1] == 168))) {
            values.add(address.address);
          }
        }
      }
    } catch (_) {}
    return values.toList()..sort();
  }
}

/// Builds the self-contained player page served to phones, TVs and consoles.
///
/// All controls operate in the receiver's browser, so a second app is not
/// required on the device opening the URL. The media itself remains served by
/// the range-aware endpoint above, which lets browsers seek without loading
/// the whole file first.
String buildMediaPlayerHtml({
  required String name,
  required String mime,
  required String mediaPath,
  bool persian = false,
}) {
  final safeName = const HtmlEscape().convert(name);
  final safeMime = const HtmlEscape().convert(mime);
  final isImage = mime.startsWith('image/');
  final tag = isImage
      ? '<img id="media" alt="$safeName" src="$mediaPath">'
      : '<${mime.startsWith('audio/') ? 'audio' : 'video'} id="media" preload="metadata" playsinline src="$mediaPath"></${mime.startsWith('audio/') ? 'audio' : 'video'}>';
  final controls = isImage
      ? '''<div class="image-tools" aria-label="Image controls">
          <button id="zoomOut" type="button" aria-label="Zoom out">−</button>
          <span id="zoomValue">100%</span>
          <button id="zoomIn" type="button" aria-label="Zoom in">+</button>
          <button id="fit" type="button">Fit</button>
          <button id="fullscreen" type="button">Fullscreen</button>
        </div>'''
      : '''<div class="timeline">
          <span id="current">0:00</span>
          <input id="seek" type="range" min="0" max="0" step="0.01" value="0" aria-label="Seek">
          <span id="duration">0:00</span>
        </div>
        <div class="controls" aria-label="Media controls">
          <button id="play" type="button">Play</button>
          <button id="back" type="button" aria-label="Back 10 seconds">−10s</button>
          <button id="forward" type="button" aria-label="Forward 10 seconds">+10s</button>
          <button id="mute" type="button">Mute</button>
          <input id="volume" type="range" min="0" max="1" step="0.01" value="1" aria-label="Volume">
          <label class="speed">Speed
            <select id="speed" aria-label="Playback speed">
              <option value="0.5">0.5×</option><option value="0.75">0.75×</option>
              <option value="1" selected>1×</option><option value="1.25">1.25×</option>
              <option value="1.5">1.5×</option><option value="2">2×</option>
            </select>
          </label>
          <button id="pip" type="button">Picture in picture</button>
          <button id="fullscreen" type="button">Fullscreen</button>
        </div>''';
  var html =
      '''<!doctype html>
<html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="theme-color" content="#17131e"><title>Localist Stream</title>
<style>
:root{color-scheme:dark;font-family:system-ui,-apple-system,Segoe UI,sans-serif;background:#17131e;color:#f7f3ff}
body{margin:0;min-height:100vh;background:radial-gradient(circle at 15% 0,#3a2757 0,#17131e 42%,#0d0b12 100%);display:flex;justify-content:center}
main{box-sizing:border-box;width:min(1050px,100%);padding:clamp(16px,4vw,42px)}
h1{font-size:clamp(1.35rem,3vw,2.2rem);margin:0 0 4px;overflow-wrap:anywhere}
.sub{color:#cfc6dc;margin:0 0 20px;overflow-wrap:anywhere}
.stage{background:#09080c;border:1px solid #544565;border-radius:18px;min-height:180px;display:flex;align-items:center;justify-content:center;overflow:hidden;box-shadow:0 18px 50px #0008}
#media{display:block;max-width:100%;max-height:70vh;width:100%;object-fit:contain}
img#media{width:auto;max-width:100%;height:auto;transform-origin:center;transition:transform .12s ease}
.panel{margin-top:14px;padding:14px;background:#211a2bde;border:1px solid #4a3a59;border-radius:14px}
.timeline{display:flex;align-items:center;gap:9px}.timeline input{flex:1;min-width:80px}
.controls,.image-tools{display:flex;align-items:center;justify-content:center;flex-wrap:wrap;gap:9px;margin-top:12px}
button,select{border:1px solid #735b8c;border-radius:9px;background:#37294a;color:#fff;padding:9px 12px;font:inherit;cursor:pointer}
button:hover,select:hover{background:#4b3763}button:focus-visible,input:focus-visible,select:focus-visible{outline:2px solid #dcb8ff;outline-offset:2px}
input[type=range]{accent-color:#bd82f6}label.speed{display:flex;align-items:center;gap:6px}.hint{font-size:.9rem;color:#bdb1cb;margin-top:14px}
@media(max-width:560px){.controls button,.image-tools button{padding:8px 9px}.timeline{font-size:.82rem}}
</style></head><body><main>
<h1>Localist Stream</h1><p class="sub">__NAME__</p>
<div class="stage">__TAG__</div><section class="panel">__CONTROLS__</section>
<p class="hint">Format: __MIME__. Controls run locally in this browser. Seeking uses HTTP byte ranges when supported by the device.</p>
<noscript>JavaScript is required for the player controls.</noscript>
<script>
(function(){
  const media=document.getElementById('media');
  const image=media && media.tagName==='IMG';
  const byId=id=>document.getElementById(id);
  const format=t=>{if(!Number.isFinite(t))return '0:00';const s=Math.max(0,Math.floor(t));return Math.floor(s/60)+':'+String(s%60).padStart(2,'0');};
  const fullscreen=()=>{const target=document.querySelector('.stage');if(document.fullscreenElement){document.exitFullscreen?.();}else{target.requestFullscreen?.();}};
  byId('fullscreen')?.addEventListener('click',fullscreen);
  if(image){
    let zoom=1;
    const render=()=>{media.style.transform='scale('+zoom+')';byId('zoomValue').textContent=Math.round(zoom*100)+'%';};
    byId('zoomIn')?.addEventListener('click',()=>{zoom=Math.min(4,zoom+.25);render();});
    byId('zoomOut')?.addEventListener('click',()=>{zoom=Math.max(.25,zoom-.25);render();});
    byId('fit')?.addEventListener('click',()=>{zoom=1;render();});
    return;
  }
  const seek=byId('seek'),volume=byId('volume');
  const update=()=>{seek.max=Number.isFinite(media.duration)?media.duration:0;seek.value=media.currentTime||0;byId('current').textContent=format(media.currentTime);byId('duration').textContent=format(media.duration);byId('play').textContent=media.paused?'Play':'Pause';byId('mute').textContent=media.muted||media.volume===0?'Unmute':'Mute';};
  media.addEventListener('loadedmetadata',update);media.addEventListener('durationchange',update);media.addEventListener('timeupdate',update);media.addEventListener('play',update);media.addEventListener('pause',update);media.addEventListener('volumechange',update);
  byId('play').addEventListener('click',()=>media.paused?media.play():media.pause());
  byId('back').addEventListener('click',()=>{media.currentTime=Math.max(0,(media.currentTime||0)-10);});
  byId('forward').addEventListener('click',()=>{media.currentTime=Math.min(media.duration||Infinity,(media.currentTime||0)+10);});
  seek.addEventListener('input',()=>{media.currentTime=Number(seek.value);});
  volume.addEventListener('input',()=>{media.volume=Number(volume.value);media.muted=false;});
  byId('mute').addEventListener('click',()=>{media.muted=!media.muted;});
  byId('speed').addEventListener('change',e=>{media.playbackRate=Number(e.target.value);});
  byId('pip')?.addEventListener('click',async()=>{try{if(document.pictureInPictureElement){await document.exitPictureInPicture();}else if(media.requestPictureInPicture){await media.requestPictureInPicture();}}catch(_){}});
  media.addEventListener('dblclick',fullscreen);media.addEventListener('click',()=>{if(media.paused)media.play();else media.pause();});
  update();
})();
</script></main></body></html>'''
          .replaceAll('__NAME__', safeName)
          .replaceAll('__MIME__', safeMime)
          .replaceAll('__TAG__', tag)
          .replaceAll('__CONTROLS__', controls);
  if (persian) {
    const labels = {
      'Image controls': 'کنترل تصویر',
      'Zoom out': 'کوچک‌نمایی',
      'Zoom in': 'بزرگ‌نمایی',
      'Fit': 'اندازه صفحه',
      'Fullscreen': 'تمام‌صفحه',
      'Seek': 'زمان پخش',
      'Media controls': 'کنترل پخش',
      'Playback speed': 'سرعت پخش',
      'Back 10 seconds': 'ده ثانیه عقب',
      'Forward 10 seconds': 'ده ثانیه جلو',
      'Picture in picture': 'تصویر در تصویر',
      'Play': 'پخش',
      'Pause': 'توقف',
      'Unmute': 'وصل صدا',
      'Mute': 'قطع صدا',
      'Volume': 'صدا',
      'Speed': 'سرعت',
      'Localist Stream': 'استریم لوکالیست',
      'JavaScript is required for the player controls.':
          'برای کنترل پخش، جاوااسکریپت مرورگر را فعال کنید.',
    };
    for (final entry in labels.entries) {
      html = html
          .replaceAll('>${entry.key}<', '>${entry.value}<')
          .replaceAll('"${entry.key}"', '"${entry.value}"')
          .replaceAll("'${entry.key}'", "'${entry.value}'");
    }
    html = html
        .replaceAll('lang="en"', 'lang="fa" dir="rtl"')
        .replaceAll(
          'Format: $safeMime. Controls run locally in this browser. Seeking uses HTTP byte ranges when supported by the device.',
          'فرمت: $safeMime. کنترل رسانه در همین مرورگر انجام می‌شود.',
        )
        .replaceAll('Speed\n', 'سرعت\n');
  }
  return html;
}
