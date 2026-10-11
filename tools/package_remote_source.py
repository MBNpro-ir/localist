"""Package corresponding native source and record Localist's native patch."""
from pathlib import Path
import gzip
import subprocess
import tarfile
import sys

root = Path(__file__).resolve().parent.parent
source = Path(sys.argv[1]) if len(sys.argv) > 1 else root / '.research/rustdesk'
package = root / 'third_party/localist_remote'
excluded = {'.git', 'target', '.dart_tool', 'build', '.gradle', '__pycache__'}
patches = [subprocess.check_output([
    'git', '-C', str(source), 'diff', '--', 'src/core_main.rs', 'src/ipc/auth.rs', 'src/platform/windows.rs',
])]
patches.append(subprocess.check_output([
    'git', '-C', str(source / 'libs/hbb_common'), 'diff',
    '--src-prefix=a/libs/hbb_common/', '--dst-prefix=b/libs/hbb_common/',
    '--', 'src/config.rs',
]))
(package / 'patches').mkdir(exist_ok=True)
(package / 'patches/localist-native-namespace.patch').write_bytes(b''.join(patches))
with (package / 'native-source.tar.gz').open('wb') as raw:
    with gzip.GzipFile(filename='', fileobj=raw, mode='wb', mtime=0) as compressed:
        with tarfile.open(fileobj=compressed, mode='w') as archive:
            for path in sorted(source.rglob('*')):
                relative = path.relative_to(source)
                if any(part in excluded for part in relative.parts) or not path.is_file():
                    continue
                info = archive.gettarinfo(str(path), f'native-source/{relative.as_posix()}')
                info.uid = info.gid = 0
                info.uname = info.gname = ''
                info.mtime = 0
                with path.open('rb') as content:
                    archive.addfile(info, content)
print('Packaged corresponding native source and namespace/dispatch patch.')
