// Actual Android WebRTC reception from four independent synthetic browser senders.
const fs=require('node:fs'),path=require('node:path'),http=require('node:http');
const {execFileSync}=require('node:child_process');
const {chromium}=require('../.runlogs/qa-node/node_modules/playwright');
const {WebSocket,WebSocketServer}=require('../.runlogs/qa-node/node_modules/ws');
const root=path.resolve(__dirname,'..'),out=path.join(root,'.runlogs/multicapture-qa');
const adb='C:/Users/MBN/AppData/Local/Android/Sdk/platform-tools/adb.exe';
const pause=ms=>new Promise(r=>setTimeout(r,ms));
const {VM}=require('./capture_vm_qa.cjs');
(async()=>{
 const vm=new VM();await vm.start();
 const browser=await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true,
   args:['--autoplay-policy=no-user-gesture-required','--disable-features=WebRtcHideLocalIpsWithMdns']});
 const servers=[],connections=[],pages=[];
 let hub,heartbeat;const adverts=[];
 try{
  hub=await vm.eval(vm.library('/capture_hub_service.dart'),'CaptureHubService.instance');
  await vm.wait(await vm.eval(hub.id,'start()'));
  await vm.wait(await vm.eval(hub.id,'setEnabled(true)'));
  heartbeat=setInterval(()=>Promise.all(adverts.map(expression=>vm.eval(hub.id,expression))).catch(()=>{}),2000);
  for(let i=0;i<4;i++){
   const port=45121+i;
   const server=http.createServer((req,res)=>res.end('<!doctype html><canvas width="320" height="240"></canvas>'));
   await new Promise(r=>server.listen(port,'0.0.0.0',r));servers.push(server);
   const page=await browser.newPage();pages.push(page);
   let client;const pending=[];
   await page.exposeFunction('sendSignal',message=>{if(client?.readyState===WebSocket.OPEN)client.send(JSON.stringify(message));else pending.push(message);});
   await page.goto(`http://127.0.0.1:${port}`);
   const wss=new WebSocketServer({server});connections.push(wss);
   wss.on('connection',socket=>{
    client=socket;pending.splice(0).forEach(m=>client.send(JSON.stringify(m)));
    socket.on('message',m=>page.evaluate(async data=>{
      if(data.type==='answer'){await pc.setRemoteDescription(data);for(const c of ice)await pc.addIceCandidate(c);ice=[];}
      else if(data.candidate){if(pc.remoteDescription)await pc.addIceCandidate(data.candidate);else ice.push(data.candidate);}
    },JSON.parse(m)).catch(()=>{}));
    page.evaluate(async index=>{
      const canvas=document.querySelector('canvas'),ctx=canvas.getContext('2d');
      const paint=()=>{ctx.fillStyle=['#ff0000','#00ff00','#0000ff','#ffff00'][index];ctx.fillRect(0,0,320,240);ctx.fillStyle='#fff';ctx.fillText('Sender '+(index+1)+' '+Date.now(),10,20);};paint();setInterval(paint,50);
      const video=canvas.captureStream(15);const audio=new AudioContext();const osc=audio.createOscillator(),dest=audio.createMediaStreamDestination();osc.frequency.value=220+index*110;osc.connect(dest);osc.start();await audio.resume();
      window.pc=new RTCPeerConnection({iceServers:[]});window.ice=[];
      pc.onicecandidate=e=>{if(e.candidate)window.sendSignal({candidate:e.candidate.toJSON()});};
      [...video.getTracks(),...dest.stream.getTracks()].forEach(t=>pc.addTrack(t,video));
      await pc.setLocalDescription(await pc.createOffer());window.sendSignal({type:'offer',sdp:pc.localDescription.sdp});
    },i).catch(e=>console.error('Producer',i,e.message));
   });
   execFileSync(adb,['-s','emulator-5560','reverse',`tcp:${port}`,`tcp:${port}`],{windowsHide:true});
   const key='a'.repeat(43);
   const expression=`observe(CaptureAdvertisement(id:'runtime-sender-id-${i}',name:'Runtime sender ${i+1}',model:'Synthetic WebRTC',host:'127.0.0.1',port:${port},key:'${key}',camera:true,microphone:true))`;
   adverts.push(expression);const result=await vm.eval(hub.id,expression);
   if(result.kind==='Error')throw Error(JSON.stringify(result));
  }
  // Prior QA runs deliberately disable one fixture peer. Reset only these
  // fixture switches so persistence does not make a repeat run skip a sender.
  await vm.wait(await vm.eval(hub.id,'Future.wait([for(final r in receivers) configure(r,enabled:true,video:true,audio:true)])'));
  const end=Date.now()+30000;let result;
  while(Date.now()<end){result=await vm.json(hub.id,"[for(final r in receivers) {'slot':r.slot,'status':r.capture.status,'video':r.capture.remoteStream?.getVideoTracks().length??0,'audio':r.capture.remoteStream?.getAudioTracks().length??0,'width':r.renderer.videoWidth,'height':r.renderer.videoHeight,'error':r.error,'mediaError':r.capture.error,'working':r.working}]");
    if(result.length===4 && result.every(r=>r.video===1&&r.audio===1&&r.width>0))break;await pause(400);}
  if(!result||result.length!==4||result.some(r=>r.width<=0))throw Error(JSON.stringify(result));
  const stats=await Promise.all(pages.map(p=>p.evaluate(async()=>[...await pc.getStats()].map(([,s])=>s).filter(s=>s.type==='outbound-rtp').map(s=>({kind:s.kind,bytes:s.bytesSent,frames:s.framesEncoded})))));
  if(stats.some(s=>!s.some(t=>t.kind==='video'&&t.bytes>0)||!s.some(t=>t.kind==='audio'&&t.bytes>0)))throw Error(JSON.stringify(stats));
  await vm.wait(await vm.eval(hub.id,'configure(receivers.first,enabled:false)'));
  const isolated=await vm.json(hub.id,'[for(final r in receivers) r.capture.receiving]');
  if(JSON.stringify(isolated)!=='[false,true,true,true]')throw Error(JSON.stringify(isolated));
  fs.writeFileSync(path.join(out,'android-four-runtime.json'),JSON.stringify({receivers:result,outbound:stats,independentStop:isolated},null,2));
  console.log('ANDROID_FOUR_REAL_WEBRTC_OK',JSON.stringify({receivers:result,independentStop:isolated}));
 }finally{
  clearInterval(heartbeat);
  if(hub)await vm.wait(await vm.eval(hub.id,'setEnabled(false)')).catch(()=>{});
  await browser.close();connections.forEach(s=>s.clients.forEach(c=>c.terminate()));
  await Promise.all(servers.map(s=>new Promise(r=>s.close(r))));
  for(let i=0;i<4;i++)execFileSync(adb,['-s','emulator-5560','reverse','--remove',`tcp:${45121+i}`],{windowsHide:true});
  vm.socket.close();
 }
})().catch(e=>{console.error(e);process.exitCode=1});
