/* KonaManager UI - logs, about, init */
(function () {
  'use strict';
  var KM = window.KM, S = KM.S;
  var E = KM.E, $ = KM.$, clear = KM.clear, text = KM.text;

  /* ---------------- Logs ---------------- */
  var logAutoTimer = null;

  function logSources() {
    var list = [{ id: 'dm', name: 'Manager (dm)' }, { id: 'appguard', name: 'AppGuard' }];
    (S.daemons || []).forEach(function (d) {
      if (d.id !== 'appguard' && KM.RE.id.test(d.id)) list.push({ id: d.id, name: d.name + ' (' + d.id + ')' });
    });
    return list;
  }

  function fillSources() {
    var sel = $('log-source');
    if (!sel) return;
    var cur = S.logs.source;
    clear(sel);
    logSources().forEach(function (s) {
      var o = E('option', '', s.name); o.value = s.id; sel.appendChild(o);
    });
    if (!logSources().some(function (s) { return s.id === cur; })) cur = 'dm';
    S.logs.source = cur; sel.value = cur;
  }

  function load() {
    if (S.logs.loading) return;
    fillSources();
    S.logs.loading = true;
    var box = $('log-output'), err = $('log-error');
    KM.hideError(err);
    KM.call(['logs', S.logs.source, String(S.logs.lines)], KM.T.read).then(function (r) {
      var lines = r.lines || [];
      var head = r.truncated ? '[showing last ' + S.logs.lines + ' lines]\n' : '';
      box.textContent = head + (lines.length ? lines.join('\n') : 'Log is empty.');
      box.scrollTop = box.scrollHeight;
      text($('log-source-note'), r.source || S.logs.source);
    }).catch(function (e) {
      KM.showError(err, e);
    }).then(function () {
      S.logs.loading = false;
    });
  }

  function initLogs() {
    var sel = $('log-source');
    if (sel) sel.addEventListener('change', function () { S.logs.source = sel.value; load(); });
    var lines = $('log-lines');
    if (lines) lines.addEventListener('change', function () { S.logs.lines = Number(lines.value) || 100; load(); });
    var b = $('log-refresh');
    if (b) b.addEventListener('click', load);
    var auto = $('log-auto');
    if (auto) auto.addEventListener('change', function () {
      S.logs.auto = auto.checked;
      if (logAutoTimer) { clearInterval(logAutoTimer); logAutoTimer = null; }
      if (auto.checked) logAutoTimer = setInterval(function () {
        if (S.tab === 'logs' && document.visibilityState === 'visible') load();
      }, 5000);
    });
  }

  KM.logs = { init: initLogs, load: load };

  /* ---------------- About ---------------- */
  function aboutRow(k, v, cls) {
    var r = E('div', 'about-row');
    r.appendChild(E('span', '', k));
    r.appendChild(E('span', 'val ' + (cls || ''), v == null || v === '' ? '-' : String(v)));
    return r;
  }

  function renderAbout() {
    var id = $('about-identity'); clear(id);
    id.appendChild(E('h3', '', 'Identity'));
    var v = S.about.version || {};
    id.appendChild(aboutRow('Name', 'KonaManager - Simple Daemon Manager'));
    id.appendChild(aboutRow('Module id', 'daemon-manager'));
    id.appendChild(aboutRow('dm version', v.version || '-', 'good'));
    id.appendChild(aboutRow('Schema', v.schema == null ? '-' : v.schema));
    var links = E('div');
    links.appendChild(E('h4', '', 'Project'));
    links.appendChild(E('div', 'plain-link', 'github.com/Konaimav2/KonaManager'));
    links.appendChild(E('div', 'plain-link', 'Report an issue: Konaimav2/KonaManager/issues'));
    id.appendChild(links);

    var doc = $('about-doctor'); clear(doc);
    var h = E('div', 'targets-head');
    h.appendChild(E('h3', '', 'Doctor'));
    var b = KM.btn('Run doctor', 'small', 'refresh');
    b.addEventListener('click', loadDoctor);
    h.appendChild(b);
    doc.appendChild(h);
    var d = S.about.doctor;
    if (!d) { doc.appendChild(E('p', 'muted', 'Not run yet.')); }
    else {
      doc.appendChild(aboutRow('Root', d.root ? 'yes' : 'no', d.root ? 'good' : 'bad'));
      var tools = d.tools || {};
      ['curl', 'unzip', 'sha256sum', 'base64', 'pm'].forEach(function (t) {
        var val = tools[t] || 'missing';
        doc.appendChild(aboutRow('tool ' + t, val, tools[t] ? 'good' : 'bad'));
      });
      if (d.busybox) doc.appendChild(aboutRow('busybox', d.busybox, 'good'));
      doc.appendChild(aboutRow('SELinux', d.selinux || '-'));
      doc.appendChild(aboutRow('Data writable', d.writable ? 'yes' : 'no', d.writable ? 'good' : 'bad'));
    }

    var m = $('about-maint'); clear(m);
    m.appendChild(E('h3', '', 'Maintenance'));
    m.appendChild(E('p', 'muted', 'Rollback restores the previous module snapshot if one exists. It does not delete daemon configs.'));
    var rb = KM.btn('Rollback', 'danger', 'restart');
    rb.addEventListener('click', function () {
      KM.typedConfirm({
        title: 'Rollback module?', message: 'This restores the previous bin/webroot snapshot. Reboot or restart daemons to apply.', expected: 'rollback', label: 'Rollback', danger: true,
        onConfirm: function () {
          return KM.call(['rollback'], KM.T.install).then(function (r) { KM.toast('Restored ' + (r.restored || 'snapshot')); loadAbout(); });
        }
      });
    });
    m.appendChild(rb);
    m.appendChild(E('p', 'muted', 'Update the module zip to keep daemon configs and AppGuard targets.'));
  }

  function loadDoctor() {
    var box = $('about-doctor');
    KM.call(['doctor'], KM.T.read).then(function (d) { S.about.doctor = d; renderAbout(); })
      .catch(function (e) { KM.showError(box, e); });
  }

  function loadAbout() {
    if (S.about.loading) return;
    S.about.loading = true;
    KM.call(['version'], KM.T.read).then(function (v) {
      S.about.version = v;
      return KM.call(['doctor'], KM.T.read).then(function (d) { S.about.doctor = d; });
    }).catch(function (e) {
      KM.toast('About: ' + KM.errInfo(e).msg, true);
    }).then(function () {
      S.about.loading = false;
      renderAbout();
    });
  }

  KM.about = { init: function () {}, load: loadAbout };

  /* ---------------- init ---------------- */
  function boot() {
    KM.wireHeader();
    KM.daemons.init();
    KM.appguard.init();
    KM.logs.init();
    var hash = (location.hash || '').replace('#', '');
    KM.activate(KM.tabs.indexOf(hash) >= 0 ? hash : 'daemons', false);
    if (!KM.hasKsu()) {
      KM.setConn('error', 'no ksu');
      KM.showError($('daemon-error'), { kind: 'nobridge' });
    }
    fillSources();
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
  else boot();
})();
