import 'dart:async';
import 'package:flutter/material.dart';
import '../services/remote_device_service.dart';
import '../widgets/glass.dart';

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
        service.devices.where((d) => d.id != widget.localId),
        query: _search.text,
        tags: _tags,
        group: _group,
        sort: _sort,
      );
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
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: _t(
                  'جست‌وجوی نام، آیدی، مدل یا تگ',
                  'Search name, ID, model or tag',
                ),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  onPressed: () {
                    _search.clear();
                    setState(() {});
                  },
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
                    onSelected: (_) => setState(() => _group = group),
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
            DropdownButtonFormField<RemoteDeviceSort>(
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
              onChanged: (s) => setState(() => _sort = s!),
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
                      onSelected: (selected) => setState(() {
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
                final width = box.maxWidth >= 660
                    ? (box.maxWidth - 12) / 2
                    : box.maxWidth;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final device in visible)
                      SizedBox(
                        width: width,
                        child: Card(
                          margin: EdgeInsets.zero,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: widget.canConnect
                                ? () => widget.onConnect(device.id)
                                : null,
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        device.platform.toLowerCase().contains(
                                              'android',
                                            )
                                            ? Icons.phone_android
                                            : Icons.computer,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          device.name.isEmpty
                                              ? device.id
                                              : device.name,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.titleMedium,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: _t('علاقه‌مندی', 'Favorite'),
                                        onPressed: () => unawaited(
                                          service.setFavorite(
                                            device.id,
                                            !device.favorite,
                                          ),
                                        ),
                                        icon: Icon(
                                          device.favorite
                                              ? Icons.star
                                              : Icons.star_border,
                                        ),
                                      ),
                                    ],
                                  ),
                                  SelectableText(
                                    'ID: ${device.id}',
                                    textDirection: TextDirection.ltr,
                                  ),
                                  Text(
                                    [
                                      if (device.model.isNotEmpty) device.model,
                                      if (device.platform.isNotEmpty)
                                        device.platform,
                                      if (device.onLan)
                                        _t('در شبکه محلی', 'On LAN'),
                                    ].join(' • '),
                                  ),
                                  if (device.tags.isNotEmpty)
                                    Wrap(
                                      spacing: 6,
                                      children: [
                                        for (final tag in device.tags)
                                          Chip(
                                            label: Text(tag),
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                      ],
                                    ),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    children: [
                                      FilledButton.tonalIcon(
                                        onPressed: widget.canConnect
                                            ? () => widget.onConnect(device.id)
                                            : null,
                                        icon: const Icon(Icons.link),
                                        label: Text(_t('اتصال', 'Connect')),
                                      ),
                                      IconButton(
                                        tooltip: _t('ویرایش', 'Edit'),
                                        onPressed: () =>
                                            unawaited(_edit(device)),
                                        icon: const Icon(Icons.edit_outlined),
                                      ),
                                      IconButton(
                                        tooltip: _t('حذف', 'Delete'),
                                        onPressed: () =>
                                            unawaited(_forget(device)),
                                        icon: const Icon(Icons.delete_outline),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      );
    },
  );

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
