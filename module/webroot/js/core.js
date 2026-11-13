/* KonaManager UI - core: bridge, helpers, tabs, modals */
(function () {
  'use strict';

  var KM = window.KM = window.KM || {};
  KM.DM = '/data/adb/modules/daemon-manager/bin/dm';
  KM.T = { read: 12000, mut: 35000, once: 70000, install: 60000 };
  KM.RE = {
    id: /^[a-z0-9][a-z0-9-]{1,30}$/,
    pkg: /^[A-Za-z0-9_.]+$/,
    sha: /^[a-f0-9]{64}$/,
    job: /^j_[a-z0-9]+$/,
    token: /^t_[a-z0-9]+$/
  };
  KM.ICONS = {
    plus: '<path d="M12 5v14M5 12h14"></path>',
    refresh: '<path d="M20 11.5a8 8 0 1 1-2.6-5.9"></path><path d="M20 4v5h-5"></path>',
    play: '<path class="fill" d="M8 5.6v12.8a.8.8 0 0 0 1.22.68l10.1-6.4a.8.8 0 0 0 0-1.36L9.22 4.92A.8.8 0 0 0 8 5.6z"></path>',
    stop: '<rect class="fill" x="6.5" y="6.5" width="11" height="11" rx="2"></rect>',
    restart: '<path d="M4 12a8 8 0 1 0 2.3-5.6"></path><path d="M4 4v5h5"></path>',
    gear: '<circle cx="12" cy="12" r="3"></circle><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"></path>',
    trash: '<path d="M4 7h16M10 11v6M14 11v6M6 7l1 12a2 2 0 0 0 2 2h6a2 2 0 0 0 2-2l1-12M9 7V5a2 2 0 0 1 2-2h2a2 2 0 0 1 2 2v2"></path>',
    chevron: '<path d="m8 10 4 4 4-4"></path>',
    x: '<path d="M6 6l12 12M18 6L6 18"></path>',
    shield: '<path d="M12 3.5 19 6v5.2c0 4.4-2.9 7.6-7 9.3-4.1-1.7-7-4.9-7-9.3V6z"></path><path d="m9 12 2 2 4-4"></path>',
    terminal: '<rect x="3.5" y="4.5" width="17" height="15" rx="2"></rect><path d="m7 10 2.5 2L7 14M12.5 15H17"></path>',
    info: '<circle cx="12" cy="12" r="8.5"></circle><path d="M12 11v5M12 8h.01"></path>',
    check: '<path d="m5 12 4 4 10-10"></path>',
    alert: '<path d="M12 4 3 20h18z"></path><path d="M12 9v5M12 17h.01"></path>',
    search: '<circle cx="11" cy="11" r="6.5"></circle><path d="m16 16 4 4"></path>',
    link: '<path d="M10 13a5 5 0 0 0 7 0l2-2a5 5 0 0 0-7-7l-1 1"></path><path d="M14 11a5 5 0 0 0-7 0l-2 2a5 5 0 0 0 7 7l1-1"></path>'
  };

  KM.S = {
    tab: 'daemons',
    daemons: [], loaded: false, loading: false, error: null,
    busy: {}, details: {}, openDetails: {},
    ag: null, agKills: null, agResult: null,
    agSearch: '', agPage: 50,
    logs: { source: 'dm', lines: 100, auto: false, loading: false, text: null, pending: null, sig: null },
    about: { version: null, doctor: null, dirty: false },
    modal: null, modalBlocking: false,
    daemonTimer: null, logTimer: null,
    lastOk: {}, dirty: false, fp: null, detailsRev: 0
  };

  function $(id) { return document.getElementById(id); }
  function E(tag, cls, txt) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (txt != null) n.textContent = txt;
    return n;
  }
  function clear(n) { while (n && n.firstChild) n.removeChild(n.firstChild); }
  function text(n, t) { if (n) n.textContent = t == null ? '' : String(t); }
  function icon(name, cls) {
    var paths = KM.ICONS[name] || '';
    var span = document.createElement('span');
    span.innerHTML = '<svg class="' + (cls || '') + '" viewBox="0 0 24 24" aria-hidden="true" focusable="false">' + paths + '</svg>';
    return span.firstChild;
  }
  function chip(txt, cls) { return E('span', 'chip mini ' + (cls || ''), txt); }
  function btn(label, cls, iconName) {
    var b = E('button', 'btn ' + (cls || ''));
    b.type = 'button';
    if (iconName) b.appendChild(icon(iconName));
    if (label) b.appendChild(E('span', '', label));
    return b;
  }
  function shq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'"; }
  function b64utf8(s) {
    var bytes = new TextEncoder().encode(String(s));
    var bin = '';
    for (var i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
    return btoa(bin);
  }
  function fmtUptime(s) {
    if (s == null || isNaN(s)) return '-';
    s = Math.max(0, Math.floor(s));
    var d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60), x = s % 60;
    if (d) return d + 'd ' + h + 'h';
    if (h) return h + 'h ' + m + 'm';
    if (m) return m + 'm ' + x + 's';
    return x + 's';
  }
  function fmtBytes(n) {
    if (n == null || isNaN(n)) return '-';
    if (n < 1024) return n + ' B';
    if (n < 1048576) return (n / 1024).toFixed(1) + ' KiB';
    return (n / 1048576).toFixed(2) + ' MiB';
  }
  function fmtTs(ts) {
    if (!ts) return '-';
    try { return new Date(ts * 1000).toLocaleString(); } catch (e) { return String(ts); }
  }
  function relTime(ts) {
    if (!ts) return '-';
    var d = Math.floor(Date.now() / 1000) - ts;
    if (d < 60) return d + 's ago';
    if (d < 3600) return Math.floor(d / 60) + 'm ago';
    if (d < 86400) return Math.floor(d / 3600) + 'h ago';
    return Math.floor(d / 86400) + 'd ago';
  }
  function errInfo(e) {
    if (!e) return { code: 'E_UNKNOWN', msg: 'Unknown error.' };
    if (e.kind === 'nobridge') return { code: 'E_NO_BRIDGE', msg: 'Open this page from the KernelSU module WebUI. No bridge is available here.' };
    if (e.kind === 'timeout') return { code: 'E_TIMEOUT', msg: 'Command timed out. The action may still be running; refresh to check.' };
    if (e.kind === 'nojson') return { code: 'E_NOJSON', msg: 'dm did not return valid JSON (exit ' + (e.errno == null ? '?' : e.errno) + ').' };
    return { code: e.code || 'E_UNKNOWN', msg: e.msg || e.message || 'Unexpected error.' };
  }
  function showError(box, e) {
    if (!box) return;
    var x = errInfo(e);
    clear(box);
    var code = E('span', 'code', x.code);
    box.appendChild(code);
    box.appendChild(document.createTextNode(x.msg));
    box.hidden = false;
  }
  function hideError(box) { if (box) { box.hidden = true; clear(box); } }
  function toast(msg, isErr) {
    var root = $('toast-root');
    if (!root) return;
    var t = E('div', 'toast' + (isErr ? ' err' : ''), msg);
    root.appendChild(t);
    while (root.children.length > 3) root.removeChild(root.firstChild);
    setTimeout(function () { if (t.parentNode) t.parentNode.removeChild(t); }, 3400);
  }
  function setConn(state, label) {
    var c = $('conn-chip');
    if (!c) return;
    if (c.dataset.state !== state) c.dataset.state = state;
    if (c.textContent !== String(label)) text(c, label);
  }

  /* ---- error boundary ----
     guard(host, name, fn, retry): runs fn; on a throw (or a rejected promise
     returned by fn) logs with console.warn and replaces only host's content
     with an inline .panel-error carrying a Retry button. */
  function panelError(host, name, e, retry) {
    if (!host) return;
    clear(host);
    var box = E('div', 'panel-error');
    box.setAttribute('role', 'alert');
    box.appendChild(E('span', 'code', 'E_RENDER'));
    box.appendChild(E('span', 'msg', 'Could not render ' + name + ': ' + ((e && (e.message || e.msg)) || String(e)).slice(0, 160)));
    if (typeof retry === 'function') {
      var b = btn('Retry', 'small', 'refresh');
      b.dataset.retry = name;
      b.addEventListener('click', function (ev) {
        ev.stopPropagation();
        try { retry(); } catch (x) { console.warn('[KM] retry failed: ' + name, x); }
      });
      box.appendChild(b);
    }
    host.appendChild(box);
  }
  function guard(host, name, fn, retry) {
    var fail = function (e) {
      try { console.warn('[KM] render failed: ' + name, e && e.message ? e.message : e); } catch (x) {}
      try { panelError(host, name, e, retry); } catch (x) {}
      return undefined;
    };
    try {
      var r = fn();
      if (r && typeof r.then === 'function') return r.then(null, fail);
      return r;
    } catch (e) { return fail(e); }
  }

  KM.$ = $; KM.E = E; KM.clear = clear; KM.text = text; KM.icon = icon;
  KM.chip = chip; KM.btn = btn; KM.shq = shq; KM.b64utf8 = b64utf8;
  KM.fmtUptime = fmtUptime; KM.fmtBytes = fmtBytes; KM.fmtTs = fmtTs; KM.relTime = relTime;
  KM.errInfo = errInfo; KM.showError = showError; KM.hideError = hideError;
  KM.toast = toast; KM.setConn = setConn;
  KM.guard = guard; KM.panelError = panelError;

  /* ---- KernelSU bridge ---- */
  var queue = [], active = 0, seq = 0;

  KM.hasKsu = function () {
    try { return typeof window.ksu !== 'undefined' && window.ksu && typeof window.ksu.exec === 'function'; }
    catch (e) { return false; }
  };

  function runOne(cmd, timeout) {
    return new Promise(function (resolve, reject) {
      var name = '__kmCb_' + Date.now().toString(36) + '_' + (seq++);
      var done = false;
      var timer = setTimeout(function () {
        if (done) return;
        done = true;
        window[name] = function () { try { delete window[name]; } catch (e) {} };
        setTimeout(function () { try { delete window[name]; } catch (e) {} }, 60000);
        reject({ kind: 'timeout' });
      }, timeout || KM.T.read);
      window[name] = function (errno, stdout, stderr) {
        if (done) return;
        done = true;
        clearTimeout(timer);
        try { delete window[name]; } catch (e) {}
        var n = Number(errno);
        resolve({ errno: isFinite(n) ? n : 0, stdout: stdout == null ? '' : String(stdout), stderr: stderr == null ? '' : String(stderr) });
      };
      try { window.ksu.exec(cmd, name); }
      catch (e) {
        if (done) return;
        done = true; clearTimeout(timer);
        try { delete window[name]; } catch (x) {}
        reject({ kind: 'nobridge' });
      }
    });
  }

  function pump() {
    while (active < 3 && queue.length) {
      (function (job) {
        active++;
        runOne(job.cmd, job.timeout).then(job.resolve, job.reject).then(function () {
          active--; pump();
        }, function () { active--; pump(); });
      })(queue.shift());
    }
  }

  KM.exec = function (cmd, timeout) {
    return new Promise(function (resolve, reject) {
      if (!KM.hasKsu()) { reject({ kind: 'nobridge' }); return; }
      queue.push({ cmd: cmd, timeout: timeout, resolve: resolve, reject: reject });
      pump();
    });
  };

  KM.call = function (args, timeout) {
    var cmd = KM.DM + ' ' + args.map(shq).join(' ');
    return KM.exec(cmd, timeout).then(function (r) {
      var raw = String(r.stdout || '').trim();
      if (!raw) throw { kind: 'nojson', errno: r.errno, stderr: r.stderr };
      var obj;
      try { obj = JSON.parse(raw); } catch (e) { throw { kind: 'nojson', errno: r.errno, stderr: r.stderr, raw: raw }; }
      if (obj && obj.ok === false) throw obj;
      if (r.errno !== 0 && (!obj || obj.ok !== true)) throw obj || { kind: 'nojson', errno: r.errno };
      return obj;
    });
  };

  /* ---- tabs ---- */
  KM.tabs = ['daemons', 'logs', 'about'];
  KM.STALE_MS = 5000;
  /* true when the panel has never loaded OK or its last OK load is >= 5 s old */
  KM.stale = function (tab) {
    var t = KM.S.lastOk[tab];
    return !t || Date.now() - t >= KM.STALE_MS;
  };
  KM.markOk = function (tab) { KM.S.lastOk[tab] = Date.now(); };
  KM.activate = function (tab, push, force) {
    /* unknown or legacy (#appguard) hashes fall back to daemons, no auto-open */
    if (KM.tabs.indexOf(tab) < 0) { tab = 'daemons'; push = true; }
    var prev = KM.S.tab;
    KM.S.tab = tab;
    KM.tabs.forEach(function (t) {
      var b = $('tab-' + t), p = $('panel-' + t);
      var on = t === tab;
      if (b) { b.setAttribute('aria-selected', on ? 'true' : 'false'); b.tabIndex = on ? 0 : -1; }
      if (p) p.hidden = !on;
    });
    if (push !== false && location.hash !== '#' + tab) {
      try { history.replaceState(null, '', '#' + tab); } catch (e) { location.hash = tab; }
    }
    var stale = force || KM.stale(tab);
    if (tab === 'daemons' && KM.daemons) {
      if (KM.S.dirty) KM.daemons.render(true);
      if (stale) KM.daemons.load(true, true);
    }
    if (tab === 'logs' && KM.logs) {
      KM.logs.activate();
      if (stale) KM.logs.load();
    }
    if (tab === 'about' && KM.about) {
      KM.about.activate();
      if (stale) KM.about.load();
    }
    return prev;
  };

  KM.tabKey = function (ev) {
    var keys = { ArrowLeft: -1, ArrowRight: 1, Home: -2, End: -2 };
    if (!(ev.key in keys)) return;
    ev.preventDefault();
    var cur = KM.tabs.indexOf(KM.S.tab);
    var next = keys[ev.key] === -2 ? (ev.key === 'Home' ? 0 : KM.tabs.length - 1) : (cur + keys[ev.key] + KM.tabs.length) % KM.tabs.length;
    KM.activate(KM.tabs[next]);
    var b = $('tab-' + KM.tabs[next]); if (b) b.focus();
  };

  /* ---- modal sheet ---- */
  function closeSheet(force) {
    if (KM.S.modalBlocking && !force) return;
    var root = $('modal-root');
    /* M3: anything fired by the teardown (blur/change of a removed field) must not commit */
    if (KM.S.modal) KM.S.modal.closing = true;
    if (root) clear(root);
    if (KM.S.modal) {
      document.removeEventListener('keydown', KM.S.modal.onKey, true);
      var last = KM.S.modal.lastFocus;
      var onClose = KM.S.modal.onClose;
      KM.S.modal = null;
      KM.S.modalBlocking = false;
      if (last && last.focus) try { last.focus(); } catch (e) {}
      if (onClose) try { onClose(); } catch (e) {}
    }
  }
  KM.closeSheet = function () { closeSheet(false); };

  KM.sheet = function (opts) {
    opts = opts || {};
    closeSheet(true);
    var last = document.activeElement;
    var root = $('modal-root');
    clear(root);
    var wrap = E('div', 'modal');
    var back = E('div', 'modal-backdrop');
    var panel = E('div', 'modal-panel' + (opts.cls ? ' ' + opts.cls : ''));
    panel.setAttribute('role', 'dialog');
    panel.setAttribute('aria-modal', 'true');
    panel.tabIndex = -1; /* focus fallback while a section re-renders with every control disabled */
    var title = E('h2', '', opts.title || '');
    title.id = 'km-modal-title';
    panel.setAttribute('aria-labelledby', 'km-modal-title');
    var head = E('div', 'modal-head');
    var ht = E('div');
    ht.appendChild(title);
    if (opts.sub) ht.appendChild(E('p', 'sub', opts.sub));
    var x = E('button', 'icon-btn');
    x.type = 'button'; x.setAttribute('aria-label', 'Close');
    x.appendChild(icon('x'));
    x.addEventListener('click', function () { closeSheet(false); });
    head.appendChild(ht); head.appendChild(x);
    var body = E('div', 'modal-body');
    var foot = E('div', 'modal-foot');
    panel.appendChild(head); panel.appendChild(body); panel.appendChild(foot);
    wrap.appendChild(back); wrap.appendChild(panel);
    root.appendChild(wrap);

    var api = {
      panel: panel, body: body, foot: foot, lastFocus: last,
      setBody: function (n) { clear(body); if (n) body.appendChild(n); },
      setFooter: function (nodes) { clear(foot); (nodes || []).forEach(function (n) { if (n) foot.appendChild(n); }); },
      close: function () { closeSheet(false); },
      setBlocking: function (v) {
        KM.S.modalBlocking = !!v;
        panel.setAttribute('aria-busy', v ? 'true' : 'false');
        var b = document.querySelector('#modal-root .modal-backdrop'); if (b) b.style.pointerEvents = v ? 'none' : '';
      },
      onClose: opts.onClose || null,
      onEscape: opts.onEscape || null,
      onKey: function (ev) {
        if (ev.key === 'Escape') {
          ev.preventDefault();
          /* optional hook: return true to consume Escape (e.g. in-sheet Back) */
          if (api.onEscape) { var used = false; try { used = api.onEscape() === true; } catch (e) {} if (used) return; }
          closeSheet(false); return;
        }
        if (ev.key !== 'Tab') return;
        var f = panel.querySelectorAll('button:not([disabled]),input:not([disabled]),select:not([disabled]),textarea:not([disabled]),[tabindex="0"]');
        if (!f.length) return;
        var first = f[0], lastEl = f[f.length - 1];
        var a = document.activeElement, out = a === panel || !panel.contains(a);
        if (ev.shiftKey && (a === first || out)) { ev.preventDefault(); lastEl.focus(); }
        else if (!ev.shiftKey && (a === lastEl || out)) { ev.preventDefault(); first.focus(); }
      }
    };
    back.addEventListener('click', function () { closeSheet(false); });
    document.addEventListener('keydown', api.onKey, true);
    KM.S.modal = api;
    setTimeout(function () { (body.querySelector('button:not([disabled]),input:not([disabled]),select:not([disabled]),textarea:not([disabled])') || x).focus(); }, 20);
    return api;
  };

  KM.confirm = function (opts) {
    var sh = KM.sheet({ title: opts.title, sub: opts.sub || '' });
    var box = E('div');
    box.appendChild(E('p', 'muted', opts.message || ''));
    var err = E('div', 'alert'); err.hidden = true;
    box.appendChild(err);
    var cancel = KM.btn('Cancel', 'ghost');
    cancel.addEventListener('click', function () { sh.close(); });
    var ok = KM.btn(opts.label || 'Confirm', opts.danger ? 'danger' : 'primary');
    ok.addEventListener('click', function () {
      ok.disabled = true; cancel.disabled = true; sh.setBlocking(true);
      Promise.resolve(opts.onConfirm()).then(function () { sh.setBlocking(false); sh.close(); })
        .catch(function (e) { sh.setBlocking(false); ok.disabled = false; cancel.disabled = false; KM.showError(err, e); });
    });
    sh.setBody(box); sh.setFooter([cancel, ok]);
    return sh;
  };

  KM.typedConfirm = function (opts) {
    var sh = KM.sheet({ title: opts.title, sub: opts.sub || '' });
    var box = E('div');
    if (opts.message) box.appendChild(E('p', 'muted', opts.message));
    var err = E('div', 'alert'); err.hidden = true; box.appendChild(err);
    var field = E('label', 'field type-confirm');
    field.appendChild(E('span', '', 'Type "' + opts.expected + '" to continue'));
    var input = E('input');
    input.type = 'text'; input.autocomplete = 'off'; input.spellcheck = false;
    input.className = 'mono';
    field.appendChild(input);
    box.appendChild(field);
    var cancel = KM.btn('Cancel', 'ghost');
    cancel.addEventListener('click', function () { sh.close(); });
    var ok = KM.btn(opts.label || 'Continue', opts.danger ? 'danger' : 'primary');
    ok.disabled = true;
    input.addEventListener('input', function () { ok.disabled = input.value !== opts.expected; });
    input.addEventListener('keydown', function (ev) { if (ev.key === 'Enter' && !ok.disabled) ok.click(); });
    ok.addEventListener('click', function () {
      if (input.value !== opts.expected) return;
      ok.disabled = true; cancel.disabled = true; input.disabled = true; sh.setBlocking(true);
      Promise.resolve(opts.onConfirm()).then(function () { sh.setBlocking(false); sh.close(); })
        .catch(function (e) { sh.setBlocking(false); ok.disabled = false; cancel.disabled = false; input.disabled = false; KM.showError(err, e); });
    });
    sh.setBody(box); sh.setFooter([cancel, ok]);
    return sh;
  };

  KM.wireHeader = function () {
    var refresh = $('refresh');
    if (refresh) refresh.addEventListener('click', function () {
      if (KM.S.tab === 'daemons') { KM.S.fp = null; KM.daemons.load(true); }
      else if (KM.S.tab === 'logs') KM.logs.load();
      else if (KM.S.tab === 'about') KM.about.load(true);
      refresh.disabled = true;
      setTimeout(function () { refresh.disabled = false; }, 700);
    });
    var tabs = $('tabs');
    if (tabs) {
      tabs.addEventListener('click', function (ev) {
        var b = ev.target.closest('.tab');
        if (b) KM.activate(b.getAttribute('data-tab'));
      });
      tabs.addEventListener('keydown', KM.tabKey);
    }
    window.addEventListener('hashchange', function () {
      var t = (location.hash || '').replace('#', '');
      if (t === KM.S.tab) return;
      KM.activate(t, KM.tabs.indexOf(t) < 0);
    });
  };
})();
