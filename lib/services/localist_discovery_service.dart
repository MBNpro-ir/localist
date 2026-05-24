import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/service_state.dart';
import 'log_service.dart';
import 'localist_discovery_protocol.dart';

class LocalistDiscoveryService extends ChangeNotifier {
  LocalistDiscoveryService._();

  static final LocalistDiscoveryService instance = LocalistDiscoveryService._();

  final LogService _logs = LogService.instance;
  final Map<String, LocalistDiscoveredDevice> _devices = {};
  RawDatagramSocket? _socket;
  Timer? _queryTimer;
  Timer? _pruneTimer;
  Timer? _notifyTimer;
  String? _deviceId;
  String _lastTargetSignature = '';
  bool _scanning = false;
  bool _refreshInFlight = false;
  bool _pendingNotify = false;
  Set<String> _localIpv4Addresses = const {};

  bool get scanning => _scanning;

  List<LocalistDiscoveredDevice> get devices {
    return _devices.values.toList(growable: false)..sort((first, second) {
      final firstName = first.name.toLowerCase();
      final secondName = second.name.toLowerCase();
      final nameOrder = firstName.compareTo(secondName);
      if (nameOrder != 0) {
        return nameOrder;
      }
      return second.lastSeen.compareTo(first.lastSeen);
    });
  }

  Future<void> start() async {
    if (_scanning) {
      _logs.debug('Local discovery start skipped: already scanning');
      return;
    }
    _logs.debug('Local discovery starting');
    await _startSocket();
    _scanning = true;
    _notifySoon();
    await refresh();
    _queryTimer = Timer.periodic(
      const Duration(seconds: 6),
      (_) => unawaited(refresh()),
    );
    _pruneTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _pruneExpiredDevices(),
    );
  }

  Future<void> resume() async {
    if (_scanning) {
      return;
    }
    await start();
  }

  Future<void> suspend() async {
    _logs.debug('Local discovery suspending');
    _queryTimer?.cancel();
    _queryTimer = null;
    _pruneTimer?.cancel();
    _pruneTimer = null;
    _notifyTimer?.cancel();
    _notifyTimer = null;
    _pendingNotify = false;
    _socket?.close();
    _socket = null;
    if (_scanning) {
      _scanning = false;
      notifyListeners();
    }
    _logs.debug('Local discovery suspended');
  }

  Future<void> _startSocket() async {
    _deviceId = await localistDiscoveryDeviceId();
    _socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      0,
      reuseAddress: true,
    );
    _socket!
      ..broadcastEnabled = true
      ..multicastLoopback = false
      ..listen(_handleSocketEvent, onError: (_) {});
    _logs.debug(
      'Local discovery socket ready deviceId=$_deviceId port=${_socket!.port}',
    );
  }

  Future<void> refresh() async {
    final socket = _socket;
    final deviceId = _deviceId;
    if (socket == null || deviceId == null || _refreshInFlight) {
      _logs.debug(
        'Local discovery refresh skipped socketReady=${socket != null} deviceReady=${deviceId != null} inFlight=$_refreshInFlight',
      );
      return;
    }
    _refreshInFlight = true;
    try {
      _logs.debug('Local discovery refresh started');
      final data = utf8.encode(
        encodeLocalistDiscoveryQuery(deviceId: deviceId),
      );
      final targets = await _queryTargets();
      final signature = targets.map((target) => target.address).join(',');
      if (signature != _lastTargetSignature) {
        _lastTargetSignature = signature;
        _logs.info(
          'Local discovery is querying ${targets.length} network targets.',
        );
      }
      _logs.debug('Local discovery targets: $signature');
      for (final target in targets) {
        try {
          socket.send(data, target, localistDiscoveryPort);
          _logs.debug(
            'Local discovery query sent to ${target.address}:$localistDiscoveryPort bytes=${data.length}',
          );
        } catch (error, stack) {
          _logs.debug(
            'Local discovery query send failed for ${target.address}',
            error: error,
            stack: stack,
          );
          // Some networks block directed multicast or limited broadcast.
        }
      }
    } finally {
      _refreshInFlight = false;
      _logs.debug('Local discovery refresh finished');
    }
  }

  Future<void> restart() async {
    _logs.debug('Local discovery manual restart requested');
    await stop();
    await start();
  }

  Future<void> stop() async {
    _logs.debug('Local discovery stopping and clearing devices');
    await suspend();
    final hadDevices = _devices.isNotEmpty;
    _devices.clear();
    _lastTargetSignature = '';
    if (hadDevices) {
      notifyListeners();
    }
  }

  void _handleSocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) {
      return;
    }
    Datagram? datagram;
    while ((datagram = _socket?.receive()) != null) {
      _handleDatagram(datagram!);
    }
  }

  void _handleDatagram(Datagram datagram) {
    _logs.debug(
      'Local discovery datagram from ${datagram.address.address}:${datagram.port} bytes=${datagram.data.length}',
    );
    final map = decodeLocalistDiscoveryPacket(datagram.data);
    if (map == null || !isLocalistDiscoveryAnnouncement(map)) {
      _logs.debug('Local discovery ignored packet: not an announcement');
      return;
    }
    if (map['deviceId'] == _deviceId) {
      _logs.debug('Local discovery ignored own announcement');
      return;
    }
    if (_isLocalAddress(datagram.address.address)) {
      _logs.debug(
        'Local discovery ignored local source ${datagram.address.address}',
      );
      return;
    }
    final device = LocalistDiscoveredDevice.fromAnnouncement(
      map,
      sourceAddress: datagram.address.address,
      lastSeen: DateTime.now(),
    );
    if (device.endpoints.isEmpty ||
        device.endpoints.every((endpoint) => _isLocalAddress(endpoint.host))) {
      _logs.debug(
        'Local discovery ignored ${device.name}: no usable remote endpoints',
      );
      return;
    }
    final previous = _devices[device.id];
    _devices[device.id] = device;
    if (previous == null || !_sameVisibleDevice(previous, device)) {
      _logs.info(
        'Discovered ${device.platform} device "${device.name}" at ${device.sourceAddress}.',
      );
      _notifySoon();
    } else if (device.lastSeen.difference(previous.lastSeen) >
        const Duration(seconds: 10)) {
      _notifySoon();
    }
  }

  void _pruneExpiredDevices() {
    final cutoff = DateTime.now().subtract(const Duration(seconds: 40));
    final before = _devices.length;
    _devices.removeWhere((_, device) => device.lastSeen.isBefore(cutoff));
    if (_devices.length != before) {
      _logs.debug(
        'Local discovery pruned ${before - _devices.length} expired device(s)',
      );
      _notifySoon();
    }
  }

  Future<List<InternetAddress>> _queryTargets() async {
    final hosts = <String>{
      localistDiscoveryMulticastAddress,
      '255.255.255.255',
      '192.168.43.1',
      '192.168.49.1',
      '192.168.137.1',
      '172.20.10.1',
      '10.0.0.1',
    };
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      _logs.debug(
        'Local discovery inspected ${interfaces.length} IPv4 interface(s)',
      );
      final localAddresses = <String>{};
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          final host = address.address;
          if (!_isUsableIpv4(host)) {
            continue;
          }
          localAddresses.add(host);
          hosts
            ..add(_ipv4WithLastOctet(host, 1))
            ..add(_ipv4WithLastOctet(host, 254))
            ..add(_ipv4WithLastOctet(host, 255));
        }
      }
      _localIpv4Addresses = localAddresses;
      _logs.debug('Local discovery local IPv4 addresses: $localAddresses');
    } catch (error) {
      _logs.warning(
        'Local discovery could not inspect network interfaces: $error',
      );
    }
    return hosts.map(InternetAddress.new).toList(growable: false);
  }

  bool _isLocalAddress(String value) {
    return value == InternetAddress.loopbackIPv4.address ||
        _localIpv4Addresses.contains(value);
  }

  bool _sameVisibleDevice(
    LocalistDiscoveredDevice previous,
    LocalistDiscoveredDevice next,
  ) {
    if (previous.name != next.name ||
        previous.platform != next.platform ||
        previous.sourceAddress != next.sourceAddress ||
        previous.endpoints.length != next.endpoints.length) {
      return false;
    }
    for (var index = 0; index < previous.endpoints.length; index++) {
      final first = previous.endpoints[index];
      final second = next.endpoints[index];
      if (first.protocol != second.protocol ||
          first.host != second.host ||
          first.port != second.port) {
        return false;
      }
    }
    return true;
  }

  void _notifySoon() {
    if (_pendingNotify) {
      return;
    }
    _pendingNotify = true;
    _notifyTimer?.cancel();
    _notifyTimer = Timer(const Duration(milliseconds: 250), () {
      _pendingNotify = false;
      notifyListeners();
    });
  }

  bool _isUsableIpv4(String value) {
    final parts = value.split('.').map(int.tryParse).toList();
    if (parts.length != 4 || parts.any((part) => part == null)) {
      return false;
    }
    final octets = parts.cast<int>();
    return octets.every((part) => part >= 0 && part <= 255) &&
        octets[0] != 0 &&
        octets[0] != 127 &&
        octets[0] < 224 &&
        value != '255.255.255.255';
  }

  String _ipv4WithLastOctet(String value, int octet) {
    final parts = value.split('.');
    parts[3] = octet.toString();
    return parts.join('.');
  }
}
