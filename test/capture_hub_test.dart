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
import 'package:shared_preferences/shared_preferences.dart';

class _Discovery extends CaptureDiscoveryService {
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> announce({bool query = false}) async {}
}

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
  @override
  Future<void> initialize() async {}
  @override
  set srcObject(MediaStream? value) {
    source = value;
  }

  @override
  MediaStream? get srcObject => source;
}

CaptureAdvertisement ad(
  int number, {
  String host = '192.168.1.2',
  int priority = 2,
}) => CaptureAdvertisement(
  id: 'device-identity-$number',
  name: 'Phone $number',
  model: 'Device $number',
  host: host,
  port: 40000 + number,
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
    await first.configure(first.receivers.first, audio: false);
    await first.stop();
    final next = hub();
    await next.start();
    addTearDown(next.stop);
    next.observe(ad(2));
    next.observe(ad(1));
    await settle(next);
    expect(next.receivers.first.advertisement.id, ad(1).id);
    expect(next.receivers.first.audio, false);
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
