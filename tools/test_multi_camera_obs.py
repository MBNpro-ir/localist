"""Exercise the installed OBS DirectShow source in an isolated libobs process.

No scenes, profiles, OBS preferences or physical webcam are read/changed.
The Localist filter is registered temporarily for this account, then removed.
"""
from pathlib import Path
import ctypes as c
import json
import os
import subprocess
import time
import winreg

ROOT = Path(__file__).resolve().parent.parent
QA = Path(os.environ.get('LOCALIST_CAPTURE_QA_ROOT', ROOT / '.runlogs/multicapture-qa'))
OBS = Path(os.environ.get('LOCALIST_OBS_ROOT', r'C:\Program Files\obs-studio'))
P = c.c_void_p


class VideoInfo(c.Structure):
    _fields_ = [('graphics_module', c.c_char_p)] + [(name, c.c_uint32) for name in
        ['fps_num', 'fps_den', 'base_width', 'base_height', 'output_width', 'output_height']] + [
        ('output_format', c.c_int), ('adapter', c.c_uint32), ('gpu_conversion', c.c_bool),
        ('colorspace', c.c_int), ('range', c.c_int), ('scale_type', c.c_int)]


class Frame(c.Structure):
    _fields_ = [('data', P * 8), ('linesize', c.c_uint32 * 8), ('width', c.c_uint32),
                ('height', c.c_uint32), ('timestamp', c.c_uint64), ('format', c.c_int)]


def main():
    config = QA / 'obs'
    config.mkdir(exist_ok=True)
    handle = os.add_dll_directory(str(OBS / 'bin/64bit'))
    plugin_handle = os.add_dll_directory(str(OBS / 'obs-plugins/64bit'))
    obs = c.CDLL(str(OBS / 'bin/64bit/obs.dll'))

    def api(name, result, *args):
        function = getattr(obs, name)
        function.restype = result
        function.argtypes = args
        return function

    startup = api('obs_startup', c.c_bool, c.c_char_p, c.c_char_p, P)
    shutdown = api('obs_shutdown', None)
    add_data = api('obs_add_data_path', None, c.c_char_p)
    reset_video = api('obs_reset_video', c.c_int, c.POINTER(VideoInfo))
    open_module = api('obs_open_module', c.c_int, c.POINTER(P), c.c_char_p, c.c_char_p)
    init_module = api('obs_init_module', c.c_bool, P)
    properties = api('obs_get_source_properties', P, c.c_char_p)
    get_property = api('obs_properties_get', P, P, c.c_char_p)
    list_count = api('obs_property_list_item_count', c.c_size_t, P)
    list_name = api('obs_property_list_item_name', c.c_char_p, P, c.c_size_t)
    list_value = api('obs_property_list_item_string', c.c_char_p, P, c.c_size_t)
    destroy_properties = api('obs_properties_destroy', None, P)
    settings_create = api('obs_data_create', P)
    settings_string = api('obs_data_set_string', None, P, c.c_char_p, c.c_char_p)
    settings_int = api('obs_data_set_int', None, P, c.c_char_p, c.c_longlong)
    settings_release = api('obs_data_release', None, P)
    modified = api('obs_property_modified', c.c_bool, P, P)
    create_source = api('obs_source_create_private', P, c.c_char_p, c.c_char_p, P)
    release_source = api('obs_source_release', None, P)
    show_source = api('obs_source_inc_showing', None, P)
    hide_source = api('obs_source_dec_showing', None, P)
    get_frame = api('obs_source_get_frame', c.POINTER(Frame), P)
    release_frame = api('obs_source_release_frame', None, P, c.POINTER(Frame))
    probe = ROOT / 'build/windows-multicapture/native-qa/Release/localist_camera_probe.exe'
    dll = probe.parent / 'LocalistCamera64.dll'
    hidden = {'creationflags': subprocess.CREATE_NO_WINDOW}
    registered = []
    started = False
    producer = None
    report = {}
    external = os.environ.get('LOCALIST_CAPTURE_EXTERNAL') == '1'
    try:
        if not external:
            for slot in range(4):
                dll = probe.parent / ('LocalistCamera64' + (f'-{slot+1}' if slot else '') + '.dll')
                subprocess.run([str(probe),f'--register{slot+1}',str(dll)],check=True,**hidden)
                registered.append((slot,dll))
            subprocess.run([str(probe),'--controls-four',str(config/'controls.json')],check=True,**hidden)
            report['nativeConfigureVideo'] = json.loads((config/'controls.json').read_text())
            producer = subprocess.Popen([str(probe),'--produce-four',str(config/'producer.json')],**hidden)
            time.sleep(.5)
        assert startup(b'en-US', str(config).encode(), None)
        started = True
        add_data(((OBS / 'data/libobs').as_posix() + '/').encode())
        video = VideoInfo(str(OBS / 'bin/64bit/libobs-d3d11.dll').encode(), 30, 1, 640, 480, 640, 480, 1, 0, True, 0, 1, 2)
        assert reset_video(c.byref(video)) == 0, 'OBS graphics initialization failed'
        module = P()
        assert open_module(c.byref(module), str(OBS / 'obs-plugins/64bit/win-dshow.dll').encode(), str(OBS / 'data/obs-plugins/win-dshow').encode()) == 0
        assert init_module(module), 'OBS DirectShow plugin did not initialize'
        props = properties(b'dshow_input')
        try:
            devices = get_property(props, b'video_device_id')
            values = [(list_name(devices, i).decode(), list_value(devices, i).decode()) for i in range(list_count(devices))]
            found = {list_name(devices,i).decode():list_value(devices,i).decode() for i in range(list_count(devices)) if list_name(devices,i).decode().startswith('Localist QA Camera ')}
            assert len(found)==4,found
            report['devicesEnumeratedByOBS']=list(found)
            settings = settings_create()
            device=found['Localist QA Camera 1']
            try:
                settings_string(settings, b'video_device_id', device.encode())
                settings_int(settings, b'res_type', 1)
                modified(devices, settings)
                modes = get_property(props, b'resolution')
                resolutions = [list_name(modes, i).decode() for i in range(list_count(modes))]
                assert '1280x720' in resolutions and '1920x1080' in resolutions, resolutions
                report['resolutions'] = resolutions
                captures = []
                for index,(width,height,fps) in enumerate([(640,480,30),(1280,720,15),(480,640,24),(1920,1080,15)]):
                    settings_string(settings,b'video_device_id',found[f'Localist QA Camera {index+1}'].encode())
                    settings_string(settings, b'resolution', f'{width}x{height}'.encode())
                    settings_int(settings, b'frame_interval', 10000000 // fps)
                    settings_int(settings, b'video_format', 201)  # DShow::VideoFormat::NV12
                    source = create_source(b'dshow_input', b'Localist isolated camera QA', settings)
                    assert source
                    show_source(source)
                    try:
                        timestamps = set()
                        luma = 0
                        deadline = time.monotonic() + 4
                        while time.monotonic() < deadline and len(timestamps) < 8:
                            frame = get_frame(source)
                            if frame:
                                try:
                                    f = frame.contents
                                    assert (f.width, f.height) == (width, height), (f.width, f.height)
                                    timestamps.add(f.timestamp)
                                    if f.data[0]:
                                        luma = c.string_at(f.data[0], 1)[0]
                                        if external:
                                            samples = c.string_at(f.data[0], f.linesize[0]*f.height)[::257]
                                            assert max(samples)-min(samples)>20, 'OBS received blank placeholder video'
                                finally: release_frame(source, frame)
                            time.sleep(.02)
                        assert len(timestamps) >= 8, (width, height, len(timestamps))
                        if not external: assert abs(luma-[81,145,41,235][index])<20,luma
                        captures.append({'width': width, 'height': height, 'fps': fps, 'frames': len(timestamps), 'luma': luma})
                    finally:
                        hide_source(source)
                        release_source(source)
                report['actualOBSFrames'] = captures
            finally:
                settings_release(settings)
        finally:
            destroy_properties(props)
        report['isolated'] = True
        (QA / 'obs-four-results.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
        print('LOCALIST_OBS_CAMERA_OK', json.dumps(report))
    finally:
        if started: shutdown()
        if producer and producer.poll() is None:
            producer.terminate()
            producer.wait(timeout=5)
        for slot,dll in reversed(registered):
            subprocess.run([str(probe),f'--unregister{slot+1}',str(dll)],check=True,**hidden)
        plugin_handle.close()
        handle.close()


if __name__ == '__main__':
    main()
