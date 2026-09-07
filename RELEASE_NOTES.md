# Release Notes

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
