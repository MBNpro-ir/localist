import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mime/mime.dart';
import 'http_file_stream.dart';
import 'feature_activity_service.dart';
import 'apple_web_transfer_service.dart';
import 'media_stream_gallery.dart';
import 'media_stream_player.dart';
import 'log_service.dart';
export 'media_stream_player.dart' show buildMediaPlayerHtml;

class StreamMediaItem {
  StreamMediaItem(this.file)
    : name = file.uri.pathSegments.last,
      mime = lookupMimeType(file.path) ?? 'application/octet-stream';
  final File file;
  final String name;
  final String mime;
}

/// Serves selected local media files with HTTP range support and a web gallery.
///
/// This is intentionally protocol-light: phones, consoles, TVs and wireless
/// display receivers that can open a local URL can play the same stream. The
/// UI keeps the URL visible so a receiver's built-in browser can be used when
/// native casting is unavailable.
class MediaStreamService extends ChangeNotifier {
  MediaStreamService._();
  static final instance = MediaStreamService._();

  HttpServer? _server;
  List<StreamMediaItem> _items = const [];
  int _selectedIndex = 0;
  String _token = '';
  List<String> _addresses = const [];
  int _rangeRequests = 0;

  bool get active => _server != null && _items.isNotEmpty;
  List<StreamMediaItem> get items => List.unmodifiable(_items);
  int get selectedIndex => _selectedIndex;
  String get name => _items.isEmpty ? '' : _items[_selectedIndex].name;
  void selectItem(int index) {
    if (index < 0 || index >= _items.length) {
      throw RangeError.index(index, _items);
    }
    _selectedIndex = index;
    LogService.instance.debug(
      'Media stream: selected item index=$index count=${_items.length}',
    );
    notifyListeners();
  }

  List<String> get addresses => List.unmodifiable(_addresses);
  int get port => _server?.port ?? 0;
  List<String> get urls => [
    for (final address in _addresses)
      Uri(
        scheme: 'http',
        host: address,
        port: port,
        path: '/$_token/items/$_selectedIndex/media',
      ).toString(),
  ];
  List<String> get playerUrls => [
    for (final address in _addresses) 'http://$address:$port',
  ];

  /// The first local player URL is convenient for opening the page on the
  /// host. Other URLs are kept in [playerUrls] for devices on other network
  /// interfaces.
  String? get playerUrl => playerUrls.isEmpty ? null : playerUrls.first;

  bool persian = false;
  Future<void> start(File file) => startFiles([file]);

  Future<void> startFiles(List<File> files) async {
    LogService.instance.debug(
      'Media stream: start requested selected=${files.length} active=$active',
    );
    if (!FeatureActivityService.instance.allows(LocalistFeature.stream)) {
      LogService.instance.debug(
        'Media stream: start rejected due to active feature',
      );
      throw StateError(
        persian
            ? 'ابتدا سرویس فعال را متوقف کنید.'
            : 'Stop the active service first.',
      );
    }
    // Validate the entire selection before replacing an existing stream.
    final selected = <StreamMediaItem>[];
    final paths = <String>{};
    for (final file in files) {
      if (!await file.exists()) {
        LogService.instance.debug(
          'Media stream: file validation failed, missing file',
        );
        throw const FileSystemException('Media file does not exist.');
      }
      final item = StreamMediaItem(file);
      if (!['image/', 'video/', 'audio/'].any(item.mime.startsWith)) {
        LogService.instance.debug(
          'Media stream: file validation failed category=unsupported',
        );
        throw FormatException(
          persian
              ? 'فقط عکس، فیلم یا موسیقی انتخاب کنید: ${item.name}'
              : 'Choose photos, videos or audio: ${item.name}',
        );
      }
      if (paths.add(file.absolute.path)) selected.add(item);
    }
    if (selected.isEmpty) {
      LogService.instance.debug(
        'Media stream: selection empty after deduplication',
      );
      throw const FormatException('No media selected.');
    }
    LogService.instance.debug(
      'Media stream: validated ${selected.length} distinct media items',
    );
    await stop();
    FeatureActivityService.instance.reserve(this, LocalistFeature.stream);
    try {
      _items = selected;
      _selectedIndex = 0;
      _token = List.generate(
        24,
        (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      _server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        0,
        shared: false,
      );
      _server!.listen(
        (request) => unawaited(_handleRequest(request)),
        onError: (_) {},
      );
      _addresses = await _privateAddresses();
      LogService.instance.debug(
        'Media stream: HTTP listener active items=${_items.length} interfaces=${_addresses.length}',
      );
      notifyListeners();
    } catch (e) {
      LogService.instance.debug(
        'Media stream: start failed errorType=${e.runtimeType}, cleaning up',
      );
      await stop();
      rethrow;
    }
  }

  Future<void> stop() async {
    if (active || _server != null) {
      LogService.instance.debug(
        'Media stream: stopping listener items=${_items.length}',
      );
    }
    await _server?.close(force: true);
    _server = null;
    _items = const [];
    _selectedIndex = 0;
    _addresses = const [];
    FeatureActivityService.instance.setActive(
      this,
      LocalistFeature.stream,
      false,
    );
    notifyListeners();
    LogService.instance.debug('Media stream: stopped');
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final response = request.response;
    // Capture this server's selection so an in-flight request cannot acquire
    // a new stream's files while the user replaces their selection.
    final items = _items;
    final token = _token;
    if (LogService.instance.debugModeEnabled && request.method != 'GET') {
      LogService.instance.debug('Media stream: HTTP method=${request.method}');
    }
    try {
      if (request.method != 'GET' && request.method != 'HEAD') {
        response.statusCode = HttpStatus.methodNotAllowed;
        LogService.instance.debug(
          'Media stream: rejected unsupported HTTP method',
        );
        return;
      }
      const webAssets = {
        '/_localist/stream.css': (
          'assets/stream_web/stream.css',
          'text/css; charset=utf-8',
        ),
        '/_localist/stream.js': (
          'assets/stream_web/stream.js',
          'text/javascript; charset=utf-8',
        ),
        '/_localist/Vazirmatn-Regular.ttf': (
          'assets/stream_web/Vazirmatn-Regular.ttf',
          'font/ttf',
        ),
      };
      final asset = webAssets[request.uri.path];
      if (asset != null && items.isNotEmpty) {
        final data = await rootBundle.load(asset.$1);
        response.headers
          ..contentType = ContentType.parse(asset.$2)
          ..set(HttpHeaders.cacheControlHeader, 'no-cache')
          ..set('X-Content-Type-Options', 'nosniff')
          ..set('Cross-Origin-Resource-Policy', 'same-origin');
        response.contentLength = data.lengthInBytes;
        if (request.method == 'GET') {
          response.add(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          );
        }
        return;
      }
      final root = request.uri.path == '/' || request.uri.path == '/$token/';
      final match = RegExp(
        '^/$token/items/([0-9]+)(/media)?\$',
      ).firstMatch(request.uri.path);
      final index = match == null ? null : int.tryParse(match.group(1)!);
      final item = index != null && index >= 0 && index < items.length
          ? items[index]
          : null;
      if (items.isNotEmpty &&
          (root || (item != null && match!.group(2) == null))) {
        response.headers
          ..contentType = ContentType.html
          ..set(HttpHeaders.cacheControlHeader, 'no-store')
          ..set('X-Content-Type-Options', 'nosniff')
          ..set('Referrer-Policy', 'no-referrer')
          ..set(
            'Content-Security-Policy',
            "default-src 'none'; style-src 'self'; script-src 'self'; media-src 'self'; img-src 'self' data:; font-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'",
          );
        if (request.method == 'GET') {
          final webItems = [
            for (var i = 0; i < items.length; i++)
              (
                name: items[i].name,
                mime: items[i].mime,
                playerPath: '/$token/items/$i',
                mediaPath: '/$token/items/$i/media',
              ),
          ];
          response.write(
            root && items.length > 1
                ? buildMediaGalleryHtml(items: webItems, persian: persian)
                : buildMediaPlayerHtml(
                    items: webItems,
                    currentIndex: index ?? 0,
                    name: (item ?? items.first).name,
                    mime: (item ?? items.first).mime,
                    mediaPath: '/$token/items/${index ?? 0}/media',
                    persian: persian,
                    galleryPath: items.length > 1 ? '/' : null,
                    previousPath: index != null && index > 0
                        ? '/$token/items/${index - 1}'
                        : null,
                    nextPath: index != null && index + 1 < items.length
                        ? '/$token/items/${index + 1}'
                        : null,
                  ),
          );
        }
        return;
      }
      final media = request.uri.path == '/$token/media' && items.isNotEmpty
          ? items[_selectedIndex]
          : item != null && match!.group(2) == '/media'
          ? item
          : null;
      if (media == null) {
        response.statusCode = HttpStatus.notFound;
        LogService.instance.debug('Media stream: unknown media route rejected');
        return;
      }
      if (LogService.instance.debugModeEnabled &&
          request.headers.value(HttpHeaders.rangeHeader) != null) {
        _rangeRequests++;
        if (_rangeRequests == 1 || _rangeRequests % 32 == 0) {
          LogService.instance.debug(
            'Media stream: range requests=$_rangeRequests itemIndex=${items.indexOf(media)}',
          );
        }
      }
      await serveMediaFile(request, media.file, media.name);
    } catch (e) {
      LogService.instance.debug(
        'Media stream: HTTP request failed errorType=${e.runtimeType}',
      );
      try {
        response.statusCode = HttpStatus.internalServerError;
      } catch (_) {}
    } finally {
      await response.close().catchError((_) {});
    }
  }

  static Future<List<String>> _privateAddresses() async {
    final values = <String>{};
    try {
      for (final interface in await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      )) {
        if (AppleWebTransferService.isIgnoredNetworkInterface(interface.name)) {
          continue;
        }
        for (final address in interface.addresses) {
          final p = address.address.split('.').map(int.tryParse).toList();
          if (p.length == 4 &&
              p.every((v) => v != null) &&
              (p[0] == 10 ||
                  (p[0] == 172 && p[1]! >= 16 && p[1]! <= 31) ||
                  (p[0] == 192 && p[1] == 168))) {
            values.add(address.address);
          }
        }
      }
    } catch (e) {
      LogService.instance.debug(
        'Media stream: address enumeration failed type=${e.runtimeType}',
      );
    }
    return values.toList()..sort();
  }
}
