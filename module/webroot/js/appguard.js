/* KonaManager UI - AppGuard tab */
(function () {
  'use strict';
  var KM = window.KM, S = KM.S;
  var E = KM.E, $ = KM.$, clear = KM.clear, text = KM.text;

  function box(title) {
    var b = E('div');
    if (title) b.appendChild(E('h3', '', title));
    return b;
  }

  function pill(t, cls) { return E('span', 'pill ' + (cls || ''), t); }

  function renderStatus(ag) {
    var host = $('ag-status'); clear(host);
    var d = ag.daemon || {};
    var st = d.state || (d.running ? 'running' : 'stopped');
    var s = E('span', 'state'); s.dataset.s = st;
    s.appendChild(E('span', 'dot'));
    s.appendChild(E('span', '', (st || 'unknown').toUpperCase()));
    host.appendChild(s);
    if (d.pid) host.appendChild(E('span', 'mono', 'pid ' + d.pid));
    if (d.uptime_s != null) host.appendChild(E('span', 'mono', 'up ' + KM.fmtUptime(d.uptime_s)));
    var c = ag.counts || {};
    host.appendChild(KM.chip((c.targets || 0) + ' targets'));
    host.appendChild(KM.chip((c.u0 || 0) + ' u0'));
    host.appendChild(KM.chip((c.u999 || 0) + ' u999'));
    host.appendChild(KM.chip((c.never || 0) + ' never'));
    var sp = E('span', 'spacer'); host.appendChild(sp);
    if (d.running) {
      host.appendChild(agBtn('Restart', 'restart', 'restart', ''));
      host.appendChild(agBtn('Stop', 'stop', 'stop', 'danger'));
    } else {
      host.appendChild(agBtn('Start', 'start', 'play', 'primary'));
    }
    if (ag.running_version && ag.installed_version && ag.running_version !== ag.installed_version) {
      var warn = E('div', 'alert warn');
      warn.style.margin = '0';
      warn.appendChild(E('span', 'code', 'UPDATE PENDING'));
      warn.appendChild(document.createTextNode('Running v' + ag.running_version + ', installed v' + ag.installed_version + '. Restart AppGuard to apply.'));
      var rb = KM.btn('Restart now', 'small');
      rb.addEventListener('click', function () { daemon('restart'); });
      warn.appendChild(rb);
      host.appendChild(warn);
    }
  }

  function agBtn(label, act, ic, cls) {
    var b = KM.btn(label, 'small ' + (cls || ''), ic);
    b.dataset.agAct = act;
    return b;
  }

  function daemon(action) {
    S.agBusy = true;
    KM.setConn('wait', action === 'stop' ? 'stopping' : action === 'restart' ? 'restarting' : 'starting');
    KM.call([action, 'appguard'], KM.T.mut).then(function (r) {
      KM.toast('AppGuard ' + (r && r.state ? r.state : action + ' ok'));
      load();
    }).catch(function (e) {
      S.agBusy = false;
      var x = KM.errInfo(e); KM.toast(x.code + ': ' + x.msg, true); KM.setConn('error', 'dm error');
      load();
    });
  }

  function renderControls(ag) {
    var host = $('ag-controls'); clear(host);
    host.appendChild(E('h3', '', 'Global'));
    var cfg = ag.config || {};
    var grid = E('div', 'num-grid');
    var f1 = E('label', 'field');
    f1.appendChild(E('span', '', 'Interval (s)'));
    var i1 = E('input'); i1.type = 'number'; i1.min = '10'; i1.max = '3600'; i1.value = cfg.interval_s != null ? cfg.interval_s : 60;
    f1.appendChild(i1);
    var s1 = KM.btn('Save', 'small');
    s1.addEventListener('click', function () { setNum('interval', i1.value, 10, 3600); });
    f1.appendChild(s1);
    var f2 = E('label', 'field');
    f2.appendChild(E('span', '', 'Default cooldown (s)'));
    var i2 = E('input'); i2.type = 'number'; i2.min = '0'; i2.max = '86400'; i2.value = cfg.cooldown_s != null ? cfg.cooldown_s : 300;
    f2.appendChild(i2);
    var s2 = KM.btn('Save', 'small');
    s2.addEventListener('click', function () { setNum('cooldown', i2.value, 0, 86400); });
    f2.appendChild(s2);
    grid.appendChild(f1); grid.appendChild(f2);
    host.appendChild(grid);

    var dr = E('div', 'switch-row');
    dr.appendChild(E('span', 'switch-label', 'Dry run (log only)'));
    var sw = E('button', 'switch'); sw.type = 'button'; sw.setAttribute('role', 'switch');
    sw.setAttribute('aria-checked', cfg.dry_run ? 'true' : 'false');
    sw.addEventListener('click', function () {
      sw.disabled = true;
      KM.call(['appguard', 'set', 'dry', cfg.dry_run ? '0' : '1'], KM.T.mut)
        .then(function () { load(); }).catch(function (e) { sw.disabled = false; KM.showError($('ag-error'), e); });
    });
    dr.appendChild(sw);
    host.appendChild(dr);
    host.appendChild(E('p', 'muted', 'Settings apply on the next sweep. No restart needed.'));
  }

  function setNum(key, value, min, max) {
    var n = Number(value);
    if (!isFinite(n) || Math.floor(n) !== n || n < min || n > max) {
      KM.toast('Value must be an integer ' + min + '–' + max + '.', true); return;
    }
    KM.call(['appguard', 'set', key, String(n)], KM.T.mut).then(function () {
      KM.toast(key + ' saved'); load();
    }).catch(function (e) { KM.showError($('ag-error'), e); });
  }

  function renderActions(ag) {
    var host = $('ag-actions'); clear(host);
    host.appendChild(E('h3', '', 'Run now'));
    var row = E('div', 'run-actions');
    var run = KM.btn('Run once', 'danger', 'play');
    run.addEventListener('click', function () {
      KM.confirm({
        title: 'Run AppGuard now?', message: 'This sends real am-kill requests for matching background apps.', label: 'Run once', danger: true,
        onConfirm: function () { return runOnce(false); }
      });
    });
    var dry = KM.btn('Dry run once', '', 'shield');
    dry.addEventListener('click', function () { runOnce(true); });
    row.appendChild(run); row.appendChild(dry);
    host.appendChild(row);
    host.appendChild(E('p', 'muted', 'Dry run writes the kill history but sends no am-kill requests.'));
    if (S.agResult) host.appendChild(resultView(S.agResult));
  }

  function resultView(r) {
    var d = E('div', 'result-box');
    var sw = r.sweep || {};
    var head = 'candidates ' + (sw.candidates || 0) + ' · killed ' + (sw.killed || 0) + ' · ' + (r.ms || sw.ms || 0) + ' ms';
    d.appendChild(E('div', '', head));
    if (sw.skipped) d.appendChild(E('div', '', 'skipped: ' + sw.skipped));
    if (sw.would_kill && sw.would_kill.length) {
      d.appendChild(E('div', '', 'would kill:'));
      sw.would_kill.forEach(function (k) { d.appendChild(E('div', '', '  u' + k.user + ' ' + k.pkg)); });
    }
    if (sw.skipped_fg && sw.skipped_fg.length) d.appendChild(E('div', '', 'foreground: ' + sw.skipped_fg.join(', ')));
    if (sw.skipped_cooldown) d.appendChild(E('div', '', 'in cooldown: ' + sw.skipped_cooldown));
    return d;
  }

  function runOnce(dry) {
    var args = ['appguard', 'once'];
    if (dry) args.push('--dry');
    S.agBusy = true;
    return KM.call(args, KM.T.once).then(function (r) {
      S.agResult = r;
      S.agBusy = false;
      KM.toast(dry ? 'Dry sweep done' : 'Sweep done · ' + ((r.sweep || {}).killed || 0) + ' kill(s)');
      return load();
    }).catch(function (e) {
      S.agBusy = false;
      KM.showError($('ag-error'), e);
      throw e;
    });
  }

  function renderTargets(ag) {
    var host = $('ag-targets'); clear(host);
    host.appendChild(E('h3', '', 'Targets'));
    var head = E('div', 'targets-head');
    var search = E('input', 'search');
    search.type = 'search'; search.placeholder = 'Filter package…'; search.value = S.agSearch;
    search.setAttribute('aria-label', 'Filter targets');
    search.addEventListener('input', function () { S.agSearch = search.value; renderRows(); });
    var add = KM.btn('Add app', 'small primary', 'plus');
    add.dataset.agAct = 'picker-target';
    head.appendChild(search); head.appendChild(add);
    host.appendChild(head);
    var rows = E('div', 'targets');
    rows.id = 'ag-target-rows';
    host.appendChild(rows);
    renderRows();
  }

  function filteredTargets() {
    var q = (S.agSearch || '').toLowerCase();
    return (S.ag.targets || []).filter(function (t) { return !q || t.pkg.toLowerCase().indexOf(q) >= 0; });
  }

  function renderRows() {
    var host = $('ag-target-rows');
    if (!host || !S.ag) return;
    clear(host);
    if (!S.ag.targets || !S.ag.targets.length) {
      host.appendChild(E('p', 'muted', 'No targets yet. Add an app to watch.'));
      return;
    }
    var head = E('div', 'target-row head');
    ['Package', 'U0', 'U999', 'Cool', ''].forEach(function (h) { head.appendChild(E('span', '', h)); });
    host.appendChild(head);
    var rows = filteredTargets();
    rows.slice(0, S.agPage).forEach(function (t) { host.appendChild(targetRow(t)); });
    if (rows.length > S.agPage) {
      var more = KM.btn('Show more (' + (rows.length - S.agPage) + ')', 'small');
      more.addEventListener('click', function () { S.agPage += 50; renderRows(); });
      host.appendChild(more);
    } else if (!rows.length) {
      host.appendChild(E('p', 'muted', 'No target matches that filter.'));
    }
  }

  function targetRow(t) {
    var r = E('div', 'target-row');
    r.dataset.pkg = t.pkg;
    var pkg = E('div', 'pkg');
    pkg.appendChild(E('span', '', t.pkg));
    if (t.shadowed) pkg.appendChild(E('span', 'shadow', 'Blocked by Never'));
    r.appendChild(pkg);
    r.appendChild(sw(t.pkg, 0, t.u0, 'u0'));
    r.appendChild(sw(t.pkg, 999, t.u999, 'u999'));
    var cool = E('div', 'cool');
    var ci = E('input');
    ci.type = 'number'; ci.min = '0'; ci.max = '86400';
    ci.value = t.cooldown_s == null ? '' : String(t.cooldown_s);
    ci.placeholder = 'default';
    ci.setAttribute('aria-label', 'Cooldown for ' + t.pkg);
    ci.addEventListener('change', function () {
      var raw = ci.value.trim();
      var cd = raw === '' ? 'default' : String(Math.max(0, Math.min(86400, parseInt(raw, 10) || 0)));
      setTarget(t.pkg, t.u0 ? 1 : 0, t.u999 ? 1 : 0, cd);
    });
    cool.appendChild(ci); r.appendChild(cool);
    var rm = KM.btn('', 'small rm', 'x');
    rm.dataset.agAct = 'target-rm';
    rm.dataset.pkg = t.pkg;
    rm.setAttribute('aria-label', 'Remove ' + t.pkg);
    r.appendChild(rm);
    return r;
  }

  function sw(pkg, user, on, cls) {
    var b = E('button', 'switch ' + cls);
    b.type = 'button'; b.setAttribute('role', 'switch');
    b.setAttribute('aria-checked', on ? 'true' : 'false');
    b.setAttribute('aria-label', 'User ' + user + ' target for ' + pkg);
    b.dataset.agAct = 'target-toggle';
    b.dataset.pkg = pkg;
    b.dataset.user = String(user);
    return b;
  }

  function setTarget(pkg, u0, u999, cooldown) {
    KM.call(['appguard', 'targets', 'set', pkg, 'u0=' + u0, 'u999=' + u999, 'cooldown=' + (cooldown == null ? 'default' : cooldown)], KM.T.mut)
      .then(function () { load(); })
      .catch(function (e) { KM.showError($('ag-error'), e); load(); });
  }

  function renderNever(ag) {
    var host = $('ag-never'); clear(host);
    host.appendChild(E('h3', '', 'Never kill'));
    var list = E('div', 'never-list');
    (ag.never || []).forEach(function (p) {
      var c = E('span', 'never-chip');
      c.appendChild(E('span', '', p));
      var x = E('button'); x.type = 'button'; x.setAttribute('aria-label', 'Remove ' + p + ' from Never');
      x.appendChild(KM.icon('x'));
      x.addEventListener('click', function () {
        KM.call(['appguard', 'never', 'rm', p], KM.T.mut).then(function () { load(); }).catch(function (e) { KM.showError($('ag-error'), e); });
      });
      c.appendChild(x);
      list.appendChild(c);
    });
    if (!(ag.never || []).length) list.appendChild(E('span', 'muted', 'No protected packages.'));
    host.appendChild(list);
    var row = E('div', 'run-actions');
    var inp = E('input', 'search'); inp.type = 'text'; inp.placeholder = 'com.example.app'; inp.setAttribute('aria-label', 'Add package to Never');
    var add = KM.btn('Add', 'small');
    add.addEventListener('click', function () {
      var p = inp.value.trim();
      if (!KM.RE.pkg.test(p) || p.length > 128) { KM.toast('Invalid package name.', true); return; }
      KM.call(['appguard', 'never', 'add', p], KM.T.mut).then(function () { inp.value = ''; load(); }).catch(function (e) { KM.showError($('ag-error'), e); });
    });
    row.appendChild(inp); row.appendChild(add);
    host.appendChild(row);
    host.appendChild(E('p', 'muted', 'Never overrides user 0 and 999 targets.'));
  }

  function renderKills() {
    var host = $('ag-kills'); clear(host);
    var head = E('div', 'targets-head');
    head.appendChild(E('h3', '', 'Recent kills'));
    var b = KM.btn('Refresh', 'small', 'refresh');
    b.addEventListener('click', function () { loadKills(); });
    head.appendChild(b);
    host.appendChild(head);
    var k = S.agKills || {};
    var list = k.kills || [];
    if (!list.length) { host.appendChild(E('p', 'muted', 'No kills recorded yet.')); return; }
    var boxEl = E('div', 'kills');
    list.slice(0, 100).forEach(function (x) {
      var r = E('div', 'kill-row');
      r.appendChild(E('span', '', KM.relTime(x.ts)));
      r.appendChild(E('span', '', 'u' + x.user));
      r.appendChild(E('span', 'pkg', x.pkg));
      r.appendChild(pill(x.mode === 'dry' ? 'dry' : 'kill', x.mode === 'dry' ? 'dry' : ''));
      r.appendChild(pill(x.result === 'fail' ? 'fail' : 'ok', x.result === 'fail' ? 'fail' : 'ok'));
      boxEl.appendChild(r);
    });
    host.appendChild(boxEl);
    if (k.total > list.length) host.appendChild(E('p', 'muted', 'Showing ' + list.length + ' of ' + k.total + '.'));
  }

  function loadKills() {
    KM.call(['appguard', 'kills', '50'], KM.T.read).then(function (r) {
      S.agKills = r; renderKills();
    }).catch(function (e) { KM.showError($('ag-error'), e); });
  }

  function render() {
    var ag = S.ag;
    var err = $('ag-error');
    if (S.agError) KM.showError(err, S.agError); else KM.hideError(err);
    if (!ag) {
      clear($('ag-status')); $('ag-status').appendChild(E('span', 'muted', 'Loading AppGuard…'));
      clear($('ag-controls')); clear($('ag-actions')); clear($('ag-targets')); clear($('ag-never')); clear($('ag-kills'));
      return;
    }
    var c = ag.counts || {};
    text($('ag-count'), (c.targets || 0) + ' targets · ' + (c.never || 0) + ' never');
    renderStatus(ag);
    renderControls(ag);
    renderActions(ag);
    renderTargets(ag);
    renderNever(ag);
    renderKills();
  }

  function load() {
    if (S.agBusy) return;
    S.agBusy = true;
    KM.call(['appguard', 'get'], KM.T.read).then(function (ag) {
      S.ag = ag; S.agError = null;
      return KM.call(['appguard', 'kills', '50'], KM.T.read).then(function (k) { S.agKills = k; });
    }).catch(function (e) {
      S.agError = e; KM.setConn('error', KM.hasKsu() ? 'dm error' : 'no ksu');
    }).then(function () {
      S.agBusy = false;
      render();
      if (!S.agError && S.tab === 'appguard') KM.setConn('ok', 'ready');
    });
  }

  function picker(mode) {
    var sh = KM.sheet({ title: mode === 'never' ? 'Add to Never' : 'Add target' });
    var body = E('div');
    var tabs = E('div', 'segmented');
    var u0b = KM.btn('User 0', ''), u999b = KM.btn('User 999', '');
    var user = 0;
    if (mode !== 'never') {
      tabs.appendChild(u0b); tabs.appendChild(u999b);
      function setUser(u) {
        user = u;
        u0b.setAttribute('aria-pressed', u === 0 ? 'true' : 'false');
        u999b.setAttribute('aria-pressed', u === 999 ? 'true' : 'false');
        loadRows('');
      }
      u0b.addEventListener('click', function () { setUser(0); });
      u999b.addEventListener('click', function () { setUser(999); });
      setUser(0);
      body.appendChild(tabs);
    }
    var search = E('input', 'search'); search.type = 'search'; search.placeholder = 'Search packages…'; search.setAttribute('aria-label', 'Search packages');
    body.appendChild(search);
    var list = E('div', 'picker-list'); body.appendChild(list);
    var err = E('div', 'alert'); err.hidden = true; body.appendChild(err);
    sh.setBody(body);
    var t = null;
    search.addEventListener('input', function () {
      clearTimeout(t); t = setTimeout(function () { loadRows(search.value.trim()); }, 250);
    });
    function loadRows(q) {
      clear(list); list.appendChild(E('p', 'muted', 'Loading…'));
      var args = ['appguard', 'packages', '--user', String(user)];
      if (q) args.push('--q', q);
      KM.call(args, KM.T.read).then(function (r) {
        clear(list);
        (r.packages || []).forEach(function (p) {
          var row = E('div', 'picker-row');
          var pkg = E('div', 'pkg', p.pkg); row.appendChild(pkg);
          var tags = E('div', 'tags');
          if (p.never) tags.appendChild(KM.chip('never', 'kind'));
          if (p.target) tags.appendChild(KM.chip('target', 'src'));
          row.appendChild(tags);
          var blocked = mode === 'never' ? p.never : p.never;
          if (blocked) row.setAttribute('aria-disabled', 'true');
          else row.addEventListener('click', function () {
            var call;
            if (mode === 'never') call = KM.call(['appguard', 'never', 'add', p.pkg], KM.T.mut);
            else if (user === 999) call = KM.call(['appguard', 'targets', 'add', p.pkg, 'u0=0', 'u999=1'], KM.T.mut);
            else call = KM.call(['appguard', 'targets', 'add', p.pkg, 'u0=1', 'u999=0'], KM.T.mut);
            call.then(function () { KM.toast((mode === 'never' ? 'Added to Never: ' : 'Target added: ') + p.pkg); sh.close(); load(); })
              .catch(function (e) { KM.showError(err, e); });
          });
          row.addEventListener('keydown', function (ev) { if (ev.key === 'Enter' || ev.key === ' ') { ev.preventDefault(); row.click(); } });
          row.tabIndex = blocked ? -1 : 0;
          list.appendChild(row);
        });
        if (!list.children.length) list.appendChild(E('p', 'muted', 'No packages found.'));
      }).catch(function (e) { clear(list); KM.showError(err, e); });
    }
    loadRows('');
  }

  function init() {
    var panel = $('panel-appguard');
    if (!panel) return;
    panel.addEventListener('click', function (ev) {
      var t = ev.target.closest('[data-ag-act]');
      if (!t) return;
      var act = t.getAttribute('data-ag-act');
      if (act === 'start' || act === 'stop' || act === 'restart') daemon(act);
      else if (act === 'picker-target') picker('target');
      else if (act === 'target-toggle') {
        var pkg = t.getAttribute('data-pkg'), user = t.getAttribute('data-user');
        var target = (S.ag.targets || []).filter(function (x) { return x.pkg === pkg; })[0];
        if (!target) return;
        var u0 = target.u0 ? 1 : 0, u999 = target.u999 ? 1 : 0;
        if (user === '0') u0 = u0 ? 0 : 1; else u999 = u999 ? 0 : 1;
        t.disabled = true;
        setTarget(pkg, u0, u999, target.cooldown_s == null ? 'default' : target.cooldown_s);
      } else if (act === 'target-rm') {
        var p = t.getAttribute('data-pkg');
        KM.confirm({
          title: 'Remove target?', message: p, label: 'Remove', danger: true,
          onConfirm: function () { return KM.call(['appguard', 'targets', 'rm', p], KM.T.mut).then(function () { load(); }); }
        });
      }
    });
  }

  KM.appguard = { init: init, load: load, render: render };
})();
