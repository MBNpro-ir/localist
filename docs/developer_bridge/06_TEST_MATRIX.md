# Localist Developer Bridge — Test Matrix

**Result key:** PASS means the check was executed; source inspection alone is not a pass.

## Code and build checks

| Check | Status | Evidence |
|---|---|---|
| Targeted Flutter analysis | PASS | Changed Dart files and model test; no issues. |
| Developer Bridge model tests | PASS | flutter test --no-pub test/developer_bridge_models_test.dart; all 6 tests passed, including USB/network transport classification. |
| Current Windows Debug build and launch | PASS | flutter build windows --no-pub --debug succeeded; Localist opened and the Developer Bridge screen rendered responsively. |
| Android build/install | NOT TESTED | No Android build/install for the latest Windows-only UI edit. |
| Phone ADB enumeration | PASS: empty | Official adb devices -l reported no device in the current session. |

## Acceptance matrix

| Test | Status | Evidence |
|---|---|---|
| Phone hotspot ADB without USB or Wireless debugging | BLOCKED | ADB device/mDNS lists were empty and the hotspot gateway rejected TCP 5555; hotspot alone does not start adbd. |
| RustDesk Internet tunnel and remote ADB | NOT TESTED / BLOCKED | Tunnel UI launches, but no phone-side ADB endpoint exists to forward. |
| Android Studio device list, APK install, Run, Logcat, debugger | NOT TESTED | Requires authenticated ADB endpoint. |
| ADB connection error path | NOT TESTED | No endpoint connect attempt made. |
| Android tunnel consent | SOURCE ONLY | Exact target shown; runtime device consent not exercised. |
| Relay and network interruption | NOT TESTED | No remote session. |
| Tunnel revocation and listener cleanup | NOT TESTED | No session. |
| Existing VPN Sharing / Quick Send / Stream regressions | NOT TESTED | Not exercised. |

## Automated coverage

test/developer_bridge_models_test.dart covers endpoint validation, IPv4/hostname/IPv6 parsing, ADB device states, USB classification, mDNS parsing, and error mapping. It does not validate a real endpoint, RustDesk, Android Studio, or device installation.

## Acceptance decision

**PARTIALLY VERIFIED.** Code analysis and model tests pass. The required phone modes are not verified. With the user's current constraints (never USB, Wireless debugging unavailable), stock Android does not expose the ADB endpoint needed by either transport. Do not describe this feature as ready or connected.

