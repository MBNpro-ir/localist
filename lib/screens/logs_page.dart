import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/log_service.dart';
import '../widgets/glass.dart';

class LogsPage extends StatefulWidget {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
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
        return PageSurface(
          children: [
            GlassPanel(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilterChip(
                    label: const Text('All'),
                    selected: _filter == null,
                    onSelected: (_) => setState(() => _filter = null),
                  ),
                  for (final severity in LogSeverity.values)
                    FilterChip(
                      label: Text(severity.label),
                      selected: _filter == severity,
                      onSelected: (_) => setState(() => _filter = severity),
                    ),
                  IconButton.filledTonal(
                    tooltip: 'Copy logs',
                    onPressed: logs.entries.isEmpty
                        ? null
                        : () => Clipboard.setData(
                            ClipboardData(text: logs.dump()),
                          ),
                    icon: const Icon(Icons.copy_all_outlined),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Clear logs',
                    onPressed: logs.entries.isEmpty ? null : logs.clear,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
            GlassPanel(
              child: entries.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(child: Text('No logs yet')),
                    )
                  : Column(
                      children: [
                        for (final entry in entries) _LogTile(entry: entry),
                      ],
                    ),
            ),
          ],
        );
      },
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
