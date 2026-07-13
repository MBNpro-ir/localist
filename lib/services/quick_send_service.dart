import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/quick_send_settings.dart';
import 'log_service.dart';

const quickSendProtocolVersion = '2.1';

class QuickSendDevice {
  const QuickSendDevice({
    required this.ip,
    required this.alias,
    required this.version,
    required this.deviceModel,
    required this.deviceType,
    required this.fingerprint,
    required this.port,
    required this.https,
    required this.download,
    required this.lastSeen,
  });

  final String ip;
  final String alias;
  final String version;
  final String deviceModel;
  final String deviceType;
  final String fingerprint;
  final int port;
  final bool https;
  final bool download;
  final DateTime lastSeen;

  String get id => fingerprint.isEmpty ? '$ip:$port' : fingerprint;
  String get endpoint => '${https ? 'https' : 'http'}://$ip:$port';

  QuickSendDevice copyWith({DateTime? lastSeen}) {
    return QuickSendDevice(
      ip: ip,
      alias: alias,
      version: version,
      deviceModel: deviceModel,
      deviceType: deviceType,
      fingerprint: fingerprint,
      port: port,
      https: https,
      download: download,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  factory QuickSendDevice.fromWire(
    Map<String, dynamic> map, {
    required String ip,
    int fallbackPort = 53317,
    bool fallbackHttps = false,
  }) {
    final protocol = (map['protocol'] as String? ?? '').toLowerCase();
    return QuickSendDevice(
      ip: ip,
      alias: (map['alias'] as String? ?? ip).trim(),
      version: (map['version'] as String? ?? '1.0').trim(),
      deviceModel: (map['deviceModel'] as String? ?? '').trim(),
      deviceType: (map['deviceType'] as String? ?? 'desktop').trim(),
      fingerprint: (map['fingerprint'] as String? ?? '').trim(),
      port: _wireInt(map['port'], fallback: fallbackPort),
      https: protocol.isEmpty ? fallbackHttps : protocol == 'https',
      download: map['download'] == true,
      lastSeen: DateTime.now(),
    );
  }
}

class QuickSendOfferedFile {
  const QuickSendOfferedFile({
    required this.id,
    required this.fileName,
    required this.size,
    required this.fileType,
    required this.preview,
  });

  final String id;
  final String fileName;
  final int size;
  final String fileType;
  final String preview;

  bool get isInlineMessage =>
      preview.isNotEmpty && fileType.toLowerCase().startsWith('text/');

  factory QuickSendOfferedFile.fromWire(
    String fallbackId,
    Map<String, dynamic> map,
  ) {
    return QuickSendOfferedFile(
      id: (map['id'] as String? ?? fallbackId).trim(),
      fileName: (map['fileName'] as String? ?? 'file').trim(),
      size: _wireInt(map['size']),
      fileType: (map['fileType'] as String? ?? 'application/octet-stream'),
      preview: (map['preview'] as String? ?? ''),
    );
  }

  Map<String, Object?> toWire() {
    return {
      'id': id,
      'fileName': fileName,
      'size': size,
      'fileType': fileType,
      if (preview.isNotEmpty) 'preview': preview,
    };
  }
}

class QuickSendPendingRequest {
  QuickSendPendingRequest({
    required this.id,
    required this.sender,
    required this.files,
    required this.createdAt,
  });

  final String id;
  final QuickSendDevice sender;
  final List<QuickSendOfferedFile> files;
  final DateTime createdAt;
  final Completer<Set<String>?> decision = Completer<Set<String>?>();

  int get totalBytes => files.fold(0, (sum, file) => sum + file.size);
}

enum QuickSendDirection { sending, receiving }

enum QuickSendTransferState { waiting, transferring, completed, failed }

class QuickSendTransfer {
  const QuickSendTransfer({
    required this.id,
    required this.deviceName,
    required this.fileName,
    required this.path,
    required this.totalBytes,
    required this.transferredBytes,
    required this.direction,
    required this.state,
    required this.message,
    required this.updatedAt,
  });

  final String id;
  final String deviceName;
  final String fileName;
  final String path;
  final int totalBytes;
  final int transferredBytes;
  final QuickSendDirection direction;
  final QuickSendTransferState state;
  final String message;
  final DateTime updatedAt;

  double get progress => totalBytes <= 0
      ? state == QuickSendTransferState.completed
            ? 1
            : 0
      : (transferredBytes / totalBytes).clamp(0, 1);

  QuickSendTransfer copyWith({
    String? path,
    int? transferredBytes,
    QuickSendTransferState? state,
    String? message,
  }) {
    return QuickSendTransfer(
      id: id,
      deviceName: deviceName,
      fileName: fileName,
      path: path ?? this.path,
      totalBytes: totalBytes,
      transferredBytes: transferredBytes ?? this.transferredBytes,
      direction: direction,
      state: state ?? this.state,
      message: message ?? this.message,
      updatedAt: DateTime.now(),
    );
  }
}

class QuickSendPinRequiredException implements Exception {
  const QuickSendPinRequiredException();

  @override
  String toString() => 'A PIN is required by the receiver.';
}

class QuickSendService extends ChangeNotifier {
  QuickSendService._();

  static final QuickSendService instance = QuickSendService._();

  final LogService _logs = LogService.instance;
  final Map<String, QuickSendDevice> _devices = {};
  final List<QuickSendTransfer> _transfers = [];
  HttpServer? _server;
  RawDatagramSocket? _discoverySocket;
  Timer? _announceTimer;
  Timer? _pruneTimer;
  QuickSendSettings? _settings;
  QuickSendPendingRequest? _pendingRequest;
  _QuickSendSession? _session;
  Future<void>? _initializing;
  bool _restarting = false;
  bool _scanning = false;
  String _lastError = '';
  _QuickSendSecurity? _security;

  bool get initialized => _settings != null;
  bool get serverRunning => _server != null;
  bool get scanning => _scanning;
  bool get restarting => _restarting;
  String get lastError => _lastError;
  QuickSendSettings? get settings => _settings;
  QuickSendPendingRequest? get pendingRequest => _pendingRequest;
  List<QuickSendDevice> get devices {
    return _devices.values.toList(growable: false)
      ..sort((a, b) => a.alias.toLowerCase().compareTo(b.alias.toLowerCase()));
  }

  List<QuickSendTransfer> get transfers => List.unmodifiable(_transfers);

  Future<void> initialize() {
    return _initializing ??= _initialize();
  }

  Future<void> _initialize() async {
    _settings = await QuickSendSettings.load();
    _security = await _loadSecurity();
    if (_settings!.destinationDirectory.isEmpty) {
      final downloads = await getDownloadsDirectory();
      final fallback = await getApplicationDocumentsDirectory();
      _settings = _settings!.copyWith(
        destinationDirectory: (downloads ?? fallback).path,
      );
      await _settings!.save();
    }
    await _startNetwork();
    notifyListeners();
  }

  Future<void> updateSettings(QuickSendSettings value) async {
    final old = _settings;
    _settings = value;
    await value.save();
    notifyListeners();
    final networkChanged =
        old == null ||
        old.port != value.port ||
        old.multicastGroup != value.multicastGroup ||
        old.receiveEnabled != value.receiveEnabled ||
        old.encryption != value.encryption ||
        old.alias != value.alias;
    if (networkChanged) {
      await restart();
    }
  }

  Future<void> toggleFavorite(QuickSendDevice device) async {
    final current = _settings;
    if (current == null || device.fingerprint.isEmpty) {
      return;
    }
    final favorites = {...current.favoriteFingerprints};
    if (!favorites.add(device.fingerprint)) {
      favorites.remove(device.fingerprint);
    }
    _settings = current.copyWith(favoriteFingerprints: favorites);
    await _settings!.save();
    notifyListeners();
  }

  Future<void> restart() async {
    if (_restarting) {
      return;
    }
    _restarting = true;
    notifyListeners();
    try {
      await _stopNetwork();
      await _startNetwork();
    } finally {
      _restarting = false;
      notifyListeners();
    }
  }

  Future<void> disposeService() async {
    await _stopNetwork();
  }

  Future<void> refresh() async {
    await initialize();
    _scanning = true;
    notifyListeners();
    try {
      await _sendDiscoveryPacket(announce: true);
      await Future<void>.delayed(const Duration(milliseconds: 900));
    } finally {
      _scanning = false;
      notifyListeners();
    }
  }

  void acceptPending({Set<String>? fileIds}) {
    final pending = _pendingRequest;
    if (pending == null || pending.decision.isCompleted) {
      return;
    }
    pending.decision.complete(
      fileIds ?? pending.files.map((file) => file.id).toSet(),
    );
  }

  void declinePending() {
    final pending = _pendingRequest;
    if (pending == null || pending.decision.isCompleted) {
      return;
    }
    pending.decision.complete(null);
  }

  Future<QuickSendDevice> addManualDevice({
    required String host,
    required int port,
    required bool https,
  }) async {
    await initialize();
    String certificateHash = '';
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    client.badCertificateCallback = (certificate, _, _) {
      certificateHash = sha256.convert(certificate.der).toString();
      return true;
    };
    try {
      final uri = Uri(
        scheme: https ? 'https' : 'http',
        host: host,
        port: port,
        path: '/api/localsend/v2/info',
      );
      final request = await client.getUrl(uri);
      final response = await request.close().timeout(
        const Duration(seconds: 7),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('Quick Send info failed (${response.statusCode})');
      }
      final map = await _readResponseMap(response);
      final device = QuickSendDevice.fromWire(
        map,
        ip: host,
        fallbackPort: port,
        fallbackHttps: https,
      );
      final pinned = certificateHash.isEmpty || device.fingerprint.isNotEmpty
          ? device
          : QuickSendDevice(
              ip: device.ip,
              alias: device.alias,
              version: device.version,
              deviceModel: device.deviceModel,
              deviceType: device.deviceType,
              fingerprint: certificateHash,
              port: device.port,
              https: device.https,
              download: device.download,
              lastSeen: device.lastSeen,
            );
      if (https &&
          certificateHash.isNotEmpty &&
          pinned.fingerprint.isNotEmpty &&
          _normalizeFingerprint(certificateHash) !=
              _normalizeFingerprint(pinned.fingerprint)) {
        throw const HandshakeException(
          'The advertised fingerprint does not match the HTTPS certificate.',
        );
      }
      _devices[pinned.id] = pinned;
      notifyListeners();
      return pinned;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> sendFiles(
    QuickSendDevice device,
    List<String> paths, {
    String? pin,
  }) async {
    await initialize();
    final files = <QuickSendOfferedFile>[];
    final fileById = <String, File>{};
    for (final value in paths) {
      final file = File(value);
      if (!await file.exists()) {
        continue;
      }
      final id = _randomToken();
      final length = await file.length();
      final offer = QuickSendOfferedFile(
        id: id,
        fileName: p.basename(file.path),
        size: length,
        fileType: _mimeFor(file.path),
        preview: '',
      );
      files.add(offer);
      fileById[id] = file;
      _putTransfer(
        QuickSendTransfer(
          id: 'send-$id',
          deviceName: device.alias,
          fileName: offer.fileName,
          path: file.path,
          totalBytes: length,
          transferredBytes: 0,
          direction: QuickSendDirection.sending,
          state: QuickSendTransferState.waiting,
          message: '',
          updatedAt: DateTime.now(),
        ),
      );
    }
    if (files.isEmpty) {
      throw StateError('No readable files were selected.');
    }

    await _sendOffers(
      device: device,
      files: files,
      fileById: fileById,
      pin: pin,
    );
  }

  Future<void> _sendOffers({
    required QuickSendDevice device,
    required List<QuickSendOfferedFile> files,
    required Map<String, File> fileById,
    String? pin,
  }) async {
    final legacy = device.version == '1.0';
    final client = _clientFor(device);
    try {
      final query = pin == null || pin.isEmpty ? null : {'pin': pin};
      final prepare = await _postJson(
        client,
        _deviceUri(
          device,
          legacy
              ? '/api/localsend/v1/send-request'
              : '/api/localsend/v2/prepare-upload',
          query,
        ),
        {
          'info': _registerInfo(),
          'files': {for (final file in files) file.id: file.toWire()},
        },
      );
      if (prepare.statusCode == HttpStatus.unauthorized) {
        await prepare.drain<void>();
        throw const QuickSendPinRequiredException();
      }
      if (prepare.statusCode == HttpStatus.noContent) {
        for (final file in files) {
          _updateTransfer(
            'send-${file.id}',
            transferredBytes: file.size,
            state: QuickSendTransferState.completed,
          );
        }
        return;
      }
      if (prepare.statusCode != HttpStatus.ok) {
        final message = await utf8.decoder.bind(prepare).join();
        throw HttpException(
          'Receiver rejected the transfer (${prepare.statusCode}) $message',
        );
      }
      final response = await _readResponseMap(prepare);
      final sessionId = legacy ? '' : response['sessionId'] as String? ?? '';
      final tokens = legacy
          ? _asStringMap(response)
          : _asStringMap(response['files']);
      if ((!legacy && sessionId.isEmpty) || tokens.isEmpty) {
        throw const FormatException('Invalid prepare-upload response.');
      }

      for (final file in files) {
        final token = tokens[file.id];
        if (token == null) {
          _updateTransfer(
            'send-${file.id}',
            state: QuickSendTransferState.completed,
            message: 'Skipped by receiver',
          );
          continue;
        }
        final source = fileById[file.id];
        if (source == null) {
          throw const FormatException(
            'Receiver requested an upload for an inline message.',
          );
        }
        await _uploadFile(
          client: client,
          device: device,
          sessionId: sessionId,
          token: token,
          offer: file,
          file: source,
          legacy: legacy,
        );
      }
    } catch (error) {
      for (final file in files) {
        final transfer = _findTransfer('send-${file.id}');
        if (transfer?.state != QuickSendTransferState.completed) {
          _updateTransfer(
            'send-${file.id}',
            state: QuickSendTransferState.failed,
            message: error.toString(),
          );
        }
      }
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> sendText(
    QuickSendDevice device,
    String text, {
    String? pin,
  }) async {
    final clean = text.trim();
    if (clean.isEmpty) {
      return;
    }
    await initialize();
    final id = _randomToken();
    final bytes = utf8.encode(clean).length;
    final offer = QuickSendOfferedFile(
      id: id,
      fileName: 'message.txt',
      size: bytes,
      fileType: 'text/plain',
      preview: clean,
    );
    _putTransfer(
      QuickSendTransfer(
        id: 'send-$id',
        deviceName: device.alias,
        fileName: 'Message',
        path: '',
        totalBytes: bytes,
        transferredBytes: 0,
        direction: QuickSendDirection.sending,
        state: QuickSendTransferState.waiting,
        message: '',
        updatedAt: DateTime.now(),
      ),
    );
    await _sendOffers(
      device: device,
      files: [offer],
      fileById: const {},
      pin: pin,
    );
  }

  Future<void> _startNetwork() async {
    final current = _settings;
    if (current == null) {
      return;
    }
    _lastError = '';
    if (current.receiveEnabled) {
      try {
        if (current.encryption) {
          final security = _security ?? await _loadSecurity();
          _security = security;
          final context = SecurityContext(withTrustedRoots: false)
            ..useCertificateChainBytes(utf8.encode(security.certificate))
            ..usePrivateKeyBytes(utf8.encode(security.privateKey));
          _server = await HttpServer.bindSecure(
            InternetAddress.anyIPv4,
            current.port,
            context,
            shared: true,
          );
        } else {
          _server = await HttpServer.bind(
            InternetAddress.anyIPv4,
            current.port,
            shared: true,
          );
        }
        _server!.listen(_handleHttpRequest, onError: _handleNetworkError);
        _logs.info('Quick Send HTTP server listening on ${current.port}');
      } catch (error) {
        _lastError = 'HTTP ${current.port}: $error';
        _logs.warning('Quick Send server failed: $error');
      }
    }
    try {
      _discoverySocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        current.port,
        reuseAddress: true,
      );
      _discoverySocket!
        ..broadcastEnabled = true
        ..multicastLoopback = false
        ..listen(_handleDiscoveryEvent, onError: _handleNetworkError);
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final interface in interfaces) {
        try {
          _discoverySocket!.joinMulticast(
            InternetAddress(current.multicastGroup),
            interface,
          );
        } catch (error) {
          _logs.debug('Quick Send multicast join skipped: $error');
        }
      }
    } catch (error) {
      _lastError = _lastError.isEmpty
          ? 'UDP ${current.port}: $error'
          : '$_lastError; UDP ${current.port}: $error';
      _logs.warning('Quick Send discovery failed: $error');
    }
    _announceTimer = Timer.periodic(
      const Duration(seconds: 7),
      (_) => unawaited(_sendDiscoveryPacket(announce: true)),
    );
    _pruneTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _pruneDevices(),
    );
    unawaited(_sendDiscoveryPacket(announce: true));
  }

  Future<void> _stopNetwork() async {
    _announceTimer?.cancel();
    _announceTimer = null;
    _pruneTimer?.cancel();
    _pruneTimer = null;
    _discoverySocket?.close();
    _discoverySocket = null;
    await _server?.close(force: true);
    _server = null;
    if (_pendingRequest != null && !_pendingRequest!.decision.isCompleted) {
      _pendingRequest!.decision.complete(null);
    }
    _pendingRequest = null;
    _session = null;
  }

  void _handleDiscoveryEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) {
      return;
    }
    Datagram? datagram;
    while ((datagram = _discoverySocket?.receive()) != null) {
      _handleDiscoveryPacket(datagram!);
    }
  }

  void _handleDiscoveryPacket(Datagram datagram) {
    try {
      final decoded = jsonDecode(utf8.decode(datagram.data));
      if (decoded is! Map<String, dynamic>) {
        return;
      }
      final fingerprint = decoded['fingerprint'] as String? ?? '';
      if (fingerprint.isEmpty || fingerprint == _ownFingerprint) {
        return;
      }
      final device = QuickSendDevice.fromWire(
        decoded,
        ip: datagram.address.address,
        fallbackPort: _settings?.port ?? 53317,
      );
      _devices[device.id] = device;
      notifyListeners();
      if ((decoded['announce'] == true || decoded['announcement'] == true) &&
          serverRunning) {
        unawaited(_sendDiscoveryPacket(announce: false));
      }
    } catch (error) {
      _logs.debug('Ignored invalid Quick Send discovery packet: $error');
    }
  }

  Future<void> _sendDiscoveryPacket({required bool announce}) async {
    final socket = _discoverySocket;
    final current = _settings;
    if (socket == null || current == null) {
      return;
    }
    final bytes = utf8.encode(
      jsonEncode({
        ..._registerInfo(),
        'announce': announce,
        'announcement': announce,
      }),
    );
    try {
      socket.send(bytes, InternetAddress(current.multicastGroup), current.port);
    } catch (error) {
      _logs.debug('Quick Send multicast announcement failed: $error');
    }
  }

  Future<void> _handleHttpRequest(HttpRequest request) async {
    try {
      switch ((request.method, request.uri.path)) {
        case ('GET', '/api/localsend/v2/info'):
        case ('GET', '/api/localsend/v1/info'):
          await _writeJson(request.response, HttpStatus.ok, _infoResponse());
          return;
        case ('POST', '/api/localsend/v2/register'):
        case ('POST', '/api/localsend/v1/register'):
          await _handleRegister(request);
          return;
        case ('POST', '/api/localsend/v2/prepare-upload'):
        case ('POST', '/api/localsend/v1/send-request'):
          await _handlePrepareUpload(request);
          return;
        case ('POST', '/api/localsend/v2/upload'):
          await _handleUpload(request, legacy: false);
          return;
        case ('POST', '/api/localsend/v1/send'):
          await _handleUpload(request, legacy: true);
          return;
        case ('POST', '/api/localsend/v2/cancel'):
        case ('POST', '/api/localsend/v1/cancel'):
          _session = null;
          await request.response.close();
          return;
        default:
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
      }
    } catch (error) {
      _logs.error('Quick Send request failed: $error');
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.write(error.toString());
        await request.response.close();
      } catch (_) {
        // The response may already be closed by a disconnected peer.
      }
    }
  }

  Future<void> _handleRegister(HttpRequest request) async {
    final body = await _readRequestMap(request);
    final remoteIp = _remoteIp(request);
    if (body.isNotEmpty && remoteIp.isNotEmpty) {
      final device = QuickSendDevice.fromWire(
        body,
        ip: remoteIp,
        fallbackPort: _settings?.port ?? 53317,
      );
      if (device.fingerprint != _ownFingerprint) {
        _devices[device.id] = device;
        notifyListeners();
      }
    }
    await _writeJson(request.response, HttpStatus.ok, _infoResponse());
  }

  Future<void> _handlePrepareUpload(HttpRequest request) async {
    final current = _settings!;
    if (_session?.expired == true) {
      _session = null;
    }
    if (_session != null || _pendingRequest != null) {
      await _writeError(request.response, HttpStatus.conflict, 'Busy');
      return;
    }
    if (current.requirePin &&
        request.uri.queryParameters['pin'] != current.pin) {
      await _writeError(
        request.response,
        HttpStatus.unauthorized,
        'PIN required',
      );
      return;
    }
    if (request.contentLength > 2 * 1024 * 1024) {
      await _writeError(
        request.response,
        HttpStatus.badRequest,
        'Body too large',
      );
      return;
    }
    final body = await _readRequestMap(request);
    final info = _asMap(body['info']);
    final fileMap = _asMap(body['files']);
    if (fileMap.isEmpty) {
      await _writeError(request.response, HttpStatus.badRequest, 'No files');
      return;
    }
    final sender = QuickSendDevice.fromWire(
      info,
      ip: _remoteIp(request),
      fallbackPort: current.port,
    );
    final files = <QuickSendOfferedFile>[];
    for (final entry in fileMap.entries) {
      final value = _asMap(entry.value);
      if (value.isEmpty) {
        continue;
      }
      final file = QuickSendOfferedFile.fromWire(entry.key, value);
      if (file.id.isNotEmpty && file.fileName.isNotEmpty && file.size >= 0) {
        files.add(file);
      }
    }
    if (files.isEmpty) {
      await _writeError(
        request.response,
        HttpStatus.badRequest,
        'No valid files',
      );
      return;
    }

    final inlineMessage = files.length == 1 && files.single.isInlineMessage;
    Set<String>? accepted;
    final autoAccept =
        !inlineMessage &&
        (current.quickSave ||
            (current.quickSaveFavorites &&
                current.isFavorite(sender.fingerprint)));
    if (autoAccept) {
      accepted = files.map((file) => file.id).toSet();
    } else {
      final pending = QuickSendPendingRequest(
        id: _randomToken(),
        sender: sender,
        files: files,
        createdAt: DateTime.now(),
      );
      _pendingRequest = pending;
      notifyListeners();
      try {
        accepted = await pending.decision.future.timeout(
          const Duration(seconds: 60),
          onTimeout: () => null,
        );
      } finally {
        if (identical(_pendingRequest, pending)) {
          _pendingRequest = null;
          notifyListeners();
        }
      }
    }
    if (accepted == null) {
      await _writeError(request.response, HttpStatus.forbidden, 'Rejected');
      return;
    }
    final chosen = {
      for (final file in files)
        if (accepted.contains(file.id)) file.id: file,
    };
    if (chosen.isEmpty) {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }
    if (chosen.length == 1 && chosen.values.single.isInlineMessage) {
      final message = chosen.values.single;
      _putTransfer(
        QuickSendTransfer(
          id: 'receive-message-${_randomToken()}',
          deviceName: sender.alias,
          fileName: 'Message',
          path: '',
          totalBytes: message.size,
          transferredBytes: message.size,
          direction: QuickSendDirection.receiving,
          state: QuickSendTransferState.completed,
          message: message.preview,
          updatedAt: DateTime.now(),
        ),
      );
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }
    final sessionId = _randomToken();
    final tokens = {for (final id in chosen.keys) id: _randomToken()};
    _session = _QuickSendSession(
      id: sessionId,
      senderIp: sender.ip,
      senderName: sender.alias,
      files: chosen,
      tokens: tokens,
    );
    await _writeJson(request.response, HttpStatus.ok, {
      'sessionId': sessionId,
      'files': tokens,
    });
  }

  Future<void> _handleUpload(
    HttpRequest request, {
    required bool legacy,
  }) async {
    final session = _session;
    final sessionId = request.uri.queryParameters['sessionId'];
    final fileId = request.uri.queryParameters['fileId'];
    final token = request.uri.queryParameters['token'];
    if (session == null ||
        (!legacy && session.id != sessionId) ||
        session.senderIp != _remoteIp(request) ||
        fileId == null ||
        token == null ||
        session.tokens[fileId] != token ||
        session.completed.contains(fileId)) {
      await _writeError(
        request.response,
        HttpStatus.forbidden,
        'Invalid token',
      );
      return;
    }
    final offer = session.files[fileId]!;
    final destination = await _destinationFile(offer.fileName);
    final transferId = 'receive-${session.id}-$fileId';
    _putTransfer(
      QuickSendTransfer(
        id: transferId,
        deviceName: session.senderName,
        fileName: offer.fileName,
        path: destination.path,
        totalBytes: offer.size,
        transferredBytes: 0,
        direction: QuickSendDirection.receiving,
        state: QuickSendTransferState.transferring,
        message: '',
        updatedAt: DateTime.now(),
      ),
    );
    var received = 0;
    final sink = destination.openWrite(mode: FileMode.writeOnly);
    try {
      await for (final chunk in request) {
        session.touch();
        received += chunk.length;
        if (received > offer.size) {
          throw const FormatException('Received more data than offered.');
        }
        sink.add(chunk);
        _updateTransfer(transferId, transferredBytes: received);
      }
      await sink.flush();
      await sink.close();
      if (received != offer.size) {
        throw FormatException(
          'Expected ${offer.size} bytes, received $received.',
        );
      }
      session.completed.add(fileId);
      _updateTransfer(
        transferId,
        transferredBytes: received,
        state: QuickSendTransferState.completed,
      );
      if (session.completed.length == session.files.length) {
        _session = null;
      }
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
    } catch (error) {
      await sink.close().catchError((_) {});
      try {
        await destination.delete();
      } catch (_) {
        // A peer disconnect can race with destination cleanup.
      }
      _updateTransfer(
        transferId,
        transferredBytes: received,
        state: QuickSendTransferState.failed,
        message: error.toString(),
      );
      rethrow;
    }
  }

  Future<void> _uploadFile({
    required HttpClient client,
    required QuickSendDevice device,
    required String sessionId,
    required String token,
    required QuickSendOfferedFile offer,
    required File file,
    required bool legacy,
  }) async {
    final uri = _deviceUri(
      device,
      legacy ? '/api/localsend/v1/send' : '/api/localsend/v2/upload',
      {if (!legacy) 'sessionId': sessionId, 'fileId': offer.id, 'token': token},
    );
    final request = await client.postUrl(uri);
    request.contentLength = offer.size;
    request.headers.contentType = ContentType.binary;
    var sent = 0;
    _updateTransfer(
      'send-${offer.id}',
      state: QuickSendTransferState.transferring,
    );
    await for (final chunk in file.openRead()) {
      request.add(chunk);
      sent += chunk.length;
      _updateTransfer('send-${offer.id}', transferredBytes: sent);
    }
    final response = await request.close().timeout(const Duration(minutes: 10));
    await response.drain<void>();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('Upload failed (${response.statusCode})');
    }
    _updateTransfer(
      'send-${offer.id}',
      transferredBytes: sent,
      state: QuickSendTransferState.completed,
    );
  }

  HttpClient _clientFor(QuickSendDevice device) {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 7)
      ..idleTimeout = const Duration(seconds: 20);
    client.badCertificateCallback = (certificate, _, _) {
      if (!device.https || device.fingerprint.isEmpty) {
        return false;
      }
      final expected = _normalizeFingerprint(device.fingerprint);
      final actual = _normalizeFingerprint(
        sha256.convert(certificate.der).toString(),
      );
      return expected == actual;
    };
    return client;
  }

  Future<HttpClientResponse> _postJson(
    HttpClient client,
    Uri uri,
    Map<String, Object?> body,
  ) async {
    final request = await client.postUrl(uri);
    request.headers.contentType = ContentType.json;
    request.add(utf8.encode(jsonEncode(body)));
    return request.close().timeout(const Duration(seconds: 70));
  }

  Uri _deviceUri(
    QuickSendDevice device,
    String route, [
    Map<String, String>? query,
  ]) {
    return Uri(
      scheme: device.https ? 'https' : 'http',
      host: device.ip,
      port: device.port,
      path: route,
      queryParameters: query,
    );
  }

  Map<String, Object?> _registerInfo() {
    final current = _settings!;
    return {
      'alias': current.alias,
      'version': quickSendProtocolVersion,
      'deviceModel': Platform.operatingSystem,
      'deviceType': Platform.isAndroid || Platform.isIOS ? 'mobile' : 'desktop',
      'fingerprint': _ownFingerprint,
      'port': current.port,
      'protocol': current.encryption ? 'https' : 'http',
      'download': false,
    };
  }

  Map<String, Object?> _infoResponse() {
    final info = _registerInfo();
    info.remove('port');
    info.remove('protocol');
    return info;
  }

  String get _ownFingerprint {
    return _security?.fingerprint ??
        sha256.convert(utf8.encode('localist.quick-send')).toString();
  }

  Future<_QuickSendSecurity> _loadSecurity() async {
    final prefs = await SharedPreferences.getInstance();
    final privateKey = prefs.getString(_privateKeyPreference);
    final certificate = prefs.getString(_certificatePreference);
    if (privateKey != null &&
        privateKey.isNotEmpty &&
        certificate != null &&
        certificate.isNotEmpty) {
      return _QuickSendSecurity(
        privateKey: privateKey,
        certificate: certificate,
        fingerprint: _certificateHash(certificate),
      );
    }
    final generated = await Isolate.run(_generateSecurity);
    await prefs.setString(_privateKeyPreference, generated.privateKey);
    await prefs.setString(_certificatePreference, generated.certificate);
    return generated;
  }

  Future<File> _destinationFile(String unsafeName) async {
    final current = _settings!;
    final directory = Directory(current.destinationDirectory);
    await directory.create(recursive: true);
    final safeName = sanitizeFileName(unsafeName);
    var destination = File(p.join(directory.path, safeName));
    if (current.overwrite || !await destination.exists()) {
      return destination;
    }
    final extension = p.extension(safeName);
    final stem = p.basenameWithoutExtension(safeName);
    for (var index = 1; index < 10000; index++) {
      destination = File(p.join(directory.path, '$stem ($index)$extension'));
      if (!await destination.exists()) {
        return destination;
      }
    }
    throw StateError('Unable to create a unique destination file.');
  }

  @visibleForTesting
  static String sanitizeFileName(String value) {
    final normalized = value.replaceAll('\\', '/');
    final name = p.posix.basename(normalized).trim();
    final safe = name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
    if (safe.isEmpty || safe == '.' || safe == '..') {
      return 'received-file';
    }
    return safe;
  }

  void _pruneDevices() {
    final cutoff = DateTime.now().subtract(const Duration(seconds: 25));
    final before = _devices.length;
    _devices.removeWhere((_, device) => device.lastSeen.isBefore(cutoff));
    if (_devices.length != before) {
      notifyListeners();
    }
    if (_session?.expired == true) {
      _logs.warning('Expired an inactive Quick Send receive session.');
      _session = null;
    }
  }

  void _putTransfer(QuickSendTransfer transfer) {
    _transfers.insert(0, transfer);
    if (_transfers.length > 40) {
      _transfers.removeRange(40, _transfers.length);
    }
    notifyListeners();
  }

  QuickSendTransfer? _findTransfer(String id) {
    for (final transfer in _transfers) {
      if (transfer.id == id) {
        return transfer;
      }
    }
    return null;
  }

  void _updateTransfer(
    String id, {
    int? transferredBytes,
    QuickSendTransferState? state,
    String? message,
  }) {
    final index = _transfers.indexWhere((transfer) => transfer.id == id);
    if (index < 0) {
      return;
    }
    _transfers[index] = _transfers[index].copyWith(
      transferredBytes: transferredBytes,
      state: state,
      message: message,
    );
    notifyListeners();
  }

  void _handleNetworkError(Object error) {
    _lastError = error.toString();
    _logs.warning('Quick Send network error: $error');
    notifyListeners();
  }
}

class _QuickSendSession {
  _QuickSendSession({
    required this.id,
    required this.senderIp,
    required this.senderName,
    required this.files,
    required this.tokens,
  });

  final String id;
  final String senderIp;
  final String senderName;
  final Map<String, QuickSendOfferedFile> files;
  final Map<String, String> tokens;
  final Set<String> completed = {};
  DateTime lastActivity = DateTime.now();

  bool get expired =>
      DateTime.now().difference(lastActivity) > const Duration(minutes: 10);

  void touch() {
    lastActivity = DateTime.now();
  }
}

class _QuickSendSecurity {
  const _QuickSendSecurity({
    required this.privateKey,
    required this.certificate,
    required this.fingerprint,
  });

  final String privateKey;
  final String certificate;
  final String fingerprint;
}

_QuickSendSecurity _generateSecurity() {
  final keyPair = CryptoUtils.generateRSAKeyPair();
  final privateKey = keyPair.privateKey as RSAPrivateKey;
  final publicKey = keyPair.publicKey as RSAPublicKey;
  final csr = X509Utils.generateRsaCsrPem(
    const {
      'CN': 'Localist Quick Send',
      'O': 'Localist',
      'OU': '',
      'L': '',
      'S': '',
      'C': '',
    },
    privateKey,
    publicKey,
  );
  final certificate = X509Utils.generateSelfSignedCertificate(
    privateKey,
    csr,
    3650,
  );
  return _QuickSendSecurity(
    privateKey: CryptoUtils.encodeRSAPrivateKeyToPemPkcs1(privateKey),
    certificate: certificate,
    fingerprint: _certificateHash(certificate),
  );
}

String _certificateHash(String certificate) {
  final content = certificate
      .replaceAll('\r\n', '\n')
      .split('\n')
      .where((line) => line.isNotEmpty && !line.startsWith('---'))
      .join();
  return sha256.convert(base64Decode(content)).toString();
}

Future<Map<String, dynamic>> _readResponseMap(
  HttpClientResponse response,
) async {
  final text = await utf8.decoder.bind(response).join();
  if (text.trim().isEmpty) {
    return {};
  }
  return _asMap(jsonDecode(text));
}

Future<Map<String, dynamic>> _readRequestMap(
  HttpRequest request, {
  int maxBytes = 2 * 1024 * 1024,
}) async {
  final bytes = BytesBuilder(copy: false);
  var length = 0;
  await for (final chunk in request) {
    length += chunk.length;
    if (length > maxBytes) {
      throw const FormatException('Request body is too large.');
    }
    bytes.add(chunk);
  }
  final text = utf8.decode(bytes.takeBytes());
  if (text.trim().isEmpty) {
    return {};
  }
  return _asMap(jsonDecode(text));
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return {};
}

Map<String, String> _asStringMap(Object? value) {
  final map = _asMap(value);
  return {
    for (final entry in map.entries)
      if (entry.value is String) entry.key: entry.value as String,
  };
}

Future<void> _writeJson(HttpResponse response, int status, Object value) async {
  response.statusCode = status;
  response.headers.contentType = ContentType.json;
  response.write(jsonEncode(value));
  await response.close();
}

Future<void> _writeError(
  HttpResponse response,
  int status,
  String message,
) async {
  response.statusCode = status;
  response.write(message);
  await response.close();
}

String _remoteIp(HttpRequest request) {
  return request.connectionInfo?.remoteAddress.address ?? '';
}

int _wireInt(Object? value, {int fallback = 0}) {
  return switch (value) {
    int number => number,
    num number => number.toInt(),
    String text => int.tryParse(text) ?? fallback,
    _ => fallback,
  };
}

String _randomToken() {
  final random = Random.secure();
  final bytes = List<int>.generate(18, (_) => random.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

String _normalizeFingerprint(String value) {
  return value.toLowerCase().replaceAll(RegExp('[^0-9a-f]'), '');
}

String _mimeFor(String fileName) {
  return switch (p.extension(fileName).toLowerCase()) {
    '.jpg' || '.jpeg' => 'image/jpeg',
    '.png' => 'image/png',
    '.gif' => 'image/gif',
    '.webp' => 'image/webp',
    '.mp4' => 'video/mp4',
    '.mkv' => 'video/x-matroska',
    '.mp3' => 'audio/mpeg',
    '.pdf' => 'application/pdf',
    '.txt' || '.md' || '.csv' || '.json' => 'text/plain',
    '.apk' => 'application/vnd.android.package-archive',
    '.zip' => 'application/zip',
    _ => 'application/octet-stream',
  };
}

const _privateKeyPreference = 'quickSend.security.privateKey';
const _certificatePreference = 'quickSend.security.certificate';
