import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../services/log_service.dart';
import '../widgets/glass.dart';

class LogsPage extends StatelessWidget {
  const LogsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _LogsBody(pageMode: true);
  }
}

class LogsSheet extends StatelessWidget {
  const LogsSheet({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return DraggableScrollableSheet(
      initialChildSize: .76,
      minChildSize: .38,
      maxChildSize: .94,
      expand: false,
      builder: (context, scrollController) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: _OpaqueSheetSurface(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 10, 10),
                    child: Row(
                      children: [
                        Icon(Icons.subject_outlined, color: scheme.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            l10n.logs,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          tooltip: l10n.close,
                          onPressed: onClose,
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _LogsBody(
                      pageMode: false,
                      scrollController: scrollController,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LogsBody extends StatefulWidget {
  const _LogsBody({required this.pageMode, this.scrollController});

  final bool pageMode;
  final ScrollController? scrollController;

  @override
  State<_LogsBody> createState() => _LogsBodyState();
}

class _LogsBodyState extends State<_LogsBody> {
  LogSeverity? _filter;

  @override
  Widget build(BuildContext context) {
    final logs = LogService.instance;
    return AnimatedBuilder(
      animation: logs,
      builder: (context, _) {
        final entries = logs.entries
            .where((entry) => _filter == null || entry.severity == _filter)
            .toList();
        final controls = _LogControls(
          filter: _filter,
          onFilterChanged: (value) => setState(() => _filter = value),
        );
        final list = _LogList(entries: entries);

        if (widget.pageMode) {
          return PageSurface(
            children: [
              GlassPanel(child: controls),
              GlassPanel(child: list),
            ],
          );
        }

        return ListView(
          controller: widget.scrollController,
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
          children: [
            _SheetFrame(child: controls),
            const SizedBox(height: 10),
            _SheetFrame(child: list),
          ],
        );
      },
    );
  }
}

class _LogControls extends StatelessWidget {
  const _LogControls({required this.filter, required this.onFilterChanged});

  final LogSeverity? filter;
  final ValueChanged<LogSeverity?> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    final logs = LogService.instance;
    final l10n = context.l10n;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilterChip(
          label: Text(l10n.all),
          selected: filter == null,
          onSelected: (_) => onFilterChanged(null),
        ),
        for (final severity in LogSeverity.values)
          FilterChip(
            label: Text(_severityLabel(l10n, severity)),
            selected: filter == severity,
            onSelected: (_) => onFilterChanged(severity),
          ),
        IconButton.filledTonal(
          tooltip: l10n.copyLogs,
          onPressed: logs.entries.isEmpty
              ? null
              : () => Clipboard.setData(ClipboardData(text: logs.dump())),
          icon: const Icon(Icons.copy_all_outlined),
        ),
        IconButton.filledTonal(
          tooltip: l10n.clearLogs,
          onPressed: logs.entries.isEmpty ? null : logs.clear,
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    );
  }
}

class _LogList extends StatelessWidget {
  const _LogList({required this.entries});

  final List<LogEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(child: Text(context.l10n.noLogsYet)),
      );
    }
    return Column(
      children: [for (final entry in entries) _LogTile(entry: entry)],
    );
  }
}

String _severityLabel(AppLocalizations l10n, LogSeverity severity) {
  return switch (severity) {
    LogSeverity.info => l10n.logInfo,
    LogSeverity.warning => l10n.logWarning,
    LogSeverity.error => l10n.logError,
  };
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: .30),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .24)),
      ),
      child: Padding(padding: const EdgeInsets.all(14), child: child),
    );
  }
}

class _OpaqueSheetSurface extends StatelessWidget {
  const _OpaqueSheetSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: child,
      ),
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.entry});

  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (entry.severity) {
      LogSeverity.info => scheme.primary,
      LogSeverity.warning => Colors.amber.shade700,
      LogSeverity.error => scheme.error,
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.circle, color: color, size: 12),
      title: Text(entry.message),
      subtitle: Text(entry.timestamp.toLocal().toString()),
      dense: true,
    );
  }
}
