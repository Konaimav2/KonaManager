/* KonaManager UI - Add (install/create/import), Deep Sleep settings */
(function () {
  'use strict';
  var KM = window.KM, S = KM.S;
  var E = KM.E, $ = KM.$, clear = KM.clear, text = KM.text;

  function field(label, input, hint) {
    var f = E('label', 'field');
    f.appendChild(E('span', '', label));
    f.appendChild(input);
    if (hint) f.appendChild(E('span', 'hint', hint));
    return f;
  }
  function input(type, cls, value, placeholder) {
    var i = E('input', cls || '');
    i.type = type || 'text';
    if (value != null) i.value = value;
    if (placeholder) i.placeholder = placeholder;
    i.autocomplete = 'off'; i.spellcheck = false;
    return i;
  }
  function validText(s, max) { return !!s && s.length <= max && !/[\r\n]/.test(s); }
  function summaryRow(dl, k, v) { dl.appendChild(E('dt', '', k)); dl.appendChild(E('dd', '', v == null || v === '' ? '-' : String(v))); }
  function alertBox(msg) { var a = E('div', 'alert'); a.appendChild(E('span', 'code', 'ERROR')); a.appendChild(document.createTextNode(msg)); return a; }

  /* ---------------- Add sheet ---------------- */
  function open() {
    var sh = KM.sheet({ title: 'Add daemon', sub: 'Install a package, create one, or import a service.d script.' });
    var seg = E('div', 'segmented');
    var bInstall = KM.btn('Install', ''), bCreate = KM.btn('Create', ''), bImport = KM.btn('Import', '');
    seg.appendChild(bInstall); seg.appendChild(bCreate); seg.appendChild(bImport);
    var content = E('div');
    var wrap = E('div'); wrap.appendChild(seg); wrap.appendChild(content);
    sh.setBody(wrap);
    sh.setFooter([]);
    var installState = { src: '', pin: '', token: null, committed: false };
    KM.S.modal.onClose = function () {
      if (installState.token && !installState.committed) {
        KM.call(['install', 'abort', installState.token], KM.T.read).catch(function () {});
        installState.token = null;
      }
    };
    var mode = 'install';
    function setMode(m) {
      if (installState.token && !installState.committed) {
        KM.call(['install', 'abort', installState.token], KM.T.read).catch(function () {});
        installState.token = null;
      }
      mode = m;
      [bInstall, bCreate, bImport].forEach(function (b) { b.setAttribute('aria-pressed', 'false'); });
      var b = m === 'install' ? bInstall : m === 'create' ? bCreate : bImport;
      b.setAttribute('aria-pressed', 'true');
      clear(content);
      if (m === 'install') renderInstall(content, sh, installState);
      else if (m === 'create') renderCreate(content, sh);
      else renderImport(content, sh);
    }
    bInstall.addEventListener('click', function () { setMode('install'); });
    bCreate.addEventListener('click', function () { setMode('create'); });
    bImport.addEventListener('click', function () { setMode('import'); });
    setMode('install');
  }

  /* ---------------- Install ---------------- */
  function renderInstall(host, sh, state) {
    state = state || { src: '', pin: '', token: null, committed: false };
    sh.setFooter([]);
    var wrap = E('div');
    var stepper = E('div', 'stepper');
    ['Source', 'Fetch', 'Review', 'Confirm'].forEach(function (s, i) {
      stepper.appendChild(E('span', i === 0 ? 'on' : '', s));
    });
    wrap.appendChild(stepper);
    var src = input('text', 'mono', state.src, 'https://…/daemon.zip or /sdcard/Download/daemon.zip');
    var pin = input('text', 'mono', state.pin, 'optional 64-char sha256');
    wrap.appendChild(field('Source', src));
    wrap.appendChild(field('Pin sha256 (optional)', pin, 'Required when curl is unavailable (busybox wget).'));
    var err = E('div', 'alert'); err.hidden = true; wrap.appendChild(err);
    var stage = KM.btn('Stage package', 'primary', 'plus');
    var status = E('p', 'muted', '');
    wrap.appendChild(stage); wrap.appendChild(status);
    host.appendChild(wrap);
    var busy = false;

    stage.addEventListener('click', function () {
      if (busy) return;
      var s = src.value.trim(), p = pin.value.trim();
      if (!(s.indexOf('https://') === 0 || (s.charAt(0) === '/' && /\.zip$/i.test(s)))) {
        KM.showError(err, { code: 'E_ARG', msg: 'Source must be an https URL or an absolute .zip path.' }); return;
      }
      if (p && !KM.RE.sha.test(p)) {
        KM.showError(err, { code: 'E_ARG', msg: 'Pin must be exactly 64 lowercase hex characters.' }); return;
      }
      if (state.token && !state.committed) {
        KM.call(['install', 'abort', state.token], KM.T.read).catch(function () {});
        state.token = null;
      }
      state.src = s; state.pin = p;
      busy = true; stage.disabled = true; src.disabled = true; pin.disabled = true;
      KM.hideError(err); text(status, 'Staging package…');
      var args = ['install', 'stage', s];
      if (p) args.push(p);
      KM.call(args, KM.T.install).then(function (r) {
        if (r.result) return r.result;
        if (r.state === 'running' && r.job) return pollJob(r.job, status);
        if (r.token) return r;
        throw { code: 'E_NOJSON', msg: 'The install stage returned no package preview.' };
      }).then(function (result) {
        state.result = result; state.token = result.token;
        showReview(host, sh, state, result);
      }).catch(function (e) {
        busy = false; stage.disabled = false; src.disabled = false; pin.disabled = false;
        KM.showError(err, e); text(status, '');
      });
    });
  }

  function pollJob(job, status) {
    return new Promise(function (resolve, reject) {
      var tick = function () {
        KM.call(['job', job], KM.T.read).then(function (r) {
          if (status) text(status, (r.step || 'working') + ' · ' + (r.pct == null ? '…' : r.pct + '%'));
          if (r.state === 'running' || r.state === 'queued') { setTimeout(tick, 1000); return; }
          if (r.state === 'failed') { reject({ code: r.code || 'E_INSTALL', msg: r.msg || 'Install stage failed.' }); return; }
          resolve(r.result || r);
        }).catch(reject);
      };
      tick();
    });
  }

  function showReview(host, sh, state, p) {
    var m = p.manifest || {};
    var wrap = E('div');
    var stepper = E('div', 'stepper');
    ['Source', 'Fetch', 'Review', 'Confirm'].forEach(function (s, i) {
      stepper.appendChild(E('span', i < 2 ? '' : 'on', s));
    });
    wrap.appendChild(stepper);
    if (p.conflict && p.conflict !== 'none') {
      var bad = E('div', 'alert');
      bad.appendChild(E('span', 'code', 'E_CONFLICT'));
      bad.appendChild(document.createTextNode('Id "' + (m.id || '?') + '" is already in use (' + p.conflict + '). Remove it first.'));
      wrap.appendChild(bad);
    }
    var dl = E('dl', 'summary');
    summaryRow(dl, 'id', m.id); summaryRow(dl, 'name', m.name); summaryRow(dl, 'version', m.version);
    summaryRow(dl, 'kind', m.kind); summaryRow(dl, 'start', m.start); summaryRow(dl, 'stop', m.stop);
    summaryRow(dl, 'files', p.files); summaryRow(dl, 'size', KM.fmtBytes(p.bytes)); summaryRow(dl, 'sha256', p.sha256);
    wrap.appendChild(dl);
    (p.warnings || []).forEach(function (w) { wrap.appendChild(E('p', 'warn-list', w)); });
    ['install', 'uninstall'].forEach(function (k) {
      var h = p.hooks && p.hooks[k];
      if (!h) return;
      var box = E('div', 'hook');
      var hd = E('div', 'hook-head');
      hd.appendChild(KM.icon('shield'));
      hd.appendChild(E('span', '', k + ' hook · runs as root · ' + KM.fmtBytes(h.bytes)));
      box.appendChild(hd);
      box.appendChild(E('pre', '', (h.preview || []).join('\n')));
      box.appendChild(E('div', 'note', 'This script runs with full root access. Read it before continuing. sha256 ' + h.sha256));
      wrap.appendChild(box);
    });
    if (!p.hooks || (!p.hooks.install && !p.hooks.uninstall)) wrap.appendChild(E('p', 'muted', 'No hooks in this package.'));

    var err = E('div', 'alert'); err.hidden = true; wrap.appendChild(err);
    var f = E('label', 'field type-confirm');
    f.appendChild(E('span', '', 'Type "' + (m.id || '') + '" to install'));
    var conf = input('text', 'mono', '', m.id || '');
    f.appendChild(conf); wrap.appendChild(f);
    var installBtn = KM.btn('Install', 'primary');
    installBtn.disabled = true;
    conf.addEventListener('input', function () { installBtn.disabled = conf.value !== m.id || (p.conflict && p.conflict !== 'none'); });

    var back = KM.btn('Back', 'ghost');
    back.addEventListener('click', function () { clear(host); renderInstall(host, sh, state); });
    var cancel = KM.btn('Cancel', 'ghost');
    cancel.addEventListener('click', function () { sh.close(); });
    installBtn.addEventListener('click', function () {
      if (installBtn.disabled) return;
      installBtn.disabled = true; back.disabled = true; cancel.disabled = true; conf.disabled = true;
      sh.setBlocking(true); text(err, '');
      KM.call(['install', 'commit', p.token, '--confirm', m.id], KM.T.install).then(function (res) {
        state.committed = true; state.token = null;
        sh.setBlocking(false);
        showInstalled(host, sh, res, m.id);
      }).catch(function (e) {
        sh.setBlocking(false); installBtn.disabled = false; back.disabled = false; cancel.disabled = false; conf.disabled = false;
        KM.showError(err, e);
      });
    });
    sh.setFooter([cancel, back, installBtn]);
    clear(host); host.appendChild(wrap);
    setTimeout(function () { conf.focus(); }, 20);
  }

  function showInstalled(host, sh, res, id) {
    var wrap = E('div');
    wrap.appendChild(E('p', '', 'Installed ' + id + (res.version ? ' v' + res.version : '') + '. It is disabled.'));
    if (res.hook && res.hook.ran) wrap.appendChild(E('p', 'muted', 'Install hook exit ' + res.hook.exit));
    var done = KM.btn('Done', 'primary', 'check');
    done.addEventListener('click', function () { sh.close(); KM.daemons.load(true); });
    var en = KM.btn('Enable', '', 'check');
    en.addEventListener('click', function () {
      en.disabled = true;
      KM.call(['enable', id], KM.T.mut).then(function () { KM.toast(id + ' enabled'); sh.close(); KM.daemons.load(true); })
        .catch(function (e) { en.disabled = false; KM.showError(wrap, e); });
    });
    var start = KM.btn('Start now', '', 'play');
    start.addEventListener('click', function () {
      start.disabled = true;
      KM.call(['start', id], KM.T.mut).then(function () { KM.toast(id + ' started'); sh.close(); KM.daemons.load(true); })
        .catch(function (e) { start.disabled = false; KM.showError(wrap, e); });
    });
    sh.setBody(wrap); sh.setFooter([start, en, done]);
    clear(host);
  }

  /* ---------------- Create ---------------- */
  function renderCreate(host, sh) {
    sh.setFooter([]);
    var wrap = E('div');
    var name = input('text', '', '', 'My daemon');
    var kind = E('select');
    ['daemon', 'oneshot'].forEach(function (k) { var o = E('option', '', k); o.value = k; kind.appendChild(o); });
    var start = input('text', 'mono', '', 'while :; do sleep 60; done');
    var stop = input('text', 'mono', '', 'optional');
    wrap.appendChild(field('Name', name));
    wrap.appendChild(field('Kind', kind));
    wrap.appendChild(field('Start command', start, 'One line, max 1024 characters. Runs with /system/bin/sh.'));
    wrap.appendChild(field('Stop command (optional)', stop, 'Leave empty to stop with TERM then KILL.'));
    var err = E('div', 'alert'); err.hidden = true; wrap.appendChild(err);
    var go = KM.btn('Create', 'primary', 'plus');
    wrap.appendChild(go);
    host.appendChild(wrap);
    go.addEventListener('click', function () {
      var n = name.value.trim(), k = kind.value, st = start.value.trim(), sp = stop.value.trim();
      if (!validText(n, 64)) { KM.showError(err, { code: 'E_ARG', msg: 'Name is required, max 64 characters, one line.' }); return; }
      if (!validText(st, 1024)) { KM.showError(err, { code: 'E_ARG', msg: 'Start command is required, one line, max 1024.' }); return; }
      if (sp && !validText(sp, 1024)) { KM.showError(err, { code: 'E_ARG', msg: 'Stop command must be one line, max 1024.' }); return; }
      var payload = 'name=' + n + '\nkind=' + k + '\nstart=' + st + '\nstop=' + sp + '\n';
      go.disabled = true; KM.hideError(err);
      KM.call(['create', KM.b64utf8(payload)], KM.T.mut).then(function (r) {
        var ok = E('div');
        ok.appendChild(E('p', '', 'Created ' + r.id + ' (disabled).'));
        var done = KM.btn('Done', 'primary', 'check');
        done.addEventListener('click', function () { sh.close(); KM.daemons.load(true); });
        var startNow = KM.btn('Start now', '', 'play');
        startNow.addEventListener('click', function () {
          startNow.disabled = true;
          KM.call(['start', r.id], KM.T.mut).then(function () { KM.toast(r.id + ' started'); sh.close(); KM.daemons.load(true); })
            .catch(function (e) { startNow.disabled = false; KM.showError(ok, e); });
        });
        ok.appendChild(startNow);
        sh.setBody(ok); sh.setFooter([done]);
      }).catch(function (e) { go.disabled = false; KM.showError(err, e); });
    });
  }

  /* ---------------- Import ---------------- */
  function renderImport(host, sh) {
    sh.setFooter([]);
    var wrap = E('div');
    wrap.appendChild(E('p', 'muted', 'Unmanaged scripts in /data/adb/service.d.'));
    var list = E('div');
    var err = E('div', 'alert'); err.hidden = true;
    wrap.appendChild(list); wrap.appendChild(err);
    host.appendChild(wrap);
    function loadList() {
      clear(list); list.appendChild(E('p', 'muted', 'Reading service.d…'));
      KM.call(['import', 'list'], KM.T.read).then(function (r) {
        clear(list);
        var rows = r.candidates || [];
        if (!rows.length) { list.appendChild(E('p', 'muted', 'No scripts found.')); return; }
        rows.forEach(function (c) {
          var row = E('div', 'import-row');
          var meta = E('div', 'meta');
          meta.appendChild(E('div', 'name', c.name));
          meta.appendChild(E('div', 'path', c.path));
          row.appendChild(meta);
          var tags = E('div', 'tags');
          tags.appendChild(KM.chip(c.executable ? 'enabled' : 'disabled', c.executable ? 'src' : ''));
          if (c.managed) tags.appendChild(KM.chip('managed', 'kind'));
          row.appendChild(tags);
          if (c.managed) row.setAttribute('aria-disabled', 'true');
          else { row.tabIndex = 0; row.addEventListener('click', function () { importForm(c); }); }
          list.appendChild(row);
        });
      }).catch(function (e) { clear(list); KM.showError(err, e); });
    }
    function importForm(c) {
      var form = E('div');
      form.appendChild(E('h3', '', 'Import ' + c.name));
      var name = input('text', '', c.name.replace(/\.sh$/, ''));
      var kind = E('select'); ['daemon', 'oneshot'].forEach(function (k) { var o = E('option', '', k); o.value = k; kind.appendChild(o); });
      var stop = input('text', 'mono', '', 'optional stop command');
      form.appendChild(field('Name', name));
      form.appendChild(field('Kind', kind));
      form.appendChild(field('Stop command (optional)', stop));
      form.appendChild(E('p', 'muted', 'The script is not moved or edited. Import only records it.'));
      var back = KM.btn('Back', 'ghost');
      var go = KM.btn('Import', 'primary');
      form.appendChild(back); form.appendChild(go);
      clear(wrap); wrap.appendChild(form);
      back.addEventListener('click', function () { clear(wrap); var w = E('div'); w.appendChild(E('p', 'muted', 'Unmanaged scripts in /data/adb/service.d.')); wrap.appendChild(w); });
      go.addEventListener('click', function () {
        var n = name.value.trim(), sp = stop.value.trim();
        if (!validText(n, 64)) { KM.showError(err, { code: 'E_ARG', msg: 'Name is required.' }); return; }
        var payload = 'name=' + n + '\nkind=' + kind.value + '\nstop=' + sp + '\n';
        go.disabled = true;
        KM.call(['import', c.path, KM.b64utf8(payload)], KM.T.mut).then(function (r) {
          var ok = E('div');
          ok.appendChild(E('p', '', 'Imported ' + r.id + (r.enabled ? ' (enabled)' : ' (disabled)') + '.'));
          ok.appendChild(E('p', 'muted', 'The script was not moved or edited.'));
          var done = KM.btn('Done', 'primary', 'check');
          done.addEventListener('click', function () { sh.close(); KM.daemons.load(true); });
          sh.setBody(ok); sh.setFooter([done]);
        }).catch(function (e) { go.disabled = false; KM.showError(err, e); });
      });
    }
    loadList();
  }

  /* ---------------- Deep Sleep settings ---------------- */
  function openSettings() {
    var sh = KM.sheet({ title: 'Deep Sleep Cool', sub: 'Freeze background apps when the screen is off.' });
    var body = E('div'); body.appendChild(E('p', 'muted', 'Loading…'));
    sh.setBody(body);
    Promise.all([KM.call(['getconf'], KM.T.read), KM.call(['packages'], KM.T.read)]).then(function (res) {
      var c = res[0], pkgs = res[1] || [];
      clear(body);
      var swRow = E('div', 'switch-row');
      swRow.appendChild(E('span', 'switch-label', 'Freeze while unplugged'));
      var sw = E('button', 'switch'); sw.type = 'button'; sw.setAttribute('role', 'switch');
      sw.setAttribute('aria-checked', c.freeze_unplugged ? 'true' : 'false');
      sw.addEventListener('click', function () {
        var next = c.freeze_unplugged ? 0 : 1;
        sw.disabled = true;
        KM.call(['setconf', 'freeze_unplugged', String(next)], KM.T.mut).then(function () { KM.toast('Saved'); openSettings(); })
          .catch(function (e) { sw.disabled = false; KM.showError(body, e); });
      });
      swRow.appendChild(sw); body.appendChild(swRow);
      body.appendChild(E('p', 'muted', 'When off, apps are only frozen while charging with the screen off.'));
      body.appendChild(E('h4', '', 'Never freeze'));
      var chips = E('div', 'never-list');
      (c.whitelist || []).forEach(function (p) {
        var chip = E('span', 'never-chip');
        chip.appendChild(E('span', '', p));
        var x = E('button'); x.type = 'button'; x.setAttribute('aria-label', 'Remove ' + p);
        x.appendChild(KM.icon('x'));
        x.addEventListener('click', function () {
          KM.call(['whitelist', 'rm', p], KM.T.mut).then(function () { openSettings(); }).catch(function (e) { KM.showError(body, e); });
        });
        chip.appendChild(x); chips.appendChild(chip);
      });
      if (!(c.whitelist || []).length) chips.appendChild(E('span', 'muted', 'No entries.'));
      body.appendChild(chips);
      var add = E('div', 'run-actions');
      var inp = input('text', 'search', '', 'com.example.app');
      inp.setAttribute('list', 'ds-pkgs');
      var dl = E('datalist'); dl.id = 'ds-pkgs';
      pkgs.forEach(function (p) { var o = E('option'); o.value = p; dl.appendChild(o); });
      var b = KM.btn('Add', 'small');
      b.addEventListener('click', function () {
        var p = inp.value.trim();
        if (!KM.RE.pkg.test(p)) { KM.toast('Invalid package.', true); return; }
        KM.call(['whitelist', 'add', p], KM.T.mut).then(function () { openSettings(); }).catch(function (e) { KM.showError(body, e); });
      });
      add.appendChild(inp); add.appendChild(b); add.appendChild(dl);
      body.appendChild(add);
      body.appendChild(E('p', 'muted', 'System apps are never targeted. Apps playing media are skipped automatically.'));
      var done = KM.btn('Done', 'primary', 'check');
      done.addEventListener('click', function () { sh.close(); KM.daemons.load(true); });
      sh.setFooter([done]);
    }).catch(function (e) { clear(body); KM.showError(body, e); });
  }

  KM.add = { open: open };
  KM.settings = { open: openSettings };
})();
