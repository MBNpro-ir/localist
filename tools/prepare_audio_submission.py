"""Build a signable, explicitly unsigned driver CAB. Never installs a driver."""
from pathlib import Path
import hashlib
import json
import subprocess
import struct

ROOT = Path(__file__).resolve().parent.parent
PACKAGE = ROOT / 'build/localist-virtual-audio/unsigned'
OUT = ROOT / 'build/localist-virtual-audio'
files = [PACKAGE / name for name in ['LocalistAudio.inf', 'LocalistAudio.sys', 'localistaudio.cat', 'LocalistAudio.pdb']]
for file in files:
    if not file.is_file():
        raise SystemExit(f'Missing driver build/catalog: {file}')
ddf = OUT / 'submission.ddf'
ddf.write_text('\n'.join([
    '.OPTION EXPLICIT', '.Set CabinetNameTemplate=LocalistAudio-UNSIGNED.cab',
    f'.Set DiskDirectoryTemplate="{OUT}"', '.Set Cabinet=on', '.Set Compress=on',
    '.Set CompressionType=MSZIP', '.Set MaxDiskSize=0',
    # Microsoft requires one directory per package; no files at CAB root.
    '.Set DestinationDir=LocalistAudio',
    *[f'"{file}" "{file.name}"' for file in files],
]) + '\n', encoding='utf-8')
subprocess.run(['makecab.exe', '/F', str(ddf)], cwd=OUT, check=True)
# Check actual contents rather than trusting MakeCab's progress output.
cab = (OUT / 'LocalistAudio-UNSIGNED.cab').read_bytes()
if cab[:4] != b'MSCF':
    raise SystemExit('Invalid submission CAB header')
offset = struct.unpack_from('<I', cab, 16)[0]
count = struct.unpack_from('<H', cab, 28)[0]
members = []
for _ in range(count):
    offset += 16  # CFFILE fixed fields, followed by a null-terminated filename.
    end = cab.index(b'\0', offset)
    members.append(cab[offset:end].decode('utf-8'))
    offset = end + 1
expected = [f'LocalistAudio\\{file.name}' for file in files]
if sorted(members) != sorted(expected):
    raise SystemExit(f'Submission CAB member layout mismatch: {members!r}')
manifest = {'status': 'UNSIGNED_NOT_FOR_INSTALLATION', 'version': '7.3.0.77',
            'cab_directory': 'LocalistAudio',
            'cab_members': members,
            'files': {file.name: hashlib.sha256(file.read_bytes()).hexdigest() for file in files}}
(OUT / 'submission-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
print('UNSIGNED_AUDIO_SUBMISSION_PREPARED', OUT / 'LocalistAudio-UNSIGNED.cab')
