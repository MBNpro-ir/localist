/* Localist Stream: native HTML media, enhanced without a CDN or cloud service. */
(function () {
  'use strict';
  var root = document.documentElement;
  var fa = root.lang === 'fa';
  var byId = function (id) { return document.getElementById(id); };
  var text = function (farsi, english) { return fa ? farsi : english; };
  var read = function (key) { try { return localStorage.getItem('localist.stream.' + key); } catch (_) { return null; } };
  var save = function (key, value) { try { localStorage.setItem('localist.stream.' + key, value); } catch (_) { /* Private browsers can deny storage. */ } };
  var icon = function (button, name, label) {
    if (!button) return;
    var use = button.querySelector('use');
    if (use) use.setAttribute('href', '#i-' + name);
    if (label) {
      button.setAttribute('aria-label', label);
      button.title = label;
      var caption = button.querySelector('.sr-only');
      if (caption) caption.textContent = label;
    }
  };
  var theme = byId('theme');
  var savedTheme = read('theme');
  if (savedTheme === 'light' || savedTheme === 'dark') root.dataset.theme = savedTheme;
  var isDark = function () { return root.dataset.theme ? root.dataset.theme === 'dark' : !window.matchMedia('(prefers-color-scheme: light)').matches; };
  var updateThemeIcon = function () { icon(theme, isDark() ? 'sun' : 'moon'); };
  updateThemeIcon();
  if (theme) {
    theme.disabled = false;
    theme.addEventListener('click', function () {
      root.dataset.theme = isDark() ? 'light' : 'dark';
      save('theme', root.dataset.theme);
      updateThemeIcon();
    });
  }

  function gallery() {
    var grid = byId('media-grid'), search = byId('search'), sort = byId('sort');
    var cards = Array.from(grid.querySelectorAll('.card'));
    var filter = 'all';
    var filters = Array.from(document.querySelectorAll('[data-filter]'));
    var normalize = function (value) { return value.normalize('NFKC').toLocaleLowerCase(fa ? 'fa' : 'en').replace(/[يى]/g, 'ی').replace(/ك/g, 'ک'); };
    var collator = new Intl.Collator(fa ? 'fa' : 'en', { numeric: true, sensitivity: 'base' });
    var update = function () {
      var query = normalize(search.value.trim());
      var visible = 0;
      cards.forEach(function (card) {
        card.hidden = (filter !== 'all' && card.dataset.kind !== filter) || normalize(card.dataset.name).indexOf(query) === -1;
        if (!card.hidden) visible++;
      });
      var ordered = cards.slice().sort(function (a, b) {
        if (sort.value === 'name') return collator.compare(a.dataset.name, b.dataset.name);
        if (sort.value === 'type') return collator.compare(a.dataset.kind, b.dataset.kind) || Number(a.dataset.order) - Number(b.dataset.order);
        return Number(a.dataset.order) - Number(b.dataset.order);
      });
      var fragment = document.createDocumentFragment();
      ordered.forEach(function (card) { fragment.appendChild(card); });
      grid.appendChild(fragment);
      byId('empty-state').hidden = visible !== 0;
      byId('result-count').textContent = new Intl.NumberFormat(fa ? 'fa' : 'en').format(visible) + text(' رسانه', visible === 1 ? ' item' : ' items');
      filters.forEach(function (button) { button.setAttribute('aria-pressed', String(button.dataset.filter === filter)); });
    };
    filters.forEach(function (button) { button.addEventListener('click', function () { filter = button.dataset.filter; update(); }); });
    search.addEventListener('input', update);
    sort.addEventListener('change', update);
    byId('reset-filters').addEventListener('click', function () { search.value = ''; filter = 'all'; sort.value = 'original'; update(); search.focus(); });
    var setView = function (list) {
      grid.classList.toggle('list-view', list);
      byId('grid-view').setAttribute('aria-pressed', String(!list));
      byId('list-view').setAttribute('aria-pressed', String(list));
      save('view', list ? 'list' : 'grid');
    };
    byId('grid-view').addEventListener('click', function () { setView(false); });
    byId('list-view').addEventListener('click', function () { setView(true); });
    setView(read('view') === 'list');
    byId('library-tools').hidden = byId('filters').hidden = false;
    update();
    document.addEventListener('keydown', function (event) {
      if (event.key === '/' && !/INPUT|SELECT|TEXTAREA/.test(event.target.tagName) && !event.target.isContentEditable) { event.preventDefault(); search.focus(); }
    });
    // Decode only visible previews, at most two at once. Never play previews.
    var pending = [], active = 0;
    var pump = function () {
      while (active < 2 && pending.length) {
        (function (video) {
          active++;
          var finished = false, timeout;
          var done = function () { if (finished) return; finished = true; clearTimeout(timeout); active--; pump(); };
          video.addEventListener('loadedmetadata', function () { if (Number.isFinite(video.duration) && video.duration > .2) video.currentTime = Math.min(.1, video.duration / 2); }, { once: true });
          video.addEventListener('loadeddata', function () { video.classList.add('preview-ready'); done(); }, { once: true });
          video.addEventListener('error', function () { video.hidden = true; done(); }, { once: true });
          timeout = setTimeout(done, 8000);
          video.preload = 'metadata'; video.src = video.dataset.src; delete video.dataset.src;
        })(pending.shift());
      }
    };
    var queue = function (video) { pending.push(video); pump(); };
    var videos = document.querySelectorAll('video[data-src]');
    if ('IntersectionObserver' in window) {
      var observer = new IntersectionObserver(function (entries) {
        entries.forEach(function (entry) { if (entry.isIntersecting) { observer.unobserve(entry.target); queue(entry.target); } });
      }, { rootMargin: '80px' });
      videos.forEach(function (video) { observer.observe(video); });
    } else { videos.forEach(queue); }
  }

  function player() {
    var media = byId('media'), stage = byId('player'), image = media.tagName === 'IMG', audio = media.tagName === 'AUDIO';
    var status = byId('player-status'), errorPanel = byId('player-error'), center = byId('center-play');
    var announce = function (message) { status.textContent = message; };
    var failed = false, idleTimer;
    var showError = function () {
      failed = true; errorPanel.hidden = false; byId('buffering').hidden = true;
      if (center) center.hidden = true;
      var unsupported = !image && media.error && (media.error.code === 3 || media.error.code === 4);
      byId('error-message').textContent = unsupported ? text('مرورگر این فرمت را پخش نمی‌کند. فایل را دریافت کنید یا با مرورگر دیگری باز کنید.', 'This browser cannot play this format. Download the file or try another browser.') : text('فایل در دسترس نیست. اتصال به فرستنده را بررسی و دوباره تلاش کنید.', 'The media is unavailable. Check the connection to the sender and try again.');
    };
    media.addEventListener('error', showError);
    byId('retry').addEventListener('click', function () {
      failed = false; errorPanel.hidden = true; announce('');
      if (image) { var source = media.src; media.removeAttribute('src'); media.src = source; }
      else { media.load(); }
    });
    var fullscreen = function () {
      try {
        var result;
        if (document.fullscreenElement) result = document.exitFullscreen();
        else if (document.webkitFullscreenElement && document.webkitExitFullscreen) result = document.webkitExitFullscreen();
        else if (stage.requestFullscreen) result = stage.requestFullscreen();
        else if (stage.webkitRequestFullscreen) result = stage.webkitRequestFullscreen();
        else if (!image && !audio && media.webkitEnterFullscreen) media.webkitEnterFullscreen();
        else announce(text('تمام‌صفحه در این مرورگر در دسترس نیست.', 'Fullscreen is unavailable in this browser.'));
        if (result && result.catch) result.catch(function () { announce(text('تمام‌صفحه در دسترس نیست.', 'Fullscreen is unavailable.')); });
      } catch (_) { announce(text('تمام‌صفحه در دسترس نیست.', 'Fullscreen is unavailable.')); }
    };
    byId('fullscreen').addEventListener('click', fullscreen);
    document.addEventListener('fullscreenchange', function () { icon(byId('fullscreen'), document.fullscreenElement ? 'exit' : 'fullscreen', document.fullscreenElement ? text('خروج از تمام‌صفحه', 'Exit fullscreen') : text('تمام‌صفحه', 'Fullscreen')); });
    byId('enhanced-controls').hidden = false;
    if (image) {
      var zoom = 1, x = 0, y = 0, drag = null;
      var surface = stage.querySelector('.media-surface');
      var render = function () {
        var maxX = Math.max(0, (media.clientWidth * zoom - surface.clientWidth) / 2 + 20);
        var maxY = Math.max(0, (media.clientHeight * zoom - surface.clientHeight + 80) / 2 + 20);
        x = Math.max(-maxX, Math.min(maxX, x)); y = Math.max(-maxY, Math.min(maxY, y));
        media.style.transform = 'translate(' + x + 'px,' + y + 'px) scale(' + zoom + ')';
        stage.classList.toggle('zoomed', zoom > 1);
        byId('zoomValue').textContent = Math.round(zoom * 100) + '%';
        byId('zoomOut').disabled = zoom <= .5; byId('zoomIn').disabled = zoom >= 4;
      };
      var setZoom = function (value) { zoom = Math.max(.5, Math.min(4, value)); if (zoom === 1) x = y = 0; render(); };
      byId('zoomIn').addEventListener('click', function () { setZoom(zoom + .25); });
      byId('zoomOut').addEventListener('click', function () { setZoom(zoom - .25); });
      byId('fit').addEventListener('click', function () { setZoom(1); });
      surface.addEventListener('dblclick', function (event) { event.preventDefault(); setZoom(zoom === 1 ? 2 : 1); });
      surface.addEventListener('pointerdown', function (event) { if (zoom <= 1) return; drag = { id: event.pointerId, x: event.clientX - x, y: event.clientY - y }; surface.setPointerCapture(event.pointerId); });
      surface.addEventListener('pointermove', function (event) { if (drag && drag.id === event.pointerId) { x = event.clientX - drag.x; y = event.clientY - drag.y; render(); } });
      surface.addEventListener('pointerup', function () { drag = null; });
      surface.addEventListener('pointercancel', function () { drag = null; });
      surface.addEventListener('wheel', function (event) { if (event.ctrlKey) { event.preventDefault(); setZoom(zoom + (event.deltaY < 0 ? .25 : -.25)); } }, { passive: false });
      media.addEventListener('load', function () { failed = false; errorPanel.hidden = true; render(); });
      if (media.complete && !media.naturalWidth) showError();
      render();
      root.classList.add('js');
      return;
    }

    var seek = byId('seek'), volume = byId('volume'), pip = byId('pip'), dragging = false;
    var format = function (value) {
      if (!Number.isFinite(value)) return '0:00';
      var seconds = Math.max(0, Math.floor(value)), hours = Math.floor(seconds / 3600);
      return (hours ? hours + ':' + String(Math.floor(seconds / 60) % 60).padStart(2, '0') : Math.floor(seconds / 60)) + ':' + String(seconds % 60).padStart(2, '0');
    };
    var update = function () {
      var duration = Number.isFinite(media.duration) ? media.duration : 0, current = media.currentTime || 0;
      seek.max = duration; seek.disabled = duration <= 0 || failed;
      if (!dragging) seek.value = current;
      seek.setAttribute('aria-valuetext', format(current) + ' / ' + format(duration));
      byId('current').textContent = format(current); byId('duration').textContent = format(duration);
      seek.style.setProperty('--played', (duration ? current / duration * 100 : 0) + '%');
      var buffered = 0;
      try { for (var i = 0; i < media.buffered.length; i++) if (media.buffered.start(i) <= current + 1) buffered = media.buffered.end(i); } catch (_) { /* Buffer can change during seeking. */ }
      seek.style.setProperty('--buffered', Math.min(100, duration ? buffered / duration * 100 : 0) + '%');
      volume.value = media.muted ? 0 : media.volume;
      volume.style.setProperty('--played', Number(volume.value) * 100 + '%');
      byId('speed').value = String(media.playbackRate);
      icon(byId('play'), media.paused ? 'play' : 'pause', media.paused ? text('پخش', 'Play') : text('توقف', 'Pause'));
      icon(byId('mute'), media.muted || media.volume === 0 ? 'muted' : 'volume', media.muted || media.volume === 0 ? text('وصل صدا', 'Unmute') : text('قطع صدا', 'Mute'));
      byId('mute').setAttribute('aria-pressed', String(media.muted || media.volume === 0));
      stage.classList.toggle('is-playing', !media.paused);
      if (center) center.hidden = !media.paused || failed;
      if (media.paused) { stage.classList.remove('controls-idle'); byId('buffering').hidden = true; }
      pip.hidden = audio || !(document.pictureInPictureEnabled && media.requestPictureInPicture || media.webkitSupportsPresentationMode && media.webkitSupportsPresentationMode('picture-in-picture'));
    };
    var showControls = function () {
      stage.classList.remove('controls-idle'); clearTimeout(idleTimer);
      if (!media.paused) idleTimer = setTimeout(function () { if (!dragging && !media.paused) stage.classList.add('controls-idle'); }, 2800);
    };
    var togglePlay = function () {
      if (failed) return;
      if (!media.paused) { media.pause(); return; }
      var promise = media.play();
      if (promise && promise.catch) promise.catch(function (error) {
        if (error.name === 'NotAllowedError') announce(text('برای پخش، دوباره دکمهٔ پخش را بزنید.', 'Tap Play to allow playback.'));
        else if (error.name !== 'AbortError') showError();
      });
      showControls();
    };
    var skip = function (seconds) { if (Number.isFinite(media.duration)) media.currentTime = Math.max(0, Math.min(media.duration, (media.currentTime || 0) + seconds)); showControls(); };
    var setVolume = function (value) {
      value = Math.max(0, Math.min(1, value));
      try { media.volume = value; media.muted = value === 0; } catch (_) { /* iOS can reserve volume for hardware buttons. */ }
      if (Math.abs(media.volume - value) > .02) { volume.disabled = true; volume.title = text('از دکمه‌های صدای دستگاه استفاده کنید.', 'Use the device volume buttons.'); }
      update();
    };
    byId('play').addEventListener('click', togglePlay);
    if (center) center.addEventListener('click', togglePlay);
    byId('back').addEventListener('click', function () { skip(-10); });
    byId('forward').addEventListener('click', function () { skip(10); });
    byId('mute').addEventListener('click', function () { media.muted = !media.muted; if (!media.muted && media.volume === 0) setVolume(.5); update(); });
    volume.addEventListener('input', function () { setVolume(Number(volume.value)); });
    seek.addEventListener('pointerdown', function () { dragging = true; });
    seek.addEventListener('input', function () { if (Number.isFinite(media.duration)) media.currentTime = Math.max(0, Math.min(media.duration, Number(seek.value))); });
    seek.addEventListener('change', function () { dragging = false; update(); });
    seek.addEventListener('pointercancel', function () { dragging = false; update(); });
    seek.addEventListener('pointerup', function () { dragging = false; update(); });
    byId('speed').addEventListener('change', function () { media.playbackRate = Number(byId('speed').value); });
    pip.addEventListener('click', function () {
      try {
        var result;
        if (document.pictureInPictureElement) result = document.exitPictureInPicture();
        else if (media.requestPictureInPicture) result = media.requestPictureInPicture();
        else if (media.webkitSetPresentationMode) media.webkitSetPresentationMode(media.webkitPresentationMode === 'picture-in-picture' ? 'inline' : 'picture-in-picture');
        if (result && result.catch) result.catch(function () { announce(text('تصویر در تصویر در دسترس نیست.', 'Picture in picture is unavailable.')); });
      } catch (_) { announce(text('تصویر در تصویر در دسترس نیست.', 'Picture in picture is unavailable.')); }
    });
    ['loadedmetadata', 'durationchange', 'timeupdate', 'play', 'pause', 'volumechange', 'ratechange', 'progress', 'ended'].forEach(function (event) { media.addEventListener(event, update); });
    ['playing', 'canplay', 'seeked'].forEach(function (event) { media.addEventListener(event, function () { byId('buffering').hidden = true; }); });
    media.addEventListener('loadeddata', function () { failed = false; errorPanel.hidden = true; announce(''); update(); });
    ['waiting', 'stalled'].forEach(function (event) { media.addEventListener(event, function () { if (!failed && !media.paused) byId('buffering').hidden = false; }); });
    stage.addEventListener('pointermove', showControls); stage.addEventListener('pointerdown', showControls); stage.addEventListener('focusin', showControls);
    if (!audio) { media.addEventListener('click', togglePlay); media.addEventListener('dblclick', fullscreen); }
    document.addEventListener('keydown', function (event) {
      if (event.altKey || event.ctrlKey || event.metaKey || /INPUT|SELECT|TEXTAREA|BUTTON|A/.test(event.target.tagName) || event.target.isContentEditable) return;
      var key = event.key.toLowerCase(), handled = true;
      if (key === ' ' || key === 'k') togglePlay();
      else if (key === 'arrowleft') skip(-5); else if (key === 'arrowright') skip(5);
      else if (key === 'j') skip(-10); else if (key === 'l') skip(10);
      else if (key === 'm') { media.muted = !media.muted; update(); }
      else if (key === 'f') fullscreen();
      else if (key === 'arrowup') setVolume(media.volume + .05); else if (key === 'arrowdown') setVolume(media.volume - .05);
      else if (key === 'home') skip(-Infinity); else if (key === 'end') skip(Infinity); else handled = false;
      if (handled) { event.preventDefault(); showControls(); }
    });
    window.addEventListener('pagehide', function () { media.pause(); clearTimeout(idleTimer); });
    if (media.error) showError();
    update();
    // Activate our controls only after all handlers have been installed.
    media.controls = false;
    root.classList.add('js');
  }

  try {
    if (document.body.dataset.page === 'gallery') gallery();
    else if (byId('media')) player();
  } catch (_) {
    // A limited TV browser still retains the original HTML media controls.
    var media = byId('media');
    if (media && media.tagName !== 'IMG') media.controls = true;
    var enhanced = byId('enhanced-controls');
    if (enhanced) enhanced.hidden = true;
    var center = byId('center-play');
    if (center) center.hidden = true;
    root.classList.remove('js');
  }
})();
