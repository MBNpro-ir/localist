import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';
import 'package:xml/xml.dart';
import 'lan_network_service.dart';
import 'log_service.dart';

class DlnaRenderer {
  const DlnaRenderer({
    required this.name,
    required this.controlUrl,
    required this.serviceType,
  });
  final String name;
  final Uri controlUrl;
  final String serviceType;
}

class DlnaCastService extends ChangeNotifier {
  static final instance = DlnaCastService();
  final List<DlnaRenderer> _devices = [];
  List<DlnaRenderer> get devices => List.unmodifiable(_devices);
  bool scanning = false;
  String error = '';
  final _client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
  bool _closed = false;
  final Set<RawDatagramSocket> _sockets = {};
  HttpClient? _scanClient;
  Completer<void>? _scanWait;

  Future<void> discover() async {
    if (scanning || _closed) {
      LogService.instance.debug(
        'DLNA: discovery skipped scanning=$scanning closed=$_closed',
      );
      return;
    }
    LogService.instance.debug('DLNA: discovery started');
    final scanClient = _scanClient = HttpClient()
      ..connectionTimeout = const Duration(seconds: 3);
    bool current() => identical(_scanClient, scanClient);
    scanning = true;
    error = '';
    notifyListeners();
    final locations = <Uri>{};
    final sockets = <RawDatagramSocket>[];
    try {
      for (final route in await LanNetworkService.instance.routes()) {
        if (!current()) return;
        if (!isLanHost(route.address)) continue;
        try {
          final socket = await RawDatagramSocket.bind(
            InternetAddress(route.address),
            0,
          );
          if (!current()) {
            socket.close();
            return;
          }
          sockets.add(socket);
          _sockets.add(socket);
          socket.listen(
            (event) {
              if (!current() || event != RawSocketEvent.read) return;
              Datagram? packet;
              while ((packet = socket.receive()) != null) {
                if (packet!.data.length > 8192) continue;
                final data = utf8.decode(packet.data, allowMalformed: true);
                final location = RegExp(
                  r'^location:\s*(.+)$',
                  caseSensitive: false,
                  multiLine: true,
                ).firstMatch(data)?.group(1)?.trim();
                final uri = Uri.tryParse(location ?? '');
                if (uri != null &&
                    uri.scheme == 'http' &&
                    uri.userInfo.isEmpty &&
                    isLanHost(uri.host) &&
                    (route.contains(uri.host) ||
                        uri.host == packet.address.address) &&
                    locations.length < 64) {
                  locations.add(uri);
                }
              }
            },
            onError: (Object e) {
              LogService.instance.debug(
                'DLNA: SSDP socket error type=${e.runtimeType}',
              );
            },
          );
          socket.send(
            utf8.encode(
              'M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: "ssdp:discover"\r\nMX: 2\r\nST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n\r\n',
            ),
            InternetAddress('239.255.255.250'),
            1900,
          );
        } on SocketException {
          LogService.instance.debug(
            'DLNA: interface bind failed; trying next interface',
          );
          /* Other local interfaces can still work. */
        }
      }
      if (!current()) return;
      final wait = _scanWait = Completer<void>();
      await wait.future.timeout(const Duration(seconds: 3), onTimeout: () {});
      if (!current()) return;
      final devices = <Uri, DlnaRenderer>{};
      final candidates = locations.take(16).toList();
      LogService.instance.debug(
        'DLNA: SSDP discovered ${locations.length} endpoints, probing=${candidates.length}',
      );
      for (var offset = 0; offset < candidates.length; offset += 4) {
        if (!current()) return;
        final results = await Future.wait(
          candidates.skip(offset).take(4).map((location) async {
            try {
              return await _loadRenderer(
                location,
                scanClient,
              ).timeout(const Duration(seconds: 8));
            } catch (e) {
              LogService.instance.debug(
                'DLNA: renderer probe failed type=${e.runtimeType}',
              );
              return null;
            }
          }),
        );
        for (final renderer in results) {
          if (renderer != null) devices[renderer.controlUrl] = renderer;
        }
      }
      if (!current()) return;
      _devices
        ..clear()
        ..addAll(
          devices.values.toList()..sort((a, b) => a.name.compareTo(b.name)),
        );
      LogService.instance.debug(
        'DLNA: discovery completed renderers=${_devices.length}',
      );
    } catch (exception) {
      if (current()) error = '$exception';
      LogService.instance.debug(
        'DLNA: discovery failed type=${exception.runtimeType}',
      );
    } finally {
      for (final socket in sockets) {
        if (_sockets.remove(socket)) socket.close();
      }
      scanClient.close(force: true);
      if (current()) {
        _scanClient = null;
        _scanWait = null;
        scanning = false;
        if (!_closed) notifyListeners();
      }
    }
  }

  void cancelDiscovery() {
    _scanClient?.close(force: true);
    _scanClient = null;
    for (final socket in _sockets) {
      socket.close();
    }
    _sockets.clear();
    final wait = _scanWait;
    _scanWait = null;
    if (wait != null && !wait.isCompleted) wait.complete();
    if (scanning) {
      scanning = false;
      if (!_closed) notifyListeners();
    }
  }

  Future<DlnaRenderer?> loadRenderer(Uri location) =>
      _loadRenderer(location, _client);

  Future<DlnaRenderer?> _loadRenderer(Uri location, HttpClient client) async {
    LogService.instance.debug('DLNA: renderer description probe started');
    if (!isLanHost(location.host)) {
      throw const FormatException('A local IP address is required');
    }
    final request = await client.getUrl(location);
    request.followRedirects = false;
    final response = await request.close().timeout(const Duration(seconds: 4));
    if (response.statusCode != 200) {
      LogService.instance.debug(
        'DLNA: renderer description HTTP ${response.statusCode}',
      );
      await response.drain<void>();
      return null;
    }
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 4))) {
      bytes.addAll(chunk);
      if (bytes.length > 1024 * 1024) {
        throw const FormatException('Device description too large');
      }
    }
    final xml = XmlDocument.parse(utf8.decode(bytes));
    String? text(XmlNode parent, String key) => parent.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == key)
        .firstOrNull
        ?.innerText;
    for (final service in xml.descendants.whereType<XmlElement>().where(
      (e) => e.name.local == 'service',
    )) {
      final type = text(service, 'serviceType') ?? '';
      if (!type.startsWith('urn:schemas-upnp-org:service:AVTransport:')) {
        continue;
      }
      final control = location.resolve(text(service, 'controlURL') ?? '');
      if (control.host != location.host || control.scheme != 'http') continue;
      LogService.instance.debug(
        'DLNA: compatible AVTransport renderer identified',
      );
      return DlnaRenderer(
        name: text(xml, 'friendlyName') ?? location.host,
        controlUrl: control,
        serviceType: type,
      );
    }
    return null;
  }

  Future<void> play(DlnaRenderer device, Uri media, String name) async {
    LogService.instance.debug(
      'DLNA: play requested mediaCategory=${lookupMimeType(name)?.split('/').first ?? 'unknown'}',
    );
    final metadata = mediaMetadata(media, name);
    await action(device, 'SetAVTransportURI', {
      'CurrentURI': '$media',
      'CurrentURIMetaData': metadata,
    });
    await action(device, 'Play', {'Speed': '1'});
    LogService.instance.debug('DLNA: playback dispatch complete');
  }

  static String mediaMetadata(Uri media, String name) {
    final mime = lookupMimeType(name) ?? 'application/octet-stream';
    final kind = mime.startsWith('audio/')
        ? 'object.item.audioItem.musicTrack'
        : mime.startsWith('image/')
        ? 'object.item.imageItem.photo'
        : 'object.item.videoItem';
    return '<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/"><item id="0" parentID="-1" restricted="1"><dc:title>${_escape(name)}</dc:title><upnp:class>$kind</upnp:class><res protocolInfo="http-get:*:$mime:*">${_escape('$media')}</res></item></DIDL-Lite>';
  }

  Future<void> action(
    DlnaRenderer device,
    String action,
    Map<String, String> arguments,
  ) async {
    LogService.instance.debug('DLNA: SOAP action=$action dispatched');
    final request = await _client.postUrl(device.controlUrl);
    request.headers
      ..contentType = ContentType('text', 'xml', charset: 'utf-8')
      ..set('SOAPACTION', '"${device.serviceType}#$action"');
    final body = utf8.encode(
      '<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body><u:$action xmlns:u="${device.serviceType}"><InstanceID>0</InstanceID>${arguments.entries.map((e) => '<${e.key}>${_escape(e.value)}</${e.key}>').join()}</u:$action></s:Body></s:Envelope>',
    );
    request.contentLength = body.length;
    request.add(body);
    final response = await request.close().timeout(const Duration(seconds: 6));
    await response.drain<void>().timeout(const Duration(seconds: 6));
    if (response.statusCode != 200) {
      LogService.instance.debug(
        'DLNA: SOAP action=$action rejected status=${response.statusCode}',
      );
      throw HttpException(
        'Receiver rejected $action (${response.statusCode}). Check supported media formats.',
      );
    }
    LogService.instance.debug(
      'DLNA: SOAP action=$action succeeded status=${response.statusCode}',
    );
  }

  static String _escape(String value) =>
      const HtmlEscape(HtmlEscapeMode.element).convert(value);
  static bool isLanHost(String value) {
    final p = value.split('.').map(int.tryParse).toList();
    return p.length == 4 &&
        p.every((v) => v != null && v >= 0 && v <= 255) &&
        (p[0] == 10 ||
            (p[0] == 192 && p[1] == 168) ||
            (p[0] == 172 && p[1]! >= 16 && p[1]! <= 31) ||
            (p[0] == 169 && p[1] == 254));
  }

  @override
  void dispose() {
    LogService.instance.debug('DLNA: dispose activeSockets=${_sockets.length}');
    _closed = true;
    cancelDiscovery();
    _client.close(force: true);
    super.dispose();
  }
}
