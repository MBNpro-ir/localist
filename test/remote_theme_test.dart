import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/common.dart' as remote;
import 'package:get/get.dart';
import 'package:localist/remote/remote_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'remote sessions retain the Localist palette in both brightness modes',
    () {
      final light = ColorScheme.fromSeed(seedColor: Colors.teal);
      final dark = ColorScheme.fromSeed(
        seedColor: Colors.teal,
        brightness: Brightness.dark,
      );
      for (final scheme in [light, dark]) {
        final restored = remoteSchemeFromColors(
          remoteSchemeColors(scheme),
          scheme.brightness,
        );
        expect(restored.primary, scheme.primary);
        expect(restored.onPrimary, scheme.onPrimary);
        expect(
          restored.surfaceContainerHighest,
          scheme.surfaceContainerHighest,
        );
        remote.MyTheme.applyLocalistPalette(
          light,
          dark,
          scheme.brightness == Brightness.light
              ? ThemeMode.light
              : ThemeMode.dark,
        );
        final theme = scheme.brightness == Brightness.light
            ? remote.MyTheme.lightTheme
            : remote.MyTheme.darkTheme;
        expect(theme.colorScheme, restored);
        expect(theme.scaffoldBackgroundColor, scheme.surface);
        expect(remote.MyTheme.accent, scheme.primary);
        expect(remote.MyTheme.onAccent, scheme.onPrimary);
        expect(theme.iconTheme.color, scheme.onSurface);
        expect(theme.textSelectionTheme.cursorColor, scheme.primary);
        expect(theme.sliderTheme.thumbColor, scheme.primary);
        expect(remote.MyTheme.overlaySurface, scheme.inverseSurface);
        expect(remote.MyTheme.onOverlaySurface, scheme.onInverseSurface);
      }
    },
  );
  testWidgets('an open remote window refreshes both brightness palettes', (
    tester,
  ) async {
    final oldLight = ColorScheme.fromSeed(seedColor: Colors.teal);
    final oldDark = ColorScheme.fromSeed(
      seedColor: Colors.teal,
      brightness: Brightness.dark,
    );
    remote.MyTheme.applyLocalistPalette(oldLight, oldDark, ThemeMode.light);
    ColorScheme? rendered;
    await tester.pumpWidget(
      GetMaterialApp(
        theme: remote.MyTheme.lightTheme,
        darkTheme: remote.MyTheme.darkTheme,
        themeMode: ThemeMode.light,
        home: Builder(
          builder: (context) {
            rendered = Theme.of(context).colorScheme;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    final light = ColorScheme.fromSeed(seedColor: Colors.purple);
    final dark = ColorScheme.fromSeed(
      seedColor: Colors.purple,
      brightness: Brightness.dark,
    );
    remote.MyTheme.applyLocalistPalette(light, dark, ThemeMode.light);
    remote.MyTheme.refreshLocalistTheme(ThemeMode.light);
    await tester.pumpAndSettle();
    expect(rendered, light);
    Get.changeThemeMode(ThemeMode.dark);
    await tester.pumpAndSettle();
    expect(rendered, dark);
    await tester.pumpWidget(const SizedBox.shrink());
    Get.reset();
  });
}
