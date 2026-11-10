// Real Dart web-transfer host and two isolated headless browser clients.
const fs = require('node:fs'), path = require('node:path'), http = require('node:http');
const assert = require('node:assert/strict');
const {spawn} = require('node:child_process');
const root = path.resolve(__dirname, '..');
const {chromium} = require(path.join(root, '.runlogs/qa-node/node_modules/playwright'));
const out = path.join(root, '.runlogs/manual-review-20261110/browser');
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
async function until(check, timeout = 40000) {
  const end = Date.now() + timeout;
  while (Date.now() < end) {if (await check()) return; await pause(100);}
  throw Error('Browser transfer acceptance timed out');
}
(async () => {
  fs.mkdirSync(out, {recursive:true});
  for (const name of ['ready.json','done']) fs.rmSync(path.join(out,name), {force:true});
  const browser = await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true});
  const errors=[], report={}; let host, viewerHost;
  try {
    host = spawn('C:/dev/flutter/bin/cache/dart-sdk/bin/dart.exe', ['C:/dev/flutter/bin/cache/flutter_tools.snapshot','test','--no-pub','test/web_transfer_browser_app.dart','--reporter','expanded'], {cwd:root,windowsHide:true});
    const log=fs.createWriteStream(path.join(out,'server.log')); host.stdout.pipe(log); host.stderr.pipe(log,{end:false});
    await until(()=>fs.existsSync(path.join(out,'ready.json')));
    const {url}=JSON.parse(fs.readFileSync(path.join(out,'ready.json'),'utf8'));
    const fa=await browser.newContext({locale:'en-US',viewport:{width:390,height:844},acceptDownloads:true});
    const en=await browser.newContext({locale:'fa-IR',viewport:{width:1280,height:900},acceptDownloads:true});
    const a=await fa.newPage(), b=await en.newPage();
    for(const page of [a,b]) page.on('pageerror',error=>errors.push(error.message));
    await a.goto(url+'?lang=fa'); await b.goto(url+'?lang=en');
    await a.waitForFunction(()=>peer&&lastState); await b.waitForFunction(()=>peer&&lastState);
    assert.equal(await a.locator('html').getAttribute('lang'),'fa');
    assert.equal(await a.locator('html').getAttribute('dir'),'rtl');
    assert.equal(await b.locator('html').getAttribute('lang'),'en');
    assert.equal(await b.locator('#heading').textContent(),'Localist Web Transfer');
    assert.equal(await a.locator('#heading').textContent(),'انتقال فایل لوکالیست');
    assert.equal(await a.locator('#downloads strong').textContent(),'_host_.txt');
    const receiverId=await b.evaluate(()=>peer.id);
    await a.waitForFunction(id=>[...document.querySelector('#target').options].some(option=>option.value===id),receiverId);
    await a.locator('#target').selectOption(receiverId);
    const contents=Buffer.from('synthetic browser relay payload \u0633\u0644\u0627\u0645');
    await a.locator('#files').setInputFiles({name:'relay-سلام.txt',mimeType:'text/plain',buffer:contents});
    await a.locator('#send').click();
    await a.waitForFunction(()=>document.querySelector('#status').textContent.includes('فایل‌ها روی میزبان آماده'));
    await b.locator('#inbox strong').waitFor();
    const received=b.waitForEvent('download'); await b.locator('#inbox button').first().click();
    const download=await received;
    assert.deepEqual(fs.readFileSync(await download.path()),contents);
    const hostDownload=a.waitForEvent('download'); await a.locator('#downloads button').first().click();
    assert.equal(fs.readFileSync(await (await hostDownload).path(),'utf8'),'host download fixture');
    await a.locator('#language').click();
    assert.equal(await a.locator('html').getAttribute('lang'),'en');
    await a.locator('#language').click();
    assert.equal(await a.locator('#heading').textContent(),'انتقال فایل لوکالیست');
    for(const width of [320,390,1280]) {
      await a.setViewportSize({width,height:900});
      assert(await a.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));
    }
    report.transfer={browserToBrowser:true,hostDownload:true,contentVerified:true,languages:['fa','en'],queryOverridesBrowserLocale:true,widths:[320,390,1280]};
    // Inspect the actual camera viewer asset without starting any media source.
    viewerHost=http.createServer((req,res)=>{res.setHeader('Content-Type','text/html');res.end(fs.readFileSync(path.join(root,'assets/live_capture.html')));});
    await new Promise(resolve=>viewerHost.listen(0,'127.0.0.1',resolve));
    const viewer=await fa.newPage(); viewer.on('pageerror',error=>errors.push(error.message));
    for(const lang of ['fa','en']) {
      await viewer.goto(`http://127.0.0.1:${viewerHost.address().port}/?lang=${lang}`);
      assert.equal(await viewer.locator('html').getAttribute('lang'),lang);
      assert.equal(await viewer.locator('#retry').textContent(),lang==='fa'?'اتصال دوباره':'Reconnect');
      assert.equal(await viewer.locator('#state').textContent(),lang==='fa'?'لینک کامل نیست؛ لینک را دوباره از برنامه دریافت کنید.':'The link is incomplete. Copy the full link from the app.');
      await viewer.locator('#mute').click();
      assert.equal(await viewer.locator('#mute').textContent(),lang==='fa'?'پخش صدا':'Unmute');
    }
    report.viewer={languages:['fa','en'],buttonsAndErrorLocalized:true};
    assert.deepEqual(errors,[]); report.pageErrors=errors;
    fs.writeFileSync(path.join(out,'done'),'ok');
    await until(()=>host.exitCode!==null);
    assert.equal(host.exitCode,0);
    fs.writeFileSync(path.join(out,'results.json'),JSON.stringify(report,null,2));
    console.log('LOCALIST_BROWSER_TRANSFER_LANGUAGES_OK',JSON.stringify(report));
  } finally {
    fs.writeFileSync(path.join(out,'done'),'stop');
    if(host&&host.exitCode===null) await until(()=>host.exitCode!==null,5000).catch(()=>host.kill());
    if(viewerHost)viewerHost.close();
    await browser.close();
  }
})().catch(error=>{console.error(error);process.exitCode=1;});
