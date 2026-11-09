// Real Windows acceptance host. Only run in LOCALIST_CAPTURE_QA_RUNNER builds.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:localist/services/capture_hub_service.dart';
import 'package:localist/services/capture_discovery_service.dart';
import 'package:localist/services/windows_virtual_devices_service.dart';
import 'package:localist/services/log_service.dart';

class _Discovery extends CaptureDiscoveryService {
  bool active = false;
  @override
  bool get running => active;
  @override
  Future<void> start() async {
    active = true;
  }

  @override
  Future<void> stop() async {
    active = false;
  }

  @override
  Future<void> announce({bool query = false}) async {}
}

class _Output extends WindowsVirtualDevicesService {
  _Output(int slot) : super(slot: slot);
  // The test harness registers isolated per-user QA filters, never production.
  @override
  Future<void> setCameraInstalled(bool installed) async {}
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  runApp(const MaterialApp(home: SizedBox.shrink()));
  final root = Directory(args[0]);
  final session =
      jsonDecode(await File('${root.path}/sender-session.json').readAsString())
          as Map;
  final hub = CaptureHubService(
    discovery: _Discovery(),
    outputFactory: _Output.new,
    windows: true,
  );
  Timer? heartbeat;
  var ok = false;
  try {
    await hub.start();
    void discover() {
      for (var i = 0; i < 4; i++) {
        final source = session['senders'] == null
            ? session
            : session['senders'][i] as Map;
        hub.observe(
          CaptureAdvertisement(
            id: 'windows-real-android-qa-$i',
            name: 'Android QA $i',
            model: 'Android hardware camera',
            host: '127.0.0.1',
            port: source['port'] as int,
            key: source['key'] as String,
            camera: true,
            microphone: true,
          ),
        );
      }
    }

    discover();
    heartbeat = Timer.periodic(const Duration(seconds: 2), (_) => discover());
    for (var cycle = 0; cycle < 2; cycle++) {
      ok = false;
      final deadline = DateTime.now().add(const Duration(seconds: 65));
      while (DateTime.now().isBefore(deadline)) {
        final receivers = hub.receivers;
        if (receivers.length == 4 &&
            receivers.every(
              (r) =>
                  r.capture.status == 'connected' &&
                  r.renderer.videoWidth > 0 &&
                  r.renderer.videoHeight > 0 &&
                  r.output.cameraEnabled,
            )) {
          ok = true;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (!ok) break;
      if (session['requireMicrophones'] == true) {
        ok = false;
        final deadline = DateTime.now().add(const Duration(seconds: 25));
        while (DateTime.now().isBefore(deadline)) {
          final states = await Future.wait(
            hub.receivers.map(
              (r) => const MethodChannel('FlutterWebRTC.Method')
                  .invokeMapMethod<String, dynamic>(
                    'localistVirtualMicrophoneStatus',
                    {'slot': r.slot},
                  ),
            ),
          );
          if (states.every(
            (s) => (s?['frames'] as int? ?? 0) >= 48000 && s?['error'] == 0,
          )) {
            ok = true;
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        if (!ok) break;
      }
      if (cycle == 0) {
        await Future.wait(
          hub.receivers.map((r) => hub.configure(r, enabled: false)),
        );
        await Future.wait(
          hub.receivers.map((r) => hub.configure(r, enabled: true)),
        );
      }
    }
    final result = {
      'ok': ok,
      'receivers': [
        for (final r in hub.receivers)
          {
            'slot': r.slot,
            'status': r.capture.status,
            'width': r.renderer.videoWidth,
            'height': r.renderer.videoHeight,
            'video': r.capture.remoteStream?.getVideoTracks().length,
            'audio': r.capture.remoteStream?.getAudioTracks().length,
            'output': r.output.cameraEnabled,
            'error': r.error,
            'mediaError': r.capture.error,
            'outputError': r.outputError,
            'microphone': await const MethodChannel('FlutterWebRTC.Method')
                .invokeMapMethod<String, dynamic>(
                  'localistVirtualMicrophoneStatus',
                  {'slot': r.slot},
                ),
            'inbound': await r.capture.connectionDiagnostics(),
          },
      ],
    };
    await File(
      '${root.path}/windows-receive-ready.json',
    ).writeAsString(jsonEncode(result));
    if (ok) {
      final stopAt = DateTime.now().add(const Duration(seconds: 90));
      while (!File('${root.path}/receiver-consumed').existsSync() &&
          DateTime.now().isBefore(stopAt)) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    }
  } catch (e, stack) {
    await File('${root.path}/windows-receive-ready.json').writeAsString(
      jsonEncode({'ok': false, 'error': '$e', 'stack': '$stack'}),
    );
  } finally {
    heartbeat?.cancel();
    await hub.stop();
    await File(
      '${root.path}/windows-receiver.log',
    ).writeAsString(LogService.instance.dump());
  }
  exit(ok ? 0 : 1);
}
