import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/live_capture_service.dart';
import '../services/capture_capabilities.dart';
import '../services/capture_hub_service.dart';
import '../services/windows_virtual_devices_service.dart';
import '../services/feature_permission_service.dart';
import '../widgets/glass.dart';
import '../widgets/capture_receivers_panel.dart';
import '../widgets/capture_audio_controls.dart';
import '../widgets/capture_microphone_mode.dart';
import '../services/capture_audio_settings.dart';
import '../services/log_service.dart';
import '../l10n/capture_error_text.dart';
import '../widgets/capture_latency_chart.dart';

class LiveCapturePage extends StatefulWidget {
  const LiveCapturePage({
    super.key,
    this.service,
    this.renderer,
    this.hub,
    this.receiving,
    this.visible = true,
  });
  final bool? receiving;
  final bool visible;
  final LiveCaptureService? service;
  final CaptureHubService? hub;
  final RTCVideoRenderer? renderer;
  @override
  State<LiveCapturePage> createState() => _LiveCapturePageState();
}

class _LiveCapturePageState extends State<LiveCapturePage>
    with WidgetsBindingObserver {
  late final _hub =
      widget.hub ??
      (widget.service == null ? CaptureHubService.instance : null);
  late final _service = widget.service ?? _hub!.sender;
  late final _renderer = widget.renderer ?? RTCVideoRenderer();
  final _scroll = ScrollController();
  final _virtual = WindowsVirtualDevicesService();
  Map<String, dynamic> _audioStatus = {};
  List<int> _installedCameraSlots = [];
  bool _checkingOutputs = false;
  CaptureCapabilities _capabilities = const CaptureCapabilities();
  CaptureMode? _mode;
  SharedPreferences? _prefs;
  Future<void> _preferenceWrites = Future.value();
  String? _lastSaved;
  int _preferredWidth = 1280, _preferredHeight = 720;
  bool _loadingInputs = false, _senderLoaded = false, _outputsLoaded = false;
  bool _muted = false, _paused = false, _torch = false;
  double _savedZoom = 1;
  int? _previewTexture;
  String _panel = 'server', _audioSource = 'microphone';
  String _microphoneMode = 'default';
  List<String> _microphoneModes = const [];
  CaptureAudioSettings _audio = const CaptureAudioSettings();
  bool _loadingCapabilities = false;
  int _capabilityRequest = 0;
  bool get _windows => defaultTargetPlatform == TargetPlatform.windows;
  bool get _android => defaultTargetPlatform == TargetPlatform.android;
  bool get _hasPreviewVideo =>
      (_service.localStream ?? _service.remoteStream)
          ?.getVideoTracks()
          .isNotEmpty ==
      true;
  List<MediaDeviceInfo> _inputs = [];
  String? _cameraId, _microphoneId;
  bool _operationRunning = false, _previewSuspended = false;
  Future<void>? _previewBinding;
  bool _previewDirty = false, _previewDisposed = false;
  String? _previewTrack;
  double? _zoomDraft;
  bool _rendererReady = false, _camera = true, _microphone = true;
  void Function(dynamic)? _previousDeviceChange;
  StreamSubscription<dynamic>? _audioDeviceChanges;
  Future<void>? _inputRefresh;
  bool _inputRefreshAgain = false;
  bool _echo = false, _noise = false, _gain = false, _mirror = false;
  int _fps = 30, _bitrate = 0;
  String _notice = '';
  String t(String fa, String en) =>
      Localizations.localeOf(context).languageCode == 'fa' ? fa : en;
  @override
  void initState() {
    super.initState();
    _panel = widget.service != null || _android ? 'server' : 'player';
    WidgetsBinding.instance.addObserver(this);
    _service.addListener(_changed);
    _hub?.addListener(_hubChanged);
    if (_hub != null) unawaited(_hub.start());
    _loadVisiblePanel();
    if (_service.broadcasting) _changed();
  }

  bool get _showSender =>
      _service.broadcasting || !(widget.receiving ?? (_panel == 'player'));

  bool get _canScanInputs => mounted && widget.visible && _showSender;

  @override
  void didUpdateWidget(covariant LiveCapturePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.receiving != widget.receiving ||
        oldWidget.visible != widget.visible) {
      _loadVisiblePanel();
      if (!widget.visible) _changed();
    }
  }

  void _loadVisiblePanel() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.visible) return;
      if (_showSender && !_senderLoaded) {
        _senderLoaded = true;
        unawaited(_initializeSender());
      } else if (_showSender && !_service.active) {
        unawaited(_refreshInputs(silent: true));
      } else if (!_showSender && _windows && !_outputsLoaded) {
        _outputsLoaded = true;
        unawaited(_refreshVirtualDevices());
      }
      _changed();
    });
  }

  Future<void> _initializeSender() async {
    setState(() => _loadingInputs = true);
    try {
      await _restoreSettings();
    } catch (error) {
      LogService.instance.warning(
        'Capture settings read failed: ${error.runtimeType}',
      );
    }
    if (!mounted) return;
    _previousDeviceChange = navigator.mediaDevices.ondevicechange;
    navigator.mediaDevices.ondevicechange = (event) {
      _previousDeviceChange?.call(event);
      if (_canScanInputs) unawaited(_refreshInputs(silent: true));
    };
    if (_android) {
      final modes = await LiveCaptureService.androidMicrophoneModes()
          .catchError((Object error) {
            LogService.instance.warning(
              'Android microphone presets unavailable: ${error.runtimeType}',
            );
            return <String>[];
          });
      if (!mounted) return;
      setState(() {
        _microphoneModes = modes;
        if (!modes.contains(_microphoneMode)) _microphoneMode = 'default';
      });
      _audioDeviceChanges = const EventChannel('localist/audioDevices')
          .receiveBroadcastStream()
          .listen(
            (_) {
              if (_canScanInputs) unawaited(_refreshInputs(silent: true));
            },
            onError: (Object error) {
              LogService.instance.debug(
                'Capture input monitoring: ${error.runtimeType}',
              );
            },
          );
    }
    await _refreshInputs(silent: true);
    if (mounted) setState(() => _loadingInputs = false);
  }

  Future<void> _restoreSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    _prefs = prefs;
    try {
      final legacy =
          jsonDecode(prefs.getString('capture.senderAudio') ?? '{}') as Map;
      final stored =
          jsonDecode(prefs.getString('capture.senderSettings') ?? '{}') as Map;
      final settings = {...legacy, ...stored};
      if (_service.active) return;
      setState(() {
        _audio = CaptureAudioSettings.fromMap(settings);
        _echo = settings['echo'] == true;
        _noise = settings['noise'] == true;
        _gain = settings['gain'] == true;
        _camera = settings['camera'] != false;
        _microphone = settings['microphone'] != false;
        _cameraId = settings['cameraId'] as String?;
        _microphoneId = settings['microphoneId'] as String?;
        _audioSource = settings['audioSource'] == 'system'
            ? 'system'
            : 'microphone';
        _microphoneMode = settings['microphoneMode'] as String? ?? 'default';
        if (_audioSource == 'system') _camera = false;
        _preferredWidth = settings['width'] as int? ?? 1280;
        _preferredHeight = settings['height'] as int? ?? 720;
        _fps = (settings['fps'] as int? ?? 30).clamp(1, 240);
        _bitrate = (settings['bitrate'] as int? ?? 0).clamp(0, 1000000);
        _mirror = settings['mirror'] == true;
        _muted = settings['muted'] == true;
        _paused = settings['paused'] == true;
        _torch = settings['torch'] == true;
        _savedZoom = (settings['zoom'] as num? ?? 1).toDouble().clamp(1, 100);
      });
    } catch (_) {
      // Preferences from an older installation may be incomplete.
    }
  }

  void _saveSettings() {
    final prefs = _prefs;
    if (prefs == null) return;
    final encoded = jsonEncode({
      ..._audio.toMap(),
      'echo': _echo,
      'noise': _noise,
      'gain': _gain,
      'camera': _camera,
      'microphone': _microphone,
      'cameraId': _cameraId,
      'microphoneId': _microphoneId,
      'audioSource': _audioSource,
      'microphoneMode': _microphoneMode,
      'width': _mode?.width ?? _preferredWidth,
      'height': _mode?.height ?? _preferredHeight,
      'fps': _fps,
      'bitrate': _bitrate,
      'mirror': _mirror,
      'muted': _muted,
      'paused': _paused,
      'torch': _torch,
      'zoom': _savedZoom,
    });
    if (_lastSaved == encoded) return;
    _lastSaved = encoded;
    _preferenceWrites = _preferenceWrites
        .then((_) async {
          if (!await prefs.setString('capture.senderSettings', encoded)) {
            throw StateError('Capture preferences write failed');
          }
        })
        .catchError((Object error) {
          if (_lastSaved == encoded) _lastSaved = null;
          LogService.instance.warning(
            'Capture settings write failed: ${error.runtimeType}',
          );
        });
  }

  void _editSettings(VoidCallback update) {
    setState(update);
    _saveSettings();
  }

  void _draftAudio(CaptureAudioSettings value) =>
      _editSettings(() => _audio = value);

  void _draftEffects(Map<String, dynamic> values) => _editSettings(() {
    _echo = values['echo'] as bool? ?? _echo;
    _noise = values['noise'] as bool? ?? _noise;
    _gain = values['gain'] as bool? ?? _gain;
    if (values.containsKey('audioGainDb')) _audio = _audio.withValues(values);
  });

  void _changed() {
    if (_service.broadcasting) {
      final value = _service.options;
      _camera = value.camera;
      _microphone = value.microphone;
      _cameraId = value.cameraId;
      if (value.microphoneId != null) _microphoneId = value.microphoneId;
      _audioSource = value.audioSource;
      _microphoneMode = value.microphoneMode;
      _audio = value.audioSettings;
      if (value.audioSource == 'microphone') {
        _echo = value.echoCancellation;
        _noise = value.noiseSuppression;
        _gain = value.autoGain;
      }
      if (!_service.busy && !_operationRunning) {
        if (value.microphone) _muted = _service.microphoneMuted;
        if (value.camera) {
          _paused = _service.cameraPaused;
          _torch = _service.torch;
          _savedZoom = _service.zoom;
        }
      }
      if (value.camera) {
        _capabilities = _service.capabilities;
        _mode = _capabilities.choose(width: value.width, height: value.height);
        _fps = value.fps;
        _bitrate = value.bitrateKbps;
      }
      if (!_service.busy && !_operationRunning) _saveSettings();
    }
    if ((_rendererReady || _android) && !_previewDisposed) {
      _previewDirty = true;
      _previewBinding ??= _bindPreview().whenComplete(
        () => _previewBinding = null,
      );
    }
    if (mounted) setState(() {});
  }

  Future<void> _bindPreview() async {
    try {
      do {
        _previewDirty = false;
        final stream =
            !widget.visible ||
                _previewSuspended ||
                (_service.broadcasting && _service.cameraPaused)
            ? null
            : _service.localStream ?? _service.remoteStream;
        final track = stream?.getVideoTracks().firstOrNull?.id;
        if (_android &&
            widget.renderer == null &&
            _service.remoteStream == null) {
          if (_previewTrack != track) {
            final texture = await const MethodChannel(
              'localist/capture',
            ).invokeMethod<int>('previewTrack', {'track': track});
            _previewTrack = track;
            if (_previewDisposed) {
              _previewTexture = texture;
              return;
            }
            if (mounted && _previewTexture != texture) {
              setState(() => _previewTexture = texture);
            }
          }
        } else if (_rendererReady &&
            (_renderer.srcObject != (track == null ? null : stream) ||
                _previewTrack != track)) {
          await _renderer.setSrcObject(
            stream: track == null ? null : stream,
            trackId: track,
          );
          _previewTrack = track;
        }
      } while (_previewDirty && !_previewDisposed);
    } catch (error) {
      LogService.instance.debug(
        'Capture page: preview binding failed type=${error.runtimeType}',
      );
      if (mounted && !_previewDisposed) {
        setState(() => _notice = '$error');
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _virtual.persian = Localizations.localeOf(context).languageCode == 'fa';
    _service.viewerLanguage = _virtual.persian ? 'fa' : 'en';
    if (_hub != null) _hub.persian = _virtual.persian;
  }

  void _hubChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshInputs({bool silent = false}) async {
    if (!_canScanInputs) return;
    if (_inputRefresh != null) {
      LogService.instance.debug('Capture page: input refresh coalesced');
      _inputRefreshAgain = true;
      return _inputRefresh;
    }
    _inputRefresh = _enumerateInputs(silent: silent);
    try {
      await _inputRefresh;
    } finally {
      _inputRefresh = null;
      if (_inputRefreshAgain && _canScanInputs) {
        _inputRefreshAgain = false;
        unawaited(_refreshInputs(silent: true));
      }
    }
  }

  Future<void> _enumerateInputs({bool silent = false}) async {
    LogService.instance.debug(
      'Capture page: input enumeration requested silent=$silent',
    );
    try {
      if (_android &&
          !silent &&
          await const MethodChannel('localist/capture')
                  .invokeMethod<bool>('hasBluetoothMicrophone')
                  .catchError((Object _) => false) ==
              true &&
          !await FeaturePermissionService.instance.granted(
            FeatureAccess.bluetoothAudio,
          )) {
        await FeaturePermissionService.instance.ensure([
          FeatureAccess.bluetoothAudio,
        ]);
      }
      final inputs = (await LiveCaptureService.inputDevices().timeout(
        const Duration(seconds: 8),
      )).where((d) => d.deviceId.isNotEmpty).toList();
      LogService.instance.debug(
        'Capture page: inputs available count=${inputs.length}',
      );
      _service.updateInputDevices(inputs);
      if (!_canScanInputs) return;
      final previous = _cameraId;
      setState(() {
        _inputs = inputs;
        final cameras = inputs.where((d) => d.kind == 'videoinput').toList();
        final microphones = inputs
            .where((d) => d.kind == 'audioinput')
            .toList();
        if (!cameras.any((d) => d.deviceId == _cameraId)) {
          _cameraId =
              cameras
                  .where(
                    (d) => RegExp(
                      r'back|rear|environment',
                      caseSensitive: false,
                    ).hasMatch(d.label),
                  )
                  .firstOrNull
                  ?.deviceId ??
              cameras.firstOrNull?.deviceId;
        }
        if (!microphones.any((d) => d.deviceId == _microphoneId)) {
          _microphoneId = microphones.firstOrNull?.deviceId;
        }
      });
      if (previous != _cameraId || _mode == null) await _loadCapabilities();
    } catch (error) {
      LogService.instance.debug(
        'Capture page: input enumeration failed type=${error.runtimeType}',
      );
      LogService.instance.warning('Capture input enumeration: $error');
      if (!silent && mounted) {
        setState(() => _notice = '$error');
      }
    }
  }

  Future<void> _loadCapabilities() async {
    final id = _cameraId;
    final request = ++_capabilityRequest;
    if (id == null) {
      LogService.instance.debug('Capture page: no camera available to query');
      if (mounted) {
        setState(() {
          _mode = null;
          _capabilities = const CaptureCapabilities();
        });
      }
      return;
    }
    setState(() => _loadingCapabilities = true);
    LogService.instance.debug(
      'Capture page: capabilities refresh requested fps=$_fps',
    );
    try {
      var caps = await LiveCaptureService.deviceCapabilities(
        id,
        width: _mode?.width ?? _preferredWidth,
        height: _mode?.height ?? _preferredHeight,
        fps: _fps,
      ).timeout(const Duration(seconds: 8));
      final mode = caps.choose(
        width: _mode?.width ?? _preferredWidth,
        height: _mode?.height ?? _preferredHeight,
      );
      final fps = mode == null ? _fps : _fps.clamp(mode.minFps, mode.maxFps);
      if (mode != null &&
          !_windows &&
          (mode.width != (_mode?.width ?? _preferredWidth) ||
              mode.height != (_mode?.height ?? _preferredHeight) ||
              fps != _fps)) {
        caps = await LiveCaptureService.deviceCapabilities(
          id,
          width: mode.width,
          height: mode.height,
          fps: fps,
        ).timeout(const Duration(seconds: 8));
      }
      if (!mounted || request != _capabilityRequest) return;
      LogService.instance.debug(
        'Capture page: capabilities loaded modes=${caps.modes.length} effectiveFps=$fps',
      );
      setState(() {
        _mode = mode;
        _fps = fps;
        _capabilities = caps;
        if (mode != null && _bitrate <= 0) {
          _bitrate = caps.recommendedBitrate(mode, fps);
        }
        if (caps.hasBitrateRange) {
          _bitrate = _bitrate.clamp(caps.minBitrate, caps.maxBitrate);
        }
      });
    } catch (error) {
      LogService.instance.debug(
        'Capture page: capabilities query failed type=${error.runtimeType}',
      );
      if (mounted && request == _capabilityRequest) {
        setState(() => _notice = '$error');
      }
    } finally {
      if (mounted && request == _capabilityRequest) {
        setState(() => _loadingCapabilities = false);
      }
    }
  }

  void _profile(String profile) {
    LogService.instance.debug(
      'Capture page: preset selected profile=$profile broadcasting=${_service.broadcasting}',
    );
    if (_service.broadcasting || _capabilities.modes.isEmpty) return;
    setState(() {
      _mode = profile == 'quality'
          ? _capabilities.modes.last
          : _capabilities.choose(
              width: profile == 'battery' ? 640 : 1280,
              height: profile == 'battery' ? 480 : 720,
            );
      _fps = (profile == 'battery' ? 15 : 30).clamp(
        _mode!.minFps,
        _mode!.maxFps,
      );
      _bitrate = _capabilities.recommendedBitrate(_mode!, _fps);
    });
    _saveSettings();
    unawaited(_loadCapabilities().then((_) => _saveSettings()));
  }

  Future<void> _refreshVirtualDevices() async {
    if (_checkingOutputs) return;
    setState(() => _checkingOutputs = true);
    LogService.instance.debug('Capture page: inspecting virtual devices');
    try {
      final status = await Future.wait([
        _virtual.microphoneStatus(),
        for (var slot = 0; slot < 4; slot++)
          WindowsVirtualDevicesService(slot: slot).cameraStatus(),
      ]);
      if (mounted) {
        LogService.instance.debug(
          'Capture page: virtual device statuses fetched count=${status.length}',
        );
        setState(() {
          _audioStatus = status.first;
          _installedCameraSlots = [
            for (var slot = 0; slot < 4; slot++)
              if (status[slot + 1]['installed'] == true) slot + 1,
          ];
        });
      }
    } catch (error) {
      LogService.instance.debug(
        'Capture page: virtual device inspection failed type=${error.runtimeType}',
      );
      if (mounted) setState(() => _notice = '$error');
    } finally {
      if (mounted) setState(() => _checkingOutputs = false);
    }
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_operationRunning) {
      LogService.instance.debug('Capture page: operation skipped while busy');
      return;
    }
    LogService.instance.debug('Capture page: operation started');
    setState(() {
      _operationRunning = true;
      _notice = '';
    });
    try {
      await operation();
      if (!mounted) return;
      if ((!_android || widget.renderer != null) &&
          !_rendererReady &&
          _hasPreviewVideo) {
        _renderer.onResize = () {
          if (mounted) setState(() {});
        };
        await _renderer.initialize();
        _rendererReady = true;
      }
      LogService.instance.debug(
        'Capture page: operation completed sender=${_service.broadcasting} receiver=${_service.receiving}',
      );
      _changed();
    } catch (error) {
      LogService.instance.debug(
        'Capture page: operation failed type=${error.runtimeType}',
      );
      if (mounted) setState(() => _notice = '$error');
    } finally {
      if (mounted) {
        setState(() => _operationRunning = false);
        if (_service.active) _changed();
      }
    }
  }

  Future<void> _switchCamera() async {
    LogService.instance.debug('Capture page: switch camera action');
    await _run(_service.switchCamera);
    if (!mounted) return;
    _editSettings(() => _cameraId = _service.activeCameraId);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_canScanInputs &&
        state == AppLifecycleState.resumed &&
        !_service.active) {
      unawaited(_refreshInputs(silent: true));
    }
    _previewSuspended = state != AppLifecycleState.resumed;
    _changed();
  }

  @override
  void dispose() {
    LogService.instance.debug(
      'Capture page: disposing UI preview and virtual outputs',
    );
    _previewDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    if (_senderLoaded && _prefs != null) {
      navigator.mediaDevices.ondevicechange = _previousDeviceChange;
    }
    unawaited(_audioDeviceChanges?.cancel());
    _service.removeListener(_changed);
    if (widget.service != null) _service.dispose();
    _hub?.removeListener(_hubChanged);
    _virtual.stopCamera();
    unawaited(_virtual.stopMicrophone().catchError((Object _) {}));
    _scroll.dispose();
    unawaited(
      (_previewBinding ?? Future<void>.value()).then((_) async {
        if (_android && widget.renderer == null && _previewTexture != null) {
          await const MethodChannel(
            'localist/capture',
          ).invokeMethod<void>('previewTrack').catchError((Object _) {});
        }
        if (_rendererReady) await _renderer.dispose();
      }),
    );
    super.dispose();
  }

  String get _statusLabel => switch (_service.status) {
    'waiting' => t('منتظر گیرنده', 'Waiting for a receiver'),
    'connected' => t('متصل', 'Connected'),
    'connecting' || 'new' => t('در حال اتصال', 'Connecting'),
    'disconnected' || 'closed' => t('قطع شده', 'Disconnected'),
    'failed' => t('اتصال ناموفق', 'Connection failed'),
    _ => t('آماده', 'Ready'),
  };

  Widget _inputSelector(String kind) {
    final video = kind == 'videoinput';
    final inputs = _inputs.where((device) => device.kind == kind).toList();
    final wanted = video ? _cameraId : _microphoneId;
    final selected = inputs.any((device) => device.deviceId == wanted)
        ? wanted
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: DropdownButtonFormField<String>(
        key: ValueKey('capture-$kind-$selected-${inputs.length}'),
        isExpanded: true,
        initialValue: selected,
        decoration: InputDecoration(
          labelText: video
              ? t('انتخاب دوربین', 'Camera input')
              : t('انتخاب میکروفون', 'Microphone input'),
        ),
        hint: Text(t('ورودی در دسترس نیست', 'No input available')),
        items: [
          for (final input in inputs)
            DropdownMenuItem(
              value: input.deviceId,
              child: Text(input.label, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: inputs.isEmpty
            ? null
            : (id) async {
                if (id == null) return;
                _editSettings(() {
                  if (video) {
                    _cameraId = id;
                  } else {
                    _microphoneId = id;
                  }
                });
                if (video) {
                  await _loadCapabilities();
                  if (mounted) _saveSettings();
                }
              },
      ),
    );
  }

  List<Widget> _videoModeFields() {
    final caps = _capabilities;
    final mode = _mode;
    final fps = _fps;
    final bitrate = _bitrate;
    return [
      if (_loadingCapabilities) const LinearProgressIndicator(),
      DropdownButtonFormField<String>(
        key: ValueKey('capture-resolution-${mode?.key}'),
        isExpanded: true,
        initialValue: mode?.key,
        decoration: InputDecoration(
          labelText: t('رزولوشن دوربین', 'Camera resolution'),
        ),
        hint: Text(
          t('در انتظار مشخصات دوربین', 'Waiting for camera capabilities'),
        ),
        items: [
          for (final mode in caps.modes)
            DropdownMenuItem(
              value: mode.key,
              child: Text(mode.label, textDirection: TextDirection.ltr),
            ),
        ],
        onChanged: _loadingCapabilities || caps.modes.isEmpty
            ? null
            : (key) async {
                if (key == null) return;
                _editSettings(
                  () =>
                      _mode = caps.modes.firstWhere((mode) => mode.key == key),
                );
                await _loadCapabilities();
                if (mounted) _saveSettings();
              },
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<int>(
        key: ValueKey('capture-fps-${mode?.key}-$fps'),
        isExpanded: true,
        initialValue: mode?.frameRates.contains(fps) == true ? fps : null,
        decoration: InputDecoration(labelText: t('نرخ فریم', 'Frame rate')),
        items: [
          for (final rate in mode?.frameRates ?? <int>[])
            DropdownMenuItem(
              value: rate,
              child: Text(t('$rate فریم در ثانیه', '$rate FPS')),
            ),
        ],
        onChanged: _loadingCapabilities || mode == null
            ? null
            : (value) async {
                if (value == null) return;
                _editSettings(() => _fps = value);
                await _loadCapabilities();
                if (mounted) _saveSettings();
              },
      ),
      const SizedBox(height: 14),
      if (caps.hasBitrateRange) ...[
        Text(
          t(
            'بیت‌ریت هدف: $bitrate کیلوبیت بر ثانیه',
            'Target bitrate: $bitrate kbps',
          ),
        ),
        Text(
          t(
            '${caps.minBitrate} تا ${caps.maxBitrate} کیلوبیت بر ثانیه',
            '${caps.minBitrate}–${caps.maxBitrate} kbps',
          ),
        ),
        if (caps.maxBitrate > caps.minBitrate)
          Slider(
            min: math.log(caps.minBitrate.toDouble()),
            max: math.log(caps.maxBitrate.toDouble()),
            value: math.log(
              bitrate.clamp(caps.minBitrate, caps.maxBitrate).toDouble(),
            ),
            onChanged: _loadingCapabilities
                ? null
                : (value) => setState(() => _bitrate = math.exp(value).round()),
            onChangeEnd: (_) => _saveSettings(),
          ),
      ] else
        TextFormField(
          initialValue: bitrate > 0 ? '$bitrate' : '',
          enabled: !_loadingCapabilities,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: t('بیت‌ریت هدف', 'Target bitrate'),
            suffixText: t('کیلوبیت/ثانیه', 'kbps'),
            helperMaxLines: 3,
            helperText: t(
              'این درایور محدودهٔ بیت‌ریت را اعلام نمی‌کند؛ مقدار موردنظر از طریق کنترل نرخ ارتباط زنده اعمال می‌شود.',
              'This driver does not report bitrate bounds; WebRTC applies the target rate.',
            ),
          ),
          onChanged: (value) {
            final rate = int.tryParse(value);
            if (rate == null || rate < 1 || rate > 1000000) return;
            _bitrate = rate;
            _saveSettings();
          },
        ),
    ];
  }

  Widget _heading(IconData icon, String title, String subtitle) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(
          icon,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    ],
  );

  Widget _settingsGroup(
    IconData icon,
    String title,
    List<Widget> fields,
  ) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...fields,
      ],
    ),
  );

  Widget _captureSettings() => LayoutBuilder(
    builder: (context, constraints) {
      final video = _settingsGroup(
        Icons.videocam_outlined,
        t('تصویر', 'Video'),
        [_inputSelector('videoinput'), ..._videoModeFields()],
      );
      final audio = _settingsGroup(Icons.mic_none, t('صدا', 'Audio'), [
        if (_windows || _android)
          DropdownButtonFormField<String>(
            isExpanded: true,
            key: ValueKey('capture-source-$_audioSource'),
            initialValue: _audioSource,
            decoration: InputDecoration(
              labelText: t('منبع صدا', 'Audio source'),
            ),
            items: [
              DropdownMenuItem(
                value: 'microphone',
                child: Text(t('میکروفون', 'Microphone')),
              ),
              DropdownMenuItem(
                value: 'system',
                child: Text(
                  t('صدای برنامه‌ها و دستگاه', 'Apps and system audio'),
                ),
              ),
            ],
            onChanged: (value) => _editSettings(() {
              _audioSource = value ?? 'microphone';
              if (_audioSource == 'system') _camera = false;
            }),
          ),
        if (_audioSource == 'microphone') _inputSelector('audioinput'),
        if (_android && _audioSource == 'microphone')
          CaptureMicrophoneMode(
            available: _microphoneModes,
            selected: _microphoneMode,
            onChanged: _operationRunning || _service.busy
                ? null
                : (mode) => _editSettings(() => _microphoneMode = mode),
          ),
        CaptureAudioControls(
          settings: _audio,
          sender: true,
          windows: _windows,
          enabled: !_operationRunning && !_service.busy,
          echo: _echo,
          noise: _noise,
          autoGain: _gain,
          onEffects: _audioSource == 'microphone' ? _draftEffects : null,
          onChanged: _draftAudio,
        ),
      ]);

      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      if (_camera && _microphone && constraints.maxWidth / scale >= 580) {
        return Row(
          key: const ValueKey('capture-settings-columns'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: video),
            const SizedBox(width: 14),
            Expanded(child: audio),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_camera) video,
          if (_camera && _microphone) const SizedBox(height: 14),
          if (_microphone) audio,
        ],
      );
    },
  );

  Widget _sendCard() {
    if (_service.active) return _sessionCard();
    if (!_senderLoaded || _loadingInputs || _service.busy) {
      return GlassPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t('در حال آماده‌سازی ورودی‌ها…', 'Preparing capture inputs…')),
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
        ),
      );
    }
    return GlassPanel(
      key: const ValueKey('capture-send-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heading(
            Icons.sensors,
            t('فرستنده', 'Send'),
            t(
              'دوربین و صدای این دستگاه را به اشتراک بگذارید.',
              'Share this device’s camera and microphone.',
            ),
          ),
          const SizedBox(height: 16),
          if (_camera)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  label: Text(t('کم‌مصرف', 'Battery saver')),
                  onPressed: () => _profile('battery'),
                ),
                ActionChip(
                  label: Text(t('متعادل', 'Balanced')),
                  onPressed: () => _profile('balanced'),
                ),
                ActionChip(
                  label: Text(t('با کیفیت', 'High quality')),
                  onPressed: () => _profile('quality'),
                ),
              ],
            ),

          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilterChip(
                showCheckmark: false,
                avatar: const Icon(Icons.videocam_outlined, size: 18),
                label: Text(t('دوربین', 'Camera')),
                selected: _camera,
                onSelected: _service.broadcasting || _audioSource == 'system'
                    ? null
                    : (v) => _editSettings(() => _camera = v),
              ),
              FilterChip(
                showCheckmark: false,
                avatar: const Icon(Icons.mic_none, size: 18),
                label: Text(t('میکروفون', 'Microphone')),
                selected: _microphone,
                onSelected: _service.broadcasting
                    ? null
                    : (v) => _editSettings(() => _microphone = v),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _captureSettings(),
          if (!_service.broadcasting &&
              ((_camera &&
                      (_cameraId == null || _capabilities.modes.isEmpty)) ||
                  (_microphone &&
                      _audioSource == 'microphone' &&
                      _microphoneId == null)))
            OutlinedButton.icon(
              onPressed: _operationRunning
                  ? null
                  : () => _run(() async {
                      if (await FeaturePermissionService.instance.ensure([
                        if (_camera) FeatureAccess.camera,
                        if (_microphone) FeatureAccess.microphone,
                      ])) {
                        await _refreshInputs();
                      }
                    }),
              icon: const Icon(Icons.perm_camera_mic_outlined),
              label: Text(
                t(
                  'دسترسی و تازه‌سازی ورودی‌ها',
                  'Allow access and refresh inputs',
                ),
              ),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed:
                _operationRunning ||
                    (!_camera && !_microphone) ||
                    (_camera &&
                        (_cameraId == null ||
                            _mode == null ||
                            _loadingCapabilities)) ||
                    (_microphone &&
                        _audioSource == 'microphone' &&
                        _microphoneId == null)
                ? null
                : () => _run(_startBroadcast),
            icon: const Icon(Icons.sensors),
            label: Text(t('شروع انتقال زنده', 'Start live capture')),
          ),
        ],
      ),
    );
  }

  Future<void> _startBroadcast() async {
    _saveSettings();
    final torch = _torch, zoom = _savedZoom;
    await _service.start(
      LiveCaptureOptions(
        camera: _camera,
        startMuted: _muted,
        startPaused: _paused,
        microphone: _microphone,
        cameraId: _cameraId,
        microphoneId: _audioSource == 'microphone' ? _microphoneId : null,
        audioSettings: _audio,
        audioSource: _audioSource,
        microphoneMode: _microphoneMode,
        width: _mode?.width ?? _preferredWidth,
        height: _mode?.height ?? _preferredHeight,
        fps: _fps,
        bitrateKbps: _bitrate > 0 ? _bitrate : 1,
        echoCancellation: _echo,
        noiseSuppression: _noise,
        autoGain: _gain,
      ),
    );
    if (!_service.broadcasting) return;
    if (_service.options.camera && zoom > 1 && _service.maxZoom > 1) {
      await _service.setZoom(zoom);
    }
    if (_service.options.camera && torch && _service.hasTorch) {
      await _service.setTorch(true);
    }
  }

  Widget _receiveCard() => CaptureReceiversPanel(hub: _hub, windows: _windows);

  bool get _nativePreviewReady =>
      _previewTexture != null &&
      (!Platform.isAndroid || _service.videoPortrait != null);

  double get _previewAspectRatio {
    if (_nativePreviewReady) return 9 / 16;
    final width = _service.options.width;
    final height = _service.options.height;
    return width == height
        ? 16 / 9
        : math.max(width, height) / math.min(width, height);
  }

  Widget _sessionCard() => GlassPanel(
    key: const ValueKey('capture-session-card'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(Icons.live_tv, t('انتقال زنده', 'Live session'), _statusLabel),
        const SizedBox(height: 16),
        if (_hasPreviewVideo &&
            !_service.cameraPaused &&
            (_nativePreviewReady || _rendererReady)) ...[
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: math.min(
                  640,
                  MediaQuery.sizeOf(context).height * .62 * _previewAspectRatio,
                ),
              ),
              child: AspectRatio(
                aspectRatio: _previewAspectRatio,
                child: ColoredBox(
                  color: Colors.black,
                  child: _nativePreviewReady
                      ? Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.diagonal3Values(
                            _mirror ? -1.0 : 1.0,
                            1,
                            1,
                          ),
                          child: Texture(textureId: _previewTexture!),
                        )
                      : RTCVideoView(_renderer, mirror: _mirror),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _nativePreviewReady
                ? t(
                    'پیش‌نمایش سبک است. خروجی با کیفیت انتخابی ارسال می‌شود.',
                    'Low-power preview. The stream uses your selected quality.',
                  )
                : t(
                    'پیش‌نمایش کوچک‌شده است. خروجی با کیفیت انتخابی ارسال می‌شود.',
                    'Scaled preview. The stream uses your selected quality.',
                  ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 12),
        Text(
          '${t('وضعیت', 'Status')}: $_statusLabel • ${t('بیننده', 'Viewers')}: ${_service.viewers}',
        ),
        if (_service.broadcasting) ...[
          const SizedBox(height: 12),
          if (_service.options.microphone)
            CaptureLatencyChart(
              values: _service.latencyHistory['audio']!,
              video: false,
            ),
          if (_service.options.microphone && _service.options.camera)
            const SizedBox(height: 12),
          if (_service.options.camera)
            CaptureLatencyChart(
              values: _service.latencyHistory['video']!,
              video: true,
            ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (_service.broadcasting && _service.options.microphone)
              IconButton.filledTonal(
                tooltip: t('قطع/وصل میکروفون', 'Mute microphone'),
                isSelected: _service.microphoneMuted,
                icon: const Icon(Icons.mic_outlined),
                selectedIcon: const Icon(Icons.mic_off_outlined),
                onPressed: () =>
                    _service.muteMicrophone(!_service.microphoneMuted),
              ),
            if (_service.broadcasting && _service.options.camera) ...[
              IconButton.filledTonal(
                tooltip: t('توقف/ادامه تصویر', 'Pause camera'),
                isSelected: _service.cameraPaused,
                icon: const Icon(Icons.videocam_outlined),
                selectedIcon: const Icon(Icons.videocam_off_outlined),
                onPressed: () => _service.pauseCamera(!_service.cameraPaused),
              ),
              IconButton.filledTonal(
                tooltip: t('تعویض دوربین', 'Switch camera'),
                icon: const Icon(Icons.cameraswitch_outlined),
                onPressed: _service.busy ? null : _switchCamera,
              ),
              if (_android && _service.hasTorch)
                IconButton.filledTonal(
                  tooltip: t('چراغ دوربین', 'Camera light'),
                  isSelected: _service.torch,
                  icon: const Icon(Icons.flashlight_off_outlined),
                  selectedIcon: const Icon(Icons.flashlight_on_outlined),
                  onPressed: _operationRunning || _service.busy
                      ? null
                      : () => _run(() => _service.setTorch(!_service.torch)),
                ),
            ],
            if (_hasPreviewVideo)
              IconButton.filledTonal(
                tooltip: t('تصویر آینه‌ای', 'Mirror preview'),
                isSelected: _mirror,
                icon: const Icon(Icons.flip),
                selectedIcon: const Icon(Icons.flip),
                onPressed: () => _editSettings(() => _mirror = !_mirror),
              ),
            if (_android && _service.broadcasting)
              IconButton.filledTonal(
                tooltip: t('ادامه با صفحهٔ خاموش', 'Continue with screen off'),
                icon: const Icon(Icons.screen_lock_portrait_outlined),
                onPressed: _operationRunning
                    ? null
                    : () => _run(_service.continueWithScreenOff),
              ),
            IconButton.filled(
              tooltip: t('توقف اشتراک', 'Stop sharing'),
              icon: const Icon(Icons.stop),
              style: IconButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.errorContainer,
                foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
              ),
              onPressed: () => _run(_service.stop),
            ),
          ],
        ),
        if (_android &&
            _service.broadcasting &&
            _service.localStream?.getVideoTracks().isNotEmpty == true &&
            _service.maxZoom > 1) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Text(t('زوم', 'Zoom')),
              Expanded(
                child: Slider(
                  value: (_zoomDraft ?? _service.zoom).clamp(
                    1,
                    _service.maxZoom,
                  ),
                  min: 1,
                  max: _service.maxZoom,
                  label: '${(_zoomDraft ?? _service.zoom).toStringAsFixed(1)}×',
                  onChanged: _operationRunning || _service.busy
                      ? null
                      : (value) => setState(() => _zoomDraft = value),
                  onChangeEnd: (value) async {
                    await _run(() => _service.setZoom(value));
                    if (mounted) setState(() => _zoomDraft = null);
                  },
                ),
              ),
              Text('${_service.zoom.toStringAsFixed(1)}×'),
            ],
          ),
        ],
      ],
    ),
  );

  Widget _virtualCard() => GlassPanel(
    key: const ValueKey('capture-outputs-card'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(
          Icons.video_camera_front_outlined,
          t('خروجی دستگاه‌ها', 'Device outputs'),
          '',
        ),
        const SizedBox(height: 12),
        if (_checkingOutputs) const LinearProgressIndicator(),
        if (!_checkingOutputs && _installedCameraSlots.isEmpty)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.videocam_off_outlined),
            title: Text(t('وبکم', 'Webcam')),
            trailing: Text(t('نصب نیست', 'Not installed')),
          ),
        for (final slot in _installedCameraSlots)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.videocam_outlined),
            title: Text(
              t('دوربین مجازی لوکالیست $slot', 'Localist Camera $slot'),
            ),
            trailing: Text(t('آماده', 'Ready')),
          ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            _audioStatus['available'] == true
                ? Icons.mic_outlined
                : Icons.mic_off_outlined,
          ),
          title: const Text('VB-CABLE · VB-Audio'),
          trailing: Text(
            _checkingOutputs
                ? t('در حال بررسی', 'Checking')
                : _audioStatus['available'] == true
                ? t('آماده', 'Ready')
                : t('در دسترس نیست', 'Unavailable'),
          ),
        ),
        TextButton.icon(
          onPressed: _checkingOutputs ? null : _refreshVirtualDevices,
          icon: const Icon(Icons.refresh),
          label: Text(t('بررسی وضعیت دستگاه‌ها', 'Refresh device status')),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final available = (constraints.maxWidth - 40).clamp(0.0, 1420.0);
      final server = _showSender;
      final columns = !server && _windows && available / scale >= 1040;
      final width = columns ? available : available.clamp(0.0, 840.0);
      final side = [if (!server && _windows) _virtualCard()];
      Widget stack(List<Widget> cards) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(height: 18),
            cards[i],
          ],
        ],
      );
      final primary = server ? _sendCard() : _receiveCard();
      return Scrollbar(
        controller: _scroll,
        thumbVisibility: _windows,
        child: SingleChildScrollView(
          controller: _scroll,
          key: const ValueKey('capture-page-scroll'),
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: width,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    t('دوربین و میکروفون', 'Camera & Mic'),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    t(
                      'انتقال دوربین و صدا با وای‌فای یا کابل؛ دریافت در لوکالیست و استفاده در برنامه‌های ضبط و پخش تصویر.',
                      'Share camera and audio over Wi-Fi or USB; receive in Localist and use in OBS or other apps.',
                    ),
                  ),
                  const SizedBox(height: 22),
                  if (widget.receiving == null && !_service.broadcasting)
                    Visibility(
                      visible: true,
                      maintainSize: true,
                      maintainState: true,
                      maintainAnimation: true,
                      child: SegmentedButton<String>(
                        key: const ValueKey('capture-role'),
                        segments: [
                          ButtonSegment(
                            value: 'player',
                            icon: const Icon(Icons.headphones),
                            label: Text(t('گیرنده', 'Receiver')),
                          ),
                          ButtonSegment(
                            value: 'server',
                            icon: const Icon(Icons.wifi_tethering),
                            label: Text(t('فرستنده', 'Sender')),
                          ),
                        ],
                        selected: {_panel},
                        onSelectionChanged: (v) {
                          setState(() => _panel = v.first);
                          _loadVisiblePanel();
                        },
                      ),
                    ),
                  const SizedBox(height: 18),
                  if (_notice.isNotEmpty || _service.error.isNotEmpty) ...[
                    Text(
                      captureErrorText(
                        context,
                        _notice.isNotEmpty ? _notice : _service.error,
                      ),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (columns)
                    Row(
                      key: const ValueKey('capture-desktop-columns'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: primary),
                        const SizedBox(width: 20),
                        Expanded(flex: 2, child: stack(side)),
                      ],
                    )
                  else
                    stack([primary, ...side]),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
