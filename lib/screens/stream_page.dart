import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/media_stream_service.dart';
import '../services/dlna_cast_service.dart';
import '../services/native_bridge_service.dart';
import '../widgets/glass.dart';
import '../widgets/feature_page_layout.dart';

class StreamPage extends StatefulWidget {
  const StreamPage({super.key, required this.service});
  final MediaStreamService service;
  @override
  State<StreamPage> createState() => _StreamPageState();
}

class _StreamPageState extends State<StreamPage> {
  final _cast = DlnaCastService();
  DlnaRenderer? _playing;
  bool _busy = false;
  String _notice = '';
  MediaStreamService get service => widget.service;
  @override
  void dispose() {
    _cast.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fa = Localizations.localeOf(context).languageCode == 'fa';
    String t(String f, String e) => fa ? f : e;
    return GlassBackground(
      simple: Platform.isAndroid || Platform.isWindows,
      child: AnimatedBuilder(
        animation: Listenable.merge([service, _cast]),
        builder: (context, _) => FeaturePageLayout(
          heading: [
            Text(
              t('استریم رسانه', 'Media Stream'),
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              t(
                'یک فایل را روی شبکهٔ محلی پخش کنید و لینک آن را در تلویزیون، کنسول، گوشی یا نمایشگر بی‌سیم باز کنید.',
                'Play media on a local DLNA receiver or in a phone, TV or console browser.',
              ),
            ),
          ],
          sections: [
            GlassPanel(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t('پخش‌کنندهٔ وب', 'Web player'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    t(
                      'فایل را انتخاب کنید تا پورت وب باز شود. دستگاه مقابل با آدرس یا QR زیر وارد صفحهٔ پخش می‌شود و کنترل پخش، زمان، صدا و تمام‌صفحه را دارد.',
                      'Choose a file to open the web port. Other devices can use the URL or QR to play, seek, change volume and enter fullscreen.',
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => unawaited(_pick(context)),
                    icon: const Icon(Icons.video_library_outlined),
                    label: Text(t('انتخاب فایل رسانه', 'Choose media file')),
                  ),
                  if (service.active) ...[
                    const SizedBox(height: 16),
                    Text(
                      service.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      t(
                        'پورت وب باز است: ${service.port}',
                        'Web port is open: ${service.port}',
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.language, size: 22),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            t(
                              'پخش‌کنندهٔ وب برای دستگاه‌های دیگر',
                              'Web player for other devices',
                            ),
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: () => unawaited(_openPlayer()),
                          icon: const Icon(Icons.open_in_browser),
                          label: Text(t('باز کردن وب', 'Open web')),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (service.playerUrls.isEmpty)
                      Text(
                        t(
                          'شبکهٔ محلی پیدا نشد. ابتدا Wi-Fi یا کابل شبکه را وصل کنید.',
                          'No local network found. Connect Wi-Fi or Ethernet first.',
                        ),
                      ),
                    if (service.playerUrls.isNotEmpty)
                      QrImageView(
                        data: service.playerUrls.first,
                        size: 190,
                        backgroundColor: Colors.white,
                      ),
                    for (final url in service.playerUrls)
                      Row(
                        children: [
                          Expanded(child: SelectableText(url)),
                          IconButton(
                            tooltip: t('کپی لینک', 'Copy link'),
                            onPressed: () =>
                                Clipboard.setData(ClipboardData(text: url)),
                            icon: const Icon(Icons.copy),
                          ),
                        ],
                      ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: () => unawaited(_openPlayer()),
                          icon: const Icon(Icons.play_circle_outline),
                          label: Text(t('صفحهٔ پخش وب', 'Web player page')),
                        ),
                        OutlinedButton.icon(
                          onPressed: service.playerUrl == null
                              ? null
                              : () => Clipboard.setData(
                                  ClipboardData(text: service.playerUrl!),
                                ),
                          icon: const Icon(Icons.link),
                          label: Text(t('کپی آدرس پخش', 'Copy player URL')),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => unawaited(service.stop()),
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: Text(t('توقف', 'Stop')),
                    ),
                  ] else
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Text(
                        t(
                          'برای شروع فایل انتخاب کنید.',
                          'Choose a file to start.',
                        ),
                      ),
                    ),
                ],
              ),
            ),
            GlassPanel(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t('تلویزیون و گیرندهٔ DLNA', 'TVs and DLNA receivers'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: _cast.scanning
                        ? null
                        : () => unawaited(_cast.discover()),
                    icon: Icon(
                      _cast.scanning ? Icons.hourglass_top : Icons.search,
                    ),
                    label: Text(t('جستجوی دستگاه‌ها', 'Find receivers')),
                  ),
                  if (!_cast.scanning && _cast.devices.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        t(
                          'گیرندهٔ DLNA را روشن و به همین شبکه وصل کنید؛ اگر دستگاه مرورگر دارد می‌توانید QR را هم باز کنید.',
                          'Turn on a DLNA receiver on the same network. Devices with a browser can use the QR instead.',
                        ),
                      ),
                    ),
                  for (final device in _cast.devices)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.tv),
                      title: Text(device.name),
                      subtitle: Text(device.controlUrl.host),
                      trailing: FilledButton(
                        onPressed:
                            !service.active || _busy || service.urls.isEmpty
                            ? null
                            : () => unawaited(_play(device)),
                        child: Text(t('پخش', 'Play')),
                      ),
                    ),
                  if (_playing != null)
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final action in ['Pause', 'Play', 'Stop'])
                          OutlinedButton(
                            onPressed: _busy
                                ? null
                                : () => unawaited(_control(action)),
                            child: Text(action),
                          ),
                      ],
                    ),
                  if (_notice.isNotEmpty || _cast.error.isNotEmpty)
                    Text(_notice.isNotEmpty ? _notice : _cast.error),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => unawaited(_wirelessDisplay()),
              icon: const Icon(Icons.connected_tv),
              label: Text(
                t('انتقال کل صفحه / Miracast', 'Mirror screen / Miracast'),
              ),
            ),
            GlassPanel(
              padding: const EdgeInsets.all(18),
              child: Text(
                t(
                  'ارسال DLNA به گیرندهٔ MediaRenderer با AVTransport نیاز دارد. پخش در مرورگر به کدک‌های دستگاه وابسته است؛ MP4 با H.264/AAC معمولاً سازگار است. انتقال کل صفحه پنل اتصال سیستم‌عامل را باز می‌کند و به سخت‌افزار سازگار نیاز دارد. پروتکل‌های AirPlay و Chromecast در این نسخه پیاده‌سازی نشده‌اند.',
                  'DLNA casting requires a MediaRenderer with AVTransport. Browser playback depends on supported codecs; MP4 H.264/AAC is widely compatible. Screen mirroring opens the OS connection panel and requires compatible hardware. AirPlay and Chromecast protocols are not implemented in this build.',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final result = await FilePicker.pickFiles(type: FileType.any);
    final path = result.isEmpty ? null : result.single.path;
    if (path == null || !context.mounted) return;
    try {
      await service.start(File(path));
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _openPlayer() async {
    final url = service.playerUrl;
    if (url == null) return;
    final opened = await NativeBridgeService.instance.openUri(url);
    if (!opened && mounted) {
      setState(
        () => _notice =
            'صفحهٔ وب روی این دستگاه باز نشد؛ آدرس را با دکمهٔ کپی در مرورگر وارد کنید.',
      );
    }
  }

  Future<void> _play(DlnaRenderer device) async {
    setState(() {
      _busy = true;
      _notice = '';
    });
    try {
      final destination = device.controlUrl.host.split('.').take(3).join('.');
      final url = service.urls.firstWhere(
        (value) => Uri.parse(value).host.startsWith('$destination.'),
        orElse: () => service.urls.first,
      );
      await _cast.play(device, Uri.parse(url), service.name);
      if (mounted) {
        setState(() {
          _playing = device;
          _notice = 'Playing on ${device.name}';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _notice = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _control(String action) async {
    setState(() => _busy = true);
    try {
      await _cast.action(
        _playing!,
        action,
        action == 'Play' ? {'Speed': '1'} : {},
      );
    } catch (error) {
      if (mounted) setState(() => _notice = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _wirelessDisplay() async {
    final opened = await NativeBridgeService.instance.openWirelessDisplay();
    if (!opened && mounted) {
      setState(
        () => _notice =
            'Wireless display settings are unavailable on this device.',
      );
    }
  }
}
