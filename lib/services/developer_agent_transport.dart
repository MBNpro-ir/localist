import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Shared application-level protocol used by Local LAN and RustDesk tunnels.
abstract interface class DeveloperBridgeTransport {
  Future<void> connect();
  Future<Object?> echo(Object? payload);
  Future<Map<String, dynamic>> sendApk(File file);
  Future<void> close();
}

/// Direct TCP/TLS transport to the phone's Android Developer Agent.
class LocalLanTransport extends _TlsDeveloperAgentTransport {
  LocalLanTransport({
    required super.host,
    required super.port,
    required super.pairingCode,
    required super.certificateSha256,
  });
}

/// Connects to a local port already forwarded by the RustDesk Network Tunnel.
/// The TLS pin and application protocol are identical to [LocalLanTransport].
class RustDeskRemoteTransport extends _TlsDeveloperAgentTransport {
  RustDeskRemoteTransport({
    required int localPort,
    required super.pairingCode,
    required super.certificateSha256,
  }) : super(host: InternetAddress.loopbackIPv4.address, port: localPort);
}

class _TlsDeveloperAgentTransport implements DeveloperBridgeTransport {
  _TlsDeveloperAgentTransport({
    required this.host,
    required this.port,
    required this.pairingCode,
    required String certificateSha256,
  }) : certificateSha256 = _normalizeFingerprint(certificateSha256) {
    if (port < 1 || port > 65535) throw ArgumentError.value(port, 'port');
    if (!RegExp(r'^\d{8}$').hasMatch(pairingCode)) {
      throw ArgumentError.value(pairingCode, 'pairingCode');
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(this.certificateSha256)) {
      throw ArgumentError.value(certificateSha256, 'certificateSha256');
    }
  }

  static const int _maxFrameBytes = 1024 * 1024;
  static const int _fileChunkBytes = _maxFrameBytes - 1;
  final String host;
  final int port;
  final String pairingCode;
  final String certificateSha256;
  final Random _random = Random.secure();
  SecureSocket? _socket;
  _AgentFrameReader? _reader;

  bool get isConnected => _socket != null;

  @override
  Future<void> connect() async {
    if (_socket != null) return;
    final socket = await SecureSocket.connect(
      host,
      port,
      context: SecurityContext(withTrustedRoots: false),
      timeout: const Duration(seconds: 12),
      onBadCertificate: (certificate) =>
          sha256.convert(certificate.der).toString() == certificateSha256,
    );
    _socket = socket;
    _reader = _AgentFrameReader(socket);
    try {
      final hello = await _readJson();
      if (hello['type'] != 'hello' || hello['version'] != 1) {
        throw const FormatException('Unsupported Developer Agent handshake');
      }
      final advertisedPin = _normalizeFingerprint(
        hello['certificateSha256']?.toString() ?? '',
      );
      if (advertisedPin != certificateSha256) {
        throw const FormatException('Android certificate fingerprint mismatch');
      }
      final nonce = base64.decode(hello['nonce']?.toString() ?? '');
      final mac = Hmac(sha256, utf8.encode(pairingCode)).convert(nonce);
      await _writeJson({'type': 'auth', 'mac': base64.encode(mac.bytes)});
      final accepted = await _readJson();
      if (accepted['type'] != 'auth_ok' || accepted['version'] != 1) {
        throw const SocketException('Android Developer Agent rejected pairing');
      }
    } catch (_) {
      await close();
      rethrow;
    }
  }

  @override
  Future<Object?> echo(Object? payload) async {
    _ensureConnected();
    final id = List<int>.generate(
      12,
      (_) => _random.nextInt(256),
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    await _writeJson({'type': 'echo', 'id': id, 'payload': payload});
    final response = await _readJson();
    if (response['type'] != 'echo' || response['id'] != id) {
      throw const FormatException('Unexpected Developer Agent echo response');
    }
    return response['payload'];
  }

  @override
  Future<Map<String, dynamic>> sendApk(File file) async {
    _ensureConnected();
    if (!file.path.toLowerCase().endsWith('.apk')) {
      throw const FormatException('Choose an APK file');
    }
    final size = await file.length();
    if (size <= 0 || size > 512 * 1024 * 1024) {
      throw const FormatException('APK size is outside the supported range');
    }
    final hash = await sha256.bind(file.openRead()).first;
    await _writeJson({
      'type': 'file.begin',
      'name': file.uri.pathSegments.isEmpty
          ? 'application.apk'
          : file.uri.pathSegments.last,
      'size': size,
      'sha256': hash.toString(),
    });

    final handle = await file.open();
    var sentBytes = 0;
    try {
      while (true) {
        final chunk = await handle.read(_fileChunkBytes);
        if (chunk.isEmpty) break;
        await _writeFrame(2, chunk);
        sentBytes += chunk.length;
      }
    } on Object catch (error) {
      throw SocketException(
        'APK transfer stopped after $sentBytes of $size bytes: $error',
      );
    } finally {
      await handle.close();
    }
    final response = await _readJson();
    if (response['type'] != 'apkReceived' ||
        response['sha256'] != hash.toString() ||
        response['size'] != size) {
      throw const FormatException('Android did not validate the received APK');
    }
    return response;
  }

  @override
  Future<void> close() async {
    final socket = _socket;
    if (socket == null) return;
    try {
      await _writeJson({'type': 'session.close'});
      final acknowledgement = await _readJson().timeout(
        const Duration(seconds: 2),
      );
      if (acknowledgement['type'] != 'session.closed') {
        throw const FormatException('Android did not acknowledge session close');
      }
    } catch (_) {
      // The peer may already have closed the session.
    }
    final reader = _reader;
    _socket = null;
    _reader = null;
    try {
      await reader?.close();
    } finally {
      await socket.close();
    }
  }

  Future<void> _writeJson(Map<String, Object?> value) =>
      _writeFrame(1, utf8.encode(jsonEncode(value)));

  Future<void> _writeFrame(int type, List<int> body) async {
    final socket = _socket;
    if (socket == null) throw const SocketException('Agent is disconnected');
    if (body.length + 1 > _maxFrameBytes) {
      throw const FormatException('Developer Agent frame is too large');
    }
    final packet = Uint8List(body.length + 5);
    final data = ByteData.sublistView(packet);
    data.setUint32(0, body.length + 1, Endian.big);
    packet[4] = type;
    packet.setRange(5, packet.length, body);
    socket.add(packet);
    await socket.flush();
  }

  Future<Map<String, dynamic>> _readJson() async {
    final frame = await _reader!.read();
    if (frame.type != 1) throw const FormatException('Expected JSON frame');
    final decoded = jsonDecode(utf8.decode(frame.body));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid Developer Agent response');
    }
    return decoded;
  }

  void _ensureConnected() {
    if (_socket == null || _reader == null) {
      throw const SocketException('Connect to the Android Agent first');
    }
  }

  static String _normalizeFingerprint(String value) =>
      value.replaceAll(':', '').trim().toLowerCase();
}

class _AgentFrame {
  const _AgentFrame(this.type, this.body);
  final int type;
  final Uint8List body;
}

class _AgentFrameReader {
  _AgentFrameReader(Socket socket) : _iterator = StreamIterator(socket);

  final StreamIterator<Uint8List> _iterator;
  final List<int> _pending = [];

  Future<void> close() async {
    await _iterator.cancel();
  }

  Future<_AgentFrame> read() async {
    final header = await _readExact(4);
    final length = ByteData.sublistView(header).getUint32(0, Endian.big);
    if (length < 1 || length > _TlsDeveloperAgentTransport._maxFrameBytes) {
      throw const FormatException('Invalid Developer Agent frame length');
    }
    final data = await _readExact(length);
    return _AgentFrame(data.first, Uint8List.fromList(data.sublist(1)));
  }

  Future<Uint8List