import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/capture_hub_service.dart';
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
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: Text(
            t(
              context,
              'دریافت خودکار دستگاه‌ها',
              'Automatically receive devices',
            ),
          ),
          subtitle: Text(
            t(
              context,
              'تا چهار فرستندهٔ فعال در شبکه؛ بدون لینک و ورود دستی.',
              'Up to four active senders on this network; no links or manual entry.',
            ),
          ),
          value: hub?.enabled ?? true,
          onChanged: hub == null ? null : (value) => hub!.setEnabled(value),
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
                '${peer.advertisement.model} · ${peer.online ? t(context, 'آنلاین', 'Online') : t(context, 'آفلاین', 'Offline')}\n${windows ? 'Localist Camera ${peer.slot + 1}' : t(context, 'گیرنده', 'Receiver')}',
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
                          'برای تغییر کیفیت و سخت‌افزار، فرستنده باید اجازهٔ کنترل گیرنده را روشن کند.',
                          'The sender must allow receiver controls to change capture quality and hardware.',
                        ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  initialValue: [320, 640, 1280, 1920].contains(state['width'])
                      ? state['width'] as int
                      : 1280,
                  decoration: InputDecoration(
                    labelText: t(context, 'وضوح', 'Resolution'),
                  ),
                  items: [
                    for (final width in [320, 640, 1280, 1920])
                      DropdownMenuItem(value: width, child: Text('$width px')),
                  ],
                  onChanged: !available
                      ? null
                      : (value) => change({'width': value}),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: [10, 15, 24, 30, 60].contains(state['fps'])
                      ? state['fps'] as int
                      : 30,
                  decoration: InputDecoration(
                    labelText: t(context, 'نرخ فریم', 'Frame rate'),
                  ),
                  items: [
                    for (final fps in [10, 15, 24, 30, 60])
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
