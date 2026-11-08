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
            channel,
            (call) async =>
                call.method == 'getSources' ? {'sources': []} : null,
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
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
      await tester.scrollUntilVisible(find.text('Start live capture'), 300);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start live capture'));
      await tester.pumpAndSettle();
      expect(preview.initialized, true);
      expect(service.started, true);
      expect(tester.takeException(), isNull);
    },
  );
}
