# Localist Camera reference sources

The pinned OBS DirectShow camera/filter, shared NV12 queue and tiny scaler are
embedded building blocks. OBS does not need to be installed or running.
`UPSTREAM.json` records source commits and exact downloaded SHA-256 digests.
Run `python tools/verify_virtual_camera_source.py` before building.

Reference licenses are retained in `upstream/COPYING` and the source notices;
libdshowcapture uses LGPL-2.1-or-later, and the OBS components are GPL-2.0-or-later.
Corresponding source and Localist adaptations are included in Windows bundles
under `data/licenses/LocalistCamera`.

Localist adaptations live in `windows/virtual_camera`, leaving these reference
bytes unchanged. CMake gives the device a separate CLSID, `Localist Camera`
friendly name and session-local queue, replaces the placeholder with black,
provides deterministic idle capabilities, removes the OBS configuration-file
dependency and blanks output immediately when the frame queue stops.
Both x86 and x64 filters are built with a static runtime. Their versioned DLL
names avoid overwriting a filter that another program still has loaded.

The WebRTC plugin's pinned renderer is adapted at build time in the build tree;
the Pub cache is never edited. A SHA-256 guard fails if that renderer changes.
Decoded I420 planes go directly to the local queue, including rotation, without
Dart frame copying, image encoding, another network stream or an OBS process.

Camera registration/removal is explicit in Camera & Mic. Uninstall only removes
the registration if its DLL path belongs to that installation. Stopping output
releases the queue and returns a neutral frame instead of keeping the last image.
DirectShow-compatible clients can select the camera; Media Foundation-only or
vendor-restricted clients need separate acceptance testing.

The filter exposes standard landscape/portrait output modes and respects the
consumer-selected frame interval, including inside OBS. Configure Video exposes
a Localist IPropertyPage; IAMCameraControl provides hardware-bounded zoom. A
session-local, same-account control bus connects those interfaces to Localist's
paired signaling channel. Source controls default to denied, require explicit
sender opt-in, expire with the receiver heartbeat, and revoke on stop. Quality
and audio-processing changes replace capture tracks on the existing connection.
The reference sources remain unchanged; all adaptations are in the build tree.

VB-CABLE is not bundled or rebranded. Its original signed package is downloaded
from VB-Audio only after a user action, checked by package/executable digests and
WinVerifyTrust, and its own interactive installer opens. Received microphone
audio can then be routed directly to CABLE Input, with CABLE Output selected in
the target app. No OBS audio routing is required. VB-Audio's license applies.
