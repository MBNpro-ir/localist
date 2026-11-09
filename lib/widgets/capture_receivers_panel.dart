import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/capture_hub_service.dart';
import '../services/capture_capabilities.dart';
import 'glass.dart';

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
        if (hub?.error.isNotEmpty == true) Text(hub!.error),
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
                '${peer.advertisement.model} · ${peer.online ? t(context, 'آنلاین', 'Online') : t(context, 'آفلاین', 'Offline')}\n${windows ? 'Localist Camera ${peer.slot + 1} · Localist Microphone ${peer.slot + 1}' : t(context, 'گیرنده', 'Receiver')}',
                maxLines: 3,
              ),
              trailing: Switch.adaptive(
                value: peer.enabled,
                onChanged: (value) => hub!.configure(peer, enabled: value),
              ),
              children: [
                if (peer.ready &&
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
                      IconButton.filledTonal(
                        tooltip: t(context, 'قطع/وصل تصویر', 'Toggle video'),
                        isSelected: peer.video,
                        icon: const Icon(Icons.videocam_off_outlined),
                        selectedIcon: const Icon(Icons.videocam_outlined),
                        onPressed: () =>
                            hub!.configure(peer, video: !peer.video),
                      ),
                      IconButton.filledTonal(
                        tooltip: t(
                          context,
                          'قطع/وصل صدای این دستگاه',
                          'Toggle this device audio',
                        ),
                        isSelected: peer.audio,
                        icon: const Icon(Icons.volume_off_outlined),
                        selectedIcon: const Icon(Icons.volume_up_outlined),
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
                    child: Text(peer.outputError),
                  ),
                if (peer.error.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(peer.error),
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
      animation: peer.capture,
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
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('$e')));
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
                                ((state['fps'] as num?)?.toInt() ?? mode.maxFps)
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
                      DropdownMenuItem(value: fps, child: Text('$fps FPS')),
                  ],
                  onChanged: !available
                      ? null
                      : (value) => change({'fps': value}),
                ),
                for (final entry in {
                  'noise': t(context, 'حذف نویز', 'Noise reduction'),
                  'echo': t(context, 'حذف اکو', 'Echo cancellation'),
                  'gain': t(context, 'تقویت خودکار', 'Automatic gain'),
                }.entries)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(entry.value),
                    value: state[entry.key] == true,
                    onChanged: !available
                        ? null
                        : (value) => change({entry.key: value}),
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
