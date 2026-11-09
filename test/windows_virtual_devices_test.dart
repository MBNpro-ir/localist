import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:localist/services/windows_virtual_devices_service.dart';

class _Track extends Fake implements MediaStreamTrack {
  _Track(this.id);
  @override
  final String id;
}

class _Stream extends Fake implements MediaStream {
  _Stream(this.ownerTag, String id) : track = _Track(id);
  @override
  final String ownerTag;
  final _Track track;
  @override
  List<MediaStreamTrack> getAudioTracks() => [track];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const native = MethodChannel('com.prs.localist.vpn');
  const webrtc = MethodChannel('FlutterWebRTC.Method');
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(webrtc, (call) async {
          calls.add(call);
          if (call.method == 'localistVirtualMicrophoneStatus') {
            return {'error': 0, 'microphone': 'CABLE Output'};
          }
          return true;
        });
  });
  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(native, null);
    messenger.setMockMethodCallHandler(webrtc, null);
  });

  test(
    'four received streams bind independently without changing system playback',
    () async {
      final services = List.generate(
        4,
        (i) => WindowsVirtualDevicesService(slot: i),
      );
      for (var i = 0; i < 4; i++) {
        final stream = _Stream('peer-$i', 'audio');
        await services[i].setMicrophoneSource(stream);
        await services[i].setMicrophoneSource(stream);
      }
      final bindings = calls
          .where((c) => c.method == 'localistVirtualMicrophone')
          .toList();
      expect(bindings.length, 4);
      for (var i = 0; i < 4; i++) {
        expect(bindings[i].arguments, containsPair('slot', i));
        expect(bindings[i].arguments, containsPair('ownerTag', 'peer-$i'));
        expect(bindings[i].arguments, containsPair('trackId', 'audio'));
        expect(bindings[i].arguments, containsPair('audioOutputMode', 'mic'));
      }
      await services[1].stopMicrophone();
      expect(calls.last.arguments, {'slot': 1, 'trackId': ''});
      final before = calls.length;
      await services[1].stopMicrophone();
      expect(calls.length, before);
      expect(calls.any((c) => c.method == 'selectAudioOutput'), isFalse);
    },
  );

  test(
    'a replacement peer with the same track ID rebinds using its owner',
    () async {
      final service = WindowsVirtualDevicesService(slot: 3);
      await service.setMicrophoneSource(_Stream('old-peer', 'audio'));
      await service.setMicrophoneSource(_Stream('new-peer', 'audio'));
      final bindings = calls
          .where((c) => c.method == 'localistVirtualMicrophone')
          .toList();
      expect(bindings.length, 2);
      expect((bindings.last.arguments as Map)['ownerTag'], 'new-peer');
      await service.setMicrophoneSource(null);
      expect(calls.last.arguments, {'slot': 3, 'trackId': ''});
    },
  );

  test(
    'missing driver is an output error and repeated retries are throttled',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(webrtc, (call) async {
            calls.add(call);
            throw PlatformException(code: 'LOCALIST_MICROPHONE_UNAVAILABLE');
          });
      final service = WindowsVirtualDevicesService();
      final stream = _Stream('peer', 'audio');
      await expectLater(
        service.setMicrophoneSource(stream),
        throwsA(isA<PlatformException>()),
      );
      await expectLater(service.setMicrophoneSource(stream), throwsStateError);
      expect(calls.length, 1);
      await service.stopMicrophone();
      expect(calls.length, 1);
    },
  );

  test('native rejection cannot be recorded as a successful binding', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(webrtc, (_) async => false);
    await expectLater(
      WindowsVirtualDevicesService().setMicrophoneSource(
        _Stream('peer', 'audio'),
      ),
      throwsStateError,
    );
  });

  test(
    'an explicit independent cable is rebound when the user changes it',
    () async {
      final service = WindowsVirtualDevicesService();
      final stream = _Stream('peer', 'audio');
      service.microphoneEndpoint = 'cable-a';
      await service.setMicrophoneSource(stream);
      service.microphoneEndpoint = 'cable-b';
      await service.setMicrophoneSource(stream);
      final bindings = calls
          .where((c) => c.method == 'localistVirtualMicrophone')
          .toList();
      expect(bindings.map((c) => (c.arguments as Map)['endpointId']), [
        'cable-a',
        'cable-b',
      ]);
      expect(service.microphoneName, 'CABLE Output');
      await service.stopMicrophone();
      expect(service.microphoneName, isEmpty);
    },
  );

  test(
    'a broken driver handle rebinds without reconnecting the RTC peer',
    () async {
      var error = 6;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(webrtc, (call) async {
            calls.add(call);
            if (call.method == 'localistVirtualMicrophoneStatus') {
              return {'error': error};
            }
            return true;
          });
      final service = WindowsVirtualDevicesService();
      final stream = _Stream('same-peer', 'same-track');
      await service.setMicrophoneSource(stream);
      await Future<void>.delayed(const Duration(milliseconds: 2050));
      await service.setMicrophoneSource(stream);
      expect(calls.map((c) => c.method), [
        'localistVirtualMicrophone',
        'localistVirtualMicrophoneStatus',
        'localistVirtualMicrophoneStatus',
        'localistVirtualMicrophone',
        'localistVirtualMicrophoneStatus',
      ]);
      error = 0;
      await Future<void>.delayed(const Duration(milliseconds: 2050));
      await service.setMicrophoneSource(stream);
      expect(calls.length, 6);
      expect(calls.last.method, 'localistVirtualMicrophoneStatus');
      await service.stopMicrophone();
    },
  );

  test('camera registration failure is visible', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(native, (_) async => {'installed': false});
    await expectLater(
      WindowsVirtualDevicesService().setCameraInstalled(true),
      throwsStateError,
    );
  });
}
