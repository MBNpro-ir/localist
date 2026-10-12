import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../remote/remote_peer_presence.dart';
import '../services/remote_device_service.dart';
import '../widgets/glass.dart';

enum RemoteDeviceView { compact, cards, list }

class RemoteAddressBook extends StatefulWidget {
  const RemoteAddressBook({
    super.key,
    required this.service,
    required this.localId,
    required this.onConnect,
    required this.canConnect,
  });
  final RemoteDeviceService service;
  final String localId;
  final ValueChanged<String> onConnect;
  final bool canConnect;
  @override
  State<RemoteAddressBook> createState() => _RemoteAddressBookState();
}

class _RemoteAddressBookState extends State<RemoteAddressBook> {
  final _search = TextEditingController();
  RemoteDeviceGroup _group = RemoteDeviceGroup.all;
  RemoteDeviceSort _sort = RemoteDeviceSort.recent;
  final Set<String> _tags = {};
  RemoteDeviceView _view = RemoteDeviceView.compact;
  int _page = 0;
  static const _pageSize = 12;
  Future<void> _viewWrite = Future<void>.value();
  @override
  void initState() {
    super.initState();
    unawaited(_loadView());
  }

  Future<void> _loadView() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('remote.devices.view.v1');
    if (!mounted) return;
    setState(
      () => _view = RemoteDeviceView.values.firstWhere(
        (view) => view.name == saved,
        orElse: () => RemoteDeviceView.compact,
      ),
    );
  }

  void _changeView(RemoteDeviceView view) {
    setState(() => _view = view);
    _viewWrite = _viewWrite.catchError((Object _) {}).then((_) async {
      await (await SharedPreferences.getInstance()).setString(
        'remote.devices.view.v1',
        view.name,
      );
    });
  }

  void _filter(VoidCallback update) => setState(() {
    update();
    _page = 0;
  });
  String _t(String fa, String en) =>
      Localizations.localeOf(context).languageCode == 'fa' ? fa : en;
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.service,
    builder: (context, _) {
      final service = widget.service;
      final visible = filterRemoteDevices(
        service.devices.where(
          (d) => d.id != widget.localId.replaceAll(RegExp(r'\s'), ''),
        ),
        query: _search.text,
        tags: _tags,
        group: _group,
        sort: _sort,
      );
      final pages = (visible.length / _pageSize).ceil().clamp(1, 1000);
      final page = _page.clamp(0, pages - 1);
      final items = visible.skip(page * _pageSize).take(_pageSize);
      return GlassPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _t('دفترچه آدرس و دستگاه‌ها', 'Address Book & devices'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => unawaited(_edit()),
                  icon: const Icon(Icons.add),
                  label: Text(_t('افزودن دستگاه', 'Add device')),
                ),
                OutlinedButton.icon(
                  onPressed: service.scanning
                      ? null
                      : () => unawaited(service.scan(localId: widget.localId)),
                  icon: const Icon(Icons.radar),
                  label: Text(
                    service.scanning
                        ? _t('در حال جست‌وجو…', 'Scanning…')
                        : _t('جست‌وجوی شبکه', 'Scan LAN'),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: service.tags.isEmpty
                      ? null
                      : () => unawaited(_manageTags()),
                  icon: const Icon(Icons.sell_outlined),
                  label: Text(_t('مدیریت تگ‌ها', 'Manage tags')),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _search,
              onChanged: (_) => _filter(() {}),
              decoration: InputDecoration(
                labelText: _t(
                  'جست‌وجوی نام، آیدی، مدل یا تگ',
                  'Search name, ID, model or tag',
                ),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  onPressed: () => _filter(_search.clear),
                  icon: const Icon(Icons.clear),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final group in RemoteDeviceGroup.values)
                  ChoiceChip(
                    selected: _group == group,
                    onSelected: (_) => _filter(() => _group = group),
                    label: Text(switch (group) {
                      RemoteDeviceGroup.all => _t('همه', 'All'),
                      RemoteDeviceGroup.recent => _t('اخیر', 'Recent'),
                      RemoteDeviceGroup.favorites => _t(
                        'علاقه‌مندی',
                        'Favorites',
                      ),
                      RemoteDeviceGroup.addressBook => _t(
                        'دفترچه آدرس',
                        'Address Book',
                      ),
                      RemoteDeviceGroup.lan => _t('شبکه محلی', 'LAN'),
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, box) {
                final wide = box.maxWidth >= 600;
                final sort = DropdownButtonFormField<RemoteDeviceSort>(
                  initialValue: _sort,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: _t('مرتب‌سازی', 'Sort by'),
                  ),
                  items: [
                    for (final sort in RemoteDeviceSort.values)
                      DropdownMenuItem(
                        value: sort,
                        child: Text(switch (sort) {
                          RemoteDeviceSort.recent => _t(
                            'آخرین اتصال',
                            'Last connection',
                          ),
                          RemoteDeviceSort.name => _t('نام', 'Name'),
                          RemoteDeviceSort.id => _t('شناسه', 'ID'),
                          RemoteDeviceSort.oldest => _t(
                            'قدیمی‌ترین',
                            'Oldest saved',
                          ),
                        }),
                      ),
                  ],
                  onChanged: (s) => _filter(() => _sort = s!),
                );
                final views = Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final view in RemoteDeviceView.values)
                      ChoiceChip(
                        key: ValueKey('device-view-${view.name}'),
                        selected: _view == view,
                        onSelected: (_) => _changeView(view),
                        avatar: Icon(switch (view) {
                          RemoteDeviceView.compact =>
                            Icons.view_comfy_alt_outlined,
                          RemoteDeviceView.cards => Icons.grid_view,
                          RemoteDeviceView.list => Icons.view_list_outlined,
                        }, size: 18),
                        label: Text(switch (view) {
                          RemoteDeviceView.compact => _t('فشرده', 'Compact'),
                          RemoteDeviceView.cards => _t('کارت', 'Cards'),
                          RemoteDeviceView.list => _t('فهرست', 'List'),
                        }),
                      ),
                  ],
                );
                return wide
                    ? Row(
                        children: [
                          Expanded(child: sort),
                          const SizedBox(width: 18),
                          Flexible(child: views),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [sort, const SizedBox(height: 10), views],
                      );
              },
            ),
            if (service.tags.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tag in service.tags)
                    FilterChip(
                      label: Text(tag),
                      selected: _tags.contains(tag),
                      onSelected: (selected) => _filter(() {
                        selected ? _tags.add(tag) : _tags.remove(tag);
                      }),
                    ),
                ],
              ),
            ],
            if (service.scanning)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(),
              ),
            if (service.error.isNotEmpty) Text(service.error),
            const SizedBox(height: 16),
            if (visible.isEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _t(
                    'دستگاهی با این فیلتر یافت نشد.',
                    'No devices match these filters.',
                  ),
                ),
              ),
            LayoutBuilder(
              builder: (context, box) {
                final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
                final minimum =
                    (_view == RemoteDeviceView.cards ? 310.0 : 270.0) *
                    scale.clamp(1.0, 2.0);
                final columns = _view == RemoteDeviceView.list
                    ? 1
                    : ((box.maxWidth + 12) / (minimum + 12)).floor().clamp(
                        1,
                        4,
                      );
                final width = (box.maxWidth - 12 * (columns - 1)) / columns;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final device in items)
                      SizedBox(width: width, child: _tile(device)),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  _t('${visible.length} دستگاه', '${visible.length} devices'),
                ),
                if (pages > 1) ...[
                  IconButton(
                    key: const ValueKey('devices-previous'),
                    tooltip: _t('صفحه قبل', 'Previous page'),
                    onPressed: page == 0
                        ? null
                        : () => setState(() => _page = page - 1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text(
                    _t(
                      'صفحه ${page + 1} از $pages',
                      'Page ${page + 1} of $pages',
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('devices-next'),
                    tooltip: _t('صفحه بعد', 'Next page'),
                    onPressed: page + 1 >= pages
                        ? null
                        : () => setState(() => _page = page + 1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ],
            ),
          ],
        ),
      );
    },
  );

  Widget _status(RemoteDevice device) {
    final state = widget.service.presenceOf(device);
    final colors = Theme.of(context).colorScheme;
    final color = switch (state) {
      RemotePeerPresence.online => colors.primary,
      RemotePeerPresence.offline => colors.error,
      RemotePeerPresence.unknown => colors.onSurfaceVariant,
    };
    final label = switch (state) {
      RemotePeerPresence.online =>
        device.onLan
            ? _t('آنلاین • شبکه محلی', 'Online • LAN')
            : _t('آنلاین', 'Online'),
      RemotePeerPresence.offline => _t('آفلاین', 'Offline'),
      RemotePeerPresence.unknown => _t('وضعیت نامشخص', 'Status unknown'),
    };
    return Tooltip(
      message: state == RemotePeerPresence.unknown
          ? _t(
              'هنوز پاسخ تازه‌ای از سرور دریافت نشده است.',
              'No recent server response is available.',
            )
          : label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: color),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(RemoteDevice device) {
    final colors = Theme.of(context).colorScheme;
    final details = [
      if (device.model.isNotEmpty) device.model,
      if (device.platform.isNotEmpty) device.platform,
      ...device.tags,
    ].join(' • ');
    final icon = device.platform.toLowerCase().contains('android')
        ? Icons.phone_android
        : device.platform.toLowerCase().contains('ios')
        ? Icons.phone_iphone
        : Icons.computer;
    final menu = PopupMenuButton<String>(
      tooltip: _t('گزینه‌های دستگاه', 'Device options'),
      onSelected: (action) {
        switch (action) {
          case 'edit':
            unawaited(_edit(device));
          case 'favorite':
            unawaited(widget.service.setFavorite(device.id, !device.favorite));
          case 'delete':
            unawaited(_forget(device));
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'favorite',
          child: ListTile(
            dense: true,
            leading: Icon(device.favorite ? Icons.star : Icons.star_border),
            title: Text(
              device.favorite
                  ? _t('حذف از علاقه‌مندی', 'Unfavorite')
                  : _t('علاقه‌مندی', 'Favorite'),
            ),
          ),
        ),
        PopupMenuItem(
          value: 'edit',
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.edit_outlined),
            title: Text(_t('ویرایش', 'Edit')),
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.delete_outline),
            title: Text(_t('حذف', 'Delete')),
          ),
        ),
      ],
    );
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          device.name.isEmpty ? device.id : device.name,
          style: Theme.of(context).textTheme.titleSmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (device.name.isNotEmpty)
          Text(
            'ID: ${device.id}',
            textDirection: TextDirection.ltr,
            style: Theme.of(context).textTheme.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        const SizedBox(height: 5),
        _status(device),
        if (details.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Tooltip(
              message: details,
              child: Text(
                details,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: _view == RemoteDeviceView.cards ? 2 : 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
      ],
    );
    return Card(
      key: ValueKey('device-${device.id}'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.canConnect ? () => widget.onConnect(device.id) : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: _view == RemoteDeviceView.cards
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(icon, size: 42, color: colors.primary),
                        if (device.favorite)
                          const Padding(
                            padding: EdgeInsets.all(6),
                            child: Icon(Icons.star, size: 16),
                          ),
                        const Spacer(),
                        menu,
                      ],
                    ),
                    const SizedBox(height: 8),
                    info,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      children: [
                        Icon(icon, color: colors.primary),
                        if (device.favorite) const Icon(Icons.star, size: 14),
                      ],
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: info),
                    menu,
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _forget(RemoteDevice device) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_t('حذف دستگاه ذخیره‌شده', 'Remove saved device')),
        content: Text(device.name.isEmpty ? device.id : device.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_t('لغو', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_t('حذف', 'Remove')),
          ),
        ],
      ),
    );
    if (ok == true) await widget.service.forget(device.id);
  }

  Future<void> _edit([RemoteDevice? device]) async {
    final id = TextEditingController(text: device?.id);
    final name = TextEditingController(text: device?.name);
    final model = TextEditingController(text: device?.model);
    final tags = TextEditingController(text: device?.tags.join(', '));
    String? error;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text(_t('ذخیره دستگاه', 'Save device')),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: id,
                    readOnly: device != null,
                    decoration: InputDecoration(
                      labelText: _t('شناسه یا IP', 'ID or IP'),
                      errorText: error,
                    ),
                  ),
                  TextField(
                    controller: name,
                    maxLength: 160,
                    decoration: InputDecoration(
                      labelText: _t('نام دلخواه', 'Custom name'),
                    ),
                  ),
                  TextField(
                    controller: model,
                    decoration: InputDecoration(
                      labelText: _t('مدل دستگاه', 'Device model'),
                    ),
                  ),
                  TextField(
                    controller: tags,
                    decoration: InputDecoration(
                      labelText: _t(
                        'تگ‌ها (جداشده با ویرگول)',
                        'Tags (comma separated)',
                      ),
                    ),
                  ),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final tag in widget.service.tags)
                        ActionChip(
                          label: Text(tag),
                          onPressed: () {
                            final values =
                                tags.text
                                    .split(RegExp('[,،]'))
                                    .map((s) => s.trim())
                                    .where((s) => s.isNotEmpty)
                                    .toSet()
                                  ..add(tag);
                            tags.text = values.join(', ');
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(_t('لغو', 'Cancel')),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await widget.service.saveAddress(
                    id: id.text,
                    name: name.text,
                    model: model.text,
                    tags: tags.text.split(RegExp('[,،]')),
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  if (ctx.mounted) update(() => error = '$e');
                }
              },
              child: Text(_t('ذخیره', 'Save')),
            ),
          ],
        ),
      ),
    );
    for (final c in [id, name, model, tags]) {
      c.dispose();
    }
  }

  Future<void> _manageTags() async {
    final old = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(_t('ویرایش تگ', 'Edit tag')),
        children: [
          for (final tag in widget.service.tags)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, tag),
              child: Text(tag),
            ),
        ],
      ),
    );
    if (old == null || !mounted) return;
    final name = TextEditingController(text: old);
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_t('نام تگ', 'Tag name')),
        content: TextField(controller: name, maxLength: 60),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(_t('لغو', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ''),
            child: Text(
              _t('حذف تگ از همه دستگاه‌ها', 'Remove tag from all devices'),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, name.text.trim()),
            child: Text(_t('ذخیره', 'Save')),
          ),
        ],
      ),
    );
    name.dispose();
    if (value != null) {
      await widget.service.renameTag(old, value);
      if (mounted) {
        setState(() {
          if (_tags.remove(old) && value.isNotEmpty) _tags.add(value);
        });
      }
    }
  }
}
