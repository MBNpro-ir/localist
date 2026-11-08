import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:localist/services/live_capture_service.dart';

void main() {
  test(
    'microphone-only and camera-only constraints request only selected hardware',
    () {
      expect(
        const LiveCaptureOptions(camera: false).constraints['video'],
        false,
      );
      expect(
        const LiveCaptureOptions(microphone: false).constraints['audio'],
        false,
      );
      expect(
        const LiveCaptureOptions(
          rearCamera: false,
        ).constraints['video']['facingMode'],
        'user',
      );
      expect(
        () => const LiveCaptureOptions(
          camera: false,
          microphone: false,
        ).validate(),
        throwsFormatException,
      );
      expect(
        () => const LiveCaptureOptions(fps: 500).validate(),
        throwsFormatException,
      );
    },
  );
  test('signaling rejects binary, oversized and unrelated messages', () {
    for (final message in [
      <int>[1, 2],
      'x' * 131073,
      '[]',
      '{}',
      '{"type":"answer","sdp":1}',
    ]) {
      expect(() => decodeCaptureSignal(message), throwsFormatException);
    }
    expect(
      decodeCaptureSignal('{"type":"answer","sdp":"v=0"}')['type'],
      'answer',
    );
  });
  test(
    'pairing requires current token, rejects foreign origins, bounds viewers and revokes old links',
    () async {
      final server = CaptureSignalingServer(
        html: '<title>Localist Capture</title>',
        maxViewers: 1,
        accept: (socket) async {
          socket.add('accepted');
        },
      );
      await server.start();
      addTearDown(server.stop);
      final firstToken = server.token;
      final client = HttpClient()..findProxy = (_) => 'DIRECT';
      addTearDown(() => client.close(force: true));
      final response = await (await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/'),
      )).close();
      expect(response.headers.value('referrer-policy'), 'no-referrer');
      final html = await utf8.decoder.bind(response).join();
      expect(html, isNot(contains(firstToken)));
      String url(String token) =>
          'ws://127.0.0.1:${server.port}/signal?key=$token';
      await expectLater(
        WebSocket.connect(url('wrong')),
        throwsA(isA<WebSocketException>()),
      );
      await expectLater(
        WebSocket.connect(
          url(firstToken),
          headers: {'Origin': 'https://untrusted.invalid'},
        ),
        throwsA(isA<WebSocketException>()),
      );
      final socket = await WebSocket.connect(
        url(firstToken),
        headers: {'Origin': 'http://127.0.0.1:${server.port}'},
      );
      expect(await socket.first, 'accepted');
      await expectLater(
        WebSocket.connect(url(firstToken)),
        throwsA(isA<WebSocketException>()),
      );
      await server.stop();
      await server.start();
      expect(server.token, isNot(firstToken));
      await expectLater(
        WebSocket.connect(url(firstToken)),
        throwsA(isA<WebSocketException>()),
      );
    },
  );
}
