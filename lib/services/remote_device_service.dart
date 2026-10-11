import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

import 'package:shared_preferences/shared_preferences.dart';

class RemoteDevice {
  const RemoteDevice({
    required this.id,
    this.name = '',
    this.model = '',
    this.platform = '',
    this.ip = '',
    this.lastSeen,
    this.lastOpened,
  });
  final String id, name, model, platform, ip;
  final DateTime? lastSeen, lastOpened;
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
  }) => RemoteDevice(
    id: id,
    name: name ?? this.name,
    model: model ?? this.model,
    platform: platform ?? this.platform,
    ip: ip ?? this.ip,
    lastSeen: lastSeen ?? this.lastSeen,
    lastOpened: lastOpened ?? this.lastOpened,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'model': model,
    'platform': platform,
    'ip': ip,
    'lastOpened': lastOpened?.toIso8601String(),
  };
  factory RemoteDevice.fromJson(Map<String, dynamic> json) => RemoteDevice(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    model: json['model'] as String? ?? '',
    platform: json['platform'] as String? ?? '',
    ip: json['ip'] as String? ?? '',
    lastOpened: DateTime.tryParse(json['lastOpened'] as String? ?? ''),
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
        for (final item in (jsonDecode(raw) as List).take(100)) {
          final device = RemoteDevice.fromJson(
            Map<String, dynamic>.from(item as Map),
          );
          if (device.id.isNotEmpty) _devices[device.id] = device;
        }
      } catch (_) {
        /* Retain valid records when one old record is malformed. */
      }
    }
    _expiry = Timer.periodic(const Duration(seconds: 10), (_) => _notify());
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _save() => _write = _write.then((_) async {
    final data = devices.take(100).map((d) => d.toJson()).toList();
    await (await SharedPreferences.getInstance()).setString(
      'remote.devices.v1',
      jsonEncode(data),
    );
  });
  Future<void> rememberOpened(String id) async {
    if (_disposed) return;
    final previous = _devices[id] ?? RemoteDevice(id: id);
    _devices[id] = previous.copyWith(lastOpened: DateTime.now());
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
              _devices[device.id] = device.copyWith(
                name: previous?.name.isNotEmpty == true
                    ? previous!.name
                    : device.name,
                model: previous?.model,
                lastOpened: previous?.lastOpened,
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
    for (final socket in _sockets) {
      socket.close();
    }
    _sockets.clear();
    super.dispose();
  }
}
