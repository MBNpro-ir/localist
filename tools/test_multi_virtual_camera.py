"""Four isolated synthetic publishers and four simultaneous DirectShow consumers."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import json
import os
import shutil
import subprocess
import time
import winreg

ROOT = Path(__file__).resolve().parent.parent
QA = ROOT / '.runlogs/multicapture-qa'
BIN = ROOT / 'build/windows-multicapture/native-qa/Release'
PROBE = BIN / 'localist_camera_probe.exe'
HIDDEN = {'creationflags': subprocess.CREATE_NO_WINDOW}

def main():
    ffmpeg = shutil.which('ffmpeg')
    if not ffmpeg:
        packages = Path(os.environ['LOCALAPPDATA']) / 'Microsoft/WinGet/Packages'
        ffmpeg = str(next(packages.glob('yt-dlp.FFmpeg_*/ffmpeg-*/bin/ffmpeg.exe')))
    registered = []
    producer = None
    try:
        for slot in range(4):
            dll = BIN / ('LocalistCamera64' + (f'-{slot+1}' if slot else '') + '.dll')
            subprocess.run([str(PROBE), f'--register{slot+1}', str(dll)], check=True, **HIDDEN)
            registered.append((slot, dll))
        producer = subprocess.Popen([str(PROBE), '--produce-four', str(QA / 'four-producer.json')], **HIDDEN)
        time.sleep(.6)
        def capture(slot):
            output = QA / f'four-camera-{slot+1}.rgb'
            process = subprocess.run([ffmpeg, '-hide_banner', '-loglevel', 'warning',
                '-f', 'dshow', '-video_size', '640x480', '-framerate', '30',
                '-i', f'video=Localist QA Camera {slot+1}', '-frames:v', '8',
                '-pix_fmt', 'rgb24', '-f', 'rawvideo', '-y', str(output)],
                capture_output=True, timeout=20, **HIDDEN)
            (QA / f'four-camera-{slot+1}.log').write_bytes(process.stderr)
            assert process.returncode == 0, process.stderr.decode(errors='replace')[-1500:]
            data = output.read_bytes()
            assert len(data) == 640*480*3*8
            frame = data[-640*480*3:]
            rgb = [round(sum(frame[channel::3])/(640*480),1) for channel in range(3)]
            expected = [[255,0,0],[0,255,0],[0,0,255],[255,255,255]][slot]
            assert all(abs(a-b)<30 for a,b in zip(rgb,expected)), (slot,rgb)
            return {'slot':slot+1,'frames':8,'meanRGB':rgb}
        with ThreadPoolExecutor(max_workers=4) as pool:
            frames = list(pool.map(capture, range(4)))
        browser = subprocess.run(['node',str(ROOT/'tools/test_multi_camera_browser.cjs')],
            capture_output=True, timeout=20, **HIDDEN)
        (QA/'browser-four.log').write_bytes(browser.stdout+browser.stderr)
        assert browser.returncode == 0, browser.stderr.decode(errors='replace')[-1500:]
        # Keep all producers alive while Chrome/OBS optional consumers connect.
        (QA / 'four-cameras-running').write_text(str(producer.pid))
        assert producer.wait(timeout=40) == 0
        result = {'simultaneousConsumers':frames,'producer':json.loads((QA/'four-producer.json').read_text())}
        (QA/'native-four-results.json').write_text(json.dumps(result,indent=2))
        print(json.dumps(result))
    finally:
        if producer and producer.poll() is None:
            producer.terminate(); producer.wait(timeout=10)
        for slot,dll in reversed(registered):
            subprocess.run([str(PROBE),f'--unregister{slot+1}',str(dll)],check=True,**HIDDEN)
            try:
                key=winreg.OpenKey(winreg.HKEY_CURRENT_USER,
                    fr'Software\Classes\CLSID\{{58BC{0x2325+slot:04X}-E9D9-4BB9-A460-6630C82A5301}}')
            except FileNotFoundError:
                pass
            else:
                winreg.CloseKey(key)
                raise AssertionError('QA camera registration was not removed')

if __name__=='__main__': main()
