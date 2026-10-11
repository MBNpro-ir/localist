import 'package:flutter_test/flutter_test.dart';
import 'package:localist/services/feature_permission_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Welcome requests all three main permissions even after a denial',
    () async {
      final requested = <FeatureAccess>[];
      final granted = <FeatureAccess>{};
      final service = FeaturePermissionService.forTesting(
        (access) async => granted.contains(access),
        (access) async {
          requested.add(access);
          if (access != FeatureAccess.notifications) granted.add(access);
        },
        (_, _) async => true,
      );
      expect(await service.requestWelcome(), isFalse);
      expect(requested, [
        FeatureAccess.notifications,
        FeatureAccess.battery,
        FeatureAccess.storage,
      ]);
      expect(requested, isNot(contains(FeatureAccess.microphone)));
      expect(requested, isNot(contains(FeatureAccess.camera)));
    },
  );

  test(
    'declining the feature popup does not request or grant access',
    () async {
      var requested = false;
      final service = FeaturePermissionService.forTesting((_) async => false, (
        _,
      ) async {
        requested = true;
      }, (_, _) async => false);
      expect(await service.ensure([FeatureAccess.screenCapture]), isFalse);
      expect(requested, isFalse);
    },
  );

  test('a denied system request keeps the pending feature blocked', () async {
    final popups = <bool>[];
    final service = FeaturePermissionService.forTesting(
      (_) async => false,
      (_) async {},
      (_, settings) async {
        popups.add(settings);
        return !settings;
      },
    );
    var operationCount = 0;
    if (await service.ensure([FeatureAccess.camera])) operationCount++;
    expect(operationCount, 0);
    expect(popups, [false, true]);
  });

  test(
    'grants resume the operation and revocations are checked again',
    () async {
      var granted = false;
      var requests = 0;
      var operationCount = 0;
      final service = FeaturePermissionService.forTesting(
        (_) async => granted,
        (_) async {
          granted = true;
          requests++;
        },
        (_, _) async => true,
      );
      if (await service.ensure([FeatureAccess.camera])) operationCount++;
      if (await service.ensure([FeatureAccess.camera])) operationCount++;
      expect(requests, 1);
      granted = false;
      if (await service.ensure([FeatureAccess.camera])) operationCount++;
      expect(requests, 2);
      expect(operationCount, 3);
    },
  );

  test(
    'concurrent features serialize prompts and reuse existing grants',
    () async {
      final granted = <FeatureAccess>{};
      final requested = <FeatureAccess>[];
      var active = 0, maximum = 0;
      final service = FeaturePermissionService.forTesting(
        (a) async => granted.contains(a),
        (a) async {
          active++;
          if (active > maximum) maximum = active;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          granted.add(a);
          requested.add(a);
          active--;
        },
        (_, _) async => true,
      );
      expect(
        await Future.wait([
          service.ensure([FeatureAccess.camera]),
          service.ensure([FeatureAccess.camera]),
          service.ensure([FeatureAccess.microphone]),
        ]),
        [true, true, true],
      );
      expect(maximum, 1);
      expect(requested, [FeatureAccess.camera, FeatureAccess.microphone]);
    },
  );
}
