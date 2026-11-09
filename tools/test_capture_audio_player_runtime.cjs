// Headless synthetic PC audio -> Android AudioTrack/OpenSL ES acceptance test.
// Uses the existing QA emulator. Never opens a physical microphone or camera.
const fs = require('node:fs'), path = require('node:path'), http = require('node:http');
const {execFileSync} = require('node:child_process');
const {chromium} = require('../.runlogs/qa-node/node_modules/playwright');
const {WebSocketServer, WebSocket} = require('../.runlogs/qa-node/node_modules/ws');
const {VM} = require('./capture_vm_qa.cjs');
const out = process.env.LOCALIST_CAPTURE_QA_ROOT || path.resolve(__dirname, '../.runlogs/usb-microphone-live');
const adb = 'C:/Users/MBN/AppData/Local/Android/Sdk/platform-tools/adb.exe';
const serial = 'emulator-5560', port = 45128;
const command = (...args) => execFileSync(adb, ['-s', serial, ...args], {windowsHide: true, encoding: 'utf8'});
const delay = ms => new Promise(r => setTimeout(r, ms));
(async () => {
  const vm = new VM(); await vm.start();
  const browser = await chromium.launch({executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true,
    args: ['--autoplay-policy=no-user-gesture-required', '--disable-features=WebRtcHideLocalIpsWithMdns']});
  const server = http.createServer((req, res) => res.end('<!doctype html><title>Localist audio fixture</title>'));
  const wss = new WebSocketServer({server});
  let hub, heartbeat, client, forwarded = false;
  const pending = [], report = {ok: false, outputs: []};
  const volumeBefore = command('shell', 'settings', 'get', 'system', 'volume_music').trim();
  try {
    await new Promise(r => server.listen(port, '127.0.0.1', r));
    const page = await browser.newPage();
    await page.exposeFunction('sendSignal', data => {
      if (client?.readyState === WebSocket.OPEN) client.send(JSON.stringify(data)); else pending.push(data);
    });
    await page.goto(`http://127.0.0.1:${port}`);
    wss.on('connection', socket => {
      client = socket;
      pending.splice(0).forEach(data => socket.send(JSON.stringify(data)));
      socket.on('message', bytes => page.evaluate(async data => {
        if (data.type === 'answer') {
          await pc.setRemoteDescription(data);
          for (const c of ice) await pc.addIceCandidate(c); ice = [];
        } else if (data.candidate) {
          if (pc.remoteDescription) await pc.addIceCandidate(data.candidate); else ice.push(data.candidate);
        }
      }, JSON.parse(bytes)).catch(() => {}));
      page.evaluate(async () => {
        window.pc?.close(); clearInterval(window.pcmTimer);
        const audio = new AudioContext(), osc = audio.createOscillator(), gain = audio.createGain(), dest = audio.createMediaStreamDestination();
        gain.gain.value = .003; osc.frequency.value = 330;
        osc.connect(gain).connect(dest); osc.start(); await audio.resume();
        window.pc = new RTCPeerConnection({iceServers: []}); window.ice = [];
        pc.onicecandidate = e => {if (e.candidate) window.sendSignal({candidate: e.candidate.toJSON()});};
        dest.stream.getTracks().forEach(t => pc.addTrack(t, dest.stream));
        window.pcm = pc.createDataChannel('localist.pcm.v1', {ordered: false, maxRetransmits: 0});
        let sequence = 0;
        window.pcmTimer = setInterval(() => {
          if (pcm.readyState !== 'open') return;
          const bytes = new ArrayBuffer(1940), v = new DataView(bytes);
          v.setUint32(0, 0x4143504c, true); v.setUint16(4, 1, true); v.setUint16(6, 1, true);
          v.setUint32(8, 48000, true); v.setUint32(12, 960, true); v.setUint32(16, sequence++, true);
          for (let i = 0; i < 960; i++) v.setInt16(20 + 2 * i, Math.round(100 * Math.sin((sequence * 960 + i) * 2 * Math.PI * 330 / 48000)), true);
          pcm.send(bytes);
        }, 20);
        await pc.setLocalDescription(await pc.createOffer());
        window.sendSignal({type: 'offer', sdp: pc.localDescription.sdp});
      }).catch(error => { report.producerError = error.message; });
    });
    command('reverse', `tcp:${port}`, `tcp:${port}`); forwarded = true;
    hub = await vm.eval(vm.library('/capture_hub_service.dart'), 'CaptureHubService.instance');
    await vm.wait(await vm.eval(hub.id, 'start()'));
    const advert = `observe(CaptureAdvertisement(id:'audio-player-runtime',name:'Audio runtime fixture',model:'Synthetic PC',host:'127.0.0.1',port:${port},key:'${'a'.repeat(43)}',camera:false,microphone:true))`;
    await vm.eval(hub.id, advert);
    heartbeat = setInterval(() => vm.eval(hub.id, advert).catch(() => {}), 2000);
    await vm.wait(await vm.eval(hub.id, "Future.wait([for(final r in receivers) if(r.advertisement.id=='audio-player-runtime') configure(r,enabled:true,audio:true)])"));
    const expression = "[for(final r in receivers) if(r.advertisement.id=='audio-player-runtime') {'connected':r.capture.status,'audio':r.capture.remoteStream?.getAudioTracks().length,'video':r.capture.remoteStream?.getVideoTracks().length,'output':r.output.audioDiagnostics,'error':r.outputError,'packets':r.capture.pcmPacketsReceived}]";
    async function waitOutput(backend, pcm) {
      const end = Date.now() + 22000;
      while (Date.now() < end) {
        const rows = await vm.json(hub.id, expression);
        const row = rows[0];
        if (row?.connected === 'connected' && row.audio === 1 && row.video === 0 && !row.error &&
            row.output.frames > 48000 && row.output.error === 0 && (!pcm || row.packets > 20)) return {...row, backend, pcm};
        await delay(250);
      }
      throw Error('Native output did not advance: ' + JSON.stringify(await vm.json(hub.id, expression)));
    }
    report.outputs.push(await waitOutput('audiotrack', false));
    for (const [backend, pcm, gain] of [['opensl', false, -30], ['audiotrack', true, 40], ['opensl', true, 0]]) {
      client.send(JSON.stringify({type: 'control-state', state: {enabled: true, audioUncompressed: pcm}}));
      await delay(150);
      await vm.wait(await vm.eval(hub.id, `Future.wait([for(final r in receivers) if(r.advertisement.id=='audio-player-runtime') configure(r,audioSettings:CaptureAudioSettings(outputMode:'playback',outputBackend:'${backend}',gainDb:${gain},bufferMode:'custom',minBufferMs:20,maxBufferMs:200,uncompressed:${pcm}))])`));
      report.outputs.push(await waitOutput(backend, pcm));
    }
    report.volumeUnchanged = volumeBefore === command('shell', 'settings', 'get', 'system', 'volume_music').trim();
    if (!report.volumeUnchanged) throw Error('Android system audio volume changed');
    report.ok = true;
    console.log('ANDROID_NATIVE_AUDIO_OUTPUTS_OK', JSON.stringify(report));
  } catch (error) {report.error = error.message; throw error;}
  finally {
    clearInterval(heartbeat);
    if (hub) await vm.wait(await vm.eval(hub.id, 'stop()')).catch(() => {});
    if (forwarded) command('reverse', '--remove', `tcp:${port}`);
    await browser.close(); wss.close(); server.close(); vm.socket.close();
    fs.writeFileSync(path.join(out, 'android-native-audio-results.json'), JSON.stringify(report, null, 2));
  }
})().catch(error => { console.error(error.message); process.exitCode = 1; });
