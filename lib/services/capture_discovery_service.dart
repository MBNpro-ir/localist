import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'lan_network_service.dart';
import 'log_service.dart';

class CaptureAdvertisement {
  const CaptureAdvertisement({
    required this.id,
    required this.name,
    required this.model,
    required this.host,
    required this.port,
    required this.key,
    required this.camera,
    required this.microphone,
    this.priority = 2,
  });
  final String id, name, model, host, key;
  final int port;
  final int priority;
  CaptureAdvertisement withPriority(int value) => CaptureAdvertisement(
    id: id,
    name: name,
    model: model,
    host: host,
    port: port,
    key: key,
    camera: camera,
    microphone: microphone,
    priority: value,
  );
  final bool camera, microphone;
  String get link =>
      Uri(scheme: 'http', host: host, port: port, fragment: key).toString();
  Map<String, Object> toJson() => {
    'protocol': 'localist.capture.v1',
    'id': id,
    'name': name,
    'model': model,
    'port': port,
    'key': key,
    'camera': camera,
    'microphone': microphone,
  };
  static CaptureAdvertisement? decode(List<int> bytes, String source) {
    if (bytes.length > 2048) return null;
    try {
      final data = jsonDecode(utf8.decode(bytes)) as Map;
      if (data['protocol'] != 'localist.capture.v1' ||
          data['id'] is! String ||
          !RegExp(r'^[a-zA-Z0-9_-]{16,64}$').hasMatch(data['id']) ||
          data['key'] is! String ||
          !RegExp(r'^[a-zA-Z0-9_=-]{40,64}$').hasMatch(data['key']) ||
          data['port'] is! int ||
          data['port'] < 1 ||
          data['port'] > 65535 ||
          data['name'] is! String ||
          data['model'] is! String ||
          (data['name'] as String).length > 100 ||
          (data['model'] as String).length > 100 ||
          data['camera'] is! bool ||
          data['microphone'] is! bool ||
          !(data['camera'] as bool) && !(data['microphone'] as bool)) {
        return null;
      }
      final ip = InternetAddress.tryParse(source);
      if (ip == null ||
          ip.type != InternetAddressType.IPv4 ||
          ip.isMulticast ||
          source == '0.0.0.0' ||
          source == '255.255.255.255') {
        return null;
      }
      final parts = ip.rawAddress;
      if (!(ip.isLoopback ||
          parts[0] == 10 ||
          parts[0] == 192 && parts[1] == 168 ||
          parts[0] == 172 && parts[1] >= 16 && parts[1] <= 31 ||
          parts[0] == 169 && parts[1] == 254)) {
        return null;
      }
      return CaptureAdvertisement(
        id: data['id'],
        name: data['name'],
        model: data['model'],
        host: source,
        port: data['port'],
        key: data['key'],
        camera: data['camera'],
        microphone: data['microphone'],
      );
    } catch (_) {
      return null;
    }
  }
}

/// LAN heartbeat only; discovering a receiver never starts its camera or mic.
class CaptureDiscoveryService {
  CaptureDiscoveryService({
    this.port = 53546,
    Future<List<LanRoute>> Function()? routes,
  }) : _loadRoutes = routes ?? LanNetworkService.instance.routes;
  final Future<List<LanRoute>> Function() _loadRoutes;
  final int port;
  static final group = InternetAddress('239.255.77.19');
  RawDatagramSocket? _socket;
  Timer? _timer;
  Future<void>? _starting;
  bool _searchEnabled = true;
  bool _publishing = false;
  bool _keepListening = false;
  bool _sending = false;
  DateTime? _lastQuery;
  List<LanRoute> _routes = [];
  int _announcements = 0, _received = 0;
  CaptureAdvertisement? Function()? advertisement;
  void Function(CaptureAdvertisement)? onAdvertisement;
  String error = '';
  bool get running => _socket != null;
  bool get _needsSocket => _searchEnabled || _publishing || _keepListening;

  void setModes({
    required bool search,
    required bool publish,
    required bool keepListening,
  }) {
    if (_searchEnabled == search &&
        _publishing == publish &&
        _keepListening == keepListening) {
      return;
    }
    _searchEnabled = search;
    _publishing = publish;
    _keepListening = keepListening;
    if (!_needsSocket) _closeSocket();
    if (search) _lastQuery = null;
    _syncTimer();
    unawaited(announce());
  }

  void _syncTimer() {
    if (_socket == null || (!_searchEnabled && !_publishing)) {
      _timer?.cancel();
      _timer = null;
    } else {
      _timer ??= Timer.periodic(
        const Duration(seconds: 3),
        (_) => unawaited(_announce()),
      );
    }
  }

  Future<void> start() =>
      _starting ??= _start().whenComplete(() => _starting = null);

  Future<void> _start() async {
    if (_socket != null || !_needsSocket) {
      LogService.instance.debug(
        'Capture discovery: start skipped, already listening',
      );
      return;
    }
    LogService.instance.debug('Capture discovery: binding UDP listener');
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        port,
        reuseAddress: true,
      );
      if (!_needsSocket) {
        socket.close();
        return;
      }
      _socket = socket;
      error = '';
      socket
        ..broadcastEnabled = true
        ..multicastLoopback = false
        ..multicastHops = 1;
      for (final interface in await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      )) {
        if (_socket != socket) return;
        if (!isPhysicalLan(interface.name)) continue;
        try {
          socket.joinMulticast(group, interface);
        } catch (e) {
          LogService.instance.debug(
            'Capture discovery: multicast join failed errorType=${e.runtimeType}',
          );
        }
      }
      if (_socket != socket) return;
      socket.listen(
        (event) {
          if (event != RawSocketEvent.read) return;
          Datagram? datagram;
          while ((datagram = socket.receive()) != null) {
            final value = datagram!;
            if (utf8.decode(value.data, allowMalformed: true) ==
                'localist.capture.query.v1') {
              final own = advertisement?.call();
              if (own != null) {
                socket.send(
                  utf8.encode(jsonEncode(own.toJson())),
                  value.address,
                  port,
                );
              }
            } else {
              final peer = CaptureAdvertisement.decode(
                value.data,
                value.address.address,
              );
              if (peer != null) {
                if (++_received == 1 || _received % 20 == 0) {
                  LogService.instance.debug(
                    'Capture discovery: valid advertisements=$_received routes=${_routes.length} camera=${peer.camera} microphone=${peer.microphone}',
                  );
                }
                final routes =
                    _routes.where((route) => route.contains(peer.host)).toList()
                      ..sort(
                        (a, b) =>
                            a.capturePriority.compareTo(b.capturePriority),
                      );
                onAdvertisement?.call(
                  peer.withPriority(routes.firstOrNull?.capturePriority ?? 2),
                );
              }
            }
          }
        },
        onError: (Object e) {
          error = '$e';
          LogService.instance.debug(
            'Capture discovery: socket event error type=${e.runtimeType}',
          );
        },
      );
      _syncTimer();
      await announce();
      LogService.instance.debug('Capture discovery: listener active');
    } catch (e) {
      error = '$e';
      LogService.instance.debug(
        'Capture discovery: listener start failed type=${e.runtimeType}',
      );
      await stop();
      rethrow;
    }
  }

  Future<void> announce({bool query = false}) =>
      _announce(query: query, refreshRoutes: true);

  Future<void> _announce({
    bool query = false,
    bool refreshRoutes = false,
  }) async {
    if (_sending || _socket == null) return;
    _sending = true;
    try {
      final own = advertisement?.call();
      final now = DateTime.now();
      query =
          _searchEnabled &&
          (query ||
              (own == null &&
                  (_lastQuery == null ||
                      now.difference(_lastQuery!) >=
                          const Duration(seconds: 15))));
      if (!query && own == null && !refreshRoutes) return;
      // Refresh routes when sending so USB tethering can appear after launch.
      final socket = _socket;
      _routes = await _loadRoutes();
      if (_socket != socket || (query && !_searchEnabled)) return;
      if (!query && own == null) return;
      if (++_announcements == 1 || _announcements % 10 == 0) {
        LogService.instance.debug(
          'Capture discovery: announce cycle=$_announcements query=$query routes=${_routes.length} publishing=${own != null}',
        );
      }
      if (query) _lastQuery = now;
      final bytes = utf8.encode(
        query ? 'localist.capture.query.v1' : jsonEncode(own!.toJson()),
      );
      for (final route in _routes) {
        if (_socket != socket || (query && !_searchEnabled)) return;
        RawDatagramSocket? output;
        try {
          output = await RawDatagramSocket.bind(
            InternetAddress(route.address),
            0,
          );
          if (_socket != socket ||
              (query && !_searchEnabled) ||
              (!query && advertisement?.call() == null)) {
            return;
          }
          output
            ..broadcastEnabled = true
            ..multicastLoopback = false
            ..multicastHops = 1;
          output.send(bytes, group, port);
          if (route.broadcast != null) {
            output.send(bytes, InternetAddress(route.broadcast!), port);
          }
        } catch (e) {
          LogService.instance.debug(
            'Capture discovery: route send failed type=${e.runtimeType}',
          );
        } finally {
          output?.close();
        }
      }
    } catch (e) {
      error = '$e';
      LogService.instance.debug(
        'Capture discovery: announce failed type=${e.runtimeType}',
      );
    } finally {
      _sending = false;
    }
  }

  Future<void> stop() async {
    await _starting;
    LogService.instance.debug(
      'Capture discovery: stop requested running=$running announcements=$_announcements received=$_received',
    );
    _closeSocket();
    LogService.instance.debug('Capture discovery: stopped');
  }

  void _closeSocket() {
    _timer?.cancel();
    _timer = null;
    _socket?.close();
    _socket = null;
  }
}
