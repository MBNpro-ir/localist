import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart' as engine;
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:material_you_dynamic_theme/material_you_dynamic_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _themeKey = 'remote.localist.palette.v1';

Map<String, int> remoteSchemeColors(ColorScheme s) => {
  'primary': s.primary.toARGB32(),
  'onPrimary': s.onPrimary.toARGB32(),
  'primaryContainer': s.primaryContainer.toARGB32(),
  'onPrimaryContainer': s.onPrimaryContainer.toARGB32(),
  'secondary': s.secondary.toARGB32(),
  'onSecondary': s.onSecondary.toARGB32(),
  'secondaryContainer': s.secondaryContainer.toARGB32(),
  'onSecondaryContainer': s.onSecondaryContainer.toARGB32(),
  'tertiary': s.tertiary.toARGB32(),
  'onTertiary': s.onTertiary.toARGB32(),
  'tertiaryContainer': s.tertiaryContainer.toARGB32(),
  'onTertiaryContainer': s.onTertiaryContainer.toARGB32(),
  'error': s.error.toARGB32(),
  'onError': s.onError.toARGB32(),
  'errorContainer': s.errorContainer.toARGB32(),
  'onErrorContainer': s.onErrorContainer.toARGB32(),
  'surface': s.surface.toARGB32(),
  'onSurface': s.onSurface.toARGB32(),
  'onSurfaceVariant': s.onSurfaceVariant.toARGB32(),
  'outline': s.outline.toARGB32(),
  'outlineVariant': s.outlineVariant.toARGB32(),
  'inverseSurface': s.inverseSurface.toARGB32(),
  'onInverseSurface': s.onInverseSurface.toARGB32(),
  'inversePrimary': s.inversePrimary.toARGB32(),
  'surfaceTint': s.surfaceTint.toARGB32(),
  'surfaceDim': s.surfaceDim.toARGB32(),
  'surfaceBright': s.surfaceBright.toARGB32(),
  'surfaceContainerLowest': s.surfaceContainerLowest.toARGB32(),
  'surfaceContainerLow': s.surfaceContainerLow.toARGB32(),
  'surfaceContainer': s.surfaceContainer.toARGB32(),
  'surfaceContainerHigh': s.surfaceContainerHigh.toARGB32(),
  'surfaceContainerHighest': s.surfaceContainerHighest.toARGB32(),
  'primaryFixed': s.primaryFixed.toARGB32(),
  'primaryFixedDim': s.primaryFixedDim.toARGB32(),
  'onPrimaryFixed': s.onPrimaryFixed.toARGB32(),
  'onPrimaryFixedVariant': s.onPrimaryFixedVariant.toARGB32(),
  'secondaryFixed': s.secondaryFixed.toARGB32(),
  'secondaryFixedDim': s.secondaryFixedDim.toARGB32(),
  'onSecondaryFixed': s.onSecondaryFixed.toARGB32(),
  'onSecondaryFixedVariant': s.onSecondaryFixedVariant.toARGB32(),
  'tertiaryFixed': s.tertiaryFixed.toARGB32(),
  'tertiaryFixedDim': s.tertiaryFixedDim.toARGB32(),
  'onTertiaryFixed': s.onTertiaryFixed.toARGB32(),
  'onTertiaryFixedVariant': s.onTertiaryFixedVariant.toARGB32(),
  'shadow': s.shadow.toARGB32(),
  'scrim': s.scrim.toARGB32(),
  // ignore: deprecated_member_use
  'surfaceVariant': s.surfaceVariant.toARGB32(),
  // ignore: deprecated_member_use
  'background': s.background.toARGB32(),
  // ignore: deprecated_member_use
  'onBackground': s.onBackground.toARGB32(),
};

ColorScheme remoteSchemeFromColors(
  Map<String, dynamic> data,
  Brightness brightness,
) {
  Color c(String key) => Color(data[key] as int);
  return ColorScheme(
    brightness: brightness,
    primary: c('primary'),
    onPrimary: c('onPrimary'),
    primaryContainer: c('primaryContainer'),
    onPrimaryContainer: c('onPrimaryContainer'),
    secondary: c('secondary'),
    onSecondary: c('onSecondary'),
    secondaryContainer: c('secondaryContainer'),
    onSecondaryContainer: c('onSecondaryContainer'),
    tertiary: c('tertiary'),
    onTertiary: c('onTertiary'),
    tertiaryContainer: c('tertiaryContainer'),
    onTertiaryContainer: c('onTertiaryContainer'),
    error: c('error'),
    onError: c('onError'),
    errorContainer: c('errorContainer'),
    onErrorContainer: c('onErrorContainer'),
    surface: c('surface'),
    onSurface: c('onSurface'),
    onSurfaceVariant: c('onSurfaceVariant'),
    outline: c('outline'),
    outlineVariant: c('outlineVariant'),
    inverseSurface: c('inverseSurface'),
    onInverseSurface: c('onInverseSurface'),
    inversePrimary: c('inversePrimary'),
    surfaceTint: c('surfaceTint'),
    surfaceDim: c('surfaceDim'),
    surfaceBright: c('surfaceBright'),
    surfaceContainerLowest: c('surfaceContainerLowest'),
    surfaceContainerLow: c('surfaceContainerLow'),
    surfaceContainer: c('surfaceContainer'),
    surfaceContainerHigh: c('surfaceContainerHigh'),
    surfaceContainerHighest: c('surfaceContainerHighest'),
    primaryFixed: c('primaryFixed'),
    primaryFixedDim: c('primaryFixedDim'),
    onPrimaryFixed: c('onPrimaryFixed'),
    onPrimaryFixedVariant: c('onPrimaryFixedVariant'),
    secondaryFixed: c('secondaryFixed'),
    secondaryFixedDim: c('secondaryFixedDim'),
    onSecondaryFixed: c('onSecondaryFixed'),
    onSecondaryFixedVariant: c('onSecondaryFixedVariant'),
    tertiaryFixed: c('tertiaryFixed'),
    tertiaryFixedDim: c('tertiaryFixedDim'),
    onTertiaryFixed: c('onTertiaryFixed'),
    onTertiaryFixedVariant: c('onTertiaryFixedVariant'),
    shadow: c('shadow'),
    scrim: c('scrim'),
    // ignore: deprecated_member_use
    surfaceVariant: c('surfaceVariant'),
    // ignore: deprecated_member_use
    background: c('background'),
    // ignore: deprecated_member_use
    onBackground: c('onBackground'),
  );
}

/// Every engine isolate reads the same palette, including already open sessions.
class RemoteThemeSync {
  static Timer? _timer;
  static String? _read;
  static String? _written;
  static Future<void> _writes = Future.value();
  static bool _reading = false;

  static void publish(ColorScheme light, ColorScheme dark, ThemeMode mode) {
    final value = jsonEncode({
      'light': remoteSchemeColors(light),
      'dark': remoteSchemeColors(dark),
      'mode': mode.name,
    });
    if (_written == value) return;
    _written = value;
    _writes = _writes
        .then((_) async {
          await (await SharedPreferences.getInstance()).setString(
            _themeKey,
            value,
          );
        })
        .catchError((Object _) {
          _written = null;
        });
  }

  static Future<void> start() async {
    await _refresh();
    _timer ??= Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_refresh()),
    );
  }

  static Future<void> _refresh() async {
    if (_reading) return;
    _reading = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final value = prefs.getString(_themeKey);
      if (value == null || value == _read) return;
      final data = jsonDecode(value) as Map<String, dynamic>;
      final mode = ThemeMode.values.byName(data['mode'] as String);
      engine.MyTheme.applyLocalistPalette(
        remoteSchemeFromColors(
          data['light'] as Map<String, dynamic>,
          Brightness.light,
        ),
        remoteSchemeFromColors(
          data['dark'] as Map<String, dynamic>,
          Brightness.dark,
        ),
        mode,
      );
      await bind.mainSetLocalOption(key: 'theme', value: mode.name);
      engine.MyTheme.refreshLocalistTheme(mode);
      engine.updateSystemWindowTheme();
      _read = value;
    } catch (_) {
      // Startup can race IPC; retry after initialization without opening a window.
    } finally {
      _reading = false;
    }
  }
}

class LocalistRemoteThemePublisher extends StatelessWidget {
  const LocalistRemoteThemePublisher({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final colors = context.watch<BrightnessGetColorScheme>();
    final settings = context.watch<ThemeSettingsModel>();
    RemoteThemeSync.publish(colors.light, colors.dark, settings.themeMode);
    return child;
  }
}
