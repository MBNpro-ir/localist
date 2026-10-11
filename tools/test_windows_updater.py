"""Exercise the actual updater against isolated, windowless fixture bundles.

Run from an x64 MSVC developer environment after a Windows build:
  python tools/test_windows_updater.py build/windows/x64/runner/Debug/LocalistUpdater.exe
No installed application, remote engine, configuration or user data is touched.
"""
from pathlib import Path
import ctypes
import subprocess
import sys
import tempfile
import time
from zipfile import ZipFile

STUB = r'''
#include <windows.h>
#include <string>
int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR args, int) {
  wchar_t path[32768];
  GetModuleFileNameW(nullptr, path, 32768);
  std::wstring output(path);
  output = output.substr(0, output.find_last_of(L"\\/")) + L"\\launched.txt";
  HANDLE file = CreateFileW(output.c_str(), GENERIC_WRITE, FILE_SHARE_READ,
      nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return 1;
  DWORD written;
  const auto result = std::to_wstring(GetCurrentProcessId()) + L"\n" + args;
  WriteFile(file, result.data(), static_cast<DWORD>(result.size() * sizeof(wchar_t)), &written, nullptr);
  CloseHandle(file);
  return 0;
}
'''


def run(helper: Path):
    if sys.platform != 'win32':
        raise SystemExit('This test requires Windows and an x64 MSVC environment.')
    helper = helper.resolve(strict=True)
    hidden = dict(creationflags=subprocess.CREATE_NO_WINDOW)
    with tempfile.TemporaryDirectory(prefix='Localist-updater-qa-') as temporary:
        root = Path(temporary).resolve()
        source = root / 'stub.cpp'
        source.write_text(STUB, encoding='utf-8')
        stub = root / 'stub.exe'
        subprocess.run(['cl', '/nologo', '/EHsc', '/std:c++17', str(source),
                        f'/Fe:{stub}', '/link', '/SUBSYSTEM:WINDOWS'],
                       cwd=root, check=True, **hidden)
        for prepared in (False, True):
            case = root / ('prepared' if prepared else 'archive')
            target, bundle = case / 'installed', case / 'new'
            target.mkdir(parents=True)
            bundle.mkdir()
            (target / 'Localist.exe').write_bytes(b'old-version')
            (target / 'librustdesk.dll').write_bytes(b'old-engine')
            (target / 'personal.keep').write_text('keep me', encoding='utf-8')
            (target / 'debug.log').write_text('preserve log', encoding='utf-8')
            (bundle / 'Localist.exe').write_bytes(stub.read_bytes())
            (bundle / 'LocalistUpdater.exe').write_bytes(helper.read_bytes())
            for name in ('LocalistRemote.exe', 'librustdesk.dll', 'flutter_windows.dll'):
                (bundle / name).write_bytes(b'new-version')
            pubspec = bundle / 'data' / 'flutter_assets' / 'pubspec.yaml'
            pubspec.parent.mkdir(parents=True)
            pubspec.write_text('version: 6.0.1+63\n', encoding='utf-8')
            archive = case / 'update.zip'
            with ZipFile(archive, 'w') as package:
                for file in bundle.rglob('*'):
                    if file.is_file():
                        package.write(file, file.relative_to(bundle))
            waiter = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(30)'], **hidden)
            command = [str(helper), '--wait-pid', str(waiter.pid), '--archive', str(archive),
                       '--target', str(target), '--launch', str(target / 'Localist.exe'),
                       '--version', '6.0.1']
            if prepared:
                command += ['--bundle', str(bundle)]
            updater = subprocess.Popen(command, **hidden)
            try:
                time.sleep(0.5)
                assert updater.poll() is None, 'Updater did not wait for the running application'
                assert (target / 'Localist.exe').read_bytes() == b'old-version'
                waiter.terminate()
                waiter.wait(timeout=5)
                assert updater.wait(timeout=90) == 0, 'Updater failed'
                marker = target / 'launched.txt'
                deadline = time.monotonic() + 10
                while not marker.exists() and time.monotonic() < deadline:
                    time.sleep(0.05)
                result = marker.read_text(encoding='utf-16-le')
                assert '6.0.1' in result
                # The launch marker is written before the fixture process exits.
                # Wait for its real exit before deleting its executable on Windows.
                kernel = ctypes.WinDLL('kernel32', use_last_error=True)
                kernel.OpenProcess.argtypes = [ctypes.c_uint32, ctypes.c_int, ctypes.c_uint32]
                kernel.OpenProcess.restype = ctypes.c_void_p
                kernel.WaitForSingleObject.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
                kernel.CloseHandle.argtypes = [ctypes.c_void_p]
                process = kernel.OpenProcess(0x100000, False, int(result.splitlines()[0]))
                if process:
                    try:
                        assert kernel.WaitForSingleObject(process, 10000) == 0, 'Fixture did not exit'
                    finally:
                        kernel.CloseHandle(process)
                assert (target / 'Localist.exe').read_bytes() == stub.read_bytes()
                assert (target / 'librustdesk.dll').read_bytes() == b'new-version'
                assert (target / 'personal.keep').read_text(encoding='utf-8') == 'keep me'
                assert (target / 'debug.log').read_text(encoding='utf-8') == 'preserve log'
                assert not archive.exists(), 'Applied download was not removed'
                print(f'{case.name}: parent wait, bundle install, preserved data and relaunch passed.')
            finally:
                for process in (waiter, updater):
                    if process.poll() is None:
                        process.kill()
                        process.wait(timeout=5)


if __name__ == '__main__':
    run(Path(sys.argv[1]))
