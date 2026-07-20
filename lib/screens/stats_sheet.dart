import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/app_settings.dart';
import '../models/service_state.dart';
import '../widgets/glass.dart';

class StatsSheet extends StatefulWidget {
  const StatsSheet({
    super.key,
    required this.settings,
    required this.snapshot,
    required this.loadSnapshot,
    required this.onClose,
  });

  final AppSettings settings;
  final ServiceSnapshot snapshot;
  final Future<ServiceSnapshot> Function() loadSnapshot;
  final VoidCallback onClose;

  @override
  State<StatsSheet> createState() => _StatsSheetState();
}

class _StatsSheetState extends State<StatsSheet> {
  late ServiceSnapshot _snapshot;
  Timer? _refreshTimer;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _snapshot = widget.snapshot;
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _refreshSnapshot(),
    );
  }

  @override
  void didUpdateWidget(covariant StatsSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.snapshot != oldWidget.snapshot) {
      _snapshot = widget.snapshot;
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshSnapshot() async {
    if (_refreshing) {
      return;
    }
    _refreshing = true;
    try {
      final snapshot = await widget.loadSnapshot();
      if (mounted) {
        setState(() => _snapshot = snapshot);
      }
    } finally {
      _refreshing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final snapshot = _snapshot;
    final sharingActive = snapshot.proxyRunning || snapshot.root.active;
    final receivingActive =
        snapshot.receivingRunning || snapshot.localProxyRunning;
    final running = sharingActive || receivingActive || snapshot.vpnConnected;
    final rootMode = widget.settings.rootRoutingEnabled;
    final localIps = snapshot.localProxyIps.isNotEmpty
        ? snapshot.localProxyIps
        : snapshot.root.availableLocalIps;
    final endpointIps = widget.settings.shareAllRoutes
        ? localIps
        : localIps
              .where(widget.settings.isLocalIpSelected)
              .toList(growable: false);
    final activeProtocols = snapshot.protocols.isEmpty
        ? widget.settings.enabledProtocols
        : snapshot.protocols;
    final protocols = activeProtocols
        .map((protocol) => '${protocol.label}:${snapshot.portFor(protocol)}')
        .join(' / ');
    final remoteProxy = snapshot.remoteProxy;
    final scheme = Theme.of(context).colorScheme;
    final title = receivingActive
        ? l10n.receivingActive
        : sharingActive
        ? l10n.sharingActive
        : l10n.liveConnection;
    final sections = <Widget>[
      if (sharingActive) ...[
        _SectionLabel(label: l10n.sharing),
        _StatsGrid(
          items: [
            if (snapshot.proxyRunning)
              _StatsItem(
                label: l10n.proxy,
                value: protocols.isEmpty ? l10n.active : protocols,
                icon: Icons.hub_outlined,
              ),
            if (snapshot.root.active || rootMode)
              _StatsItem(
                label: l10n.root,
                value: snapshot.root.active
                    ? snapshot.root.vpnInterface
                    : l10n.ready,
                icon: Icons.admin_panel_settings_outlined,
              ),
            _StatsItem(
              label: l10n.hotspot,
              value: snapshot.hotspot.active ? l10n.detected : l10n.inactive,
              icon: Icons.wifi_tethering,
            ),
            if (endpointIps.isNotEmpty)
              _StatsItem(
                label: l10n.proxyIp,
                value: endpointIps.length == 1
                    ? endpointIps.first
                    : l10n.ipCount(endpointIps.length),
                icon: Icons.lan_outlined,
              ),
          ],
        ),
      ],
      if (receivingActive) ...[
        _SectionLabel(label: l10n.receiving),
        _StatsGrid(
          items: [
            if (snapshot.receivingRunning)
              _StatsItem(
                label: 'VPN',
                value: l10n.active,
                icon: Icons.vpn_lock_outlined,
              ),
            if (snapshot.localProxyRunning)
              _StatsItem(
                label: l10n.localProxy,
                value: '127.0.0.1:${snapshot.localProxyPort}',
                icon: Icons.settings_ethernet,
              ),
            if (remoteProxy != null)
              _StatsItem(
                label: l10n.remote,
                value: '${remoteProxy.protocol.label}:${remoteProxy.port}',
                icon: Icons.sync_alt,
              ),
            if (remoteProxy != null)
              _StatsItem(
                label: l10n.remoteHost,
                value: remoteProxy.host,
                icon: Icons.dns_outlined,
              ),
          ],
        ),
      ],
      if (running) ...[
        const SizedBox(height: 12),
        _SectionLabel(label: l10n.traffic),
        _StatsGrid(
          items: [
            _StatsItem(
              label: l10n.session,
              value: formatBytes(snapshot.usage.sessionTotalBytes),
              icon: Icons.query_stats,
            ),
            _StatsItem(
              label: l10n.total,
              value: formatBytes(snapshot.usage.totalBytes),
              icon: Icons.storage_outlined,
            ),
            _StatsItem(
              label: l10n.upload,
              value: formatBytes(snapshot.usage.sessionTxBytes),
              icon: Icons.north_east,
            ),
            _StatsItem(
              label: l10n.download,
              value: formatBytes(snapshot.usage.sessionRxBytes),
              icon: Icons.south_west,
            ),
          ],
        ),
      ],
    ];

    return DraggableScrollableSheet(
      initialChildSize: .56,
      minChildSize: .30,
      maxChildSize: .94,
      expand: false,
      builder: (context, scrollController) {
        return SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: _OpaqueSheetSurface(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 14, 10, 10),
                        child: Row(
                          children: [
                            Icon(Icons.query_stats, color: scheme.primary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l10n.stats,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    running ? title : l10n.idle,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: l10n.closeStats,
                              onPressed: widget.onClose,
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          children: sections,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(label, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.items});

  final List<_StatsItem> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 720
            ? 4
            : constraints.maxWidth >= 520
            ? 3
            : constraints.maxWidth >= 300
            ? 2
            : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            mainAxisExtent: 64,
          ),
          itemBuilder: (context, index) => _StatsCard(item: items[index]),
        );
      },
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.item});

  final _StatsItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: .34),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .26)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Icon(item.icon, color: scheme.primary, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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

class _StatsItem {
  const _StatsItem({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;
}
