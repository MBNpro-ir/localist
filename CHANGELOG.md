# Changelog

All notable user-facing changes are documented here. Version numbers follow [Semantic Versioning](https://semver.org/).

## [6.0.8] - 2026-10-12

- Fixed Remote Control host recovery: a live RustDesk engine is no longer
  terminated when its Flutter heartbeat is briefly delayed while a session or
  child window is busy. Native checks now verify the executable path, creation
  time, user and session before adopting or retiring a host.
- Kept the embedded Remote Control session alive through slow window startup,
  extended session-open timeouts, and removed automatic replay of session
  commands that could create duplicate connections.
- Registered the file-drop plugin in child Flutter windows so Quick Send and
  remote file-manager drag and drop continue to work in the embedded engine.
- Removed the duplicate This device heading from Remote Control and added the
  Connect heading for the destination card.
- Increased the version to 6.0.8+70.

See [validation](docs/VALIDATION_6.0.8.md) for live localist, Android emulator
and official RustDesk interoperability evidence.

## [6.0.7] - 2026-10-12

- Fixed settings IPC startup when an old LocalistRemote process remains after a crash or a different build's launch. Retained hosts require bundle identity, a fresh heartbeat and authenticated readiness; guarded cleanup preserves active sessions and unrelated processes.
- Added multi-file Stream selection and a responsive web gallery with lazy image/video previews, individual players, previous/next navigation and per-item HTTP ranges.
- Kept shared addresses as IP:port and added a separate item selector for DLNA casting.

See [validation](docs/VALIDATION_6.0.7.md) for local IPC recovery, native guard and browser playback evidence.

## [6.0.0] - 2026-10-11

- Added Localist light/dark palette synchronization to embedded desktop, mobile, file-transfer, camera, tunnel, terminal and approval windows.
- Expanded Welcome to cover runtime and special access used by file transfer, hotspots, QR/camera, audio, VPN, remote hosting/input, updates and optional elevated/root routing.
- Removed the remote engine/profile chooser, standalone settings and Apply workflow; server/text options save automatically.
- Preserved the supplied ID and relay server with an empty API field. Confirmed actual official-client and Localist protocol interoperability, independently of the optional HTTP API.
- Fixed Windows named-pipe authentication for the identical, same-directory Localist/LocalistRemote executable pair while retaining caller user/session and service-channel checks.
- Encoded URI passwords and removed native URI logging.
- Published completed Android engine uploads to unique Download/Localist folders and included them in received history without relaxing peer path validation.
- Added responsive Stream/Remote layouts, browser media controls, device metadata, thumbnails, web peer relaying, corrected progress and batch sounds from the development builds.
- Packaged corresponding source, native dependencies and checksums; added analyzer/tests to the release workflow.

See [validation](docs/VALIDATION_6.0.0.md) for live interoperability evidence and platform limits.

## [5.0.10] - 2026-10-10 (development)

- Embedded the RustDesk 1.5.0 native engine, generated bridge and full session UI; Android packages its capture, input, audio, clipboard and boot services for three ABIs.
- Remote Control and its Localist Settings section are available in Debug and Release. Removed the installed-client fallback and Android companion requirement.
- Windows uses the bundled Localist runner for sessions, command dispatch and connection manager, with its own configuration and IPC namespace.
- Added corresponding native source, build tools, runtime/APK checksum verification and retained third-party license notices.
- Preserved compatible official-client protocols, supplied relay defaults and large text-labelled server import/export controls. Platform permissions, drivers and server capabilities still govern feature availability.
- Added a formatted self-ID/password card with individual copy actions, an
  encoded connection payload and explicit Paste & connect parsing.

See [validation](docs/VALIDATION_5.0.10.md) for the tested scope.

## [5.0.9] - 2026-10-10 (development)

- Fixed Windows sign-in launch: absolute Flutter assets, normal-user manifest, quoted startup command, silent duplicate startup, clean shutdown marker and elevation handoff.
- Added named web peers, browser-to-browser and browser-to-app relaying, private inboxes, raw streamed uploads and receipt-confirmed downloads.
- Corrected transfer progress, byte/time/rate accounting, partial-file commits and receive-session cleanup; received sounds fire once per successful batch.
- Added Stream with HTTP range playback, QR/URLs, DLNA AVTransport controls and OS screen-mirroring settings. Receiver codecs/hardware still determine compatibility; AirPlay/Chromecast/transcoding remain unimplemented.
- Redesigned received history with gallery/video thumbnails, categories, search, date/status filters and sorting. Android saves to Download/Localist/category/file-name by default.
- Android navigation shows inactive icons and the selected label; Windows chrome uses opaque colors for older graphics systems.
- Added a Windows hosted-network fallback subject to adapter/driver AP support.
- Added debug-only RustDesk companion entry points and selected engine options. Full embedded RustDesk functionality is still pending; see docs/RUSTDESK_INTEGRATION.md.

## [5.0.8] - 2026-09-07

### Notifications and background receiving

- Removed the Flutter post-frame dependency from incoming request alerts, so system notifications are dispatched immediately while Localist is backgrounded.
- Android now holds the CPU, high-performance Wi-Fi, and multicast resources required by Quick Send while its foreground receiver remains in Recents.
- Android stops the Quick Send foreground receiver when the user removes Localist from Recents.
- Added separate high-importance Android request channels with an optional bundled notification sound and unique notification IDs.
- Registered the Windows process AUMID explicitly before notification initialization, while retaining taskbar flashing as a fallback for restricted desktop toast environments.

### Sounds, startup, profile, and polish

- Added subtle CC0 Kenney sounds for incoming requests, acceptance, cancellation, completed transfers, and failed transfers.
- Added a default-on App sound effects option under App behavior.
- Added a first-run Windows prompt for launch-at-sign-in and a persistent Start with Windows toggle backed by the current-user Run registry entry.
- Made the device avatar on Quick Send open its profile, avatar, image, and color settings.
- Changed mobile bottom navigation so the active icon and label transition as one visual unit, while all three labels remain visible.
- Requested the small Windows 11 corner style for a lightly rounded native window.

### Validation

- Added preference persistence coverage for startup and sound choices.
- Passed Flutter static analysis, all unit/widget/integration tests, Android debug compilation, and Windows native debug compilation.

**Full Changelog:** [v5.0.7...v5.0.8](https://github.com/MBNpro-ir/localist/compare/v5.0.7...v5.0.8)

## [5.0.7] - 2026-09-07

### Highlights

- Quick Send is now the first screen on Android and Windows, with Sharing and Receiving following it in the primary navigation.
- Added a first-run Quick Send identity setup with a prefilled device name, editable emoji-aware validation, six dynamically colored Material avatars, and an optional local profile photo.
- Reorganized Settings into a clear overview and separate Quick Send, network/proxy, appearance/language, app-behavior, updates/about, and profile experiences.

### Incoming requests and background reliability

- Replaced the inline manual incoming-request card with an Accept/Decline popup that appears over the active app regardless of the current page.
- Quick Save continues to accept trusted file requests automatically. When the user is outside Quick Send, an unobtrusive in-app notice reports the accepted receive instead of showing the manual popup.
- Added a connected-device foreground service so Android keeps the Quick Send receiver available during normal background use instead of allowing the sender to fail merely because Localist is behind another app.
- Added Android and Windows system notifications for requests that arrive while Localist is not foregrounded. Selecting a notification opens Quick Send, brings the Windows window forward when applicable, and navigates to the pending receive.
- Preserved the Windows taskbar-attention fallback for elevated processes that cannot publish a normal desktop toast.
- Added Android 17 local-network permission handling and the required connected-device foreground-service declarations.

### Transfers and history

- Added a dedicated **Transfer history** page for received files with concise completed, failed, active, and byte totals.
- History rows show sender, timestamp, destination path, status, progress, availability, and a useful failure summary.
- Added per-file **Share** and **Open** actions while keeping a single global **Open received folder** action for the complete destination.
- Persisted up to 250 received-file history entries in platform app data and merged active receives into the same view.
- Added confirmed history clearing that removes history metadata without deleting downloaded files.
- Added **Clear** beside the live Transfers section and moved **Send to iPhone or Mac** to the bottom of Quick Send.

### Navigation, motion, and visual design

- Redesigned the three-item Android bottom navigation so every label remains visible and only the selected destination displays its icon.
- Added smoother, slightly slower navigation and theme/color transitions while honoring the operating system's disabled-animation accessibility setting.
- Refined Material 3 cards, dialogs, controls, and responsive spacing with rounder surfaces for current Android and Windows layouts.
- Stabilized the Windows hover rail so opening and closing its labels does not resize, overflow, or reflow page content.
- Preserved the user's/system's initial Windows size and enforced only a practical minimum size to prevent unusable layouts.

### Profile and settings

- Removed the Android device-name lock. Device names can now be edited safely on all supported platforms, include emoji, and are limited to 32 user-perceived characters with control characters rejected.
- Added profile editing to Settings, including avatar preset, dynamic avatar color, and local photo replacement/removal.
- Included bounded profile identity data in Quick Send discovery and request metadata without placing photo data in UDP announcements.
- Kept valid Quick Send settings automatically saved and retained guarded exit behavior that warns about invalid drafts before restoring the last valid values.

### Android build and compatibility

- Raised `compileSdk` and `targetSdk` to Android API 37.
- Updated Android Gradle Plugin to 9.2.1 and Gradle to 9.4.1 while retaining Flutter's documented legacy Kotlin compatibility bridge until all plugins support built-in Kotlin.
- Updated `file_picker` to 12.2.0 and migrated selection calls to its current API.
- Updated the release workflow to Flutter 3.47.2 and the package SDK floor to Dart 3.12.

### Testing and documentation

- Added regression tests for navigation order/animation behavior, profile persistence and validation, bounded remote avatars, and transfer-history serialization.
- Re-ran formatting, static analysis, all Flutter tests, and an isolated Android AGP 9 compile using clean Gradle state and repository mirrors.
- Updated the English and Persian guides for the new default page, identity setup, request behavior, background notifications, transfer history, Settings organization, permissions, and current release toolchain.

**Full Changelog:** [v5.0.0...v5.0.7](https://github.com/MBNpro-ir/localist/compare/v5.0.0...v5.0.7)

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

[5.0.7]: https://github.com/MBNpro-ir/localist/compare/v5.0.0...v5.0.7
[5.0.0]: https://github.com/MBNpro-ir/localist/compare/v4.1.5...v5.0.0
## [5.0.11] - 2026-10-11

- Integrated remote hosting into Localist startup with automatic profile application.
- Removed the standalone remote settings/profile window and engine chooser.
- Improved Stream web-player discoverability and Windows host/runtime packaging.

