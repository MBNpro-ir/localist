"""Real Android sender -> Windows CaptureHub -> four DirectShow webcam consumers.
Uses the isolated LOCALIST_CAPTURE_QA_RUNNER and per-user QA filter identities.
Never registers production cameras or changes user application preferences.
"""
from pathlib import Path
import concurrent.futures
import json
import os
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parent.parent
QA = ROOT / '.runlogs/capture-setup-fix'
BUNDLE = ROOT / 'build/windows-capture-receiver-qa/runner/Release'
PROBE = ROOT / 'build/windows-capture-receiver-qa/virtual_camera/Release/localist_camera_probe.exe'
ADB = Path(os.environ['LOCALAPPDATA']) / 'Android/Sdk/platform-tools/adb.exe'
HIDDEN = {'creationflags': subprocess.CREATE_NO_WINDOW}

def adb(*args):
    return subprocess.check_output([str(ADB), '-s', 'emulator-5560', *args], **HIDDEN)

def run():
    for name in ['windows-receive-ready.json', 'receiver-consumed']:
        (QA / name).unlink(missing_ok=True)
    adb('shell','am','force-stop','com.prs.localist')
    adb('shell','run-as','com.prs.localist','rm','-f','cache/capture-sender-session.json')
    adb('shell','am','start','-n','com.prs.localist/.MainActivity')
    session = None
    end = time.monotonic() + 30
    while time.monotonic() < end:
        result = subprocess.run([str(ADB),'-s','emulator-5560','exec-out','run-as','com.prs.localist','cat','cache/capture-sender-session.json'],capture_output=True,**HIDDEN)
        if result.returncode == 0:
            try:
                session = json.loads(result.stdout)
                break
            except json.JSONDecodeError:
                pass
        time.sleep(.2)
    assert session, 'Compiled Android sender did not become ready'
    (QA/'sender-session.json').write_text(json.dumps(session), encoding='utf-8')
    adb('forward', 'tcp:45108', 'tcp:33333')
    registered = []
    receiver = None
    try:
        for slot in range(4):
            suffix = f'-{slot+1}' if slot else ''
            dll = next(BUNDLE.glob(f'LocalistCamera64{suffix}-7.*.dll'))
            subprocess.run([str(PROBE),f'--register{slot+1}',str(dll)],check=True,**HIDDEN)
            registered.append((slot,dll))
        receiver = subprocess.Popen([str(BUNDLE/'Localist.exe'),str(QA)], **HIDDEN)
        end = time.monotonic() + 150
        ready = QA/'windows-receive-ready.json'
        while not ready.exists() and time.monotonic() < end:
            assert receiver.poll() is None, f'Windows receiver exited: {receiver.returncode}'
            time.sleep(.2)
        report = json.loads(ready.read_text(encoding='utf-8'))
        assert report['ok'], report
        for receiver_state in report['receivers']:
            inbound=receiver_state.get('inbound',[])
            assert any(s.get('kind',s.get('mediaType'))=='video' and int(s.get('framesDecoded',0))>0 for s in inbound), inbound
            assert any(s.get('kind',s.get('mediaType'))=='audio' and int(s.get('bytesReceived',0))>0 for s in inbound), inbound
        print('WINDOWS_FOUR_WEBRTC_RECEIVERS_CONNECTED', json.dumps(report), flush=True)
        ffmpeg = shutil.which('ffmpeg')
        if not ffmpeg:
            ffmpeg = str(next((Path(os.environ['LOCALAPPDATA'])/'Microsoft/WinGet/Packages').glob('yt-dlp.FFmpeg_*/ffmpeg-*/bin/ffmpeg.exe')))
        def consume(slot):
            output = QA/f'windows-received-camera-{slot+1}.rgb'
            process = subprocess.run([ffmpeg,'-hide_banner','-loglevel','warning','-f','dshow',
                '-video_size','640x480','-framerate','15','-i',f'video=Localist QA Camera {slot+1}',
                '-frames:v','6','-pix_fmt','rgb24','-f','rawvideo','-y',str(output)],capture_output=True,timeout=35,**HIDDEN)
            (QA/f'windows-camera-{slot+1}.log').write_bytes(process.stderr)
            assert process.returncode == 0, process.stderr.decode(errors='replace')[-1500:]
            data=output.read_bytes()
            assert len(data)==640*480*3*6, (slot,len(data))
            last=data[-640*480*3:]
            samples=last[::131]
            assert max(samples)-min(samples)>35, f'Camera {slot+1} returned blank/placeholder frames'
            return {'slot':slot+1,'frames':6,'width':640,'height':480,'range':max(samples)-min(samples)}
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            report['directShowConsumers']=list(pool.map(consume,range(4)))
        (QA/'windows-pipeline-results.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
        print('WINDOWS_ANDROID_WEBCAM_PIPELINE_OK', json.dumps(report), flush=True)
        # Keep this real producer active for a separately invoked OBS consumer.
        if os.environ.get('LOCALIST_PIPELINE_OBS') == '1':
            env=dict(os.environ,LOCALIST_CAPTURE_EXTERNAL='1',LOCALIST_CAPTURE_QA_ROOT=str(QA))
            subprocess.run(['python',str(ROOT/'tools/test_multi_camera_obs.py')],env=env,check=True,timeout=50,**HIDDEN)
    finally:
        (QA/'receiver-consumed').write_text('done',encoding='utf-8')
        if receiver:
            try: receiver.wait(timeout=15)
            except subprocess.TimeoutExpired:
                receiver.terminate(); receiver.wait(timeout=5)
        for slot,dll in reversed(registered):
            subprocess.run([str(PROBE),f'--unregister{slot+1}',str(dll)],check=True,**HIDDEN)
        adb('shell','run-as','com.prs.localist','touch','cache/capture-sender-stop')
        time.sleep(.5)
        log = subprocess.run([str(ADB),'-s','emulator-5560','exec-out','run-as','com.prs.localist','cat','cache/capture-sender.log'],capture_output=True,**HIDDEN)
        (QA/'android-sender.log').write_bytes(log.stdout)
        adb('forward','--remove','tcp:45108')

if __name__ == '__main__': run()
