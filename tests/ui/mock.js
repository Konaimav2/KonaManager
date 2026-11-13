/* KonaManager UI QA mock - injected as window.ksu before app scripts. */
(() => {
  const st = __STATE__;
  window.__cmds = [];
  window.__mockState = st;
  st.faults = st.faults || {};
  st.delays = st.delays || {};
  st.failOn = st.failOn || {};
  window.__cmdT = [];
  st.logGrow = !!st.logGrow;
  st.logN = st.logN || 0;
  st.conf = st.conf || { freeze_unplugged: true, whitelist: ['com.a', 'com.b'] };

  function counts() {
    let u0 = 0, u999 = 0;
    st.targets.forEach(t => { if (t.u0) u0++; if (t.u999) u999++; });
    return { targets: st.targets.length, u0, u999, never: st.never.length };
  }
  function target(p) { return st.targets.find(t => t.pkg === p); }
  function daemon(id) { return st.daemons.find(d => d.id === id); }
  function sync(d) {
    d.running = !!d.running;
    d.state = d.running ? 'running' : (d.state === 'failed' ? 'failed' : 'stopped');
    d.pid = d.running ? (d.pid || 20000 + Math.floor(Math.random() * 2000)) : null;
    d.pids = d.pid ? [d.pid] : [];
    d.uptime_s = d.running ? (d.uptime_s || 42) : null;
    d.enabled = !!d.enabled;
    d.verified_by = d.running ? 'marker' : 'none';
    d.health = d.running ? 'ok' : 'na';
    d.removable = d.removable !== false;
    return d;
  }
  function ok(o) { return { errno: 0, stdout: JSON.stringify(o), stderr: '' }; }
  function fail(code, msg) { return { errno: 1, stdout: JSON.stringify({ ok: false, code, msg }), stderr: '' }; }
  function tokenize(s) {
    const out = []; const re = /'([^']*)'|(\S+)/g; let m;
    while ((m = re.exec(s))) out.push(m[1] !== undefined ? m[1].replace(/'\\''/g, "'") : m[2]);
    return out;
  }
  function slug(s) {
    s = String(s).toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
    return s.length >= 2 ? s.slice(0, 30) : 'daemon-x';
  }
  function appguard() {
    const d = sync(daemon('appguard'));
    return {
      ok: true, config: st.config, never: st.never.slice(),
      targets: st.targets.map(t => Object.assign({ shadowed: st.never.indexOf(t.pkg) >= 0 }, t)),
      counts: counts(), daemon: d, running_version: '2.0.0', installed_version: '2.0.0'
    };
  }

  function handle(cmd) {
    const a = tokenize(cmd); a.shift();
    const c = a[0];
    if (c === 'list') {
      const ds = st.daemons.map(sync);
      /* fault switch: a daemon whose pids.join is not a function makes card() throw */
      if (st.faults.list === 'poison') ds.push({ id: 'zz-bad', name: 'Bad', pids: { length: 1 }, running: true });
      return ok({ ok: true, dm: '2.0.0', schema: 2, ts: Math.floor(Date.now() / 1000), daemons: ds });
    }
    if (c === 'getconf') return ok({ ok: true, freeze_unplugged: !!st.conf.freeze_unplugged, whitelist: st.conf.whitelist.slice() });
    if (c === 'setconf') {
      if (a[1] !== 'freeze_unplugged') return fail('E_ARG', 'unknown setting');
      st.conf.freeze_unplugged = a[2] === '1';
      return ok({ ok: true, msg: 'saved' });
    }
    if (c === 'whitelist') {
      if (a[1] === 'add') { if (st.conf.whitelist.indexOf(a[2]) < 0) st.conf.whitelist.push(a[2]); return ok({ ok: true, msg: 'added' }); }
      if (a[1] === 'rm') { st.conf.whitelist = st.conf.whitelist.filter(x => x !== a[2]); return ok({ ok: true, msg: 'removed' }); }
      return ok({ ok: true, freeze_unplugged: !!st.conf.freeze_unplugged, whitelist: st.conf.whitelist.slice() });
    }
    if (c === 'packages') {
      const pk = (st.packages['0'] || []).slice();
      /* faults.packages='array' = DIAGNOSTIC non-contract shape (bare array); default is the real dm shape {ok,packages} (tests/run.sh:333-335) */
      if (st.faults.packages === 'array') return { errno: 0, stdout: JSON.stringify(pk), stderr: '' };
      return ok({ ok: true, packages: pk });
    }
    if (c === 'version') return ok({ ok: true, version: '2.0.0', schema: 2 });
    if (c === 'doctor') return ok({ ok: true, root: true, tools: { curl: null, unzip: '/data/adb/ksu/bin/busybox unzip', sha256sum: '/data/adb/ksu/bin/busybox sha256sum', base64: '/data/adb/ksu/bin/busybox base64', pm: '/system/bin/pm' }, selinux: 'Enforcing', writable: true, busybox: '/data/adb/ksu/bin/busybox' });
    if (c === 'status') {
      const d = daemon(a[1]); if (!d) return fail('E_UNKNOWN', 'unknown daemon');
      return ok({ ok: true, daemon: sync(d), meta: { start: d.id === 'appguard' ? '/data/adb/appguard/appguard.sh run' : 'start.sh', stop_scope: 'marker', boot: d.boot, version: d.version }, exit_code: null, log_tail: ['mock log line', 'second line'] });
    }
    if (c === 'start' || c === 'stop' || c === 'restart') {
      const d = daemon(a[1]); if (!d) return fail('E_UNKNOWN', 'unknown daemon');
      if (c === 'stop') { d.running = false; }
      else { d.running = true; d.uptime_s = 0; }
      sync(d);
      return ok({ ok: true, id: d.id, action: c, state: d.running ? 'running' : 'stopped', pid: d.pid, pids: d.pids, uptime_s: d.uptime_s, waited_ms: 120, already: false, msg: c + ' ok' });
    }
    if (c === 'enable' || c === 'disable') {
      const d = daemon(a[1]); if (!d) return fail('E_UNKNOWN', 'unknown daemon');
      d.enabled = c === 'enable';
      if (c === 'disable' && a.indexOf('--keep-running') < 0) d.running = false;
      sync(d);
      return ok({ ok: true, id: d.id, enabled: d.enabled, boot: d.boot, stopped: c === 'disable' && !d.running, msg: c + ' ok' });
    }
    if (c === 'logs') {
      /* n numbered lines; with st.logGrow every call appends one more line (tail window slides) */
      const n = Math.max(1, parseInt(a[2], 10) || 100);
      if (st.logGrow) st.logN++;
      const lines = [];
      for (let i = 1; i <= n; i++) lines.push('mock log line ' + (st.logN + i));
      return ok({ ok: true, source: a[1], lines: lines, truncated: false });
    }
    if (c === 'appguard') {
      const sub = a[1];
      if (sub === 'get') return ok(appguard());
      if (sub === 'set') {
        const k = a[2], v = Number(a[3]);
        if (k === 'interval') st.config.interval_s = v;
        if (k === 'cooldown') st.config.cooldown_s = v;
        if (k === 'dry') st.config.dry_run = !!v;
        return ok({ ok: true, key: k, value: v, msg: 'saved' });
      }
      if (sub === 'targets') {
        const op = a[2], p = a[3];
        if (op === 'set') {
          let t = target(p); if (!t) return fail('E_UNKNOWN', 'unknown target');
          a.slice(4).forEach(kv => { const i = kv.indexOf('='); const k = kv.slice(0, i), v = kv.slice(i + 1); if (k === 'u0') t.u0 = v === '1'; else if (k === 'u999') t.u999 = v === '1'; else if (k === 'cooldown') t.cooldown_s = v === 'default' ? null : Number(v); });
          return ok({ ok: true, pkg: t.pkg, u0: t.u0, u999: t.u999, cooldown_s: t.cooldown_s });
        }
        if (op === 'add') {
          let t = target(p);
          /* backend parity (km-appguard.sh:191): add on an existing target is a conflict */
          if (t) return fail('E_CONFLICT', 'already a target');
          t = { pkg: p, u0: false, u999: false, cooldown_s: null }; st.targets.push(t);
          a.slice(4).forEach(kv => { const i = kv.indexOf('='); const k = kv.slice(0, i), v = kv.slice(i + 1); if (k === 'u0') t.u0 = v === '1'; else if (k === 'u999') t.u999 = v === '1'; else if (k === 'cooldown') t.cooldown_s = v === 'default' ? null : Number(v); });
          return ok({ ok: true, pkg: t.pkg, u0: t.u0, u999: t.u999, cooldown_s: t.cooldown_s });
        }
        if (op === 'rm') { st.targets = st.targets.filter(t => t.pkg !== p); return ok({ ok: true, pkg: p, u0: false, u999: false, cooldown_s: null }); }
        return fail('E_USAGE', 'targets op');
      }
      if (sub === 'never') {
        const op = a[2], p = a[3];
        if (op === 'add') { if (st.never.indexOf(p) < 0) st.never.push(p); return ok({ ok: true, never: st.never.slice() }); }
        if (op === 'rm') { st.never = st.never.filter(x => x !== p); return ok({ ok: true, never: st.never.slice() }); }
        if (op === 'list') return ok({ ok: true, never: st.never.slice() });
      }
      if (sub === 'packages') {
        const ui = a.indexOf('--user'); const user = ui >= 0 ? a[ui + 1] : '0';
        const qi = a.indexOf('--q'); const q = qi >= 0 ? a[qi + 1].toLowerCase() : '';
        const list = (st.packages[user] || []).filter(p => !q || p.toLowerCase().indexOf(q) >= 0).map(p => ({ pkg: p, target: !!target(p), never: st.never.indexOf(p) >= 0 }));
        return ok({ ok: true, user: Number(user), packages: list });
      }
      if (sub === 'kills') return ok({ ok: true, total: st.kills.length, kills: st.kills });
      if (sub === 'once') {
        const dry = a.indexOf('--dry') >= 0;
        return ok({ ok: true, dry: dry, sweep: { skipped: null, candidates: 2, killed: dry ? 0 : 1, would_kill: [{ user: 0, pkg: 'com.demo.idle' }], skipped_fg: [], skipped_cooldown: 0 }, ms: 42 });
      }
    }
    if (c === 'install') {
      const sub = a[1];
      if (sub === 'stage') {
        return ok({ ok: true, job: 'j_demo', state: 'done', step: 'validate', pct: 100, result: { token: 't_demo', manifest: { id: 'km-demo', name: 'Demo Package', version: '1.0.0', kind: 'daemon', desc: 'QA fixture package', start: 'start.sh', stop: '' }, hooks: { install: { sha256: 'a'.repeat(64), bytes: 120, preview: ['#!/bin/sh', 'echo installed', 'exit 0'] }, uninstall: null }, files: 3, bytes: 2048, sha256: 'b'.repeat(64), conflict: 'none', warnings: [] } });
      }
      if (sub === 'commit') {
        if (!daemon('km-demo')) { st.daemons.push({ id: 'km-demo', name: 'Demo Package', desc: 'QA fixture package', version: '1.0.0', kind: 'daemon', source: 'package', enabled: false, boot: 'wrapper', removable: true, running: false }); }
        return ok({ ok: true, id: 'km-demo', version: '1.0.0', hook: { ran: true, exit: 0 }, enabled: false });
      }
      if (sub === 'abort') return ok({ ok: true });
    }
    if (c === 'job') return ok({ ok: true, job: a[1], state: 'done', step: 'validate', pct: 100, result: { token: 't_demo', manifest: { id: 'km-demo' } } });
    if (c === 'create') {
      let name = 'created';
      try { name = atob(a[1]).split('\n').filter(x => x.indexOf('name=') === 0)[0].slice(5); } catch (e) {}
      const id = 'km-' + slug(name);
      if (!daemon(id)) st.daemons.push({ id, name: name, desc: 'created by UI', version: '', kind: 'daemon', source: 'created', enabled: false, boot: 'wrapper', removable: true, running: false });
      return ok({ ok: true, id, dir: '/data/adb/daemon-manager/daemons/' + id, enabled: false });
    }
    if (c === 'import') {
      if (a[1] === 'list') return ok({ ok: true, candidates: [{ path: '/data/adb/service.d/dev-extra.sh', name: 'dev-extra.sh', executable: true, managed: false, bytes: 88 }] });
      const id = 'km-dev-import';
      if (!daemon(id)) st.daemons.push({ id, name: 'Dev Extra', desc: 'imported service.d script', version: '', kind: 'daemon', source: 'imported', enabled: true, boot: 'xbit', removable: false, running: false });
      return ok({ ok: true, id, script: a[1], enabled: true, source: 'imported' });
    }
    if (c === 'delete') {
      const id = a[1], mode = a[2];
      if (mode === '--plan') return ok({ ok: true, plan: { stop: false, remove_dir: '/data/adb/daemon-manager/daemons/' + id, remove_wrapper: '/data/adb/service.d/km-' + id + '.sh', run_uninstall_hook: false, keeps: ['deep-sleep-cool.conf and every other file outside the daemon folder'] } });
      if (mode === '--confirm') {
        st.daemons = st.daemons.filter(d => d.id !== id);
        return ok({ ok: true, id, stopped: false, hook: { ran: false, exit: null }, removed: ['/data/adb/daemon-manager/daemons/' + id, '/data/adb/service.d/km-' + id + '.sh'], unmanaged: false });
      }
    }
    if (c === 'rollback') return ok({ ok: true, restored: 'v1.0' });
    return fail('E_UNKNOWN', 'mock: ' + cmd);
  }

  window.ksu = {
    exec: function (cmd, cb) {
      window.__cmds.push(cmd); window.__cmdT.push(performance.now());
      /* hooks: st.delays {substr: ms} slows matching cmds, st.failOn {substr: code} fails them */
      let ms = 15; for (const k in st.delays) if (cmd.indexOf(k) >= 0) ms = Math.max(ms, st.delays[k]);
      let code = null; for (const k in st.failOn) if (cmd.indexOf(k) >= 0) code = st.failOn[k];
      function run() {
        try { return code ? fail(code, 'mock fault ' + code) : handle(cmd); }
        catch (e) { return { errno: 1, stdout: '', stderr: String(e) }; }
      }
      /* delayed cmds are answered from state AT REQUEST TIME (a real backend reads state when it runs) */
      const pre = ms > 15 ? run() : null;
      setTimeout(function () {
        const r = pre || run();
        window[cb](r.errno, r.stdout, r.stderr);
      }, ms);
    }
  };
})();
