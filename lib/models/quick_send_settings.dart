import 'dart:io';

import 'package:characters/characters.dart';
import 'package:shared_preferences/shared_preferences.dart';

class QuickSendSettings {
  const QuickSendSettings({
    required this.alias,
    required this.port,
    required this.multicastGroup,
    required this.destinationDirectory,
    required this.destinationCustomized,
    required this.receiveEnabled,
    required this.encryption,
    required this.quickSave,
    required this.quickSaveFavorites,
    required this.overwrite,
    required this.requirePin,
    required this.pin,
    required this.favoriteFingerprints,
    this.profileSetupCompleted = false,
    this.avatarPreset = 'person',
    this.avatarColorValue = 0xFF006A6A,
    this.profileImagePath = '',
  });

  final String alias;
  final int port;
  final String multicastGroup;
  final String destinationDirectory;
  final bool destinationCustomized;
  final bool receiveEnabled;
  final bool encryption;
  final bool quickSave;
  final bool quickSaveFavorites;
  final bool overwrite;
  final bool requirePin;
  final String pin;
  final Set<String> favoriteFingerprints;
  final bool profileSetupCompleted;
  final String avatarPreset;
  final int avatarColorValue;
  final String profileImagePath;

  static const int maxAliasCharacters = 32;

  static Future<bool> hasDestinationCustomizationMarker() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_destinationCustomizedKey);
  }

  static Future<QuickSendSettings> load({
    String? defaultAlias,
    bool forceDefaultAlias = false,
    String legacyDefaultDestination = '',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final hostname = Platform.localHostname.trim();
    final savedAlias = prefs.getString(_aliasKey)?.trim() ?? '';
    final savedDestination = prefs.getString(_destinationKey)?.trim() ?? '';
    final destinationCustomized = prefs.containsKey(_destinationCustomizedKey)
        ? prefs.getBool(_destinationCustomizedKey) ?? false
        : savedDestination.isNotEmpty &&
              _pathKey(savedDestination) != _pathKey(legacyDefaultDestination);
    final resolvedDefaultAlias = defaultAlias?.trim().isNotEmpty == true
        ? defaultAlias!.trim()
        : hostname.isEmpty || hostname.toLowerCase() == 'localhost'
        ? 'Localist device'
        : hostname;
    return QuickSendSettings(
      alias: forceDefaultAlias || savedAlias.isEmpty
          ? resolvedDefaultAlias
          : savedAlias,
      port: _safePort(prefs.getInt(_portKey) ?? 53317),
      multicastGroup: prefs.getString(_multicastKey) ?? '224.0.0.167',
      destinationDirectory: savedDestination,
      destinationCustomized: destinationCustomized,
      receiveEnabled: prefs.getBool(_receiveKey) ?? true,
      encryption: prefs.getBool(_encryptionKey) ?? true,
      quickSave: prefs.getBool(_quickSaveKey) ?? false,
      quickSaveFavorites: prefs.getBool(_quickSaveFavoritesKey) ?? true,
      overwrite: prefs.getBool(_overwriteKey) ?? false,
      requirePin: prefs.getBool(_requirePinKey) ?? false,
      pin: prefs.getString(_pinKey) ?? '',
      favoriteFingerprints:
          prefs.getStringList(_favoritesKey)?.toSet() ?? const {},
      profileSetupCompleted:
          prefs.getBool(_profileSetupCompletedKey) ?? savedAlias.isNotEmpty,
      avatarPreset: _safeAvatarPreset(
        prefs.getString(_avatarPresetKey) ?? 'person',
      ),
      avatarColorValue: prefs.getInt(_avatarColorKey) ?? 0xFF006A6A,
      profileImagePath: prefs.getString(_profileImagePathKey) ?? '',
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setString(_aliasKey, alias),
      prefs.setInt(_portKey, port),
      prefs.setString(_multicastKey, multicastGroup),
      prefs.setString(_destinationKey, destinationDirectory),
      prefs.setBool(_destinationCustomizedKey, destinationCustomized),
      prefs.setBool(_receiveKey, receiveEnabled),
      prefs.setBool(_encryptionKey, encryption),
      prefs.setBool(_quickSaveKey, quickSave),
      prefs.setBool(_quickSaveFavoritesKey, quickSaveFavorites),
      prefs.setBool(_overwriteKey, overwrite),
      prefs.setBool(_requirePinKey, requirePin),
      prefs.setString(_pinKey, pin),
      prefs.setStringList(_favoritesKey, favoriteFingerprints.toList()..sort()),
      prefs.setBool(_profileSetupCompletedKey, profileSetupCompleted),
      prefs.setString(_avatarPresetKey, _safeAvatarPreset(avatarPreset)),
      prefs.setInt(_avatarColorKey, avatarColorValue),
      prefs.setString(_profileImagePathKey, profileImagePath),
    ]);
  }

  QuickSendSettings copyWith({
    String? alias,
    int? port,
    String? multicastGroup,
    String? destinationDirectory,
    bool? destinationCustomized,
    bool? receiveEnabled,
    bool? encryption,
    bool? quickSave,
    bool? quickSaveFavorites,
    bool? overwrite,
    bool? requirePin,
    String? pin,
    Set<String>? favoriteFingerprints,
    bool? profileSetupCompleted,
    String? avatarPreset,
    int? avatarColorValue,
    String? profileImagePath,
  }) {
    return QuickSendSettings(
      alias: alias ?? this.alias,
      port: _safePort(port ?? this.port),
      multicastGroup: multicastGroup ?? this.multicastGroup,
      destinationDirectory: destinationDirectory ?? this.destinationDirectory,
      destinationCustomized:
          destinationCustomized ?? this.destinationCustomized,
      receiveEnabled: receiveEnabled ?? this.receiveEnabled,
      encryption: encryption ?? this.encryption,
      quickSave: quickSave ?? this.quickSave,
      quickSaveFavorites: quickSaveFavorites ?? this.quickSaveFavorites,
      overwrite: overwrite ?? this.overwrite,
      requirePin: requirePin ?? this.requirePin,
      pin: pin ?? this.pin,
      favoriteFingerprints: favoriteFingerprints ?? this.favoriteFingerprints,
      profileSetupCompleted:
          profileSetupCompleted ?? this.profileSetupCompleted,
      avatarPreset: _safeAvatarPreset(avatarPreset ?? this.avatarPreset),
      avatarColorValue: avatarColorValue ?? this.avatarColorValue,
      profileImagePath: profileImagePath ?? this.profileImagePath,
    );
  }

  bool isFavorite(String fingerprint) {
    return favoriteFingerprints.contains(fingerprint);
  }

  static String? validateAlias(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return 'empty';
    }
    if (normalized.characters.length > maxAliasCharacters) {
      return 'tooLong';
    }
    if (RegExp(r'[\x00-\x1F\x7F]').hasMatch(normalized)) {
      return 'controlCharacter';
    }
    return null;
  }

  static bool isValidAlias(String value) => validateAlias(value) == null;

  static String _safeAvatarPreset(String value) {
    return const {
          'person',
          'face',
          'pets',
          'rocket',
          'gaming',
          'spark',
        }.contains(value)
        ? value
        : 'person';
  }

  static int _safePort(int value) {
    return value >= 1024 && value <= 65535 ? value : 53317;
  }

  static String _pathKey(String value) {
    return value
        .trim()
        .replaceAll('\\', '/')
        .replaceAll(RegExp('/+'), '/')
        .replaceFirst(RegExp(r'/$'), '')
        .toLowerCase();
  }

  static const _aliasKey = 'quickSend.alias';
  static const _portKey = 'quickSend.port';
  static const _multicastKey = 'quickSend.multicastGroup';
  static const _destinationKey = 'quickSend.destinationDirectory';
  static const _destinationCustomizedKey = 'quickSend.destinationCustomized';
  static const _receiveKey = 'quickSend.receiveEnabled';
  static const _encryptionKey = 'quickSend.encryption';
  static const _quickSaveKey = 'quickSend.quickSave';
  static const _quickSaveFavoritesKey = 'quickSend.quickSaveFavorites';
  static const _overwriteKey = 'quickSend.overwrite';
  static const _requirePinKey = 'quickSend.requirePin';
  static const _pinKey = 'quickSend.pin';
  static const _favoritesKey = 'quickSend.favoriteFingerprints';
  static const _profileSetupCompletedKey = 'quickSend.profile.completed';
  static const _avatarPresetKey = 'quickSend.profile.avatarPreset';
  static const _avatarColorKey = 'quickSend.profile.avatarColor';
  static const _profileImagePathKey = 'quickSend.profile.imagePath';
}
