"""Verify the exact, unchanged camera reference source before local/CI builds."""
from pathlib import Path
import hashlib
import json

root = Path(__file__).resolve().parent.parent / 'third_party/virtual_camera'
manifest = json.loads((root / 'UPSTREAM.json').read_text())
groups = [(root / 'upstream', manifest['files']),
          (root / 'upstream/deps/libdshowcapture/src', manifest['libdshowcapture']['files'])]
count = 0
for directory, files in groups:
    for name, expected in files.items():
        path = (directory / name).resolve()
        assert path.is_relative_to(directory.resolve()), f'Invalid manifest path: {name}'
        assert path.is_file() and hashlib.sha256(path.read_bytes()).hexdigest() == expected, f'Source mismatch: {name}'
        count += 1
print(f'Verified {count} pinned virtual camera source files.')
