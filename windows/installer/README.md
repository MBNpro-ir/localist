# Persian Windows Setup

`tools/Build-WindowsSetup.ps1` packages the exact Windows Release bundle in a
single x64 installer. Production Setup, removal, Localist and its remote helper
now request administrator access. The retained install path and user data remain
per-user. QA fixtures keep their separate unelevated manifest. The WPF shell uses bundled Vazirmatn, Persian RTL,
native rounded window clipping, app-specific colors, entrance/hover/progress
animations and a lighter path when Windows disables animations or GPU rendering.
The install core is pinned Inno Setup 7.1.0, verified by SHA-256 and Authenticode
when downloaded. No additional runtime or internet is required during install on
standard Windows 10/11 with .NET Framework 4.8.

Existing installation discovery uses the app's stable uninstall entry, App Paths,
or a running copy. Users can select another existing folder. The shell identifies
update/repair/newer versions and waits for the app's normal full exit so its final
sync is retained. The core rejects downgrades independently. Accounts, downloads
and settings are not deleted. Inno manages uninstall registration and shortcuts;
uninstallation removes installed files and preserves unrelated user files.

Existing enabled Run entries migrate to a per-user interactive logon task with
RunLevel Highest, a ten-second delay, no battery/network requirement, and no
execution time limit. This uses normal Task Scheduler authorization, stores no
password and does not change UAC policy. The app's startup switch registers or
removes the same task. Sign-in does not need a second UAC prompt after setup;
manual launches still follow Windows UAC policy. Uninstall removes only this
installation's task and virtual camera registration. The camera's x86/x64 DLLs
carry a version in their names so other camera consumers cannot lock updates.

Windows releases contain only `*-Windows-Setup-x64-<version>.exe` plus its
SHA-256 file. The app updater downloads and verifies this Setup, waits for the
confirmed application exit, then invokes its maintenance mode in the existing
installation directory. Setup registers the selected x86/x64 virtual cameras
before reporting success. Removal unregisters only this installation's cameras.
Older ZIP-only updaters require one manual Setup upgrade to migrate.
Setup now asks for independent camera and microphone counts (1–4). It installs
only the selected camera registrations and stores counts in capture-devices.ini;
silent updates retain those values. Microphone output uses the official base
VB-CABLE package, verified by `Verify-VbCablePackage.ps1` against pinned hashes
and Microsoft kernel-policy catalog membership. A/B/C/D packages are not bundled:
users selecting multiple microphones supply their licensed extracted packages,
or use already installed independent cables. The app never installs devices.
Shared VB-CABLE drivers remain installed when Localist is removed.
`-Qa` only bypasses machine-wide integration for isolated installer fixtures.
See `docs/WINDOWS_VB_CABLE.md` for routing, licensing and validation limits.
These executables are not Authenticode-signed unless a signing stage is supplied;
the checksum verifies file integrity and does not establish a trusted publisher.

Run `tools/Test-WindowsSetup.ps1` for isolated real install, upgrade, repair,
downgrade rejection and uninstall checks with a small fixture and Persian paths.
The test also checks bundled fonts, RTL, brand colors and the native window
region. It uses a separate `InstallerQA` identity and leaves evidence under
`build/windows-setup-test-*`; it refuses to modify an existing QA registration.

`Build-WindowsSetup.ps1 -Qa` produces a separate QA executable supporting
`--preview` (animated simulation; does not install), `--verify-ui`,
`--verify-install` (real isolated fixture installation), and `--path`.
Production builds ignore these QA arguments. Never publish a QA executable or a
local bundle containing unrelated diagnostics as a release.

The installed `MBNUninstall.exe` uses the same WPF layout, embedded Vazirmatn,
product colors, motion and native rounded window as Setup. Windows Settings
opens this UI. Opening Inno's `unins000.exe` interactively redirects to it too;
the silent Inno core remains responsible for its installation manifest.
Removal runs its UI from a temporary copy so installed files are not locked.
It waits for the app to exit normally and preserves account/settings and
user-owned files. Directories are never recursively wiped by the UI.

Progress text and percentage have separate reserved columns. The UI check
measures 0%, 7%, 88% and 100% at normal and compact window sizes. Lifecycle
tests also exercise branded removal and reject an unrelated uninstall core.

Adapted locally from MBNapp.ir/MBNime for PRS.Localist.Windows. No CI dispatch or publishing is performed by the build script.
