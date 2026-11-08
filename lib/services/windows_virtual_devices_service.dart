import 'dart:ffi';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:path_provider/path_provider.dart';

typedef _SetTextureNative = Int32 Function(Int64 texture, Int32 fps);
typedef _SetTexture = int Function(int texture, int fps);

/// Native camera output receives decoded I420 frames inside the WebRTC plugin.
/// No per-frame Dart messages, PNG encoding or OBS process is involved.
class WindowsVirtualDevicesService {
  static const _channel = MethodChannel('com.prs.localist.vpn');
  static const cableUrl =
      'https://download.vb-audio.com/Download_CABLE/VBCABLE_Driver_Pack46.zip';
  static const cableDigest =
      'bc44e8974191a5a2427d6c979e2dab08dbb09925f3f435dfa2f0ba3e45b6eb90';
  _SetTexture? _setTexture;
  bool cameraEnabled = false;
  String? microphoneOutput;
  String? _restoreOutput;

  Future<Map<String, dynamic>> cameraStatus() async =>
      Map<String, dynamic>.from(
        await _channel.invokeMapMethod<String, dynamic>(
              'getWindowsVirtualCameraStatus',
            ) ??
            {},
      );

  Future<void> setCameraInstalled(bool installed) async {
    if (!installed) stopCamera();
    if (await _channel.invokeMethod<bool>('setWindowsVirtualCameraInstalled', {
          'enabled': installed,
        }) !=
        true) {
      throw StateError(
        'ثبت وبکم مجازی انجام نشد. Localist را با دسترسی ادمین اجرا کنید. / '
        'Virtual camera registration failed. Run Localist as administrator.',
      );
    }
  }

  void startCamera(int texture, {int fps = 30}) {
    _setTexture ??= DynamicLibrary.open('flutter_webrtc_plugin.dll')
        .lookupFunction<_SetTextureNative, _SetTexture>(
          'LocalistVirtualCameraSetTexture',
        );
    if (_setTexture!(texture, fps) != 1) {
      throw StateError('Unable to start virtual camera output.');
    }
    cameraEnabled = true;
  }

  void stopCamera() {
    _setTexture?.call(-1, 30);
    cameraEnabled = false;
  }

  Future<List<MediaDeviceInfo>> audioOutputs() => Helper.audiooutputs;

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
