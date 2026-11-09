import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:localist/services/live_capture_service.dart';
import 'package:localist/services/log_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final capture = LiveCaptureService();
  final preview = RTCVideoRenderer();
  await LiveCaptureService.initializeMedia();
  await preview.initialize();
  capture.addListener(() {
    if (preview.srcObject != capture.localStream) {
      preview.srcObject = capture.localStream;
    }
  });
  runApp(MaterialApp(home: Scaffold(body: RTCVideoView(preview))));
  const root = '/data/user/0/com.prs.localist/cache';
  final ready = File('$root/capture-sender-session.json');
  final stop = File('$root/capture-sender-stop');
  if (stop.existsSync()) stop.deleteSync();
  try {
    await capture.start(
      const LiveCaptureOptions(
        width: 640,
        height: 480,
        fps: 15,
        bitrateKbps: 1000,
        orientation: 'landscape',
      ),
      port: 33333,
    );
    await ready.writeAsString(
      jsonEncode({'key': capture.signalingKey, 'port': 45108}),
    );
    final end = DateTime.now().add(const Duration(minutes: 5));
    while (!stop.existsSync() && DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  } finally {
    await capture.stop();
    await preview.dispose();
    await File(
      '$root/capture-sender.log',
    ).writeAsString(LogService.instance.dump());
  }
  exit(0);
}
