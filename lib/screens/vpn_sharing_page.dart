import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

class VpnSharingPage extends StatefulWidget {
  const VpnSharingPage({
    super.key,
    required this.sharing,
    required this.receiving,
    required this.sharingActive,
    required this.receivingActive,
    this.busy = false,
  });
  final Widget sharing, receiving;
  final bool sharingActive, receivingActive, busy;
  @override
  State<VpnSharingPage> createState() => _VpnSharingPageState();
}

class _VpnSharingPageState extends State<VpnSharingPage> {
  bool _receive = false;
  @override
  Widget build(BuildContext context) {
    final receiving =
        widget.receivingActive || (!widget.sharingActive && _receive);
    return Column(
      children: [
        if (!widget.sharingActive && !widget.receivingActive)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: false,
                  icon: const Icon(Icons.share_outlined),
                  label: Text(context.l10n.sharing),
                ),
                ButtonSegment(
                  value: true,
                  icon: const Icon(Icons.download_outlined),
                  label: Text(context.l10n.receiving),
                ),
              ],
              selected: {receiving},
              onSelectionChanged: widget.busy
                  ? null
                  : (v) => setState(() => _receive = v.single),
            ),
          ),
        Expanded(child: receiving ? widget.receiving : widget.sharing),
      ],
    );
  }
}
