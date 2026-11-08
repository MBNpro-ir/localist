// Physical accelerometer rotation with Android auto-rotate explicitly disabled.
const fs=require('node:fs'),path=require('node:path');
const {execFileSync}=require('node:child_process');
const {chromium}=require('../.runlogs/qa-node/node_modules/playwright');
const {VM}=require('./capture_vm_qa.cjs');
const out=process.env.LOCALIST_CAPTURE_QA_ROOT || path.resolve(__dirname,'../.runlogs/capture-rotation-usb-fix');
const adb='C:/Users/MBN/AppData/Local/Android/Sdk/platform-tools/adb.exe';
const command=(...args)=>execFileSync(adb,['-s','emulator-5560',...args],{windowsHide:true,encoding:'utf8'});
const pause=ms=>new Promise(r=>setTimeout(r,ms));
(async()=>{
 const vm=new VM();await vm.start();let sender,browser;
 const savedRotation=command('shell','settings','get','system','user_rotation').trim();
 const savedAutomatic=command('shell','settings','get','system','accelerometer_rotation').trim();
 const acceleration=command('emu','sensor','get','acceleration').match(/acceleration\s*=\s*([^\r\n]+)/)?.[1].trim();
 const setPhysical=value=>command('emu','sensor','set','acceleration',value);
 try{
  command('shell','settings','put','system','accelerometer_rotation','0');
  command('shell','settings','put','system','user_rotation','0');
  setPhysical('0:9.81:0');
  const hub=await vm.eval(vm.library('/capture_hub_service.dart'),'CaptureHubService.instance');
  await vm.wait(await vm.eval(hub.id,'setEnabled(false)'));
  sender=await vm.eval(hub.id,'sender');
  await vm.wait(await vm.eval(sender.id,'start(const LiveCaptureOptions(width:640,height:480,fps:15,bitrateKbps:750),port:33333)'));
  const session=await vm.json(sender.id,"{'key':signalingKey,'port':signalingPort}");
  command('forward','tcp:45108','tcp:33333');
  browser=await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true,
   args:['--autoplay-policy=no-user-gesture-required','--disable-features=WebRtcHideLocalIpsWithMdns']});
  const page=await browser.newPage();await page.goto('http://127.0.0.1:45108/#'+session.key);
  const size=()=>page.evaluate(()=>({width:video.videoWidth,height:video.videoHeight,frames:video.getVideoPlaybackQuality().totalVideoFrames}));
  const results=[];
  for(const [name,sensor,portrait] of [['portrait','0:9.81:0',true],['landscape-left','9.81:0:0',false],
    ['portrait-inverted','0:-9.81:0',true],['landscape-right','-9.81:0:0',false]]){
    setPhysical(sensor);
    await page.waitForFunction(p=>video.videoWidth>0 && (video.videoHeight>video.videoWidth)===p,portrait,{timeout:20000});
    results.push({name,...await size()});
    if(command('shell','settings','get','system','user_rotation').trim()!=='0')throw Error('Display lock was changed');
  }
  for(const [mode,portrait] of [['portrait',true],['landscape',false]]){
    await vm.wait(await vm.eval(sender.id,`setOrientation('${mode}')`));
    await page.waitForFunction(p=>(video.videoHeight>video.videoWidth)===p,portrait);
    for(const sensor of ['0:9.81:0','9.81:0:0']){
      setPhysical(sensor);await pause(600);
      const value=await size();if((value.height>value.width)!==portrait)throw Error('Orientation lock failed');
    }
    results.push({name:mode+'-lock',...await size()});
  }
  const stats=await page.evaluate(async()=>[...await peer.getStats()].map(([,s])=>s).filter(s=>s.type==='inbound-rtp').map(s=>({kind:s.kind,bytes:s.bytesReceived,frames:s.framesDecoded})));
  if(!stats.some(s=>s.kind==='video'&&s.frames>6)||!stats.some(s=>s.kind==='audio'&&s.bytes>0))throw Error('RTP data missing');
  fs.writeFileSync(path.join(out,'physical-rotation-runtime.json'),JSON.stringify({displayLocked:true,results,stats},null,2));
  console.log('PHYSICAL_ROTATION_LOCKED_DISPLAY_OK',JSON.stringify(results));
 }finally{
  if(browser)await browser.close();
  if(sender)await vm.wait(await vm.eval(sender.id,'stop()')).catch(()=>{});
  if(acceleration)setPhysical(acceleration);
  command('shell','settings','put','system','user_rotation',savedRotation);
  command('shell','settings','put','system','accelerometer_rotation',savedAutomatic);
  try{command('forward','--remove','tcp:45108');}catch(_){}
  vm.socket.close();
 }
})().catch(e=>{console.error(e);process.exitCode=1});
