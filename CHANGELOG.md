# Changelog

All notable user-facing changes are documented here. Version numbers follow [Semantic Versioning](https://semver.org/).

## [5.0.0] - 2026-09-07

### Highlights

- Rebuilt the Windows desktop experience around a Flutter-drawn title bar, native Windows window controls, and a modern left navigation rail that reveals labels on hover without reflowing the page.
- Unified the Android navigation and visual treatment across supported Android versions while preserving page interaction behind the transparent bottom navigation treatment.
- Consolidated Quick Send configuration and status into the main Settings experience.

### Quick Send

- Moved the Quick Send connection-status card and manual connection addresses into Settings, alongside all receiving, network, storage, and security options.
- Replaced the separate Quick Send settings route with a single, organized Settings page.
- Valid Quick Send changes now save automatically. Invalid device name, port, multicast address, destination, or required PIN values are highlighted and are restored to the last valid saved state if the user chooses to leave or close the app.
- Added incoming-request awareness outside the Quick Send page: in-app notice when active, Android notifications, and Windows 10/11 notifications with a taskbar fallback for elevated Windows processes. Activating a notification brings Localist forward and opens the pending request.
- Kept the Quick Send page focused on sending and receiving while retaining the connection overview in Settings.

### Windows desktop

- Added a Flutter-rendered, draggable Windows title bar with minimize, maximize/restore, close, and back controls while Windows continues to own the native window itself.
- Corrected the Settings title-bar alignment and added guarded back/close behavior for unsaved invalid Quick Send values.
- Replaced the desktop navigation layout with an icon rail that expands on hover, animates labels, avoids RenderFlex overflow, and overlays content instead of resizing every page.
- Kept the system-selected initial window size; set a consistent minimum usable size of 920 × 620 in both Flutter and the native runner.

### Navigation and visual polish

- Removed the opaque bottom-navigation background in favor of a subtle, app-colored bottom gradient that lets content continue beneath it.
- Restored the intended navigation-button colors, shapes, and animations, and ensured the visual gradient never blocks taps or scrolling.
- Added responsive content sizing so Settings and other page surfaces remain usable across Windows widths.

### Updates and reliability

- Repaired the Windows update checker and downloader for systems whose Dart TLS trust store cannot validate GitHub certificates. Localist retries through `curl.exe` and the Windows certificate store only for certificate-verification failures.
- Added focused regression coverage for update fallback detection, mobile navigation gesture behavior, Windows hover navigation, and Quick Send status rendering.

### Documentation and release process

- Updated the English and Persian READMEs for the v5 desktop navigation, unified Settings, Quick Send notifications, and auto-save behavior.
- The release workflow now fails safely when the target version has no changelog entry and publishes the matching changelog section as the GitHub Release notes.

**Full Changelog:** [v4.1.5...v5.0.0](https://github.com/MBNpro-ir/localist/compare/v4.1.5...v5.0.0)

[5.0.0]: https://github.com/MBNpro-ir/localist/compare/v4.1.5...v5.0.0
