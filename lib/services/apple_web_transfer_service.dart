import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';

import 'log_service.dart';
import 'native_bridge_service.dart';
import 'quick_send_service.dart';

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

  Future<bool> start({
    required List<String> paths,
    required Map<String, String> offeredNames,
    String selectedText = '',
  }) async {
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

      _sessionToken = _randomToken(length: 18);
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
      await _bridge.stopLocalOnlyHotspot();
    }
    notifyListeners();
  }

  Future<void> disposeService() async {
    await stop();
  }

  Future<bool> _ensureHotspotPermission() async {
    if (!Platform.isAndroid) {
      return false;
    }
    final sdk = await _bridge.getAndroidSdkInt() ?? 0;
    final permission = sdk >= 33
        ? Permission.nearbyWifiDevices
        : Permission.locationWhenInUse;
    var status = await permission.status;
    if (!status.isGranted) {
      status = await permission.request();
    }
    return status.isGranted;
  }

  Future<void> _refreshAddresses() async {
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
    found.sort(
      (a, b) => _interfacePriority(
        a.interfaceName,
      ).compareTo(_interfacePriority(b.interfaceName)),
    );
    final next = <String>{
      ..._preferredAddresses.where(_isPrivateIpv4),
      ...found.map((entry) => entry.address),
    }.toList(growable: false);
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
            "frame-ancestors 'none'",
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
      response.statusCode = HttpStatus.internalServerError;
      response.headers.contentType = ContentType.text;
      response.write('Transfer failed: $error');
    } finally {
      await response.close();
    }
  }

  Future<void> _writeHomePage(HttpRequest request) async {
    final uploaded = int.tryParse(
      request.uri.queryParameters['uploaded'] ?? '',
    );
    request.response.headers.contentType = ContentType.html;
    request.response.write(_homePageHtml(uploaded: uploaded));
  }

  Future<void> _sendSharedFile(HttpRequest request, String id) async {
    final shared = _sharedFiles[id];
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
    response.headers
      ..contentType = ContentType.parse(shared.mimeType)
      ..contentLength = await file.length()
      ..set('content-disposition', _contentDisposition(shared.name));
    if (request.method == 'GET') {
      await response.addStream(file.openRead());
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
    return uploaded;
  }

  String _homePageHtml({int? uploaded}) {
    final alias = _htmlEscape(_quickSend.settings?.alias ?? 'Localist device');
    final status = uploaded == null
        ? ''
        : '<div class="success">${uploaded == 1 ? 'File' : '$uploaded files'} '
              'received by $alias.</div>';
    final downloads = _sharedFiles.isEmpty
        ? '<p class="muted">No Android files are selected yet. You can still '
              'send files to the Android device below.</p>'
        : _sharedFiles.values.map((file) {
            final name = _htmlEscape(file.name);
            final size = _formatBytes(file.size);
            return '<a class="file" href="/$_sessionToken/download/${file.id}">'
                '<span><strong>$name</strong><small>$size</small></span>'
                '<b>Download</b></a>';
          }).join();
    final selectedText = _selectedText.isEmpty
        ? ''
        : '<section><h2>Shared text</h2><pre>${_htmlEscape(_selectedText)}</pre>'
              '</section>';
    return '''<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
  <meta name="theme-color" content="#6750a4">
  <title>Localist Web Transfer</title>
  <style>
    :root { color-scheme: light dark; font-family: -apple-system, BlinkMacSystemFont,
      "Segoe UI", sans-serif; background:#f7f2fa; color:#211f26; }
    * { box-sizing:border-box; }
    body { margin:0; min-height:100vh; background:linear-gradient(160deg,#f7f2fa,#eee8f4);
      padding:max(22px,env(safe-area-inset-top)) 16px max(28px,env(safe-area-inset-bottom)); }
    main { width:min(680px,100%); margin:auto; }
    header,section { background:rgba(255,255,255,.88); border:1px solid #ded8e2;
      border-radius:24px; padding:22px; margin-bottom:14px; box-shadow:0 12px 32px #3b2f4a16; }
    h1 { margin:0 0 8px; font-size:28px; } h2 { margin:0 0 14px; font-size:20px; }
    p { line-height:1.5; } .muted,small { color:#69636d; }
    .badge { display:inline-flex; align-items:center; gap:7px; padding:7px 11px;
      border-radius:99px; background:#e9ddff; color:#3f236f; font-weight:700; }
    .success { margin:0 0 14px; padding:12px 14px; border-radius:14px;
      background:#d9f8df; color:#135b25; font-weight:700; }
    .file { display:flex; align-items:center; justify-content:space-between; gap:12px;
      text-decoration:none; color:inherit; padding:14px 0; border-bottom:1px solid #e5dfe8; }
    .file:last-child { border-bottom:0; } .file span { min-width:0; display:grid; gap:4px; }
    .file strong { overflow-wrap:anywhere; } .file b { color:#6750a4; white-space:nowrap; }
    label.upload { display:grid; place-items:center; min-height:120px; padding:18px;
      border:2px dashed #8069a8; border-radius:18px; text-align:center; cursor:pointer; }
    input[type=file] { width:100%; margin-top:12px; }
    button { width:100%; border:0; border-radius:16px; padding:14px 18px; margin-top:14px;
      background:#6750a4; color:white; font:inherit; font-weight:800; cursor:pointer; }
    button:disabled { opacity:.65; } pre { white-space:pre-wrap; overflow-wrap:anywhere;
      background:#f2ecf5; border-radius:14px; padding:14px; }
    footer { text-align:center; color:#69636d; font-size:13px; padding:10px; }
    @media (prefers-color-scheme:dark) {
      :root { background:#151218; color:#eee8f0; } body { background:#151218; }
      header,section { background:#211d24; border-color:#3b343f; box-shadow:none; }
      .muted,small,footer { color:#bdb5c2; } .badge { background:#493565; color:#eadcff; }
      .file { border-color:#3b343f; } .file b { color:#d5baff; }
      pre { background:#2b2530; } .success { background:#173e22; color:#a9efb8; }
    }
  </style>
</head>
<body>
<main>
  <header>
    <span class="badge">● Direct local connection</span>
    <h1>Localist Web Transfer</h1>
    <p class="muted">Transfer files directly between this browser and $alias.
      Files stay on the local hotspot or Wi-Fi network.</p>
  </header>
  $status
  <section>
    <h2>Download from Android</h2>
    $downloads
  </section>
  $selectedText
  <section>
    <h2>Send to Android</h2>
    <form action="/$_sessionToken/upload" method="post" enctype="multipart/form-data"
      onsubmit="this.querySelector('button').disabled=true;
      this.querySelector('button').textContent='Uploading…';">
      <label class="upload">
        <strong>Choose files from iPhone, iPad, or Mac</strong>
        <span class="muted">Multiple files are supported.</span>
        <input type="file" name="files" multiple required>
      </label>
      <button type="submit">Upload to Localist</button>
    </form>
  </section>
  <footer>Keep Localist open until every transfer finishes.</footer>
</main>
</body>
</html>''';
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

  static String _htmlEscape(String value) {
    return const HtmlEscape(HtmlEscapeMode.element).convert(value);
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
        (first == 192 && second == 168) ||
        (first == 169 && second == 254);
  }

  static bool _isIgnoredInterface(String value) {
    final name = value.toLowerCase();
    return name == 'lo' ||
        name.startsWith('lo') ||
        name.startsWith('tun') ||
        name.startsWith('tap') ||
        name.startsWith('utun') ||
        name.startsWith('rmnet') ||
        name.startsWith('ccmni') ||
        name.startsWith('pdp') ||
        name.contains('loopback');
  }

  static int _interfacePriority(String value) {
    final name = value.toLowerCase();
    if (name.contains('softap') || name.startsWith('ap')) {
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
