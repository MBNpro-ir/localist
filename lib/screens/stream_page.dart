import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/media_stream_service.dart';
import '../services/stream_discovery_service.dart';
import '../services/native_bridge_service.dart';
import '../services/feature_permission_service.dart';
import '../services/log_service.dart';
import '../widgets/glass.dart';
import 'localist_qr_scanner.dart';

class StreamPage extends StatefulWidget {
  const StreamPage({super.key, required this.service, this.receiving = false});
  final MediaStreamService service;
  final bool receiving;
  @override
  State<StreamPage> createState() => _StreamPageState();
}

class _StreamPageState extends State<StreamPage> {
  bool _busy = false;
  final _receiveAddress = TextEditingController();
  bool _addressError = false;
  bool _scanningQr = false;
  MediaStreamService get service => widget.service;
  bool get _supportsQr => switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => true,
    _ => false,
  };
  String _t(String fa, String en) =>
      Localizations.localeOf(context).languageCode == 'fa' ? fa : en;

  @override
  void dispose() {
    _receiveAddress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.receiving ? _buildReceiver() : _buildSharer();

  Widget _buildSharer() => ListenableBuilder(
    listenable: service,
    builder: (context, _) {
      final url = service.playerUrl;
      final address = url == null ? null : Uri.parse(url).authority;
      return PageSurface(
        useColumns: false,
        children: [
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 16,
              children: [
                Text(
                  _t('استریم رسانه', 'Media Stream'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (url != null && address != null) ...[
                  Center(
                    child: QrImageView(
                      data: url,
                      size: 174,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: SelectableText(
                            address,
                            textDirection: TextDirection.ltr,
                          ),
                        ),
                        IconButton(
                          tooltip: _t('کپی آدرس استریم', 'Copy stream address'),
                          onPressed: () =>
                              Clipboard.setData(ClipboardData(text: address)),
                          icon: const Icon(Icons.copy),
                        ),
                      ],
                    ),
                  ),
                ] else if (service.active)
                  Text(
                    _t(
                      'آدرس شبکهٔ محلی پیدا نشد. اتصال شبکه را بررسی کنید.',
                      'No local network address found. Check your network connection.',
                    ),
                  )
                else
                  Text(
                    _t(
                      'برای شروع فایل انتخاب کنید.',
                      'Choose a file to start.',
                    ),
                  ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _busy ? null : () => unawaited(_pick()),
                      icon: const Icon(Icons.video_library_outlined),
                      label: Text(_t('انتخاب رسانه‌ها', 'Choose media files')),
                    ),
                    if (service.active)
                      OutlinedButton.icon(
                        onPressed: _busy ? null : () => unawaited(_stop()),
                        icon: const Icon(Icons.stop_circle_outlined),
                        label: Text(_t('توقف اشتراک', 'Stop sharing')),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      );
    },
  );

  Widget _buildReceiver() => PageSurface(
    useColumns: false,
    children: [
      GlassPanel(
        child: ListenableBuilder(
          listenable: service.discovery,
          builder: (context, _) {
            final discovery = service.discovery;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _t('استریم‌های نزدیک', 'Nearby streams'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: _t('جست‌وجوی دوباره', 'Search again'),
                      onPressed: discovery.scanning
                          ? null
                          : () => unawaited(discovery.refresh()),
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
                if (discovery.scanning)
                  const LinearProgressIndicator()
                else if (discovery.addresses.isEmpty)
                  Text(
                    _t(
                      'استریمی پیدا نشد. دستگاه فرستنده باید به همین شبکه وصل باشد.',
                      'No streams found. Connect the sharing device to this network.',
                    ),
                  ),
                for (final uri in discovery.addresses)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.video_library_outlined),
                    title: Text(
                      '${uri.host}:${uri.port}',
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.start,
                    ),
                    trailing: const Icon(Icons.open_in_browser),
                    onTap: () => unawaited(_openReceivedStream(uri)),
                  ),
              ],
            );
          },
        ),
      ),
      GlassPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _t('دریافت استریم', 'Receive a stream'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _receiveAddress,
              keyboardType: TextInputType.url,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: _t('آدرس استریم', 'Stream address'),
                hintText: '192.168.1.20:$mediaStreamPort',
                errorText: _addressError
                    ? _t(
                        'آدرس استریم را بررسی کنید.',
                        'Check the stream address.',
                      )
                    : null,
              ),
              onChanged: (_) {
                if (_addressError) setState(() => _addressError = false);
              },
              onSubmitted: (_) => unawaited(_openReceivedStream()),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => unawaited(_openReceivedStream()),
                  icon: const Icon(Icons.open_in_browser),
                  label: Text(_t('باز کردن در مرورگر', 'Open in browser')),
                ),
                if (_supportsQr)
                  OutlinedButton.icon(
                    onPressed: _scanningQr ? null : () => unawaited(_scanQr()),
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    label: Text(_t('اسکن کد QR', 'Scan QR code')),
                  ),
              ],
            ),
          ],
        ),
      ),
    ],
  );

  Future<void> _scanQr() async {
    setState(() => _scanningQr = true);
    try {
      final value = await scanLocalistQr(
        context,
        title: _t('اسکن کد QR استریم', 'Scan stream QR'),
        accepts: (value) => parseStreamAddress(value, fromQr: true) != null,
      );
      if (mounted && widget.receiving && value != null) {
        final uri = parseStreamAddress(value, fromQr: true);
        if (uri != null) await _openReceivedStream(uri);
      }
    } finally {
      if (mounted) setState(() => _scanningQr = false);
    }
  }

  Future<void> _openReceivedStream([Uri? found]) async {
    final uri = found ?? parseStreamAddress(_receiveAddress.text);
    if (uri == null) {
      setState(() => _addressError = true);
      return;
    }
    if (_addressError) setState(() => _addressError = false);
    final opened = await NativeBridgeService.instance.openUri(uri.toString());
    if (!opened && mounted && widget.receiving) {
      _showNotice(_t('مرورگر باز نشد.', 'Could not open the browser.'));
    }
  }

  Future<void> _stop() async {
    setState(() => _busy = true);
    try {
      await service.stop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showNotice(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pick() async {
    LogService.instance.debug('Stream page: media picker opened');
    setState(() => _busy = true);
    try {
      final hasNetworkAccess = await FeaturePermissionService.instance.ensure([
        FeatureAccess.localNetwork,
      ]);
      if (!hasNetworkAccess || !mounted || widget.receiving) {
        return;
      }
      final result = await FilePicker.pickFiles();
      final files = [
        for (final item in result)
          if (item.path != null) File(item.path!),
      ];
      LogService.instance.debug(
        'Stream page: picker returned files=${files.length}',
      );
      if (files.isEmpty || !mounted || widget.receiving) return;
      service.persian = Localizations.localeOf(context).languageCode == 'fa';
      await service.startFiles(files);
      LogService.instance.debug(
        'Stream page: media service started items=${service.items.length}',
      );
    } on SocketException {
      if (mounted) {
        _showNotice(
          _t(
            'استریم روی پورت $mediaStreamPort شروع نشد. آزاد بودن پورت و اتصال شبکه را بررسی کنید.',
            'Could not start Stream on port $mediaStreamPort. Check the network and port availability.',
          ),
        );
      }
    } catch (error) {
      LogService.instance.debug(
        'Stream page: media picker/start failed type=${error.runtimeType}',
      );
      if (mounted) {
        _showNotice(
          _t(
            'رسانه انتخاب یا پخش نشد. فایل‌ها و دسترسی به آن‌ها را بررسی کنید.',
            'Could not select or share the media. Check the files and their permissions.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
