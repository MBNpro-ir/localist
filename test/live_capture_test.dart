import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:localist/services/live_capture_service.dart';

class _ProxyOverrides extends HttpOverrides {
  _ProxyOverrides(this.port);
  final int port;
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..findProxy = (_) => 'PROXY 127.0.0.1:$port';
}

void main() {
  test(
    'LAN signaling bypasses a proxy that rejects WebSocket upgrades with 501',
    () async {
      var proxyRequests = 0;
      final proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      proxy.listen((request) async {
        proxyRequests++;
        request.response.statusCode = 501;
        await request.response.close();
      });
      final server = CaptureSignalingServer(
        html: '',
        accept: (socket) async => socket.add('direct connection'),
      );
      await server.start();
      try {
        await HttpOverrides.runWithHttpOverrides(() async {
          final uri = Uri(
            scheme: 'http',
            host: '127.0.0.1',
            port: server.port,
            fragment: server.token,
          );
          // Reproduce a client using the same inherited proxy settings.
          final proxied = HttpClient();
          await expectLater(
            WebSocket.connect(
              uri
                  .replace(
                    scheme: 'ws',
                    path: '/signal',
                    fragment: '',
                    queryParameters: {'key': server.token},
                  )
                  .toString(),
              customClient: proxied,
            ),
            throwsA(isA<WebSocketException>()),
          );
          expect(proxyRequests, 1);
          proxied.close(force: true);
          final socket = await connectCaptureSocket(uri);
          expect(await socket.first, 'direct connection');
          await socket.close();
          expect(proxyRequests, 1);
        }, _ProxyOverrides(proxy.port));
      } finally {
        await server.stop();
        await proxy.close(force: true);
      }
    },
  );
  test('capture controls validate all commands before native or peer use', () {
    for (final command in <Map<String, dynamic>>[
      {},
      {'password': 'x'},
      {'zoom': double.nan},
      {'zoom': 101},
      {'width': 10000},
      {'fps': 500},
      {'bitrate': -1},
      {'noise': 1},
      {'microphone': 12},
      {'microphone': -2},
      {'width': '640'},
    ]) {
      expect(() => validateCaptureControl(command), throwsFormatException);
    }
    validateCaptureControl({
      'width': 640,
      'fps': 15,
      'bitrate': 750,
      'zoom': 2.0,
      'noise': false,
      'echo': false,
      'gain': true,
      'torch': false,
      'microphone': 0,
    });
    expect(const LiveCaptureOptions().receiverControls, true);
    expect(
      const LiveCaptureOptions(
        receiverControls: true,
      ).copyWith(background: true).receiverControls,
      true,
    );
    expect(
      () => decodeCaptureSignal(
        '{"type":"control","id":1,"command":{"fps":999}}',
      ),
      throwsFormatException,
    );
    expect(
      () => decodeCaptureSignal('{"type":"control-state","state":[]}'),
      throwsFormatException,
    );
    expect(
      () =>
          decodeCaptureSignal('{"type":"control-result","id":1,"error":true}'),
      throwsFormatException,
    );
  });

  test(
    'capture controls are unavailable until the sender starts sharing',
    () async {
      final service = LiveCaptureService();
      addTearDown(service.dispose);
      await expectLater(
        service.requestCaptureControl({'zoom': 2}),
        throwsStateError,
      );
      expect(service.captureControlState['enabled'], false);
    },
  );
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
      const LiveCaptureOptions(
        width: 320,
        height: 240,
        fps: 10,
        bitrateKbps: 350,
      ).validate();
      final audio =
          const LiveCaptureOptions(
                noiseSuppression: false,
                autoGain: false,
                echoCancellation: false,
                microphoneId: 'usb-mic',
              ).constraints['audio']
              as Map;
      final native = {
        for (final option in audio['optional'] as List) ...(option as Map),
      };
      expect(native['googNoiseSuppression'], false);
      expect(native['googAutoGainControl'], false);
      expect(native['googEchoCancellation'], false);
      expect(native['sourceId'], 'usb-mic');
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
