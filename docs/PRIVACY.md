# Localist data and remote connections

Local file transfer and browser streaming use the selected local network. Browser
links contain a random access token; anyone given that link can access its shared
media or transfer page until the service stops.

Remote Control connects to the ID/relay server selected in Localist Settings.
The default server is the maintainer's server at `81.30.108.248`. This server
coordinates connections and may relay session traffic. Direct IP connections and
LAN discovery are also supported. Remote access requires the receiving device's
approval or its configured authentication method.

Device names, connection history, transfer records and preferences are stored on
the device. Session passwords entered in Localist's connection form are not
saved by that form. The engine's permanent password and saved-peer credentials
are managed by its security settings. Optional address-book/account features use
the configured API server when the user signs in.

Updates and documentation links contact GitHub. The embedded engine's independent
automatic updater is disabled; Localist manages its own updates. Detailed debug
logs may contain device IDs, paths and connection information, so review logs
before sharing them.

Screen capture, accessibility input, microphone/audio and camera access depend on
platform permissions and the options selected by the user. Android requests the
system screen-sharing permission when screen capture starts.
Welcome can be skipped; missing access is requested when a feature needs it.
Settings → Permissions lets Android users manage individual remote capabilities
and opens the relevant system settings to revoke OS permissions. Incoming remote
requests can be accepted or declined without creating a permanent password.
