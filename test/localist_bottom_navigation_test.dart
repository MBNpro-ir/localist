import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localist/widgets/localist_bottom_navigation.dart';

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

  Widget harness({required double width, int selectedIndex = 0}) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: width,
          child: LocalistBottomNavigationBar(
            currentIndex: selectedIndex,
            onDestinationSelected: (_) {},
            items: items,
            showActionButton: true,
            actionTooltip: 'Stats',
            onActionPressed: () {},
          ),
        ),
      ),
    );
  }

  testWidgets('shows transparent destinations and the action', (tester) async {
    await tester.pumpWidget(harness(width: 900));

    expect(find.text('Sharing'), findsOneWidget);
    expect(find.text('Receiving'), findsOneWidget);
    expect(find.text('Quick Send'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.byTooltip('Stats'), findsOneWidget);
  });

  testWidgets('uses icon-only inactive destinations in compact mode', (
    tester,
  ) async {
    await tester.pumpWidget(harness(width: 420, selectedIndex: 1));

    expect(find.text('Receiving'), findsOneWidget);
    expect(find.text('Sharing'), findsNothing);
    expect(find.text('Quick Send'), findsNothing);
    expect(find.text('Settings'), findsNothing);
  });
}
