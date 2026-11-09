import 'dart:ffi';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'live_capture_service.dart';
import 'capture_audio_settings.dart';

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
  static const _media = MethodChannel('FlutterWebRTC.Method');
  static const _androidAudio = MethodChannel('localist/capture');
  bool get _windows => Platform.isWindows;
  MethodChannel get _audioChannel => _windows ? _media : _androidAudio;
  String _audioMethod(String windows, String android) =>
      _windows ? windows : android;
  CaptureAudioSettings _audioSettings = CaptureAudioSettings(
    outputMode: Platform.isWindows ? 'mic' : 'playback',
  );
  CaptureAudioSettings get audioSettings => _audioSettings;
  set audioSettings(CaptureAudioSettings value) {
    value.validate();
    if (jsonEncode(value.toMap()) == jsonEncode(_audioSettings.toMap())) return;
    _audioSettings = value;
    _microphoneFailure = null;
    _microphoneRetry = DateTime(1970);
  }

  Map<String, dynamic> audioDiagnostics = {};
  Future<void> pushPcm(Uint8List data) async {
    if (_microphoneTrack == null || !validCapturePcm(data)) return;
    await _audioChannel.invokeMethod(
      _audioMethod('localistVirtualMicrophonePcm', 'audioOutputPcm'),
      {'slot': slot, 'data': data},
    );
  }

  _SetSlot? _setSlot;
  bool cameraEnabled = false;
  String? _microphoneTrack;
  String microphoneName = '';
  String _microphoneEndpoint = '';
  String get microphoneEndpoint => _microphoneEndpoint;
  set microphoneEndpoint(String value) {
    if (value == _microphoneEndpoint) return;
    _microphoneEndpoint = value;
    _microphoneFailure = null;
    _microphoneRetry = DateTime(1970);
  }

  DateTime _microphoneRetry = DateTime(1970);
  DateTime _microphoneCheck = DateTime(1970);
  String? _microphoneFailure;
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
    if (!installed) {
      stopCamera();
      return;
    }
    if ((await cameraStatus())['installed'] != true) {
      throw StateError(
        'این وبکم با Setup نصب نشده است؛ برای افزایش تعداد وبکم‌ها Setup را اجرا کنید. / '
        'This camera is not installed. Run Setup to change the camera count.',
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

  Future<Map<String, dynamic>> microphoneStatus() async =>
      Map<String, dynamic>.from(
        await (_windows ? _channel : _androidAudio)
                .invokeMapMethod<String, dynamic>(
                  _windows
                      ? 'getWindowsVirtualMicrophoneStatus'
                      : 'audioOutputDevices',
                ) ??
            {},
      );

  Future<void> setMicrophoneSource(MediaStream? stream) async {
    final track = stream?.getAudioTracks().firstOrNull;
    final identity = track == null
        ? null
        : '${stream!.ownerTag}/${track.id}/$_microphoneEndpoint/${jsonEncode(audioSettings.toMap())}';
    if (identity == _microphoneTrack) {
      if (identity == null || DateTime.now().isBefore(_microphoneCheck)) return;
      _microphoneCheck = DateTime.now().add(const Duration(seconds: 2));
      final state = await _audioChannel.invokeMapMethod<String, dynamic>(
        _audioMethod('localistVirtualMicrophoneStatus', 'audioOutputStatus'),
        {'slot': slot},
      );
      microphoneName = state?['microphone'] as String? ?? microphoneName;
      audioDiagnostics = state ?? {};
      if (state?['error'] == 0) return;
      // Reopen a removed/restarted driver handle while retaining the RTC session.
      _microphoneTrack = null;
    }
    if (identity == null) {
      await stopMicrophone();
      return;
    }
    if (_microphoneFailure != null &&
        DateTime.now().isBefore(_microphoneRetry)) {
      throw StateError(_microphoneFailure!);
    }
    try {
      final bound = await _audioChannel.invokeMethod<bool>(
        _audioMethod('localistVirtualMicrophone', 'audioOutputBind'),
        {
          'slot': slot,
          'ownerTag': stream!.ownerTag,
          'trackId': track!.id,
          ...audioSettings.nativeMap,
          if ((audioSettings.outputMode == 'playback'
                  ? audioSettings.outputDevice
                  : _microphoneEndpoint)
              .isNotEmpty)
            'endpointId': audioSettings.outputMode == 'playback'
                ? audioSettings.outputDevice
                : _microphoneEndpoint,
        },
      );
      if (bound != true) throw StateError('Native microphone binding failed.');
      _microphoneTrack = identity;
      _microphoneCheck = DateTime.now().add(const Duration(seconds: 2));
      _microphoneFailure = null;
      final state = await _audioChannel.invokeMapMethod<String, dynamic>(
        _audioMethod('localistVirtualMicrophoneStatus', 'audioOutputStatus'),
        {'slot': slot},
      );
      microphoneName = state?['microphone'] as String? ?? '';
      audioDiagnostics = state ?? {};
    } catch (error) {
      _microphoneTrack = null;
      _microphoneRetry = DateTime.now().add(const Duration(seconds: 5));
      _microphoneFailure =
          'کابل مستقل خالی در دسترس نیست؛ Setup را برای نصب کابل‌های بیشتر اجرا کنید یا صدای یک گیرنده را خاموش کنید. / $error';
      rethrow;
    }
  }

  Future<void> stopMicrophone() async {
    final hadTrack = _microphoneTrack != null;
    _microphoneTrack = null;
    microphoneName = '';
    if (hadTrack) {
      await _audioChannel.invokeMethod<bool>(
        _audioMethod('localistVirtualMicrophone', 'audioOutputBind'),
        {'slot': slot, 'trackId': ''},
      );
    }
  }

  Future<void> stop() async {
    stopCamera();
    await stopMicrophone();
  }
}
