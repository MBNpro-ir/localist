// Hidden hardware acceptance target, used only with LOCALIST_CAPTURE_QA_RUNNER.
// Uses real LAN discovery and a consenting phone already sharing its microphone.
// Saves counters/diagnostics only; no microphone recording or system settings.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:localist/services/capture_hub_service.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  runApp(const MaterialApp(home: SizedBox.shrink()));
  final hub = CaptureHubService(windows: true);
  final result = <String, dynamic>{'ok': false};
  try {
    await hub.start();
    final deadline = DateTime.now().add(const Duration(seconds: 50));
    while (DateTime.now().isBefore(deadline)) {
      for (final receiver in hub.receivers) {
        final state = await const MethodChannel('FlutterWebRTC.Method')
            .invokeMapMethod<String, dynamic>(
              'localistVirtualMicrophoneStatus',
              {'slot': receiver.slot},
            );
        final reports = await receiver.capture.connectionDiagnostics();
        result.addAll({
          'status': receiver.capture.status,
          'host': receiver.advertisement.host,
          'priority': receiver.advertisement.priority,
          'advertisedCamera': receiver.advertisement.camera,
          'advertisedMicrophone': receiver.advertisement.microphone,
          'videoTracks': receiver.capture.remoteStream?.getVideoTracks().length,
          'audioTracks': receiver.capture.remoteStream?.getAudioTracks().length,
          'microphone': state,
          'outputError': receiver.outputError,
          'pcmPackets': receiver.capture.pcmPacketsReceived,
          'audioSettings': receiver.capture.captureControlState,
          'inbound': reports,
        });
        if (receiver.capture.status == 'connected' &&
            receiver.advertisement.priority == 0 &&
            result['videoTracks'] == 0 &&
            result['audioTracks'] == 1 &&
            state?['error'] == 0 &&
            (state?['frames'] as int? ?? 0) > 96000 &&
            (state?['silentPlayoutEndpoint'] as String? ?? '').isNotEmpty &&
            reports.any(
              (r) =>
                  r['kind'] == 'audio' && (r['bytesReceived'] as int? ?? 0) > 0,
            )) {
          result['ok'] = true;
          if (args.length > 1 && args[1] == 'controls') {
            await receiver.capture.requestCaptureControl({
              'noise': false,
              'echo': false,
              'gain': false,
              'audioGainDb': -30.0,
              'audioBitrate': 256,
              'audioUncompressed': true,
            });
            final until = DateTime.now().add(const Duration(seconds: 20));
            while (DateTime.now().isBefore(until)) {
              final controls = receiver.capture.captureControlState;
              if (controls['audioUncompressed'] == true &&
                  controls['audioGainDb'] == -30.0 &&
                  receiver.capture.pcmPacketsReceived > 20) {
                break;
              }
              await Future<void>.delayed(const Duration(milliseconds: 200));
            }
            result['remoteControls'] = receiver.capture.captureControlState;
            result['pcmPackets'] = receiver.capture.pcmPacketsReceived;
            result['ok'] =
                receiver.capture.captureControlState['audioGainDb'] == -30.0 &&
                receiver.capture.pcmPacketsReceived > 20;
            await receiver.capture.requestCaptureControl({
              'noise': true,
              'echo': true,
              'gain': true,
              'audioGainDb': 0.0,
              'audioUncompressed': false,
              'audioBitrate': 96,
            });
          }
          break;
        }
      }
      if (result['ok'] == true) break;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  } catch (error) {
    result['error'] = '$error';
  } finally {
    await hub.stop();
    await File(
      '${args[0]}/physical-usb-result.json',
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(result));
  }
  exit(result['ok'] == true ? 0 : 1);
}
