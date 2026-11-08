const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const {chromium} = require('../.runlogs/qa-node/node_modules/playwright');
(async () => {
  const server = http.createServer((req,res) => res.end('<!doctype html><title>Localist four-camera QA</title>'));
  await new Promise(resolve => server.listen(0,'127.0.0.1',resolve));
  const browser = await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',
    headless:true,args:['--use-fake-ui-for-media-stream','--autoplay-policy=no-user-gesture-required']});
  try {
    const page=await browser.newPage();
    await page.goto(`http://127.0.0.1:${server.address().port}`);
    const result=await page.evaluate(async()=>{
      const devices=await navigator.mediaDevices.enumerateDevices();
      const cameras=devices.filter(d=>d.kind==='videoinput' && /^Localist QA Camera [1-4]$/.test(d.label)).sort((a,b)=>a.label.localeCompare(b.label));
      if(cameras.length!==4) throw Error(`Expected four cameras, found ${cameras.length}`);
      const streams=await Promise.all(cameras.map(d=>navigator.mediaDevices.getUserMedia({video:{deviceId:{exact:d.deviceId},width:640,height:480},audio:false})));
      try {
        const videos=await Promise.all(streams.map(async stream=>{const video=document.createElement('video');video.srcObject=stream;video.muted=true;await video.play();return video;}));
        await new Promise(resolve=>setTimeout(resolve,1000));
        return videos.map((video,index)=>{
          const canvas=document.createElement('canvas');canvas.width=640;canvas.height=480;
          const ctx=canvas.getContext('2d');ctx.drawImage(video,0,0,640,480);
          return {name:cameras[index].label,frames:video.getVideoPlaybackQuality().totalVideoFrames,
            rgb:[...ctx.getImageData(320,240,1,1).data].slice(0,3)};
        });
      } finally {streams.forEach(s=>s.getTracks().forEach(t=>t.stop()));}
    });
    const expected=[[255,0,0],[0,255,0],[0,0,255],[255,255,255]];
    for(let i=0;i<4;i++) if(result[i].frames<5 || result[i].rgb.some((v,c)=>Math.abs(v-expected[i][c])>30)) throw Error(JSON.stringify(result));
    fs.writeFileSync(path.join(__dirname,'../.runlogs/multicapture-qa/browser-four-results.json'),JSON.stringify(result,null,2));
    console.log(JSON.stringify(result));
  } finally {await browser.close();await new Promise(resolve=>server.close(resolve));}
})().catch(e=>{console.error(e);process.exitCode=1});
