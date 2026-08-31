'use strict';

// ============================================================
// State
// ============================================================

let cameras = [];        // [{id, label}] from /cameras.json
let focusedId = null;    // camera id currently in focus mode, or null
let pipMainId = null;    // camera promoted to the PiP main slot, or null
let slideshowActive = false;
let slideshowTimer = null;
let pingTimers = {};     // {camId: intervalId}
let statuses = {};       // {camId: 'unknown'|'online'|'degraded'|'offline'}
let fails = {};          // {camId: consecutive failed probes}
let toolbarHideTimer = null;
let toolbarAutoHide = false;

const PREFS_KEY = 'maks-cams-prefs';
const SLIDESHOW_INTERVALS = [5, 10, 15, 30, 60]; // seconds

// A camera is only pulled out of the grid after this many consecutive failed
// probes, so a single dropped packet doesn't reflow the whole page.
export const FAIL_LIMIT = 2;

let prefs = {
  layout: 'layout-auto',
  enabled: {},        // {camId: bool}
  slideshowInterval: 10,  // seconds
  autoHideToolbar: false,
  collapseDead: true,
};

// ============================================================
// Pure decision logic (exported for test.mjs)
//
// A "state" is {id, enabled, status, fails} — see camStates().
// ============================================================

export function probeStatus(ok, ms) {
  if (!ok) return 'offline';
  return ms < 300 ? 'online' : 'degraded';
}

export function isLive(state) {
  return state.enabled && (state.status === 'online' || state.status === 'degraded');
}

// Cameras to pull out of the grid: switched off, or offline past FAIL_LIMIT.
// When that would empty the grid entirely, collapse nothing — a page of dead
// tiles beats a page of nothing.
export function collapsedIds(states, collapseEnabled) {
  if (!collapseEnabled) return [];
  const dead = states.filter(function (s) {
    return !s.enabled || s.fails >= FAIL_LIMIT;
  });
  if (dead.length === states.length) return [];
  return dead.map(function (s) { return s.id; });
}

// Which camera gets the big PiP slot: the promoted one if it is still visible,
// else the first live one, else whatever is left.
export function pickPipMain(states, collapsed, preferredId) {
  const visible = states.filter(function (s) { return collapsed.indexOf(s.id) === -1; });
  if (visible.length === 0) return null;
  const preferred = visible.find(function (s) { return s.id === preferredId; });
  if (preferred) return preferred.id;
  const live = visible.find(isLive);
  return (live || visible[0]).id;
}

// Slideshow skips dead feeds, but never dead-ends: with nothing live it falls
// back to every enabled camera.
export function slideshowOrder(states) {
  const enabled = states.filter(function (s) { return s.enabled; });
  const live = enabled.filter(isLive);
  return (live.length ? live : enabled).map(function (s) { return s.id; });
}

// The iframe holds a dead error page until something reloads it.
export function shouldReload(prevStatus, nextStatus) {
  return prevStatus === 'offline' && nextStatus !== 'offline';
}

// ============================================================
// Preferences persistence
// ============================================================

function loadPrefs() {
  try {
    const raw = localStorage.getItem(PREFS_KEY);
    if (raw) {
      Object.assign(prefs, JSON.parse(raw));
    }
  } catch (_) {}
}

function savePrefs() {
  try {
    localStorage.setItem(PREFS_KEY, JSON.stringify(prefs));
  } catch (_) {}
}

// ============================================================
// Camera URL construction
// ============================================================

function buildCameraUrl(camId) {
  const host = window.location.hostname;
  const protocol = window.location.protocol;
  const parts = host.split('.');
  const newHost = parts[0] + '-' + camId + '.' + parts.slice(1).join('.');
  return protocol + '//' + newHost + '/cam';
}

// ============================================================
// Rendering
// ============================================================

function renderCameras() {
  const grid = document.getElementById('grid');
  grid.innerHTML = '';

  cameras.forEach(function (cam) {
    const enabled = prefs.enabled[cam.id] !== false;
    const url = buildCameraUrl(cam.id);
    const card = createCameraCard(cam, url, enabled);
    grid.appendChild(card);
  });
}

function createCameraCard(cam, url, enabled) {
  const card = document.createElement('div');
  card.className = 'cam-card' + (enabled ? '' : ' disabled');
  card.dataset.camId = cam.id;
  card.dataset.url = url;

  // Iframe
  const iframe = document.createElement('iframe');
  iframe.className = 'cam-iframe';
  iframe.allowFullscreen = true;
  if (enabled) {
    iframe.src = url;
  }
  card.appendChild(iframe);

  // Disabled placeholder
  const placeholder = document.createElement('div');
  placeholder.className = 'cam-placeholder';
  placeholder.innerHTML = svgVideoOff(32) + '<span>Disabled</span>';
  card.appendChild(placeholder);

  // Status dot
  const statusDot = document.createElement('div');
  statusDot.className = 'cam-status';
  statusDot.dataset.status = 'unknown';
  statusDot.title = 'Checking…';
  card.appendChild(statusDot);

  // Label
  const label = document.createElement('div');
  label.className = 'cam-label';
  label.textContent = cam.label;
  card.appendChild(label);

  // Latency display
  const latency = document.createElement('div');
  latency.className = 'cam-latency';
  latency.textContent = '';
  card.appendChild(latency);

  // Controls
  const controls = document.createElement('div');
  controls.className = 'cam-controls';

  // Toggle enable/disable
  const toggleBtn = document.createElement('button');
  toggleBtn.className = 'cam-ctrl-btn toggle-btn' + (enabled ? '' : ' is-disabled');
  toggleBtn.title = enabled ? 'Disable camera' : 'Enable camera';
  toggleBtn.setAttribute('aria-label', enabled ? 'Disable camera' : 'Enable camera');
  toggleBtn.setAttribute('aria-pressed', enabled ? 'true' : 'false');
  toggleBtn.innerHTML = enabled ? svgEye(16) : svgEyeOff(16);
  toggleBtn.addEventListener('click', function (e) {
    e.stopPropagation();
    toggleCamera(cam.id);
  });
  controls.appendChild(toggleBtn);

  // Open in new tab
  const tabBtn = document.createElement('button');
  tabBtn.className = 'cam-ctrl-btn';
  tabBtn.title = 'Open in new tab';
  tabBtn.setAttribute('aria-label', 'Open ' + cam.label + ' in new tab');
  tabBtn.innerHTML = svgExternalLink(16);
  tabBtn.addEventListener('click', function (e) {
    e.stopPropagation();
    window.open(url, '_blank', 'noopener');
  });
  controls.appendChild(tabBtn);

  // Fullscreen / focus
  const focusBtn = document.createElement('button');
  focusBtn.className = 'cam-ctrl-btn';
  focusBtn.title = 'Fullscreen';
  focusBtn.setAttribute('aria-label', 'Fullscreen ' + cam.label);
  focusBtn.innerHTML = svgMaximize(16);
  focusBtn.addEventListener('click', function (e) {
    e.stopPropagation();
    if (focusedId === cam.id) {
      exitFocus();
    } else {
      enterFocus(cam.id);
    }
  });
  controls.appendChild(focusBtn);

  card.appendChild(controls);

  // Click card body (not buttons): promote into the PiP main slot, or focus
  card.addEventListener('click', function (e) {
    if (e.target === card || e.target === iframe || e.target === label || e.target === placeholder) {
      if (prefs.layout === 'layout-pip' && !card.classList.contains('pip-main')) {
        pipMainId = cam.id;
        refresh();
        return;
      }
      if (focusedId === cam.id) {
        exitFocus();
      } else {
        enterFocus(cam.id);
      }
    }
  });

  return card;
}

// ============================================================
// Collapsed strip / layout refresh
// ============================================================

function camStates() {
  return cameras.map(function (cam) {
    return {
      id: cam.id,
      enabled: prefs.enabled[cam.id] !== false,
      status: statuses[cam.id] || 'unknown',
      fails: fails[cam.id] || 0,
    };
  });
}

let stripKey = null;

function renderStrip(collapsed) {
  const strip = document.getElementById('strip');
  // refresh() runs on every probe; rebuilding unchanged rows would throw away
  // keyboard focus a few times a minute.
  const key = collapsed.map(function (id) {
    return id + ':' + (prefs.enabled[id] !== false);
  }).join(',');
  if (key === stripKey) return;
  stripKey = key;

  strip.innerHTML = '';

  collapsed.forEach(function (camId) {
    const cam = cameras.find(function (c) { return c.id === camId; });
    if (!cam) return;
    const enabled = prefs.enabled[camId] !== false;

    const row = document.createElement('div');
    row.className = 'strip-row';

    const dot = document.createElement('span');
    dot.className = 'cam-status strip-dot';
    dot.dataset.status = enabled ? 'offline' : 'unknown';
    row.appendChild(dot);

    const label = document.createElement('span');
    label.className = 'strip-label';
    label.textContent = cam.label;
    row.appendChild(label);

    const state = document.createElement('span');
    state.className = 'strip-state';
    state.textContent = enabled ? 'Offline' : 'Disabled';
    row.appendChild(state);

    if (!enabled) {
      const btn = document.createElement('button');
      btn.className = 'cam-ctrl-btn strip-btn';
      btn.title = 'Enable camera';
      btn.setAttribute('aria-label', 'Enable ' + cam.label);
      btn.innerHTML = svgEyeOff(14);
      btn.addEventListener('click', function () { setCameraEnabled(camId, true); });
      row.appendChild(btn);
    }

    strip.appendChild(row);
  });
}

// Recompute everything derived from camera state. Never touches iframe.src —
// a layout change must not restart the WebRTC streams.
function refresh() {
  const grid = document.getElementById('grid');
  const strip = document.getElementById('strip');
  const states = camStates();
  const collapsed = collapsedIds(states, prefs.collapseDead !== false);

  if (focusedId && collapsed.indexOf(focusedId) !== -1) {
    exitFocus();
  }

  const mainId = pickPipMain(states, collapsed, pipMainId);

  cameras.forEach(function (cam) {
    const card = getCard(cam.id);
    if (!card) return;
    card.classList.toggle('collapsed', collapsed.indexOf(cam.id) !== -1);
    card.classList.toggle('pip-main', cam.id === mainId);
  });

  renderStrip(collapsed);

  const secondary = states.length - collapsed.length - (mainId ? 1 : 0);
  grid.style.setProperty('--pip-cols', String(Math.max(secondary, 1)));
  grid.classList.toggle('pip-solo', secondary <= 0);

  // Focus mode owns the whole viewport; the strip would only be in the way.
  strip.style.display = focusedId ? 'none' : '';
  const stripHeight = focusedId ? 0 : strip.offsetHeight;
  grid.style.bottom = stripHeight ? stripHeight + 'px' : '';
  document.getElementById('slideshow-progress').style.bottom =
    stripHeight ? stripHeight + 'px' : '';
}

// ============================================================
// Camera enable/disable
// ============================================================

function toggleCamera(camId) {
  const isEnabled = prefs.enabled[camId] !== false;
  setCameraEnabled(camId, !isEnabled);
}

function setCameraEnabled(camId, enabled) {
  prefs.enabled[camId] = enabled;
  savePrefs();

  const card = getCard(camId);
  if (!card) return;

  const iframe = card.querySelector('.cam-iframe');
  const toggleBtn = card.querySelector('.toggle-btn');
  const url = card.dataset.url;

  card.classList.toggle('disabled', !enabled);

  if (enabled) {
    if (!iframe.src || iframe.src === window.location.href) {
      iframe.src = url;
    }
    toggleBtn.innerHTML = svgEye(16);
    toggleBtn.title = 'Disable camera';
    toggleBtn.setAttribute('aria-label', 'Disable camera');
    toggleBtn.setAttribute('aria-pressed', 'true');
    toggleBtn.classList.remove('is-disabled');
    startPing(camId);
  } else {
    iframe.src = '';
    toggleBtn.innerHTML = svgEyeOff(16);
    toggleBtn.title = 'Enable camera';
    toggleBtn.setAttribute('aria-label', 'Enable camera');
    toggleBtn.setAttribute('aria-pressed', 'false');
    toggleBtn.classList.add('is-disabled');
    stopPing(camId);
    statuses[camId] = 'unknown';
    fails[camId] = 0;
    setStatus(camId, 'unknown', '');
    // Exit focus if this camera was focused
    if (focusedId === camId) {
      exitFocus();
    }
  }

  refresh();
}

function enableAll() {
  cameras.forEach(function (cam) {
    if (prefs.enabled[cam.id] === false) {
      setCameraEnabled(cam.id, true);
    }
  });
}

function disableAll() {
  cameras.forEach(function (cam) {
    setCameraEnabled(cam.id, false);
  });
  if (slideshowActive) stopSlideshow();
}

function setCollapseDead(enabled) {
  prefs.collapseDead = enabled;
  savePrefs();
  const btn = document.getElementById('collapse-btn');
  btn.classList.toggle('active', enabled);
  btn.setAttribute('aria-pressed', enabled ? 'true' : 'false');
  refresh();
}

// ============================================================
// Focus / Fullscreen
// ============================================================

function enterFocus(camId) {
  const card = getCard(camId);
  if (!card) return;

  // Exit previous focus if any
  if (focusedId) {
    const prev = getCard(focusedId);
    if (prev) prev.classList.remove('focused');
  }

  focusedId = camId;
  card.classList.add('focused');
  document.getElementById('grid').classList.add('has-focus');
  refresh();

  // Try native fullscreen (may not work in iOS PWA)
  if (document.fullscreenEnabled && !document.fullscreenElement) {
    card.requestFullscreen().catch(function () {});
  }
}

function exitFocus() {
  if (focusedId) {
    const card = getCard(focusedId);
    if (card) card.classList.remove('focused');
  }
  focusedId = null;
  document.getElementById('grid').classList.remove('has-focus');

  if (document.fullscreenElement) {
    document.exitFullscreen().catch(function () {});
  }

  if (slideshowActive) stopSlideshow();
  refresh();
}

function focusStep(direction) {
  const order = slideshowOrder(camStates());
  if (order.length === 0) return;
  const idx = order.indexOf(focusedId);
  const next = order[(idx + direction + order.length) % order.length];
  enterFocus(next);
}

function focusNext() { focusStep(1); }
function focusPrev() { focusStep(-1); }

// ============================================================
// Slideshow
// ============================================================

function toggleSlideshow() {
  if (slideshowActive) {
    stopSlideshow();
  } else {
    startSlideshow();
  }
}

function startSlideshow() {
  const order = slideshowOrder(camStates());
  if (order.length === 0) return;

  slideshowActive = true;
  document.getElementById('slideshow-btn').classList.add('active');

  // Focus first camera if none focused
  if (!focusedId || order.indexOf(focusedId) === -1) {
    enterFocus(order[0]);
  }

  scheduleNext();
}

function stopSlideshow() {
  slideshowActive = false;
  document.getElementById('slideshow-btn').classList.remove('active');
  clearTimeout(slideshowTimer);
  const bar = document.getElementById('slideshow-progress');
  bar.classList.remove('visible');
  bar.style.width = '0%';
  bar.style.transition = 'none';
}

function scheduleNext() {
  clearTimeout(slideshowTimer);

  const ms = prefs.slideshowInterval * 1000;
  const bar = document.getElementById('slideshow-progress');
  bar.style.transition = 'none';
  bar.style.width = '0%';
  bar.classList.add('visible');

  // Animate progress bar
  requestAnimationFrame(function () {
    bar.style.transition = 'width ' + ms + 'ms linear';
    bar.style.width = '100%';
  });

  slideshowTimer = setTimeout(function () {
    if (!slideshowActive) return;
    focusNext();
    scheduleNext();
  }, ms);
}

function cycleInterval() {
  const idx = SLIDESHOW_INTERVALS.indexOf(prefs.slideshowInterval);
  prefs.slideshowInterval = SLIDESHOW_INTERVALS[(idx + 1) % SLIDESHOW_INTERVALS.length];
  savePrefs();
  document.getElementById('interval-label').textContent = prefs.slideshowInterval + 's';
  if (slideshowActive) {
    scheduleNext(); // restart with new interval
  }
}

// ============================================================
// Layout
// ============================================================

const LAYOUTS = ['layout-auto', 'layout-column', 'layout-2x2', 'layout-pip'];

function setLayout(layout) {
  if (!LAYOUTS.includes(layout)) return;
  prefs.layout = layout;
  savePrefs();

  const grid = document.getElementById('grid');
  LAYOUTS.forEach(function (l) { grid.classList.remove(l); });
  grid.classList.add(layout);

  document.querySelectorAll('[data-layout]').forEach(function (btn) {
    btn.classList.toggle('active', btn.dataset.layout === layout);
  });

  refresh();
}

// ============================================================
// Connectivity monitoring
// ============================================================

function startPing(camId) {
  stopPing(camId);
  pingOnce(camId); // immediate first check
  pingTimers[camId] = setInterval(function () { pingOnce(camId); }, 15000);
}

function stopPing(camId) {
  if (pingTimers[camId]) {
    clearInterval(pingTimers[camId]);
    delete pingTimers[camId];
  }
}

function pingOnce(camId) {
  const card = getCard(camId);
  if (!card) return;
  if (prefs.enabled[camId] === false) return;

  const t0 = Date.now();

  // Same-origin, proxied to the camera by Caddy. Probing the camera host
  // directly cannot work: a cross-origin response is unreadable without CORS
  // headers, and neither MediaMTX nor Traefik's 502 page sends any — so every
  // camera, live or dead, came back as a rejected fetch.
  fetch('/probe/' + camId, { cache: 'no-store' })
    .then(function (resp) { finishPing(camId, resp.ok, Date.now() - t0); })
    .catch(function () { finishPing(camId, false, 0); });
}

function finishPing(camId, ok, ms) {
  const prev = statuses[camId] || 'unknown';
  const next = probeStatus(ok, ms);

  statuses[camId] = next;
  fails[camId] = ok ? 0 : (fails[camId] || 0) + 1;

  setStatus(camId, next, ok ? ms + ' ms' : 'Offline');
  if (shouldReload(prev, next)) reloadFeed(camId);
  refresh();
}

function reloadFeed(camId) {
  const card = getCard(camId);
  if (!card) return;
  const iframe = card.querySelector('.cam-iframe');
  const url = card.dataset.url;
  // about:blank first: re-assigning the same src is a no-op in some browsers.
  iframe.src = 'about:blank';
  setTimeout(function () { iframe.src = url; }, 0);
}

function setStatus(camId, status, text) {
  const card = getCard(camId);
  if (!card) return;
  const dot = card.querySelector('.cam-status');
  const lat = card.querySelector('.cam-latency');
  if (dot) { dot.dataset.status = status; dot.title = text || status; }
  if (lat) { lat.textContent = text || ''; }
}

// ============================================================
// Toolbar auto-hide
// ============================================================

function setAutoHide(enabled) {
  toolbarAutoHide = enabled;
  prefs.autoHideToolbar = enabled;
  savePrefs();
  const btn = document.getElementById('autohide-btn');
  btn.classList.toggle('active', enabled);
  btn.setAttribute('aria-pressed', enabled ? 'true' : 'false');
  showToolbar(); // always run: schedules hide timer when enabled, clears it when disabled
}

function showToolbar() {
  clearTimeout(toolbarHideTimer);
  const tb = document.getElementById('toolbar');
  const grid = document.getElementById('grid');
  tb.classList.remove('hidden');
  grid.classList.remove('toolbar-hidden');
  if (toolbarAutoHide) {
    toolbarHideTimer = setTimeout(hideToolbar, 3000);
  }
}

function hideToolbar() {
  const tb = document.getElementById('toolbar');
  const grid = document.getElementById('grid');
  tb.classList.add('hidden');
  grid.classList.add('toolbar-hidden');
}

// ============================================================
// Helpers
// ============================================================

function getCard(camId) {
  return document.querySelector('.cam-card[data-cam-id="' + camId + '"]');
}

// ============================================================
// SVG icons (inline, no external dependencies)
// ============================================================

function svgIcon(size, path) {
  return '<svg width="' + size + '" height="' + size + '" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' + path + '</svg>';
}

function svgEye(s) {
  return svgIcon(s, '<path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/>');
}

function svgEyeOff(s) {
  return svgIcon(s, '<path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94"/><path d="M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19"/><line x1="1" y1="1" x2="23" y2="23"/>');
}

function svgExternalLink(s) {
  return svgIcon(s, '<path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/><polyline points="15 3 21 3 21 9"/><line x1="10" y1="14" x2="21" y2="3"/>');
}

function svgMaximize(s) {
  return svgIcon(s, '<path d="M8 3H5a2 2 0 0 0-2 2v3"/><path d="M21 8V5a2 2 0 0 0-2-2h-3"/><path d="M3 16v3a2 2 0 0 0 2 2h3"/><path d="M16 21h3a2 2 0 0 0 2-2v-3"/>');
}

function svgVideoOff(s) {
  return svgIcon(s, '<line x1="1" y1="1" x2="23" y2="23"/><path d="M21 21H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h3m3-3h6l2 3h2a2 2 0 0 1 2 2v9.34"/><path d="M15 13a3 3 0 1 1-3-3"/>');
}

// ============================================================
// Keyboard shortcuts
// ============================================================

function initKeyboard() {
  document.addEventListener('keydown', function (e) {
    // Escape: exit focus / stop slideshow
    if (e.key === 'Escape') {
      if (slideshowActive) stopSlideshow();
      if (focusedId) exitFocus();
      return;
    }

    // Arrow keys: cycle cameras when focused
    if (e.key === 'ArrowRight' || e.key === 'ArrowDown') {
      e.preventDefault();
      if (focusedId) {
        focusNext();
        if (slideshowActive) scheduleNext();
      }
      return;
    }

    if (e.key === 'ArrowLeft' || e.key === 'ArrowUp') {
      e.preventDefault();
      if (focusedId) {
        focusPrev();
        if (slideshowActive) scheduleNext();
      }
      return;
    }

    // Space: toggle slideshow
    if (e.key === ' ') {
      e.preventDefault();
      toggleSlideshow();
      return;
    }

    // F: toggle fullscreen on focused camera
    if (e.key === 'f' || e.key === 'F') {
      if (focusedId) {
        const card = getCard(focusedId);
        if (card) {
          if (document.fullscreenElement) {
            document.exitFullscreen().catch(function () {});
          } else {
            card.requestFullscreen().catch(function () {});
          }
        }
      }
      return;
    }
  });
}

// ============================================================
// Activity detection (for toolbar auto-hide)
// ============================================================

function initActivityDetection() {
  ['mousemove', 'touchstart', 'click', 'keydown'].forEach(function (evt) {
    document.addEventListener(evt, function () {
      if (toolbarAutoHide) showToolbar();
    }, { passive: true });
  });
}

// ============================================================
// Init
// ============================================================

async function init() {
  loadPrefs();

  // Load camera config
  let config;
  try {
    const resp = await fetch('/config/cameras.json');
    config = await resp.json();
  } catch (err) {
    document.getElementById('grid').innerHTML =
      '<div style="display:flex;align-items:center;justify-content:center;height:100%;color:rgba(255,255,255,0.4);font-size:14px;">Failed to load camera configuration</div>';
    return;
  }

  cameras = config.cameras || [];

  // Initialise enabled state for any new cameras (default: enabled)
  cameras.forEach(function (cam) {
    if (prefs.enabled[cam.id] === undefined) {
      prefs.enabled[cam.id] = true;
    }
  });

  // Render cameras
  renderCameras();

  // Apply saved layout
  setLayout(prefs.layout);

  // Restore slideshow interval label
  document.getElementById('interval-label').textContent = prefs.slideshowInterval + 's';

  // Restore auto-hide
  setAutoHide(prefs.autoHideToolbar);

  // Restore collapse-dead toggle
  setCollapseDead(prefs.collapseDead !== false);

  // Start connectivity pings for enabled cameras
  cameras.forEach(function (cam) {
    if (prefs.enabled[cam.id] !== false) {
      startPing(cam.id);
    }
  });

  // Wire up toolbar buttons
  document.querySelectorAll('[data-layout]').forEach(function (btn) {
    btn.addEventListener('click', function () { setLayout(btn.dataset.layout); });
  });

  document.getElementById('slideshow-btn').addEventListener('click', toggleSlideshow);
  document.getElementById('interval-btn').addEventListener('click', cycleInterval);
  document.getElementById('enable-all-btn').addEventListener('click', enableAll);
  document.getElementById('disable-all-btn').addEventListener('click', disableAll);
  document.getElementById('collapse-btn').addEventListener('click', function () {
    setCollapseDead(prefs.collapseDead === false);
  });
  document.getElementById('autohide-btn').addEventListener('click', function () {
    setAutoHide(!toolbarAutoHide);
  });

  initKeyboard();
  initActivityDetection();
}

if (typeof document !== 'undefined') {
  document.addEventListener('DOMContentLoaded', init);
}
