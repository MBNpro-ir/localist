import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../services/native_bridge_service.dart';

/// Handles the OLE drop events used by Explorer on the Flutter child window.
/// The runner's WM_DROPFILES handler remains available for legacy shell drops.
class QuickSendDropTarget extends StatefulWidget {
  const QuickSendDropTarget({
    super.key,
    required this.child,
    required this.onFilesDropped,
    required this.enabled,
  });

  final Widget child;
  final ValueChanged<List<QuickSendSharedFile>> onFilesDropped;
  final bool enabled;

  @override
  State<QuickSendDropTarget> createState() => _QuickSendDropTargetState();
}

class _QuickSendDropTargetState extends State<QuickSendDropTarget> {
  bool _dragging = false;

  void _setDragging(bool value) {
    if (mounted && _dragging != value) {
      setState(() => _dragging = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DropTarget(
      enable: widget.enabled,
      onDragEntered: (_) => _setDragging(true),
      onDragExited: (_) => _setDragging(false),
      onDragDone: (details) {
        _setDragging(false);
        final files = [
          for (final file in details.files)
            if (file.path.trim().isNotEmpty)
              QuickSendSharedFile(path: file.path, name: file.name),
        ];
        if (files.isNotEmpty) {
          widget.onFilesDropped(files);
        }
      },
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          if (_dragging && widget.enabled)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  key: const ValueKey('quick-send-drop-highlight'),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: .08),
                    border: Border.all(color: scheme.primary, width: 2),
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
