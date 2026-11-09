"""Build a signable, explicitly unsigned driver CAB. Never installs a driver."""
from pathlib import Path
import hashlib
import json
import subprocess

ROOT = Path(__file__).resolve().parent.parent
PACKAGE = ROOT / 'build/localist-virtual-audio/unsigned'
OUT = ROOT / 'build/localist-virtual-audio'
files = [PACKAGE / name for name in ['LocalistAudio.inf', 'LocalistAudio.sys', 'localistaudio.cat']]
for file in files:
    if not file.is_file():
        raise SystemExit(f'Missing driver build/catalog: {file}')
ddf = OUT / 'submission.ddf'
ddf.write_text('\n'.join([
    '.OPTION EXPLICIT', '.Set CabinetNameTemplate=LocalistAudio-UNSIGNED.cab',
    f'.Set DiskDirectoryTemplate="{OUT}"', '.Set Cabinet=on', '.Set Compress=on',
    '.Set CompressionType=MSZIP', '.Set MaxDiskSize=0',
    *[f'"{file}" "{file.name}"' for file in files],
]) + '\n', encoding='utf-8')
subprocess.run(['makecab.exe', '/F', str(ddf)], cwd=OUT, check=True)
manifest = {'status': 'UNSIGNED_NOT_FOR_INSTALLATION', 'version': '7.3.0.77',
            'files': {file.name: hashlib.sha256(file.read_bytes()).hexdigest() for file in files}}
(OUT / 'submission-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
print('UNSIGNED_AUDIO_SUBMISSION_PREPARED', OUT / 'LocalistAudio-UNSIGNED.cab')
