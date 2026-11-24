import 'dart:io';
import 'package:flutter/services.dart';
import 'log_service.dart';

class LanRoute {
  const LanRoute(this.address, this.prefixLength, [this.name = '']);
  final String address;
  final int prefixLength;
  final String name;
  int get capturePriority {
    final value = name.toLowerCase();
    if (RegExp(r'usb|rndis|remote[\s_-]*ndis|ncm|tether').hasMatch(value)) {
      return 0;
    }
    if (RegExp(r'ethernet|^eth\d|enp\d').hasMatch(value)) return 1;
    return 2;
  }

  bool contains(String other) {
    final first = ipv4Broadcast(address, prefixLength);
    return first != null && first == ipv4Broadcast(other, prefixLength);
  }

  String? get broadcast => ipv4Broadcast(address, prefixLength);
}

String? ipv4Broadcast(String address, int prefix) {
  final parts = address.split('.').map(int.tryParse).toList();
  if (prefix < 1 ||
      prefix > 30 ||
      parts.length != 4 ||
      parts.any((p) => p == null || p < 0 || p > 255)) {
    return null;
  }
  var ip = 0;
  for (final part in parts) {
    ip = (ip << 8) | part!;
  }
  final value = ip | ((1 << (32 - prefix)) - 1);
  return [24, 16, 8, 0].map((shift) => (value >> shift) & 255).join('.');
}

bool isPhysicalLan(String name) => !RegExp(
  r'^(lo|dummy|ifb|tun|tap|ppp|rmnet|ccmni|pdp)|clat|vpn|wireguard|tailscale',
  caseSensitive: false,
).hasMatch(name);

class LanNetworkService {
  static final instance = LanNetworkService();
  static const _channel = MethodChannel('com.prs.localist.vpn');
  List<LanRoute> _cache = [];
  DateTime? _updated;
  Future<List<LanRoute>>? _loading;
  Future<List<LanRoute>> routes() {
    if (_updated != null &&
        DateTime.now().difference(_updated!) < const Duration(seconds: 20)) {
      LogService.instance.debug(
        'LAN routes served from cache count=${_cache.length}',
      );
      return Future.value(_cache);
    }
    LogService.instance.debug(
      'LAN route discovery requested inFlight=${_loading != null}',
    );
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  Future<List<LanRoute>> _load() async {
    LogService.instance.debug(
      'LAN route enumeration started platform=${Platform.operatingSystem}',
    );
    final routes = <LanRoute>[];
    try {
      List<dynamic>? records;
      if (Platform.isAndroid || Platform.isWindows) {
        records = await _channel.invokeListMethod<dynamic>('getLanInterfaces');
      }
      LogService.instance.debug(
        'LAN native route records count=${records?.length ?? 0}',
      );
      var skipped = 0;
      for (final row in records ?? []) {
        final map = row as Map;
        final address = map['address'] as String;
        final name = map['name'] as String;
        final prefix = map['prefixLength'] as int;
        if (isPhysicalLan(name) &&
            !address.startsWith('127.') &&
            address != '0.0.0.0') {
          routes.add(LanRoute(address, prefix, name));
        } else {
          skipped++;
        }
      }
      LogService.instance.debug(
        'LAN route filtering accepted=${routes.length} rejected=$skipped',
      );
    } catch (error) {
      LogService.instance.debug(
        'LAN native route enumeration failed type=${error.runtimeType}',
      );
    }
    if (routes.isEmpty) {
      LogService.instance.debug('LAN falling back to Dart network interfaces');
      for (final interface in await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      )) {
        if (!isPhysicalLan(interface.name)) continue;
        for (final address in interface.addresses) {
          if (!address.isLoopback) {
            routes.add(LanRoute(address.address, 32, interface.name));
          }
        }
      }
    }
    routes.sort((a, b) => a.capturePriority.compareTo(b.capturePriority));
    _cache = routes.take(8).toList();
    _updated = DateTime.now();
    LogService.instance.debug(
      'LAN route enumeration completed total=${routes.length} cached=${_cache.length}',
    );
    return _cache;
  }
}
