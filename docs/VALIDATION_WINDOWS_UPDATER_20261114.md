# Windows updater and device migration — 2026-11-14

Baseline: `164e54b`, Localist 7.3.1+2078. Local fixes and repair Setup only;
no push, Action, public release, website deployment or production installation.

## Findings

- Older ZIP-only clients discard EXE assets. The live public `v7.3.1` release
  contains Android APKs and Windows Setup, with no Windows ZIP. Such clients
  cannot migrate through their old updater and require one manual Setup upgrade.
  The exact version of the user's failing executable was not supplied.
- Current-source code successfully selected the live Windows Setup independently
  of Android ABIs, downloaded all 59,591,680 bytes, verified its release SHA-256
  and staged it. No downloaded public installer was executed.
- A deleted prepared download remained non-null in the controller and prevented
  another download. The controller now clears missing package/staging references.
- The real Inno post-install handoff passed literal
  `{param:CameraCount|0}` / `{param:MicrophoneCount|0}` strings instead of values.
  This was observed in the isolated executable's captured arguments. The command
  now uses `ExpandConstant`; selected counts and a quoted package path containing
  spaces reach the installed integration process correctly.

## Changes

- Use shared, anchored versioned x64 Setup-name validation for release selection
  and staging, including version-first naming. Portable ZIPs and unrelated EXEs
  remain excluded from Windows release selection.
- Show a specific missing-Setup message and the official release link, log the
  release/package mismatch, and support retry after assets become available.
- Redownload a missing prepared package; preserve hash/size validation.
- Preserve installation-owned `capture-devices.ini`: never package a build-tree
  copy. Silent maintenance explicitly retains device counts. If the file is
  missing, detect this installation's registered camera slots and available
  signed-vendor cable devices instead of resetting to one.
- Check device-configuration writes for failure. Keep shared VB-CABLE drivers;
  existing vendor devices are not reinstalled or removed by an update.
- Keep previous versioned camera modules available during registration migration
  and the existing registration rollback path.
- If a non-elevated updater receives Windows error 740, request normal UAC consent
  for Setup. Do not terminate Setup on a fixed timeout during device registration;
  wait for completion before restarting the application.
- Ordinary QA builds still skip integration. A separate explicit
  `-QaIntegrationProbe` option exercises production's argument expansion using
  only a harmless fixture. The maintenance test validates its exact cleanup
  target and uses the registered QA uninstaller.

## Validation

| Check | Result |
| --- | --- |
| Targeted updater tests | 16 passed |
| Full `flutter test --no-pub` | 238 passed |
| `flutter analyze --no-pub` | No issues |
| Windows Release build | Passed |
| Final native updater rebuild | Passed |
| Real public API/download/size/SHA-256/staging probe | Passed |
| Isolated Inno install/update/repair/native handoff/relaunch/uninstall | Passed |
| Selected counts, retained INI, prior camera module and user data | Passed |
| Legacy ZIP/prepared-bundle updater fixture tests | Both passed |
| Registry-isolated native migration probe | Passed; empty, 1–4 slots, ownership, partial slot |
| Windows runtime bundle verification | Passed |
| Production repair Setup build and local SHA-256 verification | Passed |

The first maintenance run caught the literal-parameter bug. The corrected final
run confirms selected `4` cameras / `3` microphones on first install and `0` / `0`
(retain installed settings) on silent update. A deliberately stale build-tree INI
does not overwrite the installed `4` / `3` configuration. All tests use isolated
fixtures, a separate InstallerQA identity, and no installed application data.
The QA uninstall registration was absent after cleanup.

Evidence: `.runlogs/updater-fix-20261114/`. Local repair artifact:
`setup/Localist-Windows-Setup-x64-7.3.1.exe` and its `.sha256` file under that root.
The version remains 7.3.1+2078; this is a local repair build, not a new release.

No production camera/audio driver was installed, removed or re-registered during
validation. UAC interaction, Windows 10 hardware and an actual in-use driver
upgrade were not repeated. The tests verify the real installer/updater handoff
and migration policy with isolated fixtures, not every hardware configuration.
Existing plugin CMake and admin/per-user Inno warnings remain build warnings.
