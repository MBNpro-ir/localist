// Hardware-derived capture settings and linked video/preview orientation.
const fs=require('node:fs'),path=require('node:path');
const {execFileSync}=require('node:child_process');
const {chromium}=require('../.runlogs/qa-node/node_modules/playwright');
const {VM}=require('./capture_vm_qa.cjs');
const out=process.env.LOCALIST_CAPTURE_QA_ROOT || path.resolve(__dirname,'../.runlogs/capture-device-capabilities');
const adb='C:/Users/MBN/AppData/Local/Android/Sdk/platform-tools/adb.exe';
const command=(...args)=>execFileSync(adb,['-s','emulator-5560',...args],{windowsHide:true,encoding:'utf8'});
const pause=ms=>new Promise(r=>setTimeout(r,ms));
(async()=>{
 const vm=new VM();await vm.start();let sender,browser,preview,forwarded=false;
 const rotation=command('shell','settings','get','system','user_rotation').trim();
 const automatic=command('shell','settings','get','system','accelerometer_rotation').trim();
 const acceleration=command('emu','sensor','get','acceleration').match(/acceleration\s*=\s*([^\r\n]+)/)?.[1].trim();
 const sensor=v=>command('emu','sensor','set','acceleration',v);
 try{
  command('shell','settings','put','system','accelerometer_rotation','0');command('shell','settings','put','system','user_rotation','0');sensor('0:9.81:0');
  const hub=await vm.eval(vm.library('/capture_hub_service.dart'),'CaptureHubService.instance');
  await vm.wait(await vm.eval(hub.id,'stop()'));
  await vm.wait(await vm.eval(hub.id,'start()'));
  if(!(await vm.json(hub.id,'enabled')))throw Error('Automatic reception was not restored');
  await vm.wait(await vm.eval(hub.id,'setEnabled(false)')); // Isolated sender fixture only.
  sender=await vm.eval(hub.id,'sender');
  await vm.wait(await vm.eval(sender.id,'start(const LiveCaptureOptions(width:640,height:480,fps:15,bitrateKbps:750,background:false,receiverControls:false),port:33333)'));
  const state=await vm.json(sender.id,"{'key':signalingKey,'camera':options.cameraId,'microphone':options.microphoneId,'background':options.background,'controls':options.receiverControls,'orientation':options.orientation,'capabilities':capabilities.toJson()}");
  preview=await vm.wait(await vm.eval(sender.id,'(() async { final renderer = RTCVideoRenderer(); await renderer.initialize(); renderer.srcObject = localStream; return renderer; })()'));
  if(!state.camera||!state.microphone||!state.background||!state.controls||state.orientation!=='landscape'||!state.capabilities.modes.length)throw Error('Capture defaults/device selection failed');
  command('forward','tcp:45108','tcp:33333');
  forwarded=true;
  browser=await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true,
    args:['--autoplay-policy=no-user-gesture-required','--disable-features=WebRtcHideLocalIpsWithMdns']});
  const page=await browser.newPage();await page.goto('http://127.0.0.1:45108/#'+state.key);
  await page.waitForFunction(()=>video.videoWidth>0);
  const size=()=>page.evaluate(()=>({width:video.videoWidth,height:video.videoHeight,frames:video.getVideoPlaybackQuality().totalVideoFrames}));
  const results=[];
  for(const [mode,poses] of [['auto',[['0:9.81:0',true],['9.81:0:0',false],['0:-9.81:0',true],['-9.81:0:0',false]]],
    ['landscape',[['0:9.81:0',false],['9.81:0:0',false]]],['portrait',[['0:9.81:0',true],['9.81:0:0',true]]]]){
    await vm.wait(await vm.eval(sender.id,`setOrientation('${mode}')`));
    for(const [pose,portrait] of poses){sensor(pose);await pause(500);
      await page.waitForFunction(p=>video.videoWidth>0 && (video.videoHeight>video.videoWidth)===p,portrait,{timeout:15000});
      let local;
      for(let i=0;i<40;i++){
        const width=Number((await vm.eval(preview.id,'videoWidth')).valueAsString),height=Number((await vm.eval(preview.id,'videoHeight')).valueAsString);
        local={width,height};if(width>0&&(height>width)===portrait)break;await pause(100);
      }
      if(!local.width||(local.height>local.width)!==portrait)throw Error('Local preview did not follow '+mode);
      results.push({mode,pose,...await size(),preview:local});}
  }
  const selected=state.capabilities.modes.find(m=>m.width>640&&m.width<=1280)||state.capabilities.modes[0];
  await vm.wait(await vm.eval(sender.id,`requestCaptureControl({'width':${selected.width},'height':${selected.height},'fps':${Math.max(selected.minFps,Math.min(15,selected.maxFps))}})`));
  const controls=await vm.json(sender.id,"{'width':options.width,'height':options.height,'camera':options.cameraId,'microphone':options.microphoneId,'range':capabilities.toJson(),'control':captureControlState['enabled']}");
  if(controls.width!==selected.width||controls.height!==selected.height||!controls.control)throw Error('Device-specific control failed');
  const videoFrames=(await size()).frames;await pause(1000);if((await size()).frames<=videoFrames)throw Error('Video stopped after mode change');
  delete state.key;
  fs.writeFileSync(path.join(out,'device-runtime.json'),JSON.stringify({state,results,controls},null,2));
  console.log('DEVICE_MODES_AND_LINKED_ORIENTATION_OK',JSON.stringify({camera:state.camera,microphone:state.microphone,range:state.capabilities.maxBitrateKbps,results,controls}));
 }finally{
  if(browser)await browser.close();if(preview)await vm.wait(await vm.eval(preview.id,'dispose()')).catch(()=>{});if(sender)await vm.wait(await vm.eval(sender.id,'stop()')).catch(()=>{});
  if(acceleration)sensor(acceleration);command('shell','settings','put','system','user_rotation',rotation);command('shell','settings','put','system','accelerometer_rotation',automatic);
  if(forwarded)try{command('forward','--remove','tcp:45108');}catch(_){}vm.socket.close();
 }
})().catch(e=>{console.error(e);process.exitCode=1});
