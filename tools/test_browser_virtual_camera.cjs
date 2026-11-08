// Chrome getUserMedia consumer acceptance, using only synthetic Localist frames.
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const { spawn, execFileSync } = require('node:child_process');
const root = path.resolve(__dirname, '..');
const { chromium } = require(process.env.LOCALIST_PLAYWRIGHT || path.join(root, '.runlogs/qa-node/node_modules/playwright'));
const folder = path.join(root, 'build/virtual-camera-qa/Release');
const probe = path.join(folder, 'localist_camera_probe.exe');
const dll = path.join(folder, 'LocalistCamera64.dll');
const hidden = { windowsHide: true, stdio: 'pipe' };
(async () => {
  let registered = false, producer, browser, server;
  try {
    execFileSync(probe, ['--register', dll], hidden);
    registered = true;
    producer = spawn(probe, ['--produce', path.join(root, '.runlogs/nov08-browser-camera-producer.json')], hidden);
    server = http.createServer((req, res) => { res.setHeader('Content-Type', 'text/html'); res.end('<video autoplay playsinline></video><canvas></canvas>'); });
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    browser = await chromium.launch({ executablePath: process.env.LOCALIST_CHROME || 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true, args: ['--autoplay-policy=no-user-gesture-required'] });
    const context = await browser.newContext({ permissions: ['camera'] });
    const page = await context.newPage();
    await page.goto(`http://127.0.0.1:${server.address().port}/`);
    const result = await page.evaluate(async () => {
      const devices = await navigator.mediaDevices.enumerateDevices();
      const camera = devices.find(device => device.kind === 'videoinput' && device.label === 'Localist Camera');
      if (!camera) throw new Error('Localist Camera not enumerated by Chrome');
      const stream = await navigator.mediaDevices.getUserMedia({ video: { deviceId: { exact: camera.deviceId }, width: { exact: 1280 }, height: { exact: 720 }, frameRate: { ideal: 15 } }, audio: false });
      const video = document.querySelector('video'); video.srcObject = stream; await video.play();
      await new Promise(resolve => setTimeout(resolve, 900));
      const canvas = document.querySelector('canvas'); canvas.width = 1280; canvas.height = 720;
      const ctx = canvas.getContext('2d'); ctx.drawImage(video, 0, 0);
      const rgb = [...ctx.getImageData(640, 360, 1, 1).data].slice(0, 3);
      const settings = stream.getVideoTracks()[0].getSettings();
      window.qaStream = stream;
      return { deviceEnumerated: true, width: settings.width, height: settings.height, fps: settings.frameRate, frames: video.getVideoPlaybackQuality().totalVideoFrames, rgb };
    });
    if (result.width !== 1280 || result.height !== 720 || result.frames < 5 || result.rgb[0] < 200 || result.rgb[1] > 60 || result.rgb[2] > 60) throw new Error(JSON.stringify(result));
    producer.kill();
    await new Promise(resolve => setTimeout(resolve, 1000));
    result.blankAfterStop = await page.evaluate(() => {
      const canvas = document.querySelector('canvas'), video = document.querySelector('video');
      const ctx = canvas.getContext('2d'); ctx.drawImage(video, 0, 0);
      const rgb = [...ctx.getImageData(640, 360, 1, 1).data].slice(0, 3);
      window.qaStream.getTracks().forEach(track => track.stop());
      return rgb.every(channel => channel < 4);
    });
    if (!result.blankAfterStop) throw new Error('Browser retained private frame after stop');
    fs.writeFileSync(path.join(root, '.runlogs/nov08-browser-camera-test.json'), JSON.stringify(result, null, 2));
    console.log('LOCALIST_BROWSER_CAMERA_OK', JSON.stringify(result));
  } finally {
    if (browser) await browser.close();
    if (server) await new Promise(resolve => server.close(resolve));
    if (producer && producer.exitCode === null) producer.kill();
    if (registered) execFileSync(probe, ['--unregister', dll], hidden);
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
