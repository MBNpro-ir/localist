import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localist/widgets/localist_bottom_navigation.dart';

void main() {
  final items = [
    const LocalistBottomNavigationItem(
      label: 'Quick Send',
      icon: Icons.send_outlined,
      selectedIcon: Icons.send,
    ),
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

  testWidgets('shows pill destinations and the circular action', (
    tester,
  ) async {
    await tester.pumpWidget(harness(width: 900));

    expect(find.text('Sharing'), findsOneWidget);
    expect(find.text('Receiving'), findsOneWidget);
    expect(find.text('Quick Send'), findsOneWidget);
    expect(find.byTooltip('Stats'), findsOneWidget);
  });

  testWidgets('keeps labels visible and only shows the selected icon', (
    tester,
  ) async {
    await tester.pumpWidget(harness(width: 420, selectedIndex: 1));

    expect(find.text('Sharing'), findsOneWidget);
    expect(find.text('Receiving'), findsOneWidget);
    expect(find.text('Quick Send'), findsOneWidget);
    expect(find.byIcon(Icons.share), findsOneWidget);
    expect(find.byIcon(Icons.download_outlined), findsNothing);
    expect(find.byIcon(Icons.send_outlined), findsNothing);
  });

  testWidgets('gradient overlay does not block page gestures', (tester) async {
    var taps = 0;
    final bodyKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          extendBody: true,
          body: GestureDetector(
            key: bodyKey,
            behavior: HitTestBehavior.opaque,
            onTap: () => taps++,
            child: const SizedBox.expand(child: ColoredBox(color: Colors.blue)),
          ),
          bottomNavigationBar: LocalistBottomNavigationBar(
            currentIndex: 0,
            onDestinationSelected: (_) {},
            items: items,
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byType(LocalistBottomNavigationBar)).height,
      144,
    );
    await tester.tapAt(const Offset(100, 100));
    expect(taps, 1);
  });
}
