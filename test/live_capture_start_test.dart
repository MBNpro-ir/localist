import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:localist/screens/live_capture_page.dart';
import 'package:localist/services/live_capture_service.dart';

class _Capture extends LiveCaptureService {
  bool started = false;
  @override
  bool get broadcasting => started;
  @override
  Future<void> start(LiveCaptureOptions value, {int port = 0}) async {
    options = value;
    started = true;
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    started = false;
  }
}

class _Preview extends RTCVideoRenderer {
  bool initialized = false;
  @override
  Future<void> initialize() async {
    initialized = true;
  }

  @override
  set srcObject(MediaStream? stream) {}
  @override
  Future<void> setSrcObject({MediaStream? stream, String? trackId}) async {}
  @override
  set muted(bool value) =>
      throw StateError('Preview must never mute the capture microphone');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Start reaches capture without muting a null preview or the local microphone',
    (tester) async {
      const channel = MethodChannel('FlutterWebRTC.Method');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('localist/audioDevices'),
            (_) async => null,
          );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('FlutterWebRTC.Event'),
            (_) async => null,
          );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) async => call.method == 'getSources'
                ? {
                    'sources': [
                      {
                        'deviceId': 'camera',
                        'label': 'Back camera',
                        'kind': 'videoinput',
                      },
                      {
                        'deviceId': 'microphone',
                        'label': 'Built in mic',
                        'kind': 'audioinput',
                      },
                    ],
                  }
                : null,
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.prs.localist.vpn'),
            (call) async => call.method == 'getCaptureDeviceCapabilities'
                ? {
                    'modes': [
                      {'width': 640, 'height': 480, 'minFps': 1, 'maxFps': 30},
                      {'width': 1280, 'height': 720, 'minFps': 1, 'maxFps': 60},
                      {
                        'width': 1920,
                        'height': 1080,
                        'minFps': 1,
                        'maxFps': 60,
                      },
                      {
                        'width': 3840,
                        'height': 2160,
                        'minFps': 1,
                        'maxFps': 30,
                      },
                    ],
                    'minBitrateKbps': 64,
                    'maxBitrateKbps': 80000,
                    'codecs': 'avc',
                  }
                : null,
          );
      final service = _Capture();
      final preview = _Preview();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LiveCapturePage(service: service, renderer: preview),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Start live capture'));
      await tester.pumpAndSettle();
      for (
        var i = 0;
        i < 30 &&
            tester
                    .widget<FilledButton>(
                      find.widgetWithText(FilledButton, 'Start live capture'),
                    )
                    .onPressed ==
                null;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Start live capture'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
      expect(preview.initialized, true);
      expect(service.started, true);
      expect(tester.takeException(), isNull);
    },
  );
}
