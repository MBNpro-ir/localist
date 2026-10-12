import 'dart:io';
import 'dart:convert';
import 'package:xml/xml.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localist/services/http_file_stream.dart';
import 'package:localist/services/dlna_cast_service.dart';
import 'package:localist/services/media_stream_service.dart';

void main() {
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
        'media.playbackRate',
        'requestPictureInPicture',
      ]) {
        expect(html, contains(control));
      }
    },
  );
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
      expect(html, contains("media.paused?'پخش':'توقف'"));
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
}
