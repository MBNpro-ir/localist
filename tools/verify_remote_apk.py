"""Check that Android packages contain the internal engine and retained JNI types."""
from zipfile import ZipFile
from pathlib import Path
import sys

abis = {'arm64-v8a', 'armeabi-v7a', 'x86_64'}
required_types = (
    b'Lffi/FFI;',
    b'Lcom/carriez/flutter_hbb/RemoteActivity;',
    b'Lcom/carriez/flutter_hbb/MainService;',
    b'Lcom/carriez/flutter_hbb/InputService;',
    b'Lorg/rustls/platformverifier/CertificateVerifier;',
)
for argument in sys.argv[1:]:
    apk = Path(argument)
    with ZipFile(apk) as archive:
        files = archive.namelist()
        packaged_abis = {n.split('/')[1] for n in files if n.startswith('lib/')}
        if not packaged_abis or not packaged_abis <= abis:
            raise SystemExit(f'Unsupported/missing architectures in {apk}')
        for abi in packaged_abis:
            for library in ('librustdesk.so', 'libc++_shared.so', 'libflutter.so'):
                if f'lib/{abi}/{library}' not in files:
                    raise SystemExit(f'Missing {library} for {abi} in {apk}')
        dex = b''.join(archive.read(n) for n in files if n.endswith('.dex'))
        for name in required_types:
            if name not in dex:
                raise SystemExit(f'Missing retained native type {name!r} in {apk}')
        if archive.testzip() is not None:
            raise SystemExit(f'APK archive integrity failed: {apk}')
    print(f'{apk.name}: native engine, C++ runtime and JNI types verified ({", ".join(sorted(packaged_abis))}).')
