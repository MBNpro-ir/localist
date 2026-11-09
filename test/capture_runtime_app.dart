// Compile-only Android acceptance entrypoint; intentionally not a *_test.dart.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:localist/services/live_capture_service.dart';
import 'package:localist/screens/live_capture_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final service = LiveCaptureService();
  final preview = RTCVideoRenderer();
  await LiveCaptureService.initializeMedia();
  await preview.initialize();
  service.addListener(() {
    if (preview.srcObject != service.localStream) {
      preview.srcObject = service.localStream;
    }
  });
  final failures = <String>[];
  final previousHandler = FlutterError.onError;
  FlutterError.onError = (details) {
    failures.add(details.exceptionAsString());
    previousHandler?.call(details);
  };
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            SizedBox(height: 180, child: RTCVideoView(preview)),
            Expanded(child: LiveCapturePage(service: service)),
          ],
        ),
      ),
    ),
  );
  await WidgetsBinding.instance.endOfFrame;
  final report = <String, dynamic>{};
  try {
    var cycles = 0;
    for (var i = 0; i < 8; i++) {
      await service.start(
        const LiveCaptureOptions(
          width: 640,
          height: 480,
          fps: 15,
          bitrateKbps: 1000,
        ),
      );
      if (!service.broadcasting ||
          service.localStream?.getVideoTracks().length != 1 ||
          service.localStream?.getAudioTracks().length != 1) {
        throw StateError('Missing camera/mic on cycle $i');
      }
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (preview.videoWidth == 0 && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (preview.videoWidth <= 0) throw StateError('Preview did not render');
      await service.setOrientation(i.isEven ? 'landscape' : 'auto');
      await service.switchCamera();
      await service.requestCaptureControl({
        'width': 640,
        'height': 480,
        'fps': 15,
        'noise': false,
      });
      await Future.wait([
        service.requestCaptureControl({'fps': 15}),
        service.requestCaptureControl({'fps': 15}).catchError((Object _) {}),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await service.stop();
      cycles++;
    }
    for (var i = 0; i < 5; i++) {
      await Future.wait([
        service.start(
          const LiveCaptureOptions(width: 640, height: 480, fps: 15),
        ),
        service.stop(),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (service.active) {
        throw StateError('Capture revived after cancellation');
      }
    }
    await Future<void>.delayed(const Duration(seconds: 6));
    if (service.active || service.busy) {
      throw StateError('Capture remained active/busy');
    }
    if (failures.isNotEmpty) throw StateError(failures.join('\n'));
    report.addAll({
      'ok': true,
      'cycles': cycles,
      'cancelledStarts': 5,
      'busy': service.busy,
      'active': service.active,
    });
  } catch (error, stack) {
    report.addAll({
      'ok': false,
      'error': '$error',
      'stack': '$stack',
      'flutterErrors': failures,
    });
  } finally {
    await service.stop();
    FlutterError.onError = previousHandler;
    final path = '${Directory.systemTemp.path}/capture-runtime-results.json';
    await File(path).writeAsString(jsonEncode(report));
    debugPrint('LOCALIST_COMPILED_CAPTURE_QA ${jsonEncode(report)}');
    await const MethodChannel(
      'com.prs.localist.vpn',
    ).invokeMethod('getDeviceDetails').catchError((Object _) => null);
  }
}
