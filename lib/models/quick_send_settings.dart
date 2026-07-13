import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

class QuickSendSettings {
  const QuickSendSettings({
    required this.alias,
    required this.port,
    required this.multicastGroup,
    required this.destinationDirectory,
    required this.receiveEnabled,
    required this.encryption,
    required this.quickSave,
    required this.quickSaveFavorites,
    required this.overwrite,
    required this.requirePin,
    required this.pin,
    required this.favoriteFingerprints,
  });

  final String alias;
  final int port;
  final String multicastGroup;
  final String destinationDirectory;
  final bool receiveEnabled;
  final bool encryption;
  final bool quickSave;
  final bool quickSaveFavorites;
  final bool overwrite;
  final bool requirePin;
  final String pin;
  final Set<String> favoriteFingerprints;

  static Future<QuickSendSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final hostname = Platform.localHostname.trim();
    return QuickSendSettings(
      alias: prefs.getString(_aliasKey)?.trim().isNotEmpty == true
          ? prefs.getString(_aliasKey)!.trim()
          : hostname.isEmpty
          ? 'Localist device'
          : hostname,
      port: _safePort(prefs.getInt(_portKey) ?? 53317),
      multicastGroup: prefs.getString(_multicastKey) ?? '224.0.0.167',
      destinationDirectory: prefs.getString(_destinationKey) ?? '',
      receiveEnabled: prefs.getBool(_receiveKey) ?? true,
      encryption: prefs.getBool(_encryptionKey) ?? true,
      quickSave: prefs.getBool(_quickSaveKey) ?? false,
      quickSaveFavorites: prefs.getBool(_quickSaveFavoritesKey) ?? true,
      overwrite: prefs.getBool(_overwriteKey) ?? false,
      requirePin: prefs.getBool(_requirePinKey) ?? false,
      pin: prefs.getString(_pinKey) ?? '',
      favoriteFingerprints:
          prefs.getStringList(_favoritesKey)?.toSet() ?? const {},
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setString(_aliasKey, alias),
      prefs.setInt(_portKey, port),
      prefs.setString(_multicastKey, multicastGroup),
      prefs.setString(_destinationKey, destinationDirectory),
      prefs.setBool(_receiveKey, receiveEnabled),
      prefs.setBool(_encryptionKey, encryption),
      prefs.setBool(_quickSaveKey, quickSave),
      prefs.setBool(_quickSaveFavoritesKey, quickSaveFavorites),
      prefs.setBool(_overwriteKey, overwrite),
      prefs.setBool(_requirePinKey, requirePin),
      prefs.setString(_pinKey, pin),
      prefs.setStringList(_favoritesKey, favoriteFingerprints.toList()..sort()),
    ]);
  }

  QuickSendSettings copyWith({
    String? alias,
    int? port,
    String? multicastGroup,
    String? destinationDirectory,
    bool? receiveEnabled,
    bool? encryption,
    bool? quickSave,
    bool? quickSaveFavorites,
    bool? overwrite,
    bool? requirePin,
    String? pin,
    Set<String>? favoriteFingerprints,
  }) {
    return QuickSendSettings(
      alias: alias ?? this.alias,
      port: _safePort(port ?? this.port),
      multicastGroup: multicastGroup ?? this.multicastGroup,
      destinationDirectory: destinationDirectory ?? this.destinationDirectory,
      receiveEnabled: receiveEnabled ?? this.receiveEnabled,
      encryption: encryption ?? this.encryption,
      quickSave: quickSave ?? this.quickSave,
      quickSaveFavorites: quickSaveFavorites ?? this.quickSaveFavorites,
      overwrite: overwrite ?? this.overwrite,
      requirePin: requirePin ?? this.requirePin,
      pin: pin ?? this.pin,
      favoriteFingerprints: favoriteFingerprints ?? this.favoriteFingerprints,
    );
  }

  bool isFavorite(String fingerprint) {
    return favoriteFingerprints.contains(fingerprint);
  }

  static int _safePort(int value) {
    return value >= 1024 && value <= 65535 ? value : 53317;
  }

  static const _aliasKey = 'quickSend.alias';
  static const _portKey = 'quickSend.port';
  static const _multicastKey = 'quickSend.multicastGroup';
  static const _destinationKey = 'quickSend.destinationDirectory';
  static const _receiveKey = 'quickSend.receiveEnabled';
  static const _encryptionKey = 'quickSend.encryption';
  static const _quickSaveKey = 'quickSend.quickSave';
  static const _quickSaveFavoritesKey = 'quickSend.quickSaveFavorites';
  static const _overwriteKey = 'quickSend.overwrite';
  static const _requirePinKey = 'quickSend.requirePin';
  static const _pinKey = 'quickSend.pin';
  static const _favoritesKey = 'quickSend.favoriteFingerprints';
}
