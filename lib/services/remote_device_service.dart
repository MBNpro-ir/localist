import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

import 'package:shared_preferences/shared_preferences.dart';
import '../remote/remote_peer_presence.dart';

class RemoteDevice {
  const RemoteDevice({
    required this.id,
    this.name = '',
    this.model = '',
    this.platform = '',
    this.ip = '',
    this.lastSeen,
    this.lastOpened,
    this.tags = const [],
    this.favorite = false,
    this.inAddressBook = false,
    this.createdAt,
  });
  final String id, name, model, platform, ip;
  final DateTime? lastSeen, lastOpened;
  final DateTime? createdAt;
  final List<String> tags;
  final bool favorite, inAddressBook;
  bool get onLan =>
      lastSeen != null &&
      DateTime.now().difference(lastSeen!) < const Duration(seconds: 30);
  RemoteDevice copyWith({
    String? name,
    String? model,
    String? platform,
    String? ip,
    DateTime? lastSeen,
    DateTime? lastOpened,
    List<String>? tags,
    bool? favorite,
    bool? inAddressBook,
    DateTime? createdAt,
  }) => RemoteDevice(
    id: id,
    name: name ?? this.name,
    model: model ?? this.model,
    platform: platform ?? this.platform,
    ip: ip ?? this.ip,
    lastSeen: lastSeen ?? this.lastSeen,
    lastOpened: lastOpened ?? this.lastOpened,
    tags: tags ?? this.tags,
    favorite: favorite ?? this.favorite,
    inAddressBook: inAddressBook ?? this.inAddressBook,
    createdAt: createdAt ?? this.createdAt,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'model': model,
    'platform': platform,
    'ip': ip,
    'lastOpened': lastOpened?.toIso8601String(),
    'createdAt': createdAt?.toIso8601String(),
    'tags': tags,
    'favorite': favorite,
    'inAddressBook': inAddressBook,
  };
  factory RemoteDevice.fromJson(Map<String, dynamic> json) => RemoteDevice(
    id: (json['id'] as String).trim().replaceAll(RegExp(r'\s'), ''),
    name: json['name'] as String? ?? '',
    model: json['model'] as String? ?? '',
    platform: json['platform'] as String? ?? '',
    ip: json['ip'] as String? ?? '',
    lastOpened: DateTime.tryParse(json['lastOpened'] as String? ?? ''),
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
    tags: (json['tags'] as List? ?? []).whereType<String>().take(30).toList(),
    favorite: json['favorite'] == true,
    inAddressBook: json.containsKey('inAddressBook')
        ? json['inAddressBook'] == true
        : (json['name'] as String? ?? '').isNotEmpty,
  );
}

/// Bounded protobuf adapter for PeerDiscovery in upstream rendezvous.proto.
/// Network advertisements never confer trust or automatically open a session.
class RemoteDiscoveryProtocol {
  static List<int> _varint(int value) {
    final bytes = <int>[];
    do {
      bytes.add((value & 127) | (value > 127 ? 128 : 0));
      value >>= 7;
    } while (value > 0);
    return bytes;
  }

  static List<int> field(int number, String value) {
    final data = utf8.encode(value);
    return [..._varint((number << 3) | 2), ..._varint(data.length), ...data];
  }

  static Uint8List ping(String localId) {
    final message = [...field(1, 'ping'), ...field(3, localId)];
    return Uint8List.fromList([
      ..._varint((22 << 3) | 2),
      ..._varint(message.length),
      ...message,
    ]);
  }

  static Map<int, List<int>> _fields(List<int> bytes) {
    var offset = 0;
    int number() {
      var value = 0;
      for (var i = 0; i < 10 && offset < bytes.length; i++) {
        final byte = bytes[offset++];
        value |= (byte & 127) << (i * 7);
        if (byte < 128) return value;
      }
      throw const FormatException('Malformed discovery packet');
    }

    final result = <int, List<int>>{};
    while (offset < bytes.length) {
      final tag = number();
      if (tag >> 3 == 0) {
        throw const FormatException('Invalid protobuf tag');
      }
      switch (tag & 7) {
        case 0:
          number();
          break;
        case 1:
          offset += 8;
          break;
        case 5:
          offset += 4;
          break;
        case 2:
          final size = number();
          if (size < 0 || offset + size > bytes.length) {
            throw const FormatException('Truncated discovery packet');
          }
          result[tag >> 3] = bytes.sublist(offset, offset + size);
          offset += size;
          break;
        default:
          throw const FormatException('Unsupported protobuf wire type');
      }
      if (offset > bytes.length) {
        throw const FormatException('Truncated discovery packet');
      }
    }
    return result;
  }

  static RemoteDevice? decode(List<int> data, String ip, {DateTime? now}) {
    if (data.length > 4096) return null;
    try {
      final nested = _fields(data)[22];
      if (nested == null) return null;
      final fields = _fields(nested);
      String value(int key) => utf8.decode(fields[key] ?? []);
      final id = value(3);
      if (value(1) != 'pong' ||
          id.isEmpty ||
          id.length > 200 ||
          id.startsWith('-') ||
          id.contains(RegExp(r'[\s\x00-\x1f]'))) {
        return null;
      }
      // Upstream advertises hostname/platform, not the hardware model.
      return RemoteDevice(
        id: id,
        name: value(5),
        platform: value(6),
        ip: ip,
        lastSeen: now ?? DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }
}

class RemoteDeviceService extends ChangeNotifier {
  RemoteDeviceService({this.queryPresence, DateTime Function()? now})
    : _presence = RemotePeerPresenceStore(now: now);

  final Future<Map<String, String>> Function(List<String>)? queryPresence;
  final RemotePeerPresenceStore _presence;
  Timer? _presenceTimer;
  Future<void>? _polling;
  String _presenceServer = '';
  bool _presenceReady = false;
  int _presenceGeneration = 0;
  RemotePeerPresence presenceOf(RemoteDevice device) =>
      device.onLan ? RemotePeerPresence.online : _presence.get(device.id);

  void setPresenceContext({required String server, required bool ready}) {
    if (_disposed || (server == _presenceServer && ready == _presenceReady)) {
      return;
    }
    _presenceServer = server;
    _presenceReady = ready;
    _presenceGeneration++;
    _presence.clear();
    _notify();
    if (ready) unawaited(refreshPresence());
  }

  Future<void> refreshPresence() =>
      _polling ??= _refreshPresence().whenComplete(() => _polling = null);

  Future<void> _refreshPresence() async {
    if (_disposed || !_presenceReady || queryPresence == null) return;
    final generation = _presenceGeneration;
    final ids = _devices.keys
        .where((id) => RegExp(r'^\d+$').hasMatch(id))
        .toList();
    if (ids.isEmpty) return;
    try {
      final states = await queryPresence!(
        ids,
      ).timeout(const Duration(seconds: 12));
      if (_disposed || generation != _presenceGeneration) return;
      _presence.applySnapshot({
        for (final id in ids) id: states[id] ?? 'unknown',
      });
    } catch (_) {
      if (_disposed || generation != _presenceGeneration) return;
      _presence.clear();
    }
    _notify();
  }

  final Map<String, RemoteDevice> _devices = {};
  final List<RawDatagramSocket> _sockets = [];
  Timer? _expiry;
  bool _disposed = false;
  bool scanning = false;
  String error = '';
  Future<void> _write = Future<void>.value();
  List<RemoteDevice> get devices => _devices.values.toList()
    ..sort(
      (a, b) => a.onLan != b.onLan
          ? (a.onLan ? -1 : 1)
          : (b.lastOpened ?? DateTime(1970)).compareTo(
              a.lastOpened ?? DateTime(1970),
            ),
    );

  Future<void> initialize() async {
    final raw = (await SharedPreferences.getInstance()).getString(
      'remote.devices.v1',
    );
    if (raw != null) {
      try {
        for (final item in (jsonDecode(raw) as List).take(500)) {
          try {
            final device = RemoteDevice.fromJson(
              Map<String, dynamic>.from(item as Map),
            );
            if (device.id.isNotEmpty) {
              final old = _devices[device.id];
              _devices[device.id] = old == null
                  ? device
                  : device.copyWith(
                      name: old.inAddressBook && old.name.isNotEmpty
                          ? old.name
                          : device.name,
                      model: device.model.isEmpty ? old.model : device.model,
                      tags: {...old.tags, ...device.tags}.toList()..sort(),
                      favorite: old.favorite || device.favorite,
                      inAddressBook: old.inAddressBook || device.inAddressBook,
                      lastOpened:
                          (old.lastOpened ?? DateTime(1970)).isAfter(
                            device.lastOpened ?? DateTime(1970),
                          )
                          ? old.lastOpened
                          : device.lastOpened,
                    );
            }
          } catch (_) {
            /* Skip malformed records individually. */
          }
        }
      } catch (_) {
        /* Retain valid records when one old record is malformed. */
      }
    }
    _expiry = Timer.periodic(const Duration(seconds: 10), (_) => _notify());
    if (queryPresence != null) {
      _presenceTimer = Timer.periodic(const Duration(seconds: 4), (_) {
        unawaited(refreshPresence());
      });
      unawaited(refreshPresence());
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _save() =>
      _write = _write.catchError((Object _) {}).then((_) async {
        final data = devices.take(500).map((d) => d.toJson()).toList();
        await (await SharedPreferences.getInstance()).setString(
          'remote.devices.v1',
          jsonEncode(data),
        );
      });
  Future<void> rememberOpened(String id) async {
    if (_disposed) return;
    id = id.trim().replaceAll(RegExp(r'\s'), '');
    if (id.isEmpty) return;
    final previous = _devices[id] ?? RemoteDevice(id: id);
    _devices[id] = previous.copyWith(
      lastOpened: DateTime.now(),
      createdAt: previous.createdAt ?? DateTime.now(),
    );
    await _save();
    _notify();
  }

  List<String> get tags =>
      _devices.values.expand((d) => d.tags).toSet().toList()..sort();

  Future<void> saveAddress({
    required String id,
    required String name,
    String model = '',
    List<String> tags = const [],
  }) async {
    id = id.trim().replaceAll(RegExp(r'\s'), '');
    if (id.isEmpty ||
        id.length > 200 ||
        id.startsWith('-') ||
        id.contains(RegExp(r'[\x00-\x1f]'))) {
      throw const FormatException('Enter a valid ID or IP.');
    }
    if (!_devices.containsKey(id) && _devices.length >= 500) {
      throw StateError('Address book is full (500 devices).');
    }
    final previous = _devices[id] ?? RemoteDevice(id: id);
    _devices[id] = previous.copyWith(
      name: name.trim().substring(0, name.trim().length.clamp(0, 160)),
      model: model.trim(),
      tags:
          tags
              .map((t) => t.trim())
              .where((t) => t.isNotEmpty)
              .map((t) => t.substring(0, t.length.clamp(0, 60)))
              .toSet()
              .take(30)
              .toList()
            ..sort(),
      inAddressBook: true,
      createdAt: previous.createdAt ?? DateTime.now(),
    );
    await _save();
    _notify();
  }

  Future<void> setFavorite(String id, bool value) async {
    final device = _devices[id];
    if (device == null || _disposed) return;
    _devices[id] = device.copyWith(favorite: value);
    await _save();
    _notify();
  }

  Future<void> renameTag(String oldTag, String newTag) async {
    newTag = newTag.trim();
    if (newTag.length > 60) throw const FormatException('Tag is too long.');
    for (final device in _devices.values.toList()) {
      if (!device.tags.contains(oldTag)) continue;
      _devices[device.id] = device.copyWith(
        tags: {
          for (final tag in device.tags)
            if (tag != oldTag) tag,
          if (newTag.isNotEmpty) newTag,
        }.toList()..sort(),
      );
    }
    await _save();
    _notify();
  }

  Future<void> rename(String id, String name, String model) async {
    if (_disposed || !_devices.containsKey(id)) return;
    _devices[id] = _devices[id]!.copyWith(
      name: name.trim(),
      model: model.trim(),
    );
    await _save();
    _notify();
  }

  Future<void> updatePeerInfo(String id, Map<String, dynamic> info) async {
    if (_disposed || !_devices.containsKey(id)) return;
    final previous = _devices[id]!;
    final hostname = info['hostname'] as String? ?? '';
    final platform = info['platform'] as String? ?? '';
    if (hostname.isEmpty && platform.isEmpty) return;
    final name = previous.name.isEmpty ? hostname : previous.name;
    if (previous.name == name && previous.platform == platform) return;
    _devices[id] = previous.copyWith(name: name, platform: platform);
    await _save();
    _notify();
  }

  Future<void> forget(String id) async {
    _devices.remove(id);
    await _save();
    _notify();
  }

  Future<void> scan({String localId = ''}) async {
    if (scanning || _disposed) return;
    scanning = true;
    // Remove stale advertisements for our own ID from earlier scans.
    if (localId.isNotEmpty) _devices.remove(localId);
    error = '';
    _notify();
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      for (final address
          in interfaces
              .expand((i) => i.addresses)
              .where((a) => !a.isLoopback)
              .take(8)) {
        if (_disposed) break;
        try {
          final socket = await RawDatagramSocket.bind(address, 0);
          if (_disposed) {
            socket.close();
            break;
          }
          _sockets.add(socket);
          socket.broadcastEnabled = true;
          socket.listen((event) {
            if (_disposed || event != RawSocketEvent.read) return;
            Datagram? packet;
            while ((packet = socket.receive()) != null) {
              final device = RemoteDiscoveryProtocol.decode(
                packet!.data,
                packet.address.address,
              );
              if (device == null ||
                  device.id == localId ||
                  (!_devices.containsKey(device.id) &&
                      _devices.length >= 100)) {
                continue;
              }
              final previous = _devices[device.id];
              _devices[device.id] = (previous ?? device).copyWith(
                name: previous?.name.isNotEmpty == true
                    ? previous!.name
                    : device.name,
                model: previous?.model,
                lastOpened: previous?.lastOpened,
                platform: device.platform,
                ip: device.ip,
                lastSeen: device.lastSeen,
              );
              _notify();
            }
          }, onError: (_) {});
          socket.send(
            RemoteDiscoveryProtocol.ping(localId),
            InternetAddress('255.255.255.255'),
            21119,
          );
        } on SocketException {
          /* Other adapters may still support discovery. */
        }
      }
      if (_sockets.isEmpty && !_disposed) {
        error = 'No LAN adapter is available for discovery.';
      }
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!_disposed) await _save();
    } catch (_) {
      error = 'LAN discovery could not finish.';
    } finally {
      for (final socket in _sockets) {
        socket.close();
      }
      _sockets.clear();
      scanning = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _expiry?.cancel();
    _presenceTimer?.cancel();
    _presenceGeneration++;
    for (final socket in _sockets) {
      socket.close();
    }
    _sockets.clear();
    super.dispose();
  }
}

enum RemoteDeviceGroup { all, recent, favorites, addressBook, lan }

enum RemoteDeviceSort { recent, name, id, oldest }

List<RemoteDevice> filterRemoteDevices(
  Iterable<RemoteDevice> devices, {
  String query = '',
  Set<String> tags = const {},
  RemoteDeviceGroup group = RemoteDeviceGroup.all,
  RemoteDeviceSort sort = RemoteDeviceSort.recent,
}) {
  final needle = query.trim().toLowerCase();
  final result = devices.where((d) {
    final inGroup = switch (group) {
      RemoteDeviceGroup.all => true,
      RemoteDeviceGroup.recent => d.lastOpened != null,
      RemoteDeviceGroup.favorites => d.favorite,
      RemoteDeviceGroup.addressBook => d.inAddressBook,
      RemoteDeviceGroup.lan => d.onLan,
    };
    return inGroup &&
        tags.every(d.tags.contains) &&
        [
          d.id,
          d.name,
          d.model,
          d.platform,
          d.ip,
          ...d.tags,
        ].any((s) => s.toLowerCase().contains(needle));
  }).toList();
  result.sort((a, b) {
    final order = switch (sort) {
      RemoteDeviceSort.name =>
        (a.name.isEmpty ? a.id : a.name).toLowerCase().compareTo(
          (b.name.isEmpty ? b.id : b.name).toLowerCase(),
        ),
      RemoteDeviceSort.id => a.id.compareTo(b.id),
      RemoteDeviceSort.recent =>
        (b.lastOpened ?? b.createdAt ?? DateTime(1970)).compareTo(
          a.lastOpened ?? a.createdAt ?? DateTime(1970),
        ),
      RemoteDeviceSort.oldest => (a.createdAt ?? DateTime(1970)).compareTo(
        b.createdAt ?? DateTime(1970),
      ),
    };
    return order == 0 ? a.id.compareTo(b.id) : order;
  });
  return result;
}
