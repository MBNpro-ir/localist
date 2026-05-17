import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/service_state.dart';
import 'localist_discovery_protocol.dart';

class LocalistDiscoveryService extends ChangeNotifier {
  LocalistDiscoveryService._();

  static final LocalistDiscoveryService instance = LocalistDiscoveryService._();

  final Map<String, LocalistDiscoveredDevice> _devices = {};
  RawDatagramSocket? _socket;
  Timer? _queryTimer;
  Timer? _pruneTimer;
  String? _deviceId;
  bool _scanning = false;

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
      return;
    }
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
    _scanning = true;
    notifyListeners();
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

  Future<void> refresh() async {
    final socket = _socket;
    final deviceId = _deviceId;
    if (socket == null || deviceId == null) {
      return;
    }
    final data = utf8.encode(encodeLocalistDiscoveryQuery(deviceId: deviceId));
    for (final host in const [
      localistDiscoveryMulticastAddress,
      '255.255.255.255',
    ]) {
      try {
        socket.send(data, InternetAddress(host), localistDiscoveryPort);
      } catch (_) {
        // Some networks block directed multicast or limited broadcast.
      }
    }
  }

  Future<void> stop() async {
    _queryTimer?.cancel();
    _queryTimer = null;
    _pruneTimer?.cancel();
    _pruneTimer = null;
    _socket?.close();
    _socket = null;
    _devices.clear();
    if (_scanning) {
      _scanning = false;
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
    final map = decodeLocalistDiscoveryPacket(datagram.data);
    if (map == null || !isLocalistDiscoveryAnnouncement(map)) {
      return;
    }
    if (map['deviceId'] == _deviceId) {
      return;
    }
    final device = LocalistDiscoveredDevice.fromAnnouncement(
      map,
      sourceAddress: datagram.address.address,
      lastSeen: DateTime.now(),
    );
    if (device.endpoints.isEmpty) {
      return;
    }
    final previous = _devices[device.id];
    _devices[device.id] = device;
    if (previous == null ||
        previous.name != device.name ||
        previous.endpointSummary != device.endpointSummary ||
        previous.sourceAddress != device.sourceAddress) {
      notifyListeners();
    } else {
      notifyListeners();
    }
  }

  void _pruneExpiredDevices() {
    final cutoff = DateTime.now().subtract(const Duration(seconds: 40));
    final before = _devices.length;
    _devices.removeWhere((_, device) => device.lastSeen.isBefore(cutoff));
    if (_devices.length != before) {
      notifyListeners();
    }
  }
}
