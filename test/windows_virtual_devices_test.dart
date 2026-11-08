import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localist/services/windows_virtual_devices_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const native = MethodChannel('com.prs.localist.vpn');
  const webrtc = MethodChannel('FlutterWebRTC.Method');
  final selected = <String>[];
  setUp(() {
    selected.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(webrtc, (call) async {
          if (call.method == 'getSources') {
            return {
              'sources': [
                {
                  'deviceId': 'speaker',
                  'label': 'Default speakers',
                  'kind': 'audiooutput',
                },
                {
                  'deviceId': 'cable',
                  'label': 'CABLE Input',
                  'kind': 'audiooutput',
                },
              ],
            };
          }
          if (call.method == 'selectAudioOutput') {
            selected.add((call.arguments as Map)['deviceId'] as String);
          }
          return null;
        });
  });
  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(native, null);
    messenger.setMockMethodCallHandler(webrtc, null);
  });

  test('microphone routing restores playback after the stream stops', () async {
    final service = WindowsVirtualDevicesService();
    await service.routeMicrophone('cable');
    expect(service.microphoneOutput, 'cable');
    await service.stop();
    expect(selected, ['cable', 'speaker']);
    expect(service.microphoneOutput, isNull);
  });

  test(
    'a removed audio endpoint cannot silently route to another device',
    () async {
      final service = WindowsVirtualDevicesService();
      await expectLater(service.routeMicrophone('removed'), throwsStateError);
      expect(selected, isEmpty);
      expect(service.microphoneOutput, isNull);
    },
  );

  test(
    'camera registration failure is visible instead of reporting success',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(native, (_) async => false);
      await expectLater(
        WindowsVirtualDevicesService().setCameraInstalled(true),
        throwsStateError,
      );
    },
  );
}
