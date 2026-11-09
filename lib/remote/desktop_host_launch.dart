/// Upstream consumes --noinstall before deciding whether to start the portable
/// SYSTEM helper. Our old --localist-host argument remained in its argument
/// list and skipped that path, even though Localist was already elevated.
const desktopHostLaunchArguments = ['--noinstall'];

bool isRetainedDesktopHostLaunch(List<String> arguments) =>
    arguments.length == 1 &&
    (arguments.single == desktopHostLaunchArguments.single ||
        arguments.single == '--localist-host');
