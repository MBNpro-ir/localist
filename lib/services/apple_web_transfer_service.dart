import 'dart:async';
import 'feature_activity_service.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'feature_permission_service.dart';

import 'log_service.dart';
import 'native_bridge_service.dart';
import 'quick_send_service.dart';
import 'http_file_stream.dart';

class AppleWebTransferService extends ChangeNotifier {
  AppleWebTransferService._() {
    _bridge.localOnlyHotspotStopped.listen(
      (_) => unawaited(_handleHotspotStopped()),
    );
  }

  static final AppleWebTransferService instance = AppleWebTransferService._();

  final NativeBridgeService _bridge = NativeBridgeService.instance;
  final QuickSendService _quickSend = QuickSendService.instance;
  final LogService _logs = LogService.instance;
  final Map<String, _BrowserSharedFile> _sharedFiles = {};
  final Map<String, _WebPeer> _webPeers = {};
  final Map<String, _BrowserSharedFile> _inboxFiles = {};
  final Map<String, String> _inboxOwners = {};
  final Map<String, String> _inboxSenders = {};
  final Map<String, _BrowserDownload> _downloadTransfers = {};
  final Set<String> _uploadingPeers = {};
  final Map<String, Set<int>> _finishedBatches = {};
  final Map<String, DateTime> _batchActivity = {};
  Directory? _relayDirectory;
  String? _webHtml;
  int _relayBytes = 0;
  List<Map<String, String>> get browserDevices => [
    for (final peer in _webPeers.values)
      if (DateTime.now().difference(peer.lastSeen).inSeconds < 35)
        {'id': peer.id, 'name': peer.name, 'platform': peer.platform},
  ];

  HttpServer? _server;
  Timer? _addressRefreshTimer;
  bool _starting = false;
  bool _active = false;
  bool _cancelStart = false;
  bool _managedHotspot = false;
  bool _manualHotspotRequired = false;
  String _hotspotSsid = '';
  String _hotspotPassword = '';
  String _statusMessage = '';
  String _errorMessage = '';
  String _selectedText = '';
  String _sessionToken = '';
  List<String> _preferredAddresses = const [];
  List<String> _addresses = const [];

  bool get starting => _starting;
  bool get active => _active;
  bool get managedHotspot => _managedHotspot;
  bool get manualHotspotRequired => _manualHotspotRequired;
  String get hotspotSsid => _hotspotSsid;
  String get hotspotPassword => _hotspotPassword;
  String get statusMessage => _statusMessage;
  String get errorMessage => _errorMessage;
  int get sharedFileCount => _sharedFiles.length;
  int get port => _server?.port ?? 0;
  List<String> get addresses => List.unmodifiable(_addresses);

  List<String> get webUrls {
    final currentPort = port;
    if (!_active || currentPort == 0 || _sessionToken.isEmpty) {
      return const [];
    }
    return _addresses
        .map(
          (address) => Uri(
            scheme: 'http',
            host: address,
            port: currentPort,
            path: '/$_sessionToken/',
          ).toString(),
        )
        .toList(growable: false);
  }

  String get primaryUrl => webUrls.firstOrNull ?? '';

  @visibleForTesting
  Uri get loopbackTestUri => Uri(
    scheme: 'http',
    host: InternetAddress.loopbackIPv4.address,
    port: port,
    path: '/$_sessionToken/',
  );

  String get wifiQrPayload =>
      buildWifiQrPayload(ssid: _hotspotSsid, password: _hotspotPassword);

  void setSharedContent({
    required List<String> paths,
    required Map<String, String> offeredNames,
    String selectedText = '',
  }) {
    final existingIds = {
      for (final file in _sharedFiles.values) file.path: file.id,
    };
    final next = <String, _BrowserSharedFile>{};
    for (final value in paths) {
      final file = File(value);
      if (!file.existsSync()) {
        continue;
      }
      final name = QuickSendService.safeRelativeFilePath(
        offeredNames[value] ?? p.basename(value),
      ).replaceAll('\\', '/');
      final entry = _BrowserSharedFile(
        id: existingIds[value] ?? _randomToken(),
        path: value,
        name: name,
        size: _safeFileLength(file),
        mimeType: lookupMimeType(value) ?? 'application/octet-stream',
      );
      next[entry.id] = entry;
    }
    final nextSignature = next.values
        .map((file) => '${file.id}|${file.path}|${file.name}|${file.size}')
        .join('\n');
    final currentSignature = _sharedFiles.values
        .map((file) => '${file.id}|${file.path}|${file.name}|${file.size}')
        .join('\n');
    final normalizedText = selectedText.trim();
    if (nextSignature == currentSignature && normalizedText == _selectedText) {
      return;
    }
    _sharedFiles
      ..clear()
      ..addAll(next);
    _selectedText = normalizedText;
    if (_active) {
      notifyListeners();
    }
  }

  @override
  void notifyListeners() {
    FeatureActivityService.instance.setActive(
      this,
      LocalistFeature.quickSend,
      _active || _starting,
    );
    super.notifyListeners();
  }

  Future<bool> start({
    required List<String> paths,
    required Map<String, String> offeredNames,
    String selectedText = '',
  }) async {
    if (!FeatureActivityService.instance.allows(LocalistFeature.quickSend)) {
      throw StateError(
        'ابتدا سرویس فعال را متوقف کنید. / Stop the active service first.',
      );
    }
    setSharedContent(
      paths: paths,
      offeredNames: offeredNames,
      selectedText: selectedText,
    );
    if (_active) {
      return _managedHotspot;
    }
    if (_starting) {
      return false;
    }
    _cancelStart = false;
    _starting = true;
    _errorMessage = '';
    _statusMessage = '';
    _manualHotspotRequired = false;
    notifyListeners();

    LocalOnlyHotspotInfo hotspotInfo = const LocalOnlyHotspotInfo.unsupported();
    try {
      await _quickSend.initialize();
      if (Platform.isAndroid) {
        final permissionGranted = await _ensureHotspotPermission();
        if (permissionGranted) {
          hotspotInfo = await _bridge.startLocalOnlyHotspot();
        } else {
          _errorMessage =
              'Nearby Wi-Fi permission was not granted. Use the Android hotspot settings instead.';
        }
        if (_cancelStart) {
          if (hotspotInfo.active) {
            await _bridge.stopLocalOnlyHotspot();
          }
          return false;
        }

        _managedHotspot = hotspotInfo.active && hotspotInfo.managed;
        _manualHotspotRequired = !_managedHotspot;
        _hotspotSsid = hotspotInfo.ssid;
        _hotspotPassword = hotspotInfo.password;
        _preferredAddresses = [
          hotspotInfo.primaryAddress,
          ...hotspotInfo.addresses,
        ].where((value) => value.trim().isNotEmpty).toSet().toList();
        if (!_managedHotspot && hotspotInfo.message.isNotEmpty) {
          _errorMessage = hotspotInfo.message;
        }
      } else {
        _managedHotspot = false;
        _manualHotspotRequired = false;
        _hotspotSsid = '';
        _hotspotPassword = '';
        _preferredAddresses = const [];
      }
      if (_cancelStart) {
        return false;
      }

      _sessionToken = _randomToken(length: 18);
      _webHtml = await rootBundle.loadString('assets/web_transfer.html');
      _relayDirectory = await Directory.systemTemp.createTemp(
        'localist-relay-',
      );
      try {
        _server = await HttpServer.bind(
          InternetAddress.anyIPv4,
          _preferredPort,
          shared: false,
        );
      } on SocketException {
        _server = await HttpServer.bind(
          InternetAddress.anyIPv4,
          0,
          shared: false,
        );
      }
      if (_cancelStart) {
        await _closeServer();
        if (_managedHotspot) {
          await _bridge.stopLocalOnlyHotspot();
        }
        _managedHotspot = false;
        return false;
      }
      _server!.listen(
        _handleRequest,
        onError: (Object error, StackTrace stack) {
          _logs.warning('Apple / Mac web transfer server error: $error');
          _logs.debug(
            'Apple / Mac web transfer server stack.',
            error: error,
            stack: stack,
          );
        },
      );
      _active = true;
      _statusMessage = _managedHotspot
          ? 'Private hotspot and browser transfer are ready.'
          : Platform.isWindows
          ? 'Browser transfer is ready on this Windows PC.'
          : 'Browser transfer is ready; turn on a hotspot or use the current Wi-Fi network.';
      await _refreshAddresses();
      _addressRefreshTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => unawaited(_refreshAddresses()),
      );
      _logs.info(
        'Apple / Mac web transfer listening on port ${_server!.port}; '
        'managedHotspot=$_managedHotspot addresses=${_addresses.join(',')}',
      );
      return _managedHotspot;
    } catch (error, stack) {
      _errorMessage = error.toString();
      _logs.warning('Apple / Mac web transfer failed to start: $error');
      _logs.debug(
        'Apple / Mac web transfer start stack.',
        error: error,
        stack: stack,
      );
      await _closeServer();
      if (_managedHotspot) {
        await _bridge.stopLocalOnlyHotspot();
      }
      _managedHotspot = false;
      _active = false;
      rethrow;
    } finally {
      _starting = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    _cancelStart = true;
    final stopManagedHotspot = _managedHotspot;
    _active = false;
    _managedHotspot = false;
    _manualHotspotRequired = false;
    _statusMessage = '';
    _errorMessage = '';
    _hotspotSsid = '';
    _hotspotPassword = '';
    _preferredAddresses = const [];
    _addresses = const [];
    _sessionToken = '';
    await _closeServer();
    if (stopManagedHotspot) {
      if (Platform.isWindows) {
        await _bridge.stopWindowsLocalNetwork();
      } else {
        await _bridge.stopLocalOnlyHotspot();
      }
    }
    notifyListeners();
  }

  Future<void> disposeService() async {
    await stop();
  }

  Future<void> createWindowsLocalNetwork() async {
    if (!Platform.isWindows || _starting || _managedHotspot) return;
    _starting = true;
    notifyListeners();
    try {
      final info = await _bridge.startWindowsLocalNetwork();
      _managedHotspot = info.active && info.managed;
      _hotspotSsid = info.ssid;
      _hotspotPassword = info.password;
      _statusMessage = info.active ? info.message : _statusMessage;
      _errorMessage = info.active ? '' : info.message;
      await _refreshAddresses();
    } finally {
      _starting = false;
      notifyListeners();
    }
  }

  Future<bool> _ensureHotspotPermission() async {
    if (!Platform.isAndroid) {
      return false;
    }
    return FeaturePermissionService.instance.ensure([
      FeatureAccess.nearbyDevices,
    ]);
  }

  Future<void> _refreshAddresses() async {
    _expirePendingTransfers();
    if (!_active) {
      return;
    }
    final found = <_InterfaceAddress>[];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final interface in interfaces) {
        if (_isIgnoredInterface(interface.name)) {
          continue;
        }
        for (final address in interface.addresses) {
          if (_isPrivateIpv4(address.address)) {
            found.add(_InterfaceAddress(interface.name, address.address));
          }
        }
      }
    } catch (error) {
      _logs.debug('Web transfer address refresh skipped: $error');
    }
    found.sort((a, b) {
      final priority = _interfacePriority(
        a.interfaceName,
      ).compareTo(_interfacePriority(b.interfaceName));
      return priority != 0 ? priority : a.address.compareTo(b.address);
    });
    final next = <String>{
      ..._preferredAddresses.where(_isPrivateIpv4),
      ...found.map((entry) => entry.address),
    }.take(8).toList(growable: false);
    if (!listEquals(next, _addresses)) {
      _addresses = next;
      notifyListeners();
    }
  }

  Future<void> _handleHotspotStopped() async {
    if (!_active || !_managedHotspot) {
      return;
    }
    _managedHotspot = false;
    _manualHotspotRequired = true;
    _hotspotSsid = '';
    _hotspotPassword = '';
    _preferredAddresses = const [];
    _errorMessage =
        'The private hotspot stopped. Turn on Android hotspot settings to continue.';
    await _refreshAddresses();
    notifyListeners();
  }

  Future<void> _closeServer() async {
    _addressRefreshTimer?.cancel();
    _addressRefreshTimer = null;
    await _server?.close(force: true);
    _server = null;
    _webPeers.clear();
    _inboxFiles.clear();
    _inboxOwners.clear();
    _inboxSenders.clear();
    _finishedBatches.clear();
    _batchActivity.clear();
    for (final download in _downloadTransfers.values) {
      _quickSend.updateBrowserTransfer(
        download.id,
        download.sent,
        state: QuickSendTransferState.failed,
        message: 'Browser server stopped before receipt confirmation.',
      );
    }
    _downloadTransfers.clear();
    _relayBytes = 0;
    if (_relayDirectory != null) {
      await _relayDirectory!
          .delete(recursive: true)
          .catchError((_) => _relayDirectory!);
      _relayDirectory = null;
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final response = request.response;
    response.headers
      ..set(HttpHeaders.cacheControlHeader, 'no-store')
      ..set('X-Content-Type-Options', 'nosniff')
      ..set('Referrer-Policy', 'no-referrer')
      ..set(
        'Content-Security-Policy',
        "default-src 'self'; style-src 'unsafe-inline'; "
            "script-src 'unsafe-inline'; form-action 'self'; "
            "img-src 'self' blob:; media-src 'self' blob:; frame-ancestors 'none'",
      );
    try {
      if (request.uri.path == '/favicon.ico') {
        response.statusCode = HttpStatus.noContent;
        return;
      }
      final segments = request.uri.pathSegments;
      if (segments.isEmpty || segments.first != _sessionToken) {
        response.statusCode = HttpStatus.notFound;
        response.write('Not found');
        return;
      }
      if (request.uri.path == '/$_sessionToken') {
        response.statusCode = HttpStatus.movedPermanently;
        response.headers.set('location', '/$_sessionToken/');
        return;
      }
      if (request.uri.path == '/$_sessionToken/') {
        await _writeHomePage(request);
        return;
      }
      if (segments.length == 2 &&
          segments[1] == 'join' &&
          request.method == 'POST') {
        await _joinPeer(request);
        return;
      }
      if (segments.length == 2 &&
          segments[1] == 'upload-file' &&
          request.method == 'POST') {
        await _receivePeerFile(request);
        return;
      }
      if (segments.length == 2 &&
          segments[1] == 'receipt' &&
          request.method == 'POST') {
        _receiveDownloadReceipt(request);
        return;
      }
      if (segments.length == 2 && segments[1] == 'state') {
        if (request.method != 'GET') {
          response.statusCode = HttpStatus.methodNotAllowed;
          return;
        }
        _writeSharedState(request);
        return;
      }
      if (segments.length == 2 && segments[1] == 'upload') {
        if (request.method != 'POST') {
          response.statusCode = HttpStatus.methodNotAllowed;
          return;
        }
        final uploaded = await _receiveUploads(request);
        response.statusCode = HttpStatus.seeOther;
        response.headers.set(
          'location',
          Uri(
            path: '/$_sessionToken/',
            queryParameters: {'uploaded': '$uploaded'},
          ).toString(),
        );
        return;
      }
      if (segments.length == 3 && segments[1] == 'download') {
        if (request.method != 'GET' && request.method != 'HEAD') {
          response.statusCode = HttpStatus.methodNotAllowed;
          return;
        }
        await _sendSharedFile(request, segments[2]);
        return;
      }
      response.statusCode = HttpStatus.notFound;
      response.write('Not found');
    } catch (error, stack) {
      _logs.warning('Apple / Mac web request failed: $error');
      _logs.debug('Apple / Mac web request stack.', error: error, stack: stack);
      try {
        response.statusCode = HttpStatus.internalServerError;
        response.headers.contentType = ContentType.text;
        response.write('Transfer failed: $error');
      } catch (_) {
        /* The peer may have disconnected after headers. */
      }
    } finally {
      try {
        await response.close();
      } catch (_) {
        /* Closed by peer. */
      }
    }
  }

  Future<void> _writeHomePage(HttpRequest request) async {
    request.response.headers.contentType = ContentType.html;
    request.response.write(
      (_webHtml ?? '').replaceAll('__BASE__', '/$_sessionToken/'),
    );
  }

  void _writeSharedState(HttpRequest request) {
    final peer = _peerFor(request);
    if (peer != null) peer.lastSeen = DateTime.now();
    final payload = utf8.encode(
      jsonEncode({
        'files': [
          for (final file in _sharedFiles.values)
            {
              'id': file.id,
              'name': file.name,
              'size': file.size,
              'sizeLabel': _formatBytes(file.size),
              'url': '/$_sessionToken/download/${file.id}',
              'mimeType': file.mimeType,
            },
        ],
        'text': _selectedText,
        'host': _quickSend.settings?.alias ?? 'Localist',
        'devices': [
          {
            'id': 'host',
            'name': _quickSend.settings?.alias ?? 'Localist',
            'platform': Platform.operatingSystem,
          },
          ...browserDevices,
          for (final device in _quickSend.devices)
            {
              'id': 'app:${device.id}',
              'name': device.alias,
              'platform': device.deviceType,
            },
        ],
        'inbox': [
          for (final file in _inboxFiles.values)
            if (peer != null && _inboxOwners[file.id] == peer.id)
              {
                'id': file.id,
                'name': file.name,
                'size': file.size,
                'sizeLabel': _formatBytes(file.size),
                'mimeType': file.mimeType,
                'sender': _inboxSenders[file.id],
                'url': '/$_sessionToken/download/${file.id}',
              },
        ],
      }),
    );
    request.response.headers.contentType = ContentType.json;
    request.response.contentLength = payload.length;
    request.response.add(payload);
  }

  Future<void> _sendSharedFile(HttpRequest request, String id) async {
    final peer = _peerFor(request);
    final shared =
        _sharedFiles[id] ??
        (peer != null && _inboxOwners[id] == peer.id ? _inboxFiles[id] : null);
    if (shared == null) {
      request.response.statusCode = HttpStatus.notFound;
      request.response.write('File not found');
      return;
    }
    final file = File(shared.path);
    if (!await file.exists()) {
      request.response.statusCode = HttpStatus.gone;
      request.response.write('The selected file is no longer available.');
      return;
    }
    final response = request.response;
    if (request.uri.queryParameters['inline'] == '1') {
      await serveMediaFile(request, file, shared.name);
      return;
    }
    response.headers
      ..contentType = ContentType.parse(shared.mimeType)
      ..contentLength = await file.length()
      ..set('content-disposition', _contentDisposition(shared.name));
    if (request.method == 'GET') {
      if (peer == null) {
        await response.addStream(file.openRead());
      } else {
        final key = '${peer.id}:$id';
        if (_downloadTransfers.containsKey(key)) {
          response.statusCode = HttpStatus.conflict;
          response.contentLength = 0;
          return;
        }
        final transferId = _quickSend.beginBrowserTransfer(
          deviceName: peer.name,
          fileName: shared.name,
          path: '',
          totalBytes: shared.size,
          direction: QuickSendDirection.sending,
        );
        final pendingDownload = _BrowserDownload(transferId, shared.size);
        _downloadTransfers['${peer.id}:$id'] = pendingDownload;
        var sent = 0;
        var lastReported = 0;
        var lastReportAt = DateTime.now();
        try {
          await response.addStream(
            file.openRead().map((chunk) {
              sent += chunk.length;
              pendingDownload.sent = sent;
              pendingDownload.lastActivity = DateTime.now();
              if (sent - lastReported >= 256 * 1024 ||
                  sent == shared.size ||
                  DateTime.now().difference(lastReportAt).inMilliseconds >=
                      250) {
                lastReported = sent;
                lastReportAt = DateTime.now();
                _quickSend.updateBrowserTransfer(transferId, sent);
              }
              return chunk;
            }),
          );
        } catch (error) {
          _downloadTransfers.remove(key);
          _quickSend.updateBrowserTransfer(
            transferId,
            sent,
            state: QuickSendTransferState.failed,
            message: '$error',
          );
          rethrow;
        }
      }
    }
  }

  Future<int> _receiveUploads(HttpRequest request) async {
    final contentType = request.headers.contentType;
    final boundary = contentType?.parameters['boundary'];
    if (contentType?.mimeType != 'multipart/form-data' ||
        boundary == null ||
        boundary.isEmpty) {
      throw const FormatException('A multipart file upload is required.');
    }
    var uploaded = 0;
    final parts = request.cast<List<int>>().transform(
      MimeMultipartTransformer(boundary),
    );
    await for (final part in parts) {
      final disposition = part.headers['content-disposition'] ?? '';
      final unsafeName = _multipartFilename(disposition);
      if (unsafeName.isEmpty) {
        await part.drain<void>();
        continue;
      }
      final mimeType =
          part.headers['content-type'] ??
          lookupMimeType(unsafeName) ??
          'application/octet-stream';
      final destination = await _quickSend.createReceivedFile(
        unsafeName,
        mimeType,
      );
      final partial = File(
        '${destination.path}.localist-upload-${_randomToken(length: 6)}',
      );
      var byteCount = 0;
      IOSink? sink;
      try {
        await partial.parent.create(recursive: true);
        sink = partial.openWrite();
        await for (final chunk in part) {
          byteCount += chunk.length;
          sink.add(chunk);
        }
        await sink.flush();
        await sink.close();
        sink = null;
        if (await destination.exists()) {
          await destination.delete();
        }
        await partial.rename(destination.path);
      } catch (_) {
        await sink?.close();
        if (await partial.exists()) {
          await partial.delete();
        }
        rethrow;
      }
      _quickSend.recordCompletedBrowserReceive(
        fileName: p.basename(destination.path),
        path: destination.path,
        totalBytes: byteCount,
      );
      uploaded++;
    }
    if (uploaded == 0) {
      throw const FormatException('No file was selected.');
    }
    _quickSend.completeBrowserBatch();
    return uploaded;
  }

  _WebPeer? _peerFor(HttpRequest request) {
    final peer = _webPeers[request.uri.queryParameters['peer']];
    return peer != null && peer.secret == request.uri.queryParameters['key']
        ? peer
        : null;
  }

  Future<void> _joinPeer(HttpRequest request) async {
    if (_webPeers.length >= 64) {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      return;
    }
    if (request.contentLength > 4096) {
      throw const FormatException('Profile too large');
    }
    final bytes = <int>[];
    await for (final chunk in request.timeout(const Duration(seconds: 15))) {
      bytes.addAll(chunk);
      if (bytes.length > 4096) throw const FormatException('Profile too large');
    }
    final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final name = (data['name'] as String? ?? 'Browser').trim();
    if (name.isEmpty || name.length > 64) {
      throw const FormatException('Invalid device name');
    }
    final platform = (data['platform'] as String? ?? 'Web').substring(
      0,
      min(32, (data['platform'] as String? ?? 'Web').length),
    );
    final peer = _WebPeer(
      _randomToken(),
      _randomToken(length: 18),
      name,
      platform,
    );
    _webPeers[peer.id] = peer;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'id': peer.id, 'key': peer.secret}));
    notifyListeners();
  }

  void _receiveDownloadReceipt(HttpRequest request) {
    final peer = _peerFor(request);
    final id = request.uri.queryParameters['file'];
    final bytes = int.tryParse(request.uri.queryParameters['bytes'] ?? '');
    final transfer = peer == null ? null : _downloadTransfers['${peer.id}:$id'];
    if (transfer == null ||
        bytes != transfer.size ||
        transfer.sent != transfer.size) {
      request.response.statusCode = HttpStatus.badRequest;
      return;
    }
    _quickSend.updateBrowserTransfer(
      transfer.id,
      bytes!,
      state: QuickSendTransferState.completed,
    );
    _downloadTransfers.remove('${peer!.id}:$id');
    request.response.statusCode = HttpStatus.noContent;
  }

  Future<void> _receivePeerFile(HttpRequest request) async {
    final peer = _peerFor(request);
    if (peer == null) {
      request.response.statusCode = HttpStatus.unauthorized;
      return;
    }
    if (!_uploadingPeers.add(peer.id)) {
      request.response.statusCode = HttpStatus.conflict;
      return;
    }
    String? transfer;
    File? partial;
    File? relayFile;
    var reserved = 0;
    var keptInInbox = false;
    final token = _sessionToken;
    var received = 0;
    try {
      final q = request.uri.queryParameters;
      final name = QuickSendService.sanitizeFileName(q['name'] ?? 'file');
      final size = int.tryParse(q['size'] ?? '') ?? -1;
      final target = q['target'] ?? 'host';
      final batch = q['batch'] ?? '';
      final count = int.tryParse(q['count'] ?? '') ?? 1;
      final index = int.tryParse(q['index'] ?? '') ?? 0;
      if (size < 0 ||
          (request.contentLength >= 0 && request.contentLength != size) ||
          count < 1 ||
          count > 500 ||
          index < 0 ||
          index >= count ||
          batch.length > 80) {
        throw const FormatException('Invalid file metadata');
      }
      if (target != 'host' &&
          !target.startsWith('app:') &&
          !_webPeers.containsKey(target)) {
        throw const FormatException('Destination disconnected');
      }
      if (target != 'host' &&
          (size > 4 * 1024 * 1024 * 1024 ||
              _relayBytes + size > 8 * 1024 * 1024 * 1024)) {
        throw const FileSystemException('Relay storage limit reached');
      }
      if (target != 'host') {
        reserved = size;
        _relayBytes += size;
      }
      final mime = lookupMimeType(name) ?? 'application/octet-stream';
      final destination = target == 'host'
          ? await _quickSend.createReceivedFile(name, mime)
          : File(p.join(_relayDirectory!.path, _randomToken()));
      if (target != 'host') relayFile = destination;
      partial = File('${destination.path}.part-${_randomToken()}');
      transfer = _quickSend.beginBrowserTransfer(
        deviceName: peer.name,
        fileName: name,
        path: target == 'host' ? destination.path : '',
        totalBytes: size,
      );
      var lastReported = 0;
      var lastReportAt = DateTime.now();
      final sink = partial.openWrite();
      try {
        await sink.addStream(
          request.timeout(const Duration(minutes: 2)).map((chunk) {
            received += chunk.length;
            if (received > size) throw const FormatException('Too many bytes');
            peer.lastSeen = DateTime.now();
            if (received - lastReported >= 256 * 1024 ||
                received == size ||
                DateTime.now().difference(lastReportAt).inMilliseconds >= 250) {
              lastReported = received;
              lastReportAt = DateTime.now();
              _quickSend.updateBrowserTransfer(transfer!, received);
            }
            return chunk;
          }),
        );
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (received != size) throw const FormatException('Incomplete upload');
      if (token != _sessionToken || !_active) {
        throw const HttpException('Browser server stopped');
      }
      await partial.rename(destination.path);
      partial = null;
      if (target.startsWith('app:')) {
        final device = _quickSend.devices
            .where((d) => 'app:${d.id}' == target)
            .firstOrNull;
        if (device == null) {
          throw const FormatException('Localist device disconnected');
        }
        try {
          await _quickSend.sendFiles(
            device,
            [destination.path],
            offeredNames: {destination.path: name},
          );
        } finally {
          await destination.delete();
        }
      } else if (target != 'host') {
        final fileId = _randomToken();
        _inboxFiles[fileId] = _BrowserSharedFile(
          id: fileId,
          path: destination.path,
          name: name,
          size: size,
          mimeType: mime,
        );
        _inboxOwners[fileId] = target;
        _inboxSenders[fileId] = peer.name;
        keptInInbox = true;
      }
      if (token != _sessionToken || !_active) {
        throw const HttpException('Browser server stopped');
      }
      _quickSend.updateBrowserTransfer(
        transfer,
        received,
        state: QuickSendTransferState.completed,
        message: target == 'host'
            ? ''
            : 'Uploaded to host relay; destination must download.',
      );
      final finished = _finishedBatches.putIfAbsent(
        '${peer.id}:$batch',
        () => <int>{},
      );
      finished.add(index);
      _batchActivity['${peer.id}:$batch'] = DateTime.now();
      if (finished.length == count) {
        _finishedBatches.remove('${peer.id}:$batch');
        _batchActivity.remove('${peer.id}:$batch');
        _quickSend.completeBrowserBatch();
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'received': received, 'name': name}));
      notifyListeners();
    } catch (error) {
      if (partial != null && await partial.exists()) await partial.delete();
      if (transfer != null) {
        _quickSend.updateBrowserTransfer(
          transfer,
          received,
          state: QuickSendTransferState.failed,
          message: '$error',
        );
      }
      rethrow;
    } finally {
      if (!keptInInbox && relayFile != null && await relayFile.exists()) {
        await relayFile.delete();
      }
      if (!keptInInbox && token == _sessionToken) _relayBytes -= reserved;
      _uploadingPeers.remove(peer.id);
    }
  }

  void _expirePendingTransfers() {
    final now = DateTime.now();
    final expired = _downloadTransfers.entries
        .where(
          (entry) =>
              now.difference(entry.value.lastActivity) >
              const Duration(minutes: 10),
        )
        .toList();
    for (final entry in expired) {
      _downloadTransfers.remove(entry.key);
      _quickSend.updateBrowserTransfer(
        entry.value.id,
        entry.value.sent,
        state: QuickSendTransferState.failed,
        message: 'Browser did not confirm receipt; retry receiving this file.',
      );
    }
    final staleBatches = _batchActivity.entries
        .where(
          (entry) => now.difference(entry.value) > const Duration(hours: 2),
        )
        .map((e) => e.key)
        .toList();
    for (final key in staleBatches) {
      _batchActivity.remove(key);
      _finishedBatches.remove(key);
    }
    // Expire idle profiles only after a generous reconnect window.
    _webPeers.removeWhere(
      (key, peer) =>
          !_uploadingPeers.contains(key) &&
          !_inboxOwners.containsValue(key) &&
          now.difference(peer.lastSeen) > const Duration(hours: 2),
    );
  }

  static String buildWifiQrPayload({
    required String ssid,
    required String password,
  }) {
    if (ssid.trim().isEmpty) {
      return '';
    }
    final safeSsid = _escapeWifiQrValue(ssid);
    if (password.isEmpty) {
      return 'WIFI:T:nopass;S:$safeSsid;;';
    }
    return 'WIFI:T:WPA;S:$safeSsid;P:${_escapeWifiQrValue(password)};;';
  }

  static String _escapeWifiQrValue(String value) {
    return value.replaceAllMapped(
      RegExp(r'([\\;,:"])'),
      (match) => '\\${match.group(1)}',
    );
  }

  @visibleForTesting
  static bool isUsableNetworkAddress(String value) => _isPrivateIpv4(value);

  static bool isIgnoredNetworkInterface(String value) =>
      _isIgnoredInterface(value);

  @visibleForTesting
  static int networkInterfacePriority(String value) =>
      _interfacePriority(value);

  static String _multipartFilename(String disposition) {
    final extended = RegExp(
      r'''filename\*=(?:UTF-8'')?([^;]+)''',
      caseSensitive: false,
    ).firstMatch(disposition);
    if (extended != null) {
      final encoded = extended.group(1)!.trim().replaceAll('"', '');
      return Uri.decodeComponent(encoded);
    }
    final quoted = RegExp(
      r'''filename="((?:\\.|[^"])*)"''',
      caseSensitive: false,
    ).firstMatch(disposition);
    if (quoted != null) {
      return quoted.group(1)!.replaceAll(r'\"', '"').replaceAll(r'\\', '\\');
    }
    final plain = RegExp(
      r'''filename=([^;]+)''',
      caseSensitive: false,
    ).firstMatch(disposition);
    return plain?.group(1)?.trim() ?? '';
  }

  static String _contentDisposition(String fileName) {
    final safeAscii = p
        .basename(fileName)
        .replaceAll(RegExp(r'[\r\n"\\]'), '_')
        .replaceAll(RegExp(r'[^\x20-\x7E]'), '_');
    return 'attachment; filename="$safeAscii"; '
        "filename*=UTF-8''${Uri.encodeComponent(p.basename(fileName))}";
  }

  static bool _isPrivateIpv4(String value) {
    final parts = value.split('.').map(int.tryParse).toList();
    if (parts.length != 4 || parts.any((part) => part == null)) {
      return false;
    }
    final first = parts[0]!;
    final second = parts[1]!;
    return first == 10 ||
        (first == 172 && second >= 16 && second <= 31) ||
        (first == 192 && second == 168);
  }

  static bool _isIgnoredInterface(String value) {
    final name = value.toLowerCase();
    return name == 'lo' ||
        RegExp(r'^lo\d+$').hasMatch(name) ||
        name.startsWith('tun') ||
        name.startsWith('tap') ||
        name.startsWith('utun') ||
        name.startsWith('rmnet') ||
        name.startsWith('ccmni') ||
        name.startsWith('pdp') ||
        name.contains('loopback') ||
        name.contains('vethernet') ||
        name.contains('hyper-v') ||
        name.contains('virtualbox') ||
        name.contains('vmware') ||
        name.contains('docker') ||
        name.contains('wsl') ||
        name.contains('tailscale') ||
        name.contains('zerotier') ||
        name.contains('hamachi') ||
        name.contains('wireguard') ||
        name.contains('wintun') ||
        name.contains('openvpn') ||
        name.contains('vpn');
  }

  static int _interfacePriority(String value) {
    final name = value.toLowerCase();
    if (name.contains('softap') ||
        name.contains('mobile hotspot') ||
        name.contains('local area connection') ||
        name.startsWith('ap')) {
      return 0;
    }
    if (name.contains('wlan') ||
        name.contains('wifi') ||
        name.contains('wi-fi')) {
      return 1;
    }
    if (name.contains('usb') || name.contains('rndis')) {
      return 2;
    }
    if (name.startsWith('eth') || name.startsWith('en')) {
      return 3;
    }
    return 4;
  }

  static int _safeFileLength(File file) {
    return runCatching(file.lengthSync) ?? 0;
  }

  static T? runCatching<T>(T Function() callback) {
    try {
      return callback();
    } catch (_) {
      return null;
    }
  }

  static String _randomToken({int length = 12}) {
    const alphabet =
        'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    const units = ['KB', 'MB', 'GB', 'TB'];
    var value = bytes / 1024;
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(value >= 10 ? 0 : 1)} ${units[unit]}';
  }

  static const int _preferredPort = 53318;
}

class _BrowserSharedFile {
  const _BrowserSharedFile({
    required this.id,
    required this.path,
    required this.name,
    required this.size,
    required this.mimeType,
  });

  final String id;
  final String path;
  final String name;
  final int size;
  final String mimeType;
}

class _InterfaceAddress {
  const _InterfaceAddress(this.interfaceName, this.address);

  final String interfaceName;
  final String address;
}

class _WebPeer {
  _WebPeer(this.id, this.secret, this.name, this.platform);
  final String id;
  final String secret;
  final String name;
  final String platform;
  DateTime lastSeen = DateTime.now();
}

class _BrowserDownload {
  _BrowserDownload(this.id, this.size);
  final String id;
  final int size;
  int sent = 0;
  DateTime lastActivity = DateTime.now();
}
