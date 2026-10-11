"""Refresh pinned hashes after rebuilding the packaged Localist native engine."""
from pathlib import Path
import hashlib
import json

root = Path(__file__).resolve().parent.parent / 'third_party/localist_remote'
manifest_path = root / 'UPSTREAM.json'
manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
files = [root / 'native-source.tar.gz', root / 'LICENSE',
         root / 'patches/localist-native-namespace.patch']
files.extend(p for p in (root / 'windows/runtime').rglob('*') if p.is_file())
files.extend(p for p in (root / 'android/src/main/jniLibs').rglob('libc++_shared.so'))
files.extend(p for p in (root / 'android').rglob('*.aar'))
manifest['runtime_sha256'] = {
    p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
    for p in sorted(files)
}
manifest['hbb_common_commit'] = '229b904508364c8997aad0fb5af57effac859f60'
manifest['windows_native'] = {
    'namespace': 'LocalistRemote',
    'rust_version': '1.75.0',
    'features': ['flutter'],
    'vcpkg_baseline': '9e593bb18ea69cc5095e012465dcd675a822ed0d',
    'corresponding_source': 'native-source.tar.gz',
    'patch': 'patches/localist-native-namespace.patch',
}
manifest['android_cpp_runtime'] = {'ndk': '28.2.13676358 (r28c)'}
manifest['android_tls_verifier'] = 'rustls-platform-verifier 0.1.1'
manifest_path.write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
print(f'Recorded {len(files)} runtime/dependency/source hashes.')
