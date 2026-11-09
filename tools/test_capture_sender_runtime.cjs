const fs=require('node:fs'),path=require('node:path');
const {execFileSync}=require('node:child_process');
const {chromium}=require('../.runlogs/qa-node/node_modules/playwright');
const {VM}=require('./capture_vm_qa.cjs');
const out=path.resolve(__dirname,'../.runlogs/multicapture-qa');
const adb='C:/Users/MBN/AppData/Local/Android/Sdk/platform-tools/adb.exe';
const command=(...args)=>execFileSync(adb,['-s','emulator-5560',...args],{windowsHide:true,encoding:'utf8'});
(async()=>{
 const vm=new VM();await vm.start();let sender,web,browser;
 const savedRotation=command('shell','settings','get','system','user_rotation').trim();
 const savedAutomatic=command('shell','settings','get','system','accelerometer_rotation').trim();
 const savedAcceleration=command('emu','sensor','get','acceleration').match(/acceleration\s*=\s*([^\r\n]+)/)?.[1].trim();
 try{
  const hub=await vm.eval(vm.library('/capture_hub_service.dart'),'CaptureHubService.instance');
  await vm.wait(await vm.eval(hub.id,'setEnabled(false)'));
  sender=await vm.eval(hub.id,'sender');
  await vm.wait(await vm.eval(sender.id,'start(const LiveCaptureOptions(width:640,height:480,fps:15,bitrateKbps:750),port:33333)'));
  const session=await vm.json(sender.id,"{'key':signalingKey,'port':signalingPort,'camera':localStream?.getVideoTracks().length,'microphone':localStream?.getAudioTracks().length}");
  if(session.camera!==1||session.microphone!==1)throw Error('Capture tracks missing');
  command('forward','tcp:45108','tcp:33333');
  browser=await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true,
    args:['--autoplay-policy=no-user-gesture-required','--disable-features=WebRtcHideLocalIpsWithMdns']});
  const page=await browser.newPage();await page.goto('http://127.0.0.1:45108/#'+session.key);
  await page.waitForFunction(()=>document.querySelector('video').videoWidth>0,{timeout:20000});
  const size=()=>page.evaluate(()=>({width:video.videoWidth,height:video.videoHeight,frames:video.getVideoPlaybackQuality().totalVideoFrames}));
  await vm.wait(await vm.eval(sender.id,"setOrientation('portrait')"));
  await page.waitForFunction(()=>video.videoHeight>video.videoWidth);const portrait=await size();
  await vm.wait(await vm.eval(sender.id,"setOrientation('landscape')"));
  await page.waitForFunction(()=>video.videoWidth>video.videoHeight);const landscape=await size();
  await vm.wait(await vm.eval(sender.id,"setOrientation('auto')"));
  command('shell','settings','put','system','accelerometer_rotation','0');
  command('shell','settings','put','system','user_rotation','0');
  command('emu','sensor','set','acceleration','0:9.81:0');
  await page.waitForFunction(()=>video.videoHeight>video.videoWidth);const automaticPortrait=await size();
  command('shell','settings','put','system','user_rotation','1');
  command('emu','sensor','set','acceleration','9.81:0:0');
  await page.waitForFunction(()=>video.videoWidth>video.videoHeight);const automaticLandscape=await size();
  const media=await page.evaluate(async()=>({state:peer.connectionState,inbound:[...await peer.getStats()].map(([,s])=>s).filter(s=>s.type==='inbound-rtp').map(s=>({kind:s.kind,bytes:s.bytesReceived,frames:s.framesDecoded}))}));
  if(!media.inbound.some(s=>s.kind==='audio'&&s.bytes>0))throw Error('No inbound audio');
  await vm.wait(await vm.eval(sender.id,'stop()'));await browser.close();browser=null;

  const wifiBefore=command('shell','dumpsys','wifi');
  web=await vm.eval(vm.library('/apple_web_transfer_service.dart'),'AppleWebTransferService.instance');
  await vm.wait(await vm.eval(web.id,"start(paths:[],offeredNames:{},selectedText:'Current LAN only QA',useHotspot:false)"));
  const state=await vm.json(web.id,"{'active':active,'managedHotspot':managedHotspot,'manualHotspotRequired':manualHotspotRequired,'port':port,'path':loopbackTestUri.path}");
  if(!state.active||state.managedHotspot||state.manualHotspotRequired)throw Error(JSON.stringify(state));
  command('forward','tcp:45130','tcp:'+state.port);
  const response=await fetch('http://127.0.0.1:45130'+state.path+'state');const content=await response.json();
  if(content.text!=='Current LAN only QA')throw Error('LAN transfer state not served');
  const wifiAfter=command('shell','dumpsys','wifi');
  const ap=value=>value.match(/curState=([A-Za-z]+State)/)?.[1]||value.match(/mWifiApState[^\n]*/)?.[0]||'not-started';
  if(ap(wifiBefore)!==ap(wifiAfter))throw Error('Wi-Fi AP state changed');
  const result={portrait,landscape,automaticPortrait,automaticLandscape,media,
    lanOnly:{served:true,managedHotspot:state.managedHotspot,manualHotspotRequired:state.manualHotspotRequired,apBefore:ap(wifiBefore),apAfter:ap(wifiAfter)}};
  fs.writeFileSync(path.join(out,'android-sender-runtime.json'),JSON.stringify(result,null,2));
  console.log('ANDROID_ORIENTATION_AND_LAN_OK',JSON.stringify(result));
 }finally{
  if(browser)await browser.close();
  if(sender)await vm.wait(await vm.eval(sender.id,'stop()')).catch(()=>{});
  if(web)await vm.wait(await vm.eval(web.id,'stop()')).catch(()=>{});
  command('shell','settings','put','system','user_rotation',savedRotation);
  command('shell','settings','put','system','accelerometer_rotation',savedAutomatic);
  if(savedAcceleration)command('emu','sensor','set','acceleration',savedAcceleration);
  for(const port of [45108,45130])try{command('forward','--remove','tcp:'+port);}catch(_){}
  vm.socket.close();
 }
})().catch(e=>{console.error(e);process.exitCode=1});
