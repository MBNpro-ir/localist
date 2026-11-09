// Four real browser WebRTC senders -> native Windows AudioTrack sinks -> QA pipes.
// No kernel driver is loaded and no system audio settings/devices are changed.
const fs = require('node:fs'), path = require('node:path'), http = require('node:http'), net = require('node:net');
const {spawn} = require('node:child_process');
const {chromium} = require('../.runlogs/qa-node/node_modules/playwright');
const {WebSocketServer, WebSocket} = require('../.runlogs/qa-node/node_modules/ws');
const root = path.resolve(__dirname, '..'), qa = path.join(root, '.runlogs/localist-microphone');
const delay = ms => new Promise(r => setTimeout(r, ms));
const bundle = path.join(root, 'build/windows-capture-receiver-qa/runner/Release');

(async () => {
  const browser = await chromium.launch({executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true,
    args: ['--autoplay-policy=no-user-gesture-required', '--disable-features=WebRtcHideLocalIpsWithMdns']});
  const servers = [], signals = [], pipes = [], sockets = new Set(), samples = [[],[],[],[]], resets = [0,0,0,0];
  let receiver;
  const ready = path.join(qa, 'windows-receive-ready.json'), stop = path.join(qa, 'receiver-consumed');
  fs.rmSync(ready, {force:true}); fs.rmSync(stop, {force:true});
  try {
    const senders = [];
    for (let slot = 0; slot < 4; slot++) {
      const server = http.createServer((req,res) => res.end('<!doctype html><canvas width="320" height="240"></canvas>'));
      await new Promise(r => server.listen(0, '127.0.0.1', r)); servers.push(server);
      const page = await browser.newPage(); await page.goto(`http://127.0.0.1:${server.address().port}`);
      const wss = new WebSocketServer({server}); signals.push(wss);
      // Each reconnect creates its own RTC peer and retains its own callback.
      wss.on('connection', socket => {
        const id = Math.random().toString(36).slice(2);
        socket.on('message', message => page.evaluate(async ({id,data}) => {
          const state = window.peers[id];
          if (data.type === 'answer') { await state.pc.setRemoteDescription(data); for (const c of state.ice) await state.pc.addIceCandidate(c); state.ice=[]; }
          else if (data.candidate) { if (state.pc.remoteDescription) await state.pc.addIceCandidate(data.candidate); else state.ice.push(data.candidate); }
        }, {id,data:JSON.parse(message)}).catch(() => {}));
        socket.on('close', () => page.evaluate(id => { window.peers?.[id]?.pc.close(); delete window.peers?.[id]; }, id).catch(() => {}));
        page.evaluate(async ({id,slot}) => {
          if (!window.stream) {
            const canvas = document.querySelector('canvas'), ctx = canvas.getContext('2d');
            setInterval(() => { ctx.fillStyle=['#f00','#0f0','#00f','#ff0'][slot];ctx.fillRect(0,0,320,240);ctx.fillStyle='#fff';ctx.fillText('Localist '+slot+' '+Date.now(),10,25); }, 50);
            const audio = new AudioContext(), osc = audio.createOscillator(), dest = audio.createMediaStreamDestination();
            osc.frequency.value=220+slot*110; osc.connect(dest); osc.start(); await audio.resume();
            window.stream=canvas.captureStream(15); window.stream.addTrack(dest.stream.getAudioTracks()[0]);window.peers={};
          }
          const pc = new RTCPeerConnection({iceServers:[]});window.peers[id]={pc,ice:[]};
          pc.onicecandidate=e=>{if(e.candidate)window.signal({id,data:{candidate:e.candidate.toJSON()}});};
          window.stream.getTracks().forEach(t=>pc.addTrack(t,window.stream));
          await pc.setLocalDescription(await pc.createOffer());window.signal({id,data:{type:'offer',sdp:pc.localDescription.sdp}});
        }, {id,slot}).catch(() => {});
        // ExposeFunction is installed once per page below, before the receiver connects.
        socket.localistId=id;
      });
      await page.exposeFunction('signal', ({id,data}) => {
        for (const client of wss.clients) if(client.localistId===id && client.readyState===WebSocket.OPEN) client.send(JSON.stringify(data));
      });
      senders.push({port:server.address().port,key:'a'.repeat(43)});
    }
    fs.writeFileSync(path.join(qa,'sender-session.json'),JSON.stringify({senders,requireMicrophones:true}));
    receiver = spawn(path.join(bundle,'Localist.exe'),[qa],{cwd:bundle,windowsHide:true,stdio:'ignore'});
    for (let slot=0;slot<4;slot++) {
      const pipe = net.createServer(socket => {
        sockets.add(socket);let pending=Buffer.alloc(0);
        socket.on('close',()=>sockets.delete(socket));
        socket.on('error',()=>{});
        socket.on('data',chunk=>{
          pending=Buffer.concat([pending,chunk]);
          while(pending.length>=32) {
            const h=Array.from({length:8},(_,i)=>pending.readUInt32LE(i*4));
            if(h[0]!==0x4c4d4943 || h[1]!==1 || h[2]!==slot || h[3]>960 || h[4]!==48000 || h[5]!==1 || h[6]!==16 || h[7]>1) throw Error('Invalid native PCM header '+h);
            const length=32+h[3]*2;if(pending.length<length)break;
            if(h[7]===1)resets[slot]++;
            // Bound retained samples while still draining the entire pipe.
            for(let i=0;i<h[3] && samples[slot].length<480000;i++)samples[slot].push(pending.readInt16LE(32+i*2));
            pending=pending.subarray(length);
          }
        });
      });
      await new Promise((resolve,reject)=>{pipe.once('error',reject);pipe.listen(`\\\\.\\pipe\\LocalistAudioQA-${receiver.pid}-${slot}`,resolve);});pipes.push(pipe);
    }
    const end=Date.now()+180000;
    while(!fs.existsSync(ready)&&Date.now()<end){if(receiver.exitCode!==null)throw Error('Receiver exited '+receiver.exitCode);await delay(200);}
    const report=JSON.parse(fs.readFileSync(ready,'utf8'));
    if(!report.ok)throw Error(JSON.stringify(report));
    const tones=samples.map((pcm,slot)=>{
      if(pcm.length<48000)throw Error(`Insufficient native PCM in slot ${slot}: ${pcm.length}`);
      // Ignore codec startup/reconnect transients and measure a one-second window.
      const data=pcm.slice(-48000);let energy=0,crossings=0;
      for(let i=0;i<data.length;i++){energy+=data[i]*data[i];if(i&&data[i-1]<0&&data[i]>=0)crossings++;}
      const frequency=crossings*48000/data.length,rms=Math.sqrt(energy/data.length),expected=220+slot*110;
      if(rms<100 || Math.abs(frequency-expected)>4)throw Error(`Wrong/silent microphone ${slot}: ${frequency}Hz RMS=${rms}`);
      if(!resets[slot])throw Error(`Slot ${slot} did not detach/reset across reconnect`);
      return {slot:slot+1,frames:pcm.length,frequency,rms,resets:resets[slot]};
    });
    fs.writeFileSync(path.join(qa,'runtime-results.json'),JSON.stringify({ok:true,tones,receivers:report.receivers},null,2));
    console.log('FOUR_WINDOWS_NATIVE_MICROPHONES_WEBRTC_QA_OK',JSON.stringify(tones));
  } finally {
    fs.writeFileSync(stop,'done');
    if(receiver){for(let i=0;i<100&&receiver.exitCode===null;i++)await delay(100);if(receiver.exitCode===null)receiver.kill();}
    for(const socket of sockets)socket.destroy();
    await Promise.all(pipes.map(p=>new Promise(r=>p.close(r))));
    await browser.close();for(const wss of signals)for(const socket of wss.clients)socket.terminate();
    await Promise.all(servers.map(s=>new Promise(r=>s.close(r))));
  }
})().catch(e=>{console.error(e);process.exitCode=1;});
