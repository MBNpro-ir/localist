"""Release packaging invariants, including native IPC executable-pair trust."""
from pathlib import Path
import hashlib
import re
import sys

root = Path(__file__).resolve().parent.parent
bundle = Path(sys.argv[1]) if len(sys.argv) > 1 else root / 'build/windows/x64/runner/Release'
spec = (root/'pubspec.yaml').read_text(encoding='utf-8')
version,build = re.search(r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)',spec,re.M).groups()
app,helper = bundle/'Localist.exe',bundle/'LocalistRemote.exe'
assert hashlib.sha256(app.read_bytes()).digest() == hashlib.sha256(helper.read_bytes()).digest(), \
    'Localist.exe and LocalistRemote.exe must be byte-identical for authenticated native IPC'
for arch in (32,64):
    for slot in range(4):
        suffix = f'-{slot+1}' if slot else ''
        camera = bundle/f'LocalistCamera{arch}{suffix}-{version}.{build}.dll'
        assert camera.is_file() and camera.stat().st_size > 10000, f'Missing camera: {camera.name}'
for relative in ('flutter_windows.dll','flutter_webrtc_plugin.dll','libwebrtc.dll',
                 'librustdesk.dll','LocalistUpdater.exe','data/app.so',
                 'data/flutter_assets/assets/live_capture.html'):
    assert (bundle/relative).is_file(), f'Missing bundle file: {relative}'
print(f'Verified Windows {version}+{build}: identical IPC executables, eight camera modules and runtime assets.')
