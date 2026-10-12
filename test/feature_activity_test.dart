import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localist/l10n/app_localizations.dart';
import 'package:localist/screens/vpn_sharing_page.dart';
import 'package:localist/services/feature_activity_service.dart';
import 'package:localist/services/lan_network_service.dart';

void main() {
  test(
    'active operations exclude other features and last operation unlocks',
    () {
      final service = FeatureActivityService();
      expect(service.owner, isNull);
      expect(service.reserve('send', LocalistFeature.quickSend), isTrue);
      expect(service.reserve('web', LocalistFeature.quickSend), isTrue);
      expect(service.reserve('vpn', LocalistFeature.vpnSharing), isFalse);
      service.setActive('send', LocalistFeature.quickSend, false);
      expect(service.owner, LocalistFeature.quickSend);
      service.setActive('web', LocalistFeature.quickSend, false);
      expect(service.reserve('vpn', LocalistFeature.vpnSharing), isTrue);
      service.setActive('vpn', LocalistFeature.vpnSharing, false);
      expect(service.owner, isNull);
      service.dispose();
    },
  );
  test('broadcast uses prefix length for LAN and USB networks', () {
    expect(ipv4Broadcast('192.168.2.7', 23), '192.168.3.255');
    expect(ipv4Broadcast('172.20.10.2', 28), '172.20.10.15');
    expect(ipv4Broadcast('10.15.9.8', 16), '10.15.255.255');
    expect(ipv4Broadcast('192.168.1.1', 32), isNull);
    expect(ipv4Broadcast('192.168.999.1', 24), isNull);
    expect(isPhysicalLan('rndis0'), isTrue);
    expect(isPhysicalLan('eth0'), isTrue);
    expect(isPhysicalLan('wlan0'), isTrue);
    expect(isPhysicalLan('rmnet_data0'), isFalse);
    expect(isPhysicalLan('tun0'), isFalse);
  });
  testWidgets('VPN modes hide opposite service, including narrow Persian UI', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Widget page(bool sharing, bool receiving) => MaterialApp(
      locale: const Locale('fa'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('fa'), Locale('en')],
      home: Scaffold(
        body: VpnSharingPage(
          sharingActive: sharing,
          receivingActive: receiving,
          sharing: const Text('share-content'),
          receiving: const Text('receive-content'),
        ),
      ),
    );
    await tester.pumpWidget(page(false, false));
    expect(find.text('share-content'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.download_outlined));
    await tester.pumpAndSettle();
    expect(find.text('receive-content'), findsOneWidget);
    await tester.pumpWidget(page(true, false));
    expect(find.text('share-content'), findsOneWidget);
    expect(find.text('receive-content'), findsNothing);
    expect(find.byType(SegmentedButton<bool>), findsNothing);
    await tester.pumpWidget(page(false, true));
    expect(find.text('share-content'), findsNothing);
    expect(find.text('receive-content'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
