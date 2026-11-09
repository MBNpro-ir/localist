import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/live_capture_service.dart';
import '../services/capture_capabilities.dart';
import '../services/capture_hub_service.dart';
import '../services/windows_virtual_devices_service.dart';
import '../services/feature_permission_service.dart';
import '../widgets/glass.dart';
import '../widgets/capture_receivers_panel.dart';

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
  CaptureCapabilities _capabilities = const CaptureCapabilities();
  CaptureMode? _mode;
  String _orientation = 'landscape';
  bool _loadingCapabilities = false;
  int _capabilityRequest = 0;
  bool get _windows => defaultTargetPlatform == TargetPlatform.windows;
  bool get _android => defaultTargetPlatform == TargetPlatform.android;
  List<MediaDeviceInfo> _inputs = [];
  String? _cameraId, _microphoneId;
  bool _operationRunning = false, _previewSuspended = false;
  Future<void>? _previewBinding;
  bool _previewDirty = false, _previewDisposed = false;
  String? _previewTrack;
  double? _zoomDraft;
  bool _rendererReady = false, _camera = true, _microphone = true;
  bool _echo = true, _noise = true, _gain = true, _mirror = false;
  int _fps = 30, _bitrate = 0;
  String _notice = '';
  String t(String fa, String en) =>
      Localizations.localeOf(context).languageCode == 'fa' ? fa : en;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _service.addListener(_changed);
    _hub?.addListener(_hubChanged);
    if (_hub != null) unawaited(_hub.start());
    if (_windows) unawaited(_refreshVirtualDevices());
    unawaited(_refreshInputs(silent: true));
  }

  void _changed() {
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
          await _renderer.setSrcObject(stream: source, trackId: track);
          _previewTrack = track;
        }
      } while (_previewDirty && !_previewDisposed);
    } catch (error) {
      if (mounted && !_previewDisposed) setState(() => _notice = '$error');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _virtual.persian = Localizations.localeOf(context).languageCode == 'fa';
    if (_hub != null) _hub.persian = _virtual.persian;
  }

  void _hubChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshInputs({bool silent = false}) async {
    try {
      final inputs = (await LiveCaptureService.inputDevices())
          .where((d) => d.deviceId.isNotEmpty)
          .toList();
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
      if (!silent && mounted) setState(() => _notice = '$error');
    }
  }

  Future<void> _loadCapabilities() async {
    final id = _cameraId;
    final request = ++_capabilityRequest;
    if (id == null) {
      if (mounted) {
        setState(() {
          _mode = null;
          _capabilities = const CaptureCapabilities();
        });
      }
      return;
    }
    setState(() => _loadingCapabilities = true);
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
      if (mounted && request == _capabilityRequest) {
        setState(() => _notice = '$error');
      }
    } finally {
      if (mounted && request == _capabilityRequest) {
        setState(() => _loadingCapabilities = false);
      }
    }
  }

  Future<void> _bluetoothInputs() async {
    if (await FeaturePermissionService.instance.ensure(
      [FeatureAccess.bluetoothAudio],
      reason: t(
        'برای انتخاب میکروفون هدست بلوتوث، دسترسی اتصال بلوتوث لازم است.',
        'Bluetooth connection access is needed to select a headset microphone.',
      ),
    )) {
      await _refreshInputs();
    }
  }

  void _profile(String profile) {
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
    try {
      final status = await _virtual.microphoneStatus();
      if (mounted) setState(() => _audioStatus = status);
    } catch (error) {
      if (mounted) setState(() => _notice = '$error');
    }
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_operationRunning) return;
    setState(() => _operationRunning = true);
    try {
      await LiveCaptureService.initializeMedia();
      if (!_rendererReady) {
        _renderer.onResize = () {
          if (mounted) setState(() {});
        };
        await _renderer.initialize();
        _rendererReady = true;
      }
      await operation();
      _changed();
    } catch (error) {
      if (mounted) setState(() => _notice = '$error');
    } finally {
      if (mounted) setState(() => _operationRunning = false);
    }
  }

  Future<void> _switchCamera() async {
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
    _previewDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
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
            key: ValueKey('capture-$kind-$live-$selected-${inputs.length}'),
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
          if (!video)
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: () => _refreshInputs(),
                  icon: const Icon(Icons.refresh),
                  label: Text(t('تازه‌سازی ورودی‌ها', 'Refresh inputs')),
                ),
                if (_android)
                  TextButton.icon(
                    onPressed: _bluetoothInputs,
                    icon: const Icon(Icons.bluetooth_audio),
                    label: Text(t('میکروفون بلوتوث', 'Bluetooth microphone')),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  List<Widget> _videoModeFields() => [
    if (_loadingCapabilities) const LinearProgressIndicator(),
    DropdownButtonFormField<String>(
      key: ValueKey('capture-resolution-${_mode?.key}'),
      isExpanded: true,
      initialValue: _mode?.key,
      decoration: InputDecoration(
        labelText: t('رزولوشن دوربین', 'Camera resolution'),
      ),
      hint: Text(
        t('در انتظار مشخصات دوربین', 'Waiting for camera capabilities'),
      ),
      items: [
        for (final mode in _capabilities.modes)
          DropdownMenuItem(
            value: mode.key,
            child: Text(mode.label, textDirection: TextDirection.ltr),
          ),
      ],
      onChanged: _loadingCapabilities
          ? null
          : (key) {
              setState(
                () =>
                    _mode = _capabilities.modes.firstWhere((m) => m.key == key),
              );
              unawaited(_loadCapabilities());
            },
    ),
    const SizedBox(height: 12),
    DropdownButtonFormField<int>(
      key: ValueKey('capture-fps-${_mode?.key}-$_fps'),
      isExpanded: true,
      initialValue: _mode == null ? null : _fps,
      decoration: InputDecoration(labelText: t('نرخ فریم', 'Frame rate')),
      items: [
        for (final fps in _mode?.frameRates ?? <int>[])
          DropdownMenuItem(
            value: fps,
            child: Text('$fps FPS', textDirection: TextDirection.ltr),
          ),
      ],
      onChanged: _loadingCapabilities
          ? null
          : (value) {
              if (value == null) return;
              setState(() => _fps = value);
              unawaited(_loadCapabilities());
            },
    ),
    const SizedBox(height: 14),
    Text('${t('بیت‌ریت هدف', 'Target bitrate')}: $_bitrate kbps'),
    if (_capabilities.hasBitrateRange) ...[
      Text(
        '${_capabilities.minBitrate}–${_capabilities.maxBitrate} kbps · ${_capabilities.codecs}',
        textDirection: TextDirection.ltr,
      ),
      if (_capabilities.maxBitrate > _capabilities.minBitrate)
        Slider(
          min: math.log(_capabilities.minBitrate.toDouble()),
          max: math.log(_capabilities.maxBitrate.toDouble()),
          value: math.log(
            _bitrate
                .clamp(_capabilities.minBitrate, _capabilities.maxBitrate)
                .toDouble(),
          ),
          onChanged: _loadingCapabilities
              ? null
              : (value) => setState(() => _bitrate = math.exp(value).round()),
        ),
    ] else
      TextFormField(
        key: ValueKey('capture-bitrate-$_bitrate'),
        initialValue: _bitrate > 0 ? '$_bitrate' : '',
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          suffixText: 'kbps',
          helperMaxLines: 3,
          helperText: t(
            'این درایور محدودهٔ بیت‌ریت اعلام نمی‌کند؛ مقدار هدف با کنترل نرخ WebRTC اعمال می‌شود.',
            'This driver does not report bitrate bounds; WebRTC applies the target rate.',
          ),
        ),
        onChanged: (v) {
          final rate = int.tryParse(v);
          if (rate != null && rate > 0 && rate <= 1000000) _bitrate = rate;
        },
      ),
  ];

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
            const SizedBox(height: 4),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
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
        _inputSelector('audioinput'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(t('حذف اکو', 'Echo cancellation')),
          value: _echo,
          onChanged: (v) => setState(() => _echo = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(t('کاهش نویز', 'Noise suppression')),
          value: _noise,
          onChanged: (v) => setState(() => _noise = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(t('تنظیم خودکار بلندی صدا', 'Automatic gain')),
          value: _gain,
          onChanged: (v) => setState(() => _gain = v),
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
              onSelected: (v) => setState(() => _camera = v),
            ),
            FilterChip(
              showCheckmark: false,
              avatar: const Icon(Icons.mic_none, size: 18),
              label: Text(t('میکروفون', 'Microphone')),
              selected: _microphone,
              onSelected: (v) => setState(() => _microphone = v),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _captureSettings(),
        if ((_camera && (_cameraId == null || _capabilities.modes.isEmpty)) ||
            (_microphone && _microphoneId == null))
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
        if (_android && _camera) _orientationSelector(),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed:
              _operationRunning ||
                  _service.busy ||
                  _loadingCapabilities ||
                  (!_camera && !_microphone) ||
                  (_camera && (_cameraId == null || _mode == null)) ||
                  (_microphone && _microphoneId == null)
              ? null
              : () => _run(
                  () => _service.start(
                    LiveCaptureOptions(
                      camera: _camera,
                      microphone: _microphone,
                      cameraId: _cameraId,
                      orientation: _orientation,
                      microphoneId: _microphoneId,
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
          icon: const Icon(Icons.sensors),
          label: Text(t('شروع انتقال زنده', 'Start live capture')),
        ),
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
        if (_rendererReady &&
            (_service.localStream != null || _service.remoteStream != null))
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
        if (_android && _service.broadcasting && _service.options.camera) ...[
          const SizedBox(height: 12),
          _orientationSelector(live: true),
        ],
        if (_android && _service.broadcasting) ...[
          const SizedBox(height: 12),
          _inputSelector('audioinput', live: true),
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
          t(
            'وبکم مستقل هر گیرنده به‌صورت خودکار آماده می‌شود.',
            'Each receiver gets an automatically registered webcam.',
          ),
        ),
        const SizedBox(height: 12),
        for (final slot in [1, 2, 3, 4])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              'Localist Camera $slot',
              textDirection: TextDirection.ltr,
            ),
          ),
        const SizedBox(height: 12),
        Text(
          _audioStatus['available'] == true
              ? t(
                  'صدا آماده است؛ در Discord، OBS یا مرورگر CABLE Output را به‌عنوان میکروفون انتخاب کنید.',
                  'Audio is ready. Select CABLE Output as your microphone in Discord, OBS or your browser.',
                )
              : t(
                  'VB-CABLE نصب یا فعال نیست. پس از نصب اولیه، ویندوز را ری‌استارت کنید.',
                  'VB-CABLE is not installed or enabled. Restart Windows after its first installation.',
                ),
        ),
        const SizedBox(height: 8),
        Text(
          t(
            'هر دستگاه یک کابل مستقل می‌گیرد و صداها ترکیب نمی‌شوند. تعداد وبکم و میکروفون را در Setup انتخاب کنید؛ برای کابل‌های بیشتر بسته‌های دارای مجوز A/B/C/D لازم است.',
            'Each device uses an independent cable; audio is never mixed. Choose device counts in Setup. Additional A/B/C/D cables require their licensed packages.',
          ),
        ),
        const SizedBox(height: 8),
        Text(
          t(
            'درایور صوتی VB-Audio · Donationware؛ حمایت از سازنده از vb-cable.com',
            'Audio driver by VB-Audio · Donationware; support the author at vb-cable.com',
          ),
        ),
        TextButton.icon(
          onPressed: _refreshVirtualDevices,
          icon: const Icon(Icons.refresh),
          label: Text(t('بررسی وضعیت دستگاه‌ها', 'Refresh device status')),
        ),
      ],
    ),
  );

  Widget _guideCard() => GlassPanel(
    padding: EdgeInsets.zero,
    child: ExpansionTile(
      title: Text(
        t(
          'راهنمای USB، OBS، دوربین و میکروفون مجازی',
          'USB, OBS & virtual device guide',
        ),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            t(
              '۱. برای Wi-Fi هر دو دستگاه را به یک شبکه وصل کنید. برای کابل، USB tethering گوشی را روشن کنید و Localist را در دو دستگاه باز کنید تا اتصال خودکار برقرار شود. اینترنت لازم نیست.\n۲. در ویندوز در برنامهٔ مقصد Localist Camera 1 تا 4 را انتخاب کنید؛ خروجی خودکار آماده می‌شود. برای صدا، CABLE Output را به‌عنوان میکروفون انتخاب کنید. هر دستگاه از کابل مستقل استفاده می‌کند؛ تعداد دستگاه‌ها و بسته‌های لازم در Setup انتخاب می‌شوند و پس از نصب اولیه ری‌استارت لازم است.\n۳. در OBS یک Video Capture Device با Localist Camera بسازید. وضوح و FPS خروجی در Properties و کنترل فرستنده در Configure Video هستند؛ کنترل تنظیمات فرستنده در دسترس است.\n۴. کیفیت و FPS واقعی به سخت‌افزار و شبکه وابسته‌اند. انتقال در پس‌زمینه ادامه دارد؛ اعلان بی‌صدا و دکمهٔ توقف در دسترس است.',
              '1. Use the same Wi-Fi, or enable phone USB tethering and open Localist on both devices for automatic reception. Internet is not needed.\n2. Select Localist Camera 1–4 in the target app; outputs are registered automatically. For audio, select CABLE Output. Each sender uses an independent cable. Choose device counts and licensed packages in Setup; restart Windows after first installation.\n3. In OBS add a Video Capture Device with Localist Camera. Properties sets output resolution/FPS; Configure Video controls the paired sender.\n4. Actual quality/FPS depend on hardware and network. Background sharing stays active with a silent notification and Stop action.',
            ),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final available = (constraints.maxWidth - 40).clamp(0.0, 1420.0);
      final columns = available / scale >= 1040;
      final width = columns ? available : available.clamp(0.0, 840.0);
      final side = [_receiveCard(), if (_windows) _virtualCard(), _guideCard()];
      Widget stack(List<Widget> cards) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(height: 18),
            cards[i],
          ],
        ],
      );
      final primary = _service.active ? _sessionCard() : _sendCard();
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
                      'انتقال دوربین و صدا با Wi-Fi یا کابل؛ دریافت در Localist و استفاده در OBS و برنامه‌های دیگر.',
                      'Share camera and audio over Wi-Fi or USB; receive in Localist and use in OBS or other apps.',
                    ),
                  ),
                  const SizedBox(height: 22),
                  if (_notice.isNotEmpty || _service.error.isNotEmpty) ...[
                    Text(
                      _notice.isNotEmpty ? _notice : _service.error,
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
