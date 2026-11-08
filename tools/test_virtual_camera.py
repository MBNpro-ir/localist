"""Probe -> Localist shared frames -> real DirectShow filter -> independent FFmpeg.

Build windows/virtual_camera with LOCALIST_CAMERA_QA=ON and LOCALIST_WEBRTC_DIR.
Only a temporary HKCU registration is used; an existing Localist camera is
refused. No installed camera, OBS registration, microphone or user media is used.
"""
from pathlib import Path
import json
import shutil
import subprocess
import time
import winreg


def main():
    root = Path(__file__).resolve().parent.parent
    folder = root / 'build/virtual-camera-qa/Release'
    probe, dll = folder / 'localist_camera_probe.exe', folder / 'LocalistCamera64.dll'
    ffmpeg = shutil.which('ffmpeg')
    assert ffmpeg and probe.is_file() and dll.is_file(), 'Build the camera QA probe and install FFmpeg first'
    hidden = {'creationflags': subprocess.CREATE_NO_WINDOW}
    registered, producer = False, None
    try:
        subprocess.run([str(probe), '--register', str(dll)], check=True, **hidden)
        registered = True
        report = root / '.runlogs/nov08-native-camera-producer.json'
        producer = subprocess.Popen([str(probe), '--produce', str(report)], **hidden)
        time.sleep(1)

        def capture(name):
            output = root / '.runlogs' / name
            process = subprocess.run([
                ffmpeg, '-hide_banner', '-loglevel', 'info', '-f', 'dshow',
                '-video_size', '640x480', '-framerate', '30', '-i', 'video=Localist Camera',
                '-frames:v', '12', '-pix_fmt', 'rgb24', '-f', 'rawvideo', '-y', str(output),
            ], capture_output=True, timeout=25, **hidden)
            (root / '.runlogs' / (name + '.log')).write_bytes(process.stderr)
            assert process.returncode == 0, process.stderr.decode(errors='replace')[-1500:]
            data = output.read_bytes()
            assert len(data) == 640 * 480 * 3 * 12
            image = data[-640 * 480 * 3:]
            return [round(sum(image[channel::3]) / (640 * 480), 2) for channel in range(3)]

        live = capture('nov08-virtual-camera-live.rgb')
        assert live[0] > 200 and live[1] < 60 and live[2] < 60, live
        assert producer.wait(timeout=25) == 0
        blank = capture('nov08-virtual-camera-stopped.rgb')
        assert max(blank) < 3, blank
        result = {
            'consumer': 'Independent FFmpeg DirectShow capture', 'liveFrames': 12,
            'liveMeanRGB': live, 'stoppedMeanRGB': blank, 'privateFrameCleared': True,
            'nativePublisher': json.loads(report.read_text()),
        }
        (root / '.runlogs/nov08-virtual-camera-test.json').write_text(json.dumps(result, indent=2))
        print(result)
    finally:
        if producer and producer.poll() is None:
            producer.terminate()
            producer.wait(timeout=10)
        if registered:
            subprocess.run([str(probe), '--unregister', str(dll)], check=True, **hidden)
            try:
                key = winreg.OpenKey(winreg.HKEY_CURRENT_USER, r'Software\Classes\CLSID\{58BC2225-E9D9-4BB9-A460-6630C82A5301}')
            except FileNotFoundError:
                pass
            else:
                winreg.CloseKey(key)
                raise AssertionError('QA camera registration was not removed')


if __name__ == '__main__':
    main()
