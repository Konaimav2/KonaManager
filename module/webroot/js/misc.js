/* KonaManager UI - logs, about, init */
(function () {
  'use strict';
  var KM = window.KM, S = KM.S;
  var E = KM.E, $ = KM.$, clear = KM.clear, text = KM.text;

  /* ---------------- Logs ---------------- */
  var LOG_CAP = 200;

  function logSources() {
    var list = [{ id: 'dm', name: 'Manager (dm)' }, { id: 'appguard', name: 'AppGuard' }];
    (S.daemons || []).forEach(function (d) {
      if (d.id !== 'appguard' && KM.RE.id.test(d.id)) list.push({ id: d.id, name: d.name + ' (' + d.id + ')' });
    });
    return list;
  }

  /* rebuilds the <select> only when the source list signature changes */
  function fillSources() {
    var sel = $('log-source');
    if (!sel) return;
    var src = logSources();
    var sig = src.map(function (s) { return s.id + '=' + s.name; }).join('|');
    var cur = S.logs.source;
    if (!src.some(function (s) { return s.id === cur; })) cur = 'dm';
    if (sig !== S.logs.sig) {
      var frag = document.createDocumentFragment();
      src.forEach(function (s) { var o = E('option', '', s.name); o.value = s.id; frag.appendChild(o); });
      clear(sel);
      sel.appendChild(frag);
      S.logs.sig = sig;
    }
    S.logs.source = cur;
    if (sel.value !== cur) sel.value = cur;
  }

  function atBottom(box) { return box.scrollHeight - box.scrollTop - box.clientHeight <= 24; }

  /* writes log text without yanking: sticks to bottom only if the user was
     there (or on the first load); otherwise scrollTop is left untouched */
  function applyLog(p) {
    var box = $('log-output');
    if (!box || !p) return;
    var note = $('log-source-note');
    if (p.note != null && note && note.textContent !== p.note) text(note, p.note);
    if (p.text === S.logs.text && box.textContent === p.text) return;
    var first = S.logs.text == null;
    var stick = first || atBottom(box);
    var top = box.scrollTop;
    S.logs.text = null;
    box.textContent = p.text;
    S.logs.text = p.text;
    if (stick) box.scrollTop = box.scrollHeight;
    else if (box.scrollTop !== top) box.scrollTop = top;
  }

  function load() {
    if (S.logs.loading) return Promise.resolve(false);
    fillSources();
    S.logs.loading = true;
    var box = $('log-output'), err = $('log-error');
    if (err && !err.hidden) KM.hideError(err);
    return KM.call(['logs', S.logs.source, String(Math.min(LOG_CAP, S.logs.lines))], KM.T.read).then(function (r) {
      var lines = (r.lines || []).slice(-LOG_CAP);
      var head = r.truncated ? '[showing last ' + lines.length + ' lines]\n' : '';
      var p = { text: head + (lines.length ? lines.join('\n') : 'Log is empty.'), note: String(r.source || S.logs.source) };
      KM.markOk('logs');
      if (S.tab !== 'logs') { S.logs.pending = p; return; }
      S.logs.pending = null;
      return KM.guard(box, 'logs', function () { applyLog(p); }, function () { S.logs.text = null; load(); });
    }).catch(function (e) {
      KM.showError(err, e);
    }).then(function () {
      S.logs.loading = false;
      return true;
    });
  }

  function activateLogs() {
    var p = S.logs.pending;
    if (!p) return;
    S.logs.pending = null;
    KM.guard($('log-output'), 'logs', function () { applyLog(p); }, function () { S.logs.text = null; load(); });
  }

  /* auto refresh: setTimeout chain, runs only on the Logs tab, page visible,
     auto on and the user parked at the bottom of the log */
  function logTick() {
    clearTimeout(S.logTimer);
    if (!S.logs.auto) return;
    S.logTimer = setTimeout(function () {
      var box = $('log-output');
      if (S.tab === 'logs' && !document.hidden && S.logs.auto && box && atBottom(box)) load();
      logTick();
    }, 5000);
  }

  function initLogs() {
    var sel = $('log-source');
    if (sel) sel.addEventListener('change', function () { S.logs.source = sel.value; S.logs.text = null; load(); });
    var lines = $('log-lines');
    if (lines) lines.addEventListener('change', function () { S.logs.lines = Math.min(LOG_CAP, Number(lines.value) || 100); load(); });
    var b = $('log-refresh');
    if (b) b.addEventListener('click', function () { load(); });
    var auto = $('log-auto');
    if (auto) auto.addEventListener('change', function () {
      S.logs.auto = auto.checked;
      logTick();
    });
  }

  KM.logs = { init: initLogs, load: load, activate: activateLogs };

  /* ---------------- About ---------------- */
  function aboutRow(k, v, cls) {
    var r = E('div', 'about-row');
    r.appendChild(E('span', '', k));
    r.appendChild(E('span', 'val ' + (cls || ''), v == null || v === '' ? '-' : String(v)));
    return r;
  }

  function renderIdentity(host) {
    var frag = document.createDocumentFragment();
    frag.appendChild(E('h3', '', 'Identity'));
    var v = S.about.version || {};
    frag.appendChild(aboutRow('Name', 'KonaManager - Simple Daemon Manager'));
    frag.appendChild(aboutRow('Module id', 'daemon-manager'));
    frag.appendChild(aboutRow('dm version', v.version || '-', 'good'));
    frag.appendChild(aboutRow('Schema', v.schema == null ? '-' : v.schema));
    var links = E('div');
    links.appendChild(E('h4', '', 'Project'));
    links.appendChild(E('div', 'plain-link', 'github.com/Konaimav2/KonaManager'));
    links.appendChild(E('div', 'plain-link', 'Report an issue: Konaimav2/KonaManager/issues'));
    frag.appendChild(links);
    clear(host); host.appendChild(frag);
  }

  function renderDoctor(host) {
    var frag = document.createDocumentFragment();
    var h = E('div', 'targets-head');
    h.appendChild(E('h3', '', 'Doctor'));
    var b = KM.btn('Run doctor', 'small', 'refresh');
    b.addEventListener('click', loadDoctor);
    h.appendChild(b);
    frag.appendChild(h);
    var d = S.about.doctor;
    if (!d) { frag.appendChild(E('p', 'muted', 'Not run yet.')); }
    else {
      frag.appendChild(aboutRow('Root', d.root ? 'yes' : 'no', d.root ? 'good' : 'bad'));
      var tools = d.tools || {};
      ['curl', 'unzip', 'sha256sum', 'base64', 'pm'].forEach(function (t) {
        var val = tools[t] || 'missing';
        frag.appendChild(aboutRow('tool ' + t, val, tools[t] ? 'good' : 'bad'));
      });
      if (d.busybox) frag.appendChild(aboutRow('busybox', d.busybox, 'good'));
      frag.appendChild(aboutRow('SELinux', d.selinux || '-'));
      frag.appendChild(aboutRow('Data writable', d.writable ? 'yes' : 'no', d.writable ? 'good' : 'bad'));
    }
    clear(host); host.appendChild(frag);
  }

  function renderMaint(host) {
    var frag = document.createDocumentFragment();
    frag.appendChild(E('h3', '', 'Maintenance'));
    frag.appendChild(E('p', 'muted', 'Rollback restores the previous module snapshot if one exists. It does not delete daemon configs.'));
    var rb = KM.btn('Rollback', 'danger', 'restart');
    rb.addEventListener('click', function () {
      KM.typedConfirm({
        title: 'Rollback module?', message: 'This restores the previous bin/webroot snapshot. Reboot or restart daemons to apply.', expected: 'rollback', label: 'Rollback', danger: true,
        onConfirm: function () {
          return KM.call(['rollback'], KM.T.install).then(function (r) { KM.toast('Restored ' + (r.restored || 'snapshot')); loadAbout(true); });
        }
      });
    });
    frag.appendChild(rb);
    frag.appendChild(E('p', 'muted', 'Update the module zip to keep daemon configs and AppGuard targets.'));
    clear(host); host.appendChild(frag);
  }

  /* each About block has its own error boundary and is rebuilt only when
     its data changed; nothing renders while the About panel is hidden */
  var aboutSig = { identity: null, doctor: null, maint: null };
  function renderAbout(force) {
    if (S.tab !== 'about') { S.about.dirty = true; return; }
    S.about.dirty = false;
    var blocks = [
      ['identity', 'about-identity', renderIdentity, JSON.stringify(S.about.version)],
      ['doctor', 'about-doctor', renderDoctor, JSON.stringify(S.about.doctor)],
      ['maint', 'about-maint', renderMaint, 'static']
    ];
    blocks.forEach(function (b) {
      var host = $(b[1]);
      if (!host) return;
      if (!force && aboutSig[b[0]] === b[3] && host.firstChild) return;
      aboutSig[b[0]] = b[3];
      KM.guard(host, 'about ' + b[0], function () { b[2](host); }, function () { aboutSig[b[0]] = null; renderAbout(true); });
    });
  }

  function loadDoctor() {
    var box = $('about-doctor');
    KM.call(['doctor'], KM.T.read).then(function (d) { S.about.doctor = d; aboutSig.doctor = null; renderAbout(); })
      .catch(function (e) { aboutSig.doctor = null; KM.showError(box, e); });
  }

  function loadAbout(force) {
    if (S.about.loading) return Promise.resolve(false);
    S.about.loading = true;
    var ok = false;
    return KM.call(['version'], KM.T.read).then(function (v) {
      S.about.version = v;
      return KM.call(['doctor'], KM.T.read).then(function (d) { S.about.doctor = d; ok = true; });
    }).catch(function (e) {
      KM.toast('About: ' + KM.errInfo(e).msg, true);
    }).then(function () {
      S.about.loading = false;
      if (ok) KM.markOk('about');
      renderAbout(!!force);
      return ok;
    });
  }

  function activateAbout() {
    var m = $('about-maint');
    if (S.about.dirty || (m && !m.firstChild)) renderAbout();
  }

  KM.about = { init: function () {}, load: loadAbout, activate: activateAbout };

  /* ---------------- init ---------------- */
  function boot() {
    KM.wireHeader();
    KM.daemons.init();
    KM.logs.init();
    var hash = (location.hash || '').replace('#', '');
    /* legacy #appguard (or any unknown hash) lands on Daemons; activate rewrites the hash */
    KM.activate(hash, KM.tabs.indexOf(hash) < 0);
    if (!KM.hasKsu()) {
      KM.setConn('error', 'no ksu');
      KM.showError($('daemon-error'), { kind: 'nobridge' });
    }
    fillSources();
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
  else boot();
})();
