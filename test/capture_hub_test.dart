import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:localist/services/capture_discovery_service.dart';
import 'package:localist/services/capture_hub_service.dart';
import 'package:localist/services/lan_network_service.dart';
import 'package:localist/services/live_capture_service.dart';
import 'package:localist/services/windows_virtual_devices_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Discovery extends CaptureDiscoveryService {
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> announce({bool query = false}) async {}
}

class _RealHttp extends HttpOverrides {}

class _Capture extends LiveCaptureService {
  bool connected = false;
  final List<String> linksUsed = [];
  int stopped = 0;
  @override
  bool get receiving => connected;
  @override
  Future<void> connect(String link) async {
    linksUsed.add(link);
    connected = true;
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    stopped++;
    connected = false;
    notifyListeners();
  }

  @override
  Future<void> setPlaybackMuted(bool mute) async {
    playbackMuted = mute;
  }
}

class _Renderer extends RTCVideoRenderer {
  MediaStream? source;
  int bindings = 0;
  @override
  Future<void> initialize() async {}
  @override
  set srcObject(MediaStream? value) {
    bindings++;
    source = value;
  }

  @override
  MediaStream? get srcObject => source;
  @override
  Future<void> setSrcObject({MediaStream? stream, String? trackId}) async {
    srcObject = stream;
  }
}

class _MutableStream extends Fake implements MediaStream {
  final videos = <MediaStreamTrack>[];
  @override
  List<MediaStreamTrack> getVideoTracks() => videos;
}

class _OutputRenderer extends _Renderer {
  @override
  int? get textureId => 1;
}

class _MissingMicrophone extends WindowsVirtualDevicesService {
  _MissingMicrophone(int slot) : super(slot: slot);
  @override
  Future<void> setCameraInstalled(bool installed) async {}
  @override
  void startCamera(int texture, {int fps = 30}) {
    cameraEnabled = true;
  }

  @override
  void stopCamera() {
    cameraEnabled = false;
  }

  @override
  Future<void> setMicrophoneSource(MediaStream? stream) async {
    throw StateError('Dedicated driver is not installed');
  }
}

class _MissingCamera extends WindowsVirtualDevicesService {
  _MissingCamera(int slot) : super(slot: slot);
  int audioBindings = 0;
  @override
  Future<void> setCameraInstalled(bool installed) async {
    throw StateError('Camera count is lower than this slot');
  }

  @override
  Future<void> setMicrophoneSource(MediaStream? stream) async {
    audioBindings++;
  }
}

class _VideoTrack extends Fake implements MediaStreamTrack {
  @override
  String get id => 'late-video';
}

class _HeldCapture extends _Capture {
  final released = Completer<void>();
  @override
  Future<void> setPlaybackMuted(bool mute) => released.future;
  void changed() => notifyListeners();
}

class _SocketCapture extends _Capture {
  @override
  Future<void> connect(String link) async {
    linksUsed.add(link);
    final socket = await connectCaptureSocket(Uri.parse(link));
    try {
      expect(await socket.first, 'capture accepted');
    } finally {
      await socket.close();
    }
    connected = true;
    error = '';
    notifyListeners();
  }
}

CaptureAdvertisement ad(
  int number, {
  String host = '192.168.1.2',
  int priority = 2,
  int? port,
}) => CaptureAdvertisement(
  id: 'device-identity-$number',
  name: 'Phone $number',
  model: 'Device $number',
  host: host,
  port: port ?? 40000 + number,
  key: List.filled(43, 'a').join(),
  camera: true,
  microphone: true,
  priority: priority,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.prs.localist.vpn'),
          (_) async => null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('FlutterWebRTC.Method'),
          (_) async => null,
        );
  });
  CaptureHubService hub() => CaptureHubService(
    discovery: _Discovery(),
    receiverFactory: _Capture.new,
    rendererFactory: _Renderer.new,
    windows: false,
  );
  Future<void> settle(CaptureHubService hub) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await hub.tick();
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }

  test(
    'a missing microphone driver preserves the received video and RTC session',
    () async {
      final capture = _Capture();
      final stream = _MutableStream()..videos.add(_VideoTrack());
      capture.remoteStream = stream;
      final service = CaptureHubService(
        discovery: _Discovery(),
        receiverFactory: () => capture,
        rendererFactory: _OutputRenderer.new,
        outputFactory: _MissingMicrophone.new,
        windows: true,
      );
      await service.start();
      try {
        service.observe(ad(98));
        await settle(service);
        final receiver = service.receivers.single;
        expect(capture.receiving, isTrue);
        expect(receiver.renderer.srcObject, same(stream));
        expect(receiver.output.cameraEnabled, isTrue);
        expect(receiver.error, isEmpty);
        expect(
          receiver.outputError,
          contains('Dedicated driver is not installed'),
        );
        expect(capture.playbackMuted, isTrue);
        expect(capture.linksUsed.length, 1);
      } finally {
        await service.stop();
      }
    },
  );

  test(
    'a video track arriving during audio/output sync is rebound to the same stream',
    () async {
      final capture = _HeldCapture();
      final stream = _MutableStream();
      capture.remoteStream = stream;
      final renderer = _Renderer();
      final service = CaptureHubService(
        discovery: _Discovery(),
        receiverFactory: () => capture,
        rendererFactory: () => renderer,
        windows: false,
      );
      await service.start();
      try {
        service.observe(ad(99));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(renderer.source, isNull);
        final initialBindings = renderer.bindings;
        stream.videos.add(_VideoTrack());
        capture.changed();
        capture.released.complete();
        await settle(service);
        expect(renderer.source, same(stream));
        expect(
          renderer.bindings,
          greaterThan(initialBindings),
          reason: 'Video must bind after the initial audio-only stream',
        );
        expect(service.receivers.single.renderedVideoTrack, 'late-video');
      } finally {
        if (!capture.released.isCompleted) capture.released.complete();
        await service.stop();
      }
    },
  );

  test(
    'Setup camera count does not prevent an independent audio output',
    () async {
      final capture = _Capture()
        ..remoteStream = (_MutableStream()..videos.add(_VideoTrack()));
      final output = _MissingCamera(0);
      final service = CaptureHubService(
        discovery: _Discovery(),
        receiverFactory: () => capture,
        rendererFactory: _OutputRenderer.new,
        outputFactory: (_) => output,
        windows: true,
      );
      await service.start();
      try {
        service.observe(ad(97));
        await settle(service);
        expect(output.audioBindings, greaterThan(0));
        final attempts = output.audioBindings;
        await service.tick();
        expect(
          output.audioBindings,
          greaterThan(attempts),
          reason: 'A healthy RTC session must retry unavailable outputs',
        );
        expect(capture.receiving, isTrue);
        expect(
          service.receivers.single.outputError,
          contains('Camera count is lower'),
        );
      } finally {
        await service.stop();
      }
    },
  );

  for (final code in [404, 501]) {
    test(
      'failed USB endpoint ($code) falls back without heartbeat reconnect loops',
      () => HttpOverrides.runWithHttpOverrides(() async {
        final bad = await HttpServer.bind(InternetAddress('127.0.0.2'), 0);
        var failedRequests = 0;
        var recovered = false;
        bad.listen((request) async {
          failedRequests++;
          if (recovered) {
            final socket = await WebSocketTransformer.upgrade(request);
            socket.add('capture accepted');
            return;
          }
          request.response.statusCode = code;
          await request.response.close();
        });
        final good = CaptureSignalingServer(
          html: '',
          accept: (socket) async => socket.add('capture accepted'),
        );
        await good.start();
        final service = CaptureHubService(
          discovery: _Discovery(),
          receiverFactory: _SocketCapture.new,
          rendererFactory: _Renderer.new,
          windows: false,
        );
        await service.start();
        try {
          final wifi = CaptureAdvertisement(
            id: ad(1).id,
            name: 'phone',
            model: 'QA',
            host: '127.0.0.1',
            port: good.port,
            key: good.token,
            camera: true,
            microphone: true,
          );
          final usb = CaptureAdvertisement(
            id: wifi.id,
            name: wifi.name,
            model: wifi.model,
            host: '127.0.0.2',
            port: bad.port,
            key: good.token,
            camera: true,
            microphone: true,
            priority: 0,
          );
          service.observe(wifi);
          await settle(service);
          service.observe(usb);
          await settle(service);
          await settle(service);
          expect(service.receivers.single.capture.receiving, true);
          expect(service.receivers.single.advertisement.host, '127.0.0.1');
          expect(failedRequests, 1);
          // Expiring a cooldown must not interrupt a healthy fallback session.
          service.receivers.single.failedRoutes[usb.link] = DateTime.now()
              .subtract(const Duration(seconds: 1));
          final count = (service.receivers.single.capture as _SocketCapture)
              .linksUsed
              .length;
          for (var i = 0; i < 3; i++) {
            service.observe(usb);
            service.observe(wifi);
            await settle(service);
          }
          expect(
            (service.receivers.single.capture as _SocketCapture)
                .linksUsed
                .length,
            count,
          );
          // A fresh connection can return to the preferred cable once repaired.
          recovered = true;
          await service.configure(service.receivers.single, enabled: false);
          await service.configure(service.receivers.single, enabled: true);
          await settle(service);
          expect(service.receivers.single.advertisement.host, usb.host);
          service.observe(wifi);
          await settle(service);
          expect(service.receivers.single.advertisement.host, usb.host);
          expect(service.receivers.single.capture.receiving, true);
        } finally {
          await service.stop();
          await good.stop();
          await bad.close(force: true);
        }
      }, _RealHttp()),
    );
  }

  test(
    'four senders connect automatically with isolated switches and no self discovery',
    () async {
      final service = hub();
      await service.start();
      addTearDown(service.stop);
      service.observe(
        CaptureAdvertisement(
          id: service.id,
          name: 'self',
          model: 'self',
          host: '192.168.1.1',
          port: 40000,
          key: List.filled(43, 'a').join(),
          camera: true,
          microphone: true,
        ),
      );
      for (var i = 1; i <= 5; i++) {
        service.observe(ad(i));
      }
      await settle(service);
      expect(service.receivers.length, 4);
      expect(service.receivers.map((r) => r.slot).toSet(), {0, 1, 2, 3});
      expect(service.receivers.every((r) => r.capture.receiving), true);
      final first = service.receivers.first;
      await service.configure(
        first,
        audio: false,
        video: false,
        enabled: false,
      );
      expect(first.capture.receiving, false);
      expect(first.audio, false);
      expect(
        service.receivers
            .skip(1)
            .every((r) => r.capture.receiving && r.audio && r.video),
        true,
      );
      await service.configure(first, enabled: true);
      await settle(service);
      expect(first.capture.receiving, true);
      expect(first.capture.playbackMuted, true);
      final prefs = await SharedPreferences.getInstance();
      expect(
        jsonDecode(
          prefs.getString('capture.receiver.${first.advertisement.id}')!,
        )['audio'],
        false,
      );
      await service.setEnabled(false);
      expect(service.receivers.every((r) => !r.capture.receiving), true);
      await service.setEnabled(true);
      await settle(service);
      expect(service.receivers.every((r) => r.capture.receiving), true);
    },
  );
  test(
    'USB endpoint takes precedence over Wi-Fi without reconnect oscillation',
    () async {
      final service = hub();
      await service.start();
      addTearDown(service.stop);
      service.observe(ad(1));
      await settle(service);
      service.observe(ad(1, host: '192.168.42.2', priority: 0));
      await settle(service);
      final receiver = service.receivers.single;
      expect(receiver.advertisement.host, '192.168.42.2');
      final count = (receiver.capture as _Capture).linksUsed.length;
      service.observe(ad(1));
      await settle(service);
      expect(receiver.advertisement.host, '192.168.42.2');
      expect((receiver.capture as _Capture).linksUsed.length, count);
      expect(
        const LanRoute(
          '192.168.42.1',
          24,
          'Remote NDIS USB adapter',
        ).capturePriority,
        0,
      );
      expect(
        const LanRoute(
          '192.168.42.1',
          24,
          'Remote NDIS Compatible Device',
        ).capturePriority,
        0,
      );
      expect(const LanRoute('192.168.42.1', 24).contains('192.168.42.2'), true);
      expect(const LanRoute('192.168.42.1', 24).contains('192.168.1.2'), false);
    },
  );
  test(
    'offline devices close only their session and reconnect automatically',
    () async {
      final service = hub();
      await service.start();
      addTearDown(service.stop);
      service.observe(ad(1));
      service.observe(ad(2));
      await settle(service);
      final first = service.receivers.first;
      first.lastSeen = DateTime.now().subtract(const Duration(seconds: 20));
      await service.tick();
      expect(first.capture.receiving, false);
      expect(service.receivers.last.capture.receiving, true);
      service.observe(ad(1));
      await settle(service);
      expect(first.capture.receiving, true);
    },
  );
  test(
    'LAN announcements reject arbitrary URLs, public hosts and malformed metadata',
    () {
      final encoded = utf8.encode(jsonEncode(ad(1).toJson()));
      expect(
        CaptureAdvertisement.decode(encoded, '192.168.1.2')?.host,
        '192.168.1.2',
      );
      expect(CaptureAdvertisement.decode(encoded, '8.8.8.8'), isNull);
      expect(
        CaptureAdvertisement.decode(utf8.encode('{}'), '192.168.1.2'),
        isNull,
      );
      final invalid = ad(1).toJson()..['key'] = 'https://example.com';
      expect(
        CaptureAdvertisement.decode(
          utf8.encode(jsonEncode(invalid)),
          '192.168.1.2',
        ),
        isNull,
      );
    },
  );
  test('preferred camera slots survive application restart', () async {
    final first = hub();
    await first.start();
    first.observe(ad(1));
    first.observe(ad(2));
    await settle(first);
    await first.configure(
      first.receivers.first,
      audio: false,
      audioEndpoint: 'saved-cable',
    );
    await first.stop();
    final next = hub();
    await next.start();
    addTearDown(next.stop);
    next.observe(ad(2));
    next.observe(ad(1));
    await settle(next);
    expect(next.receivers.first.advertisement.id, ad(1).id);
    expect(next.receivers.first.audio, false);
    expect(next.receivers.first.output.microphoneEndpoint, 'saved-cable');
    expect(next.receivers.last.advertisement.id, ad(2).id);
  });
  test('USB media candidates stay on the selected cable interface', () {
    const cable = 'candidate:1 1 udp 123 192.168.42.1 50000 typ host';
    const wifi = 'candidate:2 1 udp 123 192.168.1.2 50001 typ host';
    expect(captureCandidateAllowed(cable, {'192.168.42.1'}), true);
    expect(captureCandidateAllowed(wifi, {'192.168.42.1'}), false);
    expect(captureCandidateAllowed(wifi, {}), true);
    expect(captureCandidateAllowed('', {'192.168.42.1'}), true);
  });
  test('actual UDP transport observes the sender source address', () async {
    final reserve = await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final port = reserve.port;
    reserve.close();
    var routes = <LanRoute>[];
    final discovery = CaptureDiscoveryService(
      port: port,
      routes: () async => routes,
    );
    final received = Completer<CaptureAdvertisement>();
    discovery.onAdvertisement = (value) {
      if (!received.isCompleted) received.complete(value);
    };
    await discovery.start();
    // A receiver with no outgoing media must notice a cable added after launch.
    routes = [const LanRoute('127.0.0.1', 8, 'USB tether')];
    await discovery.announce();
    final sender = await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    try {
      sender.send(
        utf8.encode(jsonEncode(ad(1).toJson())),
        InternetAddress.loopbackIPv4,
        port,
      );
      final found = await received.future.timeout(const Duration(seconds: 2));
      expect(found.host, '127.0.0.1');
      expect(found.name, 'Phone 1');
      expect(found.priority, 0);
    } finally {
      sender.close();
      await discovery.stop();
    }
  });
}
