import 'dart:ffi';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:path_provider/path_provider.dart';
import 'live_capture_service.dart';

typedef _SetSlotNative = Int32 Function(Int32 slot, Int64 texture, Int32 fps);
typedef _SetSlot = int Function(int slot, int texture, int fps);

/// Native camera output receives decoded I420 frames inside the WebRTC plugin.
/// No per-frame Dart messages, PNG encoding or OBS process is involved.
class WindowsVirtualDevicesService {
  WindowsVirtualDevicesService({this.slot = 0}) {
    RangeError.checkValueInInterval(slot, 0, 3, 'slot');
  }
  final int slot;
  static const _channel = MethodChannel('com.prs.localist.vpn');
  static const cableUrl =
      'https://download.vb-audio.com/Download_CABLE/VBCABLE_Driver_Pack46.zip';
  static const cableDigest =
      'bc44e8974191a5a2427d6c979e2dab08dbb09925f3f435dfa2f0ba3e45b6eb90';
  _SetSlot? _setSlot;
  bool cameraEnabled = false;
  String? microphoneOutput;
  String? _restoreOutput;
  Timer? _controlsTimer;
  LiveCaptureService? _capture;
  bool _controlsBusy = false;
  String _controlError = '';
  bool persian = false;

  void bindCaptureControls(LiveCaptureService capture) => _capture = capture;

  Future<void> _syncControls() async {
    final capture = _capture;
    if (_controlsBusy || capture == null) return;
    _controlsBusy = true;
    try {
      final state = Map<String, dynamic>.from(capture.captureControlState);
      state['enabled'] =
          state['enabled'] == true && cameraEnabled && capture.active;
      state['persian'] = persian;
      state['slot'] = slot;
      state['message'] = _controlError.isEmpty
          ? state['message']
          : _controlError;
      final command = await _channel.invokeMethod<String>(
        'publishCaptureControls',
        state,
      );
      if (command != null && command.isNotEmpty && state['enabled'] == true) {
        await capture.requestCaptureControl(
          Map<String, dynamic>.from(jsonDecode(command) as Map),
        );
        _controlError = '';
      }
    } catch (error) {
      _controlError = '$error';
    } finally {
      _controlsBusy = false;
    }
  }

  Future<Map<String, dynamic>> cameraStatus() async =>
      Map<String, dynamic>.from(
        await _channel.invokeMapMethod<String, dynamic>(
              'getWindowsVirtualCameraStatus',
              {'slot': slot},
            ) ??
            {},
      );

  Future<void> setCameraInstalled(bool installed) async {
    if (!installed) stopCamera();
    if (await _channel.invokeMethod<bool>('setWindowsVirtualCameraInstalled', {
          'enabled': installed,
          'slot': slot,
        }) !=
        true) {
      throw StateError(
        'ثبت وبکم مجازی انجام نشد. Localist را با دسترسی ادمین اجرا کنید. / '
        'Virtual camera registration failed. Run Localist as administrator.',
      );
    }
  }

  void startCamera(int texture, {int fps = 30}) {
    _setSlot ??= DynamicLibrary.open(
      'flutter_webrtc_plugin.dll',
    ).lookupFunction<_SetSlotNative, _SetSlot>('LocalistVirtualCameraSetSlot');
    if (_setSlot!(slot, texture, fps) != 1) {
      throw StateError('Unable to start virtual camera output.');
    }
    cameraEnabled = true;
    _controlsTimer?.cancel();
    _controlsTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => unawaited(_syncControls()),
    );
    unawaited(_syncControls());
  }

  void stopCamera() {
    _setSlot?.call(slot, -1, 30);
    cameraEnabled = false;
    _controlsTimer?.cancel();
    _controlsTimer = null;
    unawaited(_syncControls());
  }

  Future<List<MediaDeviceInfo>> audioOutputs() async {
    await LiveCaptureService.initializeMedia();
    return Helper.audiooutputs;
  }

  Future<void> routeMicrophone(String deviceId) async {
    final devices = await audioOutputs();
    if (!devices.any((device) => device.deviceId == deviceId)) {
      throw StateError('Audio device is no longer available.');
    }
    _restoreOutput ??= devices.firstOrNull?.deviceId;
    await Helper.selectAudioOutput(deviceId);
    microphoneOutput = deviceId;
  }

  Future<void> stopMicrophone() async {
    final previous = _restoreOutput;
    microphoneOutput = null;
    _restoreOutput = null;
    if (previous != null) await Helper.selectAudioOutput(previous);
  }

  Future<void> stop() async {
    stopCamera();
    await stopMicrophone();
  }

  /// Fetch from the vendor only after an explicit user action. The package is
  /// not redistributed with Localist; its original installer and license remain.
  Future<void> downloadMicrophoneInstaller() async {
    final root = Directory(
      '${(await getApplicationSupportDirectory()).path}/drivers/vb-cable46',
    );
    await root.create(recursive: true);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final response = await (await client.getUrl(Uri.parse(cableUrl))).close();
      if (response.statusCode != 200) {
        throw HttpException('Driver download failed: ${response.statusCode}');
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        bytes.addAll(chunk);
        if (bytes.length > 4 * 1024 * 1024) {
          throw const FormatException('Driver package too large');
        }
      }
      if (sha256.convert(bytes).toString() != cableDigest) {
        throw const FormatException('Driver package checksum mismatch');
      }
      final archive = ZipDecoder().decodeBytes(
        Uint8List.fromList(bytes),
        verify: true,
      );
      for (final entry in archive) {
        if (!entry.isFile) continue;
        if (entry.name.contains(RegExp(r'[/\\:]')) ||
            entry.name == '..' ||
            entry.name == '.') {
          throw const FormatException('Unexpected driver archive path');
        }
        await File(
          '${root.path}/${entry.name}',
        ).writeAsBytes(entry.content as List<int>, flush: true);
      }
      if (await _channel.invokeMethod<bool>(
            'launchWindowsMicrophoneInstaller',
            {'path': '${root.path}/VBCABLE_Setup_x64.exe'},
          ) !=
          true) {
        throw StateError('Signed microphone installer could not be opened.');
      }
    } finally {
      client.close(force: true);
    }
  }
}
