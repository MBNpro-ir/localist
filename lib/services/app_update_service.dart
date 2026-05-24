import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'log_service.dart';
import 'native_bridge_service.dart';

const _localistRepoOwner = 'MBNpro-ir';
const _localistRepoName = 'localist';
const _latestReleaseApi =
    'https://api.github.com/repos/$_localistRepoOwner/$_localistRepoName/releases/latest';
const localistLatestReleaseUrl =
    'https://github.com/$_localistRepoOwner/$_localistRepoName/releases/latest';

class AppUpdateService {
  AppUpdateService({NativeBridgeService? bridge})
    : _bridge = bridge ?? NativeBridgeService.instance;

  final NativeBridgeService _bridge;
  final LogService _logs = LogService.instance;

  Future<AppUpdateCheck> checkForUpdate() async {
    _logs.debug('Update check started');
    final current = await AppVersion.current();
    final release = await _fetchLatestRelease();
    final supportedAbis = await _bridge.getAndroidSupportedAbis();
    final androidAsset = release.pickAndroidAsset(supportedAbis);
    _logs.debug(
      'Update check finished current=$current latest=${release.version} supportedAbis=$supportedAbis selectedAsset=${androidAsset?.name}',
    );
    return AppUpdateCheck(
      current: current,
      release: release,
      androidAsset: androidAsset,
      supportedAbis: supportedAbis,
    );
  }

  Future<File> downloadAndroidUpdate(
    UpdateAsset asset, {
    required void Function(int received, int total) onProgress,
  }) async {
    final client = HttpClient();
    try {
      _logs.debug('Android update download started asset=${asset.name}');
      final request = await client.getUrl(Uri.parse(asset.downloadUrl));
      request.headers.set(HttpHeaders.userAgentHeader, 'Localist updater');
      final response = await request.close();
      _logs.debug(
        'Android update download response status=${response.statusCode} length=${response.contentLength}',
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'GitHub returned HTTP ${response.statusCode}.',
          uri: Uri.parse(asset.downloadUrl),
        );
      }
      final nativeUpdatesPath = await _bridge.getAndroidUpdateDirectory();
      final updatesDir = Directory(
        nativeUpdatesPath == null || nativeUpdatesPath.isEmpty
            ? '${Directory.systemTemp.path}/updates'
            : nativeUpdatesPath,
      );
      if (!updatesDir.existsSync()) {
        updatesDir.createSync(recursive: true);
      }
      final file = File('${updatesDir.path}/${asset.name}');
      final sink = file.openWrite();
      var received = 0;
      final total = response.contentLength;
      try {
        await for (final chunk in response) {
          received += chunk.length;
          sink.add(chunk);
          _logs.debug(
            'Android update download chunk bytes=${chunk.length} received=$received total=$total',
          );
          onProgress(received, total);
        }
      } finally {
        await sink.close();
      }
      final expectedLength = response.contentLength;
      if (expectedLength > 0 && received != expectedLength) {
        throw const FileSystemException('Downloaded APK size mismatch.');
      }
      _logs.debug('Android update download saved to ${file.path}');
      return file;
    } catch (error, stack) {
      _logs.debug('Android update download failed', error: error, stack: stack);
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  Future<AppRelease> _fetchLatestRelease() async {
    final client = HttpClient();
    try {
      _logs.debug('Fetching latest GitHub release: $_latestReleaseApi');
      final request = await client.getUrl(Uri.parse(_latestReleaseApi));
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      request.headers.set(HttpHeaders.userAgentHeader, 'Localist updater');
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
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
}

class AppUpdateCheck {
  const AppUpdateCheck({
    required this.current,
    required this.release,
    required this.androidAsset,
    required this.supportedAbis,
  });

  final AppVersion current;
  final AppRelease release;
  final UpdateAsset? androidAsset;
  final List<String> supportedAbis;

  bool get updateAvailable => release.version.compareTo(current) > 0;
  bool get canInstallOnThisDevice => androidAsset != null;
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
      assets:
          (json['assets'] as List<Object?>?)
              ?.whereType<Map<String, Object?>>()
              .map(UpdateAsset.fromJson)
              .where((asset) => asset.downloadUrl.isNotEmpty)
              .toList(growable: false) ??
          const [],
    );
  }

  UpdateAsset? pickAndroidAsset(List<String> supportedAbis) {
    final apkAssets = assets
        .where((asset) => asset.name.toLowerCase().endsWith('.apk'))
        .toList(growable: false);
    for (final abi in supportedAbis) {
      final token = switch (abi) {
        'arm64-v8a' => 'android-arm64-v8a',
        'armeabi-v7a' => 'android-armeabi-v7a',
        'x86_64' => 'android-x86_64',
        _ => '',
      };
      if (token.isEmpty) {
        continue;
      }
      for (final asset in apkAssets) {
        if (asset.name.toLowerCase().contains(token)) {
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
}

class UpdateAsset {
  const UpdateAsset({required this.name, required this.downloadUrl});

  final String name;
  final String downloadUrl;

  factory UpdateAsset.fromJson(Map<String, Object?> json) {
    return UpdateAsset(
      name: json['name'] as String? ?? '',
      downloadUrl: json['browser_download_url'] as String? ?? '',
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
