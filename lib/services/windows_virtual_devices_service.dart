import 'dart:ffi';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
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
  static const _media = MethodChannel('FlutterWebRTC.Method');
  _SetSlot? _setSlot;
  bool cameraEnabled = false;
  String? _microphoneTrack;
  String get microphoneName => 'Localist Microphone ${slot + 1}';
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

  Future<Map<String, dynamic>> microphoneStatus() async =>
      Map<String, dynamic>.from(
        await _channel.invokeMapMethod<String, dynamic>(
              'getWindowsVirtualMicrophoneStatus',
            ) ??
            {},
      );

  Future<void> setMicrophoneSource(MediaStream? stream) async {
    final track = stream?.getAudioTracks().firstOrNull;
    final identity = track == null ? null : '${stream!.ownerTag}/${track.id}';
    if (identity == _microphoneTrack) {
      if (identity == null || DateTime.now().isBefore(_microphoneCheck)) return;
      _microphoneCheck = DateTime.now().add(const Duration(seconds: 2));
      final state = await _media.invokeMapMethod<String, dynamic>(
        'localistVirtualMicrophoneStatus',
        {'slot': slot},
      );
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
      final bound = await _media.invokeMethod<bool>(
        'localistVirtualMicrophone',
        {'slot': slot, 'ownerTag': stream!.ownerTag, 'trackId': track!.id},
      );
      if (bound != true) throw StateError('Native microphone binding failed.');
      _microphoneTrack = identity;
      _microphoneCheck = DateTime.now().add(const Duration(seconds: 2));
      _microphoneFailure = null;
    } catch (error) {
      _microphoneTrack = null;
      _microphoneRetry = DateTime.now().add(const Duration(seconds: 5));
      _microphoneFailure =
          'میکروفون اختصاصی Localist در دسترس نیست؛ درایور امضاشده را با Setup نصب یا ترمیم کنید. / $error';
      rethrow;
    }
  }

  Future<void> stopMicrophone() async {
    final hadTrack = _microphoneTrack != null;
    _microphoneTrack = null;
    if (hadTrack) {
      await _media.invokeMethod<bool>('localistVirtualMicrophone', {
        'slot': slot,
        'trackId': '',
      });
    }
  }

  Future<void> stop() async {
    stopCamera();
    await stopMicrophone();
  }
}
