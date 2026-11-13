# KonaManager night QA summary

Generated 2026-11-13T06:54:09+0700. Overall: **PASS** (114 passed, 0 failed, 114 checks).

Console errors: 0; pageerrors: 0; console warnings: 1 (expected: only the C9 injected fault).

## Ten viewports

| Viewport | scrollW-innerW | edge-crossers | layout (expected) | cards cols | tab bar | Logs/About overflow (sw/edge) | result |
|---|---|---|---|---|---|---|---|
| 360x640 | 0 | 0 | phone (phone) | 1 (exp 1) | fixed | logs 0/0, about 0/0 | PASS |
| 390x844 | 0 | 0 | phone (phone) | 1 (exp 1) | fixed | logs 0/0, about 0/0 | PASS |
| 414x896 | 0 | 0 | phone (phone) | 1 (exp 1) | fixed | logs 0/0, about 0/0 | PASS |
| 768x1024 | 0 | 0 | tablet (tablet) | 2 (exp 2) | static | logs 0/0, about 0/0 | PASS |
| 820x1180 | 0 | 0 | tablet (tablet) | 2 (exp 2) | static | logs 0/0, about 0/0 | PASS |
| 1024x1366 | 0 | 0 | desktop (desktop) | 3 (exp 3) | static | logs 0/0, about 0/0 | PASS |
| 1280x800 | 0 | 0 | desktop (desktop) | 3 (exp 3) | static | logs 0/0, about 0/0 | PASS |
| 1440x900 | 0 | 0 | desktop (desktop) | 3 (exp 3) | static | logs 0/0, about 0/0 | PASS |
| 1920x1080 | 0 | 0 | desktop (desktop) | 3 (exp 3) | static | logs 0/0, about 0/0 | PASS |
| 1080x1080 | 0 | 0 | desktop (desktop) | 3 (exp 3) | static | logs 0/0, about 0/0 | PASS |

## AppGuard sheet viewports

| Shot | scrollW-innerW | edge-crossers | panel rect |
|---|---|---|---|
| ag-sheet-390x844.png | 0 | 0 | [0, 0, 390, 844] |
| ag-sheet-360x640.png | 0 | 0 | [0, 0, 360, 640] |
| ag-sheet-1280x800.png | 0 | 0 | [260, 40, 760, 720, 1280, 800] |

## Backend

- TOTAL: 596 passed, 42 failed; failed names 42; new=[]; fixed=[]; gate>=596
- gate: >= 596 passed and sorted failure-name set identical to baseline: **PASS**
- output file: /root/temp/konamanager-night/tmp/night-backend2.txt; baseline: /root/temp/konamanager-night/tmp/baseline-failed.txt
- node --check: add.js=ok, appguard.js=ok, core.js=ok, daemons.js=ok, misc.js=ok

## Checks

| # | Result | Check | Measured |
|---|---|---|---|
| 1 | PASS | brand title | KonaManager - Simple Daemon Manager |
| 2 | PASS | daemon cards rendered | 6 |
| 3 | PASS | connection chip ready |  |
| 4 | PASS | no horizontal overflow (desktop) |  |
| 5 | PASS | install review shows hook |  |
| 6 | PASS | install commit completed |  |
| 7 | PASS | installed daemon card appears |  |
| 8 | PASS | delete plan shown |  |
| 9 | PASS | create flow completed |  |
| 10 | PASS | import flow completed |  |
| 11 | PASS | logs rendered |  |
| 12 | PASS | about version rendered |  |
| 13 | PASS | doctor rendered |  |
| 14 | PASS | C1 exactly 3 [role=tab] Daemons/Logs/About | ['Daemons', 'Logs', 'About'] |
| 15 | PASS | C1 no #tab-appguard, #panel-appguard, [id^=ag-] outside #modal-root | {'tab': False, 'panel': False, 'ag': []} |
| 16 | PASS | C2 sheet role=dialog aria-modal=true title AppGuard | {'aria': 'true', 'ag': True, 'title': 'AppGuard', 'dialogs': 1} |
| 17 | PASS | C2 six sections Status/Settings/Run now/Targets/Never/Recent kills | ['Status', 'Settings', 'Run now', 'Targets', 'Never', 'Recent kills'] |
| 18 | PASS | C2 status shows running state, PID 17741 and uptime | Status / RUNNING / PID / 17741 / UPTIME / 1h 0m / 33 targets / 30 u0 / 3 u999 / 6 never / Start / Stop / Restart |
| 19 | PASS | C2 kills rows == 3 | 3 |
| 20 | PASS | C2 Start disabled, Stop/Restart enabled while running | ['start:disabled', 'stop:enabled', 'restart:enabled'] |
| 21 | PASS | C2 default cooldown input shows 300, interval 60 | ('300', '60') |
| 22 | PASS | C2 44x44 audit .ag-sheet @390x844 (main view) | {'n': 0, 'total': 156, 'bad': []} |
| 23 | PASS | C2 sheet 390x844 overflow=0 edge-crossers=0 full-screen | {'overflow': 0, 'edge': {'n': 0, 'list': []}, 'panel': [0, 0, 390, 844]} |
| 24 | PASS | C2 Restart issues dm restart appguard | ["/data/adb/modules/daemon-manager/bin/dm 'restart' 'appguard'", "/data/adb/modules/daemon-manager/bin/dm 'list'", "/data/adb/modules/daemon-manager/bin/dm 'appguard' ... |
| 25 | PASS | C2 Stop issues dm stop appguard and status shows stopped | (["/data/adb/modules/daemon-manager/bin/dm 'stop' 'appguard'", "/data/adb/modules/daemon-manager/bin/dm 'list'", "/data/adb/modules/daemon-manager/bin/dm 'appguard' 'g... |
| 26 | PASS | C2 Start issues dm start appguard and status shows running | ["/data/adb/modules/daemon-manager/bin/dm 'start' 'appguard'", "/data/adb/modules/daemon-manager/bin/dm 'list'", "/data/adb/modules/daemon-manager/bin/dm 'appguard' 'g... |
| 27 | PASS | C2 sheet still open after lifecycle actions (single dialog) |  |
| 28 | PASS | C2 interval set 90 command + persisted | {'interval_s': 90, 'cooldown_s': 450, 'dry_run': True} |
| 29 | PASS | C2 default cooldown set 450 command + persisted | {'interval_s': 90, 'cooldown_s': 450, 'dry_run': True} |
| 30 | PASS | C2 dry-run on/off commands + note | ({'interval_s': 90, 'cooldown_s': 450, 'dry_run': True}, {'interval_s': 90, 'cooldown_s': 450, 'dry_run': False}, True) |
| 31 | PASS | C2 Run once shows inline confirm strip (no nested dialog) | Run now Run once Dry run once Sends real am-kill requests. Confirm Cancel  Dry run writes the kill history but sends no  |
| 32 | PASS | C2 44x44 audit with confirm strip open | {'n': 0, 'total': 158, 'bad': []} |
| 33 | PASS | C2 Cancel sends no once command | [] |
| 34 | PASS | C2 Run once confirm -> appguard once WITHOUT --dry | ["/data/adb/modules/daemon-manager/bin/dm 'appguard' 'once'", "/data/adb/modules/daemon-manager/bin/dm 'appguard' 'kills' '50'"] |
| 35 | PASS | C2 Dry run once -> once --dry, result box shows candidates | (["/data/adb/modules/daemon-manager/bin/dm 'appguard' 'once' '--dry'", "/data/adb/modules/daemon-manager/bin/dm 'appguard' 'kills' '50'"], 'dry · candidates 2 · killed... |
| 36 | PASS | C2 U0 toggle: targets set command, aria-checked flips, same row node | (["/data/adb/modules/daemon-manager/bin/dm 'appguard' 'targets' 'set' 'com.demo.app00' 'u0=0' 'u999=0' 'cooldown=default'"], True, [False, False]) |
| 37 | PASS | C2 U999 toggle: targets set command, aria-checked flips, same row node | (["/data/adb/modules/daemon-manager/bin/dm 'appguard' 'targets' 'set' 'com.demo.app00' 'u0=0' 'u999=1' 'cooldown=default'"], True, [False, True]) |
| 38 | PASS | C2 per-app cooldown 120 -> targets set cooldown=120, persisted | (["/data/adb/modules/daemon-manager/bin/dm 'appguard' 'targets' 'set' 'com.demo.app01' 'u0=1' 'u999=0' 'cooldown=120'"], 120) |
| 39 | PASS | C2 picker (target) opens in-sheet, single dialog |  |
| 40 | PASS | C2 44x44 audit with picker open | {'n': 0, 'total': 41, 'bad': []} |
| 41 | PASS | C2 picker Back closes picker, sheet stays, focus returns to opener | picker-target |
| 42 | PASS | C2 picker target mode adds com.demo.extra (u0=1 u999=0) and row appears | ["/data/adb/modules/daemon-manager/bin/dm 'appguard' 'targets' 'add' 'com.demo.extra' 'u0=1' 'u999=0'"] |
| 43 | PASS | C2 picker never mode adds com.demo.ghost chip | ["/data/adb/modules/daemon-manager/bin/dm 'appguard' 'never' 'add' 'com.demo.ghost'"] |
| 44 | PASS | C2 never chip remove -> never rm, chip gone | ["/data/adb/modules/daemon-manager/bin/dm 'appguard' 'never' 'rm' 'com.demo.ghost'"] |
| 45 | PASS | C2 focus trap: Tab from last wraps to first, Shift+Tab from first wraps to last | {'trap': {'n': 159, 'first': 'Close', 'last': 'Done'}, 'fwd': {'inside': True, 'isFirst': True}, 'back': {'inside': True, 'isLast': True}} |
| 46 | PASS | C2 focus stays inside dialog after 4 more Tabs |  |
| 47 | PASS | C2 Escape in picker goes Back first (sheet stays) |  |
| 48 | PASS | C2 second Escape closes sheet, focus restored to AppGuard gear | {'act': 'settings', 'card': 'appguard'} |
| 49 | PASS | C2 sheet flow: zero console/page errors | ([], []) |
| 50 | PASS | C2 sheet full-screen at 360x640, overflow=0, edge-crossers=0 | {'panel': [0, 0, 360, 640], 'overflow': 0, 'edge': {'n': 0, 'list': []}} |
| 51 | PASS | C2 44x44 audit .ag-sheet @360x640 | {'n': 0, 'total': 156, 'bad': []} |
| 52 | PASS | C2 sheet 1280x800 inside viewport, overflow=0, edge-crossers=0 | {'panel': [260, 40, 760, 720, 1280, 800], 'overflow': 0, 'edge': {'n': 0, 'list': []}} |
| 53 | PASS | C2 44x44 audit .ag-sheet @1280x800 | {'n': 0, 'total': 156, 'bad': []} |
| 54 | PASS | C3 DSC gear opens "Deep Sleep Cool" sheet | Deep Sleep Cool |
| 55 | PASS | C3 DSC sheet renders "Freeze while unplugged" switch | textContent='Freeze while unplugged' sw_ok=True body=FREEZE WHILE UNPLUGGED /  / When off, apps are only frozen while charging with the screen off. /  / Never freeze /... |
| 56 | PASS | C3 DSC switch toggles via setconf freeze_unplugged | ('true', 'false', ["/data/adb/modules/daemon-manager/bin/dm 'setconf' 'freeze_unplugged' '0'", "/data/adb/modules/daemon-manager/bin/dm 'getconf'", "/data/adb/modules/... |
| 57 | PASS | C3b DIAGNOSTIC (bare-array packages, NOT the dm contract): rest of DSC sheet works, switch toggles via setconf | ('true', 'false', ["/data/adb/modules/daemon-manager/bin/dm 'setconf' 'freeze_unplugged' '0'", "/data/adb/modules/daemon-manager/bin/dm 'getconf'", "/data/adb/modules/... |
| 58 | PASS | C4 scrolled to 300 (precondition) | 300 |
| 59 | PASS | C4 KM.pollNow() ran (resolved true) and list issued; plus >=1 real 5.5s tick | {'pollNow': True, 'list_calls_in_window': 2} |
| 60 | PASS | C4 MutationObserver on #daemon-list: 0 records | {'records': 0, 'sample': []} |
| 61 | PASS | C4 same card node references |  |
| 62 | PASS | C4 window.scrollY unchanged | (300, 300) |
| 63 | PASS | C4 activeElement unchanged |  |
| 64 | PASS | C5 changed poll: same card nodes, 0 .card removals | {'same': True, 'removed': 0, 'records': 1, 'up0': '1h 0m', 'up1': '1h 1m', 'sameAg': True} |
| 65 | PASS | C5 uptime text updated in place (3612s -> 3672s) | {'same': True, 'removed': 0, 'records': 1, 'up0': '1h 0m', 'up1': '1h 1m', 'sameAg': True} |
| 66 | PASS | C6 sheet open: 0 list calls in 6 s, pollNow() resolves false | {'list_calls': 0, 'pollNow': False} |
| 67 | PASS | C6 Logs tab: 0 list calls in 6 s, pollNow() resolves false | {'list_calls': 0, 'pollNow': False} |
| 68 | PASS | C6 document.hidden: 0 list calls in 6 s, pollNow() resolves false | {'list_calls': 0, 'pollNow': False} |
| 69 | PASS | C6 visible again: poll resumes with one immediate refresh (1..2 list calls) | 1 |
| 70 | PASS | C7 100 rapid tab switches: 0 pageerror, 0 console error | ([], []) |
| 71 | PASS | C7 no empty active panel at every 10th switch (10 checks) | {'checked': 10, 'empty': []} |
| 72 | PASS | C7 list calls during burst <= 2 | {'list_calls': 0, 'all_cmds': 3} |
| 73 | PASS | C7 no .panel-error after burst, unexpected console.warn = 0 | (0, []) |
| 74 | PASS | C7 40 wheel +-1200 on daemon list: no errors, cards intact, page scrolled | {'state': {'sy': 0, 'h': 2679, 'cards': 6}, 'scrollY_samples': [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]} |
| 75 | PASS | C7 40 wheel +-1200 on #log-output (200 lines): scrollable, no errors | {'log': {'lines': 200, 'sh': 3862, 'ch': 582, 'ov': 'auto'}, 'scrollTop_samples': [2080, 2080, 2080, 2080, 2080, 2080, 2080, 2080, 2080, 2080]} |
| 76 | PASS | C7 AppGuard sheet open/close x10: closes cleanly, modal-root empty, no errors | {'modal_root_nodes_after_close': [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]} |
| 77 | PASS | C7 target toggle + cooldown applied after stress (mock state) | {'cooldown_s': 240, 'u0': False} |
| 78 | PASS | C7 Logs scroll kept across pollNow (skipped) + 5.6 s of timers | {'before': 400, 'after': 400, 'pollNow': False} |
| 79 | PASS | C7 after stress: no-change poll keeps daemon scrollY, 0 mutations, same nodes | {'scrollY': [300, 300], 'mutations': 0, 'same': True, 'pollNow': True, 'list_calls': 2} |
| 80 | PASS | C7 stress run: zero pageerror / console error | ([], []) |
| 81 | PASS | C8 auto on, scrolled to top, logGrow on, 6 s: scrollTop unchanged (0) | {'scrollTop': 0, 'precond': {'sh': 3862, 'ch': 582, 'top': 3280}} |
| 82 | PASS | C8 no logs call while away from bottom | [] |
| 83 | PASS | C8 at bottom, 6 s: new line appended and still at bottom (gap<=1) | {'last_before': 'mock log line 200', 'last_after': 'mock log line 201', 'gap': 0, 'logs_calls': 1} |
| 84 | PASS | C9 poison + Refresh -> .panel-error with Retry in Daemons panel | {'text': 'E_RENDER\nCould not render daemon list: item.pids.join is not a function\nRetry', 'retry': True, 'role': 'alert'} |
| 85 | PASS | C9 boundary logs console.warn only (no console error / pageerror) | ([], [], ['[C9 error boundary] [KM] render failed: daemon list item.pids.join is not a function']) |
| 86 | PASS | C9 tabs still switch while the Daemons panel is in error | [('logs', True), ('about', True), ('daemons', True)] |
| 87 | PASS | C9 shell intact: header + tabs + conn chip visible |  |
| 88 | PASS | C9 clear fault + Retry -> cards back, no .panel-error | {'cards': 6, 'note': 'panel-error survived tab switches'} |
| 89 | PASS | C9 error boundary run: 0 pageerror, 0 console error | ([], []) |
| 90 | PASS | C10 360x640: overflow=0 edge=0 layout=phone cols=1 tabbar=fixed | {'overflow': 0, 'edge': 0, 'layout': 'phone', 'cols': 1, 'tabbar': 'fixed'} |
| 91 | PASS | C10 360x640: Logs/About/Daemons panels no overflow / edge-crossers | {'logs': [0, 0], 'about': [0, 0], 'daemons': [0, 0]} |
| 92 | PASS | C10 390x844: overflow=0 edge=0 layout=phone cols=1 tabbar=fixed | {'overflow': 0, 'edge': 0, 'layout': 'phone', 'cols': 1, 'tabbar': 'fixed'} |
| 93 | PASS | C10 390x844: Logs/About/Daemons panels no overflow / edge-crossers | {'logs': [0, 0], 'about': [0, 0], 'daemons': [0, 0]} |
| 94 | PASS | C10 414x896: overflow=0 edge=0 layout=phone cols=1 tabbar=fixed | {'overflow': 0, 'edge': 0, 'layout': 'phone', 'cols': 1, 'tabbar': 'fixed'} |
| 95 | PASS | C10 414x896: Logs/About/Daemons panels no overflow / edge-crossers | {'logs': [0, 0], 'about': [0, 0], 'daemons': [0, 0]} |
| 96 | PASS | C10 768x1024: overflow=0 edge=0 layout=tablet cols=2 tabbar=static | {'overflow': 0, 'edge': 0, 'layout': 'tablet', 'cols': 2, 'tabbar': 'static'} |
| 97 | PASS | C10 768x1024: Logs/About/Daemons panels no overflow / edge-crossers | {'logs': [0, 0], 'about': [0, 0], 'daemons': [0, 0]} |
| 98 | PASS | C10 820x1180: overflow=0 edge=0 layout=tablet cols=2 tabbar=static | {'overflow': 0, 'edge': 0, 'layout': 'tablet', 'cols': 2, 'tabbar': 'static'} |
| 99 | PASS | C10 820x1180: Logs/About/Daemons panels no overflow / edge-crossers | {'logs': [0, 0], 'about': [0, 0], 'daemons': [0, 0]} |
| 100 | PASS | C10 1024x1366: overflow=0 edge=0 layout=desktop cols=3 tabbar=static | {'overflow': 0, 'edge': 0, 'layout': 'desktop', 'cols': 3, 'tabbar': 'static'} |
| 101 | PASS | C10 1024x1366: Logs/About/Daemons panels no overflow / edge-crossers | {'logs': [0, 0], 'about': [0, 0], 'daemons': [0, 0]} |
| 102 | PASS | C10 1280x800: overflow=0 edge=0 layout=desktop cols=3 tabbar=static | {'overflow': 0, 'edge': 0, 'layout': 'desktop', 'cols': 3, 'tabbar': 'static'} |
| 103 | PASS | C10 1280x800: Logs/About/Daemons panels no overflow / edge-crossers | {'logs': [0, 0], 'about': [0, 0], 'daemons': [0, 0]} |
| 104 | PASS | C10 1440x900: overflow=0 edge=0 layout=desktop cols=3 tabbar=static | {'overflow': 0, 'edge': 0, 'layout': 'desktop', 'cols': 3, 'tabbar': 'static'} |
| 105 | PASS | C10 1440x900: Logs/About/Daemons panels no overflow / edge-crossers | {'logs': [0, 0], 'about': [0, 0], 'daemons': [0, 0]} |
| 106 | PASS | C10 1920x1080: overflow=0 edge=0 layout=desktop cols=3 tabbar=static | {'overflow': 0, 'edge': 0, 'layout': 'desktop', 'cols': 3, 'tabbar': 'static'} |
| 107 | PASS | C10 1920x1080: Logs/About/Daemons panels no overflow / edge-crossers | {'logs': [0, 0], 'about': [0, 0], 'daemons': [0, 0]} |
| 108 | PASS | C10 1080x1080: overflow=0 edge=0 layout=desktop cols=3 tabbar=static | {'overflow': 0, 'edge': 0, 'layout': 'desktop', 'cols': 3, 'tabbar': 'static'} |
| 109 | PASS | C10 1080x1080: Logs/About/Daemons panels no overflow / edge-crossers | {'logs': [0, 0], 'about': [0, 0], 'daemons': [0, 0]} |
| 110 | PASS | C12 backend: >= 596 passed and failure-name set == baseline | TOTAL: 596 passed, 42 failed; failed names 42; new=[]; fixed=[]; gate>=596 |
| 111 | PASS | C12 node --check all module/webroot/js/*.js (5 files) | [('add.js', 0, ''), ('appguard.js', 0, ''), ('core.js', 0, ''), ('daemons.js', 0, ''), ('misc.js', 0, '')] |
| 112 | PASS | C11 zero console error across the whole run | [] |
| 113 | PASS | C11 zero pageerror across the whole run | [] |
| 114 | PASS | C11 console.warn only from the injected boundary fault (C9) | [] |

## Failures

none

## Notes

- extra info: {"log_scrollTop_after_tab_roundtrip": {"set": 400, "after": 400}, "boundary_warnings": ["[C9 error boundary] [KM] render failed: daemon list item.pids.join is not a function"]}

## Loop-2 rerun (QA, 2026-11-13 06:54 WIB, after C3 assertion fix)

- Result: **PASS**, 114 passed, 0 failed, 114 checks (report.json generated 2026-11-13T06:54:09+0700; log: tmp/qa/final3.log). Same invocation as loop 1; backend output tmp/night-backend2.txt reused (no app/backend code changed). node --check on all module/webroot/js/*.js: ok.
- Assertion change (tests/ui/qa.py, check `C3 DSC sheet renders "Freeze while unplugged" switch`): previously `'Freeze while unplugged' in inner_text(modal body)`. inner_text returns CSS-transformed text and style.css:160 `.switch-label{text-transform:uppercase}` (pre-existing) renders "FREEZE WHILE UNPLUGGED", so the loop-1 FAIL was a test defect. Now reads DOM textContent of `#modal-root .switch-label` (stripped) and requires exact equality with 'Freeze while unplugged' AND sw_ok. Measured: textContent='Freeze while unplugged', sw_ok=True. No other check changed.
- Console errors: 0; pageerrors: 0; console warnings: 1 (expected, C9 injected fault only).
