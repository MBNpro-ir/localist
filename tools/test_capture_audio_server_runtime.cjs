// Actual Android microphone-only sender with headless Player controls.
// QA emulator only: no physical camera/microphone and no speaker monitoring.
const fs = require('node:fs'), path = require('node:path');
const {execFileSync} = require('node:child_process');
const {chromium} = require('../.runlogs/qa-node/node_modules/playwright');
const {VM} = require('./capture_vm_qa.cjs');
const out = process.env.LOCALIST_CAPTURE_QA_ROOT || path.resolve(__dirname, '../.runlogs/usb-microphone-live');
const adb = 'C:/Users/MBN/AppData/Local/Android/Sdk/platform-tools/adb.exe';
const command = (...args) => execFileSync(adb, ['-s', 'emulator-5560', ...args], {windowsHide: true, encoding: 'utf8'});
(async () => {
  const vm = new VM(); await vm.start();
  let sender, browser, page, forwarded = false;
  const result = {ok: false};
  try {
    sender = await vm.eval(vm.library('/capture_hub_service.dart'), 'CaptureHubService.instance.sender');
    await vm.wait(await vm.eval(sender.id, 'start(const LiveCaptureOptions(camera:false,microphone:true),port:33333)'));
    const source = await vm.json(sender.id, "{'key':signalingKey,'audio':localStream?.getAudioTracks().length,'video':localStream?.getVideoTracks().length}");
    if (source.audio !== 1 || source.video !== 0) throw Error('Audio-only capture created incorrect tracks');
    command('forward', 'tcp:45108', 'tcp:33333'); forwarded = true;
    browser = await chromium.launch({executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true,
      args: ['--autoplay-policy=no-user-gesture-required', '--disable-features=WebRtcHideLocalIpsWithMdns']});
    page = await browser.newPage();
    page.on('console', message => {if(message.type()==='error')console.error(message.text());});
    await page.goto('http://127.0.0.1:45108/');
    await page.evaluate(() => stop());
    await page.evaluate(key => {
      window.controlState = {}; window.requestNumber = 0; window.qaPending = new Map(); window.packets = 0;
      window.pc = new RTCPeerConnection({iceServers: []}); const ice = [];
      window.signal = new WebSocket(`ws://127.0.0.1:45108/signal?key=${key}`);
      signal.onclose = event => {window.testError = `Socket closed: ${event.code} ${event.reason}`;};
      pc.onicecandidate = e => {if (e.candidate) signal.send(JSON.stringify({candidate: e.candidate.toJSON()}));};
      pc.ondatachannel = e => {e.channel.onmessage = () => window.packets++;};
      let queue = Promise.resolve();
      signal.onmessage = e => {queue = queue.then(async () => {
        const data = JSON.parse(e.data);
        if (data.type === 'offer') {
          await pc.setRemoteDescription(data);
          for (const c of ice) await pc.addIceCandidate(c); ice.length = 0;
          await pc.setLocalDescription(await pc.createAnswer());
          signal.send(JSON.stringify({type: 'answer', sdp: pc.localDescription.sdp}));
        } else if (data.candidate) {
          if (pc.remoteDescription) await pc.addIceCandidate(data.candidate); else ice.push(data.candidate);
        } else if (data.type === 'control-state') window.controlState = data.state;
        else if (data.type === 'control-result') {
          const item = qaPending.get(data.id); qaPending.delete(data.id);
          if (data.error) item?.reject(Error(data.error)); else item?.resolve(true);
        }
      }).catch(error => {window.testError = error.message;});};
      window.change = command => new Promise((resolve, reject) => {
        const id = ++requestNumber; qaPending.set(id, {resolve, reject});
        signal.send(JSON.stringify({type: 'control', id, command}));
        setTimeout(() => {if (qaPending.delete(id)) reject(Error('Control timed out'));}, 15000);
      });
    }, source.key);
    await page.waitForFunction(() => pc.connectionState === 'connected' && controlState.enabled, {timeout: 25000});
    await vm.wait(await vm.eval(sender.id, "requestCaptureControl({'audioGainDb':-30.0,'audioContinuous':false})"));
    await page.waitForFunction(() => controlState.audioGainDb === -30 && controlState.audioContinuous === false);
    result.localApplied = await page.evaluate(() => ({gain: controlState.audioGainDb, continuous: controlState.audioContinuous}));
    await page.evaluate(() => change({audioGainDb: 40, audioContinuous: true, audioUncompressed: true, noise: false, echo: false, gain: false}));
    await page.waitForFunction(() => packets > 20 && controlState.audioGainDb === 40 && controlState.enabled);
    result.playerApplied = await vm.json(sender.id, "{'gain':options.audioSettings.gainDb,'pcm':options.audioSettings.uncompressed,'noise':options.noiseSuppression,'echo':options.echoCancellation,'agc':options.autoGain,'port':signalingPort}");
    await page.evaluate(() => change({microphone: 0}));
    await page.evaluate(() => change({audioGainDb: 0, audioUncompressed: false, noise: true, echo: true, gain: true}));
    await page.waitForFunction(() => controlState.audioGainDb === 0 && controlState.audioUncompressed === false && controlState.enabled);
    result.restored = await vm.json(sender.id, "{'gain':options.audioSettings.gainDb,'audio':localStream?.getAudioTracks().length,'video':localStream?.getVideoTracks().length,'port':signalingPort,'delay':latencyHistory,'error':error}");
    result.player = await page.evaluate(async () => ({state: pc.connectionState, packets,
      inbound: [...await pc.getStats()].map(([,s]) => s).filter(s => s.type === 'inbound-rtp').map(s => ({kind:s.kind, bytes:s.bytesReceived}))}));
    if (result.playerApplied.gain !== 40 || result.restored.port !== 33333 || result.restored.video !== 0 || result.player.state !== 'connected' || result.restored.error) throw Error('Live reconfiguration changed the session or failed');
    result.ok = true; console.log('ANDROID_LIVE_SERVER_PLAYER_CONTROLS_OK', JSON.stringify(result));
  } catch (error) {
    result.error = error.message;
    if(page) result.browser = await page.evaluate(() => ({connection:window.pc?.connectionState, ice:window.pc?.iceConnectionState, state:window.controlState, error:window.testError, socket:window.signal?.readyState})).catch(() => null);
    if(sender) result.sender = await vm.json(sender.id,"{'status':status,'error':error,'viewers':viewers,'controls':captureControlState}").catch(() => null);
    console.error(JSON.stringify(result)); throw error;
  }
  finally {
    if (browser) await browser.close();
    if (sender) await vm.wait(await vm.eval(sender.id, 'stop()')).catch(() => {});
    if (forwarded) command('forward', '--remove', 'tcp:45108');
    vm.socket.close();
    fs.writeFileSync(path.join(out, 'android-live-server-results.json'), JSON.stringify(result, null, 2));
  }
})().catch(error => {console.error(error.message); process.exitCode = 1;});
