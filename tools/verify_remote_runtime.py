"""Verify packaged engines against their pinned corresponding-source manifest."""
from pathlib import Path
import hashlib
import json

root = Path(__file__).resolve().parent.parent / 'third_party' / 'localist_remote'
manifest = json.loads((root / 'UPSTREAM.json').read_text(encoding='utf-8'))
checks = dict(manifest.get('runtime_sha256', {}))
for abi, expected in manifest['native_sha256'].items():
    checks[f'android/src/main/jniLibs/{abi}/librustdesk.so'] = expected
if not manifest.get('runtime_sha256'):
    raise SystemExit('Runtime dependency hashes have not been recorded.')
for relative, expected in checks.items():
    actual = hashlib.sha256((root / relative).read_bytes()).hexdigest()
    if actual != expected:
        raise SystemExit(f'Packaged engine checksum mismatch: {relative}')
print(f'Verified {len(checks)} engine, dependency and source files.')
