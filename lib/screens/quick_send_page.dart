import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../l10n/app_localizations.dart';
import '../models/quick_send_settings.dart';
import '../services/quick_send_service.dart';
import '../widgets/glass.dart';

class QuickSendPage extends StatefulWidget {
  const QuickSendPage({super.key});

  @override
  State<QuickSendPage> createState() => _QuickSendPageState();
}

class _QuickSendPageState extends State<QuickSendPage> {
  final QuickSendService _service = QuickSendService.instance;
  final List<String> _selectedPaths = [];
  final Map<String, String> _selectedFileNames = {};
  final Set<String> _selectedDeviceIds = {};
  String _selectedText = '';
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    unawaited(_initializeQuickSend());
  }

  Future<void> _initializeQuickSend() async {
    await _service.initialize();
    if (Platform.isAndroid &&
        _service.settings?.receiveEnabled == true &&
        !_service.storageAccessGranted) {
      await _service.ensureReceiveStorageAccess();
    }
    await _service.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _service,
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
            _statusPanel(settings),
            if (_service.pendingRequest case final pending?)
              _pendingPanel(pending),
            _selectionPanel(),
            _nearbyPanel(settings),
            if (_service.transfers.isNotEmpty) _transfersPanel(),
          ],
        );
      },
    );
  }

  Widget _statusPanel(QuickSendSettings settings) {
    final running = _service.serverRunning;
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
                onPressed: _showManualDeviceDialog,
                icon: const Icon(Icons.add_link),
              ),
              IconButton(
                tooltip: _t('جست‌وجوی دوباره', 'Search again'),
                onPressed: _service.scanning || _service.restarting
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
                onLongPress: _sending
                    ? null
                    : () => _toggleDeviceSelection(device),
                onTap: _sending
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
                onPressed: _sending
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
            spacing: 10,
            runSpacing: 10,
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
                  onPressed: () => setState(() => _selectedText = ''),
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
                  onPressed: () => setState(() {
                    _selectedPaths.remove(path);
                    _selectedFileNames.remove(path);
                  }),
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
          Text(
            _t('انتقال‌ها', 'Transfers'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          for (final transfer in _service.transfers.take(12))
            ListTile(
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
                  if (transfer.message.isNotEmpty)
                    Text(
                      transfer.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
              trailing: Text(
                transfer.path.isEmpty &&
                        transfer.direction == QuickSendDirection.receiving &&
                        transfer.state == QuickSendTransferState.completed
                    ? _t('کپی', 'Copy')
                    : '${_formatBytes(transfer.transferredBytes)}\n${_formatBytes(transfer.totalBytes)}',
                textAlign: TextAlign.end,
              ),
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
            ),
        ],
      ),
    );
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
    final host = TextEditingController();
    final port = TextEditingController(text: '53317');
    var https = true;
    final result = await showDialog<(String, int, bool)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(_t('افزودن دستگاه با IP', 'Add device by IP')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: host,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: _t('IP یا میزبان', 'IP or host'),
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
    return SizedBox(
      width: 112,
      height: 96,
      child: Material(
        color: colors.secondaryContainer.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 30),
                const SizedBox(height: 8),
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
