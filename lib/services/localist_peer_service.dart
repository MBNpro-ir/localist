import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/service_state.dart';
import 'localist_discovery_protocol.dart';
import 'log_service.dart';

const localistPeerPort = 37889;

class LocalistConnectedPeer {
  const LocalistConnectedPeer({
    required this.id,
    required this.name,
    required this.platform,
    required this.address,
    required this.connectedAt,
    required this.lastSeen,
  });

  final String id;
  final String name;
  final String platform;
  final String address;
  final DateTime connectedAt;
  final DateTime lastSeen;

  LocalistConnectedPeer copyWith({DateTime? lastSeen, String? address}) {
    return LocalistConnectedPeer(
      id: id,
      name: name,
      platform: platform,
      address: address ?? this.address,
      connectedAt: connectedAt,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}

class LocalistPeerService extends ChangeNotifier {
  LocalistPeerService._();

  static final LocalistPeerService instance = LocalistPeerService._();

  final LogService _logs = LogService.instance;
  final Map<String, LocalistConnectedPeer> _peers = {};
  RawDatagramSocket? _socket;
  Timer? _heartbeatTimer;
  Timer? _pruneTimer;
  _PeerMode _mode = _PeerMode.off;
  RemoteProxyConfig? _remote;
  int _generation = 0;
  String _deviceId = '';
  String _deviceName = '';
  String _platform = '';

  List<LocalistConnectedPeer> get peers {
    return _peers.values.toList(growable: false)
      ..sort((first, second) => first.name.compareTo(second.name));
  }

  Future<void> update({
    required bool sharing,
    required bool receiving,
    required RemoteProxyConfig? remote,
  }) async {
    final targetMode = sharing
        ? _PeerMode.host
        : receiving && remote != null
        ? _PeerMode.client
        : _PeerMode.off;
    _logs.debug(
      'Peer registry update requested from=${_mode.name} to=${targetMode.name} remoteConfigured=${remote != null}',
    );
    if (targetMode == _mode &&
        (targetMode != _PeerMode.client || remote?.url == _remote?.url)) {
      _logs.debug('Peer registry update skipped unchanged state');
      return;
    }
    final generation = ++_generation;
    await _shutdown(sendDisconnect: _mode == _PeerMode.client);
    if (generation != _generation) {
      _logs.debug('Peer registry update superseded during shutdown');
      return;
    }
    _mode = targetMode;
    _remote = remote;
    if (targetMode == _PeerMode.off) {
      return;
    }
    await _loadIdentity();
    if (generation != _generation) {
      _logs.debug('Peer registry update superseded during identity load');
      return;
    }
    if (targetMode == _PeerMode.host) {
      await _startHost();
    } else {
      await _startClient();
    }
  }

  Future<void> stop() async {
    _logs.debug('Peer registry explicit stop requested mode=${_mode.name}');
    ++_generation;
    await _shutdown(sendDisconnect: _mode == _PeerMode.client);
    _mode = _PeerMode.off;
    _remote = null;
  }

  Future<void> _loadIdentity() async {
    _deviceId = await localistDiscoveryDeviceId();
    _deviceName = await localistDiscoveryDeviceName();
    _platform = localistDiscoveryPlatformName();
    _logs.debug('Peer registry identity loaded platform=$_platform');
  }

  Future<void> _startHost() async {
    _logs.debug('Peer registry UDP host binding');
    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        localistPeerPort,
        reuseAddress: true,
      );
      _socket!.listen(_handleHostEvent, onError: _handleSocketError);
      _pruneTimer = Timer.periodic(
        const Duration(seconds: 4),
        (_) => _prunePeers(),
      );
      _logs.info(
        'Connected-device registry listening on UDP $localistPeerPort',
      );
    } catch (error) {
      _logs.debug(
        'Connected-device registry start failed type=${error.runtimeType}',
      );
      _logs.warning('Connected-device registry could not start.');
      _mode = _PeerMode.off;
    }
  }

  Future<void> _startClient() async {
    _logs.debug('Peer registry UDP client binding');
    try {
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      await _sendHeartbeat('connected');
      _heartbeatTimer = Timer.periodic(
        const Duration(seconds: 4),
        (_) => unawaited(_sendHeartbeat('connected')),
      );
      _logs.debug('Connected-device heartbeat timer started intervalSeconds=4');
    } catch (error) {
      _logs.debug(
        'Connected-device heartbeat start failed type=${error.runtimeType}',
      );
      _logs.warning('Connected-device heartbeat could not start.');
      _mode = _PeerMode.off;
    }
  }

  void _handleHostEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read || _mode != _PeerMode.host) {
      return;
    }
    Datagram? datagram;
    while ((datagram = _socket?.receive()) != null) {
      _handlePeerPacket(datagram!);
    }
  }

  void _handlePeerPacket(Datagram datagram) {
    if (!_isPrivateAddress(datagram.address.address)) {
      _logs.debug(
        'Peer registry rejected packet outside private address range',
      );
      return;
    }
    try {
      final value = jsonDecode(utf8.decode(datagram.data));
      if (value is! Map<String, dynamic> ||
          value['type'] != 'localist.peer.v1') {
        _logs.debug('Peer registry ignored unrecognized packet');
        return;
      }
      final id = (value['deviceId'] as String? ?? '').trim();
      if (id.isEmpty || id == _deviceId) {
        _logs.debug('Peer registry ignored missing or local device identity');
        return;
      }
      if (value['state'] == 'disconnected') {
        _logs.debug(
          'Peer registry disconnect received known=${_peers.containsKey(id)}',
        );
        if (_peers.remove(id) != null) {
          notifyListeners();
        }
        return;
      }
      final now = DateTime.now();
      final previous = _peers[id];
      _peers[id] = LocalistConnectedPeer(
        id: id,
        name: (value['deviceName'] as String? ?? '').trim().isEmpty
            ? datagram.address.address
            : (value['deviceName'] as String).trim(),
        platform: (value['platform'] as String? ?? 'Localist').trim(),
        address: datagram.address.address,
        connectedAt: previous?.connectedAt ?? now,
        lastSeen: now,
      );
      if (previous == null || previous.address != datagram.address.address) {
        _logs.debug(
          'Peer registry peer addedOrMoved=${previous == null ? 'added' : 'moved'} tracked=${_peers.length}',
        );
        _logs.info(
          'Connected-device registry now tracks ${_peers.length} peer(s).',
        );
        notifyListeners();
      }
    } catch (error) {
      _logs.debug(
        'Ignored invalid connected-device packet type=${error.runtimeType}',
      );
    }
  }

  Future<void> _sendHeartbeat(String state) async {
    final socket = _socket;
    final remote = _remote;
    if (socket == null || remote == null || _mode != _PeerMode.client) {
      _logs.debug(
        'Peer registry heartbeat skipped socketReady=${socket != null} remoteReady=${remote != null} mode=${_mode.name}',
      );
      return;
    }
    final data = utf8.encode(
      jsonEncode({
        'type': 'localist.peer.v1',
        'state': state,
        'deviceId': _deviceId,
        'deviceName': _deviceName,
        'platform': _platform,
      }),
    );
    try {
      final bytes = socket.send(
        data,
        InternetAddress(remote.host),
        localistPeerPort,
      );
      _logs.debug('Peer registry heartbeat state=$state sentBytes=$bytes');
    } catch (error) {
      _logs.debug(
        'Connected-device heartbeat failed type=${error.runtimeType}',
      );
    }
  }

  void _prunePeers() {
    final cutoff = DateTime.now().subtract(const Duration(seconds: 13));
    final before = _peers.length;
    _peers.removeWhere((_, peer) => peer.lastSeen.isBefore(cutoff));
    if (before != _peers.length) {
      _logs.debug(
        'Peer registry pruned expired count=${before - _peers.length} remaining=${_peers.length}',
      );
      notifyListeners();
    }
  }

  Future<void> _shutdown({required bool sendDisconnect}) async {
    _logs.debug(
      'Peer registry shutting down mode=${_mode.name} sendDisconnect=$sendDisconnect knownPeers=${_peers.length}',
    );
    if (sendDisconnect) {
      await _sendHeartbeat('disconnected');
    }
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _pruneTimer?.cancel();
    _pruneTimer = null;
    _socket?.close();
    _socket = null;
    _remote = null;
    if (_peers.isNotEmpty) {
      _peers.clear();
      notifyListeners();
    }
    _logs.debug('Peer registry shutdown completed');
  }

  void _handleSocketError(Object error) {
    _logs.debug('Connected-device socket error type=${error.runtimeType}');
    _logs.warning('Connected-device socket error.');
  }

  bool _isPrivateAddress(String value) {
    final parts = value.split('.').map(int.tryParse).toList();
    if (parts.length != 4 || parts.any((part) => part == null)) {
      return value == '::1' || value.toLowerCase().startsWith('fe80:');
    }
    final a = parts[0]!;
    final b = parts[1]!;
    return a == 10 ||
        a == 127 ||
        (a == 169 && b == 254) ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 192 && b == 168);
  }
}

enum _PeerMode { off, host, client }
