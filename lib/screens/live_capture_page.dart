import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/live_capture_service.dart';
import '../services/windows_virtual_devices_service.dart';
import '../services/feature_permission_service.dart';
import '../widgets/glass.dart';

class LiveCapturePage extends StatefulWidget {
  const LiveCapturePage({super.key, this.service, this.renderer});
  final LiveCaptureService? service;
  final RTCVideoRenderer? renderer;
  @override
  State<LiveCapturePage> createState() => _LiveCapturePageState();
}

class _LiveCapturePageState extends State<LiveCapturePage>
    with WidgetsBindingObserver {
  late final _service = widget.service ?? LiveCaptureService();
  late final _renderer = widget.renderer ?? RTCVideoRenderer();
  final _link = TextEditingController();
  final _virtual = WindowsVirtualDevicesService();
  bool _virtualBusy = false, _cameraInstalled = false;
  List<MediaDeviceInfo> _outputs = [];
  bool get _windows => defaultTargetPlatform == TargetPlatform.windows;
  bool get _android => defaultTargetPlatform == TargetPlatform.android;
  List<MediaDeviceInfo> _inputs = [];
  String? _cameraId, _microphoneId;
  bool _operationRunning = false, _previewSuspended = false;
  bool _receiverControls = false;
  double? _zoomDraft;
  bool _rendererReady = false, _camera = true, _microphone = true, _rear = true;
  bool _echo = true,
      _noise = true,
      _gain = true,
      _mirror = false,
      _background = true;
  int _width = 1280, _fps = 30, _bitrate = 2500;
  String _notice = '';
  String t(String fa, String en) =>
      Localizations.localeOf(context).languageCode == 'fa' ? fa : en;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _service.addListener(_changed);
    _virtual.bindCaptureControls(_service);
    if (_windows) unawaited(_refreshVirtualDevices());
    unawaited(_refreshInputs(silent: true));
  }

  void _changed() {
    if (!_service.active &&
        (_virtual.cameraEnabled || _virtual.microphoneOutput != null)) {
      _virtual.stopCamera();
      unawaited(_virtual.stopMicrophone().catchError((Object _) {}));
    }
    if (_rendererReady) {
      _renderer.srcObject =
          _android && _previewSuspended && _service.broadcasting
          ? null
          : _service.localStream ?? _service.remoteStream;
    }
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _virtual.persian = Localizations.localeOf(context).languageCode == 'fa';
  }

  Future<void> _refreshInputs({bool silent = false}) async {
    try {
      final inputs = await LiveCaptureService.inputDevices();
      if (mounted) {
        setState(() {
          _inputs = inputs
              .where((device) => device.deviceId.isNotEmpty)
              .toList();
          if (!_inputs.any((device) => device.deviceId == _cameraId)) {
            _cameraId = null;
          }
          if (!_inputs.any((device) => device.deviceId == _microphoneId)) {
            _microphoneId = null;
          }
        });
      }
    } catch (error) {
      if (!silent && mounted) setState(() => _notice = '$error');
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

  void _profile(String profile) => setState(() {
    _width = profile == 'battery'
        ? 640
        : profile == 'quality'
        ? 1920
        : 1280;
    _fps = profile == 'battery' ? 15 : 30;
    _bitrate = profile == 'battery'
        ? 750
        : profile == 'quality'
        ? 6000
        : 2500;
    _background = true;
  });

  Future<void> _refreshVirtualDevices() async {
    try {
      final status = await _virtual.cameraStatus();
      final outputs = await _virtual.audioOutputs();
      if (mounted) {
        setState(() {
          _cameraInstalled = status['installed'] == true;
          _outputs = outputs;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _notice = '$error');
    }
  }

  Future<void> _virtualWork(Future<void> Function() operation) async {
    setState(() => _virtualBusy = true);
    try {
      await operation();
      if (mounted) setState(() => _notice = '');
    } catch (error) {
      if (mounted) setState(() => _notice = '$error');
    } finally {
      if (mounted) {
        await _refreshVirtualDevices();
        if (mounted) setState(() => _virtualBusy = false);
      }
    }
  }

  Future<void> _installMicrophone() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          t('نصب ورودی میکروفون ویندوز', 'Install Windows microphone input'),
        ),
        content: Text(
          t(
            'درایور امضاشدهٔ VB-CABLE از وب‌سایت رسمی VB-Audio دانلود می‌شود و نصب‌کنندهٔ اصلی باز می‌شود. این درایور متعلق به VB-Audio و تابع مجوز Donationware آن است. نصب را در پنجرهٔ آن تکمیل کنید؛ ممکن است ری‌استارت ویندوز لازم شود. درایور همراه Localist بازتوزیع نمی‌شود.',
            'The signed VB-CABLE driver is downloaded from VB-Audio and its original installer opens. It belongs to VB-Audio under its Donationware license. Complete installation there; Windows may need a restart. The driver is not redistributed with Localist.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('لغو', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              t('دانلود و باز کردن نصب‌کننده', 'Download & open installer'),
            ),
          ),
        ],
      ),
    );
    if (accepted == true && mounted) {
      await _virtualWork(_virtual.downloadMicrophoneInstaller);
    }
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_operationRunning) return;
    setState(() => _operationRunning = true);
    try {
      await LiveCaptureService.initializeMedia();
      if (!_rendererReady) {
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshInputs(silent: true));
    }
    if (_android) {
      _previewSuspended = state != AppLifecycleState.resumed;
      _changed();
    }
    if (state == AppLifecycleState.paused &&
        _service.broadcasting &&
        !_service.options.background) {
      unawaited(_service.stop());
      _notice = t(
        'انتقال با خروج از برنامه متوقف شد؛ برای ادامه شروع را بزنید.',
        'Capture stopped in background. Press Start to resume.',
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _service.removeListener(_changed);
    _service.dispose();
    _virtual.stopCamera();
    unawaited(_virtual.stopMicrophone().catchError((Object _) {}));
    _link.dispose();
    unawaited(_renderer.dispose());
    super.dispose();
  }

  Future<void> _copy(String link) async {
    await Clipboard.setData(ClipboardData(text: link));
    if (mounted) {
      showLocalistNotice(
        context,
        message: t('لینک اتصال کپی شد', 'Connection link copied'),
      );
    }
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
    final inputs = _inputs.where((device) => device.kind == kind).toList();
    final wanted = live
        ? (video ? _service.activeCameraId : _service.options.microphoneId)
        : (video ? _cameraId : _microphoneId);
    final selected = inputs.any((device) => device.deviceId == wanted)
        ? wanted!
        : '';
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
            items: [
              DropdownMenuItem(
                value: '',
                child: Text(t('خودکار', 'Automatic')),
              ),
              for (final input in inputs)
                DropdownMenuItem(
                  value: input.deviceId,
                  child: Text(input.label, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: _operationRunning || _service.busy
                ? null
                : (value) async {
                    final id = value?.isEmpty == true ? null : value;
                    if (live) {
                      if (video) {
                        await _run(() => _service.switchCamera(cameraId: id));
                        if (mounted) {
                          setState(() => _cameraId = _service.activeCameraId);
                        }
                      } else if (inputs.isNotEmpty) {
                        final chosen =
                            id ??
                            inputs
                                .firstWhere(
                                  (input) => input.label.toLowerCase().contains(
                                    'built-in',
                                  ),
                                  orElse: () => inputs.first,
                                )
                                .deviceId;
                        await _run(() => _service.selectMicrophone(chosen));
                        if (mounted) {
                          setState(
                            () => _microphoneId = _service.options.microphoneId,
                          );
                        }
                      }
                    } else if (mounted) {
                      setState(() {
                        if (video) {
                          _cameraId = id;
                        } else {
                          _microphoneId = id;
                        }
                      });
                    }
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

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 110),
    children: [
      Text(
        t('دوربین و میکروفون', 'Camera & Mic'),
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 8),
      Text(
        t(
          'انتقال زنده در Wi-Fi یا USB tethering؛ دریافت در Localist، مرورگر و OBS.',
          'Live over Wi-Fi or USB tethering; receive in Localist, a browser or OBS.',
        ),
      ),
      const SizedBox(height: 16),
      if (_notice.isNotEmpty)
        Text(
          _notice,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      if (_rendererReady &&
          (_service.localStream != null || _service.remoteStream != null))
        Container(
          height: 320,
          color: Colors.black,
          child: RTCVideoView(
            _renderer,
            mirror: _mirror,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
          ),
        ),
      if (_service.active) ...[
        const SizedBox(height: 12),
        Text(
          '${t('وضعیت', 'Status')}: $_statusLabel • ${t('بیننده', 'Viewers')}: ${_service.viewers}',
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (_service.broadcasting && _microphone)
              FilterChip(
                label: Text(t('میکروفون بی‌صدا', 'Mute microphone')),
                selected: _service.microphoneMuted,
                onSelected: _service.muteMicrophone,
              ),
            if (_service.broadcasting && _camera)
              FilterChip(
                label: Text(t('توقف تصویر', 'Pause camera')),
                selected: _service.cameraPaused,
                onSelected: _service.pauseCamera,
              ),
            if (_service.broadcasting && _camera)
              OutlinedButton.icon(
                onPressed: _service.busy
                    ? null
                    : () => _run(_service.switchCamera),
                icon: const Icon(Icons.cameraswitch),
                label: Text(t('تعویض دوربین', 'Switch camera')),
              ),
            FilterChip(
              label: Text(t('تصویر آینه‌ای', 'Mirror preview')),
              selected: _mirror,
              onSelected: (v) => setState(() => _mirror = v),
            ),
            if (_service.receiving)
              OutlinedButton.icon(
                onPressed: () => _run(
                  () => _service.setPlaybackMuted(!_service.playbackMuted),
                ),
                icon: const Icon(Icons.volume_up),
                label: Text(t('قطع/وصل صدا', 'Toggle playback audio')),
              ),
            FilledButton.icon(
              onPressed: () => _run(_service.stop),
              icon: const Icon(Icons.stop),
              label: Text(
                t('توقف و قطع همهٔ اتصال‌ها', 'Stop & disconnect all'),
              ),
            ),
          ],
        ),
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
          OutlinedButton.icon(
            onPressed: _operationRunning
                ? null
                : () => _run(_service.continueWithScreenOff),
            icon: const Icon(Icons.screen_lock_portrait),
            label: Text(t('ادامه با صفحهٔ خاموش', 'Continue with screen off')),
          ),
          Text(
            t(
              'انتقال در پس‌زمینه ادامه دارد. اگر صفحه خودکار قفل نشد، دکمهٔ پاور گوشی را بزنید. برای مصرف کمتر، پیش از شروع پروفایل کم‌مصرف را انتخاب کنید. محدودیت باتری سازنده هم باید اجازهٔ فعالیت پس‌زمینه بدهد.',
              'Sharing continues in the background. If the screen does not lock automatically, press the phone power button. Choose the battery saver profile before starting; allow background activity in the device battery settings.',
            ),
          ),
          TextButton(
            onPressed: () => FeaturePermissionService.instance.ensure(
              [FeatureAccess.battery],
              reason: t(
                'برای انتقال پیوسته با صفحهٔ خاموش، محدودیت فعالیت پس‌زمینه را بررسی کنید.',
                'Check background battery restrictions for uninterrupted screen-off sharing.',
              ),
            ),
            child: Text(
              t(
                'بررسی دسترسی پس‌زمینه و باتری',
                'Check background battery access',
              ),
            ),
          ),
        ],
        if (_service.broadcasting)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              t(
                'کنترل تنظیمات توسط گیرنده / OBS',
                'Allow receiver / OBS capture controls',
              ),
            ),
            subtitle: Text(
              t(
                'گیرندهٔ لینک جفت‌شده می‌تواند کیفیت، میکروفون، حذف نویز و زوم را تغییر دهد.',
                'Paired viewers can change capture quality, microphone, audio processing and zoom.',
              ),
            ),
            value: _service.options.receiverControls,
            onChanged: _service.allowReceiverControls,
          ),
        for (final link in _service.links)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: SelectableText(link, textDirection: TextDirection.ltr),
            trailing: IconButton(
              tooltip: t('کپی لینک', 'Copy link'),
              onPressed: () => _copy(link),
              icon: const Icon(Icons.copy),
            ),
          ),
        if (_service.broadcasting)
          Text(
            t(
              'لینک، کلید دسترسی دارد؛ فقط با شخص موردنظر به اشتراک بگذارید. با توقف، لینک باطل می‌شود. برای OBS گزینهٔ ?obs=1 را قبل از # اضافه کنید.',
              'The link contains an access key. Share with intended viewers only; Stop revokes it. For OBS add ?obs=1 before #.',
            ),
          ),
      ] else ...[
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t('فرستنده', 'Send'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
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
              SwitchListTile(
                title: Text(t('دوربین', 'Camera')),
                value: _camera,
                onChanged: (v) => setState(() => _camera = v),
              ),
              SwitchListTile(
                title: Text(t('میکروفون', 'Microphone')),
                value: _microphone,
                onChanged: (v) => setState(() => _microphone = v),
              ),
              SwitchListTile(
                title: Text(
                  t(
                    'کنترل تنظیمات توسط گیرنده / OBS',
                    'Allow receiver / OBS capture controls',
                  ),
                ),
                subtitle: Text(
                  t(
                    'با اجازهٔ شما، گیرندهٔ لینک می‌تواند تنظیمات ضبط را تغییر دهد.',
                    'Let a paired viewer adjust the capture settings.',
                  ),
                ),
                value: _receiverControls,
                onChanged: (value) => setState(() => _receiverControls = value),
              ),
              SwitchListTile(
                title: Text(
                  t(
                    'ادامهٔ انتقال در پس‌زمینه با اعلان توقف',
                    'Continue in background with a Stop notification',
                  ),
                ),
                value: _background,
                onChanged: (v) => setState(() => _background = v),
              ),
              if (_camera) ...[
                _inputSelector('videoinput'),
                SwitchListTile(
                  title: Text(t('دوربین پشت', 'Rear camera')),
                  value: _rear,
                  onChanged: (v) => setState(() => _rear = v),
                ),
                DropdownButtonFormField<int>(
                  key: ValueKey('capture-resolution-$_width'),
                  isExpanded: true,
                  initialValue: _width,
                  decoration: InputDecoration(
                    labelText: t('وضوح درخواستی', 'Requested resolution'),
                  ),
                  items: [
                    for (final w in [320, 640, 1280, 1920])
                      DropdownMenuItem(
                        value: w,
                        child: Text(
                          w == 320
                              ? '320 × 240'
                              : w == 640
                              ? '640 × 480'
                              : w == 1280
                              ? '1280 × 720'
                              : '1920 × 1080',
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _width = v!),
                ),
                DropdownButtonFormField<int>(
                  key: ValueKey('capture-fps-$_fps'),
                  isExpanded: true,
                  initialValue: _fps,
                  decoration: InputDecoration(
                    labelText: t('نرخ فریم درخواستی', 'Requested frame rate'),
                  ),
                  items: [
                    for (final fps in [10, 15, 24, 30, 60])
                      DropdownMenuItem(value: fps, child: Text('$fps FPS')),
                  ],
                  onChanged: (v) => setState(() => _fps = v!),
                ),
                Text('${t('سقف بیت‌ریت', 'Maximum bitrate')}: $_bitrate kbps'),
                Slider(
                  min: 250,
                  max: 8000,
                  divisions: 31,
                  value: _bitrate.toDouble(),
                  onChanged: (v) => setState(() => _bitrate = v.round()),
                ),
              ],
              if (_microphone) ...[
                _inputSelector('audioinput'),
                SwitchListTile(
                  title: Text(t('حذف اکو', 'Echo cancellation')),
                  value: _echo,
                  onChanged: (v) => setState(() => _echo = v),
                ),
                SwitchListTile(
                  title: Text(t('کاهش نویز', 'Noise suppression')),
                  value: _noise,
                  onChanged: (v) => setState(() => _noise = v),
                ),
                SwitchListTile(
                  title: Text(t('تنظیم خودکار بلندی صدا', 'Automatic gain')),
                  value: _gain,
                  onChanged: (v) => setState(() => _gain = v),
                ),
              ],
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed:
                    _operationRunning ||
                        _service.busy ||
                        (!_camera && !_microphone)
                    ? null
                    : () => _run(
                        () => _service.start(
                          LiveCaptureOptions(
                            background: _background,
                            camera: _camera,
                            microphone: _microphone,
                            rearCamera: _rear,
                            cameraId: _cameraId,
                            microphoneId: _microphoneId,
                            width: _width,
                            height: _width == 320
                                ? 240
                                : _width == 640
                                ? 480
                                : _width == 1280
                                ? 720
                                : 1080,
                            fps: _fps,
                            bitrateKbps: _bitrate,
                            echoCancellation: _echo,
                            noiseSuppression: _noise,
                            autoGain: _gain,
                            receiverControls: _receiverControls,
                          ),
                        ),
                      ),
                icon: const Icon(Icons.sensors),
                label: Text(t('شروع انتقال زنده', 'Start live capture')),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t('گیرنده', 'Receive'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              TextField(
                controller: _link,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: t(
                    'لینک کامل دستگاه فرستنده',
                    'Full sender connection link',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _service.busy
                    ? null
                    : () => _run(() => _service.connect(_link.text)),
                icon: const Icon(Icons.connected_tv),
                label: Text(t('اتصال', 'Connect')),
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 16),
      if (_windows) ...[
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t(
                  'وبکم و میکروفون برای نرم‌افزارهای ویندوز',
                  'Webcam & microphone for Windows apps',
                ),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                t(
                  'در OBS: Sources ← Video Capture Device ← Localist Camera. رزولوشن و FPS خروجی در Properties تنظیم می‌شوند. Configure Video تنظیمات ضبطِ فرستنده را با اجازهٔ او تغییر می‌دهد. در دیگر برنامه‌های سازگار هم Localist Camera را انتخاب کنید.',
                  'In OBS: Sources → Video Capture Device → Localist Camera. Set output resolution/FPS in Properties. Configure Video adjusts capture on a sender that has allowed receiver controls. Other compatible webcam apps can also select Localist Camera.',
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t('خروجی وبکم مجازی', 'Virtual webcam output')),
                subtitle: Text(
                  t(
                    'با توقف انتقال، تصویر خصوصی پاک و تصویر خالی جایگزین می‌شود.',
                    'Stopping the stream clears the private image and returns a blank frame.',
                  ),
                ),
                value: _virtual.cameraEnabled,
                onChanged:
                    _virtualBusy ||
                        !_rendererReady ||
                        (_service.localStream ?? _service.remoteStream)
                                ?.getVideoTracks()
                                .isEmpty !=
                            false
                    ? null
                    : (enabled) => _virtualWork(() async {
                        if (enabled) {
                          if (!_cameraInstalled) {
                            await _virtual.setCameraInstalled(true);
                          }
                          if (!mounted || !_service.active) return;
                          _virtual.startCamera(_renderer.textureId!, fps: _fps);
                        } else {
                          _virtual.stopCamera();
                        }
                      }),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _virtualBusy
                        ? null
                        : () => _virtualWork(
                            () =>
                                _virtual.setCameraInstalled(!_cameraInstalled),
                          ),
                    icon: Icon(
                      _cameraInstalled
                          ? Icons.videocam_off_outlined
                          : Icons.add_a_photo_outlined,
                    ),
                    label: Text(
                      _cameraInstalled
                          ? t('حذف وبکم مجازی', 'Remove virtual webcam')
                          : t('ثبت وبکم Localist', 'Register Localist webcam'),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _virtualBusy ? null : _refreshVirtualDevices,
                    icon: const Icon(Icons.refresh),
                    label: Text(t('تازه‌سازی دستگاه‌ها', 'Refresh devices')),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey(
                  'virtual-audio-${_virtual.microphoneOutput}-${_outputs.length}',
                ),
                isExpanded: true,
                initialValue:
                    _outputs.any(
                      (device) => device.deviceId == _virtual.microphoneOutput,
                    )
                    ? _virtual.microphoneOutput
                    : null,
                decoration: InputDecoration(
                  labelText: t(
                    'ارسال صدای دریافتی به ورودی مجازی',
                    'Route received audio to a virtual input',
                  ),
                ),
                items: [
                  for (final device in _outputs)
                    DropdownMenuItem(
                      value: device.deviceId,
                      child: Text(
                        device.label,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged:
                    _virtualBusy ||
                        !_service.receiving ||
                        _service.remoteStream?.getAudioTracks().isEmpty != false
                    ? null
                    : (id) => _virtualWork(() async {
                        if (id != null) {
                          await _virtual.routeMicrophone(id);
                          await _service.setPlaybackMuted(false);
                        }
                      }),
              ),
              Text(
                t(
                  'برای میکروفون، اینجا CABLE Input و در برنامهٔ مقصد CABLE Output را انتخاب کنید. صدای گوشی مستقیم ارسال می‌شود؛ OBS لازم نیست.',
                  'For microphone input, choose CABLE Input here and CABLE Output in the target app. Phone audio is routed directly; OBS is not required.',
                ),
              ),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: _virtualBusy ? null : _installMicrophone,
                    icon: const Icon(Icons.mic_external_on),
                    label: Text(
                      t('نصب درایور میکروفون', 'Install microphone driver'),
                    ),
                  ),
                  if (_virtual.microphoneOutput != null)
                    TextButton(
                      onPressed: () => _virtualWork(_virtual.stopMicrophone),
                      child: Text(
                        t('توقف خروجی میکروفون', 'Stop microphone output'),
                      ),
                    ),
                ],
              ),
              if (_virtualBusy) const LinearProgressIndicator(),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
      ExpansionTile(
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
                '۱. برای Wi-Fi هر دو دستگاه را به یک شبکه وصل کنید. برای کابل، USB tethering گوشی را روشن کنید و لینک همان رابط را در Localist ویندوز باز کنید. اینترنت لازم نیست.\n۲. در ویندوز خروجی وبکم مجازی را روشن و در برنامهٔ مقصد Localist Camera را انتخاب کنید. برای میکروفون، درایور را از همین صفحه نصب و CABLE Input را برای خروجی و CABLE Output را در برنامهٔ مقصد انتخاب کنید.\n۳. استفاده از مرورگر یا OBS همچنان اختیاری است؛ برای OBS یک Browser Source با لینک بسازید و Control audio via OBS را روشن کنید.\n۴. کیفیت و FPS واقعی به سخت‌افزار و شبکه وابسته‌اند. برای ادامه در پس‌زمینه گزینهٔ مربوط را روشن کنید؛ اعلان بی‌صدا و دکمهٔ توقف در دسترس است.',
                '1. Use the same Wi-Fi, or enable phone USB tethering and open its interface link in Localist for Windows. Internet is not needed.\n2. Enable virtual webcam output on Windows and select Localist Camera in the target app. For microphone input, install the driver from this page, choose CABLE Input for output and CABLE Output in the target app.\n3. Browser and OBS reception remain optional; in OBS add a Browser Source with the link and enable Control audio via OBS.\n4. Actual quality/FPS depend on hardware and network. Enable background mode to continue with a silent notification and Stop action.',
              ),
            ),
          ),
        ],
      ),
    ],
  );
}
