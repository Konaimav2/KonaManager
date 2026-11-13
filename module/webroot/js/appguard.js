/* KonaManager UI - AppGuard settings sheet (lazy; opened from the AppGuard card gear) */
(function () {
  'use strict';
  var KM = window.KM, S = KM.S;
  var E = KM.E, clear = KM.clear, text = KM.text;

  var PAGE = 50, CAP = 200, KILLS = 50, PICK_CAP = 200;

  /* Everything below lives only while the sheet is open. `sid` invalidates
     late async callbacks after close; `v` holds all node refs and timers. */
  var sid = 0, sh = null, v = null;
  /* pkg -> token of the in-flight `targets set` (one per package; rows rebuilt mid-flight stay locked) */
  var pend = {};
  var seq = {}; /* pkg -> last request no., never reset by open/cleanup */

  function alive(id) { return id === sid && sh && v; }

  function sec(key, title, sub) {
    var s = E('section', 'ag-sec');
    s.dataset.sec = key;
    var head = E('div', 'ag-sec-head');
    var h = E('h3', '', title);
    s.setAttribute('aria-label', title);
    var ht = E('div', 'ag-sec-title');
    ht.appendChild(h);
    if (sub) ht.appendChild(E('p', 'muted', sub));
    head.appendChild(ht);
    var tools = E('div', 'ag-sec-tools');
    head.appendChild(tools);
    var err = E('div', 'alert'); err.hidden = true; err.setAttribute('role', 'alert');
    var body = E('div', 'ag-sec-body');
    s.appendChild(head); s.appendChild(err); s.appendChild(body);
    return { el: s, tools: tools, err: err, body: body };
  }

  function guarded(key, fn) {
    var s = v && v.sec[key];
    if (!s) return;
    /* E3: a re-render that removes the focused control must not drop focus out of the dialog */
    var panel = sh && sh.panel, a = document.activeElement;
    if (panel && a && a !== panel && panel.contains(a) && s.body.contains(a) && a.dataset && a.dataset.agAct) {
      v.refocus = { key: key, act: a.dataset.agAct, carried: false };
    }
    KM.guard(s.body, 'AppGuard ' + key, fn, function () { guarded(key, fn); });
    restoreFocus(key);
  }

  function restoreFocus(key) {
    var rf = v && v.refocus, panel = sh && sh.panel;
    if (!rf || rf.key !== key || !panel || !v.sec[key]) return;
    var a = document.activeElement;
    if (a && a !== document.body && a !== panel) { v.refocus = null; return; }
    var host = v.sec[key].body;
    var el = null, all = host.querySelectorAll('[data-ag-act]:not([disabled])');
    for (var i = 0; i < all.length; i++) if (all[i].dataset.agAct === rf.act) { el = all[i]; break; }
    if (!el && rf.carried) el = all[0] || null;
    if (el) { try { el.focus({ preventScroll: true }); } catch (e) {} v.refocus = null; return; }
    try { panel.focus({ preventScroll: true }); } catch (e) {}
    rf.carried = true;
  }

  function secError(key, e) { if (v && v.sec[key]) KM.showError(v.sec[key].err, e); }
  function secOk(key) { if (v && v.sec[key] && !v.sec[key].err.hidden) KM.hideError(v.sec[key].err); }

  function pill(t, cls) { return E('span', 'pill ' + (cls || ''), t); }

  function recount() {
    var ag = S.ag; if (!ag) return;
    var u0 = 0, u999 = 0;
    (ag.targets || []).forEach(function (t) { if (t.u0) u0++; if (t.u999) u999++; });
    ag.counts = { targets: (ag.targets || []).length, u0: u0, u999: u999, never: (ag.never || []).length };
  }

  /* ---------------- Status ---------------- */
  function renderStatus() {
    var host = v.sec.status.body, ag = S.ag;
    var d = ag.daemon || {};
    var st = d.state || (d.running ? 'running' : 'stopped');
    var frag = document.createDocumentFragment();
    var row = E('div', 'ag-status');
    var s = E('span', 'state'); s.dataset.s = v.busy ? 'busy' : st;
    s.appendChild(E('span', 'dot'));
    s.appendChild(E('span', '', v.busy ? v.busy.toUpperCase() + '…' : (st || 'unknown').toUpperCase()));
    row.appendChild(s);
    var tel = E('div', 'ag-tele');
    tel.appendChild(kv('PID', d.pid ? String(d.pid) : '-', 'pid'));
    tel.appendChild(kv('Uptime', KM.fmtUptime(d.uptime_s), 'uptime'));
    row.appendChild(tel);
    frag.appendChild(row);
    var c = ag.counts || {};
    var chips = E('div', 'ag-counts');
    chips.dataset.f = 'counts';
    chips.appendChild(KM.chip((c.targets || 0) + ' targets'));
    chips.appendChild(KM.chip((c.u0 || 0) + ' u0'));
    chips.appendChild(KM.chip((c.u999 || 0) + ' u999'));
    chips.appendChild(KM.chip((c.never || 0) + ' never'));
    frag.appendChild(chips);
    if (ag.running_version && ag.installed_version && ag.running_version !== ag.installed_version) {
      var warn = E('div', 'alert warn');
      warn.appendChild(E('span', 'code', 'UPDATE PENDING'));
      warn.appendChild(document.createTextNode('Running v' + ag.running_version + ', installed v' + ag.installed_version + '. Restart AppGuard to apply.'));
      frag.appendChild(warn);
    }
    var acts = E('div', 'run-actions');
    var busy = !!v.busy;
    [['Start', 'start', 'play', 'primary', busy || !!d.running],
     ['Stop', 'stop', 'stop', 'danger', busy || !d.running],
     ['Restart', 'restart', 'restart', '', busy || !d.running]].forEach(function (b) {
      var x = KM.btn(b[0], b[3], b[2]);
      x.dataset.agAct = b[1];
      x.disabled = b[4];
      acts.appendChild(x);
    });
    frag.appendChild(acts);
    clear(host); host.appendChild(frag);
  }

  function kv(k, val, f) {
    var d = E('div', 'tele');
    d.dataset.f = f;
    d.appendChild(E('div', 'k', k));
    d.appendChild(E('div', 'v', val));
    return d;
  }

  function patchCounts() {
    recount();
    var host = v && v.sec.status.body.querySelector('[data-f="counts"]');
    if (!host) return;
    var c = S.ag.counts, vals = [c.targets + ' targets', c.u0 + ' u0', c.u999 + ' u999', c.never + ' never'];
    for (var i = 0; i < host.children.length && i < 4; i++) if (host.children[i].textContent !== vals[i]) text(host.children[i], vals[i]);
  }

  function lifecycle(act) {
    if (v.busy) return;
    var my = sid;
    v.busy = act === 'stop' ? 'stopping' : act === 'restart' ? 'restarting' : 'starting';
    guarded('status', renderStatus);
    secOk('status');
    KM.daemons.runAction('appguard', act).catch(function (e) {
      if (alive(my)) secError('status', e);
    }).then(function () {
      if (!alive(my)) return;
      return KM.call(['appguard', 'get'], KM.T.read).then(function (ag) {
        if (!alive(my)) return;
        S.ag.daemon = ag.daemon; S.ag.running_version = ag.running_version; S.ag.installed_version = ag.installed_version;
      }).catch(function (e) { if (alive(my)) secError('status', e); });
    }).then(function () {
      if (!alive(my)) return;
      v.busy = null;
      guarded('status', renderStatus);
    });
  }

  /* ---------------- Settings ---------------- */
  function renderSettings() {
    var host = v.sec.settings.body, cfg = S.ag.config || {};
    var frag = document.createDocumentFragment();
    var grid = E('div', 'num-grid');
    grid.appendChild(numField('interval', 'Interval (s)', 'interval_s', 10, 3600, 60));
    grid.appendChild(numField('cooldown', 'Default cooldown (s)', 'cooldown_s', 0, 86400, 300));
    frag.appendChild(grid);
    var dr = E('div', 'switch-row');
    dr.appendChild(E('span', 'switch-label', 'Dry run (log only)'));
    var sw = E('button', 'switch'); sw.type = 'button'; sw.setAttribute('role', 'switch');
    sw.setAttribute('aria-checked', cfg.dry_run ? 'true' : 'false');
    sw.setAttribute('aria-label', 'Dry run');
    sw.dataset.agAct = 'dry';
    dr.appendChild(sw);
    frag.appendChild(dr);
    frag.appendChild(E('p', 'muted', 'Settings apply on the next sweep. No restart needed.'));
    clear(host); host.appendChild(frag);
  }

  function numField(key, label, cfgKey, min, max, def) {
    var cfg = S.ag.config || {};
    var f = E('div', 'field ag-num');
    f.appendChild(E('span', '', label));
    var row = E('div', 'ag-inline');
    var i = E('input'); i.type = 'number'; i.inputMode = 'numeric';
    i.setAttribute('aria-label', label);
    i.dataset.agNum = key;
    i.min = String(min); i.max = String(max);
    i.value = cfg[cfgKey] != null ? cfg[cfgKey] : def;
    var save = KM.btn('Save', 'small');
    var hint = E('span', 'hint', min + '–' + max);
    /* M3: commit only on Enter or Save. Blur (incl. the one caused by closing the sheet) never commits. */
    function apply() { setNum(key, cfgKey, i, min, max, save, dirty); }
    function dirty() {
      var c = S.ag.config || {};
      var cur = c[cfgKey] != null ? c[cfgKey] : def;
      var un = String(i.value).trim() !== String(cur);
      save.classList.toggle('primary', un);
      var want = un ? 'Unsaved - press Enter or Save' : min + '–' + max;
      if (hint.textContent !== want) text(hint, want);
    }
    i.addEventListener('keydown', function (ev) { if (ev.key === 'Enter') { ev.preventDefault(); apply(); } });
    i.addEventListener('input', dirty);
    save.addEventListener('click', apply);
    row.appendChild(i); row.appendChild(save);
    f.appendChild(row);
    f.appendChild(hint);
    return f;
  }

  function setNum(key, cfgKey, input, min, max, btn, after) {
    if (!alive(sid) || (S.modal && S.modal.closing)) return;
    var raw = String(input.value).trim();
    var n = parseInt(raw, 10);
    if (!/^-?\d+$/.test(raw) || !isFinite(n)) { secError('settings', { code: 'E_ARG', msg: 'Enter a whole number ' + min + '–' + max + '.' }); return; }
    if (n < min) n = min; if (n > max) n = max;
    if (String(n) !== raw) input.value = String(n);
    var cfg = S.ag.config || (S.ag.config = {});
    if (cfg[cfgKey] === n || input.dataset.pending === String(n)) { if (after) after(); return; }
    var my = sid;
    input.dataset.pending = String(n);
    btn.disabled = true;
    KM.call(['appguard', 'set', key, String(n)], KM.T.mut).then(function () {
      if (!alive(my)) return;
      cfg[cfgKey] = n;
      secOk('settings');
      if (after) after();
      KM.toast((key === 'interval' ? 'Interval' : 'Default cooldown') + ' saved');
    }).catch(function (e) {
      if (alive(my)) secError('settings', e);
    }).then(function () {
      delete input.dataset.pending;
      btn.disabled = false;
    });
  }

  function toggleDry(sw) {
    var cfg = S.ag.config || (S.ag.config = {});
    var next = !cfg.dry_run, my = sid;
    sw.disabled = true;
    sw.setAttribute('aria-checked', next ? 'true' : 'false');
    KM.call(['appguard', 'set', 'dry', next ? '1' : '0'], KM.T.mut).then(function () {
      if (!alive(my)) return;
      cfg.dry_run = next;
      secOk('settings');
      guarded('run', renderRun);
    }).catch(function (e) {
      sw.setAttribute('aria-checked', cfg.dry_run ? 'true' : 'false');
      if (alive(my)) secError('settings', e);
    }).then(function () { sw.disabled = false; });
  }

  /* ---------------- Run now ---------------- */
  function renderRun() {
    var host = v.sec.run.body, cfg = S.ag.config || {};
    var frag = document.createDocumentFragment();
    if (cfg.dry_run) {
      var n = E('div', 'alert warn');
      n.appendChild(E('span', 'code', 'DRY-RUN'));
      n.appendChild(document.createTextNode('Dry-run is on: Run once will not kill.'));
      frag.appendChild(n);
    }
    var row = E('div', 'run-actions');
    var run = KM.btn(v.running === 'real' ? 'Running…' : 'Run once', 'danger', 'play');
    run.dataset.agAct = 'run'; run.disabled = !!v.running || v.confirmRun;
    var dry = KM.btn(v.running === 'dry' ? 'Running…' : 'Dry run once', '', 'shield');
    dry.dataset.agAct = 'dry-run'; dry.disabled = !!v.running;
    row.appendChild(run); row.appendChild(dry);
    frag.appendChild(row);
    if (v.confirmRun) {
      var strip = E('div', 'ag-confirm');
      strip.setAttribute('role', 'group');
      strip.setAttribute('aria-label', 'Confirm run once');
      strip.appendChild(E('span', '', 'Sends real am-kill requests.'));
      var ok = KM.btn('Confirm', 'danger'); ok.dataset.agAct = 'run-confirm';
      var no = KM.btn('Cancel', 'ghost'); no.dataset.agAct = 'run-cancel';
      strip.appendChild(ok); strip.appendChild(no);
      frag.appendChild(strip);
    }
    frag.appendChild(E('p', 'muted', 'Dry run writes the kill history but sends no am-kill requests.'));
    if (S.agResult) frag.appendChild(resultView(S.agResult));
    clear(host); host.appendChild(frag);
    if (v.confirmRun) { var c = host.querySelector('[data-ag-act="run-cancel"]'); if (c) c.focus(); }
  }

  function resultView(r) {
    var d = E('div', 'result-box');
    d.setAttribute('role', 'status');
    var sw = r.sweep || {};
    d.appendChild(E('div', '', (r.dry ? 'dry · ' : '') + 'candidates ' + (sw.candidates || 0) + ' · killed ' + (sw.killed || 0) + ' · ' + (r.ms || sw.ms || 0) + ' ms'));
    if (sw.skipped) d.appendChild(E('div', '', 'skipped: ' + sw.skipped));
    if (sw.would_kill && sw.would_kill.length) {
      d.appendChild(E('div', '', 'would kill:'));
      sw.would_kill.slice(0, CAP).forEach(function (k) { d.appendChild(E('div', '', '  u' + k.user + ' ' + k.pkg)); });
    }
    if (sw.skipped_fg && sw.skipped_fg.length) d.appendChild(E('div', '', 'foreground: ' + sw.skipped_fg.join(', ')));
    if (sw.skipped_cooldown) d.appendChild(E('div', '', 'in cooldown: ' + sw.skipped_cooldown));
    return d;
  }

  function runOnce(dry) {
    if (v.running) return;
    var my = sid;
    v.running = dry ? 'dry' : 'real';
    v.confirmRun = false;
    secOk('run');
    guarded('run', renderRun);
    var args = ['appguard', 'once'];
    if (dry) args.push('--dry');
    KM.call(args, KM.T.once).then(function (r) {
      if (!alive(my)) return;
      S.agResult = r;
      KM.toast(dry ? 'Dry sweep done' : 'Sweep done · ' + ((r.sweep || {}).killed || 0) + ' kill(s)');
      loadKills();
    }).catch(function (e) {
      if (alive(my)) secError('run', e);
    }).then(function () {
      if (!alive(my)) return;
      v.running = null;
      guarded('run', renderRun);
    });
  }

  /* ---------------- Targets ---------------- */
  function renderTargets() {
    var s = v.sec.targets;
    if (!s.tools.firstChild) {
      var add = KM.btn('Add app', 'small primary', 'plus');
      add.dataset.agAct = 'picker-target';
      s.tools.appendChild(add);
    }
    var host = s.body;
    var frag = document.createDocumentFragment();
    var search = E('input', 'search');
    search.type = 'search'; search.placeholder = 'Filter package…'; search.value = S.agSearch;
    search.setAttribute('aria-label', 'Filter targets');
    search.addEventListener('input', function () {
      clearTimeout(v.filterT);
      v.filterT = setTimeout(function () {
        if (!v) return;
        S.agSearch = search.value; S.agPage = PAGE;
        guarded('rows', renderRows);
      }, 150);
    });
    frag.appendChild(search);
    var rows = E('div', 'targets');
    frag.appendChild(rows);
    clear(host); host.appendChild(frag);
    v.sec.rows = { body: rows, err: s.err };
    guarded('rows', renderRows);
  }

  function filteredTargets() {
    var q = (S.agSearch || '').toLowerCase();
    return (S.ag.targets || []).filter(function (t) { return !q || t.pkg.toLowerCase().indexOf(q) >= 0; });
  }

  function renderRows() {
    var host = v.sec.rows.body;
    var frag = document.createDocumentFragment();
    if (!S.ag.targets || !S.ag.targets.length) {
      frag.appendChild(E('p', 'muted', 'No targets yet. Add an app to watch.'));
      clear(host); host.appendChild(frag); return;
    }
    var head = E('div', 'target-row head');
    head.setAttribute('aria-hidden', 'true');
    ['Package', 'U0', 'U999', 'Cooldown', ''].forEach(function (h) { head.appendChild(E('span', '', h)); });
    frag.appendChild(head);
    var rows = filteredTargets();
    var limit = Math.min(S.agPage, CAP);
    rows.slice(0, limit).forEach(function (t) { frag.appendChild(targetRow(t)); });
    if (!rows.length) frag.appendChild(E('p', 'muted', 'No target matches that filter.'));
    else if (rows.length > limit) {
      if (limit < CAP) {
        var more = KM.btn('Show more (' + (rows.length - limit) + ')', 'small block');
        more.dataset.agAct = 'more';
        frag.appendChild(more);
      } else {
        frag.appendChild(E('p', 'muted', 'Showing ' + limit + ' of ' + rows.length + '. Refine the filter.'));
      }
    }
    clear(host); host.appendChild(frag);
  }

  function targetRow(t) {
    var r = E('div', 'target-row');
    r.dataset.pkg = t.pkg;
    var pkg = E('div', 'pkg');
    pkg.appendChild(E('span', '', t.pkg));
    if (t.shadowed) pkg.appendChild(E('span', 'shadow', 'Blocked by Never'));
    r.appendChild(pkg);
    r.appendChild(ucell(t.pkg, 0, t.u0, 'u0'));
    r.appendChild(ucell(t.pkg, 999, t.u999, 'u999'));
    var cool = E('div', 'cool');
    var ci = E('input');
    ci.type = 'number'; ci.min = '0'; ci.max = '86400'; ci.inputMode = 'numeric';
    ci.value = t.cooldown_s == null ? '' : String(t.cooldown_s);
    ci.placeholder = 'default';
    ci.setAttribute('aria-label', 'Cooldown seconds for ' + t.pkg);
    ci.dataset.agCool = t.pkg;
    ci.enterKeyHint = 'done';
    if (pend[t.pkg]) ci.disabled = true;
    ci.addEventListener('input', function () {
      var m = findTarget(t.pkg), mv = m && m.cooldown_s != null ? String(m.cooldown_s) : '';
      markUnsaved(ci, ci.value.trim() !== mv);
    });
    cool.appendChild(ci); r.appendChild(cool);
    var rm = KM.btn('', 'rm', 'x');
    rm.dataset.agAct = 'target-rm';
    rm.setAttribute('aria-label', 'Remove ' + t.pkg);
    r.appendChild(rm);
    return r;
  }

  function ucell(pkg, user, on, cls) {
    var c = E('div', 'ucell ' + cls);
    c.appendChild(E('span', 'ulab', 'U' + user));
    var b = E('button', 'switch');
    b.type = 'button'; b.setAttribute('role', 'switch');
    b.setAttribute('aria-checked', on ? 'true' : 'false');
    b.setAttribute('aria-label', 'User ' + user + ' target for ' + pkg);
    b.dataset.agAct = 'target-toggle';
    b.dataset.user = String(user);
    if (pend[pkg]) { b.disabled = true; b.setAttribute('aria-busy', 'true'); }
    c.appendChild(b);
    return c;
  }

  function markUnsaved(ci, on) {
    if (on) { ci.classList.add('unsaved'); ci.title = 'Unsaved - press Enter'; }
    else { ci.classList.remove('unsaved'); ci.removeAttribute('title'); }
  }

  function findTarget(pkg) { return (S.ag.targets || []).filter(function (x) { return x.pkg === pkg; })[0]; }

  /* writes only the changed attributes of one row (same node stays) */
  function patchRow(row, t) {
    if (!row) return;
    var sws = row.querySelectorAll('.switch');
    var want = [t.u0 ? 'true' : 'false', t.u999 ? 'true' : 'false'];
    for (var i = 0; i < sws.length; i++) {
      if (sws[i].getAttribute('aria-checked') !== want[i]) sws[i].setAttribute('aria-checked', want[i]);
      sws[i].disabled = false;
      sws[i].removeAttribute('aria-busy');
    }
    var ci = row.querySelector('input');
    var cv = t.cooldown_s == null ? '' : String(t.cooldown_s);
    if (ci) ci.disabled = false;
    if (ci && document.activeElement !== ci && ci.value !== cv) ci.value = cv;
    if (ci && ci.value.trim() === cv) markUnsaved(ci, false);
  }

  /* the live row for pkg (rows are rebuilt by filter / Show more / remove / picker add / Never) */
  function rowFor(pkg) {
    var rs = v && v.sec.targets ? v.sec.targets.body.querySelectorAll('.target-row') : [];
    for (var i = 0; i < rs.length; i++) if (rs[i].dataset.pkg === pkg) return rs[i];
    return null;
  }

  function markBusy(row) {
    var sws = row ? row.querySelectorAll('.switch') : [];
    for (var i = 0; i < sws.length; i++) { sws[i].disabled = true; sws[i].setAttribute('aria-busy', 'true'); }
    var ci = row && row.querySelector('input[data-ag-cool]');
    if (ci) ci.disabled = true;
  }

  function writeChecked(row, t) {
    var sws = row ? row.querySelectorAll('.switch') : [];
    var want = [t.u0 ? 'true' : 'false', t.u999 ? 'true' : 'false'];
    for (var i = 0; i < sws.length; i++) if (sws[i].getAttribute('aria-checked') !== want[i]) sws[i].setAttribute('aria-checked', want[i]);
  }

  /* M1: optimistic model write, so a row rebuilt mid-flight renders the intended value (and stays
     locked via pend); the reply patches whichever row is live when it lands. */
  function setTarget(pkg, u0, u999, cooldown) {
    var t = findTarget(pkg), my = sid;
    if (!t || pend[pkg]) return;
    var n = seq[pkg] = (seq[pkg] || 0) + 1;
    var prev = { u0: t.u0, u999: t.u999, cooldown_s: t.cooldown_s };
    t.u0 = !!u0; t.u999 = !!u999;
    t.cooldown_s = cooldown === 'default' || cooldown == null ? null : Number(cooldown);
    var tok = pend[pkg] = {};
    var row0 = rowFor(pkg);
    markBusy(row0);
    writeChecked(row0, t);
    KM.call(['appguard', 'targets', 'set', pkg, 'u0=' + u0, 'u999=' + u999, 'cooldown=' + (cooldown == null ? 'default' : cooldown)], KM.T.mut)
      .then(function (r) {
        if (pend[pkg] === tok) delete pend[pkg];
        var t2 = findTarget(pkg);
        if (t2) {
          t2.u0 = r && r.u0 != null ? !!r.u0 : !!u0;
          t2.u999 = r && r.u999 != null ? !!r.u999 : !!u999;
          if (r && 'cooldown_s' in r) t2.cooldown_s = r.cooldown_s;
          else t2.cooldown_s = cooldown === 'default' ? null : Number(cooldown);
        }
        if (!alive(my)) return;
        secOk('targets');
        if (t2) patchRow(rowFor(pkg), t2);
        patchCounts();
      }).catch(function (e) {
        if (pend[pkg] === tok) delete pend[pkg];
        var t2 = findTarget(pkg);
        if (t2 && seq[pkg] === n) { t2.u0 = prev.u0; t2.u999 = prev.u999; t2.cooldown_s = prev.cooldown_s; }
        if (!alive(my)) return;
        var row = rowFor(pkg);
        if (t2) {
          patchRow(row, t2);
          var ci = row && row.querySelector('input');
          if (ci) { ci.value = t2.cooldown_s == null ? '' : String(t2.cooldown_s); markUnsaved(ci, false); }
        }
        patchCounts();
        secError('targets', e);
      });
  }

  function onToggle(btn) {
    var row = btn.closest('.target-row'), pkg = row && row.dataset.pkg;
    var t = pkg && findTarget(pkg);
    if (!t || btn.disabled || pend[pkg]) return;
    var u0 = t.u0 ? 1 : 0, u999 = t.u999 ? 1 : 0;
    if (btn.dataset.user === '0') u0 = u0 ? 0 : 1; else u999 = u999 ? 0 : 1;
    setTarget(pkg, u0, u999, t.cooldown_s == null ? 'default' : t.cooldown_s);
  }

  function onCooldown(input) {
    var row = input.closest('.target-row'), pkg = row && row.dataset.pkg;
    var t = pkg && findTarget(pkg);
    if (!t || pend[pkg]) return;
    var raw = input.value.trim();
    var cd = raw === '' ? 'default' : String(Math.max(0, Math.min(86400, parseInt(raw, 10) || 0)));
    if (cd !== 'default' && cd !== raw) input.value = cd;
    if ((cd === 'default' && t.cooldown_s == null) || String(t.cooldown_s) === cd) return;
    setTarget(pkg, t.u0 ? 1 : 0, t.u999 ? 1 : 0, cd);
  }

  function askRemove(btn) {
    var row = btn.closest('.target-row'), pkg = row && row.dataset.pkg;
    if (!pkg || row.querySelector('.ag-confirm')) return;
    var strip = E('div', 'ag-confirm row-confirm');
    strip.setAttribute('role', 'group');
    strip.setAttribute('aria-label', 'Confirm remove ' + pkg);
    strip.appendChild(E('span', '', 'Remove ' + pkg + '?'));
    var ok = KM.btn('Remove', 'danger'); ok.dataset.agAct = 'rm-confirm';
    var no = KM.btn('Cancel', 'ghost'); no.dataset.agAct = 'rm-cancel';
    strip.appendChild(ok); strip.appendChild(no);
    row.appendChild(strip);
    no.focus();
  }

  function doRemove(btn) {
    var row = btn.closest('.target-row'), pkg = row && row.dataset.pkg, my = sid;
    if (!pkg) return;
    var strip = row.querySelector('.ag-confirm');
    var bs = strip ? strip.querySelectorAll('button') : [];
    for (var i = 0; i < bs.length; i++) bs[i].disabled = true;
    KM.call(['appguard', 'targets', 'rm', pkg], KM.T.mut).then(function () {
      if (!alive(my)) return;
      S.ag.targets = (S.ag.targets || []).filter(function (t) { return t.pkg !== pkg; });
      secOk('targets');
      var top = sh.body.scrollTop;
      guarded('rows', renderRows);
      sh.body.scrollTop = top;
      patchCounts();
      KM.toast('Target removed: ' + pkg);
      var f = v.sec.targets.body.querySelector('input'); if (f) f.focus({ preventScroll: true });
    }).catch(function (e) {
      if (!alive(my)) return;
      if (strip && strip.parentNode) strip.parentNode.removeChild(strip);
      secError('targets', e);
    });
  }

  /* ---------------- Never ---------------- */
  function renderNever() {
    var s = v.sec.never;
    if (!s.tools.firstChild) {
      var pick = KM.btn('Pick', 'small', 'search');
      pick.dataset.agAct = 'picker-never';
      pick.setAttribute('aria-label', 'Pick a package for Never');
      s.tools.appendChild(pick);
    }
    var frag = document.createDocumentFragment();
    var list = E('div', 'never-list');
    (S.ag.never || []).forEach(function (p) {
      var c = E('span', 'never-chip');
      c.dataset.pkg = p;
      c.appendChild(E('span', '', p));
      var x = E('button'); x.type = 'button'; x.setAttribute('aria-label', 'Remove ' + p + ' from Never');
      x.dataset.agAct = 'never-rm';
      x.appendChild(KM.icon('x'));
      c.appendChild(x);
      list.appendChild(c);
    });
    if (!(S.ag.never || []).length) list.appendChild(E('span', 'muted', 'No protected packages.'));
    frag.appendChild(list);
    var row = E('div', 'run-actions');
    var inp = E('input', 'search'); inp.type = 'text'; inp.placeholder = 'com.example.app';
    inp.setAttribute('aria-label', 'Add package to Never'); inp.autocomplete = 'off'; inp.spellcheck = false;
    inp.maxLength = 128;
    inp.dataset.agNever = '1';
    inp.addEventListener('keydown', function (ev) { if (ev.key === 'Enter') { ev.preventDefault(); neverAdd(inp.value.trim(), inp).catch(function () {}); } });
    var add = KM.btn('Add', 'small');
    add.dataset.agAct = 'never-add';
    row.appendChild(inp); row.appendChild(add);
    frag.appendChild(row);
    frag.appendChild(E('p', 'muted', 'Never overrides user 0 and 999 targets.'));
    clear(s.body); s.body.appendChild(frag);
  }

  function applyNever(list) {
    S.ag.never = list;
    var changed = false;
    (S.ag.targets || []).forEach(function (t) {
      var sh2 = list.indexOf(t.pkg) >= 0;
      if (!!t.shadowed !== sh2) { t.shadowed = sh2; changed = true; }
    });
    guarded('never', renderNever);
    if (changed) guarded('rows', renderRows);
    patchCounts();
  }

  function neverAdd(p, inp) {
    var my = sid;
    if (!KM.RE.pkg.test(p) || p.length > 128) { secError('never', { code: 'E_ARG', msg: 'Invalid package name.' }); return Promise.resolve(false); }
    return KM.call(['appguard', 'never', 'add', p], KM.T.mut).then(function (r) {
      if (!alive(my)) return false;
      secOk('never');
      var list = r && r.never ? r.never : (S.ag.never || []).concat(S.ag.never.indexOf(p) < 0 ? [p] : []);
      applyNever(list);
      KM.toast('Added to Never: ' + p);
      if (inp) { var ni = v.sec.never.body.querySelector('[data-ag-never]'); if (ni) ni.focus(); }
      return true;
    }).catch(function (e) { if (alive(my)) secError('never', e); throw e; });
  }

  function neverRm(btn) {
    var chipEl = btn.closest('.never-chip'), p = chipEl && chipEl.dataset.pkg, my = sid;
    if (!p) return;
    btn.disabled = true;
    KM.call(['appguard', 'never', 'rm', p], KM.T.mut).then(function (r) {
      if (!alive(my)) return;
      secOk('never');
      applyNever(r && r.never ? r.never : (S.ag.never || []).filter(function (x) { return x !== p; }));
      var ni = v.sec.never.body.querySelector('[data-ag-never]'); if (ni) ni.focus({ preventScroll: true });
    }).catch(function (e) { btn.disabled = false; if (alive(my)) secError('never', e); });
  }

  /* ---------------- Recent kills ---------------- */
  function renderKills() {
    var s = v.sec.kills;
    if (!s.tools.firstChild) {
      var b = KM.btn('Refresh', 'small', 'refresh');
      b.dataset.agAct = 'kills-refresh';
      s.tools.appendChild(b);
    }
    var frag = document.createDocumentFragment();
    var k = S.agKills;
    if (!k) { frag.appendChild(E('p', 'muted', 'Loading…')); clear(s.body); s.body.appendChild(frag); return; }
    var list = (k.kills || []).slice(0, KILLS);
    if (!list.length) frag.appendChild(E('p', 'muted', 'No kills recorded yet.'));
    else {
      var boxEl = E('div', 'kills');
      list.forEach(function (x) {
        var r = E('div', 'kill-row');
        r.appendChild(E('span', '', KM.relTime(x.ts)));
        r.appendChild(E('span', '', 'u' + x.user));
        r.appendChild(E('span', 'pkg', x.pkg));
        r.appendChild(pill(x.mode === 'dry' ? 'dry' : 'kill', x.mode === 'dry' ? 'dry' : ''));
        r.appendChild(pill(x.result === 'fail' ? 'fail' : 'ok', x.result === 'fail' ? 'fail' : 'ok'));
        boxEl.appendChild(r);
      });
      frag.appendChild(boxEl);
      frag.appendChild(E('p', 'muted', 'Showing ' + list.length + ' of ' + (k.total != null ? k.total : list.length) + '.'));
    }
    clear(s.body); s.body.appendChild(frag);
  }

  function loadKills() {
    var my = sid;
    var b = v && v.sec.kills.tools.firstChild; if (b) b.disabled = true;
    return KM.call(['appguard', 'kills', String(KILLS)], KM.T.read).then(function (r) {
      if (!alive(my)) return;
      S.agKills = r; secOk('kills');
      guarded('kills', renderKills);
    }).catch(function (e) {
      if (alive(my)) { secError('kills', e); if (!S.agKills) { S.agKills = { kills: [], total: 0 }; guarded('kills', renderKills); } }
    }).then(function () { if (b) b.disabled = false; });
  }

  /* ---------------- Package picker (in-sheet sub-view) ---------------- */
  function picker(mode, opener) {
    if (!v || v.picker) return;
    var my = sid;
    var p = { mode: mode, opener: opener, user: 0, timer: null, scroll: sh.body.scrollTop };
    v.picker = p;
    var el = E('div', 'ag-picker');
    var head = E('div', 'ag-picker-head');
    var back = KM.btn('Back', 'ghost', 'chevron');
    back.classList.add('ag-back');
    back.dataset.agAct = 'picker-back';
    head.appendChild(back);
    var h = E('h3', '', mode === 'never' ? 'Add to Never' : 'Add target');
    el.setAttribute('role', 'region');
    el.setAttribute('aria-label', h.textContent);
    head.appendChild(h);
    el.appendChild(head);
    var seg = null;
    if (mode !== 'never') {
      seg = E('div', 'segmented');
      seg.setAttribute('role', 'group');
      seg.setAttribute('aria-label', 'Android user');
      [0, 999].forEach(function (u) {
        var b = KM.btn('User ' + u, '');
        b.dataset.user = String(u);
        b.setAttribute('aria-pressed', u === 0 ? 'true' : 'false');
        b.addEventListener('click', function () {
          p.user = u;
          Array.prototype.forEach.call(seg.children, function (x) { x.setAttribute('aria-pressed', x.dataset.user === String(u) ? 'true' : 'false'); });
          loadRows(search.value.trim());
        });
        seg.appendChild(b);
      });
      el.appendChild(seg);
    }
    var search = E('input', 'search'); search.type = 'search'; search.placeholder = 'Search packages…';
    search.setAttribute('aria-label', 'Search packages');
    el.appendChild(search);
    var err = E('div', 'alert'); err.hidden = true; err.setAttribute('role', 'alert');
    el.appendChild(err);
    var list = E('div', 'picker-list');
    el.appendChild(list);
    search.addEventListener('input', function () {
      clearTimeout(p.timer); p.timer = setTimeout(function () { loadRows(search.value.trim()); }, 250);
    });
    p.el = el;
    v.main.hidden = true;
    sh.body.appendChild(el);
    sh.body.scrollTop = 0;
    search.focus();

    function loadRows(q) {
      clear(list); list.appendChild(E('p', 'muted', 'Loading…'));
      var args = ['appguard', 'packages', '--user', String(p.user)];
      if (q) args.push('--q', q);
      var reqUser = p.user;
      var seq = p.seq = (p.seq || 0) + 1;
      KM.call(args, KM.T.read).then(function (r) {
        if (seq !== p.seq || !alive(my) || v.picker !== p || reqUser !== p.user) return;
        KM.hideError(err);
        KM.guard(list, 'package picker', function () {
          var frag = document.createDocumentFragment();
          var pk = r.packages || [];
          pk.slice(0, PICK_CAP).forEach(function (x) {
            var row = E('button', 'picker-row');
            row.type = 'button';
            row.dataset.pkg = x.pkg;
            row.appendChild(E('span', 'pkg', x.pkg));
            var tags = E('span', 'tags');
            if (x.never) tags.appendChild(KM.chip('never', 'kind'));
            if (x.target) tags.appendChild(KM.chip('target', 'src'));
            row.appendChild(tags);
            if (x.never) { row.disabled = true; row.setAttribute('aria-disabled', 'true'); }
            frag.appendChild(row);
          });
          if (!pk.length) frag.appendChild(E('p', 'muted', 'No packages found.'));
          else if (pk.length > PICK_CAP) frag.appendChild(E('p', 'muted', 'Showing ' + PICK_CAP + ' of ' + pk.length + '. Refine the search.'));
          clear(list); list.appendChild(frag);
        }, function () { loadRows(search.value.trim()); });
      }).catch(function (e) { if (seq === p.seq && alive(my) && v.picker === p) { clear(list); KM.showError(err, e); } });
    }

    list.addEventListener('click', function (ev) {
      var row = ev.target.closest('.picker-row');
      if (!row || row.disabled) return;
      var pkg = row.dataset.pkg;
      row.disabled = true;
      if (mode === 'never') {
        neverAdd(pkg).then(function (ok) { if (ok) closePicker(); }, function (e) { row.disabled = false; KM.showError(err, e); });
        return;
      }
      var u = p.user, ex = findTarget(pkg);
      /* E4: existing target -> `targets set` (the backend answers `add` with E_CONFLICT) */
      var args = ex
        ? ['appguard', 'targets', 'set', pkg, 'u0=' + (u === 999 ? (ex.u0 ? 1 : 0) : 1), 'u999=' + (u === 999 ? 1 : (ex.u999 ? 1 : 0)), 'cooldown=' + (ex.cooldown_s == null ? 'default' : ex.cooldown_s)]
        : ['appguard', 'targets', 'add', pkg, u === 999 ? 'u0=0' : 'u0=1', u === 999 ? 'u999=1' : 'u999=0'];
      KM.call(args, KM.T.mut).then(function (r) {
        if (!alive(my)) return;
        var t = findTarget(pkg);
        if (!t) { t = { pkg: pkg, u0: false, u999: false, cooldown_s: null, shadowed: (S.ag.never || []).indexOf(pkg) >= 0 }; S.ag.targets.push(t); }
        t.u0 = r && r.u0 != null ? !!r.u0 : (ex ? (u === 999 ? !!ex.u0 : true) : u !== 999);
        t.u999 = r && r.u999 != null ? !!r.u999 : (ex ? (u === 999 ? true : !!ex.u999) : u === 999);
        if (r && 'cooldown_s' in r) t.cooldown_s = r.cooldown_s;
        KM.toast('Target added: ' + pkg);
        closePicker();
        guarded('rows', renderRows);
        patchCounts();
      }).catch(function (e) { row.disabled = false; if (alive(my)) KM.showError(err, e); });
    });
    loadRows('');
  }

  function closePicker() {
    if (!v || !v.picker) return false;
    var p = v.picker;
    clearTimeout(p.timer);
    if (p.el && p.el.parentNode) p.el.parentNode.removeChild(p.el);
    v.picker = null;
    v.main.hidden = false;
    sh.body.scrollTop = p.scroll;
    if (p.opener && document.contains(p.opener)) try { p.opener.focus({ preventScroll: true }); } catch (e) {}
    return true;
  }

  /* ---------------- sheet shell ---------------- */
  function onClick(ev) {
    var t = ev.target.closest('[data-ag-act]');
    if (!t || !v || t.disabled) return;
    var act = t.getAttribute('data-ag-act');
    if (act === 'start' || act === 'stop' || act === 'restart') lifecycle(act);
    else if (act === 'dry') toggleDry(t);
    else if (act === 'run') { v.confirmRun = true; guarded('run', renderRun); }
    else if (act === 'run-cancel') { v.confirmRun = false; guarded('run', renderRun); var r = v.sec.run.body.querySelector('[data-ag-act="run"]'); if (r) r.focus(); }
    else if (act === 'run-confirm') runOnce(false);
    else if (act === 'dry-run') runOnce(true);
    else if (act === 'picker-target') picker('target', t);
    else if (act === 'picker-never') picker('never', t);
    else if (act === 'picker-back') closePicker();
    else if (act === 'target-toggle') onToggle(t);
    else if (act === 'target-rm') askRemove(t);
    else if (act === 'rm-cancel') {
      var row = t.closest('.target-row'), s = t.closest('.ag-confirm');
      if (s) s.parentNode.removeChild(s);
      var rb = row && row.querySelector('[data-ag-act="target-rm"]'); if (rb) rb.focus();
    }
    else if (act === 'rm-confirm') doRemove(t);
    else if (act === 'more') {
      var top = sh.body.scrollTop;
      S.agPage = Math.min(CAP, S.agPage + PAGE);
      guarded('rows', renderRows);
      sh.body.scrollTop = top;
    }
    else if (act === 'never-add') {
      var inp = v.sec.never.body.querySelector('[data-ag-never]');
      if (inp) neverAdd(inp.value.trim(), inp).catch(function () {});
    }
    else if (act === 'never-rm') neverRm(t);
    else if (act === 'kills-refresh') loadKills();
  }

  function onCoolKey(ev) { var t = ev.target; if (ev.key !== 'Enter' || !t || !t.dataset || !t.dataset.agCool) return; ev.preventDefault(); if (!alive(sid) || (S.modal && S.modal.closing)) return; onCooldown(t); }

  function buildSections() {
    var main = v.main;
    clear(main);
    var defs = [
      ['status', 'Status', ''],
      ['settings', 'Settings', ''],
      ['run', 'Run now', ''],
      ['targets', 'Targets', 'Per-app watch for user 0 and user 999.'],
      ['never', 'Never', 'Packages AppGuard never kills.'],
      ['kills', 'Recent kills', 'Last ' + KILLS + ' entries.']
    ];
    var frag = document.createDocumentFragment();
    defs.forEach(function (d) {
      var s = sec(d[0], d[1], d[2]);
      v.sec[d[0]] = s;
      frag.appendChild(s.el);
    });
    main.appendChild(frag);
    guarded('status', renderStatus);
    guarded('settings', renderSettings);
    guarded('run', renderRun);
    guarded('targets', renderTargets);
    guarded('never', renderNever);
    guarded('kills', renderKills);
  }

  function loadAll() {
    var my = sid;
    clear(v.main);
    v.main.appendChild(E('p', 'muted', 'Loading AppGuard…'));
    return KM.call(['appguard', 'get'], KM.T.read).then(function (ag) {
      if (!alive(my)) return;
      S.ag = ag;
      if (!S.ag.targets) S.ag.targets = [];
      if (!S.ag.never) S.ag.never = [];
      if (!S.ag.counts) recount();
      KM.guard(v.main, 'AppGuard sheet', buildSections, loadAll);
      loadKills();
    }).catch(function (e) {
      if (!alive(my)) return;
      clear(v.main);
      var err = E('div', 'alert'); err.id = 'ag-sheet-error'; err.setAttribute('role', 'alert');
      v.main.appendChild(err);
      KM.showError(err, e);
      var r = KM.btn('Retry', '', 'refresh');
      r.addEventListener('click', function () { loadAll(); });
      v.main.appendChild(r);
    });
  }

  function cleanup() {
    if (v) {
      clearTimeout(v.filterT);
      if (v.picker) clearTimeout(v.picker.timer);
    }
    sid++; pend = {};
    sh = null; v = null;
    S.agPage = PAGE; S.agSearch = ''; S.agResult = null;
  }

  function open() {
    if (sh && S.modal === sh) return sh;
    sid++; pend = {};
    S.agPage = PAGE; S.agSearch = ''; S.agResult = null; S.agKills = null;
    sh = KM.sheet({
      title: 'AppGuard', sub: 'Idle app watchdog', cls: 'ag-sheet',
      onClose: cleanup,
      onEscape: function () { return closePicker(); }
    });
    v = { sec: {}, picker: null, busy: null, running: null, confirmRun: false, filterT: null, refocus: null };
    v.main = E('div', 'ag-main');
    sh.setBody(v.main);
    sh.body.addEventListener('click', onClick);
    sh.body.addEventListener('keydown', onCoolKey);
    var done = KM.btn('Done', 'primary', 'check');
    done.addEventListener('click', function () { if (sh) sh.close(); });
    sh.setFooter([done]);
    loadAll();
    return sh;
  }

  KM.appguard = { open: open };
})();
