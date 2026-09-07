import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localist/widgets/localist_bottom_navigation.dart';
import 'package:localist/widgets/localist_windows_navigation.dart';

void main() {
  final items = [
    const LocalistBottomNavigationItem(
      label: 'Sharing',
      icon: Icons.share_outlined,
      selectedIcon: Icons.share,
    ),
    const LocalistBottomNavigationItem(
      label: 'Receiving',
      icon: Icons.download_outlined,
      selectedIcon: Icons.download,
    ),
    const LocalistBottomNavigationItem(
      label: 'Quick Send',
      icon: Icons.send_outlined,
      selectedIcon: Icons.send,
    ),
    const LocalistBottomNavigationItem(
      label: 'Settings',
      icon: Icons.tune_outlined,
      selectedIcon: Icons.tune,
    ),
  ];

  testWidgets('Windows navigation expands labels on hover', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalistWindowsNavigation(
            currentIndex: 0,
            onDestinationSelected: (_) {},
            items: items,
          ),
        ),
      ),
    );

    expect(find.text('Sharing'), findsNothing);
    expect(
      tester.getSize(find.byType(LocalistWindowsNavigation)).width,
      LocalistWindowsNavigation.collapsedWidth,
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byIcon(Icons.share)));
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 30));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpAndSettle();

    expect(find.text('Sharing'), findsOneWidget);
    expect(
      tester.getSize(find.byType(LocalistWindowsNavigation)).width,
      LocalistWindowsNavigation.expandedWidth,
    );
    await mouse.removePointer();
  });
}
