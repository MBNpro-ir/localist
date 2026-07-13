import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    unawaited(_service.initialize());
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
            _nearbyPanel(settings),
            _selectionPanel(),
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
          const SizedBox(height: 8),
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
                trailing: IconButton(
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
                onTap: _sending ? null : () => _sendSelected(device),
              ),
        ],
      ),
    );
  }

  Widget _selectionPanel() {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t('محتوای آماده ارسال', 'Ready to send'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),
          if (_selectedPaths.isEmpty)
            Text(
              _t(
                'فایل‌ها را انتخاب کنید، سپس روی دستگاه مقصد بزنید.',
                'Choose files, then tap the destination device.',
              ),
            )
          else
            for (final path in _selectedPaths)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.insert_drive_file_outlined),
                title: Text(path.split(RegExp(r'[/\\]')).last),
                subtitle: Text(
                  path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  tooltip: _t('حذف', 'Remove'),
                  onPressed: () => setState(() => _selectedPaths.remove(path)),
                  icon: const Icon(Icons.close),
                ),
              ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _sending ? null : _pickFiles,
                  icon: const Icon(Icons.add_to_drive_outlined),
                  label: Text(_t('انتخاب فایل', 'Choose files')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _sending ? null : _sendMessage,
                  icon: const Icon(Icons.message_outlined),
                  label: Text(_t('ارسال پیام', 'Send message')),
                ),
              ),
            ],
          ),
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
    final result = await FilePicker.pickFiles(allowMultiple: true);
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

  Future<void> _sendSelected(QuickSendDevice device) async {
    if (_selectedPaths.isEmpty) {
      _notice(
        _t(
          'ابتدا حداقل یک فایل انتخاب کنید.',
          'Choose at least one file first.',
        ),
        warning: true,
      );
      return;
    }
    final sent = await _runSend(
      device,
      (pin) => _service.sendFiles(device, List.of(_selectedPaths), pin: pin),
    );
    if (sent && mounted) {
      setState(_selectedPaths.clear);
    }
  }

  Future<void> _sendMessage() async {
    if (_service.devices.isEmpty) {
      _notice(
        _t(
          'ابتدا یک دستگاه مقصد پیدا کنید.',
          'Find a destination device first.',
        ),
        warning: true,
      );
      return;
    }
    final messageController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_t('ارسال پیام', 'Send message')),
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
    final device = await _chooseDevice();
    if (device == null) {
      return;
    }
    await _runSend(
      device,
      (pin) => _service.sendText(device, result, pin: pin),
    );
  }

  Future<QuickSendDevice?> _chooseDevice() {
    return showModalBottomSheet<QuickSendDevice>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
          children: [
            for (final device in _service.devices)
              ListTile(
                leading: const Icon(Icons.devices_outlined),
                title: Text(device.alias),
                subtitle: Text(device.endpoint),
                onTap: () => Navigator.of(context).pop(device),
              ),
          ],
        ),
      ),
    );
  }

  Future<bool> _runSend(
    QuickSendDevice device,
    Future<void> Function(String? pin) action,
  ) async {
    if (_sending) {
      return false;
    }
    setState(() => _sending = true);
    try {
      try {
        await action(null);
      } on QuickSendPinRequiredException {
        if (!mounted) {
          return false;
        }
        final pin = await _askForPin();
        if (pin == null) {
          return false;
        }
        await action(pin);
      }
      if (mounted) {
        _notice(_t('انتقال با موفقیت انجام شد.', 'Transfer completed.'));
      }
      return true;
    } catch (error) {
      if (mounted) {
        _notice(
          _t('انتقال ناموفق بود: $error', 'Transfer failed: $error'),
          warning: true,
        );
      }
      return false;
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<String?> _askForPin() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_t('PIN دستگاه مقصد', 'Receiver PIN')),
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
                          decoration: InputDecoration(
                            labelText: _t('نام دستگاه', 'Device name'),
                            prefixIcon: const Icon(Icons.badge_outlined),
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
      setState(() => _destination.text = path);
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
