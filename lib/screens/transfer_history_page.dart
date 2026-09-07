import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/native_bridge_service.dart';
import '../services/quick_send_service.dart';
import '../widgets/glass.dart';

class TransferHistoryPage extends StatefulWidget {
  const TransferHistoryPage({super.key, required this.service});

  final QuickSendService service;

  @override
  State<TransferHistoryPage> createState() => _TransferHistoryPageState();
}

class _TransferHistoryPageState extends State<TransferHistoryPage> {
  final NativeBridgeService _bridge = NativeBridgeService.instance;

  String _t(String fa, String en) => context.l10n.isPersian ? fa : en;

  @override
  Widget build(BuildContext context) {
    return GlassBackground(
      simple: Platform.isAndroid || Platform.isWindows,
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        appBar: GlassAppBar(
          title: Text(_t('تاریخچه انتقال', 'Transfer history')),
          leading: IconButton(
            tooltip: _t('بازگشت', 'Back'),
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          actions: [
            AnimatedBuilder(
              animation: widget.service,
              builder: (context, _) {
                final records = widget.service.receivedHistory;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: _t(
                        'باز کردن پوشه فایل‌های دریافتی',
                        'Open received files folder',
                      ),
                      onPressed: () => unawaited(_openReceiveFolder(records)),
                      icon: const Icon(Icons.folder_open_rounded),
                    ),
                    if (records.isNotEmpty)
                      IconButton(
                        tooltip: _t('پاک کردن تاریخچه', 'Clear history'),
                        onPressed: () => unawaited(_clearHistory()),
                        icon: const Icon(Icons.delete_sweep_outlined),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
        body: SafeArea(
          bottom: false,
          child: AnimatedBuilder(
            animation: widget.service,
            builder: (context, _) {
              final records = widget.service.receivedHistory;
              if (records.isEmpty) {
                return _emptyState();
              }
              return _historyList(records);
            },
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: GlassPanel(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.inventory_2_outlined,
                  size: 54,
                  color: scheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  _t('هنوز فایلی دریافت نشده', 'No received files yet'),
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  _t(
                    'فایل‌های دریافتی و گزارش کوتاه هر انتقال اینجا نگهداری می‌شوند.',
                    'Received files and a concise report for each transfer will appear here.',
                  ),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _historyList(List<QuickSendTransfer> records) {
    final completed = records
        .where((item) => item.state == QuickSendTransferState.completed)
        .length;
    final failed = records
        .where((item) => item.state == QuickSendTransferState.failed)
        .length;
    final active = records.length - completed - failed;
    final totalBytes = records
        .where((item) => item.state == QuickSendTransferState.completed)
        .fold<int>(0, (sum, item) => sum + item.totalBytes);

    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = constraints.maxWidth < 500 ? 12.0 : 22.0;
        return ListView.separated(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            16,
            horizontalPadding,
            40,
          ),
          itemCount: records.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final child = index == 0
                ? _summaryCard(
                    count: records.length,
                    completed: completed,
                    failed: failed,
                    active: active,
                    totalBytes: totalBytes,
                  )
                : _historyCard(records[index - 1]);
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: child,
              ),
            );
          },
        );
      },
    );
  }

  Widget _summaryCard({
    required int count,
    required int completed,
    required int failed,
    required int active,
    required int totalBytes,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return GlassPanel(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.history_rounded,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _t('فایل‌های دریافتی', 'Received files'),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _t(
                        '$count فایل • ${_formatBytes(totalBytes)} دریافت موفق',
                        '$count files • ${_formatBytes(totalBytes)} received successfully',
                      ),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _summaryChip(
                Icons.check_circle_outline_rounded,
                _t('$completed موفق', '$completed completed'),
                scheme.primary,
              ),
              if (failed > 0)
                _summaryChip(
                  Icons.error_outline_rounded,
                  _t('$failed ناموفق', '$failed failed'),
                  scheme.error,
                ),
              if (active > 0)
                _summaryChip(
                  Icons.downloading_rounded,
                  _t('$active در حال دریافت', '$active active'),
                  scheme.tertiary,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryChip(IconData icon, String label, Color color) {
    return Chip(
      avatar: Icon(icon, size: 18, color: color),
      label: Text(label),
      side: BorderSide(color: color.withValues(alpha: .34)),
      backgroundColor: color.withValues(alpha: .09),
    );
  }

  Widget _historyCard(QuickSendTransfer transfer) {
    final scheme = Theme.of(context).colorScheme;
    final completed = transfer.state == QuickSendTransferState.completed;
    final active =
        transfer.state == QuickSendTransferState.waiting ||
        transfer.state == QuickSendTransferState.transferring;
    final available =
        transfer.path.isNotEmpty && File(transfer.path).existsSync();
    final statusColor = completed
        ? scheme.primary
        : active
        ? scheme.tertiary
        : scheme.error;

    return GlassPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  completed
                      ? Icons.download_done_rounded
                      : active
                      ? Icons.downloading_rounded
                      : Icons.file_download_off_outlined,
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      transfer.fileName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _t(
                        'از ${transfer.deviceName} • ${_formatDate(transfer.updatedAt)}',
                        'From ${transfer.deviceName} • ${_formatDate(transfer.updatedAt)}',
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              _statusBadge(transfer.state, statusColor),
            ],
          ),
          const SizedBox(height: 14),
          LinearProgressIndicator(
            value: transfer.progress,
            minHeight: 5,
            borderRadius: BorderRadius.circular(99),
            color: statusColor,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              _detail(Icons.data_usage_rounded, _transferSizeText(transfer)),
              _detail(
                available
                    ? Icons.check_circle_outline_rounded
                    : Icons.link_off_rounded,
                available
                    ? _t('فایل در دسترس است', 'File is available')
                    : _t('فایل در دسترس نیست', 'File is unavailable'),
              ),
            ],
          ),
          if (transfer.path.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              transfer.path,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
          if (transfer.message.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                transfer.message,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
          if (completed) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: available
                      ? () => Navigator.of(context).pop(transfer)
                      : null,
                  icon: const Icon(Icons.ios_share_rounded),
                  label: Text(_t('اشتراک', 'Share')),
                ),
                OutlinedButton.icon(
                  onPressed: available
                      ? () => unawaited(_openFile(transfer))
                      : null,
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: Text(_t('باز کردن', 'Open')),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusBadge(QuickSendTransferState state, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        _stateLabel(state),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _detail(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17),
        const SizedBox(width: 5),
        Text(text, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  String _stateLabel(QuickSendTransferState state) {
    return switch (state) {
      QuickSendTransferState.waiting => _t('در انتظار', 'Waiting'),
      QuickSendTransferState.transferring => _t('در حال دریافت', 'Receiving'),
      QuickSendTransferState.completed => _t('کامل شد', 'Completed'),
      QuickSendTransferState.failed => _t('ناموفق', 'Failed'),
    };
  }

  String _transferSizeText(QuickSendTransfer transfer) {
    if (transfer.totalBytes <= 0) {
      return _t('اندازه نامشخص', 'Unknown size');
    }
    if (transfer.state == QuickSendTransferState.completed) {
      return _formatBytes(transfer.totalBytes);
    }
    return '${_formatBytes(transfer.transferredBytes)} / ${_formatBytes(transfer.totalBytes)}';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    final kb = bytes / 1024;
    if (kb < 1024) {
      return '${kb.toStringAsFixed(kb >= 100 ? 0 : 1)} KB';
    }
    final mb = kb / 1024;
    if (mb < 1024) {
      return '${mb.toStringAsFixed(mb >= 100 ? 0 : 1)} MB';
    }
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(gb >= 100 ? 0 : 1)} GB';
  }

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  Future<void> _openFile(QuickSendTransfer transfer) async {
    final opened = await _bridge.openFile(transfer.path);
    if (!opened && mounted) {
      _notice(_t('فایل باز نشد.', 'Could not open the file.'));
    }
  }

  Future<void> _openReceiveFolder(List<QuickSendTransfer> records) async {
    var opened = false;
    for (final transfer in records) {
      if (transfer.path.isNotEmpty && File(transfer.path).existsSync()) {
        opened = await _bridge.openContainingFolder(transfer.path);
        if (opened) {
          break;
        }
      }
    }
    if (!opened && Platform.isAndroid) {
      opened = await _bridge.openLocalistFolder();
    }
    if (!opened && mounted) {
      _notice(
        _t(
          'پوشه فایل‌های دریافتی باز نشد.',
          'Could not open the received files folder.',
        ),
      );
    }
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_sweep_outlined),
        title: Text(_t('پاک کردن تاریخچه؟', 'Clear transfer history?')),
        content: Text(
          _t(
            'فقط گزارش انتقال‌ها پاک می‌شود و فایل‌های دریافتی حذف نمی‌شوند.',
            'Only transfer records will be cleared. Received files will not be deleted.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(_t('لغو', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(_t('پاک کردن', 'Clear')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.service.clearReceivedHistory();
    }
  }

  void _notice(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
