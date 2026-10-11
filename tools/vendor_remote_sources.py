"""Import the pinned upstream client; run once before applying Localist patches.

Native and bridge artifacts must come from the same upstream commit.
The generated tree and subsequent Localist patches are checked into the repo.
"""
import hashlib
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
UPSTREAM = ROOT / '.research/rustdesk'
DEST = ROOT / 'third_party/localist_remote'
COMMIT = '4411d10f450a514c01c83e4f8af7151836300abb'
if DEST.exists():
    raise SystemExit('Refusing to overwrite the patched remote module.')

shutil.copytree(UPSTREAM / 'flutter/lib', DEST / 'lib')
shutil.copytree(UPSTREAM / 'flutter/assets', ROOT / 'assets/remote')
shutil.copyfile(UPSTREAM / 'LICENCE', DEST / 'LICENSE')
for file in (ROOT / '.research/bridge/flutter/lib').glob('*.dart'):
    shutil.copyfile(file, DEST / 'lib' / file.name)

for file in (DEST / 'lib').rglob('*.dart'):
    text = file.read_text(encoding='utf-8')
    text = text.replace('assets/', 'assets/remote/')
    text = text.replace('bind.mainGetAppNameSync()', "'Localist'")
    text = text.replace('dialogTheme: DialogTheme(', 'dialogTheme: DialogThemeData(')
    text = text.replace('tabBarTheme: const TabBarTheme(', 'tabBarTheme: const TabBarThemeData(')
    text = text.replace('return platformFFI.translate(name, localeName);',
                        "return platformFFI.translate(name, localeName).replaceAll('RustDesk', 'Localist');")
    file.write_text(text, encoding='utf-8')

pubspec = (UPSTREAM / 'flutter/pubspec.yaml').read_text(encoding='utf-8')
pubspec = pubspec[:pubspec.index('dev_dependencies:')]
pubspec = pubspec.replace('package_info_plus: ^4.2.0', 'package_info_plus: ^9.0.0')
pubspec = pubspec.replace('device_info_plus: ^9.1.0', 'device_info_plus: ^12.0.0')
pubspec = pubspec.replace('file_picker: ^5.1.0', 'file_picker: ^12.2.0')
pubspec = pubspec.replace('extended_text: 14.0.0', 'extended_text: 15.0.2')
pubspec = pubspec.replace('google_fonts: ^6.2.1', 'google_fonts: ^8.1.0')
pubspec = pubspec.replace('flutter_keyboard_visibility: ^5.4.0', 'flutter_keyboard_visibility: ^6.0.0')
pubspec = pubspec.replace('qr_code_scanner: ^1.0.0', 'mobile_scanner: ^7.2.0')
pubspec += '''
flutter:
  plugin:
    platforms:
      android:
        package: com.carriez.flutter_hbb
        pluginClass: LocalistRemotePlugin
'''
(DEST / 'pubspec.yaml').write_text(pubspec, encoding='utf-8')

native = DEST / 'android/src/main'
shutil.copytree(UPSTREAM / 'flutter/android/app/src/main/kotlin', native / 'kotlin')
for directory in ['drawable', 'values', 'xml']:
    shutil.copytree(UPSTREAM / f'flutter/android/app/src/main/res/{directory}', native / 'res' / directory)
shutil.copytree(UPSTREAM / 'libs/base/protos', native / 'proto')
verifier = ROOT / '.research/rustls-platform-verifier-android-0.1.1/maven'
shutil.copytree(verifier, DEST / 'android/maven')
hashes = {}
for abi in ['arm64-v8a', 'armeabi-v7a', 'x86_64']:
    target = native / 'jniLibs' / abi / 'librustdesk.so'
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(ROOT / f'.research/native/{abi}/liblibrustdesk.so', target)
    hashes[abi] = hashlib.sha256(target.read_bytes()).hexdigest()

for file in (native / 'kotlin').rglob('*.kt'):
    text = file.read_text(encoding='utf-8').replace('"RustDesk', '"Localist')
    text = text.replace('class MainActivity : FlutterActivity()', 'open class MainActivity : FlutterActivity()')
    file.write_text(text, encoding='utf-8')
strings = native / 'res/values/strings.xml'
strings.write_text(strings.read_text(encoding='utf-8').replace('RustDesk', 'Localist'), encoding='utf-8')
(DEST / 'UPSTREAM.json').write_text(json.dumps({
    'repository': 'https://github.com/rustdesk/rustdesk',
    'commit': COMMIT,
    'version': '1.5.0',
    'native_and_bridge_workflow_run': 38038914676,
    'native_sha256': hashes,
}, indent=2) + '\n', encoding='utf-8')
print(f'Imported remote client and three native ABIs into {DEST}')
