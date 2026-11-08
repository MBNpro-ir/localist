// Functional and visual acceptance against Localist's actual Dart HTTP server.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { spawn, execFileSync } = require('node:child_process');
const root = path.resolve(__dirname, '..');
const { chromium } = require(process.env.LOCALIST_PLAYWRIGHT || path.join(root, '.runlogs/qa-node/node_modules/playwright'));
const out = path.join(root, '.runlogs/stream-web-qa');
const fixtures = path.join(out, 'fixtures');
const chrome = process.env.LOCALIST_CHROME || 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
async function until(check, timeout = 20000) { const end = Date.now() + timeout; while (Date.now() < end) { if (await check()) return; await pause(100); } throw Error('Acceptance wait timed out'); }

async function makeFixtures(browser) {
  fs.mkdirSync(fixtures, { recursive: true });
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
  try {
    await page.setContent('<canvas width="1280" height="720"></canvas>');
    for (const [name, palette] of [
      ['Evening colours.png', ['#172c43', '#da8a72', '#f2c09c', '#293f51', '#182b3b']],
      ['Coastal lines.png', ['#274c67', '#9bcac8', '#edf0ce', '#256a73', '#124650']],
    ]) {
      await page.evaluate(colors => {
        const c = document.querySelector('canvas'), ctx = c.getContext('2d');
        const sky = ctx.createLinearGradient(0, 0, 0, 720); sky.addColorStop(0, colors[0]); sky.addColorStop(.65, colors[1]); sky.addColorStop(1, colors[2]); ctx.fillStyle = sky; ctx.fillRect(0, 0, 1280, 720);
        ctx.fillStyle = colors[2]; ctx.beginPath(); ctx.arc(920, 235, 70, 0, Math.PI * 2); ctx.fill();
        ctx.fillStyle = colors[3]; ctx.beginPath(); ctx.moveTo(0, 550); ctx.lineTo(0, 410); ctx.lineTo(220, 265); ctx.lineTo(460, 490); ctx.lineTo(670, 330); ctx.lineTo(1020, 580); ctx.lineTo(1280, 410); ctx.lineTo(1280, 720); ctx.lineTo(0, 720); ctx.fill();
        ctx.fillStyle = colors[4]; ctx.beginPath(); ctx.moveTo(0, 620); ctx.bezierCurveTo(300, 380, 650, 800, 1280, 535); ctx.lineTo(1280, 720); ctx.lineTo(0, 720); ctx.fill();
        ctx.strokeStyle = '#ffffff18'; ctx.lineWidth = 1; for (let i = 0; i < 10; i++) { ctx.beginPath(); ctx.moveTo(0, 650 + i * 8); ctx.bezierCurveTo(350, 590 + i * 10, 950, 780, 1280, 650 + i * 8); ctx.stroke(); }
      }, palette);
      await page.locator('canvas').screenshot({ path: path.join(fixtures, name) });
    }
    fs.copyFileSync(path.join(fixtures, 'Coastal lines.png'), path.join(fixtures, 'نور صبح ـ خاطرهٔ سفر در یک روز آرام و طولانی.png'));
  } finally { await page.close(); }
  const packageRoot = path.join(process.env.LOCALAPPDATA, 'Microsoft/WinGet/Packages/yt-dlp.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe');
  const ffmpeg = process.env.LOCALIST_FFMPEG || path.join(packageRoot, fs.readdirSync(packageRoot).find(name => name.startsWith('ffmpeg-')), 'bin/ffmpeg.exe');
  execFileSync(ffmpeg, ['-hide_banner', '-loglevel', 'error', '-y', '-loop', '1', '-framerate', '24', '-i', path.join(fixtures, 'Evening colours.png'), '-t', '18', '-an', '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', path.join(fixtures, 'Mountain trail.mp4')], { windowsHide: true });
  execFileSync(ffmpeg, ['-hide_banner', '-loglevel', 'error', '-y', '-f', 'lavfi', '-i', 'sine=frequency=220:sample_rate=48000:duration=18', '-c:a', 'pcm_s16le', path.join(fixtures, 'Ambient session.wav')], { windowsHide: true });
  fs.writeFileSync(path.join(fixtures, 'Unavailable clip.mp4'), 'deliberately unsupported synthetic fixture');
}

(async () => {
  fs.mkdirSync(out, { recursive: true });
  for (const name of ['done', 'port.json', 'language', 'language-applied']) { const target = path.join(out, name); if (fs.existsSync(target)) fs.unlinkSync(target); }
  const browser = await chromium.launch({ executablePath: chrome, headless: true, args: ['--autoplay-policy=no-user-gesture-required'] });
  let server;
  try {
    await makeFixtures(browser);
    server = spawn('C:/dev/flutter/bin/cache/dart-sdk/bin/dart.exe', ['C:/dev/flutter/bin/cache/flutter_tools.snapshot', 'test', '--no-pub', 'tools/stream_web_browser_probe.dart', '--reporter', 'expanded'], { cwd: root, windowsHide: true });
    const log = fs.createWriteStream(path.join(out, 'server.log'));
    server.stdout.pipe(log); server.stderr.pipe(log, { end: false });
    await until(() => fs.existsSync(path.join(out, 'port.json')), 45000);
    const { port } = JSON.parse(fs.readFileSync(path.join(out, 'port.json')));
    const origin = `http://127.0.0.1:${port}`;
    const context = await browser.newContext({ viewport: { width: 1440, height: 1040 }, colorScheme: 'dark', reducedMotion: 'reduce' });
    const external = [], errors = [], policies = [];
    await context.route('**/*', route => {
      const url = new URL(route.request().url());
      if (url.origin !== origin) { external.push(url.origin); return route.abort(); }
      return route.continue();
    });
    const page = await context.newPage();
    page.on('pageerror', error => errors.push(error.message));
    await page.addInitScript(() => { window.qaPolicyErrors = []; document.addEventListener('securitypolicyviolation', event => window.qaPolicyErrors.push(event.violatedDirective)); });
    const noOverflow = async () => assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1), 'Page exceeds viewport width');
    const collectPolicies = async () => policies.push(...await page.evaluate(() => window.qaPolicyErrors));
    const screenshot = async name => { await page.evaluate(() => document.fonts.ready); await page.screenshot({ path: path.join(out, name + '.png'), fullPage: true }); };
    const report = {};

    await page.goto(origin, { waitUntil: 'networkidle' });
    assert.equal(await page.locator('.card').count(), 6);
    assert.equal(await page.locator('#library-tools').isVisible(), true);
    await noOverflow(); await screenshot('gallery-desktop-fa'); await collectPolicies();
    const links = await page.locator('.card').evaluateAll(cards => cards.map(card => card.getAttribute('href')));
    await page.locator('[data-filter=image]').click(); assert.equal(await page.locator('.card:visible').count(), 3);
    await page.locator('#search').fill('نور'); assert.equal(await page.locator('.card:visible').count(), 1);
    await page.locator('#search').fill('no-matching-file'); assert(await page.locator('#empty-state').isVisible());
    await page.locator('#reset-filters').click(); assert.equal(await page.locator('.card:visible').count(), 6);
    await page.locator('#sort').selectOption('name');
    assert.match(await page.locator('.card h2').first().textContent(), /نور/);
    assert.match(await page.locator('.card h2').nth(1).textContent(), /Ambient/);
    await page.locator('#list-view').click(); assert(await page.locator('#media-grid').evaluate(grid => grid.classList.contains('list-view')));
    await page.locator('[data-filter=audio]').click(); assert.equal(await page.locator('.card:visible').count(), 1);
    await page.locator('[data-filter=all]').click(); await page.locator('#grid-view').click(); await page.locator('#sort').selectOption('original');
    report.gallery = { items: 6, composedSearchFilters: true, emptyState: true, sorting: true, gridList: true };

    await page.goto(origin + links[0]);
    await page.waitForFunction(() => document.querySelector('#media').readyState >= 1);
    assert.equal(await page.locator('#media').evaluate(video => video.controls), false);
    await screenshot('player-desktop-fa');
    await page.locator('#play').click(); await page.waitForFunction(() => document.querySelector('#media').currentTime > .15);
    await page.locator('#play').click();
    await page.locator('#seek').evaluate(input => { input.value = '4'; input.dispatchEvent(new Event('input', { bubbles: true })); });
    await page.waitForFunction(() => Math.abs(document.querySelector('#media').currentTime - 4) < .2);
    await page.locator('#forward').click(); await page.waitForFunction(() => Math.abs(document.querySelector('#media').currentTime - 14) < .2);
    await page.locator('#back').click(); await page.waitForFunction(() => Math.abs(document.querySelector('#media').currentTime - 4) < .2);
    await page.locator('#speed').selectOption('1.5');
    await page.locator('#volume').evaluate(input => { input.value = '.35'; input.dispatchEvent(new Event('input', { bubbles: true })); });
    await page.locator('#mute').click(); assert(await page.locator('#media').evaluate(video => video.muted)); await page.locator('#mute').click();
    assert.equal(await page.locator('#media').evaluate(video => video.playbackRate), 1.5);
    assert(Math.abs(await page.locator('#media').evaluate(video => video.volume) - .35) < .01);
    await page.locator('#player').focus(); await page.keyboard.press('ArrowRight'); await page.waitForFunction(() => Math.abs(document.querySelector('#media').currentTime - 9) < .2);
    await page.locator('#fullscreen').click(); await page.waitForFunction(() => !!document.fullscreenElement); await page.evaluate(() => document.exitFullscreen());
    report.video = { playback: true, seek: true, skipTenSeconds: true, speed: true, volume: true, mute: true, keyboard: true, fullscreen: true };
    await noOverflow(); await collectPolicies();

    for (const width of [320, 390, 768, 1920]) {
      await page.setViewportSize({ width, height: width >= 768 ? 1080 : 844 });
      await noOverflow();
      assert(await page.locator('#play').isVisible()); assert(await page.locator('#fullscreen').isVisible());
      await screenshot('player-' + width);
    }
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto(origin + links[1]); await page.locator('#media').evaluate(image => image.decode());
    await page.locator('#zoomIn').click(); assert.equal(await page.locator('#zoomValue').textContent(), '125%');
    await page.locator('#fit').click(); assert.equal(await page.locator('#zoomValue').textContent(), '100%');
    await page.locator('#media').dblclick(); assert.equal(await page.locator('#zoomValue').textContent(), '200%');
    await page.locator('#fit').click(); await screenshot('photo-mobile-fa'); await noOverflow(); await collectPolicies();
    report.image = { decoded: true, zoom: true, fit: true, doubleClick: true };
    await page.locator('a[rel=next]').click(); assert(page.url().endsWith(links[2]));
    await page.goto(origin + links[3]); await page.waitForFunction(() => document.querySelector('#media').readyState >= 1);
    await page.locator('#play').click(); await page.waitForFunction(() => document.querySelector('#media').currentTime > .1); await page.locator('#play').click();
    assert(await page.locator('#pip').isHidden()); await screenshot('audio-mobile-fa'); await collectPolicies(); report.audio = { played: true, irrelevantPiPHidden: true };
    await page.goto(origin + links[4]); await page.waitForSelector('#player-error', { state: 'visible' });
    assert.match(await page.locator('#error-message').textContent(), /فرمت/); await page.locator('#retry').click(); await page.waitForSelector('#player-error', { state: 'visible' });
    await screenshot('unsupported-format'); await noOverflow(); await collectPolicies(); report.codecFailure = { readable: true, retryAvailable: true };

    await page.goto(origin); await page.locator('#theme').click(); assert.equal(await page.evaluate(() => document.documentElement.dataset.theme), 'light');
    await page.locator('.card').first().click();
    await page.waitForFunction(() => document.documentElement.dataset.theme === 'light');
    await page.locator('.back-link').click(); await page.waitForSelector('#library-tools', { state: 'visible' }); assert.equal(await page.locator('.card').count(), 6);
    await screenshot('gallery-mobile-light-fa'); await noOverflow(); await collectPolicies();
    fs.writeFileSync(path.join(out, 'language'), 'en');
    await until(() => fs.existsSync(path.join(out, 'language-applied')) && fs.readFileSync(path.join(out, 'language-applied'), 'utf8') === 'en');
    await page.reload(); assert.equal(await page.locator('html').getAttribute('lang'), 'en');
    await page.setViewportSize({ width: 1440, height: 1040 }); await screenshot('gallery-desktop-en'); await noOverflow();
    const fallbackContext = await browser.newContext({ javaScriptEnabled: false, viewport: { width: 390, height: 844 } });
    const fallback = await fallbackContext.newPage(); await fallback.goto(origin + links[0]); assert(await fallback.locator('#media').evaluate(video => video.controls)); await fallbackContext.close();
    report.nativeFallback = true; report.responsiveWidths = [320, 390, 768, 1920]; report.themePersists = true;
    report.pageErrors = errors; report.externalRequests = external; report.cspViolations = policies;
    assert.deepEqual(errors, []); assert.deepEqual(external, []); assert.deepEqual(policies, []);
    fs.writeFileSync(path.join(out, 'browser-results.json'), JSON.stringify(report, null, 2));
    console.log('LOCALIST_STREAM_WEB_OK', JSON.stringify(report));
    await context.close();
  } finally {
    fs.writeFileSync(path.join(out, 'done'), 'done');
    await browser.close();
    if (server) {
      try { await until(() => server.exitCode !== null, 10000); }
      catch (_) { execFileSync('taskkill.exe', ['/PID', String(server.pid), '/T', '/F'], { windowsHide: true }); }
    }
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
