/* KonaManager UI - daemons tab (fingerprint + in-place reconcile) */
(function () {
  'use strict';
  var KM = window.KM, S = KM.S;
  var E = KM.E, $ = KM.$, clear = KM.clear, text = KM.text;

  var LABEL = {
    running: 'RUNNING', stopped: 'STOPPED', failed: 'FAILED',
    done: 'DONE', unknown: 'UNKNOWN', busy: 'WORKING'
  };

  function stateOf(item) {
    if (S.busy[item.id]) return 'busy';
    var s = item.state || (item.running ? 'running' : 'stopped');
    if (s === 'running' && !item.running) s = 'unknown';
    return LABEL[s] ? s : 'unknown';
  }

  function emptyState(title, body, withAdd) {
    var box = E('div', 'empty');
    box.appendChild(E('strong', '', title));
    box.appendChild(E('span', '', body));
    if (withAdd) {
      var b = KM.btn('Add a daemon', 'primary', 'plus');
      b.addEventListener('click', function () { KM.add.open(); });
      var wrap = E('div', 'section-actions');
      wrap.style.justifyContent = 'center';
      wrap.style.marginTop = '14px';
      wrap.appendChild(b);
      box.appendChild(wrap);
    }
    return box;
  }

  function tele(k, v, cls, f) {
    var d = E('div', 'tele');
    if (f) d.dataset.f = f;
    d.appendChild(E('div', 'k', k));
    d.appendChild(E('div', 'v ' + (cls || ''), v == null || v === '' ? '-' : v));
    return d;
  }

  function verifiedBadge(v) {
    var b = E('span', 'vbadge ' + (v === 'marker' ? 'marker' : v === 'pidfile+argv' ? 'pidfile' : 'none'));
    text(b, v === 'marker' ? 'marker' : v === 'pidfile+argv' ? 'pidfile+argv' : v === 'none' ? 'unverified' : (v || 'unknown'));
    return b;
  }

  function healthEl(item) {
    var d = E('div', 'tele');
    d.dataset.f = 'health';
    d.appendChild(E('div', 'k', 'Health'));
    var v = E('div', 'v');
    var h = item.health || 'na';
    var label = h === 'ok' ? 'ok' : h === 'degraded' ? 'degraded' : h === 'down' ? 'down' : 'n/a';
    var s = E('span', 'health ' + (h === 'ok' ? 'ok' : h === 'degraded' ? 'degraded' : h === 'down' ? 'down' : 'na'), label);
    v.appendChild(s);
    if (item.health_detail) v.appendChild(E('div', 'muted', item.health_detail));
    d.appendChild(v);
    return d;
  }

  function failure(item) {
    var last = item.last;
    if (!last || last.ok !== false) return null;
    var b = E('div', 'failure');
    b.dataset.f = 'failure';
    b.appendChild(E('span', 'code', last.code || 'E_UNKNOWN'));
    b.appendChild(document.createTextNode('Last ' + (last.action || 'action') + ' failed' + (last.ts ? ' · ' + KM.fmtTs(last.ts) : '') + '.'));
    return b;
  }

  function detailsView(item) {
    var d = S.details[item.id];
    var box = E('div', 'details');
    box.dataset.f = 'details';
    if (!d) { box.appendChild(E('span', 'muted', 'Loading details…')); return box; }
    var daemon = d.daemon || {};
    var meta = d.meta || {};
    var dl = E('dl', 'kv');
    function pair(k, v) {
      dl.appendChild(E('dt', '', k));
      dl.appendChild(E('dd', '', v == null || v === '' ? '-' : String(v)));
    }
    pair('state', daemon.state || '-');
    pair('boot', daemon.boot || meta.boot || '-');
    pair('version', daemon.version || meta.version || '-');
    pair('source', daemon.source || meta.source || '-');
    pair('exit', d.exit_code == null ? '-' : d.exit_code);
    if (meta.start) pair('start', meta.start);
    if (meta.stop) pair('stop', meta.stop);
    if (meta.stop_scope) pair('scope', meta.stop_scope);
    if (meta.argv_match) pair('argv', meta.argv_match);
    box.appendChild(dl);
    if (d.log_tail && d.log_tail.length) {
      box.appendChild(E('h4', '', 'Last log lines'));
      box.appendChild(E('pre', '', d.log_tail.join('\n')));
    }
    return box;
  }

  function card(item) {
    var st = stateOf(item);
    var c = E('article', 'card');
    c.dataset.id = item.id;
    c.dataset.state = st;

    var head = E('div', 'card-head');
    var stEl = E('span', 'state');
    stEl.dataset.f = 'state';
    stEl.dataset.s = st;
    stEl.appendChild(E('span', 'dot'));
    stEl.appendChild(E('span', '', S.busy[item.id] ? S.busy[item.id].toUpperCase() + '…' : LABEL[st]));
    head.appendChild(stEl);
    c.appendChild(head);

    var title = E('div', 'card-title');
    title.dataset.f = 'title';
    title.appendChild(E('h3', '', item.name || item.id));
    title.appendChild(E('div', 'card-id', item.id));
    c.appendChild(title);

    var chips = E('div', 'card-chips');
    chips.dataset.f = 'chips';
    if (item.source) chips.appendChild(KM.chip(item.source, 'src'));
    if (item.kind === 'oneshot') chips.appendChild(KM.chip('oneshot', 'kind'));
    if (item.boot) chips.appendChild(KM.chip(item.boot, 'src'));
    c.appendChild(chips);
    if (item.desc) { var de = E('p', 'desc', item.desc); de.dataset.f = 'desc'; c.appendChild(de); }

    var tel = E('div', 'telemetry');
    tel.dataset.f = 'telemetry';
    var pids = item.pids && item.pids.length ? item.pids.join(', ') : (item.pid ? String(item.pid) : '-');
    tel.appendChild(tele('PID', pids, '', 'pid'));
    tel.appendChild(tele('Uptime', KM.fmtUptime(item.uptime_s), '', 'uptime'));
    tel.appendChild(healthEl(item));
    var ver = E('div', 'tele');
    ver.dataset.f = 'verified';
    ver.appendChild(E('div', 'k', 'Verified'));
    var vv = E('div', 'v');
    vv.appendChild(verifiedBadge(item.verified_by));
    ver.appendChild(vv);
    tel.appendChild(ver);
    c.appendChild(tel);

    var swRow = E('div', 'switch-row');
    swRow.dataset.f = 'boot';
    swRow.appendChild(E('span', 'switch-label', 'Start at boot'));
    var sw = E('button', 'switch');
    sw.type = 'button';
    sw.setAttribute('role', 'switch');
    sw.setAttribute('aria-checked', item.enabled ? 'true' : 'false');
    sw.setAttribute('aria-label', 'Start ' + item.name + ' at boot');
    sw.dataset.act = 'toggle';
    sw.dataset.f = 'switch';
    sw.disabled = !!S.busy[item.id];
    swRow.appendChild(sw);
    c.appendChild(swRow);

    var row = E('div', 'card-actions');
    row.dataset.f = 'actions';
    var busy = !!S.busy[item.id];
    var primary;
    if (item.kind === 'oneshot') {
      primary = KM.btn(item.running || item.state === 'done' ? 'Run again' : 'Run', 'primary primary-action', 'play');
      primary.dataset.act = 'start';
    } else if (item.running) {
      primary = KM.btn('Stop', 'primary primary-action', 'stop');
      primary.dataset.act = 'stop';
    } else {
      primary = KM.btn('Start', 'primary primary-action', 'play');
      primary.dataset.act = 'start';
    }
    primary.dataset.f = 'primary';
    primary.disabled = busy;
    row.appendChild(primary);

    if (item.kind !== 'oneshot') {
      var rb = KM.btn('', '', 'restart');
      rb.dataset.act = 'restart';
      rb.dataset.f = 'restart';
      rb.setAttribute('aria-label', 'Restart ' + item.name);
      rb.disabled = busy || !item.running;
      row.appendChild(rb);
    }

    if (item.id === 'appguard' || item.id === 'deep-sleep-cool') {
      var gb = KM.btn('', '', 'gear');
      gb.dataset.act = 'settings';
      gb.dataset.f = 'gear';
      gb.setAttribute('aria-label', item.name + ' settings');
      gb.disabled = busy;
      row.appendChild(gb);
    }
    var db = KM.btn('', '', 'chevron');
    db.dataset.act = 'details';
    db.dataset.f = 'details-btn';
    db.setAttribute('aria-label', 'Details for ' + item.name);
    row.appendChild(db);
    var xb = KM.btn('', '', 'trash');
    xb.dataset.act = 'delete';
    xb.dataset.f = 'delete';
    xb.setAttribute('aria-label', item.removable ? 'Delete ' + item.name : 'Unmanage ' + item.name);
    xb.disabled = busy;
    row.appendChild(xb);
    c.appendChild(row);

    var f = failure(item); if (f) c.appendChild(f);
    if (S.openDetails[item.id]) c.appendChild(detailsView(item));
    return c;
  }

  function skeleton() {
    var wrap = document.createDocumentFragment();
    for (var i = 0; i < 3; i++) wrap.appendChild(E('div', 'skeleton'));
    return wrap;
  }

  /* ---- in-place morph: patch dst to match src, keeping dst nodes ----
     Children are matched by position, or by data-f key when the keyed slot
     moved. Attributes/text are written only when they differ, so a patch
     with identical content performs zero DOM writes. */
  function fkey(n) { return n.nodeType === 1 ? (n.getAttribute('data-f') || '') : ''; }
  function same(a, b) { return a.nodeType === b.nodeType && a.nodeName === b.nodeName && fkey(a) === fkey(b); }
  function syncAttrs(d, s) {
    var i, a, sa = s.attributes, da = d.attributes, drop = [];
    for (i = 0; i < sa.length; i++) {
      a = sa[i];
      if (d.getAttribute(a.name) !== a.value) d.setAttribute(a.name, a.value);
    }
    for (i = 0; i < da.length; i++) if (!s.hasAttribute(da[i].name)) drop.push(da[i].name);
    drop.forEach(function (n) { d.removeAttribute(n); });
  }
  function morph(d, s) {
    if (d.nodeType === 3 || d.nodeType === 8) {
      if (d.nodeValue !== s.nodeValue) d.nodeValue = s.nodeValue;
      return;
    }
    syncAttrs(d, s);
    var sc = s.firstChild, dc = d.firstChild;
    while (sc) {
      var next = sc.nextSibling;
      if (dc && same(dc, sc)) { morph(dc, sc); dc = dc.nextSibling; }
      else {
        var k = fkey(sc), match = null;
        if (k) for (var x = dc; x; x = x.nextSibling) if (fkey(x) === k && x.nodeName === sc.nodeName) { match = x; break; }
        if (match) { d.insertBefore(match, dc); morph(match, sc); dc = match.nextSibling; }
        else d.insertBefore(sc, dc);
      }
      sc = next;
    }
    while (dc) { var n = dc.nextSibling; d.removeChild(dc); dc = n; }
  }
  KM.morph = morph;

  function cardFp(item) {
    var id = item.id;
    return JSON.stringify(item) + '|' + (S.busy[id] || '') + '|' + (S.openDetails[id] ? 'o' + S.detailsRev : '');
  }
  function listFp() {
    var e = S.error ? KM.errInfo(S.error).code : '';
    return JSON.stringify(S.daemons) + '|' + JSON.stringify(S.busy) + '|' + Object.keys(S.openDetails).sort().join(',') +
      '|' + S.detailsRev + '|' + e + '|' + (S.loaded ? 1 : 0) + (S.loading && !S.loaded ? 'L' : '');
  }

  function setText(n, t) { if (n && n.textContent !== t) n.textContent = t; }
  function setAttr(n, k, v) { if (n && n.getAttribute(k) !== v) n.setAttribute(k, v); }

  function reconcile(list) {
    var y = window.scrollY, act = document.activeElement;
    var kids = Array.prototype.slice.call(list.children), map = {}, hasCards = false;
    kids.forEach(function (c) {
      if (c.classList.contains('card') && c.dataset.id) { map[c.dataset.id] = c; hasCards = true; }
      else list.removeChild(c); /* skeleton, empty state, panel-error */
    });
    if (!hasCards) {
      var frag = document.createDocumentFragment();
      S.daemons.forEach(function (d) { var el = card(d); el._fp = cardFp(d); frag.appendChild(el); });
      list.appendChild(frag);
    } else {
      var ref = list.firstChild, seen = {};
      S.daemons.forEach(function (d) {
        var el = map[d.id], f = cardFp(d);
        if (el) { if (el._fp !== f) { morph(el, card(d)); el._fp = f; } }
        else { el = card(d); el._fp = f; }
        seen[d.id] = true;
        if (el !== ref) list.insertBefore(el, ref); else ref = ref.nextSibling;
      });
      Object.keys(map).forEach(function (id) { if (!seen[id] && map[id].parentNode === list) list.removeChild(map[id]); });
    }
    if (window.scrollY !== y) window.scrollTo(window.scrollX, y);
    if (act && act !== document.activeElement && document.contains(act) && act.focus) {
      try { act.focus({ preventScroll: true }); } catch (e) {}
    }
  }

  function paint(list) {
    var err = $('daemon-error');
    var count = $('daemon-count');
    if (!S.loaded && S.loading) {
      if (!list.querySelector('.card')) {
        setAttr(list, 'aria-busy', 'true');
        if (!list.querySelector('.skeleton')) { clear(list); list.appendChild(skeleton()); }
      }
      setText(count, 'loading');
      return;
    }
    setAttr(list, 'aria-busy', 'false');
    if (S.error) {
      KM.showError(err, S.error);
      setText(count, 'error');
    } else {
      if (err && !err.hidden) KM.hideError(err);
      var running = S.daemons.filter(function (d) { return d.running; }).length;
      setText(count, running + ' / ' + S.daemons.length + ' running');
    }
    if (!S.daemons.length) {
      clear(list);
      list.appendChild(emptyState(S.error ? 'Daemons unavailable' : 'No daemons yet.',
        S.error ? 'The manager could not read the daemon list. Retry from the header.' : 'Install a package, create one, or import an existing service.d script.',
        !S.error));
      return;
    }
    reconcile(list);
  }

  /* render(force): no DOM write when the fingerprint is unchanged; while the
     Daemons panel is hidden only marks dirty (reconciled on activation). */
  function render(force) {
    var list = $('daemon-list');
    if (!list) return;
    KM.guard(list, 'daemon list', function () {
      var fp = listFp();
      if (!force && fp === S.fp && !S.dirty) return;
      if (S.tab !== 'daemons') { S.dirty = true; return; }
      S.dirty = false;
      S.fp = fp; /* set before painting: a throwing render is not repeated on identical data */
      paint(list);
    }, retry);
  }
  function retry() { S.fp = null; load(true); }

  /* M2: a refresh asked for while a `list` is in flight is coalesced into ONE follow-up load;
     the in-flight reply is stale (it may predate the action that asked), so it is not painted. */
  function load(silent, join) {
    if (S.loading) { if (!join) S.again = true; return S.loadP; }
    S.loading = true;
    if (!silent || !S.loaded) render();
    S.loadP = KM.call(['list'], KM.T.read).then(function (r) {
      if (S.again) return;
      S.daemons = (r.daemons || []).filter(function (d) { return d && d.id; });
      S.loaded = true;
      S.error = null;
      KM.markOk('daemons');
      KM.setConn('ok', 'ready');
    }).catch(function (e) {
      if (S.again) return;
      S.error = e;
      KM.setConn('error', KM.hasKsu() ? 'dm error' : 'no ksu');
    }).then(function () {
      S.loading = false;
      if (S.again) { S.again = false; return load(true); }
      render();
      return true;
    });
    return S.loadP;
  }

  /* poll gate: Daemons tab, page visible, no modal open, no load in flight */
  function canPoll() { return S.tab === 'daemons' && !document.hidden && !S.modal && !S.loading; }
  function pollTick() { return canPoll() ? load(true, true) : Promise.resolve(false); }
  function schedule() {
    clearTimeout(S.daemonTimer);
    S.daemonTimer = setTimeout(function () {
      try { pollTick(); } catch (e) { console.warn('[KM] poll failed', e); }
      schedule();
    }, 5000);
  }

  function perform(id, action, extra, timeout) {
    var args = [action, id];
    if (extra) args = args.concat(extra);
    return KM.call(args, timeout || KM.T.mut);
  }

  function runAction(id, action, extra) {
    if (S.busy[id]) return Promise.resolve();
    var item = S.daemons.filter(function (d) { return d.id === id; })[0];
    var label = { start: 'Starting', stop: 'Stopping', restart: 'Restarting', enable: 'Enabling', disable: 'Disabling' }[action] || action;
    S.busy[id] = label.toLowerCase();
    render(true);
    return perform(id, action, extra).then(function (r) {
      if (action === 'start' && r.state === 'running') KM.toast(id + ' started' + (r.pid ? ' · pid ' + r.pid : ''));
      else if (action === 'stop') KM.toast(id + ' stopped');
      else if (action === 'restart') KM.toast(id + ' restarted');
      else if (action === 'enable') KM.toast(id + ' will start at boot');
      else if (action === 'disable') KM.toast(id + ' disabled' + (r.stopped ? ' and stopped' : ''));
      else KM.toast(id + ' ' + action + ' ok');
      return r;
    }).catch(function (e) {
      var x = KM.errInfo(e);
      KM.toast(x.code + ': ' + x.msg, true);
      throw e;
    }).then(function (r) {
      delete S.busy[id];
      load(true);
      return r;
    }, function (e) {
      delete S.busy[id];
      load(true);
      throw e;
    });
  }

  function toggle(item) {
    if (S.busy[item.id]) return;
    if (!item.enabled) {
      runAction(item.id, 'enable').catch(function () {});
      return;
    }
    if (!item.running) {
      runAction(item.id, 'disable').catch(function () {});
      return;
    }
    var sh = KM.sheet({ title: 'Disable ' + item.name, sub: 'It is running now.' });
    var box = E('div');
    box.appendChild(E('p', 'muted', 'Choose whether disabling also stops the running daemon.'));
    var err = E('div', 'alert'); err.hidden = true; box.appendChild(err);
    var cancel = KM.btn('Cancel', 'ghost');
    cancel.addEventListener('click', function () { sh.close(); });
    var keep = KM.btn('Disable, keep running', '');
    var stop = KM.btn('Disable and stop now', 'danger');
    keep.addEventListener('click', function () {
      sh.setBlocking(true);
      runAction(item.id, 'disable', ['--keep-running']).then(function () { sh.setBlocking(false); sh.close(); })
        .catch(function (e) { sh.setBlocking(false); KM.showError(err, e); });
    });
    stop.addEventListener('click', function () {
      sh.setBlocking(true);
      runAction(item.id, 'disable').then(function () { sh.setBlocking(false); sh.close(); })
        .catch(function (e) { sh.setBlocking(false); KM.showError(err, e); });
    });
    sh.setBody(box); sh.setFooter([cancel, keep, stop]);
  }

  function openDetails(id) {
    if (S.openDetails[id]) {
      delete S.openDetails[id];
      render();
      return;
    }
    S.openDetails[id] = true;
    render();
    KM.call(['status', id], KM.T.read).then(function (r) {
      S.details[id] = r;
      S.detailsRev++;
      render();
    }).catch(function (e) {
      S.details[id] = { daemon: {}, meta: {}, exit_code: null, log_tail: [KM.errInfo(e).code + ': ' + KM.errInfo(e).msg] };
      S.detailsRev++;
      render();
    });
  }

  function stopConfirm(item) {
    KM.confirm({
      title: 'Stop root sshd?',
      message: 'Ends the port 22 listener. Live sessions stay up.',
      label: 'Stop sshd',
      danger: true,
      onConfirm: function () { return runAction(item.id, 'stop'); }
    });
  }

  function settingsFor(item) {
    if (item.id === 'appguard' && KM.appguard) { KM.appguard.open(); return; }
    if (item.id === 'deep-sleep-cool' && KM.settings) KM.settings.open();
  }

  function onClick(ev) {
    var t = ev.target.closest('[data-act]');
    if (!t) return;
    var cardEl = t.closest('[data-id]');
    if (!cardEl) return;
    var id = cardEl.getAttribute('data-id');
    var item = S.daemons.filter(function (d) { return d.id === id; })[0];
    if (!item) return;
    var act = t.getAttribute('data-act');
    if (act === 'toggle') toggle(item);
    else if (act === 'start') runAction(id, 'start').catch(function () {});
    else if (act === 'stop') {
      if (id === 'root-sshd') stopConfirm(item);
      else runAction(id, 'stop').catch(function () {});
    }
    else if (act === 'restart') runAction(id, 'restart').catch(function () {});
    else if (act === 'details') openDetails(id);
    else if (act === 'settings') settingsFor(item);
    else if (act === 'delete') openDelete(item);
  }

  function openDelete(item) {
    var sh = KM.sheet({ title: (item.removable ? 'Delete ' : 'Unmanage ') + item.name, sub: item.id });
    var body = E('div');
    body.appendChild(E('p', 'muted', 'Reading the removal plan…'));
    var err = E('div', 'alert'); err.hidden = true;
    var cancel = KM.btn('Cancel', 'ghost');
    cancel.addEventListener('click', function () { sh.close(); });
    sh.setBody(body); sh.setFooter([cancel]);

    KM.call(['delete', item.id, '--plan'], KM.T.read).then(function (r) {
      var plan = r.plan || {};
      clear(body);
      err.hidden = true;
      var list = E('div');
      if (plan.stop) list.appendChild(row('Stops the daemon', 'yes'));
      if (plan.remove_dir) list.appendChild(row('Removes', plan.remove_dir));
      if (plan.remove_wrapper) list.appendChild(row('Removes wrapper', plan.remove_wrapper));
      if (plan.run_uninstall_hook) list.appendChild(row('Runs uninstall hook as root', 'root'));
      (plan.keeps || []).forEach(function (k) { if (k) list.appendChild(row('Leaves alone', k, 'muted')); });
      if (!item.removable) list.appendChild(row('Keeps script and boot state', 'yes', 'muted'));
      body.appendChild(list);
      body.appendChild(err);
      var f = E('label', 'field type-confirm');
      f.appendChild(E('span', '', 'Type "' + item.id + '" to confirm'));
      var input = E('input'); input.type = 'text'; input.autocomplete = 'off'; input.className = 'mono';
      f.appendChild(input); body.appendChild(f);
      var del = KM.btn(item.removable ? 'Delete' : 'Unmanage', 'danger');
      del.disabled = true;
      input.addEventListener('input', function () { del.disabled = input.value !== item.id; });
      del.addEventListener('click', function () {
        if (input.value !== item.id) return;
        del.disabled = true; cancel.disabled = true; input.disabled = true; sh.setBlocking(true);
        KM.call(['delete', item.id, '--confirm', item.id], KM.T.install).then(function (res) {
          sh.setBlocking(false);
          clear(body);
          var ok = E('div');
          ok.appendChild(E('p', '', (res.unmanaged ? 'Unmanaged ' : 'Deleted ') + item.id + '.'));
          if (res.hook && res.hook.ran) ok.appendChild(E('p', 'muted', 'Uninstall hook exit ' + res.hook.exit));
          (res.removed || []).forEach(function (p) { ok.appendChild(E('div', 'plain-link', p)); });
          body.appendChild(ok);
          sh.setFooter([KM.btn('Done', 'primary', 'check')]);
          sh.foot.firstChild.addEventListener('click', function () { sh.close(); });
          load(true);
        }).catch(function (e) {
          sh.setBlocking(false); del.disabled = false; cancel.disabled = false; input.disabled = false;
          KM.showError(err, e);
        });
      });
      sh.setFooter([cancel, del]);
      setTimeout(function () { input.focus(); }, 20);
    }).catch(function (e) {
      clear(body);
      err.hidden = true;
      body.appendChild(E('p', 'muted', 'Could not read the plan.'));
      KM.showError(err, e);
    });

    function row(k, v, cls) {
      var d = E('div', 'about-row');
      d.appendChild(E('span', '', k));
      d.appendChild(E('span', 'val ' + (cls || ''), String(v)));
      return d;
    }
  }

  KM.daemons = {
    init: function () {
      var list = $('daemon-list');
      if (list) list.addEventListener('click', onClick);
      var add = $('add-daemon');
      if (add) add.addEventListener('click', function () { KM.add.open(); });
      schedule();
      document.addEventListener('visibilitychange', function () {
        if (!document.hidden && KM.stale('daemons')) pollTick();
      });
    },
    load: load,
    render: render,
    runAction: runAction,
    pollNow: pollTick
  };
  /* QA hook: runs the same guarded tick as the 5 s poller; resolves when done */
  KM.pollNow = pollTick;

  KM.openDelete = openDelete;
})();
