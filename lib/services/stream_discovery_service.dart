import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'lan_network_service.dart';
import 'log_service.dart';

// HTTP uses TCP and discovery uses UDP on the same port.
const mediaStreamPort = 53547;
const streamDiscoveryPort = mediaStreamPort;
const _query = 'localist.stream.query.v1';
const _reply = 'localist.stream.reply.v1';

bool _isLocalAddress(InternetAddress address) {
  if (address.type != InternetAddressType.IPv4) return false;
  final bytes = address.rawAddress;
  return address.isLoopback ||
      bytes[0] == 10 ||
      (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
      (bytes[0] == 192 && bytes[1] == 168) ||
      (bytes[0] == 169 && bytes[1] == 254);
}

Uri? parseStreamAddress(String input, {bool fromQr = false}) {
  final value = input.trim();
  if (value.isEmpty || value.length > 2048) return null;
  final uri = Uri.tryParse(
    !fromQr && !value.contains('://') ? 'http://$value' : value,
  );
  if (uri == null ||
      !const {'http', 'https'}.contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  if (uri.port < 1 || uri.port > 65535) return null;
  if (fromQr) {
    final address = InternetAddress.tryParse(uri.host);
    if (address == null || address.isLoopback || !_isLocalAddress(address)) {
      return null;
    }
  }
  return uri;
}

class StreamDiscoveryService extends ChangeNotifier {
  StreamDiscoveryService({
    this.port = streamDiscoveryPort,
    Future<Set<String>> Function()? targets,
  }) : _targets = targets ?? _lanTargets;

  final int port;
  final Future<Set<String>> Function() _targets;
  RawDatagramSocket? _socket;
  Timer? _repeat;
  Timer? _timeout;
  bool _active = false;
  int _generation = 0;
  bool scanning = false;
  List<Uri> addresses = const [];
  int? ownPlayerPort;

  static Future<Set<String>> _lanTargets() async => {
    '255.255.255.255',
    for (final route in await LanNetworkService.instance.routes())
      if (route.broadcast != null) route.broadcast!,
  };

  static Future<RawDatagramSocket> serve(
    int playerPort, {
    int port = streamDiscoveryPort,
  }) async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port);
    final pattern = RegExp('^${RegExp.escape(_query)} ([a-f0-9]{16})\$');
    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      Datagram? packet;
      while ((packet = socket.receive()) != null) {
        final datagram = packet!;
        if (datagram.data.length > 80 || !_isLocalAddress(datagram.address)) {
          continue;
        }
        final match = pattern.firstMatch(
          ascii.decode(datagram.data, allowInvalid: true),
        );
        if (match == null) continue;
        try {
          socket.send(
            ascii.encode('$_reply ${match[1]} $playerPort'),
            datagram.address,
            datagram.port,
          );
        } on SocketException {
          // The requesting device or its interface may have disappeared.
        }
      }
    }, onError: (_) {});
    return socket;
  }

  void setActive(bool value) {
    if (_active == value) return;
    _active = value;
    if (value) {
      unawaited(refresh());
      _repeat = Timer.periodic(
        const Duration(seconds: 8),
        (_) => unawaited(refresh()),
      );
    } else {
      _repeat?.cancel();
      _repeat = null;
      _finish(clear: true);
    }
  }

  Future<void> refresh() async {
    if (!_active || scanning) return;
    final generation = ++_generation;
    scanning = true;
    notifyListeners();
    final found = <Uri>{};
    try {
      final targets = await _targets();
      if (generation != _generation) return;
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      if (generation != _generation) {
        socket.close();
        return;
      }
      _socket = socket..broadcastEnabled = true;
      final random = Random.secure();
      final nonce = List.generate(
        16,
        (_) => random.nextInt(16).toRadixString(16),
      ).join();
      final pattern = RegExp('^${RegExp.escape(_reply)} $nonce ([0-9]{1,5})\$');
      final ownAddresses = ownPlayerPort == null
          ? const <String>{}
          : {
              for (final route in await LanNetworkService.instance.routes())
                route.address,
              InternetAddress.loopbackIPv4.address,
            };
      if (generation != _generation) return;
      socket.listen((event) {
        if (event != RawSocketEvent.read || generation != _generation) return;
        Datagram? packet;
        while ((packet = socket.receive()) != null) {
          final datagram = packet!;
          if (datagram.data.length > 80 || !_isLocalAddress(datagram.address)) {
            continue;
          }
          final match = pattern.firstMatch(
            ascii.decode(datagram.data, allowInvalid: true),
          );
          final playerPort = int.tryParse(match?[1] ?? '');
          if (playerPort == null ||
              playerPort < 1 ||
              playerPort > 65535 ||
              (playerPort == ownPlayerPort &&
                  ownAddresses.contains(datagram.address.address))) {
            continue;
          }
          if (found.length >= 32) continue;
          final uri = Uri(
            scheme: 'http',
            host: datagram.address.address,
            port: playerPort,
          );
          if (found.add(uri) && !addresses.contains(uri)) {
            addresses = List.unmodifiable([...addresses, uri]);
            notifyListeners();
          }
        }
      }, onError: (_) {});
      final request = ascii.encode('$_query $nonce');
      for (final target in targets) {
        try {
          socket.send(request, InternetAddress(target), port);
        } on SocketException {
          // Continue discovery over the remaining interfaces.
        }
      }
      _timeout = Timer(const Duration(milliseconds: 1350), () {
        addresses = List.unmodifiable(found);
        _finish();
      });
      LogService.instance.debug(
        'Stream discovery probe sent routes=${targets.length}',
      );
    } catch (error) {
      if (generation != _generation) return;
      LogService.instance.debug(
        'Stream discovery unavailable type=${error.runtimeType}',
      );
      _finish(clear: true);
    }
  }

  void _finish({bool clear = false}) {
    _generation++;
    _timeout?.cancel();
    _timeout = null;
    _socket?.close();
    _socket = null;
    if (clear) addresses = const [];
    scanning = false;
    notifyListeners();
  }

  @override
  void dispose() {
    setActive(false);
    super.dispose();
  }
}
