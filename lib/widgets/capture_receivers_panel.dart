import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/capture_hub_service.dart';
import '../services/capture_capabilities.dart';
import 'glass.dart';
import 'capture_audio_controls.dart';
import '../services/capture_audio_settings.dart';
import '../l10n/capture_error_text.dart';

class CaptureReceiversPanel extends StatelessWidget {
  const CaptureReceiversPanel({super.key, this.hub, required this.windows});
  final CaptureHubService? hub;
  final bool windows;
  String t(BuildContext context, String fa, String en) =>
      Localizations.localeOf(context).languageCode == 'fa' ? fa : en;
  @override
  Widget build(BuildContext context) => GlassPanel(
    key: const ValueKey('capture-receive-card'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          t(context, 'گیرنده', 'Receive'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            t(
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
              t(
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
              leading: Icon(
                peer.capture.receiving ? Icons.sensors : Icons.sensors_off,
              ),
              title: Text(
                peer.advertisement.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${peer.advertisement.model} · ${peer.online ? t(context, 'آنلاین', 'Online') : t(context, 'آفلاین', 'Offline')}\n${windows ? [if (peer.advertisement.camera) t(context, 'دوربین مجازی لوکالیست ${peer.slot + 1}', 'Localist Camera ${peer.slot + 1}'), if (peer.advertisement.microphone) peer.output.microphoneName.isEmpty ? t(context, 'در انتظار کابل مستقل', 'Waiting for an independent cable') : peer.output.microphoneName].join(' · ') : t(context, 'گیرنده', 'Receiver')}',
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
                          tooltip: t(context, 'قطع/وصل تصویر', 'Toggle video'),
                          isSelected: peer.video,
                          icon: const Icon(Icons.videocam_off_outlined),
                          selectedIcon: const Icon(Icons.videocam_outlined),
                          onPressed: () =>
                              hub!.configure(peer, video: !peer.video),
                        ),
                      if (peer.advertisement.microphone)
                        IconButton.filledTonal(
                          tooltip: t(
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
                      IconButton.filledTonal(
                        tooltip: t(
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
  Future<void> _settings(
    BuildContext context,
    CaptureReceiver peer,
  ) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => AnimatedBuilder(
      animation: Listenable.merge([peer.capture, ?hub]),
      builder: (context, _) {
        final state = peer.capture.captureControlState;
        final available = state['enabled'] == true;
        final capabilities = CaptureCapabilities.fromMap(state);
        final selectedMode = capabilities.modes
            .where(
              (m) => m.width == state['width'] && m.height == state['height'],
            )
            .firstOrNull;
        Future<void> change(Map<String, dynamic> command) async {
          try {
            await peer.capture.requestCaptureControl(command);
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(captureErrorText(context, '$e'))),
              );
            }
          }
        }

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  peer.advertisement.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Text(
                  available
                      ? t(
                          context,
                          'کنترل فرستندهٔ همین دستگاه',
                          'Controls for this sender',
                        )
                      : t(
                          context,
                          'تنظیمات پس از برقراری اتصال آماده می‌شوند.',
                          'Settings become available after the sender connects.',
                        ),
                ),
                const SizedBox(height: 16),
                if (peer.advertisement.microphone)
                  Text(
                    t(context, 'خروجی گیرنده', 'Receiver output'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                if (peer.advertisement.microphone)
                  CaptureAudioControls(
                    settings: peer.output.audioSettings,
                    windows: windows,
                    loadDevices: peer.output.microphoneStatus,
                    onChanged: (value) => hub!.configure(
                      peer,
                      audioSettings: value,
                      audioEndpoint: value.outputMode == 'mic'
                          ? value.outputDevice
                          : null,
                    ),
                  ),
                if (peer.advertisement.microphone &&
                    peer.output.audioDiagnostics.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      '${t(context, 'نمونه‌های دریافت‌شده', 'Received samples')}: ${peer.output.audioDiagnostics['frames'] ?? 0}\n'
                      '${t(context, 'بافر', 'Buffer')}: ${((peer.output.audioDiagnostics['bufferedFrames'] as num? ?? 0) / 48).round()} ${t(context, 'میلی‌ثانیه', 'ms')} · '
                      '${t(context, 'افت بافر', 'Underruns')}: ${peer.output.audioDiagnostics['underruns'] ?? 0} · '
                      '${t(context, 'نمونه‌های حذف‌شده', 'Dropped samples')}: ${peer.output.audioDiagnostics['droppedFrames'] ?? 0}',
                    ),
                  ),
                const Divider(height: 32),
                Text(
                  t(context, 'تنظیمات فرستنده', 'Sender settings'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                if (peer.advertisement.camera) ...[
                  if (state.keys.any(
                    (k) =>
                        k.startsWith('camera') &&
                        int.tryParse(k.substring(6)) != null,
                  ))
                    DropdownButtonFormField<int>(
                      isExpanded: true,
                      key: ValueKey(
                        'receiver-camera-${state['selectedCamera']}',
                      ),
                      initialValue: (state['selectedCamera'] as int? ?? -1) >= 0
                          ? state['selectedCamera'] as int
                          : null,
                      decoration: InputDecoration(
                        labelText: t(context, 'انتخاب دوربین', 'Camera input'),
                      ),
                      items: [
                        for (var i = 0; i < 12; i++)
                          if (state['camera$i'] is String)
                            DropdownMenuItem(
                              value: i,
                              child: Text(
                                state['camera$i'] as String,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                      ],
                      onChanged: available
                          ? (value) => change({'camera': value})
                          : null,
                    ),
                  DropdownButtonFormField<String>(
                    key: ValueKey(
                      'receiver-orientation-${state['orientation']}',
                    ),
                    isExpanded: true,
                    initialValue:
                        [
                          'auto',
                          'portrait',
                          'landscape',
                        ].contains(state['orientation'])
                        ? state['orientation'] as String
                        : 'landscape',
                    decoration: InputDecoration(
                      labelText: t(
                        context,
                        'جهت ویدیوی ارسالی',
                        'Outgoing video orientation',
                      ),
                    ),
                    items: [
                      for (final e in {
                        'auto': t(context, 'خودکار', 'Automatic'),
                        'landscape': t(context, 'قفل افقی', 'Lock landscape'),
                        'portrait': t(context, 'قفل عمودی', 'Lock portrait'),
                      }.entries)
                        DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ],
                    onChanged: available
                        ? (value) => change({'orientation': value})
                        : null,
                  ),
                  DropdownButtonFormField<String>(
                    key: ValueKey('receiver-mode-${selectedMode?.key}'),
                    isExpanded: true,
                    initialValue: selectedMode?.key,
                    decoration: InputDecoration(
                      labelText: t(
                        context,
                        'رزولوشن دوربین',
                        'Camera resolution',
                      ),
                    ),
                    items: [
                      for (final mode in capabilities.modes)
                        DropdownMenuItem(
                          value: mode.key,
                          child: Text(
                            mode.label,
                            textDirection: TextDirection.ltr,
                          ),
                        ),
                    ],
                    onChanged: !available
                        ? null
                        : (key) {
                            final mode = capabilities.modes.firstWhere(
                              (m) => m.key == key,
                            );
                            change({
                              'width': mode.width,
                              'height': mode.height,
                              'fps':
                                  ((state['fps'] as num?)?.toInt() ??
                                          mode.maxFps)
                                      .clamp(mode.minFps, mode.maxFps),
                            });
                          },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    key: ValueKey(
                      'receiver-fps-${state['fps']}-${selectedMode?.key}',
                    ),
                    isExpanded: true,
                    initialValue:
                        selectedMode?.frameRates.contains(state['fps']) == true
                        ? state['fps'] as int
                        : null,
                    decoration: InputDecoration(
                      labelText: t(context, 'نرخ فریم', 'Frame rate'),
                    ),
                    items: [
                      for (final fps in selectedMode?.frameRates ?? <int>[])
                        DropdownMenuItem(
                          value: fps,
                          child: Text(
                            t(context, '$fps فریم در ثانیه', '$fps FPS'),
                          ),
                        ),
                    ],
                    onChanged: !available
                        ? null
                        : (value) => change({'fps': value}),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: ValueKey('receiver-bitrate-${state['bitrate']}'),
                    initialValue: '${state['bitrate'] ?? ''}',
                    enabled: available,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: t(
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
                    const SizedBox(height: 12),
                    Text(t(context, 'بزرگ‌نمایی دوربین', 'Camera zoom')),
                    _CaptureZoomControl(
                      maximum: (state['maxZoom'] as num).toDouble() / 100,
                      value: ((state['zoom'] as num? ?? 100).toDouble() / 100)
                          .clamp(1, (state['maxZoom'] as num).toDouble() / 100),
                      onChanged: available
                          ? (value) => change({'zoom': value})
                          : null,
                    ),
                  ],
                  if (state['torchAvailable'] == true)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(t(context, 'چراغ دوربین', 'Camera light')),
                      value: state['torch'] == true,
                      onChanged: available
                          ? (value) => change({'torch': value})
                          : null,
                    ),
                ],
                if (peer.advertisement.microphone &&
                    state['audioSource'] != 'system')
                  if (state.keys.any(
                    (k) =>
                        k.startsWith('microphone') &&
                        int.tryParse(k.substring(10)) != null,
                  ))
                    DropdownButtonFormField<int>(
                      isExpanded: true,
                      key: ValueKey(
                        'receiver-microphone-${state['selectedMicrophone']}',
                      ),
                      initialValue:
                          (state['selectedMicrophone'] as int? ?? -1) >= 0
                          ? state['selectedMicrophone'] as int
                          : null,
                      decoration: InputDecoration(
                        labelText: t(
                          context,
                          'انتخاب میکروفون',
                          'Microphone input',
                        ),
                      ),
                      items: [
                        for (var i = 0; i < 12; i++)
                          if (state['microphone$i'] is String)
                            DropdownMenuItem(
                              value: i,
                              child: Text(
                                state['microphone$i'] as String,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                      ],
                      onChanged: available
                          ? (value) => change({'microphone': value})
                          : null,
                    ),
                if (peer.advertisement.microphone)
                  CaptureAudioControls(
                    settings: CaptureAudioSettings.fromMap(state),
                    sender: true,
                    windows: windows,
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
              ],
            ),
          ),
        );
      },
    ),
  );
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
