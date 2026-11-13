#!/usr/bin/env python3
"""KonaManager WebUI QA: stateful KSUser bridge mock, AppGuard sheet flow, poll/scroll/stress
checks, error boundary, ten viewports, backend gate.

Run from repo/:  KM_EVID=tests/evidence/ui-night KM_QA_PORT=8199 python3 tests/ui/qa.py
Every check is recorded with its measured detail in <KM_EVID>/report.json and SUMMARY.md.
"""
import functools
import http.server
import json
import os
import re
import subprocess
import sys
import threading
import time
from pathlib import Path

from playwright.sync_api import sync_playwright

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
ROOT = Path(os.environ.get('KM_WEBROOT', REPO / 'module' / 'webroot'))
EVID = Path(os.environ.get('KM_EVID', REPO / 'tests' / 'evidence' / 'ui'))
MOCK = (HERE / 'mock.js').read_text()
PORT = int(os.environ.get('KM_QA_PORT', '8099'))
BASE = f'http://127.0.0.1:{PORT}/index.html'
BACKEND_OUT = os.environ.get('KM_BACKEND_OUT', '/root/temp/konamanager-night/tmp/night-backend.txt')
BACKEND_BASE = os.environ.get('KM_BACKEND_BASE', '/root/temp/konamanager-night/tmp/baseline-failed.txt')
BACKEND_MIN = int(os.environ.get('KM_BACKEND_MIN', '596'))

TARGETS = []
for i in range(29):
    TARGETS.append({'pkg': f'com.demo.app{i:02d}', 'u0': True, 'u999': False, 'cooldown_s': None})
TARGETS.append({'pkg': 'com.example.carrier', 'u0': True, 'u999': False, 'cooldown_s': 600})
for p in ('com.whatsapp', 'com.discord', 'id.dana'):
    TARGETS.append({'pkg': p, 'u0': False, 'u999': True, 'cooldown_s': None})

NEVER = ['com.whatsapp', 'com.whatsapp.w4b', 'com.discord', 'com.termux', 'com.termux.api', 'com.kanagawa.yamada.project.raco']

DAEMONS = [
    {'id': 'appguard', 'name': 'AppGuard', 'desc': 'Kills idle background apps to keep memory free', 'version': '2.0.0', 'kind': 'daemon', 'source': 'builtin', 'enabled': True, 'boot': 'xbit', 'removable': False, 'running': True, 'pid': 17741, 'pids': [17741], 'uptime_s': 3612, 'state': 'running', 'health': 'ok', 'health_detail': '', 'verified_by': 'marker', 'last': None},
    {'id': 'deep-sleep-cool', 'name': 'Deep Sleep Cool', 'desc': 'Freezes background apps when the screen is off', 'version': '2.0.0', 'kind': 'daemon', 'source': 'builtin', 'enabled': True, 'boot': 'xbit', 'removable': False, 'running': True, 'pid': 8033, 'pids': [8033], 'uptime_s': 7200, 'state': 'running', 'health': 'ok', 'health_detail': '', 'verified_by': 'marker', 'last': None},
    {'id': 'root-sshd', 'name': 'Root SSH (port 22)', 'desc': 'Key-only root sshd on port 22 while root is up', 'version': '2.0.0', 'kind': 'daemon', 'source': 'builtin', 'enabled': True, 'boot': 'xbit', 'removable': False, 'running': True, 'pid': 23448, 'pids': [23448], 'uptime_s': 8400, 'state': 'running', 'health': 'ok', 'health_detail': '', 'verified_by': 'pidfile+argv', 'last': None},
    {'id': 'sim-monitor', 'name': 'SIM Monitor', 'desc': 'Watches SIM and mobile-data state', 'version': '2.0.0', 'kind': 'daemon', 'source': 'builtin', 'enabled': True, 'boot': 'xbit', 'removable': False, 'running': False, 'pid': None, 'pids': [], 'uptime_s': None, 'state': 'stopped', 'health': 'na', 'health_detail': '', 'verified_by': 'none', 'last': None},
    {'id': 'wifi-ps-guard', 'name': 'Wi-Fi Power Save Guard', 'desc': 'Keeps Wi-Fi power save disabled while an SSH session is active', 'version': '2.0.0', 'kind': 'daemon', 'source': 'builtin', 'enabled': False, 'boot': 'xbit', 'removable': False, 'running': False, 'pid': None, 'pids': [], 'uptime_s': None, 'state': 'stopped', 'health': 'na', 'health_detail': '', 'verified_by': 'none', 'last': None},
    {'id': 'wifi-tune', 'name': 'Wi-Fi TCP Tune', 'desc': 'Applies TCP keepalive sysctls and power save off at boot', 'version': '2.0.0', 'kind': 'oneshot', 'source': 'builtin', 'enabled': False, 'boot': 'xbit', 'removable': False, 'running': False, 'pid': None, 'pids': [], 'uptime_s': None, 'state': 'stopped', 'health': 'na', 'health_detail': '', 'verified_by': 'none', 'last': None},
]

NOW = int(time.time())
KILLS = [
    {'ts': NOW - 90, 'user': 0, 'pkg': 'com.demo.app01', 'mode': 'kill', 'result': 'ok', 'cooldown_s': 300, 'reason': 'idle'},
    {'ts': NOW - 600, 'user': 0, 'pkg': 'com.demo.app02', 'mode': 'dry', 'result': 'ok', 'cooldown_s': 300, 'reason': 'dry-run'},
    {'ts': NOW - 1800, 'user': 999, 'pkg': 'id.dana', 'mode': 'kill', 'result': 'fail', 'cooldown_s': 600, 'reason': 'am-refused'},
]

STATE = {
    'daemons': DAEMONS,
    'config': {'interval_s': 60, 'cooldown_s': 300, 'dry_run': False},
    'never': NEVER,
    'targets': TARGETS,
    'kills': KILLS,
    'packages': {
        '0': [t['pkg'] for t in TARGETS] + ['com.demo.extra', 'com.demo.ghost'],
        '999': ['com.whatsapp', 'com.discord', 'com.whatsapp.w4b'],
    },
}

VIEWPORTS = [
    (360, 640, 'phone'), (390, 844, 'phone'), (414, 896, 'phone'),
    (768, 1024, 'tablet'), (820, 1180, 'tablet'), (1024, 1366, 'desktop'),
    (1280, 800, 'desktop'), (1440, 900, 'desktop'), (1920, 1080, 'desktop'),
    (1080, 1080, 'desktop'),
]

# horizontal edge crossing; elements inside an overflow-x auto/scroll strip are intentional scrolls
EDGE_JS = """(sel) => {
  const iw = window.innerWidth;
  const root = sel ? document.querySelector(sel) : document.body;
  if (!root) return {n: -1, list: ['root missing: ' + sel]};
  const els = [root].concat(Array.from(root.querySelectorAll('*')));
  const out = [];
  for (const el of els) {
    if (el.closest('svg') && el.tagName.toLowerCase() !== 'svg') continue;
    const cs = getComputedStyle(el);
    if (cs.display === 'none' || cs.visibility === 'hidden') continue;
    const r = el.getBoundingClientRect();
    if (r.width === 0 && r.height === 0) continue;
    if (el.matches('a.skip') && document.activeElement !== el) continue; /* skip link: parked at left:-999px until focused (intentional) */
    let strip = false;
    for (let p = el.parentElement; p && p !== document.body && p !== document.documentElement; p = p.parentElement) {
      if (/(auto|scroll)/.test(getComputedStyle(p).overflowX)) { strip = true; break; }
    }
    if (strip) continue;
    if (r.left < -1 || r.right > iw + 1) {
      out.push(el.tagName.toLowerCase() + (el.id ? '#' + el.id : '') + (el.className && typeof el.className === 'string' ? '.' + el.className.trim().split(/\\s+/).join('.') : '') + ' [' + Math.round(r.left) + ',' + Math.round(r.right) + ']');
    }
  }
  return {n: out.length, list: out.slice(0, 12)};
}"""

# every visible control inside .ag-sheet must be >= 44x44 (or sit inside a .hit ancestor that is)
HIT_JS = """() => {
  const sheet = document.querySelector('.ag-sheet');
  if (!sheet) return {n: -1, total: 0, bad: ['no .ag-sheet']};
  const els = Array.from(sheet.querySelectorAll('button, input, select, [role=switch]'));
  const bad = []; let total = 0;
  els.forEach(e => {
    const r = e.getBoundingClientRect();
    if (r.width === 0 || r.height === 0 || getComputedStyle(e).visibility === 'hidden') return;
    total++;
    let w = r.width, h = r.height;
    const hit = e.closest('.hit');
    if (hit) { const hr = hit.getBoundingClientRect(); w = Math.max(w, hr.width); h = Math.max(h, hr.height); }
    if (w < 43.5 || h < 43.5) bad.push((e.getAttribute('aria-label') || e.innerText || e.className || e.tagName).toString().slice(0, 28) + ' ' + w.toFixed(1) + 'x' + h.toFixed(1));
  });
  return {n: bad.length, total: total, bad: bad.slice(0, 12)};
}"""

FOCUSABLE_JS = """() => {
  const panel = document.querySelector('#modal-root .modal-panel');
  const q = 'a[href], button, input, select, textarea, [tabindex]';
  return Array.from(panel.querySelectorAll(q)).filter(e => !e.disabled && e.tabIndex >= 0 && e.getClientRects().length > 0 && getComputedStyle(e).visibility !== 'hidden');
}"""

BURST_JS = """() => {
  const order = ['logs', 'about', 'daemons'];
  const empty = [];
  const content = {
    daemons: () => document.getElementById('daemon-list').children.length > 0,
    logs: () => document.getElementById('log-output').textContent.trim().length > 0,
    about: () => ['about-identity', 'about-doctor', 'about-maint'].every(id => document.getElementById(id).children.length > 0)
  };
  let checked = 0;
  for (let i = 1; i <= 100; i++) {
    const t = order[(i - 1) % 3];
    document.getElementById('tab-' + t).click();
    if (i % 10 === 0) {
      checked++;
      const panel = document.querySelector('.panel:not([hidden])');
      const txt = panel.innerText.trim();
      if (!txt || panel.id !== 'panel-' + t || !content[t]()) empty.push({i: i, tab: t, panel: panel.id, len: txt.length, content: content[t]()});
    }
  }
  return {checked: checked, empty: empty};
}"""


def waitfn(pg, expr, timeout=3000):
    """Poll a JS expression with evaluate(); page.wait_for_function eval()s the predicate, which the app CSP blocks."""
    end = time.time() + timeout / 1000.0
    while True:
        try:
            if pg.evaluate(expr):
                return True
        except Exception as e:
            if 'Execution context' not in str(e) and 'navigat' not in str(e):
                raise
        if time.time() > end:
            raise TimeoutError('waitfn timeout: ' + expr[:140])
        time.sleep(0.05)


class Quiet(http.server.SimpleHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass


def list_calls(cmds):
    return sum(1 for c in cmds if "'list'" in c)


def backend_gate():
    """Parse the finished backend run: >= BACKEND_MIN passed and failure-name set == baseline."""
    res = {}
    try:
        txt = Path(BACKEND_OUT).read_text()
    except Exception as e:
        return {'ok': False, 'detail': f'backend output missing: {e}'}
    m = re.search(r'^TOTAL: (\d+) passed, (\d+) failed', txt, re.M)
    if not m:
        return {'ok': False, 'detail': 'no TOTAL line (run incomplete?)'}
    passed, failed = int(m.group(1)), int(m.group(2))
    fl = [ln for ln in txt.splitlines() if ln.startswith('failed:')]
    names = set()
    if fl:
        names = {x.strip() for x in fl[-1][len('failed:'):].split('|') if x.strip()}
    try:
        base = {x.strip() for x in Path(BACKEND_BASE).read_text().splitlines() if x.strip()}
    except Exception as e:
        return {'ok': False, 'detail': f'baseline missing: {e}'}
    extra, missing = sorted(names - base), sorted(base - names)
    res['total'] = m.group(0)
    res['passed'], res['failed'] = passed, failed
    res['new_failures'], res['fixed_since_baseline'] = extra, missing
    res['ok'] = passed >= BACKEND_MIN and not extra and not missing and len(names) == failed
    res['detail'] = f"{m.group(0)}; failed names {len(names)}; new={extra}; fixed={missing}; gate>={BACKEND_MIN}"
    return res


def main():
    EVID.mkdir(parents=True, exist_ok=True)
    handler = functools.partial(Quiet, directory=str(ROOT))
    httpd = http.server.ThreadingHTTPServer(('127.0.0.1', PORT), handler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()

    results = []
    console_errors, page_errors, console_warns = [], [], []
    vp_rows, extra_info = [], {}
    sect = {'name': 'init'}
    mock_js = MOCK.replace('__STATE__', json.dumps(STATE, ensure_ascii=False))

    def check(name, cond, detail=''):
        results.append({'name': name, 'ok': bool(cond), 'detail': detail, 'section': sect['name']})
        d = str(detail)
        print(('PASS ' if cond else 'FAIL ') + name + ((' :: ' + d[:300]) if d else ''), flush=True)
        return bool(cond)

    with sync_playwright() as p:
        browser = None
        last = None
        for exe in (None, '/snap/bin/chromium'):
            try:
                kw = {'headless': True, 'args': ['--no-sandbox', '--disable-dev-shm-usage']}
                if exe:
                    kw['executable_path'] = exe
                browser = p.chromium.launch(**kw)
                break
            except Exception as e:
                last = e
        if not browser:
            print('browser launch failed:', last)
            return 1

        state = {'ctx': None, 'page': None}

        def fresh(w, h, section, url=None, wait_cards=True, pre_js=None):
            """New context + page with the mock injected; one browser alive at a time."""
            sect['name'] = section
            if state['ctx']:
                try:
                    state['ctx'].close()
                except Exception:
                    pass
            ctx = browser.new_context(viewport={'width': w, 'height': h})
            pg = ctx.new_page()
            pg.on('console', lambda m: console_errors.append(f'[{sect["name"]}] {m.text}') if m.type == 'error' else (console_warns.append(f'[{sect["name"]}] {m.text}') if m.type == 'warning' else None))
            pg.on('pageerror', lambda e: page_errors.append(f'[{sect["name"]}] {e}'))
            pg.add_init_script(mock_js)
            if pre_js:
                pg.add_init_script(pre_js)  # runs after the mock: lets a section set delays before the first list
            pg.goto(url or BASE, wait_until='load')
            if wait_cards:
                pg.wait_for_selector('#daemon-list .card', timeout=5000)
            state['ctx'], state['page'] = ctx, pg
            return pg

        def cmds(pg):
            return pg.evaluate('window.__cmds')

        def errs_now():
            return len(console_errors), len(page_errors)

        # ---------------------------------------------------------------- legacy shell + install/create/import
        pg = fresh(1280, 800, 'legacy')
        check('brand title', 'KonaManager' in pg.title(), pg.title())
        n = pg.locator('#daemon-list .card').count()
        check('daemon cards rendered', n >= 6, n)
        check('connection chip ready', (pg.locator('#conn-chip').inner_text() or '').strip() == 'ready')
        check('no horizontal overflow (desktop)', pg.evaluate('document.documentElement.scrollWidth - window.innerWidth') == 0)

        pg.click('#add-daemon')
        pg.wait_for_selector('#modal-root .modal-panel')
        pg.locator('#modal-root .modal-body input.mono').nth(0).fill('https://example.com/demo.zip')
        pg.locator('#modal-root .modal-body button', has_text='Stage package').click()
        pg.wait_for_selector('#modal-root .modal-body .summary', timeout=5000)
        check('install review shows hook', 'runs as root' in pg.locator('#modal-root .modal-body').inner_text())
        pg.locator('#modal-root .modal-body .type-confirm input').fill('km-demo')
        pg.locator('#modal-root .modal-foot button', has_text='Install').click()
        pg.wait_for_selector('text=Installed km-demo', timeout=5000)
        check('install commit completed', any("'install'" in c and "'commit'" in c for c in cmds(pg)))
        pg.locator('#modal-root .modal-foot button', has_text='Done').click()
        pg.wait_for_selector('#daemon-list .card[data-id="km-demo"]', timeout=3000)
        check('installed daemon card appears', pg.locator('#daemon-list .card[data-id="km-demo"]').count() == 1)

        pg.locator('#daemon-list .card[data-id="km-demo"] [data-act="delete"]').click()
        pg.wait_for_selector('#modal-root .type-confirm input', timeout=5000)
        check('delete plan shown', 'Removes' in pg.locator('#modal-root .modal-body').inner_text())
        pg.locator('#modal-root .modal-head .icon-btn').click()
        pg.wait_for_timeout(200)

        pg.click('#add-daemon')
        pg.locator('#modal-root .segmented button', has_text='Create').click()
        pg.wait_for_selector('#modal-root .modal-body input')
        pg.locator('#modal-root .modal-body input').nth(0).fill('QA Created')
        pg.locator('#modal-root .modal-body input.mono').nth(0).fill('while :; do sleep 1; done')
        pg.locator('#modal-root .modal-body button.btn.primary').click()
        pg.wait_for_selector('text=Created km-qa-created', timeout=5000)
        check('create flow completed', 'create' in ' '.join(cmds(pg)))
        pg.locator('#modal-root .modal-foot button', has_text='Done').click()

        pg.click('#add-daemon')
        pg.locator('#modal-root .segmented button', has_text='Import').click()
        pg.wait_for_selector('#modal-root .import-row', timeout=5000)
        pg.locator('#modal-root .import-row').first.click()
        pg.wait_for_selector('#modal-root .modal-body input')
        pg.locator('#modal-root .modal-body button.btn.primary').click()
        pg.wait_for_selector('text=Imported', timeout=5000)
        check('import flow completed', 'import' in ' '.join(cmds(pg)))
        pg.locator('#modal-root .modal-foot button', has_text='Done').click()

        pg.click('#tab-logs')
        pg.click('#log-refresh')
        waitfn(pg, "document.getElementById('log-output').textContent.indexOf('mock log line') >= 0", timeout=3000)
        check('logs rendered', 'mock log line' in pg.locator('#log-output').inner_text())
        pg.click('#tab-about')
        waitfn(pg, "document.getElementById('about-identity').innerText.indexOf('dm version') >= 0", timeout=3000)
        check('about version rendered', 'dm version' in pg.locator('#about-identity').inner_text())
        waitfn(pg, "document.getElementById('about-doctor').innerText.indexOf('SELinux') >= 0", timeout=3000)
        check('doctor rendered', 'SELinux' in pg.locator('#about-doctor').inner_text())

        # ---------------------------------------------------------------- 1. structure
        pg = fresh(390, 844, 'C1 structure')
        tabs = pg.eval_on_selector_all('[role=tab]', 'els => els.map(e => e.innerText.trim())')
        check('C1 exactly 3 [role=tab] Daemons/Logs/About', tabs == ['Daemons', 'Logs', 'About'], tabs)
        gone = pg.evaluate("""() => ({
          tab: !!document.getElementById('tab-appguard'),
          panel: !!document.getElementById('panel-appguard'),
          ag: Array.from(document.querySelectorAll('[id^="ag-"]')).filter(e => !e.closest('#modal-root')).map(e => e.id)
        })""")
        check('C1 no #tab-appguard, #panel-appguard, [id^=ag-] outside #modal-root', not gone['tab'] and not gone['panel'] and not gone['ag'], gone)

        # ---------------------------------------------------------------- 2. AppGuard sheet full flow @390x844
        pg = fresh(390, 844, 'C2 appguard sheet')
        e0 = errs_now()
        gear = '.card[data-id=appguard] [data-act=settings]'
        pg.click(gear)
        pg.wait_for_selector('#modal-root .ag-sheet .ag-sec[data-sec=kills] .kill-row', timeout=5000)
        meta = pg.evaluate("""() => { const d = document.querySelector('#modal-root [role=dialog]');
          return {aria: d.getAttribute('aria-modal'), ag: d.classList.contains('ag-sheet'), title: document.getElementById('km-modal-title').innerText, dialogs: document.querySelectorAll('#modal-root [role=dialog]').length}; }""")
        check('C2 sheet role=dialog aria-modal=true title AppGuard', meta['aria'] == 'true' and meta['title'] == 'AppGuard' and meta['ag'], meta)
        heads = pg.eval_on_selector_all('#modal-root .ag-sheet .ag-sec h3', 'els => els.map(e => e.innerText.trim())')
        check('C2 six sections Status/Settings/Run now/Targets/Never/Recent kills', heads == ['Status', 'Settings', 'Run now', 'Targets', 'Never', 'Recent kills'], heads)
        st_txt = pg.inner_text('.ag-sec[data-sec=status]')
        check('C2 status shows running state, PID 17741 and uptime', '17741' in st_txt and 'running' in st_txt.lower() and 'uptime' in st_txt.lower(), st_txt[:160].replace('\n', ' | '))
        check('C2 kills rows == 3', pg.locator('.ag-sec[data-sec=kills] .kill-row').count() == 3, pg.locator('.ag-sec[data-sec=kills] .kill-row').count())
        sbtn = pg.evaluate("""() => ['start','stop','restart'].map(a => { const b = document.querySelector('.ag-sheet [data-ag-act=' + a + ']'); return a + ':' + (b ? (b.disabled ? 'disabled' : 'enabled') : 'missing'); })""")
        check('C2 Start disabled, Stop/Restart enabled while running', sbtn == ['start:disabled', 'stop:enabled', 'restart:enabled'], sbtn)
        vals = (pg.input_value('.ag-sheet [data-ag-num=cooldown]'), pg.input_value('.ag-sheet [data-ag-num=interval]'))
        check('C2 default cooldown input shows 300, interval 60', vals == ('300', '60'), vals)

        # 44x44 audit (main view), screenshot and overflow at 390x844
        hit = pg.evaluate(HIT_JS)
        pg.wait_for_timeout(450)  # let the sheet slide-in transition finish before measuring geometry
        check('C2 44x44 audit .ag-sheet @390x844 (main view)', hit['n'] == 0 and hit['total'] > 20, hit)
        ov = pg.evaluate('document.documentElement.scrollWidth - window.innerWidth')
        edge = pg.evaluate(EDGE_JS, '#modal-root')
        panel = pg.evaluate("(() => { const r = document.querySelector('#modal-root .modal-panel').getBoundingClientRect(); return [r.left, r.top, r.width, r.height]; })()")
        pg.screenshot(path=str(EVID / 'ag-sheet-390x844.png'))
        check('C2 sheet 390x844 overflow=0 edge-crossers=0 full-screen', ov == 0 and edge['n'] == 0 and panel == [0, 0, 390, 844], {'overflow': ov, 'edge': edge, 'panel': panel})
        vp_rows.append({'name': 'ag-sheet-390x844', 'overflow': ov, 'edge': edge['n'], 'panel': panel})

        # Status Start/Stop/Restart
        def settle_status():
            waitfn(pg, "document.querySelector('.ag-sec[data-sec=status] .state') && document.querySelector('.ag-sec[data-sec=status] .state').dataset.s !== 'busy'", timeout=5000)
        n0 = len(cmds(pg))
        pg.click('.ag-sheet [data-ag-act=restart]'); settle_status(); pg.wait_for_timeout(250)
        cm = cmds(pg)[n0:]
        check('C2 Restart issues dm restart appguard', any(c.endswith("'restart' 'appguard'") for c in cm), cm)
        n0 = len(cmds(pg))
        pg.click('.ag-sheet [data-ag-act=stop]'); settle_status(); pg.wait_for_timeout(250)
        cm = cmds(pg)[n0:]
        stopped_txt = pg.inner_text('.ag-sec[data-sec=status]').lower()
        check('C2 Stop issues dm stop appguard and status shows stopped', any(c.endswith("'stop' 'appguard'") for c in cm) and 'stopped' in stopped_txt, (cm, stopped_txt[:80]))
        n0 = len(cmds(pg))
        pg.click('.ag-sheet [data-ag-act=start]'); settle_status(); pg.wait_for_timeout(250)
        cm = cmds(pg)[n0:]
        check('C2 Start issues dm start appguard and status shows running', any(c.endswith("'start' 'appguard'") for c in cm) and 'running' in pg.inner_text('.ag-sec[data-sec=status]').lower(), cm)
        check('C2 sheet still open after lifecycle actions (single dialog)', pg.locator('#modal-root [role=dialog]').count() == 1)

        # interval, default cooldown, dry-run
        n0 = len(cmds(pg))
        pg.fill('.ag-sheet [data-ag-num=interval]', '90'); pg.keyboard.press('Enter'); pg.wait_for_timeout(250)
        pg.fill('.ag-sheet [data-ag-num=cooldown]', '450'); pg.keyboard.press('Enter'); pg.wait_for_timeout(250)
        pg.click('.ag-sheet [data-ag-act=dry]'); pg.wait_for_timeout(250)
        cfg_on = pg.evaluate('JSON.parse(JSON.stringify(window.__mockState.config))')
        dry_note = 'Dry-run is on' in pg.inner_text('.ag-sec[data-sec=run]')
        pg.click('.ag-sheet [data-ag-act=dry]'); pg.wait_for_timeout(250)
        cfg_off = pg.evaluate('JSON.parse(JSON.stringify(window.__mockState.config))')
        cm = ' || '.join(cmds(pg)[n0:])
        check('C2 interval set 90 command + persisted', "'set' 'interval' '90'" in cm and cfg_on['interval_s'] == 90, cfg_on)
        check('C2 default cooldown set 450 command + persisted', "'set' 'cooldown' '450'" in cm and cfg_on['cooldown_s'] == 450, cfg_on)
        check('C2 dry-run on/off commands + note', "'set' 'dry' '1'" in cm and "'set' 'dry' '0'" in cm and cfg_on['dry_run'] is True and cfg_off['dry_run'] is False and dry_note, (cfg_on, cfg_off, dry_note))

        # Run once: Cancel path then Confirm path
        n0 = len(cmds(pg))
        pg.click('.ag-sheet [data-ag-act=run]')
        pg.wait_for_selector('.ag-sheet [data-ag-act=run-confirm]', timeout=2000)
        confirm_txt = pg.inner_text('.ag-sec[data-sec=run]')
        check('C2 Run once shows inline confirm strip (no nested dialog)', 'Sends real am-kill requests' in confirm_txt and pg.locator('#modal-root [role=dialog]').count() == 1, confirm_txt[:120])
        hit2 = pg.evaluate(HIT_JS)
        check('C2 44x44 audit with confirm strip open', hit2['n'] == 0, hit2)
        pg.click('.ag-sheet [data-ag-act=run-cancel]'); pg.wait_for_timeout(200)
        check('C2 Cancel sends no once command', not any("'once'" in c for c in cmds(pg)[n0:]), cmds(pg)[n0:])
        pg.click('.ag-sheet [data-ag-act=run]')
        pg.click('.ag-sheet [data-ag-act=run-confirm]')
        pg.wait_for_selector('.ag-sheet .result-box', timeout=3000)
        cm = cmds(pg)[n0:]
        check('C2 Run once confirm -> appguard once WITHOUT --dry', any(c.endswith("'appguard' 'once'") for c in cm) and not any('--dry' in c for c in cm), cm)
        n0 = len(cmds(pg))
        pg.click('.ag-sheet [data-ag-act=dry-run]')
        waitfn(pg, "document.querySelector('.ag-sheet .result-box') && document.querySelector('.ag-sheet .result-box').innerText.indexOf('dry') >= 0", timeout=3000)
        cm = cmds(pg)[n0:]
        rb = pg.inner_text('.ag-sheet .result-box')
        check('C2 Dry run once -> once --dry, result box shows candidates', any(c.endswith("'once' '--dry'") for c in cm) and 'candidates' in rb, (cm, rb[:80]))

        # targets: toggle U0 and U999 on the first row, same node
        pg.evaluate("window.__r0 = document.querySelector('.ag-sheet .target-row[data-pkg]'); window.__pkg0 = window.__r0.dataset.pkg;")
        n0 = len(cmds(pg))
        pg.locator('.ag-sheet .target-row[data-pkg] .u0 .switch').first.click()
        waitfn(pg, "document.querySelector('.ag-sheet .target-row[data-pkg] .u0 .switch').getAttribute('aria-checked') === 'false'", timeout=2000)
        pg.wait_for_timeout(250)
        cm = cmds(pg)[n0:]
        st0 = pg.evaluate('(() => { const t = window.__mockState.targets.find(x => x.pkg === window.__pkg0); return [t.u0, t.u999]; })()')
        same = pg.evaluate("window.__r0 === document.querySelector('.ag-sheet .target-row[data-pkg]') && document.contains(window.__r0)")
        check('C2 U0 toggle: targets set command, aria-checked flips, same row node', any("'targets'" in c and "'set'" in c and 'u0=0' in c for c in cm) and same and st0[0] is False, (cm, same, st0))
        n0 = len(cmds(pg))
        pg.locator('.ag-sheet .target-row[data-pkg] .u999 .switch').first.click()
        waitfn(pg, "document.querySelector('.ag-sheet .target-row[data-pkg] .u999 .switch').getAttribute('aria-checked') === 'true'", timeout=2000)
        pg.wait_for_timeout(250)
        cm = cmds(pg)[n0:]
        st0 = pg.evaluate('(() => { const t = window.__mockState.targets.find(x => x.pkg === window.__pkg0); return [t.u0, t.u999]; })()')
        same = pg.evaluate("window.__r0 === document.querySelector('.ag-sheet .target-row[data-pkg]') && document.contains(window.__r0)")
        check('C2 U999 toggle: targets set command, aria-checked flips, same row node', any("'targets'" in c and "'set'" in c and 'u999=1' in c for c in cm) and same and st0[1] is True, (cm, same, st0))
        # per-app cooldown
        n0 = len(cmds(pg))
        pg.locator('.ag-sheet .target-row[data-pkg]').nth(1).locator('input').fill('120')
        pg.keyboard.press('Enter'); pg.wait_for_timeout(300)
        cm = cmds(pg)[n0:]
        pkg1 = pg.evaluate("document.querySelectorAll('.ag-sheet .target-row[data-pkg]')[1].dataset.pkg")
        cs = pg.evaluate('(p) => window.__mockState.targets.find(x => x.pkg === p).cooldown_s', pkg1)
        check('C2 per-app cooldown 120 -> targets set cooldown=120, persisted', any('cooldown=120' in c and "'targets'" in c for c in cm) and cs == 120, (cm, cs))

        # picker, target mode: Back path, then add
        pg.click('.ag-sheet [data-ag-act=picker-target]')
        pg.wait_for_selector('.ag-sheet .ag-picker .picker-row', timeout=3000)
        check('C2 picker (target) opens in-sheet, single dialog', pg.locator('#modal-root [role=dialog]').count() == 1 and pg.locator('.ag-sheet .ag-picker').count() == 1)
        hit3 = pg.evaluate(HIT_JS)
        check('C2 44x44 audit with picker open', hit3['n'] == 0, hit3)
        pg.click('.ag-picker [data-ag-act=picker-back]'); pg.wait_for_timeout(150)
        back_focus = pg.evaluate("document.activeElement && document.activeElement.getAttribute('data-ag-act')")
        check('C2 picker Back closes picker, sheet stays, focus returns to opener', pg.locator('.ag-picker').count() == 0 and pg.locator('.ag-sheet').count() == 1 and back_focus == 'picker-target', back_focus)
        pg.click('.ag-sheet [data-ag-act=picker-target]')
        pg.wait_for_selector('.ag-picker .picker-row[data-pkg="com.demo.extra"]', timeout=3000)
        n0 = len(cmds(pg))
        pg.click('.ag-picker .picker-row[data-pkg="com.demo.extra"]')
        pg.wait_for_selector('.ag-sheet .target-row[data-pkg="com.demo.extra"]', timeout=3000)
        cm = cmds(pg)[n0:]
        check('C2 picker target mode adds com.demo.extra (u0=1 u999=0) and row appears', any("'targets' 'add' 'com.demo.extra'" in c and 'u0=1' in c and 'u999=0' in c for c in cm) and pg.locator('.ag-picker').count() == 0, cm)

        # picker, never mode: add then chip remove
        pg.click('.ag-sheet [data-ag-act=picker-never]')
        pg.wait_for_selector('.ag-picker .picker-row[data-pkg="com.demo.ghost"]', timeout=3000)
        n0 = len(cmds(pg))
        pg.click('.ag-picker .picker-row[data-pkg="com.demo.ghost"]')
        pg.wait_for_selector('.ag-sheet .never-chip[data-pkg="com.demo.ghost"]', timeout=3000)
        cm = cmds(pg)[n0:]
        check('C2 picker never mode adds com.demo.ghost chip', any("'never' 'add' 'com.demo.ghost'" in c for c in cm) and pg.locator('.ag-picker').count() == 0, cm)
        n0 = len(cmds(pg))
        pg.click('.ag-sheet .never-chip[data-pkg="com.demo.ghost"] button')
        waitfn(pg, "document.querySelectorAll('.ag-sheet .never-chip[data-pkg=\"com.demo.ghost\"]').length === 0", timeout=3000)
        cm = cmds(pg)[n0:]
        check('C2 never chip remove -> never rm, chip gone', any("'never' 'rm' 'com.demo.ghost'" in c for c in cm), cm)

        # focus trap wrap
        trap = pg.evaluate("""() => {
          const f = (%s)();
          const last = f[f.length - 1], first = f[0];
          last.focus();
          return {n: f.length, first: first.getAttribute('aria-label') || first.innerText || first.className, last: last.getAttribute('aria-label') || last.innerText || last.className};
        }""" % FOCUSABLE_JS)
        pg.keyboard.press('Tab')
        fwd = pg.evaluate("""() => { const f = (%s)(); const a = document.activeElement; return {inside: !!a.closest('#modal-root .modal-panel'), isFirst: a === f[0]}; }""" % FOCUSABLE_JS)
        pg.keyboard.press('Shift+Tab')
        back = pg.evaluate("""() => { const f = (%s)(); const a = document.activeElement; return {inside: !!a.closest('#modal-root .modal-panel'), isLast: a === f[f.length - 1]}; }""" % FOCUSABLE_JS)
        check('C2 focus trap: Tab from last wraps to first, Shift+Tab from first wraps to last', fwd['inside'] and fwd['isFirst'] and back['inside'] and back['isLast'], {'trap': trap, 'fwd': fwd, 'back': back})
        for _ in range(4):
            pg.keyboard.press('Tab')
        check('C2 focus stays inside dialog after 4 more Tabs', pg.evaluate("!!document.activeElement.closest('#modal-root .modal-panel')"))

        # Escape: picker back first, then close; focus restored to gear
        pg.click('.ag-sheet [data-ag-act=picker-never]')
        pg.wait_for_selector('.ag-picker .picker-row', timeout=3000)
        pg.keyboard.press('Escape'); pg.wait_for_timeout(150)
        check('C2 Escape in picker goes Back first (sheet stays)', pg.locator('.ag-sheet').count() == 1 and pg.locator('.ag-picker').count() == 0)
        pg.keyboard.press('Escape'); pg.wait_for_timeout(200)
        focus = pg.evaluate("(() => { const a = document.activeElement; return {act: a && a.getAttribute('data-act'), card: a && a.closest('[data-id]') && a.closest('[data-id]').dataset.id}; })()")
        check('C2 second Escape closes sheet, focus restored to AppGuard gear', pg.locator('#modal-root .modal').count() == 0 and focus == {'act': 'settings', 'card': 'appguard'}, focus)
        check('C2 sheet flow: zero console/page errors', errs_now() == e0, (console_errors[e0[0]:], page_errors[e0[1]:]))

        # sheet at 360x640: full screen, no overflow, 44x44
        pg = fresh(360, 640, 'C2 sheet 360x640')
        pg.click(gear)
        pg.wait_for_selector('.ag-sheet .target-row[data-pkg]', timeout=5000)
        pg.wait_for_timeout(450)  # sheet slide-in transition
        panel = pg.evaluate("(() => { const r = document.querySelector('.ag-sheet').getBoundingClientRect(); return [r.left, r.top, r.width, r.height]; })()")
        ov = pg.evaluate('document.documentElement.scrollWidth - window.innerWidth')
        edge = pg.evaluate(EDGE_JS, '#modal-root')
        hit = pg.evaluate(HIT_JS)
        pg.screenshot(path=str(EVID / 'ag-sheet-360x640.png'))
        check('C2 sheet full-screen at 360x640, overflow=0, edge-crossers=0', panel == [0, 0, 360, 640] and ov == 0 and edge['n'] == 0, {'panel': panel, 'overflow': ov, 'edge': edge})
        check('C2 44x44 audit .ag-sheet @360x640', hit['n'] == 0, hit)
        vp_rows.append({'name': 'ag-sheet-360x640', 'overflow': ov, 'edge': edge['n'], 'panel': panel})

        # sheet at 1280x800
        pg = fresh(1280, 800, 'C2 sheet 1280x800')
        pg.click(gear)
        pg.wait_for_selector('.ag-sheet .target-row[data-pkg]', timeout=5000)
        pg.wait_for_timeout(450)  # sheet slide-in transition
        panel = pg.evaluate("(() => { const r = document.querySelector('.ag-sheet').getBoundingClientRect(); return [Math.round(r.left), Math.round(r.top), Math.round(r.width), Math.round(r.height), innerWidth, innerHeight]; })()")
        ov = pg.evaluate('document.documentElement.scrollWidth - window.innerWidth')
        edge = pg.evaluate(EDGE_JS, '#modal-root')
        hit = pg.evaluate(HIT_JS)
        pg.screenshot(path=str(EVID / 'ag-sheet-1280x800.png'))
        inside = panel[0] >= 0 and panel[0] + panel[2] <= 1280 and panel[1] >= 0 and panel[1] + panel[3] <= 800
        check('C2 sheet 1280x800 inside viewport, overflow=0, edge-crossers=0', inside and ov == 0 and edge['n'] == 0, {'panel': panel, 'overflow': ov, 'edge': edge})
        check('C2 44x44 audit .ag-sheet @1280x800', hit['n'] == 0, hit)
        vp_rows.append({'name': 'ag-sheet-1280x800', 'overflow': ov, 'edge': edge['n'], 'panel': panel})

        # ---------------------------------------------------------------- 3. DSC sheet
        pg = fresh(1280, 800, 'C3 DSC')
        pg.click('.card[data-id=deep-sleep-cool] [data-act=settings]')
        pg.wait_for_selector('#modal-root [role=dialog]', timeout=3000)
        title = pg.inner_text('#km-modal-title')
        sw_ok = True
        try:
            pg.wait_for_selector('#modal-root [role=switch]', timeout=3000)
        except Exception:
            sw_ok = False
        body = pg.inner_text('#modal-root .modal-body')
        check('C3 DSC gear opens "Deep Sleep Cool" sheet', title == 'Deep Sleep Cool', title)
        # textContent (DOM text), not inner_text: style.css:160 .switch-label{text-transform:uppercase} makes inner_text uppercase
        try:
            sw_label = (pg.locator('#modal-root .switch-label').first.text_content(timeout=3000) or '').strip()
        except Exception as e:
            sw_label = 'ERR: %s' % str(e)[:80]
        check('C3 DSC sheet renders "Freeze while unplugged" switch', sw_ok and sw_label == 'Freeze while unplugged', 'textContent=%r sw_ok=%s body=%s' % (sw_label, sw_ok, body[:120].replace('\n', ' | ')))
        if sw_ok:
            before = pg.get_attribute('#modal-root [role=switch]', 'aria-checked')
            n0 = len(cmds(pg))
            pg.click('#modal-root [role=switch]')
            waitfn(pg, "document.querySelector('#modal-root [role=switch]') && document.querySelector('#modal-root [role=switch]').getAttribute('aria-checked') !== '%s'" % before, timeout=3000)
            after = pg.get_attribute('#modal-root [role=switch]', 'aria-checked')
            cm = cmds(pg)[n0:]
            check('C3 DSC switch toggles via setconf freeze_unplugged', any("'setconf' 'freeze_unplugged'" in c for c in cm) and before != after, (before, after, cm))

        # diagnostic: same sheet with a non-contract bare-array `packages` reply, to isolate the defect above
        pg = fresh(1280, 800, 'C3b DSC diagnostic')
        pg.evaluate("window.__mockState.faults.packages = 'array'")
        pg.click('.card[data-id=deep-sleep-cool] [data-act=settings]')
        sw_ok = True
        try:
            pg.wait_for_selector('#modal-root [role=switch]', timeout=3000)
        except Exception:
            sw_ok = False
        if sw_ok:
            before = pg.get_attribute('#modal-root [role=switch]', 'aria-checked')
            n0 = len(cmds(pg))
            pg.click('#modal-root [role=switch]')
            waitfn(pg, "document.querySelector('#modal-root [role=switch]') && document.querySelector('#modal-root [role=switch]').getAttribute('aria-checked') !== '%s'" % before, timeout=3000)
            after = pg.get_attribute('#modal-root [role=switch]', 'aria-checked')
            cm = cmds(pg)[n0:]
            check('C3b DIAGNOSTIC (bare-array packages, NOT the dm contract): rest of DSC sheet works, switch toggles via setconf', any("'setconf' 'freeze_unplugged'" in c for c in cm) and before != after, (before, after, cm))
        else:
            check('C3b DIAGNOSTIC (bare-array packages, NOT the dm contract): switch renders', False, pg.inner_text('#modal-root .modal-body')[:150])

        # ---------------------------------------------------------------- 4/5. no-change + changed poll
        pg = fresh(390, 844, 'C4 no-change poll')
        pg.wait_for_timeout(300)
        pg.evaluate("document.querySelector('#daemon-list .card [data-act=details]').focus({preventScroll: true}); window.__ae = document.activeElement; window.scrollTo(0, 300);")
        pg.wait_for_timeout(100)
        sy0 = pg.evaluate('window.scrollY')
        pg.evaluate("""() => { window.__mut = []; window.__cards = Array.from(document.querySelectorAll('#daemon-list .card'));
          window.__mo = new MutationObserver(r => window.__mut.push(...r));
          window.__mo.observe(document.getElementById('daemon-list'), {childList: true, subtree: true, attributes: true, characterData: true}); }""")
        n0 = len(cmds(pg))
        r = pg.evaluate('KM.pollNow()')
        pg.wait_for_timeout(5500)
        pg.evaluate('window.__mut.push(...window.__mo.takeRecords())')
        cm = cmds(pg)[n0:]
        lc = list_calls(cm)
        muts = pg.evaluate('window.__mut.length')
        mut_desc = pg.evaluate("window.__mut.slice(0, 5).map(m => m.type + ':' + (m.target.nodeName || '') + ':' + (m.attributeName || ''))")
        same = pg.evaluate("(() => { const now = Array.from(document.querySelectorAll('#daemon-list .card')); return now.length === window.__cards.length && now.every((c, i) => c === window.__cards[i]); })()")
        sy1 = pg.evaluate('window.scrollY')
        ae_same = pg.evaluate('document.activeElement === window.__ae')
        check('C4 scrolled to 300 (precondition)', sy0 == 300, sy0)
        check('C4 KM.pollNow() ran (resolved true) and list issued; plus >=1 real 5.5s tick', r is True and lc >= 2, {'pollNow': r, 'list_calls_in_window': lc})
        check('C4 MutationObserver on #daemon-list: 0 records', muts == 0, {'records': muts, 'sample': mut_desc})
        check('C4 same card node references', same)
        check('C4 window.scrollY unchanged', sy1 == sy0, (sy0, sy1))
        check('C4 activeElement unchanged', ae_same)

        # changed poll (uptime +60)
        sect['name'] = 'C5 changed poll'
        pg.evaluate("""() => { window.__mut = []; window.__mo.takeRecords();
          const c = document.querySelector('#daemon-list .card[data-id=appguard]');
          window.__up0 = (c.querySelector('[data-f=uptime] .v') || c).innerText; window.__card0 = c; }""")
        pg.evaluate("window.__mockState.daemons[0].uptime_s += 60")
        r = pg.evaluate('KM.pollNow()')
        pg.wait_for_timeout(200)
        pg.evaluate('window.__mut.push(...window.__mo.takeRecords())')
        info = pg.evaluate("""() => {
          const now = Array.from(document.querySelectorAll('#daemon-list .card'));
          const removed = window.__mut.reduce((n, m) => n + Array.from(m.removedNodes).filter(x => x.nodeType === 1 && (x.classList.contains('card') || (x.querySelector && x.querySelector('.card')))).length, 0);
          const c = document.querySelector('#daemon-list .card[data-id=appguard]');
          return {same: now.length === window.__cards.length && now.every((x, i) => x === window.__cards[i]), removed: removed, records: window.__mut.length,
                  up0: window.__up0, up1: (c.querySelector('[data-f=uptime] .v') || c).innerText, sameAg: c === window.__card0}; }""")
        check('C5 changed poll: same card nodes, 0 .card removals', r is True and info['same'] and info['sameAg'] and info['removed'] == 0, info)
        check('C5 uptime text updated in place (3612s -> 3672s)', info['up0'] != info['up1'] and '1h 1m' in info['up1'], info)

        # ---------------------------------------------------------------- 6. pauses
        pg = fresh(390, 844, 'C6 pause: sheet open')
        pg.wait_for_timeout(500)
        pg.click(gear)
        pg.wait_for_selector('.ag-sheet .ag-sec[data-sec=kills] .kill-row', timeout=5000)
        pg.wait_for_timeout(300)
        n0 = len(cmds(pg))
        pr = pg.evaluate('KM.pollNow()')
        pg.wait_for_timeout(6000)
        lc = list_calls(cmds(pg)[n0:])
        check('C6 sheet open: 0 list calls in 6 s, pollNow() resolves false', lc == 0 and pr is False, {'list_calls': lc, 'pollNow': pr})

        pg = fresh(390, 844, 'C6 pause: logs tab')
        pg.wait_for_timeout(300)
        pg.click('#tab-logs')
        pg.wait_for_timeout(500)
        n0 = len(cmds(pg))
        pr = pg.evaluate('KM.pollNow()')
        pg.wait_for_timeout(6000)
        lc = list_calls(cmds(pg)[n0:])
        check('C6 Logs tab: 0 list calls in 6 s, pollNow() resolves false', lc == 0 and pr is False, {'list_calls': lc, 'pollNow': pr})

        pg = fresh(390, 844, 'C6 pause: hidden')
        pg.wait_for_timeout(300)
        pg.evaluate("""() => { Object.defineProperty(document, 'hidden', {get: () => true, configurable: true});
          Object.defineProperty(document, 'visibilityState', {get: () => 'hidden', configurable: true});
          document.dispatchEvent(new Event('visibilitychange')); }""")
        n0 = len(cmds(pg))
        pr = pg.evaluate('KM.pollNow()')
        pg.wait_for_timeout(6000)
        lc = list_calls(cmds(pg)[n0:])
        check('C6 document.hidden: 0 list calls in 6 s, pollNow() resolves false', lc == 0 and pr is False, {'list_calls': lc, 'pollNow': pr})
        n0 = len(cmds(pg))
        pg.evaluate("""() => { Object.defineProperty(document, 'hidden', {get: () => false, configurable: true});
          Object.defineProperty(document, 'visibilityState', {get: () => 'visible', configurable: true});
          document.dispatchEvent(new Event('visibilitychange')); }""")
        pg.wait_for_timeout(800)
        lc = list_calls(cmds(pg)[n0:])
        check('C6 visible again: poll resumes with one immediate refresh (1..2 list calls)', 1 <= lc <= 2, lc)

        # ---------------------------------------------------------------- 7. stress
        pg = fresh(390, 844, 'C7 stress')
        pg.wait_for_timeout(400)
        e0 = errs_now()
        w0 = len(console_warns)
        n0 = len(cmds(pg))
        burst = pg.evaluate(BURST_JS)
        pg.wait_for_timeout(800)
        cm = cmds(pg)[n0:]
        lc = list_calls(cm)
        check('C7 100 rapid tab switches: 0 pageerror, 0 console error', errs_now() == e0, (console_errors[e0[0]:], page_errors[e0[1]:]))
        check('C7 no empty active panel at every 10th switch (10 checks)', burst['checked'] == 10 and not burst['empty'], burst)
        check('C7 list calls during burst <= 2', lc <= 2, {'list_calls': lc, 'all_cmds': len(cm)})
        check('C7 no .panel-error after burst, unexpected console.warn = 0', pg.locator('.panel-error').count() == 0 and len(console_warns) == w0, (pg.locator('.panel-error').count(), console_warns[w0:]))

        # wheel stress on daemon list
        pg.evaluate("KM.activate('daemons', false)")
        pg.wait_for_timeout(300)
        box = pg.locator('#daemon-list').bounding_box()
        pg.mouse.move(box['x'] + box['width'] / 2, 400)
        ys = []
        for i in range(40):
            pg.mouse.wheel(0, 1200 if i % 2 == 0 else -1200)
            if i % 4 == 3:
                pg.wait_for_timeout(80)
                ys.append(pg.evaluate('window.scrollY'))
        pg.wait_for_timeout(300)
        dl_state = pg.evaluate("({sy: window.scrollY, h: document.documentElement.scrollHeight, cards: document.querySelectorAll('#daemon-list .card').length})")
        check('C7 40 wheel +-1200 on daemon list: no errors, cards intact, page scrolled', errs_now() == e0 and dl_state['cards'] >= 6 and dl_state['h'] > 844, {'state': dl_state, 'scrollY_samples': ys})

        # wheel stress on #log-output with 200 lines
        pg.click('#tab-logs')
        pg.select_option('#log-lines', '200')
        waitfn(pg, "document.getElementById('log-output').textContent.split('\\n').length >= 200", timeout=4000)
        pg.wait_for_timeout(200)
        lo = pg.evaluate("(() => { const b = document.getElementById('log-output'); return {lines: b.textContent.split('\\n').length, sh: b.scrollHeight, ch: b.clientHeight, ov: getComputedStyle(b).overflowY}; })()")
        pg.evaluate("window.scrollTo(0, 0)")
        bb = pg.locator('#log-output').bounding_box()
        pg.mouse.move(bb['x'] + bb['width'] / 2, bb['y'] + min(bb['height'], 300) / 2)
        lys = []
        for i in range(40):
            pg.mouse.wheel(0, 1200 if i % 2 == 0 else -1200)
            if i % 4 == 3:
                pg.wait_for_timeout(80)
                lys.append(pg.evaluate("document.getElementById('log-output').scrollTop"))
        pg.wait_for_timeout(200)
        check('C7 40 wheel +-1200 on #log-output (200 lines): scrollable, no errors', errs_now() == e0 and lo['lines'] >= 200 and lo['sh'] > lo['ch'], {'log': lo, 'scrollTop_samples': lys})

        # open/close AppGuard sheet 10 times
        pg.click('#tab-daemons')
        pg.wait_for_selector('#daemon-list .card')
        opened = []
        for i in range(10):
            pg.click(gear)
            pg.wait_for_selector('.ag-sheet .ag-sec[data-sec=kills] .kill-row', timeout=4000)
            if i % 2 == 0:
                pg.keyboard.press('Escape')
            else:
                pg.click('.ag-sheet .modal-foot button:has-text("Done")')
            waitfn(pg, "document.querySelectorAll('#modal-root .modal').length === 0", timeout=2000)
            opened.append(pg.evaluate("document.querySelectorAll('#modal-root *').length"))
        check('C7 AppGuard sheet open/close x10: closes cleanly, modal-root empty, no errors', errs_now() == e0 and all(x == 0 for x in opened), {'modal_root_nodes_after_close': opened})

        # toggle one target and one cooldown, then no-change poll keeps both scroll positions
        pg.click(gear)
        pg.wait_for_selector('.ag-sheet .target-row[data-pkg]', timeout=4000)
        pg.locator('.ag-sheet .target-row[data-pkg] .u0 .switch').first.click()
        pg.wait_for_timeout(300)
        pg.locator('.ag-sheet .target-row[data-pkg]').nth(2).locator('input').fill('240')
        pg.keyboard.press('Enter'); pg.wait_for_timeout(300)
        cs = pg.evaluate("window.__mockState.targets[2].cooldown_s")
        u0 = pg.evaluate('window.__mockState.targets[0].u0')
        pg.keyboard.press('Escape'); pg.wait_for_timeout(200)
        check('C7 target toggle + cooldown applied after stress (mock state)', cs == 240 and u0 is False, {'cooldown_s': cs, 'u0': u0})
        # logs position: park mid-log; daemons: park page at 300
        pg.click('#tab-logs'); pg.wait_for_timeout(300)
        pg.evaluate("document.getElementById('log-output').scrollTop = 400")
        pg.wait_for_timeout(100)
        lt0 = pg.evaluate("document.getElementById('log-output').scrollTop")
        pr = pg.evaluate('KM.pollNow()')
        pg.wait_for_timeout(5600)
        lt1 = pg.evaluate("document.getElementById('log-output').scrollTop")
        check('C7 Logs scroll kept across pollNow (skipped) + 5.6 s of timers', lt0 > 0 and lt0 == lt1 and pr is False, {'before': lt0, 'after': lt1, 'pollNow': pr})
        pg.click('#tab-daemons'); pg.wait_for_selector('#daemon-list .card')
        pg.wait_for_timeout(300)
        pg.evaluate("window.scrollTo(0, 300)")
        pg.wait_for_timeout(100)
        sy0 = pg.evaluate('window.scrollY')
        pg.evaluate("window.__mut = []; window.__cards = Array.from(document.querySelectorAll('#daemon-list .card')); window.__mo = new MutationObserver(r => window.__mut.push(...r)); window.__mo.observe(document.getElementById('daemon-list'), {childList: true, subtree: true, attributes: true, characterData: true});")
        n0 = len(cmds(pg))
        pr = pg.evaluate('KM.pollNow()')
        pg.wait_for_timeout(5600)
        pg.evaluate('window.__mut.push(...window.__mo.takeRecords())')
        sy1 = pg.evaluate('window.scrollY')
        muts = pg.evaluate('window.__mut.length')
        same = pg.evaluate("Array.from(document.querySelectorAll('#daemon-list .card')).every((c, i) => c === window.__cards[i])")
        lc = list_calls(cmds(pg)[n0:])
        check('C7 after stress: no-change poll keeps daemon scrollY, 0 mutations, same nodes', sy0 == 300 and sy1 == sy0 and muts == 0 and same and pr is True and lc >= 2, {'scrollY': [sy0, sy1], 'mutations': muts, 'same': same, 'pollNow': pr, 'list_calls': lc})
        pg.click('#tab-logs'); pg.wait_for_timeout(300)
        extra_info['log_scrollTop_after_tab_roundtrip'] = {'set': lt0, 'after': pg.evaluate("document.getElementById('log-output').scrollTop")}
        check('C7 stress run: zero pageerror / console error', errs_now() == e0, (console_errors[e0[0]:], page_errors[e0[1]:]))

        # ---------------------------------------------------------------- 8. logs
        pg = fresh(390, 844, 'C8 logs')
        pg.click('#tab-logs')
        pg.select_option('#log-lines', '200')
        waitfn(pg, "document.getElementById('log-output').textContent.split('\\n').length >= 200", timeout=4000)
        pg.check('#log-auto')
        pg.wait_for_timeout(200)
        pre = pg.evaluate("(() => { const b = document.getElementById('log-output'); return {sh: b.scrollHeight, ch: b.clientHeight, top: b.scrollTop}; })()")
        pg.evaluate("document.getElementById('log-output').scrollTop = 0")
        pg.wait_for_timeout(100)
        pg.evaluate("window.__mockState.logGrow = true")
        n0 = len(cmds(pg))
        pg.wait_for_timeout(6000)
        lg = [c for c in cmds(pg)[n0:] if "'logs'" in c]
        top = pg.evaluate("document.getElementById('log-output').scrollTop")
        check('C8 auto on, scrolled to top, logGrow on, 6 s: scrollTop unchanged (0)', top == 0 and pre['sh'] > pre['ch'], {'scrollTop': top, 'precond': pre})
        check('C8 no logs call while away from bottom', len(lg) == 0, lg)
        last0 = pg.evaluate("document.getElementById('log-output').textContent.trim().split('\\n').pop()")
        pg.evaluate("(() => { const b = document.getElementById('log-output'); b.scrollTop = b.scrollHeight; })()")
        pg.wait_for_timeout(6000)
        res = pg.evaluate("""() => { const b = document.getElementById('log-output'); const lines = b.textContent.trim().split('\\n');
          return {last: lines.pop(), gap: b.scrollHeight - b.scrollTop - b.clientHeight, n: lines.length + 1}; }""")
        lg2 = [c for c in cmds(pg)[n0:] if "'logs'" in c]
        check('C8 at bottom, 6 s: new line appended and still at bottom (gap<=1)', res['last'] != last0 and len(lg2) >= 1 and res['gap'] <= 1, {'last_before': last0, 'last_after': res['last'], 'gap': res['gap'], 'logs_calls': len(lg2)})

        # ---------------------------------------------------------------- 9. error boundary
        pg = fresh(390, 844, 'C9 error boundary')
        pg.wait_for_timeout(300)
        e0 = errs_now()
        w0 = len(console_warns)
        pg.evaluate("window.__mockState.faults.list = 'poison'")
        pg.click('#refresh')
        pg.wait_for_selector('#panel-daemons .panel-error', timeout=4000)
        pe = pg.evaluate("""() => { const e = document.querySelector('#panel-daemons .panel-error'); return {text: e.innerText, retry: !!Array.from(e.querySelectorAll('button')).find(b => /retry/i.test(b.innerText)), role: e.getAttribute('role')}; }""")
        check('C9 poison + Refresh -> .panel-error with Retry in Daemons panel', pe['retry'] and 'E_RENDER' in pe['text'], pe)
        check('C9 boundary logs console.warn only (no console error / pageerror)', errs_now() == e0 and len(console_warns) > w0, (console_errors[e0[0]:], page_errors[e0[1]:], console_warns[w0:][:2]))
        sw = []
        for t in ('logs', 'about', 'daemons'):
            pg.click('#tab-' + t)
            pg.wait_for_timeout(150)
            sw.append((t, pg.evaluate("document.getElementById('tab-%s').getAttribute('aria-selected') === 'true' && !document.getElementById('panel-%s').hidden" % (t, t))))
        check('C9 tabs still switch while the Daemons panel is in error', all(x[1] for x in sw), sw)
        check('C9 shell intact: header + tabs + conn chip visible', pg.evaluate("['tabs', 'refresh', 'conn-chip'].every(id => document.getElementById(id).getClientRects().length > 0)"))
        pg.evaluate("window.__mockState.faults.list = null")
        retry_note = 'panel-error survived tab switches'
        if pg.locator('#panel-daemons .panel-error').count() == 0:
            # a tab-activation reload already healed it; re-poison once to exercise Retry itself
            retry_note = 'healed by tab switch; re-poisoned to exercise Retry'
            pg.evaluate("window.__mockState.faults.list = 'poison'")
            pg.click('#refresh')
            pg.wait_for_selector('#panel-daemons .panel-error', timeout=4000)
            pg.evaluate("window.__mockState.faults.list = null")
        pg.locator('#panel-daemons .panel-error button', has_text='Retry').click()
        waitfn(pg, "document.querySelectorAll('#daemon-list .card').length >= 6 && document.querySelectorAll('#panel-daemons .panel-error').length === 0", timeout=4000)
        check('C9 clear fault + Retry -> cards back, no .panel-error', pg.locator('#daemon-list .card').count() >= 6 and pg.locator('#panel-daemons .panel-error').count() == 0, {'cards': pg.locator('#daemon-list .card').count(), 'note': retry_note})
        check('C9 error boundary run: 0 pageerror, 0 console error', errs_now() == e0, (console_errors[e0[0]:], page_errors[e0[1]:]))
        extra_info['boundary_warnings'] = console_warns[w0:][:3]

        # ---------------------------------------------------------------- R. fix-loop regressions (M1/M2/M3 + extras)
        # Each section records a FAIL instead of aborting, so the pre-fix snapshot run completes.
        GEAR = '.card[data-id=appguard] [data-act=settings]'

        def open_ag(pg):
            pg.click(GEAR)
            pg.wait_for_selector('#modal-root .ag-sheet .target-row[data-pkg]', timeout=5000)
            pg.wait_for_selector('#modal-root .ag-sheet [data-ag-num=interval]', timeout=5000)

        def reset_hooks(pg):
            try:
                pg.evaluate("() => { window.__mockState.delays = {}; window.__mockState.failOn = {}; return 1 }")
            except Exception:
                pass

        def aborted(rid, e):
            check(f'{rid}: section completed (no timeout/abort)', False, f'{type(e).__name__}: {str(e)[:200]}')

        LIVE_SW_JS = """([pkg, cls]) => {
          const rows = Array.from(document.querySelectorAll('#modal-root .ag-sheet .ag-sec[data-sec=targets] .target-row'));
          const r = rows.find(x => x.dataset.pkg === pkg);
          if (!r) return null;
          const b = r.querySelector('.' + cls + ' .switch');
          return {checked: b.getAttribute('aria-checked'), disabled: b.disabled, busy: b.getAttribute('aria-busy'), live: document.contains(r)};
        }"""
        STATE3_JS = """([pkg, key]) => {
          const m = (window.KM.S.ag.targets || []).find(x => x.pkg === pkg);
          const k = window.__mockState.targets.find(x => x.pkg === pkg);
          return {model: m ? !!m[key] : null, mock: k ? !!k[key] : null};
        }"""
        FILTER = '#modal-root .ag-sec[data-sec=targets] input[type=search]'

        def rerender_mid_flight(pg, pkg, gap):
            pg.fill(FILTER, pkg)
            pg.wait_for_timeout(gap)
            pg.fill(FILTER, '')
            pg.wait_for_timeout(gap)

        def wait_unbusy(pg, pkg):
            waitfn(pg, """(() => { const r = Array.from(document.querySelectorAll('#modal-root .ag-sec[data-sec=targets] .target-row')).find(x => x.dataset.pkg === %s);
              return !!r && !r.querySelector('.switch[aria-busy=true]'); })()""" % json.dumps(pkg), timeout=3000)

        # R1 / R1b - M1 stale switch after an in-flight targets set + row re-render
        pg = fresh(390, 844, 'R1 M1 setTarget')
        e0 = errs_now()
        try:
            open_ag(pg)
            pkg0 = pg.evaluate("document.querySelector('#modal-root .ag-sheet .target-row[data-pkg]').dataset.pkg")
            b0 = pg.evaluate(LIVE_SW_JS, [pkg0, 'u0'])['checked'] == 'true'
            want = 'false' if b0 else 'true'
            pg.evaluate("""() => { window.__mockState.delays = {"'targets' 'set'": 1200}; return 1 }""")
            n0 = len(cmds(pg))
            pg.locator('#modal-root .ag-sheet .target-row[data-pkg] .u0 .switch').first.click()
            rerender_mid_flight(pg, pkg0, 300)
            mid = pg.evaluate(LIVE_SW_JS, [pkg0, 'u0'])
            sent = [c for c in cmds(pg)[n0:] if "'targets' 'set'" in c]
            check('R1 M1 mid-flight: re-rendered live switch shows the optimistic value and stays locked',
                  mid is not None and mid['checked'] == want and mid['disabled'] and len(sent) == 1, {'pkg': pkg0, 'before': b0, 'mid': mid, 'sent': sent})
            wait_unbusy(pg, pkg0)
            pg.wait_for_timeout(200)
            fin = pg.evaluate(LIVE_SW_JS, [pkg0, 'u0'])
            st3 = pg.evaluate(STATE3_JS, [pkg0, 'u0'])
            check('R1 M1 final: live aria-checked == KM.S.ag == mock == toggled value, switch enabled',
                  fin is not None and fin['checked'] == want and st3['model'] == (not b0) and st3['mock'] == (not b0) and not fin['disabled'] and fin['live'],
                  {'final': fin, 'state': st3, 'want': want})
            reset_hooks(pg)

            # R1b: same on an error reply, other row
            pkg1 = pg.evaluate("document.querySelectorAll('#modal-root .ag-sheet .target-row[data-pkg]')[1].dataset.pkg")
            b1 = pg.evaluate(LIVE_SW_JS, [pkg1, 'u0'])['checked'] == 'true'
            pg.evaluate("""() => { window.__mockState.delays = {"'targets' 'set'": 600}; window.__mockState.failOn = {"'targets' 'set'": 'E_BUSY'}; return 1 }""")
            pg.locator('#modal-root .ag-sheet .target-row[data-pkg]').nth(1).locator('.u0 .switch').click()
            rerender_mid_flight(pg, pkg1, 200)
            mid = pg.evaluate(LIVE_SW_JS, [pkg1, 'u0'])
            wait_unbusy(pg, pkg1)
            pg.wait_for_timeout(200)
            fin = pg.evaluate(LIVE_SW_JS, [pkg1, 'u0'])
            st3 = pg.evaluate(STATE3_JS, [pkg1, 'u0'])
            errbox = pg.evaluate("(() => { const e = document.querySelector('#modal-root .ag-sec[data-sec=targets] > .alert'); return e && !e.hidden ? e.innerText : null; })()")
            bstr = 'true' if b1 else 'false'
            check('R1b M1 error: locked mid-flight, then live == KM.S.ag == mock == pre-toggle value, targets error shown',
                  mid is not None and mid['disabled'] and fin is not None and fin['checked'] == bstr and st3['model'] == b1 and st3['mock'] == b1 and not fin['disabled'] and bool(errbox) and 'E_BUSY' in errbox,
                  {'pkg': pkg1, 'before': b1, 'mid': mid, 'final': fin, 'state': st3, 'err': errbox})
        except Exception as e:
            aborted('R1', e)
        reset_hooks(pg)
        check('R1: zero console/page errors', errs_now() == e0, (console_errors[e0[0]:], page_errors[e0[1]:]))

        # R2 - M2 refresh requested during an in-flight poll is coalesced, stale reply not painted
        pg = fresh(390, 844, 'R2 M2 coalesced refresh')
        e0 = errs_now()
        try:
            pg.wait_for_timeout(300)
            pg.evaluate("""() => { window.__mockState.delays = {"'list'": 1500}; return 1 }""")
            n0 = len(cmds(pg))
            pg.evaluate("() => { KM.pollNow(); return 1 }")
            pg.wait_for_timeout(150)
            pg.evaluate("""() => { window.__samp = []; window.__sampT = setInterval(() => {
              const s = document.querySelector('.card[data-id=sim-monitor] .state'); window.__samp.push(s ? s.textContent.trim().toUpperCase() : '?'); }, 25); return 1 }""")
            pg.click('.card[data-id=sim-monitor] [data-act=start]')
            pg.evaluate("() => { KM.daemons.load(true); KM.daemons.load(true); return 1 }")
            ok_run = True
            try:
                waitfn(pg, "(() => { const s = document.querySelector('.card[data-id=sim-monitor] .state'); return !!s && s.dataset.s === 'running'; })()", timeout=6000)
            except TimeoutError:
                ok_run = False
            pg.wait_for_timeout(300)
            pg.evaluate("() => { clearInterval(window.__sampT); return 1 }")
            samp = pg.evaluate('window.__samp')
            prim = pg.evaluate("(() => { const c = document.querySelector('.card[data-id=sim-monitor]'); const b = c && (c.querySelector('.btn.primary[data-act]') || c.querySelector('[data-act=stop],[data-act=start]')); return b ? b.getAttribute('data-act') : null; })()")
            cm = cmds(pg)[n0:]
            ts = pg.evaluate('window.__cmdT')[n0:]
            li = [i for i, c in enumerate(cm) if "'list'" in c]
            t_first = ts[li[0]] if li else 0
            in_flight = sum(1 for i in li[1:] if ts[i] < t_first + 1490)
            follow = sum(1 for i in li[1:] if t_first + 1490 <= ts[i] <= t_first + 1700)
            check('R2 M2 final: sim-monitor RUNNING, primary action is stop', ok_run and prim == 'stop', {'running': ok_run, 'primary': prim, 'tail': samp[-3:]})
            first_s = next((i for i, x in enumerate(samp) if 'STARTING' in x), None)
            stopped_after = [x for x in samp[first_s:]] if first_s is not None else []
            check('R2 M2 no STOPPED sample after the first STARTING… sample (stale reply not painted)',
                  first_s is not None and not any('STOPPED' in x for x in stopped_after), {'first_starting': first_s, 'samples': len(samp), 'distinct': sorted(set(samp))})
            check('R2 M2 bound: 0 list calls during the flight, exactly 1 coalesced follow-up, <= 3 total',
                  len(li) >= 1 and in_flight == 0 and follow == 1 and len(li) <= 3,
                  {'list_total': len(li), 'in_flight': in_flight, 'follow_ups_200ms': follow, 'offsets_ms': [round(ts[i] - t_first) for i in li]})
        except Exception as e:
            aborted('R2', e)
        reset_hooks(pg)
        check('R2: zero console/page errors', errs_now() == e0, (console_errors[e0[0]:], page_errors[e0[1]:]))

        # R3 - M3 number fields: only Enter/Save commit; Escape / X discard
        pg = fresh(390, 844, 'R3 M3 number fields')
        e0 = errs_now()
        def ag_sets(cm):
            return [c for c in cm if "'appguard' 'set'" in c]
        try:
            open_ag(pg)
            cfg0 = pg.evaluate('window.__mockState.config.interval_s')
            n0 = len(cmds(pg))
            pg.click('.ag-sheet [data-ag-num=interval]')
            pg.fill('.ag-sheet [data-ag-num=interval]', '999')
            pg.keyboard.press('Escape')
            pg.wait_for_timeout(400)
            closed = pg.locator('#modal-root .modal').count() == 0
            sets = ag_sets(cmds(pg)[n0:])
            cfg1 = pg.evaluate('window.__mockState.config.interval_s')
            open_ag(pg)
            shown = pg.input_value('.ag-sheet [data-ag-num=interval]')
            check('R3a M3 Escape after typing Interval 999: sheet closed, no appguard set, config unchanged, reopen shows old value',
                  closed and not sets and cfg1 == cfg0 and shown == str(cfg0), {'closed': closed, 'sets': sets, 'cfg': (cfg0, cfg1), 'reopen': shown})

            cd0 = pg.evaluate('window.__mockState.config.cooldown_s')
            n0 = len(cmds(pg))
            pg.click('.ag-sheet [data-ag-num=cooldown]')
            pg.fill('.ag-sheet [data-ag-num=cooldown]', '5')
            pg.click('#modal-root .modal-head [aria-label=Close]')
            pg.wait_for_timeout(400)
            closed = pg.locator('#modal-root .modal').count() == 0
            sets = ag_sets(cmds(pg)[n0:])
            cd1 = pg.evaluate('window.__mockState.config.cooldown_s')
            check('R3b M3 X-close after typing Default cooldown 5: no appguard set, cooldown unchanged',
                  closed and not sets and cd1 == cd0, {'closed': closed, 'sets': sets, 'cooldown': (cd0, cd1)})

            open_ag(pg)
            n0 = len(cmds(pg))
            ci = pg.locator('#modal-root .ag-sheet .target-row[data-pkg]').first.locator('input')
            ci.click()
            ci.fill('77')
            pg.keyboard.press('Escape')
            pg.wait_for_timeout(400)
            bad = [c for c in cmds(pg)[n0:] if "'targets' 'set'" in c and 'cooldown=77' in c]
            check('R3c M3 guard: Escape after typing a target cooldown sends no targets set cooldown=77', not bad and pg.locator('#modal-root .modal').count() == 0, bad)

            # R3c-X (loop 2, M-1): X-close after typing a per-app cooldown commits nothing
            open_ag(pg)
            r3pkg = pg.evaluate("document.querySelector('#modal-root .ag-sheet .target-row[data-pkg]').dataset.pkg")
            r3old = pg.evaluate('(p) => window.__mockState.targets.find(x => x.pkg === p).cooldown_s', r3pkg)
            n0 = len(cmds(pg))
            ci = pg.locator('#modal-root .ag-sheet .target-row[data-pkg]').first.locator('input')
            ci.click()
            ci.fill('77')
            pg.click('#modal-root .modal-head [aria-label=Close]')
            pg.wait_for_timeout(400)
            bad = [c for c in cmds(pg)[n0:] if "'targets' 'set'" in c and 'cooldown=' in c]
            r3now = pg.evaluate('(p) => window.__mockState.targets.find(x => x.pkg === p).cooldown_s', r3pkg)
            open_ag(pg)
            shown = pg.locator('#modal-root .ag-sheet .target-row[data-pkg]').first.locator('input').input_value()
            want = '' if r3old is None else str(r3old)
            check('R3c-X M-1 X-close after typing target cooldown 77: no targets set cooldown=, mock unchanged, reopen shows old value',
                  not bad and r3now == r3old and shown == want, {'pkg': r3pkg, 'sent': bad, 'mock': (r3old, r3now), 'reopen': shown})
            pg.keyboard.press('Escape'); pg.wait_for_timeout(200)

            open_ag(pg)
            n0 = len(cmds(pg))
            pg.click('.ag-sheet [data-ag-num=interval]')
            pg.fill('.ag-sheet [data-ag-num=interval]', '120')
            cue = pg.evaluate("""(() => { const i = document.querySelector('.ag-sheet [data-ag-num=interval]'); const f = i.closest('.field');
              return {hint: f.querySelector('.hint').textContent, primary: f.querySelector('.btn').classList.contains('primary')}; })()""")
            check('R3d unsaved cue: hint says Unsaved and Save turns primary before commit', 'Unsaved' in cue['hint'] and cue['primary'], cue)
            pg.locator('.ag-sheet [data-ag-num=interval]').locator('xpath=..').locator('button').click()
            pg.wait_for_timeout(400)
            cm = ' || '.join(cmds(pg)[n0:])
            cfg2 = pg.evaluate('window.__mockState.config.interval_s')
            cue2 = pg.evaluate("""(() => { const f = document.querySelector('.ag-sheet [data-ag-num=interval]').closest('.field');
              return {hint: f.querySelector('.hint').textContent, primary: f.querySelector('.btn').classList.contains('primary')}; })()""")
            check('R3d positive: Interval 120 + Save click sends set interval 120 and persists', "'set' 'interval' '120'" in cm and cfg2 == 120, {'cmds': cm[:200], 'cfg': cfg2, 'cue_after': cue2})
            pg.keyboard.press('Escape'); pg.wait_for_timeout(200)
        except Exception as e:
            aborted('R3', e)
        reset_hooks(pg)
        check('R3: zero console/page errors', errs_now() == e0, (console_errors[e0[0]:], page_errors[e0[1]:]))

        # R3c-backdrop / R3c-Enter (loop 2, M-1): backdrop close commits nothing, Enter commits once
        pg = fresh(1280, 800, 'R3c M-1 backdrop/Enter')
        e0 = errs_now()
        try:
            open_ag(pg)
            r3pkg = pg.evaluate("document.querySelector('#modal-root .ag-sheet .target-row[data-pkg]').dataset.pkg")
            r3old = pg.evaluate('(p) => window.__mockState.targets.find(x => x.pkg === p).cooldown_s', r3pkg)
            n0 = len(cmds(pg))
            ci = pg.locator('#modal-root .ag-sheet .target-row[data-pkg]').first.locator('input')
            ci.click()
            ci.fill('55')
            onback = pg.evaluate("(() => { const e = document.elementFromPoint(5, 5); return !!(e && e.closest('.modal-backdrop')); })()")
            pg.mouse.click(5, 5)
            pg.wait_for_timeout(400)
            closed = pg.locator('#modal-root .modal').count() == 0
            bad = [c for c in cmds(pg)[n0:] if "'targets' 'set'" in c and 'cooldown=' in c]
            r3now = pg.evaluate('(p) => window.__mockState.targets.find(x => x.pkg === p).cooldown_s', r3pkg)
            open_ag(pg)
            shown = pg.locator('#modal-root .ag-sheet .target-row[data-pkg]').first.locator('input').input_value()
            want = '' if r3old is None else str(r3old)
            check('R3c-backdrop M-1 backdrop close after typing target cooldown 55: no targets set cooldown=, mock unchanged, reopen shows old value',
                  onback and closed and not bad and r3now == r3old and shown == want,
                  {'pkg': r3pkg, 'on_backdrop': onback, 'closed': closed, 'sent': bad, 'mock': (r3old, r3now), 'reopen': shown})

            n0 = len(cmds(pg))
            ci = pg.locator('#modal-root .ag-sheet .target-row[data-pkg]').first.locator('input')
            ci.click()
            ci.fill('77')
            pg.keyboard.press('Enter')
            pg.wait_for_timeout(400)
            sent = [c for c in cmds(pg)[n0:] if "'targets' 'set'" in c and 'cooldown=' in c]
            r3now = pg.evaluate('(p) => window.__mockState.targets.find(x => x.pkg === p).cooldown_s', r3pkg)
            check('R3c-Enter M-1 positive: Enter after typing 77 sends exactly one targets set cooldown=77, mock stores 77',
                  len(sent) == 1 and 'cooldown=77' in sent[0] and r3now == 77, {'sent': sent, 'mock': r3now})
            pg.keyboard.press('Escape'); pg.wait_for_timeout(200)
        except Exception as e:
            aborted('R3c-bd', e)
        reset_hooks(pg)
        check('R3c-bd: zero console/page errors', errs_now() == e0, (console_errors[e0[0]:], page_errors[e0[1]:]))

        # R4 - E1 initial focus never lands on a disabled control
        pg = fresh(390, 844, 'R4 E1 initial focus')
        e0 = errs_now()
        try:
            pg.click(GEAR)
            pg.wait_for_timeout(300)
            af = pg.evaluate("""(() => { const a = document.activeElement; return {inPanel: !!(a && a.closest('#modal-root .modal-panel')), disabled: !!(a && a.disabled),
              tag: a ? a.tagName : null, label: a ? (a.getAttribute('aria-label') || a.getAttribute('data-ag-act') || a.getAttribute('data-act') || a.innerText.slice(0, 20)) : null}; })()""")
            check('R4 E1 gear click: initial focus inside .modal-panel and not disabled', af['inPanel'] and not af['disabled'], af)
            pg.keyboard.press('Escape'); pg.wait_for_timeout(200)
        except Exception as e:
            aborted('R4', e)
        check('R4: zero console/page errors', errs_now() == e0, (console_errors[e0[0]:], page_errors[e0[1]:]))

        # R5 - E2 Never add via Enter: rejected call shows the error, no unhandled rejection
        pg = fresh(390, 844, 'R5 E2 never Enter')
        e0 = errs_now()
        try:
            open_ag(pg)
            pg.evaluate("""() => { window.__mockState.failOn = {"'never' 'add'": 'E_BUSY'}; return 1 }""")
            pg.fill('.ag-sheet [data-ag-never]', 'com.demo.x')
            pg.press('.ag-sheet [data-ag-never]', 'Enter')
            pg.wait_for_timeout(400)
            eb = pg.evaluate("(() => { const e = document.querySelector('#modal-root .ag-sec[data-sec=never] > .alert'); return e && !e.hidden ? e.innerText : null; })()")
            check('R5 E2 Never Enter rejected: error box shows E_BUSY, no new pageerror', bool(eb) and 'E_BUSY' in eb and len(page_errors) == e0[1], {'err': eb, 'page_errors': page_errors[e0[1]:]})
        except Exception as e:
            aborted('R5', e)
        reset_hooks(pg)
        check('R5: zero console/page errors', errs_now() == e0, (console_errors[e0[0]:], page_errors[e0[1]:]))

        # R6 - E4 picker on an existing target upserts via targets set
        pg = fresh(390, 844, 'R6 E4 picker upsert')
        e0 = errs_now()
        try:
            pg.evaluate("() => { const t = window.__mockState.targets[0]; t.u0 = true; t.u999 = false; window.__mockState.packages['999'].push(t.pkg); return 1 }")
            open_ag(pg)
            pkg0 = pg.evaluate('window.__mockState.targets[0].pkg')
            pg.click('.ag-sheet [data-ag-act=picker-target]')
            pg.wait_for_selector('.ag-picker .picker-row', timeout=3000)
            pg.click('.ag-picker .segmented button[data-user="999"]')
            pg.wait_for_selector('.ag-picker .picker-row[data-pkg="%s"]' % pkg0, timeout=3000)
            n0 = len(cmds(pg))
            pg.click('.ag-picker .picker-row[data-pkg="%s"]' % pkg0)
            pg.wait_for_timeout(500)
            cm = cmds(pg)[n0:]
            mk = pg.evaluate("(p) => { const t = window.__mockState.targets.find(x => x.pkg === p); return [t.u0, t.u999]; }", pkg0)
            perr = pg.evaluate("(() => { const e = document.querySelector('.ag-picker .alert'); return e && !e.hidden ? e.innerText : null; })()")
            setc = [c for c in cm if ("'targets' 'set' '%s'" % pkg0) in c and 'u0=1' in c and 'u999=1' in c]
            addc = [c for c in cm if ("'targets' 'add' '%s'" % pkg0) in c]
            check('R6 E4 picker U999 on existing target -> targets set u0=1 u999=1 (no add), mock both true, no picker error',
                  setc and not addc and mk == [True, True] and not perr and pg.locator('.ag-picker').count() == 0, {'cmds': cm, 'mock': mk, 'picker_err': perr})
        except Exception as e:
            aborted('R6', e)
        reset_hooks(pg)
        check('R6: zero console/page errors', errs_now() == e0, (console_errors[e0[0]:], page_errors[e0[1]:]))

        # R7 - E5 first-load skeleton
        pg = fresh(390, 844, 'R7 E5 skeleton', wait_cards=False, pre_js="""window.__mockState.delays = {"'list'": 1500};""")
        e0 = errs_now()
        try:
            pg.wait_for_timeout(300)
            sk = pg.evaluate("({n: document.querySelectorAll('#daemon-list .skeleton').length, count: (document.getElementById('daemon-count').textContent || '').trim(), children: document.getElementById('daemon-list').children.length})")
            check('R7 E5 first load paints 3 skeletons and count "loading"', sk['n'] == 3 and sk['count'] == 'loading', sk)
            reset_hooks(pg)
            pg.wait_for_selector('#daemon-list .card', timeout=5000)
            check('R7 E5 cards replace the skeleton', pg.locator('#daemon-list .card').count() >= 6 and pg.locator('#daemon-list .skeleton').count() == 0, pg.locator('#daemon-list .card').count())
        except Exception as e:
            aborted('R7', e)
        reset_hooks(pg)
        check('R7: zero console/page errors', errs_now() == e0, (console_errors[e0[0]:], page_errors[e0[1]:]))

        # R8 - E6 picker error cleared on success, E7 stale picker replies ignored
        pg = fresh(390, 844, 'R8 E6/E7 picker')
        e0 = errs_now()
        PERR = "(() => { const e = document.querySelector('.ag-picker .alert'); return e && !e.hidden ? e.innerText : null; })()"
        try:
            open_ag(pg)
            pg.evaluate("""() => { window.__mockState.failOn = {"'appguard' 'packages'": 'E_BUSY'}; return 1 }""")
            pg.click('.ag-sheet [data-ag-act=picker-target]')
            waitfn(pg, PERR, timeout=3000)
            e1 = pg.evaluate(PERR)
            pg.evaluate("() => { window.__mockState.failOn = {}; return 1 }")
            pg.fill('.ag-picker input[type=search]', 'demo')
            pg.wait_for_selector('.ag-picker .picker-row', timeout=3000)
            pg.wait_for_timeout(150)
            e2 = pg.evaluate(PERR)
            check('R8 E6 picker error shown on failure, hidden after a successful search', bool(e1) and 'E_BUSY' in e1 and e2 is None, {'err_before': e1, 'err_after': e2})
            pg.evaluate("""() => { window.__mockState.delays = {"'packages'": 900}; return 1 }""")
            n0 = len(cmds(pg))
            pg.fill('.ag-picker input[type=search]', 'app0')
            pg.wait_for_timeout(350)
            pg.evaluate("() => { window.__mockState.delays = {}; return 1 }")
            pg.fill('.ag-picker input[type=search]', 'extra')
            pg.wait_for_timeout(1300)
            rows = pg.eval_on_selector_all('.ag-picker .picker-row', 'els => els.map(e => e.dataset.pkg)')
            reqs = [c for c in cmds(pg)[n0:] if "'packages'" in c]
            check('R8 E7 slow stale reply (app0) does not overwrite the newer query (extra)',
                  len(reqs) >= 2 and rows == ['com.demo.extra'] and pg.evaluate(PERR) is None, {'rows': rows[:5], 'n_rows': len(rows), 'reqs': reqs})
            pg.keyboard.press('Escape'); pg.wait_for_timeout(150)
        except Exception as e:
            aborted('R8', e)
        reset_hooks(pg)
        check('R8: zero console/page errors', errs_now() == e0, (console_errors[e0[0]:], page_errors[e0[1]:]))

        # R9 - L1 a stale failure must not revert a newer successful write
        pg = fresh(390, 844, 'R9 L1')
        e0 = errs_now()
        try:
            open_ag(pg)
            pkg0 = pg.evaluate("document.querySelector('#modal-root .ag-sheet .target-row[data-pkg]').dataset.pkg")
            b0 = pg.evaluate(LIVE_SW_JS, [pkg0, 'u0'])['checked'] == 'true'
            c0 = pg.evaluate(LIVE_SW_JS, [pkg0, 'u999'])['checked'] == 'true'
            key = "'%s' 'u0=%d' 'u999=%d'" % (pkg0, 0 if b0 else 1, 1 if c0 else 0)
            pg.evaluate("(k) => { window.__mockState.failOn = {[k]: 'E_BUSY'}; window.__mockState.delays = {[k]: 2000}; return 1 }", key)
            n0 = len(cmds(pg))
            pg.locator('#modal-root .ag-sheet .target-row[data-pkg] .u0 .switch').first.click()
            pg.wait_for_timeout(100)
            pg.keyboard.press('Escape'); pg.wait_for_timeout(250)
            open_ag(pg)
            pg.locator('#modal-root .ag-sheet .target-row[data-pkg]').first.locator('.u999 .switch').click()
            pg.wait_for_timeout(2600)
            rerender_mid_flight(pg, pkg0, 150)
            fin = pg.evaluate(LIVE_SW_JS, [pkg0, 'u999'])
            st3 = pg.evaluate(STATE3_JS, [pkg0, 'u999'])
            sent = [c for c in cmds(pg)[n0:] if "'targets' 'set'" in c]
            want = 'false' if c0 else 'true'
            check('R9 L1 stale E_BUSY reply after a newer U999 write: KM.S.ag u999 == mock == toggled, live switch matches',
                  fin is not None and st3['model'] == (not c0) and st3['mock'] == (not c0) and fin['checked'] == want,
                  {'pkg': pkg0, 'b0': b0, 'c0': c0, 'key': key, 'final': fin, 'state': st3, 'sent': sent})
            pg.keyboard.press('Escape'); pg.wait_for_timeout(150)
        except Exception as e:
            aborted('R9', e)
        reset_hooks(pg)
        check('R9: zero console/page errors', errs_now() == e0, (console_errors[e0[0]:], page_errors[e0[1]:]))

        # R10 - L2 cooldown input locked while the row's targets set is in flight
        pg = fresh(390, 844, 'R10 L2')
        e0 = errs_now()
        CI_DIS = "(p) => { const r = Array.from(document.querySelectorAll('#modal-root .ag-sec[data-sec=targets] .target-row')).find(x => x.dataset.pkg === p); const i = r && r.querySelector('input[data-ag-cool]'); return i ? i.disabled : null; }"
        try:
            open_ag(pg)
            pkg0 = pg.evaluate("document.querySelector('#modal-root .ag-sheet .target-row[data-pkg]').dataset.pkg")
            pg.evaluate("""() => { window.__mockState.delays = {"'targets' 'set'": 1000}; return 1 }""")
            pg.locator('#modal-root .ag-sheet .target-row[data-pkg] .u0 .switch').first.click()
            pg.wait_for_timeout(100)
            mid = pg.evaluate(CI_DIS, pkg0)
            wait_unbusy(pg, pkg0)
            after = pg.evaluate(CI_DIS, pkg0)
            check('R10 L2 per-app cooldown input disabled while targets set is in flight, enabled after', mid is True and after is False, {'pkg': pkg0, 'mid': mid, 'after': after})
            reset_hooks(pg)
            n0 = len(cmds(pg))
            ci = pg.locator('#modal-root .ag-sheet .target-row[data-pkg]').first.locator('input')
            ci.click()
            ci.fill('77')
            pg.keyboard.press('Enter')
            pg.wait_for_timeout(400)
            sent = [c for c in cmds(pg)[n0:] if "'targets' 'set'" in c and 'cooldown=' in c]
            cs = pg.evaluate('(p) => window.__mockState.targets.find(x => x.pkg === p).cooldown_s', pkg0)
            check('R10 L2 then 77 + Enter sends one targets set cooldown=77, mock stores 77', len(sent) == 1 and 'cooldown=77' in sent[0] and cs == 77, {'sent': sent, 'mock': cs})
            pg.keyboard.press('Escape'); pg.wait_for_timeout(150)
        except Exception as e:
            aborted('R10', e)
        reset_hooks(pg)
        check('R10: zero console/page errors', errs_now() == e0, (console_errors[e0[0]:], page_errors[e0[1]:]))

        # R11 - L3 tab activation joins the in-flight list instead of queueing a follow-up
        pg = fresh(390, 844, 'R11 L3', wait_cards=False, pre_js="window.__mockState.delays = {\"'list'\": 1000};")
        e0 = errs_now()
        try:
            waitfn(pg, "window.__cmds.some(c => c.indexOf(\"'list'\") >= 0)", timeout=3000)
            for _ in range(3):
                pg.click('#tab-logs')
                pg.wait_for_timeout(40)
                pg.click('#tab-daemons')
                pg.wait_for_timeout(40)
            cm = cmds(pg)
            ts = pg.evaluate('window.__cmdT')
            li = [i for i, c in enumerate(cm) if "'list'" in c]
            t_first = ts[li[0]]
            pg.evaluate("(t) => new Promise(r => { const f = () => performance.now() >= t ? r(1) : setTimeout(f, 10); f(); })", t_first + 1400)
            cards = pg.evaluate("document.querySelectorAll('#daemon-list .card').length")
            pg.wait_for_timeout(1500)
            cm = cmds(pg)
            ts = pg.evaluate('window.__cmdT')
            li = [i for i, c in enumerate(cm) if "'list'" in c]
            early = sum(1 for i in li if ts[i] < t_first + 1300)
            check('R11 L3 3x Logs->Daemons during the first list: 1 list call in 1.3 s, cards by +1.4 s',
                  early == 1 and cards > 0, {'early_list_calls': early, 'cards_at_1400': cards, 'offsets_ms': [round(ts[i] - t_first) for i in li]})
        except Exception as e:
            aborted('R11', e)
        reset_hooks(pg)
        check('R11: zero console/page errors', errs_now() == e0, (console_errors[e0[0]:], page_errors[e0[1]:]))

        # R12 - L5 Tab trap wraps when focus sits on the panel fallback
        pg = fresh(390, 844, 'R12 L5')
        e0 = errs_now()
        FOC = "(() => { const p = KM.S.modal && KM.S.modal.panel, a = document.activeElement; return {inside: !!(p && p.contains(a)), isPanel: a === p, tag: a ? a.tagName : null}; })()"
        try:
            open_ag(pg)
            pg.wait_for_timeout(100)
            pg.evaluate("() => { KM.S.modal.panel.focus(); return 1 }")
            pg.keyboard.press('Shift+Tab')
            f1 = pg.evaluate(FOC)
            pg.evaluate("() => { KM.S.modal.panel.focus(); return 1 }")
            pg.keyboard.press('Tab')
            f2 = pg.evaluate(FOC)
            check('R12 L5 Shift+Tab from the panel fallback lands on a control inside the dialog', f1['inside'] and not f1['isPanel'], f1)
            check('R12 L5 Tab from the panel fallback lands on a control inside the dialog', f2['inside'] and not f2['isPanel'], f2)
            pg.keyboard.press('Escape'); pg.wait_for_timeout(150)
        except Exception as e:
            aborted('R12', e)
        reset_hooks(pg)
        check('R12: zero console/page errors', errs_now() == e0, (console_errors[e0[0]:], page_errors[e0[1]:]))

        # ---------------------------------------------------------------- 10. ten viewports
        pg = fresh(1280, 800, 'C10 viewports')
        pg.wait_for_timeout(300)
        for w, h, expect in VIEWPORTS:
            pg.evaluate("KM.activate('daemons', false)")
            pg.set_viewport_size({'width': w, 'height': h})
            pg.wait_for_timeout(250)
            overflow = pg.evaluate('document.documentElement.scrollWidth - window.innerWidth')
            layout = pg.evaluate("getComputedStyle(document.documentElement).getPropertyValue('--km-layout').trim()")
            edge = pg.evaluate(EDGE_JS, None)
            cols = pg.evaluate("getComputedStyle(document.querySelector('#daemon-list')).gridTemplateColumns.split(' ').length")
            bar = pg.evaluate("getComputedStyle(document.getElementById('tabs')).position")
            exp_layout = 'phone' if w < 600 else ('tablet' if w < 1000 else 'desktop')
            exp_cols = 1 if w < 600 else (2 if w < 1000 else 3)
            exp_fixed = w < 600
            shot = EVID / f'{w}x{h}.png'
            pg.screenshot(path=str(shot), full_page=False)
            tabs_ov = {}
            for t in ('logs', 'about', 'daemons'):
                pg.evaluate("KM.activate('%s', false)" % t)
                pg.wait_for_timeout(150)
                tabs_ov[t] = [pg.evaluate('document.documentElement.scrollWidth - window.innerWidth'), pg.evaluate(EDGE_JS, None)['n']]
            ok = (overflow == 0 and edge['n'] == 0 and layout == exp_layout == expect and cols == exp_cols and (bar == 'fixed') == exp_fixed)
            row = {'viewport': f'{w}x{h}', 'overflow': overflow, 'edge': edge['n'], 'layout': layout, 'expected': exp_layout, 'cols': cols, 'exp_cols': exp_cols, 'tabbar': bar, 'shot': shot.name, 'tabs_overflow': tabs_ov, 'ok': ok}
            vp_rows.append(row)
            det = {k: row[k] for k in ('overflow', 'edge', 'layout', 'cols', 'tabbar')}
            if edge['n']:
                det['offenders'] = edge['list']
            check(f'C10 {w}x{h}: overflow={overflow} edge={edge["n"]} layout={layout} cols={cols} tabbar={bar}', ok, det)
            tab_bad = {t: v for t, v in tabs_ov.items() if v[0] != 0 or v[1] != 0}
            check(f'C10 {w}x{h}: Logs/About/Daemons panels no overflow / edge-crossers', not tab_bad, tabs_ov)

        sect['name'] = 'global'
        if state['ctx']:
            state['ctx'].close()
        browser.close()

    httpd.shutdown()

    # ---------------------------------------------------------------- 12. backend gate + node --check
    sect['name'] = 'C12 backend'
    bg = backend_gate()
    check('C12 backend: >= %d passed and failure-name set == baseline' % BACKEND_MIN, bg['ok'], bg.get('detail'))
    nodes = []
    for f in sorted((ROOT / 'js').glob('*.js')):
        r = subprocess.run(['node', '--check', str(f)], capture_output=True, text=True)
        nodes.append((f.name, r.returncode, r.stderr.strip()[:120]))
    check('C12 node --check all module/webroot/js/*.js (%d files)' % len(nodes), nodes and all(x[1] == 0 for x in nodes), nodes)

    sect['name'] = 'global'
    unexpected_warns = [w for w in console_warns if not w.startswith('[C9 error boundary]')]
    check('C11 zero console error across the whole run', len(console_errors) == 0, console_errors[:5])
    check('C11 zero pageerror across the whole run', len(page_errors) == 0, page_errors[:5])
    check('C11 console.warn only from the injected boundary fault (C9)', not unexpected_warns, unexpected_warns[:5])

    npass = sum(1 for r in results if r['ok'])
    nfail = len(results) - npass
    report = {
        'ok': nfail == 0,
        'generated': time.strftime('%Y-%m-%dT%H:%M:%S%z'),
        'passed': npass, 'failed': nfail, 'total': len(results),
        'results': results,
        'console_errors': console_errors,
        'page_errors': page_errors,
        'console_warnings': console_warns,
        'viewports': vp_rows,
        'extra_info': extra_info,
        'backend': bg,
        'screenshots': str(EVID),
    }
    (EVID / 'report.json').write_text(json.dumps(report, indent=2))

    L = ['# KonaManager night QA summary', '',
         f'Generated {report["generated"]}. Overall: **{"PASS" if report["ok"] else "FAIL"}** ({npass} passed, {nfail} failed, {len(results)} checks).', '',
         f'Console errors: {len(console_errors)}; pageerrors: {len(page_errors)}; console warnings: {len(console_warns)} (expected: only the C9 injected fault).', '',
         '## Ten viewports', '',
         '| Viewport | scrollW-innerW | edge-crossers | layout (expected) | cards cols | tab bar | Logs/About overflow (sw/edge) | result |',
         '|---|---|---|---|---|---|---|---|']
    for r in vp_rows:
        if 'layout' not in r:
            continue
        to = r['tabs_overflow']
        L.append(f"| {r['viewport']} | {r['overflow']} | {r['edge']} | {r['layout']} ({r['expected']}) | {r['cols']} (exp {r['exp_cols']}) | {r['tabbar']} | logs {to['logs'][0]}/{to['logs'][1]}, about {to['about'][0]}/{to['about'][1]} | {'PASS' if r['ok'] else 'FAIL'} |")
    L += ['', '## AppGuard sheet viewports', '', '| Shot | scrollW-innerW | edge-crossers | panel rect |', '|---|---|---|---|']
    for r in vp_rows:
        if 'layout' in r:
            continue
        L.append(f"| {r['name']}.png | {r['overflow']} | {r['edge']} | {r['panel']} |")
    L += ['', '## Backend', '', f"- {bg.get('detail')}",
          f"- gate: >= {BACKEND_MIN} passed and sorted failure-name set identical to baseline: **{'PASS' if bg['ok'] else 'FAIL'}**",
          f"- output file: {BACKEND_OUT}; baseline: {BACKEND_BASE}",
          '- node --check: ' + ', '.join(f"{a}={'ok' if b == 0 else 'FAIL'}" for a, b, _ in nodes), '',
          '## Checks', '', '| # | Result | Check | Measured |', '|---|---|---|---|']
    for i, r in enumerate(results, 1):
        d = str(r['detail']).replace('|', '/').replace('\n', ' ')
        if len(d) > 170:
            d = d[:167] + '...'
        L.append(f"| {i} | {'PASS' if r['ok'] else '**FAIL**'} | {r['name'].replace('|', '/')} | {d} |")
    fails = [r for r in results if not r['ok']]
    L += ['', '## Failures', '']
    if fails:
        for r in fails:
            L.append(f"- {r['name']}: {str(r['detail'])[:400]}")
    else:
        L.append('none')
    L += ['', '## Notes', '', f'- extra info: {json.dumps(extra_info)[:600]}', '']
    (EVID / 'SUMMARY.md').write_text('\n'.join(L))

    print('TOTAL:', npass, 'passed,', nfail, 'failed')
    return 0 if report['ok'] else 1


if __name__ == '__main__':
    sys.exit(main())
