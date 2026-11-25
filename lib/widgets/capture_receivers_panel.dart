import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/capture_hub_service.dart';
import '../services/capture_capabilities.dart';
import 'glass.dart';
import 'capture_audio_controls.dart';
import 'capture_microphone_mode.dart';
import '../services/capture_audio_settings.dart';
import '../l10n/capture_error_text.dart';

String _text(BuildContext context, String fa, String en) =>
    Localizations.localeOf(context).languageCode == 'fa' ? fa : en;

class CaptureReceiversPanel extends StatelessWidget {
  const CaptureReceiversPanel({super.key, this.hub, required this.windows});
  final CaptureHubService? hub;
  final bool windows;
  @override
  Widget build(BuildContext context) => GlassPanel(
    key: const ValueKey('capture-receive-card'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _text(context, 'گیرنده', 'Receive'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            _text(
              context,
              'دریافت خودکار تا چهار دستگاه در شبکه فعال است.',
              'Automatic reception is active for up to four devices.',
            ),
          ),
        ),
        if (hub?.error.isNotEmpty == true)
          Text(captureErrorText(context, hub!.error)),
        if (hub?.receivers.isEmpty != false)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              _text(
                context,
                'روی دستگاه دیگر اشتراک دوربین یا میکروفون را شروع کنید؛ دریافت خودکار انجام می‌شود.',
                'Start camera or microphone sharing on another device. Reception starts automatically.',
              ),
            ),
          ),
        for (final peer in hub?.receivers ?? <CaptureReceiver>[])
          Card(
            margin: const EdgeInsets.symmetric(vertical: 6),
            child: ExpansionTile(
              key: ValueKey('capture-peer-${peer.advertisement.id}'),
              initiallyExpanded: windows,
              leading: Icon(
                peer.capture.receiving ? Icons.sensors : Icons.sensors_off,
              ),
              title: Text(
                peer.advertisement.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${peer.advertisement.model} · ${peer.online ? _text(context, 'آنلاین', 'Online') : _text(context, 'آفلاین', 'Offline')}\n${windows ? [if (peer.advertisement.camera) _text(context, 'دوربین مجازی لوکالیست ${peer.slot + 1}', 'Localist Camera ${peer.slot + 1}'), if (peer.advertisement.microphone) peer.output.microphoneName.isEmpty ? _text(context, 'در انتظار کابل مستقل', 'Waiting for an independent cable') : peer.output.microphoneName].join(' · ') : _text(context, 'گیرنده', 'Receiver')}',
                maxLines: 3,
              ),
              trailing: Switch.adaptive(
                value: peer.enabled,
                onChanged: (value) => hub!.configure(peer, enabled: value),
              ),
              children: [
                if (peer.advertisement.camera &&
                    peer.ready &&
                    peer.video &&
                    peer.capture.remoteStream?.getVideoTracks().isNotEmpty ==
                        true)
                  SizedBox(
                    height: 180,
                    child: RTCVideoView(
                      peer.renderer,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (peer.advertisement.camera)
                        IconButton.filledTonal(
                          tooltip: _text(
                            context,
                            'قطع/وصل تصویر',
                            'Toggle video',
                          ),
                          isSelected: peer.video,
                          icon: const Icon(Icons.videocam_off_outlined),
                          selectedIcon: const Icon(Icons.videocam_outlined),
                          onPressed: () =>
                              hub!.configure(peer, video: !peer.video),
                        ),
                      if (peer.advertisement.microphone)
                        IconButton.filledTonal(
                          tooltip: _text(
                            context,
                            'قطع/وصل صدای این دستگاه',
                            'Toggle this device audio',
                          ),
                          isSelected: peer.audio,
                          icon: const Icon(Icons.mic_off_outlined),
                          selectedIcon: const Icon(Icons.mic_outlined),
                          onPressed: () =>
                              hub!.configure(peer, audio: !peer.audio),
                        ),
                      if (!windows)
                        IconButton.filledTonal(
                          tooltip: _text(
                            context,
                            'تنظیمات همین دستگاه',
                            'This device settings',
                          ),
                          icon: const Icon(Icons.tune),
                          onPressed: () => _settings(context, peer),
                        ),
                    ],
                  ),
                ),
                if (windows)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                    child: _CapturePeerSettings(
                      peer: peer,
                      hub: hub!,
                      windows: true,
                    ),
                  ),
                if (peer.outputError.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(captureErrorText(context, peer.outputError)),
                  ),
                if (peer.error.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(captureErrorText(context, peer.error)),
                  ),
              ],
            ),
          ),
      ],
    ),
  );
  Future<void> _settings(BuildContext context, CaptureReceiver peer) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  peer.advertisement.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                _CapturePeerSettings(peer: peer, hub: hub!, windows: false),
              ],
            ),
          ),
        ),
      );
}

class _CapturePeerSettings extends StatefulWidget {
  const _CapturePeerSettings({
    required this.peer,
    required this.hub,
    required this.windows,
  });

  final CaptureReceiver peer;
  final CaptureHubService hub;
  final bool windows;

  @override
  State<_CapturePeerSettings> createState() => _CapturePeerSettingsState();
}

class _CapturePeerSettingsState extends State<_CapturePeerSettings> {
  bool _changing = false;

  Future<void> change(Map<String, dynamic> command) async {
    if (_changing) return;
    setState(() => _changing = true);
    try {
      await widget.peer.capture.requestCaptureControl(command);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(captureErrorText(context, '$error'))),
        );
      }
    } finally {
      if (mounted) setState(() => _changing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final peer = widget.peer;
    final windows = widget.windows;
    return ListenableBuilder(
      listenable: windows
          ? peer.capture
          : Listenable.merge([peer.capture, widget.hub]),
      builder: (context, _) {
        final state = peer.capture.captureControlState;
        final ready = state['enabled'] == true;
        final available = ready && !_changing;
        final senderSections = [
          if (peer.advertisement.camera)
            _section(
              context,
              Icons.videocam_outlined,
              _text(context, 'دوربین گوشی', 'Phone camera'),
              _cameraControls(context, state, available),
            ),
          if (peer.advertisement.microphone)
            _section(
              context,
              Icons.mic_outlined,
              _text(context, 'صدای گوشی', 'Phone audio'),
              _audioControls(context, state, available),
            ),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: [
            if (!ready && !_changing)
              Text(
                _text(
                  context,
                  'تنظیمات پس از برقراری اتصال آماده می‌شوند.',
                  'Settings become available after the sender connects.',
                ),
              ),
            if (senderSections.isNotEmpty)
              LayoutBuilder(
                builder: (context, bounds) {
                  final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
                  if (windows &&
                      senderSections.length > 1 &&
                      bounds.maxWidth / scale >= 650) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 16,
                      children: [
                        for (final section in senderSections)
                          Expanded(child: section),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 16,
                    children: senderSections,
                  );
                },
              ),
            if (peer.advertisement.microphone)
              _section(
                context,
                Icons.speaker_outlined,
                _text(
                  context,
                  'خروجی صدا در این دستگاه',
                  'Receiver audio output',
                ),
                [
                  CaptureAudioControls(
                    settings: peer.output.audioSettings,
                    windows: windows,
                    loadDevices: peer.output.microphoneStatus,
                    onChanged: (value) => widget.hub.configure(
                      peer,
                      audioSettings: value,
                      audioEndpoint: value.outputMode == 'mic'
                          ? value.outputDevice
                          : null,
                    ),
                  ),
                  if (peer.output.audioDiagnostics.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        '${_text(context, 'نمونه‌های دریافت‌شده', 'Received samples')}: ${peer.output.audioDiagnostics['frames'] ?? 0}\n'
                        '${_text(context, 'بافر', 'Buffer')}: ${((peer.output.audioDiagnostics['bufferedFrames'] as num? ?? 0) / 48).round()} ${_text(context, 'میلی‌ثانیه', 'ms')} · '
                        '${_text(context, 'افت بافر', 'Underruns')}: ${peer.output.audioDiagnostics['underruns'] ?? 0} · '
                        '${_text(context, 'نمونه‌های حذف‌شده', 'Dropped samples')}: ${peer.output.audioDiagnostics['droppedFrames'] ?? 0}',
                      ),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }

  List<Widget> _cameraControls(
    BuildContext context,
    Map<String, dynamic> state,
    bool available,
  ) {
    final capabilities = CaptureCapabilities.fromMap(state);
    final selectedMode = capabilities.modes
        .where(
          (mode) =>
              mode.width == state['width'] && mode.height == state['height'],
        )
        .firstOrNull;
    return [
      ?_inputSelector(
        state,
        field: 'camera',
        selected: 'selectedCamera',
        label: _text(context, 'انتخاب دوربین', 'Camera input'),
        available: available,
      ),
      DropdownButtonFormField<String>(
        key: ValueKey('receiver-mode-${selectedMode?.key}'),
        isExpanded: true,
        initialValue: selectedMode?.key,
        decoration: InputDecoration(
          labelText: _text(context, 'رزولوشن دوربین', 'Camera resolution'),
        ),
        items: [
          for (final mode in capabilities.modes)
            DropdownMenuItem(
              value: mode.key,
              child: Text(mode.label, textDirection: TextDirection.ltr),
            ),
        ],
        onChanged: !available
            ? null
            : (key) {
                final mode = capabilities.modes.firstWhere((m) => m.key == key);
                change({
                  'width': mode.width,
                  'height': mode.height,
                  'fps': ((state['fps'] as num?)?.toInt() ?? mode.maxFps).clamp(
                    mode.minFps,
                    mode.maxFps,
                  ),
                });
              },
      ),
      DropdownButtonFormField<int>(
        key: ValueKey('receiver-fps-${state['fps']}-${selectedMode?.key}'),
        isExpanded: true,
        initialValue: selectedMode?.frameRates.contains(state['fps']) == true
            ? state['fps'] as int
            : null,
        decoration: InputDecoration(
          labelText: _text(context, 'نرخ فریم', 'Frame rate'),
        ),
        items: [
          for (final fps in selectedMode?.frameRates ?? <int>[])
            DropdownMenuItem(
              value: fps,
              child: Text(_text(context, '$fps فریم در ثانیه', '$fps FPS')),
            ),
        ],
        onChanged: !available ? null : (value) => change({'fps': value}),
      ),
      TextFormField(
        key: ValueKey('receiver-bitrate-${state['bitrate']}'),
        initialValue: '${state['bitrate'] ?? ''}',
        enabled: available,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: _text(
            context,
            'بیت‌ریت تصویر (کیلوبیت در ثانیه)',
            'Video bitrate (kb/s)',
          ),
        ),
        onFieldSubmitted: (value) {
          final rate = int.tryParse(value);
          if (rate != null) change({'bitrate': rate});
        },
      ),
      if ((state['maxZoom'] as num? ?? 100) > 100) ...[
        Text(_text(context, 'بزرگ‌نمایی دوربین', 'Camera zoom')),
        _CaptureZoomControl(
          maximum: (state['maxZoom'] as num).toDouble() / 100,
          value: ((state['zoom'] as num? ?? 100).toDouble() / 100).clamp(
            1,
            (state['maxZoom'] as num).toDouble() / 100,
          ),
          onChanged: available ? (value) => change({'zoom': value}) : null,
        ),
      ],
      if (state['torchAvailable'] == true)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(_text(context, 'چراغ دوربین', 'Camera light')),
          value: state['torch'] == true,
          onChanged: available ? (value) => change({'torch': value}) : null,
        ),
    ];
  }

  List<Widget> _audioControls(
    BuildContext context,
    Map<String, dynamic> state,
    bool available,
  ) => [
    if (state['audioSource'] != 'system')
      ?_inputSelector(
        state,
        field: 'microphone',
        selected: 'selectedMicrophone',
        label: _text(context, 'انتخاب میکروفون', 'Microphone input'),
        available: available,
      ),
    if (state['audioSource'] != 'system' && state['microphoneModes'] is List)
      CaptureMicrophoneMode(
        available: (state['microphoneModes'] as List)
            .whereType<String>()
            .toList(),
        selected: state['microphoneMode'] as String? ?? 'default',
        onChanged: available
            ? (mode) => change({'microphoneMode': mode})
            : null,
      ),
    CaptureAudioControls(
      settings: CaptureAudioSettings.fromMap(state),
      sender: true,
      windows: widget.windows,
      enabled: available,
      echo: state['echo'] == true,
      noise: state['noise'] == true,
      autoGain: state['gain'] == true,
      onEffects: state['audioSource'] == 'system' ? null : change,
      onChanged: (value) => change({
        for (final e in value.toMap().entries)
          if ([
            'audioBitrate',
            'audioGainDb',
            'audioContinuous',
            'audioUncompressed',
          ].contains(e.key))
            e.key: e.value,
      }),
    ),
  ];

  Widget? _inputSelector(
    Map<String, dynamic> state, {
    required String field,
    required String selected,
    required String label,
    required bool available,
  }) {
    final inputs = {
      for (var index = 0; index < 12; index++)
        if (state['$field$index'] case final String name) index: name,
    };
    if (inputs.isEmpty) return null;
    final selectedIndex = state[selected];
    return DropdownButtonFormField<int>(
      isExpanded: true,
      key: ValueKey('receiver-$field-$selectedIndex'),
      initialValue: inputs.containsKey(selectedIndex)
          ? selectedIndex as int
          : null,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final input in inputs.entries)
          DropdownMenuItem(
            value: input.key,
            child: Text(input.value, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: available ? (value) => change({field: value}) : null,
    );
  }

  Widget _section(
    BuildContext context,
    IconData icon,
    String title,
    List<Widget> children,
  ) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            Row(
              spacing: 8,
              children: [
                Icon(icon, size: 20, color: colors.primary),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _CaptureZoomControl extends StatefulWidget {
  const _CaptureZoomControl({
    required this.maximum,
    required this.value,
    this.onChanged,
  });
  final double maximum, value;
  final Future<void> Function(double)? onChanged;
  @override
  State<_CaptureZoomControl> createState() => _CaptureZoomControlState();
}

class _CaptureZoomControlState extends State<_CaptureZoomControl> {
  double? draft;
  @override
  Widget build(BuildContext context) => Slider(
    min: 1,
    max: widget.maximum,
    value: (draft ?? widget.value).clamp(1, widget.maximum),
    label: '${(draft ?? widget.value).toStringAsFixed(1)}×',
    onChanged: widget.onChanged == null
        ? null
        : (value) => setState(() => draft = value),
    onChangeEnd: (value) async {
      await widget.onChanged?.call(value);
      if (mounted) setState(() => draft = null);
    },
  );
}
