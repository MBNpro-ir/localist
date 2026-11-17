import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Minimal ADB transport endpoint for the Developer Bridge proof of concept.
///
/// This is a synthetic, loopback-only device. It deliberately exposes no shell,
/// sync, install, JDWP, or device-control service. Unknown OPEN requests are
/// closed using the ADB protocol rather than being reported as successful.
class VirtualAdbEndpointService {
  static const int _commandCnxn = 0x4e584e43;
  static const int _commandOpen = 0x4e45504f;
  static const int _commandOkay = 0x59414b4f;
  static const int _commandClose = 0x45534c43;
  static const int _commandWrite = 0x45545257;
  static const int _commandAuth = 0x48545541;
  static const int _commandStls = 0x534c5453;
  static const int _version = 0x01000001;
  static const int _maxPayload = 1024 * 1024;
  static const int _headerLength = 24;

  ServerSocket? _server;
  final Set<Socket> _clients = {};
  final Set<void Function()> _listeners = {};
  bool _disposed = false;
  String? lastError;
  String? lastRejectedService;
  int acceptedConnections = 0;
  int rejectedServices = 0;

  bool get isRunning => _server != null;
  int? get port => _server?.port;
  String? get endpoint => port == null ? null : '127.0.0.1:$port';

  void addListener(void Function() listener) => _listeners.add(listener);

  void removeListener(void Function() listener) => _listeners.remove(listener);

  Future<String> start() async {
    if (_disposed) throw StateError('Virtual ADB endpoint has been disposed');
    final current = endpoint;
    if (current != null) return current;

    // Explicit loopback binding prevents LAN/Wi-Fi exposure.
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    if (_disposed) {
      await server.close();
      throw StateError('Virtual ADB endpoint has been disposed');
    }
    _server = server;
    server.listen(
      (socket) {
        if (!socket.remoteAddress.isLoopback) {
          socket.destroy();
          return;
        }
        _clients.add(socket);
        acceptedConnections++;
        _notify();
        unawaited(_serveClient(socket));
      },
      onError: (Object error) {
        lastError = 'Listener error: $error';
        _notify();
      },
    );
    lastError = null;
    _notify();
    return endpoint!;
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close();
    final clients = _clients.toList();
    _clients.clear();
    for (final socket in clients) {
      socket.destroy();
    }
    _notify();
  }

  Future<void> _serveClient(Socket socket) async {
    final reader = _AdbByteReader(socket);
    var handshakeComplete = false;
    var negotiatedVersion = 0;
    try {
      while (true) {
        final headerBytes = await reader.readExact(_headerLength);
        final header = _AdbHeader.decode(headerBytes);
        if (header.magic != (header.command ^ 0xffffffff) ||
            header.dataLength > _maxPayload) {
          throw const FormatException('Invalid ADB packet header');
        }
        final payload = await reader.readExact(header.dataLength);
        if (header.dataLength > 0 &&
            header.checksum != _checksum(payload) &&
            negotiatedVersion < _version) {
          throw const FormatException('Invalid ADB packet checksum');
        }

        if (!handshakeComplete) {
          if (header.command != _commandCnxn || header.arg0 < 0x01000000) {
            throw const FormatException('Expected ADB CNXN handshake');
          }
          negotiatedVersion = header.arg0;
          await _writePacket(
            socket,
            _commandCnxn,
            _version,
            _maxPayload,
            utf8.encode(
              'device::ro.product.name=localist;'
              'ro.product.model=Localist_Virtual;'
              'ro.product.device=localist;'
              'ro.product.manufacturer=Localist;'
              'ro.build.version.release=1;'
              'ro.build.version.sdk=35;features=;',
            ),
          );
          handshakeComplete = true;
          continue;
        }

        switch (header.command) {
          case _commandCnxn:
            // Repeated CNXN is harmless; return the same synthetic identity.
            await _writePacket(
              socket,
              _commandCnxn,
              _version,
              _maxPayload,
              utf8.encode(
                'device::ro.product.name=localist;'
                'ro.product.model=Localist_Virtual;'
                'ro.product.device=localist;'
                'ro.product.manufacturer=Localist;'
                'ro.build.version.release=1;'
                'ro.build.version.sdk=35;features=;',
              ),
            );
          case _commandOpen:
            final requested = utf8
                .decode(payload, allowMalformed: true)
                .split('\u0000')
                .first;
            lastRejectedService = requested;
            rejectedServices++;
            _notify();
            // A zero local id denotes failure to open this remote stream.
            await _writePacket(
              socket,
              _commandClose,
              0,
              header.arg0,
              const <int>[],
            );
          case _commandOkay:
            // There is no successful stream in this PoC.
            await _closeUnsupportedStream(socket, header);
          case _commandWrite:
            // Data on a nonexistent stream is a protocol error.
            throw const FormatException('ADB WRTE on an unopened stream');
          case _commandClose:
            // ADB peer closed a failed OPEN or stale stream.
            break;
          case _commandAuth:
            throw const FormatException(
              'ADB AUTH is not enabled in this loopback-only PoC',
            );
          case _commandStls:
            throw const FormatException(
              'ADB STLS is unsupported by this initial PoC',
            );
          default:
            throw FormatException(
              'Unsupported ADB command 0x${header.command.toRadixString(16)}',
            );
        }
      }
    } on SocketException {
      // Normal when adb disconnects or the endpoint is stopped.
    } on TimeoutException {
      lastError = 'Timed out waiting for an ADB packet';
      _notify();
    } on FormatException catch (error) {
      lastError = error.message;
      _notify();
    } catch (error) {
      lastError = 'ADB endpoint error: $error';
      _notify();
    } finally {
      _clients.remove(socket);
      socket.destroy();
      _notify();
    }
  }

  Future<void> _closeUnsupportedStream(Socket socket, _AdbHeader header) =>
      _writePacket(socket, _commandClose, 0, header.arg0, const <int>[]);

  Future<void> _writePacket(
    Socket socket,
    int command,
    int arg0,
    int arg1,
    List<int> payload,
  ) async {
    final packet = Uint8List(_headerLength + payload.length);
    final data = ByteData.sublistView(packet);
    data.setUint32(0, command, Endian.little);
    data.setUint32(4, arg0, Endian.little);
    data.setUint32(8, arg1, Endian.little);
    data.setUint32(12, payload.length, Endian.little);
    data.setUint32(16, _checksum(payload), Endian.little);
    data.setUint32(20, command ^ 0xffffffff, Endian.little);
    packet.setRange(_headerLength, packet.length, payload);
    socket.add(packet);
    await socket.flush();
  }

  static int _checksum(List<int> bytes) =>
      bytes.fold<int>(0, (sum, byte) => (sum + byte) & 0xffffffff);

  void _notify() {
    if (_disposed) return;
    for (final listener in _listeners.toList()) {
      listener();
    }
  }

  void dispose() {
    _disposed = true;
    _listeners.clear();
    unawaited(stop());
  }
}

class _AdbHeader {
  const _AdbHeader({
    required this.command,
    required this.arg0,
    required this.arg1,
    required this.dataLength,
    required this.checksum,
    required this.magic,
  });

  final int command;
  final int arg0;
  final int arg1;
  final int dataLength;
  final int checksum;
  final int magic;

  factory _AdbHeader.decode(Uint8List bytes) {
