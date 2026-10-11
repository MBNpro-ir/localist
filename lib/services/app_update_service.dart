import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'log_service.dart';
import 'native_bridge_service.dart';

const _localistRepoOwner = 'MBNpro-ir';
const _localistRepoName = 'localist';
const _latestReleaseApi =
    'https://api.github.com/repos/$_localistRepoOwner/$_localistRepoName/releases/latest';
const localistLatestReleaseUrl =
    'https://github.com/$_localistRepoOwner/$_localistRepoName/releases/latest';
const _windowsCurlExecutable = 'curl.exe';

class AppUpdateService {
  AppUpdateService({
    NativeBridgeService? bridge,
    this.downloadDirectory,
    this.latestReleaseUri,
    this.clientFactory,
  }) : _bridge = bridge ?? NativeBridgeService.instance;

  final NativeBridgeService _bridge;
  final LogService _logs = LogService.instance;
  final Directory? downloadDirectory;
  final Uri? latestReleaseUri;
  final HttpClient Function()? clientFactory;

  Future<String> prepareWindowsUpdate(File archive, AppVersion version) async {
    final marker = File('${archive.path}.ready.json');
    if (await marker.exists()) {
      try {
        final data = jsonDecode(await marker.readAsString()) as Map;
        final bundle = data['bundle'] as String;
        if (data['version'] == version.displayName &&
            p.isWithin(archive.parent.path, bundle) &&
            isCompleteWindowsBundle(bundle, version.displayName)) {
          return bundle;
        }
      } catch (_) {
        /* Rebuild incomplete staging. */
      }
    }
    final stage = Directory(
      '${archive.path}.stage-${DateTime.now().microsecondsSinceEpoch}',
    );
    final bundle = await compute(stageWindowsArchive, [
      archive.path,
      stage.path,
      version.displayName,
    ]);
    final partialMarker = File('${marker.path}.part');
    await partialMarker.writeAsString(
      jsonEncode({'version': version.displayName, 'bundle': bundle}),
      flush: true,
    );
    await partialMarker.rename(marker.path);
    return bundle;
  }

  Future<AppUpdateCheck> checkForUpdate() async {
    _logs.debug('Update check started');
    final current = await AppVersion.current();
    final release = await _fetchLatestRelease();
    final nativeAbis = await _bridge.getAndroidSupportedAbis();
    final supportedAbis = <String>{
      ...nativeAbis.map((abi) => abi.trim()).where((abi) => abi.isNotEmpty),
      if (Platform.isAndroid) _runtimeAndroidAbi(),
    }.where((abi) => abi.isNotEmpty).toList(growable: false);
    final androidAsset = release.pickAndroidAsset(supportedAbis);
    final windowsAsset = release.pickWindowsAsset();
    _logs.debug(
      'Update check finished current=$current latest=${release.version} supportedAbis=$supportedAbis androidAsset=${androidAsset?.name} windowsAsset=${windowsAsset?.name}',
    );
    return AppUpdateCheck(
      current: current,
      release: release,
      androidAsset: androidAsset,
      windowsAsset: windowsAsset,
      supportedAbis: supportedAbis,
    );
  }

  Future<File> downloadAndroidUpdate(
    UpdateAsset asset, {
    required void Function(int received, int total) onProgress,
  }) async {
    final nativeUpdatesPath = await _bridge.getAndroidUpdateDirectory();
    final updatesDir =
        downloadDirectory ??
        Directory(
          nativeUpdatesPath == null || nativeUpdatesPath.isEmpty
              ? p.join(Directory.systemTemp.path, 'updates')
              : nativeUpdatesPath,
        );
    return _downloadAsset(
      asset,
      directory: updatesDir,
      platformName: 'Android',
      onProgress: onProgress,
    );
  }

  Future<File> downloadWindowsUpdate(
    UpdateAsset asset, {
    required void Function(int received, int total) onProgress,
  }) async {
    final supportDirectory =
        downloadDirectory ?? await getApplicationSupportDirectory();
    return _downloadAsset(
      asset,
      directory:
          downloadDirectory ??
          Directory(p.join(supportDirectory.path, 'updates')),
      platformName: 'Windows',
      onProgress: onProgress,
    );
  }

  Future<File> _downloadAsset(
    UpdateAsset asset, {
    required Directory directory,
    required String platformName,
    required void Function(int received, int total) onProgress,
  }) async {
    final cached = File(p.join(directory.path, p.basename(asset.name)));
    if ((asset.size > 0 || asset.digest.isNotEmpty) && await cached.exists()) {
      try {
        await validateUpdateFile(cached, asset);
        final length = await cached.length();
        onProgress(length, length);
        return cached;
      } catch (_) {
        /* A partial or changed release must be downloaded again. */
      }
    }
    try {
      return await _downloadAssetWithDartHttp(
        asset,
        directory: directory,
        platformName: platformName,
        onProgress: onProgress,
      );
    } catch (error) {
      if (!Platform.isWindows || !isCertificateVerificationFailure(error)) {
        rethrow;
      }
      _logs.warning(
        '$platformName updater TLS verification failed in Dart; '
        'retrying with the Windows certificate store.',
      );
      try {
        return await _downloadAssetWithWindowsCurl(
          asset,
          directory: directory,
          platformName: platformName,
          onProgress: onProgress,
        );
      } catch (fallbackError, fallbackStack) {
        _logs.debug(
          '$platformName Windows certificate-store download failed',
          error: fallbackError,
          stack: fallbackStack,
        );
        Error.throwWithStackTrace(fallbackError, fallbackStack);
      }
    }
  }

  Future<File> _downloadAssetWithDartHttp(
    UpdateAsset asset, {
    required Directory directory,
    required String platformName,
    required void Function(int received, int total) onProgress,
  }) async {
    final client = clientFactory?.call() ?? HttpClient();
    client.connectionTimeout = const Duration(seconds: 20);
    try {
      _logs.debug('$platformName update download started asset=${asset.name}');
      final request = await client.getUrl(Uri.parse(asset.downloadUrl));
      request.headers.set(HttpHeaders.userAgentHeader, 'Localist updater');
      final response = await request.close();
      _logs.debug(
        '$platformName update response status=${response.statusCode} length=${response.contentLength}',
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'GitHub returned HTTP ${response.statusCode}.',
          uri: Uri.parse(asset.downloadUrl),
        );
      }
      if (!directory.existsSync()) {
        directory.createSync(recursive: true);
      }
      final file = File(p.join(directory.path, p.basename(asset.name)));
      final partial = File('${file.path}.part');
      final sink = partial.openWrite();
      var received = 0;
      final total = asset.size > 0 ? asset.size : response.contentLength;
      try {
        await for (final chunk in response.timeout(
          const Duration(seconds: 60),
        )) {
          received += chunk.length;
          sink.add(chunk);
          onProgress(received, total);
        }
      } finally {
        await sink.close();
      }
      if (total > 0 && received != total) {
        throw FileSystemException(
          'Downloaded $platformName update size mismatch.',
        );
      }
      await validateUpdateFile(partial, asset);
      await partial.rename(file.path);
      onProgress(received, received);
      _logs.debug('$platformName update saved to ${file.path}');
      return file;
    } catch (error, stack) {
      _logs.debug(
        '$platformName update download failed',
        error: error,
        stack: stack,
      );
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  Future<AppRelease> _fetchLatestRelease() async {
    try {
      return await _fetchLatestReleaseWithDartHttp();
    } catch (error) {
      if (!Platform.isWindows || !isCertificateVerificationFailure(error)) {
        rethrow;
      }
      _logs.warning(
        'GitHub updater TLS verification failed in Dart; '
        'retrying with the Windows certificate store.',
      );
      return _fetchLatestReleaseWithWindowsCurl();
    }
  }

  Future<AppRelease> _fetchLatestReleaseWithDartHttp() async {
    final client = clientFactory?.call() ?? HttpClient();
    client.connectionTimeout = const Duration(seconds: 20);
    try {
      _logs.debug('Fetching latest GitHub release: $_latestReleaseApi');
      final request = await client.getUrl(
        latestReleaseUri ?? Uri.parse(_latestReleaseApi),
      );
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      request.headers.set(HttpHeaders.userAgentHeader, 'Localist updater');
      final response = await request.close();
      final body = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 45));
      _logs.debug(
        'Latest GitHub release response status=${response.statusCode} bytes=${body.length}',
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'GitHub returned HTTP ${response.statusCode}.',
          uri: Uri.parse(_latestReleaseApi),
        );
      }
      final decoded = jsonDecode(body) as Map<String, Object?>;
      final release = AppRelease.fromJson(decoded);
      _logs.debug(
        'Latest GitHub release parsed tag=${release.tagName} assets=${release.assets.map((asset) => asset.name).join(', ')}',
      );
      return release;
    } catch (error, stack) {
      _logs.debug(
        'Fetching latest GitHub release failed',
        error: error,
        stack: stack,
      );
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  Future<AppRelease> _fetchLatestReleaseWithWindowsCurl() async {
    _logs.debug(
      'Fetching latest GitHub release with Windows certificate store',
    );
    final result = await Process.run(
      _windowsCurlExecutable,
      [
        '--fail',
        '--silent',
        '--show-error',
        '--location',
        '--connect-timeout',
        '20',
        '--max-time',
        '45',
        '--user-agent',
        'Localist updater',
        '--header',
        'Accept: application/vnd.github+json',
        _latestReleaseApi,
      ],
      runInShell: false,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    final body = result.stdout.toString();
    final error = result.stderr.toString().trim();
    _logs.debug(
      'Windows certificate-store release response exit=${result.exitCode} '
      'bytes=${body.length}',
    );
    if (result.exitCode != 0) {
      throw HttpException(
        'Windows certificate-store request failed '
        '(curl exit ${result.exitCode})${error.isEmpty ? '' : ': $error'}',
        uri: Uri.parse(_latestReleaseApi),
      );
    }
    try {
      final release = AppRelease.fromJson(
        jsonDecode(body) as Map<String, Object?>,
      );
      _logs.debug(
        'Latest GitHub release parsed with Windows certificate store '
        'tag=${release.tagName} assets=${release.assets.map((asset) => asset.name).join(', ')}',
      );
      return release;
    } on Object catch (parseError, stack) {
      _logs.debug(
        'Parsing the Windows certificate-store release response failed',
        error: parseError,
        stack: stack,
      );
      rethrow;
    }
  }

  Future<File> _downloadAssetWithWindowsCurl(
    UpdateAsset asset, {
    required Directory directory,
    required String platformName,
    required void Function(int received, int total) onProgress,
  }) async {
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
    final fileName = p.basename(asset.name);
    final file = File(p.join(directory.path, fileName));
    final partial = File('${file.path}.part');
    if (partial.existsSync()) {
      await partial.delete();
    }

    _logs.debug(
      '$platformName update download started with Windows certificate store '
      'asset=${asset.name}',
    );
    try {
      final progressTimer = Timer.periodic(const Duration(milliseconds: 300), (
        _,
      ) {
        if (partial.existsSync()) onProgress(partial.lengthSync(), asset.size);
      });
      ProcessResult result;
      try {
        result = await Process.run(
          _windowsCurlExecutable,
          [
            '--fail',
            '--silent',
            '--show-error',
            '--location',
            '--connect-timeout',
            '20',
            '--max-time',
            '600',
            '--retry',
            '2',
            '--retry-delay',
            '1',
            '--user-agent',
            'Localist updater',
            '--output',
            partial.path,
            asset.downloadUrl,
          ],
          runInShell: false,
          stdoutEncoding: utf8,
          stderrEncoding: utf8,
        );
      } finally {
        progressTimer.cancel();
      }
      final error = result.stderr.toString().trim();
      if (result.exitCode != 0) {
        throw HttpException(
          'Windows certificate-store download failed '
          '(curl exit ${result.exitCode})${error.isEmpty ? '' : ': $error'}',
          uri: Uri.parse(asset.downloadUrl),
        );
      }
      if (!partial.existsSync()) {
        throw FileSystemException(
          'Windows certificate-store download did not create a file.',
        );
      }
      final received = await partial.length();
      if (received == 0) {
        throw FileSystemException(
          'Windows certificate-store download returned an empty file.',
        );
      }
      await validateUpdateFile(partial, asset);
      onProgress(received, received);
      if (file.existsSync()) {
        await file.delete();
      }
      final saved = await partial.rename(file.path);
      _logs.debug(
        '$platformName update saved with Windows certificate store to ${saved.path}',
      );
      return saved;
    } finally {
      if (partial.existsSync()) {
        await partial.delete();
      }
    }
  }

  static String _runtimeAndroidAbi() {
    return switch (Abi.current()) {
      Abi.androidArm => 'armeabi-v7a',
      Abi.androidArm64 => 'arm64-v8a',
      Abi.androidIA32 => 'x86',
      Abi.androidX64 => 'x86_64',
      _ => '',
    };
  }
}

Future<void> validateUpdateFile(File file, UpdateAsset asset) async {
  final size = await file.length();
  if (size == 0 || (asset.size > 0 && size != asset.size)) {
    throw const FileSystemException(
      'Update package size does not match the release.',
    );
  }
  if (asset.digest.isNotEmpty) {
    final match = RegExp(
      r'^sha256:([a-fA-F0-9]{64})$',
    ).firstMatch(asset.digest);
    if (match == null) {
      throw const FormatException('Unsupported update digest.');
    }
    final actual = await sha256.bind(file.openRead()).first;
    if (actual.toString() != match.group(1)!.toLowerCase()) {
      throw const FileSystemException(
        'Update package SHA-256 does not match the release.',
      );
    }
  }
}

/// Extract away from the UI isolate. Reject paths/links outside the staging
/// tree and incomplete bundles before offering a restart.
String stageWindowsArchive(List<String> args) {
  final input = InputFileStream(args[0]);
  final destination = p.normalize(p.absolute(args[1]));
  Directory(destination).createSync(recursive: true);
  try {
    final archive = ZipDecoder().decodeStream(input);
    var expandedSize = 0;
    if (archive.length > 10000) {
      throw const FormatException('Too many update files.');
    }
    for (final entry in archive) {
      final path = p.normalize(
        p.join(destination, entry.name.replaceAll('\\', '/')),
      );
      if (!p.isWithin(destination, path) || entry.isSymbolicLink) {
        throw const FormatException('Unsafe update archive path.');
      }
      expandedSize += entry.size;
      if (expandedSize > 2 * 1024 * 1024 * 1024) {
        throw const FormatException('Update is too large.');
      }
      if (!entry.isFile) {
        Directory(path).createSync(recursive: true);
        continue;
      }
      Directory(p.dirname(path)).createSync(recursive: true);
      final output = OutputFileStream(path);
      try {
        entry.writeContent(output);
      } finally {
        output.closeSync();
      }
      if (File(path).lengthSync() != entry.size) {
        throw const FormatException('Incomplete update file.');
      }
    }
  } finally {
    input.closeSync();
  }
  final candidates = [
    destination,
    ...Directory(
      destination,
    ).listSync().whereType<Directory>().map((d) => d.path),
  ];
  for (final bundle in candidates) {
    if (isCompleteWindowsBundle(bundle, args[2])) return bundle;
  }
  throw const FormatException(
    'The update does not contain a complete Localist bundle.',
  );
}

bool isCompleteWindowsBundle(String bundle, String version) {
  final files = [
    'Localist.exe',
    'LocalistUpdater.exe',
    'LocalistRemote.exe',
    'librustdesk.dll',
    'flutter_windows.dll',
    'data/flutter_assets/pubspec.yaml',
  ].map((name) => File(p.join(bundle, name)));
  if (!files.every((file) => file.existsSync() && file.lengthSync() > 0)) {
    return false;
  }
  final pubspec = files.last.readAsStringSync();
  final match = RegExp(
    r'^version:\s*(.+)$',
    multiLine: true,
  ).firstMatch(pubspec);
  return AppVersion.tryParse(match?.group(1) ?? '')?.displayName == version;
}

bool isCertificateVerificationFailure(Object error) {
  final message = error.toString().toLowerCase();
  return message.contains('certificate_verify_failed') ||
      message.contains('certificate verify failed') ||
      message.contains('unable to get local issuer certificate');
}

class AppUpdateCheck {
  const AppUpdateCheck({
    required this.current,
    required this.release,
    required this.androidAsset,
    required this.windowsAsset,
    required this.supportedAbis,
  });

  final AppVersion current;
  final AppRelease release;
  final UpdateAsset? androidAsset;
  final UpdateAsset? windowsAsset;
  final List<String> supportedAbis;

  bool get updateAvailable => release.version.compareTo(current) > 0;
  UpdateAsset? get compatibleAsset => Platform.isWindows
      ? windowsAsset
      : Platform.isAndroid
      ? androidAsset
      : null;

  bool get canInstallOnThisDevice => compatibleAsset != null;
}

class AppRelease {
  const AppRelease({
    required this.name,
    required this.tagName,
    required this.htmlUrl,
    required this.version,
    required this.assets,
  });

  final String name;
  final String tagName;
  final String htmlUrl;
  final AppVersion version;
  final List<UpdateAsset> assets;

  factory AppRelease.fromJson(Map<String, Object?> json) {
    final tagName = json['tag_name'] as String? ?? '';
    final name = json['name'] as String? ?? tagName;
    return AppRelease(
      name: name.isEmpty ? tagName : name,
      tagName: tagName,
      htmlUrl: json['html_url'] as String? ?? localistLatestReleaseUrl,
      version:
          AppVersion.tryParse(tagName) ??
          AppVersion.tryParse(name) ??
          AppVersion.zero,
      assets: (json['assets'] as List<Object?>? ?? const [])
          .whereType<Map>()
          .map(
            (asset) => UpdateAsset.fromJson({
              for (final entry in asset.entries)
                entry.key.toString(): entry.value,
            }),
          )
          .where(
            (asset) =>
                asset.name.toLowerCase().endsWith('.apk') ||
                asset.name.toLowerCase().endsWith('.zip'),
          )
          .where((asset) => asset.downloadUrl.isNotEmpty)
          .toList(growable: false),
    );
  }

  UpdateAsset? pickAndroidAsset(List<String> supportedAbis) {
    final apkAssets = assets
        .where((asset) => asset.name.toLowerCase().endsWith('.apk'))
        .toList(growable: false);
    for (final rawAbi in supportedAbis) {
      final abi = rawAbi.trim().toLowerCase().replaceAll('_', '-');
      final tokens =
          abi.contains('arm64') ||
              abi.contains('aarch64') ||
              abi.contains('armv8')
          ? const ['android-64bit', 'android-arm64-v8a']
          : abi.contains('armeabi') || abi.contains('armv7') || abi == 'arm'
          ? const ['android-32bit', 'android-armeabi-v7a']
          : abi.contains('x86-64') || abi == 'x64'
          ? const ['android-x86-64', 'android-x86_64']
          : const <String>[];
      if (tokens.isEmpty) {
        continue;
      }
      for (final asset in apkAssets) {
        if (tokens.any(asset.name.toLowerCase().contains)) {
          return asset;
        }
      }
    }
    for (final asset in apkAssets) {
      final name = asset.name.toLowerCase();
      if (name.contains('android-universal') || name.contains('universal')) {
        return asset;
      }
    }
    return null;
  }

  UpdateAsset? pickWindowsAsset() {
    for (final asset in assets) {
      final name = asset.name.toLowerCase();
      if (name.endsWith('.zip') &&
          !name.contains('symbols') &&
          (name.contains('windows-64bit') || name.contains('windows-x64'))) {
        return asset;
      }
    }
    return null;
  }
}

class UpdateAsset {
  const UpdateAsset({
    required this.name,
    required this.downloadUrl,
    this.size = 0,
    this.digest = '',
  });

  final String name;
  final String downloadUrl;
  final int size;
  final String digest;

  factory UpdateAsset.fromJson(Map<String, Object?> json) {
    return UpdateAsset(
      name: json['name'] as String? ?? '',
      downloadUrl: json['browser_download_url'] as String? ?? '',
      size: (json['size'] as num? ?? 0).toInt(),
      digest: json['digest'] as String? ?? '',
    );
  }
}

class AppVersion implements Comparable<AppVersion> {
  const AppVersion({required this.parts, required this.build});

  final List<int> parts;
  final int build;

  static const zero = AppVersion(parts: [0, 0, 0], build: 0);

  static Future<AppVersion> current() async {
    final pubspec = await rootBundle.loadString('pubspec.yaml');
    for (final line in pubspec.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('version:')) {
        return tryParse(trimmed.substring('version:'.length).trim()) ?? zero;
      }
    }
    return zero;
  }

  static AppVersion? tryParse(String value) {
    final match = RegExp(
      r'v?(\d+)(?:\.(\d+))?(?:\.(\d+))?(?:\+(\d+))?',
    ).firstMatch(value.trim());
    if (match == null) {
      return null;
    }
    return AppVersion(
      parts: [
        int.parse(match.group(1)!),
        int.tryParse(match.group(2) ?? '') ?? 0,
        int.tryParse(match.group(3) ?? '') ?? 0,
      ],
      build: int.tryParse(match.group(4) ?? '') ?? 0,
    );
  }

  @override
  int compareTo(AppVersion other) {
    for (var index = 0; index < 3; index++) {
      final comparison = parts[index].compareTo(other.parts[index]);
      if (comparison != 0) {
        return comparison;
      }
    }
    return build.compareTo(other.build);
  }

  @override
  String toString() {
    return displayName;
  }

  String get displayName {
    final version = parts.join('.');
    return version;
  }
}
