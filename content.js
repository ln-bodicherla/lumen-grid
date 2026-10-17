(() => {
  if (window.top !== window || window.__lumenGrid) return;
  window.__lumenGrid = true;

  // scrTop/scrBottom: the physical screen's corner radius (CSS px), used in fullscreen.
  // MacBook Pro 14/16 (2021+) round only the top corners; tune live with Alt+Shift+arrows in fullscreen.
  const S = { scrTop: 12, scrBottom: 0, auto: true, wall: true, bypass: [], lumen: true, dim: 0.1, mode: 'theater', style: 'inplace' };
  let root, frame, stage, hud, ui;
  let active = null;      // popout: { video, ph, style, controls }
  let spot = null;        // in-place spotlight: { video, box, deco, track, ... }
  let backdrop, hole;
  let mode = S.mode;      // current layout: 'theater' | 'dock'
  let scrollStart = 0, hideTimer = 0, raf = 0, dragging = false;

  // ---------- settings ----------
  chrome.storage.sync.get(S, (v) => { Object.assign(S, v); mode = S.mode; applyTheme(); });
  chrome.storage.onChanged.addListener((ch) => {
    for (const k in ch) S[k] = ch[k].newValue;
    applyTheme();
  });
  chrome.runtime.onMessage.addListener((m) => {
    if (m.cmd === 'focus') focused() ? unfocus() : focusBest();
  });

  // ---------- bypass list: sites/URLs that keep their own look ----------
  // "example.com" also covers its subdomains; anything with "/" or "*" is a URL pattern
  // ("*" = anything), matched with or without the https:// part.
  const bypassed = () => (S.bypass || []).some((r) => tfMatchRule(r, location.href));
  const themeOn = () => !!S.lumen && !bypassed();
  // single-page apps change URL without reloading: re-check the list when it changes
  let lastUrl = location.href;
  setInterval(() => { if (location.href !== lastUrl) { lastUrl = location.href; applyTheme(); } }, 800);

  function applyTheme() {
    const on = themeOn();
    document.documentElement.classList.toggle('tf-lumen', on);
    if (root) {
      root.style.setProperty('--tf-dim', S.dim);
      root.style.setProperty('--tf-scr-t', S.scrTop + 'px');
      root.style.setProperty('--tf-scr-b', S.scrBottom + 'px');
    }
    setInvert(on && siteIsLight);
    if (isYT) ytDark(on);
    wallOn() ? showWall() : clearAll();
  }

  // ---------- Omarchy palette + wallpaper (written by omarchy-sync.sh) ----------
  // Read fresh on every page load, so a system theme switch restyles pages without reloading the extension.
  const inv = (hex) => '#' + hex.replace('#', '').match(/../g).map((h) => (255 - parseInt(h, 16)).toString(16).padStart(2, '0')).join('');
  fetch(chrome.runtime.getURL('omarchy/theme.json'), { cache: 'no-store' })
    .then((r) => r.json())
    .then((t) => {
      const wall = t.wallpaper ? `url("${chrome.runtime.getURL('omarchy/' + t.wallpaper)}?v=${t.stamp}")` : 'none';
      const style = document.createElement('style');
      style.id = 'tf-theme';
      style.textContent = `:root {
        --tf-accent: ${t.accent}; --tf-accent-inv: ${inv(t.accent)}; --tf-orange: ${t.orange};
        --tf-foreground: ${t.foreground}; --tf-foreground-muted: ${t.mutedForeground};
        --tf-background: ${t.background}; --tf-background-dark: ${t.darkBackground}; --tf-panel-bg: ${t.panel};
        --tf-wallpaper: ${wall};
      }`;
      document.documentElement.appendChild(style);
    })
    .catch(() => {});  // not synced yet: CSS fallbacks keep the stock neon palette

  // YouTube gets a live backdrop: Omarchy wallpaper + a slowly moving Lumen grid floor.
  // ---------- live backdrop on every site: Omarchy wallpaper + moving Lumen grid floor ----------
  const wallOn = () => themeOn() && S.wall;
  function showWall() {
    const html = document.documentElement;
    html.classList.add('tf-wall');
    if (!document.getElementById('tf-bg')) {
      const bg = document.createElement('div');
      bg.id = 'tf-bg';
      bg.innerHTML = '<div class="tf-wallpaper"></div><div class="tf-shade"></div><div class="tf-floor-wrap"><div class="tf-floor"></div></div><div class="tf-horizon"></div>';
      html.appendChild(bg);  // outside <body>, so SPA re-renders never remove it
    }
    clearSoon(0);
  }

  // Most sites paint an opaque page color that would hide the backdrop. Walk only the big
  // page-sized containers (cards, menus and other small boxes are never touched) and make the
  // ones painted in the page's own color transparent; sticky/fixed bars become blurred glass
  // so content scrolling under them stays readable.
  let pageBg = null;
  const parseBg = (c) => {
    const m = c.match(/[\d.]+/g);
    return m && (m[3] === undefined || +m[3] > 0.5) ? m.slice(0, 3).map(Number) : null;
  };
  const near = (a, b) => Math.abs(a[0] - b[0]) + Math.abs(a[1] - b[1]) + Math.abs(a[2] - b[2]) < 24;
  function clearScan() {
    if (!wallOn() || isYT || !document.body || !pageBg) return;  // YouTube is handled by youtube.css
    const html = document.documentElement, minW = innerWidth * 0.5;
    const queue = [html, document.body];
    for (let i = 0; i < queue.length && i < 1500; i++) {
      const el = queue[i];
      if (el.id === 'tf-root' || el.id === 'tf-bg') continue;
      if (!el.dataset.tfBg) {
        const cs = getComputedStyle(el), c = parseBg(cs.backgroundColor);
        // a light page with a dark section (GitHub's black header): the invert would turn it
        // white, so flip that section back and leave its insides alone
        if (c && siteIsLight && !near(c, pageBg) && (0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]) / 255 < 0.3) {
          el.dataset.tfBg = c.join(',');
          el.classList.add('tf-keep');
          continue;
        }
        if (c && near(c, pageBg)) {
          el.dataset.tfBg = c.join(',');
          const bar = el !== html && el !== document.body && (cs.position === 'fixed' || cs.position === 'sticky');
          el.classList.add(bar ? 'tf-glass' : 'tf-clear');
        }
      }
      if (el.classList.contains('tf-keep')) continue;  // flipped back as a whole: never touch its insides
      if (el === html) continue;  // body is already queued
      for (const ch of el.children) if (ch.getBoundingClientRect().width >= minW) queue.push(ch);
    }
  }
  function clearAll() {
    document.documentElement.classList.remove('tf-wall');
    for (const el of document.querySelectorAll('[data-tf-bg]')) {
      el.classList.remove('tf-clear', 'tf-glass', 'tf-keep');
      delete el.dataset.tfBg;
    }
  }
  let clearTimer = 0;
  const clearSoon = (ms = 300) => { clearTimeout(clearTimer); clearTimer = setTimeout(clearScan, ms); };
  // SPAs swap whole page sections; a cheap re-walk keeps new containers see-through
  setInterval(() => { if (!document.hidden) clearScan(); }, 3000);
  addEventListener('resize', () => clearSoon());

  // ---------- dark-by-default: invert light sites, leave already-dark sites alone ----------
  const host = location.hostname;
  const isYT = /(^|\.)youtube\.com$/.test(host);
  // YouTube: force its own dark theme while ours is on; hand it back if we were the ones who set it
  let forcedDark = false;
  function ytDark(on) {
    const html = document.documentElement;
    if (on && !html.hasAttribute('dark')) { forcedDark = true; html.setAttribute('dark', ''); }
    else if (!on && forcedDark) { forcedDark = false; html.removeAttribute('dark'); }
  }
  let siteIsLight = false;
  // never invert while something is fullscreen: the top layer escapes the page filter,
  // so re-inverted media would show up as a negative
  const setInvert = (on) => document.documentElement.classList.toggle('tf-invert', !!on && !isYT && !document.fullscreenElement);
  document.addEventListener('fullscreenchange', () => applyTheme());
  if (isYT) {
    const html = document.documentElement;
    html.classList.add('tf-yt');
    new MutationObserver(() => ytDark(themeOn())).observe(html, { attributes: true, attributeFilter: ['dark'] });
    ytDark(themeOn());
  }
  // remember the verdict per site so the next visit is dark from the first paint
  chrome.storage.local.get({ light: {} }, ({ light }) => {
    if (!isYT && host in light && siteIsLight !== light[host]) { siteIsLight = light[host]; applyTheme(); }
  });

  const bgOf = (el) => {
    for (; el; el = el.parentElement) {
      if (el.dataset?.tfBg) return el.dataset.tfBg.split(',').map(Number);  // its real color, before we cleared it
      const c = parseBg(getComputedStyle(el).backgroundColor);
      if (c) return c;
    }
    return [255, 255, 255];  // nothing painted -> browser default white
  };
  function detect() {
    if (!document.body || isYT) return;
    let light = 0, n = 0;
    const seen = [];
    // a playing video is black and would outvote the page around it, so skip points on videos
    const vids = [...document.querySelectorAll('video')].map((v) => v.getBoundingClientRect());
    const onVideo = (x, y) => vids.some((r) => x >= r.left && x <= r.right && y >= r.top && y <= r.bottom);
    for (let i = 0; i < 16; i++) {
      const x = innerWidth * (0.1 + 0.8 * ((i % 4) / 3)), y = innerHeight * (0.12 + 0.76 * (Math.floor(i / 4) / 3));
      if (onVideo(x, y)) continue;
      const el = document.elementFromPoint(x, y);
      if (!el || el.closest('#tf-root')) continue;
      const [r, g, b] = bgOf(el);
      seen.push([r, g, b]);
      n++;
      if ((0.2126 * r + 0.7152 * g + 0.0722 * b) / 255 > 0.45) light++;
    }
    if (!n) return;
    // the page color is the most common background under the sample points
    pageBg = seen.reduce((best, c) => {
      const k = seen.filter((d) => near(c, d)).length;
      return k > best.k ? { c, k } : best;
    }, { c: null, k: 0 }).c;
    clearSoon(0);
    const isLight = light * 2 > n;
    if (isLight === siteIsLight) return;
    siteIsLight = isLight;
    applyTheme();
    chrome.storage.local.get({ light: {} }, ({ light: l }) => { l[host] = isLight; chrome.storage.local.set({ light: l }); });
  }
  let detectTimer = 0;
  const detectSoon = (ms = 250) => { clearTimeout(detectTimer); detectTimer = setTimeout(detect, ms); };
  document.addEventListener('DOMContentLoaded', () => {
    detectSoon(0);
    // sites toggling their own dark mode (YouTube sets html[dark], others swap classes)
    const mo = new MutationObserver(() => detectSoon());
    mo.observe(document.documentElement, { attributes: true, attributeFilter: ['dark', 'data-theme', 'data-color-mode', 'style'] });
    mo.observe(document.body, { attributes: true, attributeFilter: ['class', 'style', 'data-theme'] });
  });
  addEventListener('load', () => { detectSoon(0); setTimeout(detect, 2000); });

  // ---------- auto trigger ----------
  const qualifies = (v) => {
    if (!(v instanceof HTMLVideoElement) || v.muted || v.volume === 0 || v.paused) return false;
    if (document.fullscreenElement || v.closest('#tf-root')) return false;
    const r = v.getBoundingClientRect();
    return r.width >= 300 && r.height >= 160;
  };
  const maybeFocus = (e) => {
    const v = e.target;
    if (!S.auto || !qualifies(v)) return;
    if (focused() === v) return;
    unfocus(true);
    focus(v);
  };
  document.addEventListener('ended', (e) => { if (e.target === focused()) unfocus(); }, true);

  const focused = () => active?.video || spot?.video || null;
  const focus = (v) => (S.style === 'popout' ? enter(v) : spotOn(v));
  const unfocus = (instant) => { exit(instant); spotOff(); };
  document.addEventListener('playing', maybeFocus, true);
  document.addEventListener('volumechange', maybeFocus, true); // muted feed autoplay -> user unmutes

  function focusBest() {
    const vids = [...document.querySelectorAll('video')].filter((v) => {
      const r = v.getBoundingClientRect();
      return r.width > 0 && r.height > 0;
    });
    vids.sort((a, b) => (b.paused ? 0 : 1) - (a.paused ? 0 : 1) ||
      b.clientWidth * b.clientHeight - a.clientWidth * a.clientHeight);
    if (vids[0]) focus(vids[0]);
  }

  // ---------- build DOM ----------
  function build() {
    if (root) return;
    root = document.createElement('div');
    root.id = 'tf-root';
    root.innerHTML = '<div class="tf-backdrop"></div><div class="tf-hole"></div><div class="tf-frame"><div class="tf-stage"></div><div class="tf-hud"></div></div>';
    document.documentElement.appendChild(root);
    backdrop = root.querySelector('.tf-backdrop');
    hole = root.querySelector('.tf-hole');
    frame = root.querySelector('.tf-frame');
    stage = root.querySelector('.tf-stage');
    hud = root.querySelector('.tf-hud').attachShadow({ mode: 'open' });
    hud.innerHTML = HUD_HTML;
    ui = Object.fromEntries([...hud.querySelectorAll('[data-k]')].map((el) => [el.dataset.k, el]));
    applyTheme();

    hud.addEventListener('click', onHudClick);
    ui.surface.addEventListener('dblclick', () => toggleFs());
    ui.vol.addEventListener('input', () => { const v = active?.video; if (v) { v.volume = +ui.vol.value; v.muted = v.volume === 0; } });
    ui.seek.addEventListener('pointerdown', (e) => { dragging = true; ui.seek.setPointerCapture(e.pointerId); seekTo(e); });
    ui.seek.addEventListener('pointermove', (e) => { if (dragging) seekTo(e); else hoverTime(e); });
    ui.seek.addEventListener('pointerup', () => { dragging = false; });
    ui.seek.addEventListener('pointerleave', () => { ui.tip.style.opacity = 0; });
    frame.addEventListener('pointermove', wake);
    frame.addEventListener('pointerleave', () => sleep(600));

    addEventListener('resize', () => active && layout(false));
    addEventListener('scroll', () => {
      // scrolling the feed while in theater: slide the player aside so the feed is usable
      if (active && mode === 'theater' && Math.abs(scrollY - scrollStart) > 220) setMode('dock', false);
    }, { passive: true });
    addEventListener('keydown', (e) => {
      if (!focused() || e.target.closest?.('input,textarea,[contenteditable]')) return;
      if (e.key === 'Escape' && !document.fullscreenElement) { e.stopPropagation(); unfocus(); }
      // fullscreen corner tuning: Alt+Shift+Up/Down = top corners, Alt+Shift+Left/Right = bottom corners
      const step = { ArrowUp: ['scrTop', 1], ArrowDown: ['scrTop', -1], ArrowRight: ['scrBottom', 1], ArrowLeft: ['scrBottom', -1] }[e.key];
      if (step && e.altKey && e.shiftKey && document.fullscreenElement) {
        e.preventDefault(); e.stopPropagation();
        const [k, d] = step;
        S[k] = Math.max(0, Math.min(80, S[k] + d));
        chrome.storage.sync.set({ [k]: S[k] });
        applyTheme();
        if (spot) spot.frame = 0;  // re-measure on the next frame
        toast(`SCREEN CORNERS  top ${S.scrTop}px · bottom ${S.scrBottom}px`);
      }
    }, true);
    document.addEventListener('fullscreenchange', () => { layout(false); if (spot) spot.frame = 0; });
  }

  // ---------- in-place spotlight (default) ----------
  // The video never leaves the page: it scrolls with the feed and slides under
  // sticky headers like normal. We frame it in neon and dim everything around it.
  function findBox(v) {
    const yt = v.closest('.html5-video-player');
    if (yt) return yt;
    const vr = v.getBoundingClientRect();
    let box = null;
    for (let el = v.parentElement; el && el !== document.body; el = el.parentElement) {
      const r = el.getBoundingClientRect();
      if (r.width > vr.width * 1.08 + 4 || r.height > vr.height * 1.1 + 4) break;
      box = el;
    }
    return box;  // null -> no tight wrapper, draw a fixed overlay that tracks the video
  }

  function spotOn(v) {
    build();
    const box = findBox(v);
    const deco = document.createElement('div');
    deco.className = 'tf-deco';
    deco.innerHTML = '<div class="tf-c tf-c1"></div><div class="tf-c tf-c2"></div><div class="tf-c tf-c3"></div><div class="tf-c tf-c4"></div>' +
      '<div class="tf-scan"></div><div class="tf-tag">◆ FOCUS<span class="tf-pop">⤢ POP OUT</span></div>';
    deco.querySelector('.tf-pop').addEventListener('click', (e) => {
      e.preventDefault(); e.stopPropagation();
      const vid = spot.video;
      spotOff();
      enter(vid);
    }, true);

    let fixedPos = false;
    if (box) {
      fixedPos = getComputedStyle(box).position === 'static';
      if (fixedPos) box.style.position = 'relative';
      box.classList.add('tf-host');
      box.appendChild(deco);
    } else {
      deco.classList.add('tf-track');
      root.appendChild(deco);
    }
    spot = { video: v, box, deco, fixedPos, raf: 0, radius: -1, frame: 0 };
    root.classList.add('tf-spot');
    spotTick();
  }

  function spotOff() {
    if (!spot) return;
    cancelAnimationFrame(spot.raf);
    spot.deco.remove();
    if (spot.box) {
      spot.box.classList.remove('tf-host');
      if (spot.fixedPos) spot.box.style.position = '';
    }
    root.classList.remove('tf-spot');
    backdrop.style.cssText = '';
    hole.style.cssText = '';
    spot = null;
  }

  // The visible rounding often lives on a wrapper (YouTube rounds #ytd-player, not the
  // player itself) and changes with layout (theater mode is square), so measure the
  // largest corner radius among the video and same-sized ancestors, and keep re-measuring.
  function cornerRadius(el, v) {
    const ref = el.getBoundingClientRect();
    let rad = parseFloat(getComputedStyle(v).borderTopLeftRadius) || 0;
    for (let i = 0; el && i < 6; i++, el = el.parentElement) {
      const r = el.getBoundingClientRect();
      if (Math.abs(r.width - ref.width) > 3 || Math.abs(r.height - ref.height) > 3) break;
      rad = Math.max(rad, parseFloat(getComputedStyle(el).borderTopLeftRadius) || 0);
    }
    return rad;
  }
  // full-viewport rectangle with a rounded-rect hole, for the dim layer
  function holePath(l, t, r, b, rad) {
    const W = innerWidth, H = innerHeight;
    rad = Math.max(0, Math.min(rad, (r - l) / 2, (b - t) / 2));
    const a = (x, y) => `A${rad} ${rad} 0 0 1 ${x} ${y}`;
    return `path(evenodd, 'M0 0H${W}V${H}H0Z M${l + rad} ${t}H${r - rad}${a(r, t + rad)}V${b - rad}${a(r - rad, b)}H${l + rad}${a(l, b - rad)}V${t + rad}${a(l + rad, t)}Z')`;
  }

  function spotTick() {
    if (!spot) return;
    const { video: v, box, deco } = spot;
    if (!v.isConnected || (box && !box.contains(v))) return spotOff();
    const r = (box || v).getBoundingClientRect();
    if (!box) Object.assign(deco.style, { left: r.left + 'px', top: r.top + 'px', width: r.width + 'px', height: r.height + 'px' });

    // fade the dim out as the player scrolls away / under the header
    const W = innerWidth, H = innerHeight;
    const vis = (Math.max(0, Math.min(r.bottom, H) - Math.max(r.top, 0)) / (r.height || 1)) *
                (Math.max(0, Math.min(r.right, W) - Math.max(r.left, 0)) / (r.width || 1));
    const k = Math.min(1, Math.max(0, (vis - 0.45) / 0.35));  // <45% visible -> page back to normal
    const a = document.fullscreenElement || !r.width ? 0 : k;
    const op = a.toFixed(2);
    if (backdrop.style.opacity !== op) { backdrop.style.opacity = op; hole.style.opacity = op; }

    if (spot.frame++ % 20 === 0) {
      // fullscreen: the player is the whole panel, so follow the screen's own corners
      // (top and bottom differ on notched MacBooks); otherwise follow the player's rounding
      const fs = document.fullscreenElement;
      const rad = cornerRadius(box || v, v);
      const [rt, rb] = fs && fs.contains(deco) ? [S.scrTop, S.scrBottom] : [rad, rad];
      const rkey = rt + '/' + rb;
      if (rkey !== spot.rkey) {
        spot.rkey = rkey;
        spot.radius = rt;
        hole.style.borderRadius = deco.style.borderRadius = `${rt}px ${rt}px ${rb}px ${rb}px`;
        deco.style.setProperty('--tf-rt', rt + 'px');
        deco.style.setProperty('--tf-rb', rb + 'px');
      }
    }
    const l = Math.round(r.left), t = Math.round(r.top), rr = Math.round(r.right), b = Math.round(r.bottom);
    const key = [l, t, rr, b, spot.radius, innerWidth, innerHeight].join(',');
    if (spot.key !== key) {
      spot.key = key;
      backdrop.style.clipPath = holePath(l, t, rr, b, spot.radius);
      Object.assign(hole.style, { left: l + 'px', top: t + 'px', width: rr - l + 'px', height: b - t + 'px' });
    }
    spot.raf = requestAnimationFrame(spotTick);
  }

  // ---------- enter / exit ----------
  function enter(v) {
    build();
    const r = v.getBoundingClientRect();
    const ph = document.createElement('div');
    ph.className = 'tf-placeholder';
    ph.textContent = '◆ IN FOCUS — CLICK TO RETURN';
    ph.style.cssText = `width:${r.width}px;height:${r.height}px;`;
    ph.addEventListener('click', (e) => { e.preventDefault(); e.stopPropagation(); exit(); }, true);

    active = { video: v, ph, style: v.getAttribute('style'), controls: v.controls };
    v.parentNode.insertBefore(ph, v);
    stage.appendChild(v);            // a synchronous move keeps playback going
    v.controls = false;
    v.classList.add('tf-video');
    scrollStart = scrollY;
    mode = S.mode;

    // popout animation: start exactly where the video was, then morph to the stage
    frame.classList.remove('tf-anim');
    place(r.left, r.top, r.width, r.height);
    root.classList.add('tf-on');
    root.classList.toggle('tf-dock', mode === 'dock');
    frame.offsetWidth;
    frame.classList.add('tf-anim');
    layout(true);
    ui.title.textContent = document.title.replace(/ - YouTube$/, '');
    ui.vol.value = v.muted ? 0 : v.volume;
    wake();
    cancelAnimationFrame(raf);
    tick();
  }

  function exit(instant = false) {
    if (!active) return;
    const a = active;
    active = null;
    cancelAnimationFrame(raf);
    if (document.fullscreenElement === frame) document.exitFullscreen().catch(() => {});

    const restore = () => {
      const v = a.video;
      v.classList.remove('tf-video');
      a.style == null ? v.removeAttribute('style') : v.setAttribute('style', a.style);
      v.controls = a.controls;
      if (a.ph.isConnected) a.ph.replaceWith(v);
      else { v.pause(); v.remove(); }   // the site re-rendered and dropped the slot
      if (!active) root.classList.remove('tf-on', 'tf-dock');
    };
    if (instant || !a.ph.isConnected) return restore();
    const r = a.ph.getBoundingClientRect();
    root.classList.remove('tf-dock');
    place(r.left, r.top, r.width, r.height);
    setTimeout(restore, 380);
  }

  // ---------- layout ----------
  function place(x, y, w, h) {
    Object.assign(frame.style, { left: x + 'px', top: y + 'px', width: w + 'px', height: h + 'px' });
  }
  function layout() {
    if (!active || document.fullscreenElement === frame) return;
    const v = active.video;
    const ar = v.videoWidth && v.videoHeight ? v.videoWidth / v.videoHeight : 16 / 9;
    const W = innerWidth, H = innerHeight;
    if (mode === 'dock') {
      const w = Math.min(560, W * 0.4), h = w / ar;
      place(W - w - 24, H - h - 24, w, h);
    } else {
      const w = Math.min(W * 0.86, H * 0.8 * ar), h = w / ar;
      place((W - w) / 2, (H - h) / 2, w, h);
    }
    ui.mode.textContent = mode === 'dock' ? '⬒ THEATER' : '⬓ DOCK';
  }
  function setMode(m, persist = true) {
    mode = m;
    scrollStart = scrollY;
    root.classList.toggle('tf-dock', m === 'dock');
    if (persist) chrome.storage.sync.set({ mode: m });
    layout();
  }

  // ---------- controls ----------
  function onHudClick(e) {
    const v = active?.video;
    if (!v) return;
    const a = e.target.closest('[data-a]')?.dataset.a;
    if (!a && e.target === ui.surface) return togglePlay(v);
    switch (a) {
      case 'play': togglePlay(v); break;
      case 'back': v.currentTime = Math.max(0, v.currentTime - 10); flash('« 10'); break;
      case 'fwd': v.currentTime = Math.min(v.duration || 1e9, v.currentTime + 10); flash('10 »'); break;
      case 'mute': v.muted = !v.muted; ui.vol.value = v.muted ? 0 : v.volume; break;
      case 'speed': {
        const rates = [0.5, 0.75, 1, 1.25, 1.5, 2];
        v.playbackRate = rates[(rates.indexOf(v.playbackRate) + 1) % rates.length] || 1;
        flash(v.playbackRate + '×'); break;
      }
      case 'pip': (document.pictureInPictureElement ? document.exitPictureInPicture() : v.requestPictureInPicture()).catch(() => {}); break;
      case 'fs': toggleFs(); break;
      case 'mode': setMode(mode === 'dock' ? 'theater' : 'dock'); break;
      case 'close': exit(); break;
    }
  }
  function togglePlay(v) { v.paused ? v.play() : v.pause(); flash(v.paused ? '❚❚' : '▶'); }
  function toggleFs() {
    document.fullscreenElement ? document.exitFullscreen() : frame.requestFullscreen().catch(() => {});
  }
  function seekTo(e) {
    const v = active?.video;
    if (!v || !isFinite(v.duration)) return;
    const r = ui.seek.getBoundingClientRect();
    v.currentTime = Math.min(1, Math.max(0, (e.clientX - r.left) / r.width)) * v.duration;
  }
  function hoverTime(e) {
    const v = active?.video;
    if (!v || !isFinite(v.duration)) return;
    const r = ui.seek.getBoundingClientRect();
    const p = Math.min(1, Math.max(0, (e.clientX - r.left) / r.width));
    ui.tip.textContent = fmt(p * v.duration);
    ui.tip.style.left = p * 100 + '%';
    ui.tip.style.opacity = 1;
  }
  // small readout shown inside whatever is fullscreen (the top layer hides everything else)
  let toastEl, toastTimer = 0;
  function toast(text) {
    const host = document.fullscreenElement || document.documentElement;
    if (!toastEl) {
      toastEl = document.createElement('div');
      toastEl.style.cssText = 'position:fixed;left:50%;top:48px;transform:translateX(-50%);z-index:2147483647;pointer-events:none;' +
        'padding:8px 14px;background:rgba(0,8,12,.9);border:1px solid var(--tf-c,#00f0ff);color:var(--tf-c,#00f0ff);' +
        'font:600 12px/1 ui-monospace,"JetBrains Mono",monospace;letter-spacing:.15em;box-shadow:0 0 16px color-mix(in srgb,var(--tf-c,#00f0ff) 40%,transparent);' +
        'transition:opacity .3s';
    }
    toastEl.textContent = text;
    if (toastEl.parentNode !== host) host.appendChild(toastEl);
    toastEl.style.opacity = 1;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { toastEl.style.opacity = 0; }, 1600);
  }

  function flash(t) {
    ui.flash.textContent = t;
    ui.flash.classList.remove('go'); ui.flash.offsetWidth; ui.flash.classList.add('go');
  }
  function wake() {
    ui.shell.classList.add('awake');
    sleep(2600);
  }
  function sleep(ms) {
    clearTimeout(hideTimer);
    hideTimer = setTimeout(() => { if (!dragging && !active?.video.paused) ui.shell.classList.remove('awake'); }, ms);
  }
  const fmt = (s) => {
    if (!isFinite(s)) return 'LIVE';
    s = Math.floor(s);
    const h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60, x = String(s % 60).padStart(2, '0');
    return h ? `${h}:${String(m).padStart(2, '0')}:${x}` : `${m}:${x}`;
  };

  function tick() {
    const v = active?.video;
    if (!v) return;
    if (v.parentNode !== stage) return exit(true);  // site pulled the element away
    const d = v.duration, t = v.currentTime;
    const p = isFinite(d) && d ? t / d : 0;
    ui.fill.style.width = p * 100 + '%';
    ui.knob.style.left = p * 100 + '%';
    if (v.buffered.length && isFinite(d)) ui.buf.style.width = (v.buffered.end(v.buffered.length - 1) / d) * 100 + '%';
    ui.time.textContent = `${fmt(t)} / ${fmt(d)}`;
    ui.play.textContent = v.paused ? '▶' : '❚❚';
    ui.mute.textContent = v.muted || v.volume === 0 ? 'MUTE' : 'VOL';
    ui.speed.textContent = v.playbackRate + '×';
    ui.shell.classList.toggle('paused', v.paused);
    if (v.paused) ui.shell.classList.add('awake');
    raf = requestAnimationFrame(tick);
  }

  const HUD_HTML = `
<style>
  :host { all: initial; }
  * { box-sizing: border-box; }
  .shell { position: absolute; inset: 0; font: 500 12px/1 ui-monospace, "JetBrains Mono", "Fira Code", monospace;
           color: var(--tf-fg); letter-spacing: .08em; cursor: none; }
  .shell.awake { cursor: default; }
  .surface { position: absolute; inset: 0; }
  .corner { position: absolute; width: 22px; height: 22px; border: 2px solid var(--tf-c); filter: drop-shadow(0 0 6px var(--tf-c)); pointer-events: none; }
  .c1 { top: 8px; left: 8px; border-right: 0; border-bottom: 0; border-top-left-radius: var(--tf-hud-rt, 0); }
  .c2 { top: 8px; right: 8px; border-left: 0; border-bottom: 0; border-top-right-radius: var(--tf-hud-rt, 0); }
  .c3 { bottom: 8px; left: 8px; border-right: 0; border-top: 0; border-bottom-left-radius: var(--tf-hud-rb, 0); }
  .c4 { bottom: 8px; right: 8px; border-left: 0; border-top: 0; border-bottom-right-radius: var(--tf-hud-rb, 0); }
  .scan { position: absolute; left: 0; right: 0; top: 0; height: 2px; pointer-events: none;
          background: linear-gradient(90deg, transparent, var(--tf-c), transparent); box-shadow: 0 0 12px var(--tf-c);
          animation: scan 4s linear infinite; opacity: .5; }
  @keyframes scan { from { top: 0 } to { top: 100% } }
  .bar { position: absolute; left: 0; right: 0; padding: 14px 18px; display: flex; align-items: center; gap: 10px;
         opacity: 0; transform: translateY(var(--dy)); transition: opacity .25s, transform .25s; }
  .awake .bar { opacity: 1; transform: none; }
  .top { top: 0; --dy: -8px; background: linear-gradient(rgba(0,8,14,.85), transparent); }
  .bottom { bottom: 0; --dy: 8px; flex-direction: column; align-items: stretch; gap: 10px;
            background: linear-gradient(transparent, rgba(0,8,14,.92)); padding-top: 40px; }
  .tag { color: var(--tf-c); text-shadow: 0 0 8px var(--tf-c); font-weight: 700; letter-spacing: .3em; }
  .title { flex: 1; overflow: hidden; white-space: nowrap; text-overflow: ellipsis; color: var(--tf-fg); opacity: .85; }
  .row { display: flex; align-items: center; gap: 8px; }
  .sp { flex: 1; }
  button { all: unset; cursor: pointer; padding: 7px 10px; border: 1px solid color-mix(in srgb, var(--tf-c) 45%, transparent);
           color: var(--tf-fg); background: color-mix(in srgb, var(--tf-c) 6%, transparent); clip-path: polygon(6px 0,100% 0,100% calc(100% - 6px),calc(100% - 6px) 100%,0 100%,0 6px);
           transition: background .15s, color .15s, box-shadow .15s; min-width: 14px; text-align: center; }
  button:hover { background: var(--tf-c); color: #001014; box-shadow: 0 0 16px var(--tf-c); }
  button.big { font-size: 14px; padding: 7px 14px; border-color: var(--tf-c); }
  button.x:hover { background: #ff3b5c; box-shadow: 0 0 16px #ff3b5c; border-color: #ff3b5c; }
  .time { color: var(--tf-c); min-width: 110px; }
  .seek { position: relative; height: 18px; cursor: pointer; touch-action: none; }
  .seek::before, .buf, .fill { content: ""; position: absolute; left: 0; top: 8px; height: 3px; }
  .seek::before { right: 0; background: color-mix(in srgb, var(--tf-c) 15%, transparent); }
  .buf { background: color-mix(in srgb, var(--tf-c) 30%, transparent); }
  .fill { background: var(--tf-c); box-shadow: 0 0 10px var(--tf-c), 0 0 20px var(--tf-c); }
  .seek:hover .buf, .seek:hover .fill, .seek:hover::before { top: 7px; height: 5px; }
  .knob { position: absolute; top: 4px; width: 10px; height: 10px; margin-left: -5px; background: #001014;
          border: 2px solid var(--tf-c); transform: rotate(45deg); box-shadow: 0 0 12px var(--tf-c); }
  .tip { position: absolute; bottom: 22px; transform: translateX(-50%); padding: 4px 6px; background: #001014;
         border: 1px solid var(--tf-c); opacity: 0; pointer-events: none; transition: opacity .15s; }
  input[type=range] { -webkit-appearance: none; appearance: none; width: 80px; height: 3px; background: color-mix(in srgb, var(--tf-c) 25%, transparent); outline: none; cursor: pointer; }
  input[type=range]::-webkit-slider-thumb { -webkit-appearance: none; width: 10px; height: 10px; background: var(--tf-c); transform: rotate(45deg); box-shadow: 0 0 8px var(--tf-c); }
  .flash { position: absolute; left: 50%; top: 50%; transform: translate(-50%,-50%); font-size: 34px; color: var(--tf-c);
           text-shadow: 0 0 18px var(--tf-c); pointer-events: none; opacity: 0; }
  .flash.go { animation: fl .6s ease-out; }
  @keyframes fl { 0% { opacity: 1; transform: translate(-50%,-50%) scale(.8) } 100% { opacity: 0; transform: translate(-50%,-50%) scale(1.4) } }
  .paused .flash { }
  @media (max-width: 620px) { .hide-s { display: none; } }
</style>
<div class="shell" data-k="shell">
  <div class="surface" data-k="surface"></div>
  <div class="scan"></div>
  <i class="corner c1"></i><i class="corner c2"></i><i class="corner c3"></i><i class="corner c4"></i>
  <div class="flash" data-k="flash"></div>
  <div class="bar top">
    <span class="tag">◆ FOCUS</span>
    <span class="title" data-k="title"></span>
    <button data-a="mode" data-k="mode">⬓ DOCK</button>
    <button class="x" data-a="close" title="Exit (Esc)">✕</button>
  </div>
  <div class="bar bottom">
    <div class="seek" data-k="seek"><div class="buf" data-k="buf"></div><div class="fill" data-k="fill"></div><div class="knob" data-k="knob"></div><div class="tip" data-k="tip"></div></div>
    <div class="row">
      <button class="big" data-a="play" data-k="play">▶</button>
      <button data-a="back" class="hide-s">«10</button>
      <button data-a="fwd" class="hide-s">10»</button>
      <span class="time" data-k="time">0:00 / 0:00</span>
      <span class="sp"></span>
      <button data-a="mute" data-k="mute">VOL</button>
      <input type="range" data-k="vol" min="0" max="1" step="0.01" class="hide-s">
      <button data-a="speed" data-k="speed">1×</button>
      <button data-a="pip" class="hide-s">PiP</button>
      <button data-a="fs" title="Fullscreen (double-click)">⛶</button>
    </div>
  </div>
</div>`;
})();
