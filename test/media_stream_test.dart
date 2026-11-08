import 'dart:io';
import 'dart:convert';
import 'package:xml/xml.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localist/services/http_file_stream.dart';
import 'package:localist/services/dlna_cast_service.dart';
import 'package:localist/services/media_stream_service.dart';
import 'package:localist/services/media_stream_gallery.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // This suite exercises real loopback HTTP in addition to bundled web assets.
  HttpOverrides.global = null;
  test('DLNA metadata includes MIME resource and the correct media class', () {
    for (final entry in {
      'song.mp3': 'audioItem.musicTrack',
      'photo.jpg': 'imageItem.photo',
      'movie.mp4': 'videoItem',
    }.entries) {
      final metadata = XmlDocument.parse(
        DlnaCastService.mediaMetadata(
          Uri.parse('http://192.168.1.5/media?x=1&y=2'),
          entry.key,
        ),
      );
      expect(
        metadata.findAllElements('upnp:class').single.innerText,
        'object.item.${entry.value}',
      );
      expect(
        metadata.findAllElements('res').single.innerText,
        'http://192.168.1.5/media?x=1&y=2',
      );
      expect(
        metadata.findAllElements('res').single.getAttribute('protocolInfo'),
        startsWith('http-get:*:'),
      );
    }
  });
  test('range parser covers suffix/open/full/invalid requests', () {
    expect(parseFileRange(null, 100), (start: 0, end: 100));
    expect(parseFileRange('bytes=10-19', 100), (start: 10, end: 20));
    expect(parseFileRange('bytes=90-', 100), (start: 90, end: 100));
    expect(parseFileRange('bytes=-5', 100), (start: 95, end: 100));
    expect(parseFileRange(null, 0), (start: 0, end: 0));
    for (final range in [
      'bytes=100-',
      'bytes=4-2',
      'bytes=-0',
      'bytes=0-1,3-4',
      'garbage',
    ]) {
      expect(() => parseFileRange(range, 100), throwsFormatException);
    }
  });
  test('real HTTP range/HEAD returns exact bytes and length', () async {
    final dir = await Directory.systemTemp.createTemp('localist-media-test');
    final file = await File(
      '${dir.path}/test.mp4',
    ).writeAsBytes(List.generate(100, (i) => i));
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await serveMediaFile(request, file, 'test.mp4');
      await request.response.close();
    });
    final client = HttpClient();
    try {
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/media'),
      );
      request.headers.set('Range', 'bytes=10-19');
      final response = await request.close();
      expect(response.statusCode, 206);
      expect(response.contentLength, 10);
      final data = await response.fold<List<int>>([], (a, b) => a..addAll(b));
      expect(data, List.generate(10, (i) => i + 10));
      final head = await (await client.openUrl(
        'HEAD',
        Uri.parse('http://127.0.0.1:${server.port}/media'),
      )).close();
      expect(head.contentLength, 100);
      expect(await head.toList(), isEmpty);
    } finally {
      client.close(force: true);
      await server.close(force: true);
      await dir.delete(recursive: true);
    }
  });
  test('DLNA accepts local hosts and rejects remote/invalid addresses', () {
    expect(DlnaCastService.isLanHost('192.168.1.5'), true);
    expect(DlnaCastService.isLanHost('10.1.2.3'), true);
    expect(DlnaCastService.isLanHost('192.168.1.999'), false);
    expect(DlnaCastService.isLanHost('example.com'), false);
    expect(DlnaCastService.isLanHost('8.8.8.8'), false);
  });
  test(
    'web player contains complete browser controls and escapes metadata',
    () {
      final html = buildMediaPlayerHtml(
        name: 'movie <test>.mp4',
        mime: 'video/mp4',
        mediaPath: '/secret/media',
      );
      expect(html, contains('movie &lt;test&gt;.mp4'));
      expect(html, contains('src="/secret/media"'));
      for (final control in [
        'id="play"',
        'id="seek"',
        'id="volume"',
        'id="mute"',
        'id="speed"',
        'id="pip"',
        'id="fullscreen"',
      ]) {
        expect(html, contains(control));
      }
      final script = File('assets/stream_web/stream.js').readAsStringSync();
      expect(script, contains('media.playbackRate'));
      expect(script, contains('requestPictureInPicture'));
      expect(html, contains('controls preload="metadata"'));
      expect(html, contains('src="/_localist/stream.js?v=3"'));
    },
  );
  test('web pages keep hostile filenames as escaped text', () {
    const name = '" onerror="alert(1)"><script>alert(2)</script>&.mp4';
    final pages = [
      buildMediaPlayerHtml(
        name: name,
        mime: 'video/mp4',
        mediaPath: '/token/items/0/media',
      ),
      buildMediaGalleryHtml(
        items: [
          (
            name: name,
            mime: 'video/mp4',
            playerPath: '/token/items/0',
            mediaPath: '/token/items/0/media',
          ),
        ],
      ),
    ];
    for (final page in pages) {
      expect(page, isNot(contains('<script>alert(2)</script>')));
      expect(page, isNot(contains(' onerror="')));
      expect(page, contains('&lt;script&gt;alert(2)&lt;/script&gt;'));
      expect(page, contains('&quot;'));
      expect(page, contains('&amp;'));
    }
  });
  test('web pages reject external or browser-normalized remote routes', () {
    for (final route in [
      'https://example.com/media',
      '//example.com/media',
      '/\\example.com/media',
      '/\n/example.com/media',
    ]) {
      expect(
        () => buildMediaPlayerHtml(
          name: 'movie.mp4',
          mime: 'video/mp4',
          mediaPath: route,
        ),
        throwsFormatException,
      );
      expect(
        () => buildMediaGalleryHtml(
          items: [
            (
              name: 'movie.mp4',
              mime: 'video/mp4',
              playerPath: route,
              mediaPath: '/token/items/0/media',
            ),
          ],
        ),
        throwsFormatException,
      );
    }
  });
  test('stream root URL serves Persian controls and range endpoint', () async {
    final dir = await Directory.systemTemp.createTemp('localist-player-root');
    final file = await File(
      '${dir.path}/movie.mp4',
    ).writeAsBytes(List.generate(20, (i) => i));
    final service = MediaStreamService.instance;
    final client = HttpClient();
    try {
      service.persian = true;
      await service.start(file);
      for (final url in service.playerUrls) {
        expect(Uri.parse(url).path, isEmpty);
        expect(Uri.parse(url).port, service.port);
      }
      final response = await (await client.getUrl(
        Uri.parse('http://127.0.0.1:${service.port}'),
      )).close();
      expect(response.statusCode, 200);
      final html = await utf8.decoder.bind(response).join();
      expect(html, contains('lang="fa" dir="rtl"'));
      expect(html, contains('>پخش<'));
      expect(html, contains('aria-label="پخش"'));
      expect(
        response.headers.value('Content-Security-Policy'),
        contains("script-src 'self'"),
      );
      for (final entry in {
        'stream.css': 'text/css',
        'stream.js': 'text/javascript',
        'Vazirmatn-Regular.ttf': 'font/ttf',
      }.entries) {
        final asset = await (await client.getUrl(
          Uri.parse('http://127.0.0.1:${service.port}/_localist/${entry.key}'),
        )).close();
        expect(asset.statusCode, 200);
        expect(asset.headers.contentType!.mimeType, entry.value);
        expect(asset.contentLength, greaterThan(100));
        await asset.drain<void>();
      }
      final unavailable = await (await client.getUrl(
        Uri.parse(
          'http://127.0.0.1:${service.port}/_localist/../../pubspec.yaml',
        ),
      )).close();
      expect(unavailable.statusCode, 404);
      await unavailable.drain<void>();
      final path = RegExp(r'src="([^" ]+/media)"').firstMatch(html)!.group(1)!;
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:${service.port}$path'),
      );
      request.headers.set('Range', 'bytes=5-9');
      final media = await request.close();
      expect(media.statusCode, 206);
      expect(await media.fold<List<int>>([], (a, b) => a..addAll(b)), [
        5,
        6,
        7,
        8,
        9,
      ]);
    } finally {
      client.close(force: true);
      await service.stop();
      await dir.delete(recursive: true);
    }
  });
  test('image web player exposes zoom and fullscreen controls', () {
    final html = buildMediaPlayerHtml(
      name: 'photo.jpg',
      mime: 'image/jpeg',
      mediaPath: '/token/media',
    );
    expect(html, contains('id="zoomIn"'));
    expect(html, contains('id="zoomOut"'));
    expect(html, contains('id="fit"'));
    expect(html, isNot(contains('id="seek"')));
  });

  test('gallery escapes names and defers video preview loading', () {
    final html = buildMediaGalleryHtml(
      items: [
        (
          name: '<script>alert(1)</script>.mp4',
          mime: 'video/mp4',
          playerPath: '/token/items/0',
          mediaPath: '/token/items/0/media',
        ),
        (
          name: 'photo.jpg',
          mime: 'image/jpeg',
          playerPath: '/token/items/1',
          mediaPath: '/token/items/1/media',
        ),
      ],
      persian: true,
    );
    expect(html, contains('lang="fa" dir="rtl"'));
    expect(html, contains('&lt;script&gt;alert(1)&lt;/script&gt;.mp4'));
    expect(html, isNot(contains('<script>alert(1)')));
    expect(html, contains('loading="lazy"'));
    expect(html, contains('preload="none"'));
    expect(
      File('assets/stream_web/stream.js').readAsStringSync(),
      contains('IntersectionObserver'),
    );
    expect(html, isNot(contains('autoplay')));
  });

  test(
    'multiple files have independent players, seek routes and DLNA selection',
    () async {
      final dir = await Directory.systemTemp.createTemp('localist-gallery');
      final photo = await File(
        '${dir.path}/photo.jpg',
      ).writeAsBytes([1, 2, 3, 4]);
      final movie = await File(
        '${dir.path}/movie.mp4',
      ).writeAsBytes(List.generate(30, (i) => i + 10));
      final song = await File(
        '${dir.path}/song.mp3',
      ).writeAsBytes([60, 61, 62]);
      final service = MediaStreamService.instance;
      final client = HttpClient()..findProxy = (_) => 'DIRECT';
      // Use the bound loopback port even when the machine has no physical LAN.
      Future<HttpClientResponse> get(
        String path, {
        String method = 'GET',
        String? range,
      }) async {
        final req = await client.openUrl(
          method,
          Uri.parse('http://127.0.0.1:${service.port}$path'),
        );
        if (range != null) req.headers.set('Range', range);
        return req.close();
      }

      try {
        service.persian = true;
        await service.startFiles([photo, movie, song, photo]);
        expect(service.items.length, 3);
        final root = await get('/');
        expect(root.statusCode, 200);
        final html = await utf8.decoder.bind(root).join();
        expect(html, contains('گالری استریم لوکالیست'));
        final links = RegExp(
          r'class="card" href="([^\"]+)"',
        ).allMatches(html).map((m) => m.group(1)!).toList();
        expect(links.length, 3);
        for (var i = 0; i < links.length; i++) {
          final player = await get(links[i]);
          expect(player.statusCode, 200);
          final page = await utf8.decoder.bind(player).join();
          expect(page, contains('class="back-link" href="/"'));
          expect(page, contains('${links[i]}/media'));
          expect(page, contains(i == 0 ? 'id="zoomIn"' : 'id="seek"'));
          if (i < 2) {
            expect(page, contains('rel="next" href="${links[i + 1]}"'));
          }
        }
        final range = await get('${links[1]}/media', range: 'bytes=5-9');
        expect(range.statusCode, 206);
        expect(await range.fold<List<int>>([], (a, b) => a..addAll(b)), [
          15,
          16,
          17,
          18,
          19,
        ]);
        final head = await get('${links[0]}/media', method: 'HEAD');
        expect(head.headers.contentType!.mimeType, 'image/jpeg');
        expect(head.contentLength, 4);
        await head.drain<void>();
        service.selectItem(1);
        expect(service.name, 'movie.mp4');
        for (final url in service.urls) {
          expect(Uri.parse(url).path, '${links[1]}/media');
        }
        final photoBytes = await get('${links[0]}/media');
        expect(await photoBytes.fold<List<int>>([], (a, b) => a..addAll(b)), [
          1,
          2,
          3,
          4,
        ]);
        for (final path in [
          '/wrong-token/items/0/media',
          '${links[0].replaceFirst('/0', '/99')}/media',
          '${links[0]}/media/extra',
          '/${links[0].split('/')[1]}/items/-1',
        ]) {
          final invalid = await get(path);
          expect(invalid.statusCode, 404);
          await invalid.drain<void>();
        }
        final post = await get('/', method: 'POST');
        expect(post.statusCode, 405);
        await post.drain<void>();
        final oldMediaPath = '${links[0]}/media';
        await service.start(photo);
        final obsolete = await get(oldMediaPath);
        expect(obsolete.statusCode, 404);
        await obsolete.drain<void>();
      } finally {
        client.close(force: true);
        await service.stop();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'invalid multi-selection does not discard the existing stream',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'localist-gallery-validation',
      );
      final photo = await File('${dir.path}/photo.jpg').writeAsBytes([1]);
      final text = await File(
        '${dir.path}/private.txt',
      ).writeAsString('private');
      final service = MediaStreamService.instance;
      try {
        await service.start(photo);
        final port = service.port;
        await expectLater(
          service.startFiles([photo, text]),
          throwsFormatException,
        );
        await expectLater(service.startFiles([]), throwsFormatException);
        expect(service.active, true);
        expect(service.port, port);
        expect(service.items.single.name, 'photo.jpg');
      } finally {
        await service.stop();
        await dir.delete(recursive: true);
      }
    },
  );
}
