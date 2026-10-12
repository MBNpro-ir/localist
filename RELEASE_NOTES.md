# Release Notes

## [6.0.4] — Stable desktop session dispatch and compact device views

Windows opens remote sessions through the retained hidden engine host instead of
starting another native command process per connection. Session close/show,
reused tabs, detached tabs and additional monitors retain the upstream window
callbacks without displaying the standalone home page. Connection requests are
serialized and are never automatically replayed after a failed dispatch.

The address book now uses the full desktop width. Choose Compact, Cards or List;
the preference is saved, columns respond to available width and text size, and
pages contain at most 12 devices. Search and filters reset pagination. Names,
tags, favorites and direct click-to-connect remain available.

Saved and recent devices display native online/offline responses, refreshed
while connected to the selected server. Missing, expired or failed responses are
shown as unknown. Fresh LAN discovery is shown separately. Old spaced IDs are
normalized without merging different device IDs. See
[validation and device acceptance limits](docs/VALIDATION_6.0.4.md).

## [6.0.3] — Android permissions and remote hosting fixes

Android Settings now has a Permissions page with separate screen capture, input,
file transfer, audio, clipboard and camera controls, plus system access status.
Welcome requests notifications, background activity and storage together; other
access remains optional and is requested with guidance when a feature needs it.
Restricted Accessibility instructions cover APKs installed from GitHub.

The Android host listens for incoming connections before screen capture is
enabled. Localist provides Accept, Decline and one-time-password sharing, checks
the required access before approval, restores native events after returning from
a session, and returns to the existing app when the final session closes.

Private server settings automatically enable relay. Clearing them selects public
servers. Windows retries settings IPC on the existing bridge, repairs disabled
startup approval when startup is enabled, and requests VPN elevation through a
scoped worker without restarting the main app. See [validation and remaining
device checks](docs/VALIDATION_6.0.3.md).

## [6.0.2] — Remote Control startup and attribution fix

Remote Control now shows the requested `Powered by RustDesk` attribution above
its workspace. Its Windows FFI/RPC bridge keeps one RustdeskPlatform instance
for the lifetime of the process; a failed partial initialization is never
retried by constructing a second bridge, removing the singleton RPC error that
left the page stuck at “Starting”.

## [6.0.1] — automatic updates and remote connection fixes

Updates now download and verify automatically, show real progress, and prepare the Windows bundle before asking to restart. The updater backs up the installed bundle, restores it after a failed copy and preserves unrelated files. Android uses the system installer and its required consent. Update notifications open the Updates page directly.

Remote Control automatically selects relay when private-server settings are populated. Temporary engine passwords are the default; incoming connections support password or manual approval. Mouse-button swapping is off by default, and copying an ID, password or connection shows an in-app confirmation. Windows printer settings enumerate actual installed printers.

The local Address Book supports names, tags, favorites, search, filters and sorting. Device cards connect directly, LAN discovery excludes the current device, and an animated status reflects engine registration and the selected server. Remote preferences adapt to wider Windows layouts with icon navigation.

Launching Localist again restores the existing window without an “already running” dialog. Forced closure, crashes and Debug builds no longer enable the user’s Debug logging preference automatically. See [validation and remaining device checks](docs/VALIDATION_6.0.1.md).

## [6.0.0] — Localist remote, stream and web sharing

Remote Control packages its native engine and session interface on Windows and Android. Settings apply inside Localist, the ID/relay defaults use the supplied server with an empty API field, and sessions interoperate with compatible official clients. Separate client installation is unnecessary.

Embedded sessions now follow Localist's colors and light/dark mode. Welcome includes the app's feature permissions, with explicit optional elevation/root controls and Android's per-session capture consent. Stream exposes its local Web player alongside network playback. Received history includes media previews, categories, search and sorting; completed Android remote uploads are also published to Download/Localist.

Windows startup, cross-process engine access, transfer progress and receive-batch sounds are corrected. Windows uses software codecs; receiver formats, drivers and OS permissions still determine feature support. See [validation and device-test limits](docs/VALIDATION_6.0.0.md).

## [5.0.10] — embedded Remote Control

Remote Control now includes its native engine and full session interface on Windows and Android, with no separate client installation. It is visible in Debug and Release; full preferences open through Localist Settings. Android includes all three native ABIs and capture/input/audio/clipboard services. Windows uses an isolated Localist engine identity.

Corresponding source, licenses and build/verification tools are included. This build has not been published. See [validation and device-test limits](docs/VALIDATION_5.0.10.md).

The identity card now formats the local ID and offers separate Copy ID, Copy
password and Copy connection actions. On the destination, Paste & connect
validates the payload, fills both fields and starts the requested session;
passwords are kept out of profile settings.

## [5.0.9] — local debug build

Adds multi-device web transfers, a gallery/history redesign, Stream with local browser/DLNA playback, Android Downloads storage and selected-label navigation. Fixes Windows startup, progress accounting and repeated receive sounds. Remote launches the official RustDesk companion and is visible only in debug builds; the complete embedded port is not finished. TV codecs, Miracast and hosted Wi-Fi need compatible hardware and real-device validation.

This build has not been published as a GitHub Release. See [validation and manual test checklist](docs/VALIDATION_5.0.9.md).

## [5.0.8]
✨ Makes background Quick Send alerts reliable, adds subtle event sounds, and completes the device-profile experience.

## ✨ Highlights

- 🔔 Delivers incoming Android and Windows notifications immediately while Localist is behind other apps or minimized, without waiting for a new Flutter frame.
- 📡 Keeps Android Quick Send receiving active while Localist remains in Recents and stops it when the task is swiped away.
- 🔊 Adds default-on CC0 sound effects for requests, acceptance, cancellation, completion, and failure, with a Settings toggle.
- 🚀 Adds a first-run Windows startup choice and a matching App behavior setting.
- 👤 Opens profile and avatar customization directly when the user selects their Quick Send avatar.
- 🧭 Animates each mobile navigation label and selected icon as one unit.
- 🪟 Registers the Windows notification identity explicitly, retains taskbar attention fallback, and requests subtly rounded Windows 11 corners.

## 📦 Assets

- 🤖 Android 32-bit APK.
- 🤖 Android 64-bit APK.
- 🪟 Windows 64-bit ZIP package.

## [5.0.7]
✨ Evolves Quick Send into a profile-driven, background-ready transfer workspace with a complete received-file history.

## ✨ Highlights

- 🚀 Opens Quick Send first and adds a guided first-run device profile with a validated custom name, colorful Material avatars, or a personal photo.
- 🔔 Keeps Android receiving available during normal background use and delivers Android or Windows system notifications when Localist is behind other apps; opening a notification brings the pending request into view.
- 📥 Replaces passive incoming-request cards with a focused Accept/Decline popup, while trusted Quick Save receives remain automatic and report their arrival without interrupting the user.
- 🗂 Adds a dedicated Transfer history with received-file status, sender, date, size, errors, per-file Share/Open actions, one Open folder action, and safe history clearing.
- 🧹 Adds Clear beside live Transfers and moves the Apple browser-transfer card to the end of Quick Send.
- 🧭 Refines the three-button Android navigation with persistent labels, a selected icon, smoother motion, and accessibility-aware animation behavior.
- ⚙️ Reorganizes Settings into focused profile, Quick Send, network, appearance, behavior, and update pages with validated automatic saving.
- 🎨 Refreshes responsive Android and Windows layouts with rounder Material 3 surfaces, animated theme/color changes, stable Windows hover navigation, and a practical minimum window size.
- 🤖 Updates the Android project for API 37, AGP 9.2.1, Gradle 9.4.1, and current file-picker integration.

## 📦 Assets

- 🤖 Android 32-bit APK.
- 🤖 Android 64-bit APK.
- 🪟 Windows 64-bit ZIP package.

## [5.0.0]
✨ Reimagines Localist with a polished Windows workspace, unified navigation, and simpler Quick Send settings.

## ✨ Highlights

- 🪟 Adds a Flutter-rendered Windows title bar, native window controls, and a hover navigation rail that keeps every page stable.
- 🧭 Unifies Android navigation with a transparent, app-colored bottom treatment that preserves scrolling and touch interaction.
- 📤 Brings Quick Send status, connection addresses, receiving options, storage, and security controls together inside Settings.
- ✅ Saves valid Quick Send changes automatically and safely restores the last valid values when invalid input is discarded.
- 🔔 Shows incoming Quick Send requests outside the page through in-app, Android, and Windows notifications.
- 🔒 Repairs Windows update checks and downloads on certificate-store-sensitive systems by retrying GitHub requests through Windows `curl.exe`.

## 📦 Assets

- 🤖 Android 32-bit APK.
- 🤖 Android 64-bit APK.
- 🪟 Windows 64-bit ZIP package.
