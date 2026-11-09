import 'package:flutter_test/flutter_test.dart';
import 'package:localist/remote/desktop_host_launch.dart';

void main() {
  test(
    'retained host uses upstream no-install bootstrap and keeps its hidden UI role',
    () {
      expect(desktopHostLaunchArguments, ['--noinstall']);
      expect(isRetainedDesktopHostLaunch(desktopHostLaunchArguments), true);
      expect(isRetainedDesktopHostLaunch(['--localist-host']), true);
    },
  );
  test(
    'service helpers, approval windows and sessions never take the retained-host role',
    () {
      for (final arguments in <List<String>>[
        [],
        ['--cm'],
        ['--service'],
        ['--server'],
        ['--portable-service'],
        ['--run-as-system', '--portable-service-shmem-name=fixture'],
        ['--noinstall', '--elevate'],
        ['--connect', '123456'],
        ['multi_window', '1', '{}'],
      ]) {
        expect(
          isRetainedDesktopHostLaunch(arguments),
          false,
          reason: '$arguments',
        );
      }
    },
  );
}
