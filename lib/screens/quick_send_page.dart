import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:qr_flutter/qr_flutter.dart';

import '../l10n/app_localizations.dart';
import '../models/quick_send_settings.dart';
import '../services/apple_web_transfer_service.dart';
import '../services/native_bridge_service.dart';
import '../services/quick_send_service.dart';
import '../widgets/glass.dart';

class QuickSendPage extends StatefulWidget {
  const QuickSendPage({super.key, required this.deviceVpnActive});

  final bool deviceVpnActive;

  @override
  State<QuickSendPage> createState() => _QuickSendPageState();
}

class _QuickSendPageState extends State<QuickSendPage> {
  final QuickSendService _service = QuickSendService.instance;
  final AppleWebTransferService _appleWebTransfer =
      AppleWebTransferService.instance;
  final NativeBridgeService _bridge = NativeBridgeService.instance;
  final List<String> _selectedPaths = [];
  final Map<String, String> _selectedFileNames = {};
  final Set<String> _selectedDeviceIds = {};
  String _selectedText = '';
  bool _sending = false;
  StreamSubscription<List<QuickSendSharedFile>>? _sharedFilesSubscription;

  @override
  void initState() {
    super.initState();
    _sharedFilesSubscription = _bridge.sharedQuickSendFiles.listen(
      _addExternallySharedFiles,
    );
    unawaited(_initializeQuickSend());
  }

  Future<void> _initializeQuickSend() async {
    await _service.initialize();
    await _service.setTransferBlocked(widget.deviceVpnActive);
    if (Platform.isAndroid &&
        _service.settings?.receiveEnabled == true &&
        !_service.storageAccessGranted) {
      await _service.ensureReceiveStorageAccess();
    }
    await _loadExternallySharedFiles();
    if (!widget.deviceVpnActive) {
      await _service.refresh();
    }
  }

  @override
  void didUpdateWidget(covariant QuickSendPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deviceVpnActive != widget.deviceVpnActive) {
      unawaited(_applyVpnTransferState());
    }
  }

  Future<void> _applyVpnTransferState() async {
    final blocked = widget.deviceVpnActive;
    await _service.setTransferBlocked(blocked);
    if (blocked) {
      if (_appleWebTransfer.active || _appleWebTransfer.starting) {
        await _appleWebTransfer.stop();
      }
      return;
    }
    await _service.refresh();
  }

  @override
  void dispose() {
    _sharedFilesSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadExternallySharedFiles() async {
    final files = await _bridge.takeQuickSendSharedFiles();
    await _addExternallySharedFiles(files);
  }

  Future<void> _addExternallySharedFiles(
    List<QuickSendSharedFile> files,
  ) async {
    if (files.isEmpty) {
      return;
    }
    final expanded = <QuickSendSharedFile>[];
    for (final shared in files) {
      final path = shared.path.trim();
      if (path.isEmpty) {
        continue;
      }
      if (File(path).existsSync()) {
        expanded.add(
          QuickSendSharedFile(
            path: path,
            name: shared.name.trim().isEmpty
                ? p.basename(path)
                : shared.name.trim(),
          ),
        );
        continue;
      }
      final directory = Directory(path);
      if (!directory.existsSync()) {
        continue;
      }
      final rootName = shared.name.trim().isEmpty
          ? p.basename(path)
          : shared.name.trim();
      try {
        await for (final entity in directory.list(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is! File) {
            continue;
          }
          final relative = p
              .relative(entity.path, from: path)
              .replaceAll('\\', '/');
          expanded.add(
            QuickSendSharedFile(
              path: entity.path,
              name: p.posix.join(rootName, relative),
            ),
          );
          if (expanded.length >= 5000) {
            break;
          }
        }
      } catch (_) {
        // Keep readable drop items even when one folder cannot be enumerated.
      }
      if (expanded.length >= 5000) {
        break;
      }
    }
    _bridge.consumeQuickSendSharedFiles(files);
    if (expanded.isEmpty || !mounted) {
      return;
    }
    var added = 0;
    setState(() {
      for (final file in expanded) {
        final path = file.path.trim();
        if (path.isEmpty || _selectedPaths.contains(path)) {
          continue;
        }
        _selectedPaths.add(path);
        _selectedFileNames[path] = file.name.trim().isEmpty
            ? p.basename(path)
            : file.name.trim();
        added++;
      }
    });
    _syncAppleSharedContent();
    if (added > 0 && mounted) {
      if (context.l10n.isPersian) {
        _notice(
          '$added \u0641\u0627\u06cc\u0644 \u0628\u0631\u0627\u06cc \u0627\u0631\u0633\u0627\u0644 \u0622\u0645\u0627\u062f\u0647 \u0634\u062f.',
        );
        return;
      }
      _notice(
        _t(
          '$added ÙØ§ÛŒÙ„ Ø¨Ø±Ø§ÛŒ Ø§Ø±Ø³Ø§Ù„ Ø¢Ù…Ø§Ø¯Ù‡ Ø´Ø¯.',
          '$added file${added == 1 ? '' : 's'} ready to send.',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_service, _appleWebTransfer]),
      builder: (context, _) {
        final settings = _service.settings;
        if (settings == null) {
          return PageSurface(
            key: const PageStorageKey<String>('quick-send-page'),
            children: const [
              GlassPanel(child: Center(child: CircularProgressIndicator())),
            ],
          );
        }
        return PageSurface(
          key: const PageStorageKey<String>('quick-send-page'),
          children: [
            if (widget.deviceVpnActive) _vpnWarningPanel(),
            _statusPanel(settings),
            if (_service.pendingRequest case final pending?)
              _pendingPanel(pending),
            _selectionPanel(),
            if (Platform.isAndroid || Platform.isWindows)
              _appleWebTransferPanel(),
            _nearbyPanel(settings),
            if (_service.transfers.isNotEmpty) _transfersPanel(),
          ],
        );
      },
    );
  }

  Widget _vpnWarningPanel() {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        border: Border.all(color: colors.error, width: 1.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.vpn_lock_outlined, color: colors.error),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _t('VPN دستگاه را خاموش کنید', 'Turn off the device VPN'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colors.onErrorContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _t(
                    'برای ارسال یا دریافت فایل باید VPN این دستگاه خاموش باشد. تا وقتی VPN روشن است انتقال فایل در Quick Send غیرفعال می‌ماند.',
                    'Turn off this device VPN before sending or receiving files. Quick Send transfers remain unavailable while VPN is active.',
                  ),
                  style: TextStyle(color: colors.onErrorContainer),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _appleWebTransferPanel() {
    final service = _appleWebTransfer;
    final colors = Theme.of(context).colorScheme;
    final blocked = widget.deviceVpnActive;
    final isWindows = Platform.isWindows;
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: colors.secondaryContainer,
                child: const Icon(Icons.phone_iphone_outlined),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _t('ارسال به iPhone یا Mac', 'Send to iPhone or Mac'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isWindows
                          ? _t(
                              'صفحه انتقال محلی را روی این کامپیوتر اجرا می‌کند. iPhone یا Mac را به همان Wi-Fi، مودم یا هات‌اسپات وصل و QR را اسکن کنید.',
                              'Runs a local transfer page on this PC. Connect the iPhone or Mac to the same Wi-Fi, router, or hotspot, then scan the QR.',
                            )
                          : _t(
                              'یک شبکه خصوصی و صفحه انتقال محلی می‌سازد؛ دستگاه اپل فقط به Safari نیاز دارد.',
                              'Creates a private network and local transfer page; the Apple device only needs Safari.',
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (service.starting)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: CircularProgressIndicator(),
              ),
            )
          else if (!service.active)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: blocked ? null : _startAppleWebTransfer,
                icon: Icon(isWindows ? Icons.qr_code_2 : Icons.wifi_tethering),
                label: Text(
                  isWindows
                      ? _t(
                          'شروع انتقال وب و ساخت QR',
                          'Start web transfer and create QR',
                        )
                      : _t(
                          'ساخت هات‌اسپات خصوصی و شروع',
                          'Create private hotspot and start',
                        ),
                ),
              ),
            )
          else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: const Icon(Icons.language_outlined, size: 18),
                  label: Text(_t('وب‌سرویس فعال', 'Web service active')),
                ),
                Chip(
                  avatar: Icon(
                    service.managedHotspot
                        ? Icons.wifi_tethering
                        : Icons.settings_input_antenna,
                    size: 18,
                  ),
                  label: Text(
                    service.managedHotspot
                        ? _t('هات‌اسپات خودکار', 'Automatic hotspot')
                        : isWindows
                        ? _t(
                            'شبکه مشترک / هات‌اسپات Windows',
                            'Shared network / Windows hotspot',
                          )
                        : _t(
                            'هات‌اسپات دستی / Wi-Fi',
                            'Manual hotspot / Wi-Fi',
                          ),
                  ),
                ),
                Chip(
                  avatar: const Icon(Icons.attach_file, size: 18),
                  label: Text(
                    _t(
                      '${service.sharedFileCount} فایل اشتراکی',
                      '${service.sharedFileCount} shared files',
                    ),
                  ),
                ),
              ],
            ),
            if (service.errorMessage.isNotEmpty) ...[
              const SizedBox(height: 10),
              ServiceLockNotice(
                message: service.errorMessage,
                icon: Icons.warning_amber_outlined,
              ),
            ],
            if (service.managedHotspot) ...[
              const SizedBox(height: 14),
              Text(
                _t(
                  '۱) ابتدا QR شبکه را با دوربین iPhone اسکن و به شبکه متصل کنید. پیام «بدون اینترنت» طبیعی است.',
                  '1) Scan the Wi-Fi QR with the iPhone camera and join the network. A “No Internet” notice is expected.',
                ),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 10),
              _credentialRow(
                label: 'SSID',
                value: service.hotspotSsid,
                icon: Icons.wifi,
              ),
              if (service.hotspotPassword.isNotEmpty)
                _credentialRow(
                  label: _t('رمز', 'Password'),
                  value: service.hotspotPassword,
                  icon: Icons.password_outlined,
                ),
              const SizedBox(height: 10),
              _qrPanel(
                title: _t('QR اتصال Wi-Fi', 'Wi-Fi connection QR'),
                data: service.wifiQrPayload,
                caption: _t(
                  'این QR فقط دستگاه اپل را به شبکه خصوصی وصل می‌کند.',
                  'This QR only joins the Apple device to the private network.',
                ),
              ),
            ] else ...[
              const SizedBox(height: 12),
              Text(
                isWindows
                    ? _t(
                        'کامپیوتر و دستگاه اپل را به یک مودم یا Wi-Fi وصل کنید، یا Mobile hotspot ویندوز را روشن و دستگاه اپل را به آن متصل کنید. آدرس‌های قابل‌دسترسی به‌صورت خودکار به‌روزرسانی می‌شوند.',
                        'Connect this PC and the Apple device to the same router or Wi-Fi, or enable Windows Mobile hotspot and join it from the Apple device. Reachable addresses update automatically.',
                      )
                    : _t(
                        'هات‌اسپات خودکار روی این دستگاه شروع نشد. هات‌اسپات Android را روشن کنید یا هر دو دستگاه را روی یک Wi-Fi قرار دهید؛ آدرس‌ها خودکار به‌روزرسانی می‌شوند.',
                        'The automatic hotspot could not start on this device. Turn on Android hotspot settings or put both devices on the same Wi-Fi; addresses update automatically.',
                      ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _openWebTransferHotspotSettings,
                icon: const Icon(Icons.settings_outlined),
                label: Text(
                  isWindows
                      ? _t(
                          'باز کردن Mobile hotspot ویندوز',
                          'Open Windows Mobile hotspot',
                        )
                      : _t(
                          'باز کردن تنظیمات هات‌اسپات',
                          'Open hotspot settings',
                        ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              service.managedHotspot
                  ? _t(
                      '۲) پس از اتصال، QR زیر را اسکن کنید تا صفحه انتقال در Safari باز شود.',
                      '2) After joining, scan the QR below to open the transfer page in Safari.',
                    )
                  : _t(
                      'پس از اتصال دو دستگاه، QR زیر را اسکن یا آدرس را در Safari وارد کنید.',
                      'After both devices are connected, scan the QR below or enter the address in Safari.',
                    ),
            ),
            const SizedBox(height: 10),
            if (service.primaryUrl.isEmpty)
              ServiceLockNotice(
                message: isWindows
                    ? _t(
                        'هنوز آدرس شبکه محلی پیدا نشده است. اتصال Wi-Fi، Ethernet یا Mobile hotspot را بررسی کنید.',
                        'No local-network address is available yet. Check Wi-Fi, Ethernet, or Mobile hotspot connectivity.',
                      )
                    : _t(
                        'منتظر آدرس شبکه هستیم. پس از روشن شدن هات‌اسپات چند ثانیه صبر کنید.',
                        'Waiting for a network address. Allow a few seconds after enabling the hotspot.',
                      ),
                icon: Icons.hourglass_top_outlined,
              )
            else ...[
              _qrPanel(
                title: _t('QR صفحه انتقال', 'Transfer page QR'),
                data: service.primaryUrl,
                caption: service.primaryUrl,
              ),
              const SizedBox(height: 10),
              for (final url in service.webUrls.take(3))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.link),
                  title: SelectableText(url),
                  trailing: IconButton(
                    tooltip: _t('کپی آدرس', 'Copy address'),
                    onPressed: () => _copyWebTransferUrl(url),
                    icon: const Icon(Icons.copy_outlined),
                  ),
                ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _refreshAppleSharedContent,
                  icon: const Icon(Icons.refresh),
                  label: Text(
                    _t('به‌روزرسانی فایل‌ها', 'Refresh shared files'),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: _stopAppleWebTransfer,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: Text(_t('توقف سرویس', 'Stop service')),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _credentialRow({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(label),
      subtitle: SelectableText(value),
      trailing: IconButton(
        tooltip: _t('کپی', 'Copy'),
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: value));
          if (mounted) {
            _notice(_t('$label کپی شد.', '$label copied.'));
          }
        },
        icon: const Icon(Icons.copy_outlined),
      ),
    );
  }

  Widget _qrPanel({
    required String title,
    required String data,
    required String caption,
  }) {
    if (data.isEmpty) {
      return const SizedBox.shrink();
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: QrImageView(
                  data: data,
                  size: 176,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Colors.black,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              caption,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusPanel(QuickSendSettings settings) {
    final running = _service.serverRunning && !widget.deviceVpnActive;
    final localAddresses = _service.localAddresses;
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Quick Send',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: _t('تنظیمات Quick Send', 'Quick Send settings'),
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => QuickSendSettingsPage(
                      simple: LocalistVisualStyle.simpleOf(context),
                    ),
                  ),
                ),
                icon: const Icon(Icons.tune_outlined),
              ),
            ],
          ),
          Text(
            _t(
              'ارسال امن فایل و پیام به دستگاه‌های داخل شبکه، بدون اینترنت.',
              'Send files and messages to nearby devices without the internet.',
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(
                avatar: Icon(
                  running ? Icons.wifi_tethering : Icons.wifi_tethering_off,
                  size: 18,
                ),
                label: Text(
                  running
                      ? _t('آماده دریافت', 'Ready to receive')
                      : widget.deviceVpnActive
                      ? _t('غیرفعال به‌دلیل VPN', 'Disabled by VPN')
                      : _t('فقط ارسال', 'Send only'),
                ),
              ),
              Chip(
                avatar: const Icon(Icons.numbers, size: 18),
                label: Text('${settings.port}'),
              ),
              Chip(
                avatar: Icon(
                  settings.encryption
                      ? Icons.lock_outline
                      : Icons.no_encryption_outlined,
                  size: 18,
                ),
                label: Text(settings.encryption ? 'HTTPS' : 'HTTP'),
              ),
              if (settings.quickSave)
                Chip(
                  avatar: const Icon(Icons.bolt_outlined, size: 18),
                  label: Text(_t('ذخیره سریع', 'Quick Save')),
                ),
            ],
          ),
          if (running) ...[
            const SizedBox(height: 12),
            Text(
              _t(
                'آدرس اتصال دستی این دستگاه',
                'Manual connection address for this device',
              ),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            if (localAddresses.isEmpty)
              Text(
                _t(
                  'هنوز IP شبکه محلی پیدا نشده است؛ پس از اتصال به Wi-Fi یا Hotspot دکمه Refresh را بزنید.',
                  'No local-network IP is available yet. Connect to Wi-Fi or a hotspot, then tap Refresh.',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              )
            else ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final address in localAddresses)
                    ActionChip(
                      avatar: const Icon(Icons.copy_outlined, size: 17),
                      label: Text(address),
                      tooltip: _t('کپی IP', 'Copy IP'),
                      onPressed: () => _copyManualAddress(address),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _t(
                  'در دستگاه فرستنده، کنار Nearby devices روی + بزنید و یکی از این IPها را با پورت ${settings.port} و حالت ${settings.encryption ? 'HTTPS' : 'HTTP'} وارد کنید.',
                  'On the sender, tap + beside Nearby devices and enter one of these IPs with port ${settings.port} and ${settings.encryption ? 'HTTPS' : 'HTTP'}.',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
          if (_service.lastError.isNotEmpty) ...[
            const SizedBox(height: 10),
            ServiceLockNotice(
              message: _t(
                'سرویس شبکه کامل اجرا نشد: ${_service.lastError}',
                'The network service did not fully start: ${_service.lastError}',
              ),
              icon: Icons.warning_amber_outlined,
            ),
          ],
          if (Platform.isAndroid && !_service.storageAccessGranted) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(Icons.folder_off_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _t(
                      'برای ذخیره فایل‌ها در پوشه /Localist دسترسی فایل لازم است.',
                      'File access is required to save received files in /Localist.',
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _requestStorageAccess,
                  child: Text(_t('اعطا', 'Grant')),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _pendingPanel(QuickSendPendingRequest pending) {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.markunread_mailbox_outlined),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _t(
                    'درخواست دریافت از ${pending.sender.alias}',
                    'Incoming request from ${pending.sender.alias}',
                  ),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final file in pending.files)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: Text(file.fileName),
              subtitle: file.isInlineMessage
                  ? Text(
                      file.preview,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    )
                  : null,
              trailing: Text(_formatBytes(file.size)),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _service.declinePending,
                  icon: const Icon(Icons.close),
                  label: Text(_t('رد', 'Decline')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _service.acceptPending,
                  icon: const Icon(Icons.download_done_outlined),
                  label: Text(_t('دریافت', 'Accept')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _nearbyPanel(QuickSendSettings settings) {
    final devices = _service.devices;
    final selectedDevices = devices
        .where((device) => _selectedDeviceIds.contains(device.id))
        .toList(growable: false);
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _t('دستگاه‌های نزدیک', 'Nearby devices'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: _t('افزودن با IP', 'Add by IP'),
                onPressed: widget.deviceVpnActive
                    ? null
                    : _showManualDeviceDialog,
                icon: const Icon(Icons.add_link),
              ),
              IconButton(
                tooltip: _t('جست‌وجوی دوباره', 'Search again'),
                onPressed:
                    widget.deviceVpnActive ||
                        _service.scanning ||
                        _service.restarting
                    ? null
                    : _service.refresh,
                icon: _service.scanning
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync),
              ),
            ],
          ),
          Text(
            _t(
              'نکته: روی یک دستگاه نگه دارید تا چند مقصد را انتخاب و هم‌زمان ارسال کنید.',
              'Tip: press and hold a device to select multiple recipients and send at the same time.',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          if (devices.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: Column(
                  children: [
                    const Icon(Icons.devices_outlined, size: 42),
                    const SizedBox(height: 8),
                    Text(
                      _t(
                        'دستگاهی پیدا نشد؛ هر دو دستگاه را به یک شبکه وصل کنید.',
                        'No device found. Connect both devices to the same network.',
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            for (final device in devices)
              ListTile(
                selected: _selectedDeviceIds.contains(device.id),
                selectedTileColor: Theme.of(
                  context,
                ).colorScheme.primaryContainer.withValues(alpha: 0.45),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  child: Icon(
                    device.deviceType == 'mobile'
                        ? Icons.smartphone_outlined
                        : Icons.computer_outlined,
                  ),
                ),
                title: Text(device.alias),
                subtitle: Text(
                  '${device.deviceModel.isEmpty ? device.deviceType : device.deviceModel} • ${device.ip}:${device.port}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: settings.isFavorite(device.fingerprint)
                          ? _t('حذف از علاقه‌مندی', 'Remove favorite')
                          : _t('افزودن به علاقه‌مندی', 'Add favorite'),
                      onPressed: device.fingerprint.isEmpty
                          ? null
                          : () => _service.toggleFavorite(device),
                      icon: Icon(
                        settings.isFavorite(device.fingerprint)
                            ? Icons.star
                            : Icons.star_border,
                      ),
                    ),
                    if (_selectedDeviceIds.contains(device.id))
                      const Icon(Icons.check_circle),
                  ],
                ),
                onLongPress: _sending || widget.deviceVpnActive
                    ? null
                    : () => _toggleDeviceSelection(device),
                onTap: _sending || widget.deviceVpnActive
                    ? null
                    : _selectedDeviceIds.isEmpty
                    ? () => _sendToDevices([device])
                    : () => _toggleDeviceSelection(device),
              ),
          if (selectedDevices.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _sending || widget.deviceVpnActive
                    ? null
                    : () => _sendToDevices(selectedDevices),
                icon: const Icon(Icons.send_outlined),
                label: Text(
                  _t(
                    'ارسال هم‌زمان به ${selectedDevices.length} دستگاه',
                    'Send to ${selectedDevices.length} devices',
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _selectionPanel() {
    final hasSelection = _selectedPaths.isNotEmpty || _selectedText.isNotEmpty;
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _t('انتخاب محتوا', 'Selection'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              if (hasSelection)
                IconButton(
                  tooltip: _t('پاک کردن انتخاب‌ها', 'Clear selection'),
                  onPressed: _sending ? null : _clearSelection,
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SelectionCard(
                icon: Icons.description_outlined,
                label: _t('فایل', 'File'),
                onTap: _sending ? null : _pickFiles,
              ),
              _SelectionCard(
                icon: Icons.image_outlined,
                label: _t('رسانه', 'Media'),
                onTap: _sending ? null : _pickMedia,
              ),
              _SelectionCard(
                icon: Icons.content_paste_outlined,
                label: _t('چسباندن', 'Paste'),
                onTap: _sending ? null : _pasteClipboard,
              ),
              _SelectionCard(
                icon: Icons.subject_outlined,
                label: _t('متن', 'Text'),
                onTap: _sending ? null : _composeText,
              ),
              _SelectionCard(
                icon: Icons.folder_outlined,
                label: _t('پوشه', 'Folder'),
                onTap: _sending ? null : _pickFolder,
              ),
            ],
          ),
          if (Platform.isWindows) ...[
            const SizedBox(height: 10),
            if (context.l10n.isPersian)
              Row(
                children: [
                  const Icon(Icons.file_download_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '\u0645\u06cc\u200c\u062a\u0648\u0627\u0646\u06cc\u062f \u0641\u0627\u06cc\u0644\u200c\u0647\u0627 \u0631\u0627 \u0646\u06cc\u0632 \u0631\u0648\u06cc \u0627\u06cc\u0646 \u067e\u0646\u062c\u0631\u0647 \u0631\u0647\u0627 \u06a9\u0646\u06cc\u062f.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              )
            else
              Row(
                children: [
                  const Icon(Icons.file_download_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _t(
                        'می‌توانید فایل‌ها را نیز روی این پنجره رها کنید.',
                        'You can also drag files onto this window.',
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
          ],
          const SizedBox(height: 14),
          if (!hasSelection)
            Text(
              _t(
                'یک یا چند مورد را انتخاب کنید، سپس روی دستگاه مقصد بزنید.',
                'Choose one or more items, then tap the destination device.',
              ),
            )
          else ...[
            if (_selectedText.isNotEmpty)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.message_outlined),
                title: Text(_t('پیام متنی', 'Text message')),
                subtitle: Text(
                  _selectedText,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  tooltip: _t('حذف', 'Remove'),
                  onPressed: () {
                    setState(() => _selectedText = '');
                    _syncAppleSharedContent();
                  },
                  icon: const Icon(Icons.close),
                ),
              ),
            for (final path in _selectedPaths)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.insert_drive_file_outlined),
                title: Text(
                  _selectedFileNames[path] ?? path.split(RegExp(r'[/\\]')).last,
                ),
                subtitle: Text(
                  path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  tooltip: _t('حذف', 'Remove'),
                  onPressed: () {
                    setState(() {
                      _selectedPaths.remove(path);
                      _selectedFileNames.remove(path);
                    });
                    _syncAppleSharedContent();
                  },
                  icon: const Icon(Icons.close),
                ),
              ),
            Text(
              _t(
                '${_selectedPaths.length} فایل آماده ارسال است.',
                '${_selectedPaths.length} files ready to send.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  Widget _transfersPanel() {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _t('انتقال‌ها', 'Transfers'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              if (Platform.isAndroid)
                IconButton(
                  tooltip: _t(
                    'باز کردن پوشه اصلی Localist',
                    'Open the main Localist folder',
                  ),
                  onPressed: _openLocalistFolder,
                  icon: const Icon(Icons.folder_open_outlined),
                ),
            ],
          ),
          const SizedBox(height: 8),
          for (final transfer in _service.transfers.take(12))
            Builder(
              builder: (context) {
                final isReceivedFile =
                    transfer.direction == QuickSendDirection.receiving &&
                    transfer.path.isNotEmpty;
                final completedReceivedFile =
                    isReceivedFile &&
                    transfer.state == QuickSendTransferState.completed;
                final sizeText = _transferSizeText(transfer);
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    transfer.direction == QuickSendDirection.sending
                        ? Icons.upload_file_outlined
                        : Icons.download_for_offline_outlined,
                  ),
                  title: Text(transfer.fileName),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${transfer.deviceName} • ${_transferLabel(transfer.state)}',
                      ),
                      const SizedBox(height: 5),
                      LinearProgressIndicator(value: transfer.progress),
                      if (sizeText.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            sizeText,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      if (transfer.message.isNotEmpty)
                        Text(
                          transfer.message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                  trailing: completedReceivedFile
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: _t('ارسال دوباره', 'Share again'),
                              onPressed: () => _shareReceivedFile(transfer),
                              icon: const Icon(Icons.ios_share_outlined),
                            ),
                            if (!Platform.isAndroid)
                              IconButton(
                                tooltip: _t('باز کردن پوشه', 'Open folder'),
                                onPressed: () => _openReceivedFolder(transfer),
                                icon: const Icon(Icons.folder_open_outlined),
                              ),
                            IconButton(
                              tooltip: _t('باز کردن فایل', 'Open file'),
                              onPressed: () => _openReceivedFile(transfer),
                              icon: const Icon(Icons.open_in_new_outlined),
                            ),
                          ],
                        )
                      : transfer.path.isEmpty &&
                            transfer.direction ==
                                QuickSendDirection.receiving &&
                            transfer.state == QuickSendTransferState.completed
                      ? Text(_t('کپی', 'Copy'), textAlign: TextAlign.end)
                      : const SizedBox.shrink(),
                  onTap:
                      transfer.path.isEmpty &&
                          transfer.direction == QuickSendDirection.receiving &&
                          transfer.state == QuickSendTransferState.completed &&
                          transfer.message.isNotEmpty
                      ? () async {
                          await Clipboard.setData(
                            ClipboardData(text: transfer.message),
                          );
                          if (mounted) {
                            _notice(_t('پیام کپی شد.', 'Message copied.'));
                          }
                        }
                      : null,
                );
              },
            ),
        ],
      ),
    );
  }

  String _transferSizeText(QuickSendTransfer transfer) {
    if (transfer.totalBytes <= 0) {
      return '';
    }
    if (transfer.state == QuickSendTransferState.completed) {
      return _formatBytes(transfer.totalBytes);
    }
    return '${_formatBytes(transfer.transferredBytes)} / ${_formatBytes(transfer.totalBytes)}';
  }

  Future<void> _shareReceivedFile(QuickSendTransfer transfer) async {
    if (transfer.path.isEmpty || !File(transfer.path).existsSync()) {
      if (context.l10n.isPersian) {
        _notice(
          '\u0641\u0627\u06cc\u0644 \u0642\u0627\u0628\u0644 \u062f\u0633\u062a\u0631\u0633 \u0646\u06cc\u0633\u062a.',
          warning: true,
        );
        return;
      }
      _notice(
        _t('فایل قابل دسترس نیست.', 'The received file is unavailable.'),
        warning: true,
      );
      return;
    }
    if (!Platform.isAndroid) {
      _selectReceivedFileForQuickSend(transfer);
      return;
    }
    final choice = await showDialog<_ReceivedFileShareChoice>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(
          _t(
            'این فایل چگونه به اشتراک گذاشته شود؟',
            'How would you like to share this file?',
          ),
        ),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(_ReceivedFileShareChoice.quickSend),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.devices_outlined),
              title: Text(
                _t('ارسال دوباره داخل Localist', 'Send again inside Localist'),
              ),
              subtitle: Text(
                _t(
                  'فایل انتخاب می‌شود تا آن را برای دستگاه‌های نزدیک بفرستید.',
                  'Selects the file so you can send it to nearby devices.',
                ),
              ),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(_ReceivedFileShareChoice.androidShare),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.share_outlined),
              title: Text(
                _t('اشتراک در برنامه‌های دیگر', 'Share with other apps'),
              ),
              subtitle: Text(
                _t(
                  'منوی Share اندروید باز می‌شود.',
                  'Opens the Android system share menu.',
                ),
              ),
            ),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) {
      return;
    }
    if (choice == _ReceivedFileShareChoice.quickSend) {
      _selectReceivedFileForQuickSend(transfer);
      return;
    }
    try {
      final shared = await _bridge.shareFileExternally(transfer.path);
      if (!shared && mounted) {
        _notice(
          _t(
            'منوی اشتراک اندروید باز نشد.',
            'Could not open the Android share menu.',
          ),
          warning: true,
        );
      }
    } catch (error) {
      if (mounted) {
        _notice(
          _t(
            'اشتراک فایل ناموفق بود: $error',
            'Could not share the file: $error',
          ),
          warning: true,
        );
      }
    }
  }

  void _selectReceivedFileForQuickSend(QuickSendTransfer transfer) {
    setState(() {
      if (!_selectedPaths.contains(transfer.path)) {
        _selectedPaths.add(transfer.path);
      }
      _selectedFileNames[transfer.path] = transfer.fileName;
    });
    _syncAppleSharedContent();
    if (context.l10n.isPersian) {
      _notice(
        '\u0641\u0627\u06cc\u0644 \u0628\u0631\u0627\u06cc \u0627\u0631\u0633\u0627\u0644 \u062f\u0648\u0628\u0627\u0631\u0647 \u0622\u0645\u0627\u062f\u0647 \u0634\u062f\u061b \u062f\u0633\u062a\u06af\u0627\u0647 \u0645\u0642\u0635\u062f \u0631\u0627 \u0627\u0646\u062a\u062e\u0627\u0628 \u06a9\u0646\u06cc\u062f.',
      );
      return;
    }
    _notice(
      _t(
        'فایل برای ارسال دوباره آماده شد؛ دستگاه مقصد را انتخاب کنید.',
        'The file is ready to send again. Choose a destination device.',
      ),
    );
  }

  Future<void> _openReceivedFolder(QuickSendTransfer transfer) async {
    var opened = false;
    try {
      opened = await _bridge.openContainingFolder(transfer.path);
    } catch (_) {
      opened = false;
    }
    if (!opened && mounted) {
      if (context.l10n.isPersian) {
        _notice(
          '\u067e\u0648\u0634\u0647 \u0641\u0627\u06cc\u0644 \u0628\u0627\u0632 \u0646\u0634\u062f.',
          warning: true,
        );
        return;
      }
      _notice(
        _t('پوشه فایل باز نشد.', 'Could not open the file folder.'),
        warning: true,
      );
    }
  }

  Future<void> _openLocalistFolder() async {
    var opened = false;
    try {
      opened = await _bridge.openLocalistFolder();
    } catch (_) {
      opened = false;
    }
    if (!opened && mounted) {
      _notice(
        _t(
          'پوشه اصلی Localist باز نشد.',
          'Could not open the main Localist folder.',
        ),
        warning: true,
      );
    }
  }

  Future<void> _openReceivedFile(QuickSendTransfer transfer) async {
    var opened = false;
    try {
      opened = await _bridge.openFile(transfer.path);
    } catch (_) {
      opened = false;
    }
    if (!opened && mounted) {
      if (context.l10n.isPersian) {
        _notice(
          '\u0641\u0627\u06cc\u0644 \u0628\u0627\u0632 \u0646\u0634\u062f.',
          warning: true,
        );
        return;
      }
      _notice(_t('فایل باز نشد.', 'Could not open the file.'), warning: true);
    }
  }

  Future<void> _pickFiles() async {
    await _pickFilesOfType(FileType.any);
  }

  Future<void> _pickMedia() async {
    await _pickFilesOfType(FileType.media);
  }

  Future<void> _pickFilesOfType(FileType type) async {
    final result = await FilePicker.pickFiles(allowMultiple: true, type: type);
    if (result == null || !mounted) {
      return;
    }
    setState(() {
      for (final file in result.files) {
        final path = file.path;
        if (path != null && !_selectedPaths.contains(path)) {
          _selectedPaths.add(path);
        }
      }
    });
    _syncAppleSharedContent();
  }

  Future<void> _pickFolder() async {
    final path = await FilePicker.getDirectoryPath();
    if (path == null || !mounted) {
      return;
    }
    try {
      final files = <String>[];
      final offeredNames = <String, String>{};
      final folderName = p.basename(path);
      await for (final entity in Directory(
        path,
      ).list(recursive: true, followLinks: false)) {
        if (entity is File) {
          files.add(entity.path);
          final relative = p
              .relative(entity.path, from: path)
              .replaceAll('\\', '/');
          offeredNames[entity.path] = p.posix.join(folderName, relative);
          if (files.length >= 5000) {
            break;
          }
        }
      }
      if (!mounted) {
        return;
      }
      setState(() {
        for (final file in files) {
          if (!_selectedPaths.contains(file)) {
            _selectedPaths.add(file);
          }
          _selectedFileNames[file] = offeredNames[file]!;
        }
      });
      _syncAppleSharedContent();
      if (files.length >= 5000) {
        _notice(
          _t(
            'برای حفظ پایداری، ۵۰۰۰ فایل اول پوشه انتخاب شد.',
            'The first 5,000 folder files were selected for stability.',
          ),
          warning: true,
        );
      }
    } catch (error) {
      _notice(
        _t(
          'خواندن پوشه ناموفق بود: $error',
          'Could not read the folder: $error',
        ),
        warning: true,
      );
    }
  }

  Future<void> _pasteClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (!mounted) {
      return;
    }
    if (text.isEmpty) {
      _notice(
        _t('متنی در کلیپ‌بورد نیست.', 'There is no text in the clipboard.'),
        warning: true,
      );
      return;
    }
    setState(() => _selectedText = text);
    _syncAppleSharedContent();
  }

  Future<void> _composeText() async {
    final messageController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_t('انتخاب متن', 'Select text')),
        content: TextField(
          controller: messageController,
          autofocus: true,
          minLines: 3,
          maxLines: 8,
          decoration: InputDecoration(hintText: _t('متن پیام', 'Message text')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(_t('لغو', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(messageController.text),
            child: Text(_t('ادامه', 'Continue')),
          ),
        ],
      ),
    );
    messageController.dispose();
    if (result == null || result.trim().isEmpty || !mounted) {
      return;
    }
    setState(() => _selectedText = result.trim());
    _syncAppleSharedContent();
  }

  void _toggleDeviceSelection(QuickSendDevice device) {
    setState(() {
      if (!_selectedDeviceIds.add(device.id)) {
        _selectedDeviceIds.remove(device.id);
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedPaths.clear();
      _selectedFileNames.clear();
      _selectedText = '';
    });
    _syncAppleSharedContent();
  }

  Future<void> _sendContentToDevice(
    QuickSendDevice device, {
    String? pin,
  }) async {
    if (_selectedText.isNotEmpty) {
      await _service.sendText(device, _selectedText, pin: pin);
    }
    if (_selectedPaths.isNotEmpty) {
      await _service.sendFiles(
        device,
        List.of(_selectedPaths),
        offeredNames: Map.of(_selectedFileNames),
        pin: pin,
      );
    }
  }

  Future<void> _sendToDevices(List<QuickSendDevice> devices) async {
    if (_sending || devices.isEmpty) {
      return;
    }
    if (widget.deviceVpnActive) {
      _notice(
        _t(
          'برای انتقال فایل ابتدا VPN دستگاه را خاموش کنید.',
          'Turn off the device VPN before transferring files.',
        ),
        warning: true,
      );
      return;
    }
    if (_selectedPaths.isEmpty && _selectedText.isEmpty) {
      _notice(
        _t(
          'ابتدا حداقل یک فایل، رسانه، پوشه یا متن انتخاب کنید.',
          'Choose at least one file, media item, folder, or text first.',
        ),
        warning: true,
      );
      return;
    }
    setState(() => _sending = true);
    final succeeded = <QuickSendDevice>[];
    final pinRequired = <QuickSendDevice>[];
    final failed = <QuickSendDevice, Object>{};
    try {
      await Future.wait(
        devices.map((device) async {
          try {
            await _sendContentToDevice(device);
            succeeded.add(device);
          } on QuickSendPinRequiredException {
            pinRequired.add(device);
          } catch (error) {
            failed[device] = error;
          }
        }),
      );
      for (final device in pinRequired) {
        if (!mounted) {
          return;
        }
        final pin = await _askForPin(device);
        if (pin == null) {
          failed[device] = const QuickSendPinRequiredException();
          continue;
        }
        try {
          await _sendContentToDevice(device, pin: pin);
          succeeded.add(device);
        } catch (error) {
          failed[device] = error;
        }
      }
      if (mounted) {
        if (failed.isEmpty) {
          _notice(
            _t(
              'ارسال به ${succeeded.length} دستگاه با موفقیت انجام شد.',
              'Transfer completed for ${succeeded.length} devices.',
            ),
          );
          setState(() {
            _selectedPaths.clear();
            _selectedFileNames.clear();
            _selectedText = '';
            _selectedDeviceIds.clear();
          });
          _syncAppleSharedContent();
        } else {
          final names = failed.keys.map((device) => device.alias).join(', ');
          _notice(
            _t(
              'ارسال به ${succeeded.length} دستگاه انجام شد؛ ناموفق: $names',
              'Sent to ${succeeded.length} devices; failed: $names',
            ),
            warning: true,
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<String?> _askForPin(QuickSendDevice device) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          _t('PIN دستگاه ${device.alias}', '${device.alias} receiver PIN'),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.pin_outlined),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(_t('لغو', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(_t('ارسال', 'Send')),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _showManualDeviceDialog() async {
    await _service.refreshLocalAddresses();
    if (!mounted) {
      return;
    }
    final host = TextEditingController();
    final port = TextEditingController(text: '53317');
    var https = true;
    final result = await showDialog<(String, int, bool)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(_t('افزودن دستگاه با IP', 'Add device by IP')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.secondaryContainer.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.help_outline, size: 20),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          _t(
                            'در دستگاه مقصد Quick Send را باز کنید. IP زیر عنوان «آدرس اتصال دستی این دستگاه» را کپی کنید. هر دو دستگاه باید روی یک Wi-Fi یا Hotspot باشند و VPN خاموش باشد؛ سپس همان IP، پورت و HTTP/HTTPS را اینجا وارد کنید.',
                            'On the destination device, open Quick Send and copy an IP shown under “Manual connection address for this device”. Both devices must use the same Wi-Fi or hotspot with VPN off. Enter that IP here and keep the port and HTTP/HTTPS mode identical.',
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: host,
                  autofocus: true,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: _t('IP دستگاه مقصد', 'Destination device IP'),
                    hintText: '192.168.1.25',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: port,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: _t('پورت', 'Port')),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('HTTPS'),
                  value: https,
                  onChanged: (value) => setDialogState(() => https = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(_t('لغو', 'Cancel')),
            ),
            FilledButton(
              onPressed: () {
                final parsed = int.tryParse(port.text.trim());
                if (host.text.trim().isNotEmpty &&
                    parsed != null &&
                    parsed >= 1 &&
                    parsed <= 65535) {
                  Navigator.of(context).pop((host.text.trim(), parsed, https));
                }
              },
              child: Text(_t('اتصال', 'Connect')),
            ),
          ],
        ),
      ),
    );
    host.dispose();
    port.dispose();
    if (result == null || !mounted) {
      return;
    }
    try {
      await _service.addManualDevice(
        host: result.$1,
        port: result.$2,
        https: result.$3,
      );
      if (mounted) {
        _notice(_t('دستگاه اضافه شد.', 'Device added.'));
      }
    } catch (error) {
      if (mounted) {
        _notice(
          _t('دستگاه در دسترس نیست: $error', 'Device is unavailable: $error'),
          warning: true,
        );
      }
    }
  }

  void _syncAppleSharedContent() {
    _appleWebTransfer.setSharedContent(
      paths: List.of(_selectedPaths),
      offeredNames: Map.of(_selectedFileNames),
      selectedText: _selectedText,
    );
  }

  Future<void> _startAppleWebTransfer() async {
    if (widget.deviceVpnActive) {
      _notice(
        _t(
          'برای راه‌اندازی انتقال وب ابتدا VPN دستگاه را خاموش کنید.',
          'Turn off the device VPN before starting web transfer.',
        ),
        warning: true,
      );
      return;
    }
    try {
      final automaticHotspot = await _appleWebTransfer.start(
        paths: List.of(_selectedPaths),
        offeredNames: Map.of(_selectedFileNames),
        selectedText: _selectedText,
      );
      if (!mounted || widget.deviceVpnActive) {
        return;
      }
      if (Platform.isWindows) {
        _notice(
          _t(
            'صفحه انتقال وب آماده است؛ دستگاه اپل را به همان شبکه وصل و QR را اسکن کنید.',
            'The web transfer page is ready. Join the same network from the Apple device and scan the QR.',
          ),
        );
        return;
      }
      if (automaticHotspot) {
        _notice(
          _t(
            'هات‌اسپات خصوصی و صفحه انتقال آماده شدند.',
            'The private hotspot and transfer page are ready.',
          ),
        );
        return;
      }
      _notice(
        _t(
          'هات‌اسپات خودکار در دسترس نبود؛ هات‌اسپات سیستم را روشن کنید یا از Wi-Fi مشترک استفاده کنید.',
          'Automatic hotspot was unavailable; enable the system hotspot or use a shared Wi-Fi network.',
        ),
        warning: true,
      );
      await _openWebTransferHotspotSettings();
    } catch (error) {
      if (mounted) {
        _notice(
          _t(
            'راه‌اندازی انتقال وب ناموفق بود: $error',
            'Could not start web transfer: $error',
          ),
          warning: true,
        );
      }
    }
  }

  Future<void> _stopAppleWebTransfer() async {
    try {
      await _appleWebTransfer.stop();
      if (mounted) {
        _notice(_t('سرویس انتقال وب متوقف شد.', 'Web transfer stopped.'));
      }
    } catch (error) {
      if (mounted) {
        _notice(
          _t(
            'توقف سرویس ناموفق بود: $error',
            'Could not stop the service: $error',
          ),
          warning: true,
        );
      }
    }
  }

  void _refreshAppleSharedContent() {
    _syncAppleSharedContent();
    _notice(
      _t(
        'فایل‌ها و متن انتخاب‌شده در صفحه وب به‌روزرسانی شدند.',
        'Selected files and text were refreshed on the web page.',
      ),
    );
  }

  Future<void> _copyWebTransferUrl(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) {
      _notice(_t('آدرس کپی شد.', 'Address copied.'));
    }
  }

  Future<void> _copyManualAddress(String address) async {
    await Clipboard.setData(ClipboardData(text: address));
    if (mounted) {
      _notice(_t('IP کپی شد.', 'IP address copied.'));
    }
  }

  Future<void> _openWebTransferHotspotSettings() async {
    try {
      final opened = await _bridge.openHotspotSettings();
      if (!opened && mounted) {
        _notice(
          _t('تنظیمات هات‌اسپات باز نشد.', 'Could not open hotspot settings.'),
          warning: true,
        );
      }
    } catch (error) {
      if (mounted) {
        _notice(
          _t(
            'تنظیمات هات‌اسپات باز نشد: $error',
            'Could not open hotspot settings: $error',
          ),
          warning: true,
        );
      }
    }
  }

  Future<void> _requestStorageAccess() async {
    final granted = await _service.ensureReceiveStorageAccess();
    if (!mounted) {
      return;
    }
    _notice(
      granted
          ? _t('دسترسی فایل فعال شد.', 'File access was enabled.')
          : _t(
              'دسترسی فایل داده نشد؛ مسیر پیش‌فرض /Localist قابل نوشتن نیست.',
              'File access was not granted; the default /Localist path is not writable.',
            ),
      warning: !granted,
    );
  }

  void _notice(String message, {bool warning = false}) {
    showLocalistNotice(
      context,
      message: message,
      tone: warning ? InAppNoticeTone.warning : InAppNoticeTone.success,
    );
  }

  String _t(String fa, String en) => context.l10n.isPersian ? fa : en;

  String _transferLabel(QuickSendTransferState state) {
    return switch (state) {
      QuickSendTransferState.waiting => _t('در انتظار', 'Waiting'),
      QuickSendTransferState.transferring => _t(
        'در حال انتقال',
        'Transferring',
      ),
      QuickSendTransferState.completed => _t('کامل شد', 'Completed'),
      QuickSendTransferState.failed => _t('ناموفق', 'Failed'),
    };
  }
}

enum _ReceivedFileShareChoice { quickSend, androidShare }

class _SelectionCard extends StatelessWidget {
  const _SelectionCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final cardWidth = screenWidth >= 480
        ? 96.0
        : screenWidth >= 360
        ? 82.0
        : 72.0;
    return SizedBox(
      width: cardWidth,
      height: 78,
      child: Material(
        color: colors.secondaryContainer.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 24),
                const SizedBox(height: 5),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class QuickSendSettingsPage extends StatefulWidget {
  const QuickSendSettingsPage({super.key, required this.simple});

  final bool simple;

  @override
  State<QuickSendSettingsPage> createState() => _QuickSendSettingsPageState();
}

class _QuickSendSettingsPageState extends State<QuickSendSettingsPage> {
  final QuickSendService _service = QuickSendService.instance;
  final TextEditingController _alias = TextEditingController();
  final TextEditingController _port = TextEditingController();
  final TextEditingController _multicast = TextEditingController();
  final TextEditingController _destination = TextEditingController();
  final TextEditingController _pin = TextEditingController();
  bool _receiveEnabled = true;
  bool _encryption = true;
  bool _quickSave = false;
  bool _quickSaveFavorites = true;
  bool _overwrite = false;
  bool _requirePin = false;
  bool _destinationCustomized = false;
  bool _loaded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    await _service.initialize();
    final value = _service.settings!;
    if (!mounted) {
      return;
    }
    setState(() {
      _alias.text = value.alias;
      _port.text = value.port.toString();
      _multicast.text = value.multicastGroup;
      _destination.text = value.destinationDirectory;
      _destinationCustomized = value.destinationCustomized;
      _pin.text = value.pin;
      _receiveEnabled = value.receiveEnabled;
      _encryption = value.encryption;
      _quickSave = value.quickSave;
      _quickSaveFavorites = value.quickSaveFavorites;
      _overwrite = value.overwrite;
      _requirePin = value.requirePin;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _alias.dispose();
    _port.dispose();
    _multicast.dispose();
    _destination.dispose();
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GlassBackground(
      simple: widget.simple,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: GlassAppBar(
          title: Text(_t('تنظیمات Quick Send', 'Quick Send settings')),
        ),
        body: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  GlassPanel(
                    child: Column(
                      children: [
                        TextField(
                          controller: _alias,
                          readOnly: Platform.isAndroid,
                          decoration: InputDecoration(
                            labelText: _t('نام دستگاه', 'Device name'),
                            prefixIcon: const Icon(Icons.badge_outlined),
                            helperText: Platform.isAndroid
                                ? _t(
                                    'مدل واقعی گوشی به‌صورت خودکار استفاده می‌شود.',
                                    'The phone model is used automatically.',
                                  )
                                : null,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _port,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: _t('پورت', 'Port'),
                            prefixIcon: const Icon(Icons.numbers),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _multicast,
                          decoration: InputDecoration(
                            labelText: _t('گروه Multicast', 'Multicast group'),
                            prefixIcon: const Icon(Icons.hub_outlined),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  GlassPanel(
                    child: Column(
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            _t('فعال بودن دریافت', 'Enable receiving'),
                          ),
                          subtitle: Text(
                            _t(
                              'این دستگاه در شبکه دیده می‌شود و فایل می‌پذیرد.',
                              'This device is visible and can receive files.',
                            ),
                          ),
                          value: _receiveEnabled,
                          onChanged: (value) =>
                              setState(() => _receiveEnabled = value),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(_t('رمزنگاری HTTPS', 'HTTPS encryption')),
                          subtitle: Text(
                            _t(
                              'گواهی اختصاصی دستگاه و بررسی اثرانگشت استفاده شود.',
                              'Use a device certificate with fingerprint verification.',
                            ),
                          ),
                          value: _encryption,
                          onChanged: (value) =>
                              setState(() => _encryption = value),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Quick Save'),
                          subtitle: Text(
                            _t(
                              'تمام درخواست‌ها خودکار پذیرفته شوند.',
                              'Automatically accept every request.',
                            ),
                          ),
                          value: _quickSave,
                          onChanged: (value) =>
                              setState(() => _quickSave = value),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            _t(
                              'ذخیره سریع برای علاقه‌مندی‌ها',
                              'Quick Save for favorites',
                            ),
                          ),
                          value: _quickSaveFavorites,
                          onChanged: (value) =>
                              setState(() => _quickSaveFavorites = value),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            _t(
                              'جایگزینی فایل موجود',
                              'Overwrite existing files',
                            ),
                          ),
                          value: _overwrite,
                          onChanged: (value) =>
                              setState(() => _overwrite = value),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  GlassPanel(
                    child: Column(
                      children: [
                        TextField(
                          controller: _destination,
                          readOnly: true,
                          decoration: InputDecoration(
                            labelText: _t('پوشه ذخیره', 'Destination folder'),
                            prefixIcon: const Icon(Icons.folder_outlined),
                            suffixIcon: IconButton(
                              tooltip: _t('انتخاب پوشه', 'Choose folder'),
                              onPressed: _chooseDestination,
                              icon: const Icon(Icons.folder_open_outlined),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            _destinationCustomized
                                ? _t(
                                    'فایل‌ها مستقیم در مسیر انتخابی ذخیره می‌شوند.',
                                    'Files are saved directly in the selected folder.',
                                  )
                                : _t(
                                    'مسیر پیش‌فرض Localist است و فایل‌ها در پوشه‌های Images، Videos، Audio، Documents، Archives، Apps و Other دسته‌بندی می‌شوند.',
                                    'The Localist default groups files into Images, Videos, Audio, Documents, Archives, Apps, and Other.',
                                  ),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(_t('نیاز به PIN', 'Require PIN')),
                          value: _requirePin,
                          onChanged: (value) =>
                              setState(() => _requirePin = value),
                        ),
                        if (_requirePin)
                          TextField(
                            controller: _pin,
                            obscureText: true,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'PIN',
                              prefixIcon: const Icon(Icons.pin_outlined),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_t('ذخیره تنظیمات', 'Save settings')),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _chooseDestination() async {
    final path = await FilePicker.getDirectoryPath(
      initialDirectory: _destination.text,
    );
    if (path != null && mounted) {
      setState(() {
        _destination.text = path;
        _destinationCustomized = true;
      });
    }
  }

  Future<void> _save() async {
    final port = int.tryParse(_port.text.trim());
    final alias = _alias.text.trim();
    final multicast = _multicast.text.trim();
    final ip = multicast.split('.').map(int.tryParse).toList();
    if (alias.isEmpty ||
        port == null ||
        port < 1024 ||
        port > 65535 ||
        ip.length != 4 ||
        ip.any((part) => part == null || part < 0 || part > 255) ||
        _destination.text.trim().isEmpty ||
        (_requirePin && _pin.text.trim().isEmpty)) {
      showLocalistNotice(
        context,
        message: _t(
          'نام، پورت، Multicast، پوشه و PIN را درست وارد کنید.',
          'Enter a valid name, port, multicast group, folder, and PIN.',
        ),
        tone: InAppNoticeTone.warning,
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final current = _service.settings!;
      await _service.updateSettings(
        current.copyWith(
          alias: alias,
          port: port,
          multicastGroup: multicast,
          destinationDirectory: _destination.text.trim(),
          destinationCustomized: _destinationCustomized,
          receiveEnabled: _receiveEnabled,
          encryption: _encryption,
          quickSave: _quickSave,
          quickSaveFavorites: _quickSaveFavorites,
          overwrite: _overwrite,
          requirePin: _requirePin,
          pin: _pin.text.trim(),
        ),
      );
      if (mounted) {
        showLocalistNotice(
          context,
          message: _t('تنظیمات ذخیره شد.', 'Settings saved.'),
          tone: InAppNoticeTone.success,
        );
      }
    } catch (error) {
      if (mounted) {
        showLocalistNotice(
          context,
          message: _t(
            'ذخیره تنظیمات ناموفق بود: $error',
            'Could not save settings: $error',
          ),
          tone: InAppNoticeTone.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  String _t(String fa, String en) => context.l10n.isPersian ? fa : en;
}

String _formatBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} ${units[unit]}';
}
