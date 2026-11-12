#!/usr/bin/env python3
"""KonaManager WebUI QA: stateful KSUser bridge mock + 10 viewports."""
import functools
import http.server
import json
import os
import sys
import threading
import time
from pathlib import Path

from playwright.sync_api import sync_playwright

HERE = Path(__file__).resolve().parent
ROOT = Path(os.environ.get('KM_WEBROOT', HERE.parents[1] / 'module' / 'webroot'))
EVID = Path(os.environ.get('KM_EVID', HERE.parents[1] / 'tests' / 'evidence' / 'ui'))
MOCK = (HERE / 'mock.js').read_text()
PORT = int(os.environ.get('KM_QA_PORT', '8099'))
BASE = f'http://127.0.0.1:{PORT}/index.html'

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

class Quiet(http.server.SimpleHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

def main():
    EVID.mkdir(parents=True, exist_ok=True)
    handler = functools.partial(Quiet, directory=str(ROOT))
    httpd = http.server.ThreadingHTTPServer(('127.0.0.1', PORT), handler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()

    results = []
    console_errors = []
    page_errors = []
    mock_js = MOCK.replace('__STATE__', json.dumps(STATE, ensure_ascii=False))

    def check(name, cond, detail=''):
        results.append({'name': name, 'ok': bool(cond), 'detail': detail})
        print(('PASS ' if cond else 'FAIL ') + name + ((' :: ' + str(detail)) if detail and not cond else ''))
        return bool(cond)

    with sync_playwright() as p:
        browser = None
        for exe in ('/usr/bin/google-chrome', '/usr/bin/chromium', '/snap/bin/chromium', None):
            try:
                browser = p.chromium.launch(headless=True, executable_path=exe, args=['--no-sandbox', '--disable-dev-shm-usage']) if exe else p.chromium.launch(headless=True, args=['--no-sandbox'])
                break
            except Exception as e:
                last = e
        if not browser:
            print('browser launch failed:', last)
            return 1
        ctx = browser.new_context(viewport={'width': 1280, 'height': 800})
        page = ctx.new_page()
        page.on('console', lambda m: console_errors.append(m.text) if m.type == 'error' else None)
        page.on('pageerror', lambda e: page_errors.append(str(e)))
        page.add_init_script(mock_js)
        page.goto(BASE, wait_until='load')
        page.wait_for_selector('#daemon-list .card', timeout=5000)

        check('brand title', 'KonaManager' in page.title())
        check('daemon cards rendered', page.locator('#daemon-list .card').count() >= 6, page.locator('#daemon-list .card').count())
        check('connection chip ready', (page.locator('#conn-chip').inner_text() or '').strip() == 'ready')
        check('no horizontal overflow (desktop)', page.evaluate('document.documentElement.scrollWidth - window.innerWidth') == 0)

        # AppGuard + per-app switch
        page.click('#tab-appguard')
        page.wait_for_selector('#ag-target-rows .target-row', timeout=5000)
        check('AppGuard counts rendered', '33 targets' in page.locator('#ag-count').inner_text())
        before = page.evaluate('window.__cmds.length')
        page.locator('#ag-target-rows .target-row .u0').first.click()
        page.wait_for_timeout(400)
        cmds = page.evaluate('window.__cmds')
        check('target switch calls dm', any('appguard' in c and 'targets' in c and 'set' in c for c in cmds[before:]), cmds[before:])
        check('target switch persisted', page.locator('#ag-target-rows .target-row .u0').first.get_attribute('aria-checked') == 'false')

        # Dry run
        page.locator('#ag-actions button', has_text='Dry run once').click()
        page.wait_for_timeout(400)
        check('dry sweep result shown', 'candidates' in page.locator('#ag-actions').inner_text())

        # Install flow
        page.click('#tab-daemons')
        page.click('#add-daemon')
        page.wait_for_selector('#modal-root .modal-panel')
        page.locator('#modal-root .modal-body input.mono').nth(0).fill('https://example.com/demo.zip')
        page.locator('#modal-root .modal-body button', has_text='Stage package').click()
        page.wait_for_selector('#modal-root .modal-body .summary', timeout=5000)
        check('install review shows hook', 'runs as root' in page.locator('#modal-root .modal-body').inner_text())
        page.locator('#modal-root .modal-body .type-confirm input').fill('km-demo')
        page.locator('#modal-root .modal-foot button', has_text='Install').click()
        page.wait_for_selector('text=Installed km-demo', timeout=5000)
        check('install commit completed', any("'install'" in c and "'commit'" in c for c in page.evaluate('window.__cmds')))
        page.locator('#modal-root .modal-foot button', has_text='Done').click()
        page.wait_for_timeout(300)
        check('installed daemon card appears', page.locator('#daemon-list .card[data-id="km-demo"]').count() == 1)

        # Delete plan (do not confirm)
        page.locator('#daemon-list .card[data-id="km-demo"] [data-act="delete"]').click()
        page.wait_for_selector('#modal-root .type-confirm input', timeout=5000)
        check('delete plan shown', 'Removes' in page.locator('#modal-root .modal-body').inner_text())
        page.locator('#modal-root .modal-head .icon-btn').click()
        page.wait_for_timeout(200)

        # Create
        page.click('#add-daemon')
        page.locator('#modal-root .segmented button', has_text='Create').click()
        page.wait_for_selector('#modal-root .modal-body input')
        page.locator('#modal-root .modal-body input').nth(0).fill('QA Created')
        page.locator('#modal-root .modal-body input.mono').nth(0).fill('while :; do sleep 1; done')
        page.locator('#modal-root .modal-body button.btn.primary').click()
        page.wait_for_selector('text=Created km-qa-created', timeout=5000)
        check('create flow completed', 'create' in ' '.join(page.evaluate('window.__cmds')))
        page.locator('#modal-root .modal-foot button', has_text='Done').click()

        # Import
        page.click('#add-daemon')
        page.locator('#modal-root .segmented button', has_text='Import').click()
        page.wait_for_selector('#modal-root .import-row', timeout=5000)
        page.locator('#modal-root .import-row').first.click()
        page.wait_for_selector('#modal-root .modal-body input')
        page.locator('#modal-root .modal-body button.btn.primary').click()
        page.wait_for_selector('text=Imported', timeout=5000)
        check('import flow completed', 'import' in ' '.join(page.evaluate('window.__cmds')))
        page.locator('#modal-root .modal-foot button', has_text='Done').click()

        # Logs + About
        page.click('#tab-logs')
        page.click('#log-refresh')
        page.wait_for_timeout(400)
        check('logs rendered', 'mock log line' in page.locator('#log-output').inner_text())
        page.click('#tab-about')
        page.wait_for_timeout(500)
        check('about version rendered', 'dm version' in page.locator('#about-identity').inner_text())
        check('doctor rendered', 'SELinux' in page.locator('#about-doctor').inner_text())

        # Ten viewports
        page.evaluate("KM.activate('daemons', false)")
        page.wait_for_timeout(300)
        for w, h, expect in VIEWPORTS:
            page.set_viewport_size({'width': w, 'height': h})
            page.wait_for_timeout(220)
            overflow = page.evaluate('document.documentElement.scrollWidth - window.innerWidth')
            layout = page.evaluate("getComputedStyle(document.documentElement).getPropertyValue('--km-layout').trim()")
            off = page.evaluate("""() => {
              const els = document.querySelectorAll('.card,.panel-block,.section-head,.topbar-inner,.tabs,.card-actions');
              return Array.from(els).filter(el => {
                const r = el.getBoundingClientRect();
                return r.width > 0 && (r.right > window.innerWidth + 1 || r.left < -1);
              }).length;
            }""")
            cols = page.evaluate("getComputedStyle(document.querySelector('.cards')).gridTemplateColumns.split(' ').length")
            ok = overflow == 0 and off == 0 and layout == expect
            if w >= 1000: ok = ok and cols >= 3
            elif w >= 600: ok = ok and cols == 2
            else: ok = ok and cols == 1
            shot = EVID / f'{w}x{h}.png'
            page.screenshot(path=str(shot), full_page=False)
            check(f'{w}x{h} layout {expect} overflow={overflow} off={off} cols={cols}', ok, f'overflow={overflow} off={off} layout={layout} cols={cols}')

        # Mobile tab bar position
        page.set_viewport_size({'width': 390, 'height': 844})
        page.wait_for_timeout(150)
        bar = page.evaluate("() => { const s=getComputedStyle(document.querySelector('.tabs')); return {pos:s.position, bottom:s.bottom}; }")
        check('mobile bottom tab bar', bar['pos'] == 'fixed', bar)
        page.set_viewport_size({'width': 1280, 'height': 800})
        page.wait_for_timeout(150)
        bar = page.evaluate("() => getComputedStyle(document.querySelector('.tabs')).position")
        check('desktop tab bar top', bar != 'fixed', bar)

        ctx.close(); browser.close()

    httpd.shutdown()
    check('no console errors', len(console_errors) == 0, console_errors[:5])
    check('no page errors', len(page_errors) == 0, page_errors[:5])
    report = {
        'ok': all(r['ok'] for r in results),
        'results': results,
        'console_errors': console_errors,
        'page_errors': page_errors,
        'viewports': [f'{w}x{h}' for w, h, _ in VIEWPORTS],
        'screenshots': str(EVID),
    }
    (EVID / 'report.json').write_text(json.dumps(report, indent=2))
    print('TOTAL:', sum(1 for r in results if r['ok']), 'passed,', sum(1 for r in results if not r['ok']), 'failed')
    return 0 if report['ok'] else 1

if __name__ == '__main__':
    sys.exit(main())
