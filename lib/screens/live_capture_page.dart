import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/live_capture_service.dart';
import '../widgets/glass.dart';

class LiveCapturePage extends StatefulWidget {
  const LiveCapturePage({super.key});
  @override
  State<LiveCapturePage> createState() => _LiveCapturePageState();
}

class _LiveCapturePageState extends State<LiveCapturePage>
    with WidgetsBindingObserver {
  final _service = LiveCaptureService();
  final _renderer = RTCVideoRenderer();
  final _link = TextEditingController();
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
  }

  void _changed() {
    if (_rendererReady) {
      _renderer.srcObject = _service.localStream ?? _service.remoteStream;
    }
    if (mounted) setState(() {});
  }

  Future<void> _run(Future<void> Function() operation) async {
    try {
      if (!_rendererReady) {
        await _renderer.initialize();
        _rendererReady = true;
        _renderer.muted = true;
      }
      await operation();
      _renderer.muted = !_service.receiving;
      _changed();
    } catch (error) {
      if (mounted) setState(() => _notice = '$error');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
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
                onPressed: () => _run(_service.switchCamera),
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
                onPressed: () =>
                    setState(() => _renderer.muted = !_renderer.muted),
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
                    'ادامهٔ انتقال در پس‌زمینه با اعلان توقف',
                    'Continue in background with a Stop notification',
                  ),
                ),
                value: _background,
                onChanged: (v) => setState(() => _background = v),
              ),
              if (_camera) ...[
                SwitchListTile(
                  title: Text(t('دوربین پشت', 'Rear camera')),
                  value: _rear,
                  onChanged: (v) => setState(() => _rear = v),
                ),
                DropdownButtonFormField<int>(
                  isExpanded: true,
                  initialValue: _width,
                  decoration: InputDecoration(
                    labelText: t('وضوح درخواستی', 'Requested resolution'),
                  ),
                  items: [
                    for (final w in [640, 1280, 1920])
                      DropdownMenuItem(
                        value: w,
                        child: Text(
                          w == 640
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
                  isExpanded: true,
                  initialValue: _fps,
                  decoration: InputDecoration(
                    labelText: t('نرخ فریم درخواستی', 'Requested frame rate'),
                  ),
                  items: [
                    for (final fps in [15, 24, 30, 60])
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
                onPressed: _service.busy || (!_camera && !_microphone)
                    ? null
                    : () => _run(
                        () => _service.start(
                          LiveCaptureOptions(
                            background: _background,
                            camera: _camera,
                            microphone: _microphone,
                            rearCamera: _rear,
                            width: _width,
                            height: _width == 640
                                ? 480
                                : _width == 1280
                                ? 720
                                : 1080,
                            fps: _fps,
                            bitrateKbps: _bitrate,
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
                '۱. برای Wi-Fi هر دو دستگاه را به یک شبکه وصل کنید. برای کابل، USB tethering گوشی را روشن کنید و لینک همان رابط را باز کنید. اینترنت لازم نیست.\n۲. در OBS یک Browser Source بسازید و لینک را وارد کنید؛ Control audio via OBS را روشن کنید. برای ارسال تصویر به Zoom/Discord از Start Virtual Camera استفاده کنید.\n۳. دوربین مجازی OBS صدا منتقل نمی‌کند. برای میکروفون در برنامه‌های دیگر، یک دستگاه صوتی مجازی مانند VB-CABLE نصب کنید؛ خروجی monitoring در OBS را CABLE Input و ورودی برنامهٔ مقصد را CABLE Output بگذارید.\n۴. کیفیت و FPS واقعی به سخت‌افزار و شبکه وابسته‌اند. برای ادامه در پس‌زمینه، گزینهٔ مربوط را روشن کنید؛ اعلان فعال و دکمهٔ توقف در دسترس است.',
                '1. Connect both devices to the same Wi-Fi, or enable phone USB tethering and use its interface link. Internet is not needed.\n2. In OBS add a Browser Source with the link and enable Control audio via OBS. Use Start Virtual Camera for Zoom/Discord video.\n3. OBS Virtual Camera carries no audio. For microphone input in other apps, install a virtual audio device such as VB-CABLE: set OBS monitoring to CABLE Input and the target app input to CABLE Output.\n4. Actual quality/FPS depend on hardware and network. Enable background mode to continue with a visible capture notification and Stop action.',
              ),
            ),
          ),
        ],
      ),
    ],
  );
}
