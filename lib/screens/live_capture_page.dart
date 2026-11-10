import 'dart:async';
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
import '../services/capture_audio_settings.dart';
import '../services/log_service.dart';
import '../l10n/capture_error_text.dart';
import '../widgets/capture_latency_chart.dart';

class LiveCapturePage extends StatefulWidget {
  const LiveCapturePage({super.key, this.service, this.renderer, this.hub});
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
  String _orientation = 'landscape';
  String _panel = 'server', _audioSource = 'microphone';
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
  int? _videoBitrateDraft;
  bool _rendererReady = false, _camera = true, _microphone = true;
  void Function(dynamic)? _previousDeviceChange;
  StreamSubscription<dynamic>? _audioDeviceChanges;
  Future<void>? _inputRefresh;
  bool _inputRefreshAgain = false, _bluetoothPermissionOffered = false;
  bool _echo = true, _noise = true, _gain = true, _mirror = false;
  int _fps = 30, _bitrate = 0;
  String _notice = '';
  String t(String fa, String en) =>
      Localizations.localeOf(context).languageCode == 'fa' ? fa : en;
  @override
  void initState() {
    super.initState();
    _panel = widget.service != null || _android ? 'server' : 'player';
    unawaited(_restoreAudioSettings());
    WidgetsBinding.instance.addObserver(this);
    _previousDeviceChange = navigator.mediaDevices.ondevicechange;
    navigator.mediaDevices.ondevicechange = (event) {
      _previousDeviceChange?.call(event);
      unawaited(_refreshInputs(silent: true));
    };
    if (_android) {
      _audioDeviceChanges = const EventChannel('localist/audioDevices')
          .receiveBroadcastStream()
          .listen(
            (_) {
              unawaited(_refreshInputs(silent: true));
            },
            onError: (Object error) {
              LogService.instance.warning('Audio device monitoring: $error');
            },
          );
    }
    _service.addListener(_changed);
    _hub?.addListener(_hubChanged);
    if (_hub != null) unawaited(_hub.start());
    if (_windows) unawaited(_refreshVirtualDevices());
    unawaited(_refreshInputs(silent: true));
    if (_service.broadcasting) _changed();
  }

  Future<void> _restoreAudioSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString('capture.senderAudio');
      if (stored == null || !mounted || _service.active) return;
      final map = Map<String, dynamic>.from(jsonDecode(stored) as Map);
      setState(() {
        _audio = CaptureAudioSettings.fromMap(map);
        _echo = map['echo'] != false;
        _noise = map['noise'] != false;
        _gain = map['gain'] != false;
      });
    } catch (_) {
      /* Invalid/old preferences never prevent capture. */
    }
  }

  Future<void> _saveAudioSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'capture.senderAudio',
      jsonEncode({
        ..._audio.toMap(),
        'echo': _echo,
        'noise': _noise,
        'gain': _gain,
      }),
    );
  }

  void _draftAudio(CaptureAudioSettings value) {
    setState(() => _audio = value);
    unawaited(_saveAudioSettings().catchError((Object _) {}));
  }

  void _draftEffects(Map<String, dynamic> values) {
    setState(() {
      _echo = values['echo'] as bool? ?? _echo;
      _noise = values['noise'] as bool? ?? _noise;
      _gain = values['gain'] as bool? ?? _gain;
    });
    unawaited(_saveAudioSettings().catchError((Object _) {}));
  }

  void _changed() {
    if (_service.broadcasting) {
      final value = _service.options;
      _camera = value.camera;
      _microphone = value.microphone;
      _cameraId = value.cameraId;
      _microphoneId = value.microphoneId;
      _audioSource = value.audioSource;
      _audio = value.audioSettings;
      _echo = value.echoCancellation;
      _noise = value.noiseSuppression;
      _gain = value.autoGain;
      _orientation = value.orientation;
      if (value.camera) {
        _capabilities = _service.capabilities;
        _mode = _capabilities.choose(width: value.width, height: value.height);
        _fps = value.fps;
        _bitrate = value.bitrateKbps;
      }
    }
    if (_rendererReady && !_previewDisposed) {
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
        final stream = _android && _previewSuspended && _service.broadcasting
            ? null
            : _service.localStream ?? _service.remoteStream;
        final track = stream?.getVideoTracks().firstOrNull?.id;
        final source = track == null ? null : stream;
        if (_renderer.srcObject != source || _previewTrack != track) {
          LogService.instance.debug(
            'Capture page: preview renderer rebinding hasVideo=${track != null}',
          );
          await _renderer.setSrcObject(stream: source, trackId: track);
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
    if (!mounted) return;
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
      if (_inputRefreshAgain && mounted) {
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
          !_bluetoothPermissionOffered &&
          await const MethodChannel('localist/capture')
                  .invokeMethod<bool>('hasBluetoothMicrophone')
                  .catchError((Object _) => false) ==
              true &&
          !await FeaturePermissionService.instance.granted(
            FeatureAccess.bluetoothAudio,
          )) {
        _bluetoothPermissionOffered = true;
        await FeaturePermissionService.instance.ensure([
          FeatureAccess.bluetoothAudio,
        ]);
      }
      final inputs = (await LiveCaptureService.inputDevices())
          .where((d) => d.deviceId.isNotEmpty)
          .toList();
      LogService.instance.debug(
        'Capture page: inputs available count=${inputs.length}',
      );
      _service.updateInputDevices(inputs);
      if (!mounted) return;
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
        width: _mode?.width ?? 1280,
        height: _mode?.height ?? 720,
        fps: _fps,
      );
      final mode = caps.choose(
        width: _mode?.width ?? 1280,
        height: _mode?.height ?? 720,
      );
      final fps = mode == null ? _fps : _fps.clamp(mode.minFps, mode.maxFps);
      if (mode != null) {
        caps = await LiveCaptureService.deviceCapabilities(
          id,
          width: mode.width,
          height: mode.height,
          fps: fps,
        );
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
    if (_service.broadcasting) {
      final caps = _service.capabilities;
      final mode = profile == 'quality'
          ? caps.modes.lastOrNull
          : caps.choose(
              width: profile == 'battery' ? 640 : 1280,
              height: profile == 'battery' ? 480 : 720,
            );
      if (mode == null) return;
      final fps = (profile == 'battery' ? 15 : 30).clamp(
        mode.minFps,
        mode.maxFps,
      );
      unawaited(
        _run(
          () => _service.requestCaptureControl({
            'width': mode.width,
            'height': mode.height,
            'fps': fps,
            'bitrate': caps.recommendedBitrate(mode, fps),
          }),
        ),
      );
      return;
    }
    if (_capabilities.modes.isEmpty) return;
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
    unawaited(_loadCapabilities());
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
    setState(() => _operationRunning = true);
    try {
      await LiveCaptureService.initializeMedia();
      if (!_rendererReady && (_service.active ? _hasPreviewVideo : _camera)) {
        _renderer.onResize = () {
          if (mounted) setState(() {});
        };
        await _renderer.initialize();
        _rendererReady = true;
      }
      await operation();
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
      if (mounted) setState(() => _operationRunning = false);
    }
  }

  Future<void> _switchCamera() async {
    LogService.instance.debug('Capture page: switch camera action');
    await _run(_service.switchCamera);
    if (!mounted) return;
    setState(() => _cameraId = _service.activeCameraId);
    await _loadCapabilities();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshInputs(silent: true));
    }
    if (_android) {
      _previewSuspended = state != AppLifecycleState.resumed;
      _changed();
    }
  }

  @override
  void dispose() {
    LogService.instance.debug(
      'Capture page: disposing UI preview and virtual outputs',
    );
    _previewDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    navigator.mediaDevices.ondevicechange = _previousDeviceChange;
    unawaited(_audioDeviceChanges?.cancel());
    _service.removeListener(_changed);
    if (widget.service != null) _service.dispose();
    _hub?.removeListener(_hubChanged);
    _virtual.stopCamera();
    unawaited(_virtual.stopMicrophone().catchError((Object _) {}));
    _scroll.dispose();
    unawaited(
      (_previewBinding ?? Future<void>.value()).then(
        (_) => _renderer.dispose(),
      ),
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

  Widget _inputSelector(String kind, {bool live = false}) {
    final video = kind == 'videoinput';
    if (live && !video && !_service.options.microphone) {
      return const SizedBox.shrink();
    }
    final inputs = _inputs.where((d) => d.kind == kind).toList();
    final wanted = live
        ? (video ? _service.activeCameraId : _service.options.microphoneId)
        : (video ? _cameraId : _microphoneId);
    final selected =
        inputs.where((d) => d.deviceId == wanted).firstOrNull?.deviceId ??
        inputs.firstOrNull?.deviceId;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
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
            onChanged: _operationRunning || _service.busy || inputs.isEmpty
                ? null
                : (id) async {
                    if (id == null) return;
                    if (live) {
                      await _run(
                        () => video
                            ? _service.switchCamera(cameraId: id)
                            : _service.selectMicrophone(id),
                      );
                    }
                    if (!mounted) return;
                    setState(() {
                      if (video) {
                        _cameraId = id;
                      } else {
                        _microphoneId = id;
                      }
                    });
                    if (video) await _loadCapabilities();
                  },
          ),
        ],
      ),
    );
  }

  List<Widget> _videoModeFields({bool live = false}) {
    final caps = live ? _service.capabilities : _capabilities;
    final mode = live
        ? caps.choose(
            width: _service.options.width,
            height: _service.options.height,
          )
        : _mode;
    final fps = live ? _service.options.fps : _fps;
    final bitrate =
        _videoBitrateDraft ?? (live ? _service.options.bitrateKbps : _bitrate);
    final locked = _loadingCapabilities || _operationRunning || _service.busy;
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
        onChanged: locked
            ? null
            : (key) {
                if (live) {
                  final selected = caps.modes.firstWhere((m) => m.key == key);
                  unawaited(
                    _run(
                      () => _service.requestCaptureControl({
                        'width': selected.width,
                        'height': selected.height,
                        'fps': fps.clamp(selected.minFps, selected.maxFps),
                      }),
                    ),
                  );
                  return;
                }
                setState(
                  () => _mode = _capabilities.modes.firstWhere(
                    (m) => m.key == key,
                  ),
                );
                unawaited(_loadCapabilities());
              },
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<int>(
        key: ValueKey('capture-fps-${mode?.key}-$fps'),
        isExpanded: true,
        initialValue: mode?.frameRates.contains(fps) == true ? fps : null,
        decoration: InputDecoration(labelText: t('نرخ فریم', 'Frame rate')),
        items: [
          for (final fps in mode?.frameRates ?? <int>[])
            DropdownMenuItem(
              value: fps,
              child: Text(t('$fps فریم در ثانیه', '$fps FPS')),
            ),
        ],
        onChanged: locked
            ? null
            : (value) {
                if (value == null) return;
                if (live) {
                  unawaited(
                    _run(() => _service.requestCaptureControl({'fps': value})),
                  );
                  return;
                }
                setState(() => _fps = value);
                unawaited(_loadCapabilities());
              },
      ),
      const SizedBox(height: 14),
      Text(
        t(
          'بیت‌ریت هدف: $bitrate کیلوبیت بر ثانیه',
          'Target bitrate: $bitrate kbps',
        ),
      ),
      if (caps.hasBitrateRange) ...[
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
            onChanged: locked
                ? null
                : (value) => setState(() {
                    if (live) {
                      _videoBitrateDraft = math.exp(value).round();
                    } else {
                      _bitrate = math.exp(value).round();
                    }
                  }),
            onChangeEnd: live
                ? (value) async {
                    await _run(
                      () => _service.requestCaptureControl({
                        'bitrate': math.exp(value).round(),
                      }),
                    );
                    if (mounted) setState(() => _videoBitrateDraft = null);
                  }
                : null,
          ),
      ] else
        TextFormField(
          key: ValueKey('capture-bitrate-$bitrate'),
          initialValue: bitrate > 0 ? '$bitrate' : '',
          enabled: !locked,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            suffixText: t('کیلوبیت/ثانیه', 'kbps'),
            helperMaxLines: 3,
            helperText: t(
              'این درایور محدودهٔ بیت‌ریت را اعلام نمی‌کند؛ مقدار موردنظر از طریق کنترل نرخ ارتباط زنده اعمال می‌شود.',
              'This driver does not report bitrate bounds; WebRTC applies the target rate.',
            ),
          ),
          onChanged: (v) {
            final rate = int.tryParse(v);
            if (!live && rate != null && rate > 0 && rate <= 1000000) {
              _bitrate = rate;
            }
          },
          onFieldSubmitted: live
              ? (value) {
                  final rate = int.tryParse(value);
                  if (rate != null) {
                    unawaited(
                      _run(
                        () => _service.requestCaptureControl({'bitrate': rate}),
                      ),
                    );
                  }
                }
              : null,
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

  Widget _captureSettings({bool live = false}) => LayoutBuilder(
    builder: (context, constraints) {
      final video =
          _settingsGroup(Icons.videocam_outlined, t('تصویر', 'Video'), [
            _inputSelector('videoinput', live: live),
            ..._videoModeFields(live: live),
            if (_android) _orientationSelector(live: live),
          ]);
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
            onChanged: live
                ? null
                : (value) => setState(() {
                    _audioSource = value ?? 'microphone';
                    if (_audioSource == 'system') _camera = false;
                  }),
          ),
        if (_audioSource == 'microphone')
          _inputSelector('audioinput', live: live),
        CaptureAudioControls(
          settings: live ? _service.options.audioSettings : _audio,
          sender: true,
          windows: _windows,
          enabled: !_operationRunning && !_service.busy,
          echo: live ? _service.options.echoCancellation : _echo,
          noise: live ? _service.options.noiseSuppression : _noise,
          autoGain: live ? _service.options.autoGain : _gain,
          onEffects: _audioSource != 'microphone'
              ? null
              : live
              ? (value) => _run(() => _service.requestCaptureControl(value))
              : _draftEffects,
          onChanged: live
              ? (value) => _run(
                  () => _service.requestCaptureControl({
                    for (final entry in value.toMap().entries)
                      if ([
                        'audioBitrate',
                        'audioGainDb',
                        'audioContinuous',
                        'audioUncompressed',
                      ].contains(entry.key))
                        entry.key: entry.value,
                  }),
                )
              : _draftAudio,
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

  Widget _orientationSelector({
    bool live = false,
  }) => DropdownButtonFormField<String>(
    isExpanded: true,
    key: ValueKey(
      'capture-orientation-${live ? _service.options.orientation : _orientation}',
    ),
    initialValue: live ? _service.options.orientation : _orientation,
    decoration: InputDecoration(
      labelText: t('جهت ویدیوی ارسالی', 'Outgoing video orientation'),
      prefixIcon: const Icon(Icons.screen_rotation_outlined),
    ),
    items: [
      DropdownMenuItem(
        value: 'auto',
        child: Text(t('خودکار با چرخش گوشی', 'Automatic with device rotation')),
      ),
      DropdownMenuItem(
        value: 'landscape',
        child: Text(t('قفل افقی', 'Lock landscape')),
      ),
      DropdownMenuItem(
        value: 'portrait',
        child: Text(t('قفل عمودی', 'Lock portrait')),
      ),
    ],
    onChanged: _operationRunning
        ? null
        : (value) {
            if (value == null) return;
            setState(() => _orientation = value);
            if (live) unawaited(_run(() => _service.setOrientation(value)));
          },
  );

  Widget _sendCard() => GlassPanel(
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
                  : (v) => setState(() => _camera = v),
            ),
            FilterChip(
              showCheckmark: false,
              avatar: const Icon(Icons.mic_none, size: 18),
              label: Text(t('میکروفون', 'Microphone')),
              selected: _microphone,
              onSelected: _service.broadcasting
                  ? null
                  : (v) => setState(() => _microphone = v),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _captureSettings(live: _service.broadcasting),
        if (!_service.broadcasting &&
            ((_camera && (_cameraId == null || _capabilities.modes.isEmpty)) ||
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
          onPressed: _service.broadcasting
              ? () => _run(_service.stop)
              : _operationRunning ||
                    _service.busy ||
                    _loadingCapabilities ||
                    (!_camera && !_microphone) ||
                    (_camera && (_cameraId == null || _mode == null)) ||
                    (_microphone &&
                        _audioSource == 'microphone' &&
                        _microphoneId == null)
              ? null
              : () => _run(
                  () => _service.start(
                    LiveCaptureOptions(
                      camera: _camera,
                      microphone: _microphone,
                      cameraId: _cameraId,
                      orientation: _orientation,
                      microphoneId: _audioSource == 'microphone'
                          ? _microphoneId
                          : null,
                      audioSettings: _audio,
                      audioSource: _audioSource,
                      width: _mode?.width ?? 1280,
                      height: _mode?.height ?? 720,
                      fps: _fps,
                      bitrateKbps: _bitrate > 0 ? _bitrate : 1,
                      echoCancellation: _echo,
                      noiseSuppression: _noise,
                      autoGain: _gain,
                    ),
                  ),
                ),
          icon: Icon(_service.broadcasting ? Icons.stop : Icons.sensors),
          label: Text(
            _service.broadcasting
                ? t('توقف اشتراک', 'Stop sharing')
                : t('شروع انتقال زنده', 'Start live capture'),
          ),
        ),
        if (_service.active) ...[const SizedBox(height: 18), _sessionCard()],
      ],
    ),
  );

  Widget _receiveCard() => CaptureReceiversPanel(hub: _hub, windows: _windows);

  Widget _sessionCard() => GlassPanel(
    key: const ValueKey('capture-session-card'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(Icons.live_tv, t('انتقال زنده', 'Live session'), _statusLabel),
        const SizedBox(height: 16),
        if (_rendererReady && _hasPreviewVideo)
          AspectRatio(
            aspectRatio: _renderer.videoWidth > 0 && _renderer.videoHeight > 0
                ? _renderer.videoWidth / _renderer.videoHeight
                : _service.options.orientation == 'portrait'
                ? math.min(_service.options.width, _service.options.height) /
                      math.max(_service.options.width, _service.options.height)
                : math.max(_service.options.width, _service.options.height) /
                      math.min(_service.options.width, _service.options.height),
            child: ColoredBox(
              color: Colors.black,
              child: RTCVideoView(
                _renderer,
                mirror: _mirror,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
              ),
            ),
          ),
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
            ],
            if (_hasPreviewVideo)
              IconButton.filledTonal(
                tooltip: t('تصویر آینه‌ای', 'Mirror preview'),
                isSelected: _mirror,
                icon: const Icon(Icons.flip),
                selectedIcon: const Icon(Icons.flip),
                onPressed: () => setState(() => _mirror = !_mirror),
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
        if (_android && _service.broadcasting) ...[
          const SizedBox(height: 12),
          if (_service.localStream?.getVideoTracks().isNotEmpty == true) ...[
            _inputSelector('videoinput', live: true),
            if (_service.maxZoom > 1)
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
                      label:
                          '${(_zoomDraft ?? _service.zoom).toStringAsFixed(1)}×',
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
            if (_service.hasTorch)
              FilterChip(
                label: Text(t('چراغ دوربین', 'Camera light')),
                selected: _service.torch,
                onSelected: _service.busy
                    ? null
                    : (value) => _run(() => _service.setTorch(value)),
              ),
          ],
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
      final server = _panel == 'server' || (_android && _service.broadcasting);
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
          padding: EdgeInsets.fromLTRB(20, 24, 20, _android ? 110 : 32),
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
                  Visibility(
                    visible: !_android || !_service.broadcasting,
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
                      onSelectionChanged: (v) =>
                          setState(() => _panel = v.first),
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
