# Windows microphone output and device counts — 7.3.0+77

Received WebRTC PCM from Wi-Fi/LAN or USB tethering is converted natively to
48kHz mono16 and sent to a specific VB-CABLE WASAPI render endpoint. Other
applications select the corresponding CABLE Output recording endpoint. The name
"cable" describes a virtual audio connection inside Windows, not a physical
phone cable. The same output works for both network transports. Physical USB
tethering still needs the phone's normal network connection to Windows.

## Independent microphones

Every receiver reserves one unused cable; another receiver cannot write into
that cable. The base driver's 16-channel render alias is excluded because it
feeds the same recording device and is not another independent microphone.
Explicit per-device cable selection is optional and saved with that receiver.
An unavailable/occupied cable reports an output error while video and signaling
continue. Outputs retry during healthy sessions, allowing a waiting device to
acquire a cable released by another receiver. Stop detaches the raw audio sink,
stops its event-driven WASAPI thread and clears its bounded PCM queue.

System defaults are never changed. Native audio-track sinks are used instead of
WebRTC's global playback-output selector. Windows speaker playback for received
audio stays muted; Android's existing playback behavior is unchanged.

## Setup

The same Persian Setup shell offers camera and microphone counts from 1 to 4.
For updates it reads capture-devices.ini; silent updates preserve configured
counts. It registers the selected number of cameras, including both 32/64-bit
consumer modules. Runtime only checks registrations and tells the user to run
Setup when a camera was not installed; no in-app driver install button exists.

The ordinary signed VB-CABLE package is included unchanged. Additional A/B/C/D
cables require their own licenses and are NOT included in the distributed Setup.
When more microphones are requested than are installed, Setup asks for the
folder containing the user's extracted licensed packages. It accepts only
original VB-Audio MEDIA-class INF identities with valid catalog membership;
Windows still enforces the driver-signing policy. Invalid or insufficient
packages cannot be reported as successful installation. Initial driver setup may
require restart; Setup propagates the restart requirement and never reboots
without the user's action. Existing cables are not reinstalled or removed.

Uninstall removes this installation's webcam registrations/startup/firewall rule,
but keeps shared VB-CABLE devices that other applications may use. The original
VB-CABLE installer can remove them deliberately. VB-Audio origin and donationware
attribution appear in Setup, the application and installed notices. Professional
deployments must comply with the vendor's paid licensing rules.

Official sources:
- https://vb-audio.com/Cable/index.htm
- https://vb-audio.com/Services/licensing.htm

## Validation evidence and limits

Evidence is in `.runlogs/localist-microphone/vbcable`.
The official Pack46 archive is pinned by SHA-256, every extracted file is checked
against its manifest, and INF/SYS catalog membership passes SignTool `/kp`.
Four simultaneous actual WebRTC senders delivered distinct tones and video to
the hidden Windows receive host. A separate WASAPI recording client captured
CABLE Output. With the one cable installed on the workstation, only its owner
tone was present and other senders remained blocked, without losing their video.
Disabling the first owner's audio let a waiting sender acquire the released cable
automatically. The independent consumer then measured its 330 Hz tone at 0.98616
amplitude; the other three tones remained below 0.00013, confirming no mixing.

The workstation's device/driver-store audit found only the ordinary base cable;
A/B/C/D drivers were absent. Four real independent Windows microphones and fresh
A/B/C/D installation cannot be claimed tested without those licensed packages.
Physical Wi-Fi/USB phones were unavailable for this pass; the WebRTC integration
used synthetic browser sources over loopback. Existing network-route tests cover
USB preference/fallback separately. No physical microphone was recorded, default
audio device changed, or preexisting audio driver replaced during these tests.

The isolated QA Setup lifecycle covers install/update/repair/removal and retained
user files. Its UI verification checks both selectors expose 1–4, extra-package
controls appear when required, and the options do not overlap the action buttons
at normal and scaled sizes. QA fixtures skip machine-wide integration; this is
not a fresh-driver-installation certification.

207 Flutter tests passed, including receiver routing and USB fallback tests, and
Flutter analysis reported no issues. Windows Release and Android Debug builds
succeeded. Native probes cover PCM validation/conversion, bounded queues and
unique four-slot allocation, exhaustion, release and explicit cable selection.
The resulting 7.3.0 Setup is a local build; it has not been published or used for
a production installation on this workstation.
