import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/transfer_history_filter.dart';
import '../services/native_bridge_service.dart';
import '../services/quick_send_service.dart';
import '../widgets/glass.dart';
import '../widgets/received_media_preview.dart';

class TransferHistoryPage extends StatefulWidget {
  const TransferHistoryPage({super.key, required this.service});

  final QuickSendService service;

  @override
  State<TransferHistoryPage> createState() => _TransferHistoryPageState();
}

class _TransferHistoryPageState extends State<TransferHistoryPage> {
  final NativeBridgeService _bridge = NativeBridgeService.instance;
  String _query = '';
  String _category = 'All';
  HistoryPeriod _period = HistoryPeriod.all;
  HistorySort _sort = HistorySort.newest;
  QuickSendTransferState? _state;
  bool _gallery = true;

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
    final filtered = TransferHistoryFilter(
      query: _query,
      category: _category,
      period: _period,
      sort: _sort,
      state: _state,
    ).apply(records);
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
        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                16,
                horizontalPadding,
                16,
              ),
              sliver: SliverToBoxAdapter(
                child: Column(
                  children: [
                    _summaryCard(
                      count: records.length,
                      completed: completed,
                      failed: failed,
                      active: active,
                      totalBytes: totalBytes,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      onChanged: (value) => setState(() => _query = value),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: _t(
                          'جستجوی فایل، دستگاه یا مسیر',
                          'Search files, devices or paths',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final category in [
                            'All',
                            'Images',
                            'Videos',
                            'Audio',
                            'Documents',
                            'Archives',
                            'Apps',
                            'Other',
                          ])
                            Padding(
                              padding: const EdgeInsetsDirectional.only(end: 8),
                              child: ChoiceChip(
                                selected: _category == category,
                                label: Text(_categoryLabel(category)),
                                avatar: Icon(_categoryIcon(category), size: 18),
                                onSelected: (_) =>
                                    setState(() => _category = category),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        DropdownButton<HistoryPeriod>(
                          value: _period,
                          items: [
                            for (final period in HistoryPeriod.values)
                              DropdownMenuItem(
                                value: period,
                                child: Text(switch (period) {
                                  HistoryPeriod.all => _t(
                                    'همهٔ زمان‌ها',
                                    'All dates',
                                  ),
                                  HistoryPeriod.today => _t('امروز', 'Today'),
                                  HistoryPeriod.week => _t(
                                    '۷ روز اخیر',
                                    'Last 7 days',
                                  ),
                                  HistoryPeriod.month => _t(
                                    '۳۰ روز اخیر',
                                    'Last 30 days',
                                  ),
                                }),
                              ),
                          ],
                          onChanged: (value) =>
                              setState(() => _period = value!),
                        ),
                        DropdownButton<HistorySort>(
                          value: _sort,
                          items: [
                            for (final sort in HistorySort.values)
                              DropdownMenuItem(
                                value: sort,
                                child: Text(switch (sort) {
                                  HistorySort.newest => _t(
                                    'جدیدترین',
                                    'Newest',
                                  ),
                                  HistorySort.oldest => _t(
                                    'قدیمی‌ترین',
                                    'Oldest',
                                  ),
                                  HistorySort.name => _t(
                                    'نام فایل',
                                    'File name',
                                  ),
                                  HistorySort.largest => _t(
                                    'بزرگ‌ترین',
                                    'Largest',
                                  ),
                                  HistorySort.smallest => _t(
                                    'کوچک‌ترین',
                                    'Smallest',
                                  ),
                                  HistorySort.device => _t('دستگاه', 'Device'),
                                }),
                              ),
                          ],
                          onChanged: (value) => setState(() => _sort = value!),
                        ),
                        DropdownButton<String>(
                          value: _state?.name ?? 'all',
                          items: [
                            DropdownMenuItem(
                              value: 'all',
                              child: Text(_t('همهٔ وضعیت‌ها', 'All statuses')),
                            ),
                            for (final state in QuickSendTransferState.values)
                              DropdownMenuItem(
                                value: state.name,
                                child: Text(_stateLabel(state)),
                              ),
                          ],
                          onChanged: (value) => setState(
                            () => _state = QuickSendTransferState.values
                                .where((s) => s.name == value)
                                .firstOrNull,
                          ),
                        ),
                        IconButton(
                          onPressed: () => setState(() => _gallery = !_gallery),
                          tooltip: _gallery
                              ? _t('نمای فهرست', 'List view')
                              : _t('نمای گالری', 'Gallery view'),
                          icon: Icon(
                            _gallery
                                ? Icons.view_list_outlined
                                : Icons.grid_view_rounded,
                          ),
                        ),
                      ],
                    ),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        _t(
                          '${filtered.length} مورد',
                          '${filtered.length} items',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (filtered.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: records.isEmpty
                    ? _emptyState()
                    : Center(
                        child: Text(
                          _t('موردی مطابق فیلتر نیست', 'No matching files'),
                        ),
                      ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  0,
                  horizontalPadding,
                  40,
                ),
                sliver: _gallery
                    ? SliverGrid.builder(
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 290,
                              mainAxisExtent: 250,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                            ),
                        itemCount: filtered.length,
                        itemBuilder: (_, index) =>
                            _galleryCard(filtered[index]),
                      )
                    : SliverList.builder(
                        itemCount: filtered.length,
                        itemBuilder: (_, index) {
                          final transfer = filtered[index];
                          final date = transfer.updatedAt.toLocal();
                          final previous = index == 0
                              ? null
                              : filtered[index - 1].updatedAt.toLocal();
                          final showDate =
                              (_sort == HistorySort.newest ||
                                  _sort == HistorySort.oldest) &&
                              (previous == null ||
                                  previous.year != date.year ||
                                  previous.month != date.month ||
                                  previous.day != date.day);
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (showDate)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  child: Text(
                                    '${date.year}/${date.month}/${date.day}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
                                  ),
                                ),
                              Card(
                                child: ListTile(
                                  leading: Icon(
                                    _categoryIcon(
                                      TransferHistoryFilter.categoryOf(
                                        transfer,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    transfer.fileName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    '${transfer.deviceName} • ${_formatBytes(transfer.totalBytes)}\n${_stateLabel(transfer.state)} • ${_formatDate(transfer.updatedAt)}',
                                  ),
                                  isThreeLine: true,
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => _showDetails(transfer),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
              ),
          ],
        );
      },
    );
  }

  String _categoryLabel(String category) => switch (category) {
    'All' => _t('همه', 'All'),
    'Images' => _t('عکس‌ها', 'Photos'),
    'Videos' => _t('ویدیوها', 'Videos'),
    'Audio' => _t('موسیقی', 'Music'),
    'Documents' => _t('اسناد', 'Documents'),
    'Archives' => _t('آرشیو', 'Archives'),
    'Apps' => _t('برنامه‌ها', 'Apps'),
    _ => _t('سایر', 'Other'),
  };
  IconData _categoryIcon(String category) => switch (category) {
    'Images' => Icons.image_outlined,
    'Videos' => Icons.movie_outlined,
    'Audio' => Icons.music_note_outlined,
    'Documents' => Icons.description_outlined,
    'Archives' => Icons.folder_zip_outlined,
    'Apps' => Icons.apps,
    _ => Icons.folder_outlined,
  };
  Widget _galleryCard(QuickSendTransfer transfer) {
    final scheme = Theme.of(context).colorScheme;
    final category = TransferHistoryFilter.categoryOf(transfer);
    final isImage =
        category == 'Images' &&
        transfer.state == QuickSendTransferState.completed;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showDetails(transfer),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SizedBox(
                width: double.infinity,
                child: ColoredBox(
                  color: scheme.surfaceContainerHighest,
                  child: isImage
                      ? Image.file(
                          File(transfer.path),
                          fit: BoxFit.cover,
                          cacheWidth: 480,
                          errorBuilder: (_, _, _) => Icon(
                            Icons.broken_image_outlined,
                            size: 44,
                            color: scheme.onSurfaceVariant,
                          ),
                        )
                      : category == 'Videos' &&
                            transfer.state == QuickSendTransferState.completed
                      ? ReceivedVideoPreview(path: transfer.path)
                      : Icon(
                          _categoryIcon(category),
                          size: 54,
                          color: scheme.primary,
                        ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    transfer.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_formatBytes(transfer.totalBytes)} • ${transfer.deviceName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_stateLabel(transfer.state)} • ${_formatDate(transfer.updatedAt)}',
                    maxLines: 1,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
            if (transfer.state == QuickSendTransferState.transferring)
              LinearProgressIndicator(value: transfer.progress),
          ],
        ),
      ),
    );
  }

  Future<void> _showDetails(QuickSendTransfer transfer) async {
    final share = await showModalBottomSheet<QuickSendTransfer>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: _historyCard(transfer),
        ),
      ),
    );
    if (share != null && mounted) Navigator.of(context).pop(share);
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
