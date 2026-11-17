# Localist Developer Bridge — Security Threat Model

## Scope

This review covers the Windows ADB client integration, RustDesk's existing TCP tunnel, and Android tunnel consent. It is a source review; network and device acceptance tests have not run.

## Assets and trust boundaries

| Asset | Boundary / impact |
|---|---|
| Android device and user data | ADB can install packages, execute shell commands, read logs, and attach debuggers after Android grants authorization. |
| ADB endpoint and authorization | Android system `adbd` must expose a TCP listener and accept the workstation's ADB identity. |
| Windows ADB server | Shared local service used by Android Studio and the `adb.exe` client. |
| RustDesk session identity/password | Existing peer authentication, tunnel permission, and Android user-consent boundary. |
| Remote tunnel target | A privileged TCP route; it must stay limited to the target the Android user approves. |

## Threats and controls

| Threat | Control in code / design | Residual status |
|---|---|---|
| Shell injection through host input | Endpoint validation; structured process arguments; `runInShell: false`. | Static review only. |
| Accidental ADB connection | Feature defaults off; connect/disconnect are explicit user actions; no auto-reconnect. | UI/runtime behavior requires device test. |
| Unauthorized Android device | ADB retains its own RSA/TLS authorization. Localist does not bypass or accept Android prompts. | Real unauthorized-device case not tested. |
| False assumption that hotspot means ADB | UI states that hotspot supplies IP connectivity but does not start `adbd`. | Test with the phone's actual hotspot is pending. |
| Arbitrary remote TCP access | RustDesk Network tunnel requires the existing session permissions and exact incoming consent target. | End-to-end target restriction and lifecycle not tested. |
| Public ADB exposure | Windows port-forward listener is loopback-bound in the bundled native source. | Runtime bind probe not run. |
| Tunnel consent triggers screen capture | Android handler recognizes port-forward clients and skips capture/input permission requests. | Android UI regression test not run. |
| Credentials in Localist logs | The Developer Bridge does not log ADB payloads or RustDesk session passwords. | Runtime log review not run. |
| ADB connection survives Localist exit | Feature disconnects only endpoints it opened; it does not kill the shared ADB server. | Cleanup behavior not tested. |

## Secure defaults and limitations

- The feature starts disabled; no Android debugging settings are modified.
- No USB-only `adb tcpip` helper, root access, accessibility automation, hidden API, private-key access, new Android permission, or custom cryptography is added.
- Android's own ADB authorization remains the device-level gate; RustDesk trust and consent are separate transport gates.
- A RustDesk tunnel transports a TCP endpoint but cannot create an Android `adbd` listener. With no cable and Wireless debugging disabled, the endpoint is unavailable on stock Android.
- No external identity/cloud service is added.

## Required security tests before release

Test target mismatch, unauthorized Android consent, session revocation, relay, interruption, localhost-only listener, cleanup, and app restart. All are currently **NOT TESTED**.

