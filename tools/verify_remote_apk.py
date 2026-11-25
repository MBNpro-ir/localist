"""Check that Android packages contain the internal engine and retained JNI types."""
from zipfile import ZipFile
from pathlib import Path
import argparse
import subprocess

abis = {'arm64-v8a', 'armeabi-v7a', 'x86_64'}
required_types = (
    b'Lffi/FFI;',
    b'Lcom/carriez/flutter_hbb/RemoteActivity;',
    b'Lcom/carriez/flutter_hbb/MainService;',
    b'Lcom/carriez/flutter_hbb/InputService;',
    b'Lorg/rustls/platformverifier/CertificateVerifier;',
)
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--aapt2', type=Path)
parser.add_argument('apks', type=Path, nargs='+')
args = parser.parse_args()

for apk in args.apks:
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
    if args.aapt2:
        manifest = subprocess.check_output(
            [args.aapt2, 'dump', 'xmltree', '--file', 'AndroidManifest.xml', apk],
            text=True,
            encoding='utf-8',
        )
        forbidden = (
            'REQUEST_INSTALL_PACKAGES', 'MANAGE_EXTERNAL_STORAGE',
            'READ_EXTERNAL_STORAGE', 'WRITE_EXTERNAL_STORAGE',
            'REQUEST_IGNORE_BATTERY_OPTIMIZATIONS', 'BIND_VPN_SERVICE',
            'BIND_NOTIFICATION_LISTENER_SERVICE',
            'READ_SMS', 'RECEIVE_SMS', 'RECEIVE_BOOT_COMPLETED',
            'requestLegacyExternalStorage',
        )
        found = [name for name in forbidden if name in manifest]
        if found:
            raise SystemExit(f'{apk.name}: unexpected manifest entries: {", ".join(found)}')
        accessibility_entries = [line for line in manifest.splitlines()
                                 if 'android.permission.BIND_ACCESSIBILITY_SERVICE' in line]
        if (len(accessibility_entries) != 1
                or 'com.carriez.flutter_hbb.InputService' not in manifest):
            raise SystemExit(f'{apk.name}: the expected remote-input Accessibility service is missing or duplicated')
        print(f'{apk.name}: restricted Android permissions and services are absent.')
