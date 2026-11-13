# NIGHT-JUDGE - AppGuard sheet + WebUI performance

Judge: independent audit, 2026-11-13, base `8c289b7`, working tree dirty (11 modified, 3 untracked, nothing committed).
Scope judged: code + mock-browser QA only. Nothing here was fixed by the Judge.

## Verdict: PASS-WITH-RISKS (night scope)

Every acceptance item that can be checked in this clone passes, and I reproduced it myself (114/114 on my own run).
No High or Critical defect. Three Medium defects and eight Low ones are listed below; none breaks an acceptance bullet
on the mock, but two of them make the UI show state the backend doesn't have. The 638-pass backend figure was not
reachable here and stays open. This is not a ship verdict: real WebView QA has not happened.

## What I ran

| Command / action | Result |
|---|---|
| `git -C repo status --short`, `git diff` read in full for `module/webroot/**`, `tests/ui/**` | 6 webroot files + `add.js` (1 line) + QA files; `module/bin/**`, `tests/run.sh`, `tests/evidence/ui/`, `tests/evidence/backend.txt` untouched |
| `KM_EVID=tmp/judge/ev KM_QA_PORT=8197 KM_BACKEND_OUT=tmp/night-backend2.txt python3 tests/ui/qa.py` | `TOTAL: 114 passed, 0 failed`, 0 console errors, 0 pageerrors (`tmp/judge/qa.log`, `tmp/judge/ev/report.json`); same 114 check names as `tests/evidence/ui-night/report.json` |
| sha256 of `tests/evidence/ui-night/*` before/after my run | identical; repo evidence not touched |
| Backend: parsed `tmp/baseline-backend.txt` vs `tmp/night-backend2.txt` | both `TOTAL: 596 passed, 42 failed`; failure-name sets identical to each other and to `tmp/baseline-failed.txt`; two separate runs (different `/tmp/km-test.*` dirs) |
| `node --check` x5, grep `panel-appguard\|tab-appguard\|backdrop-filter` in `module/webroot` | clean, no hits |
| Own adversarial probes, 17 scenarios, `tmp/judge/probe.py` -> `tmp/judge/probe.log`, `probe-results.json` | see P-numbers below |
| Screenshots read: `390x844.png`, `820x1180.png`, `1280x800.png`, `ag-sheet-390x844.png`, `ag-sheet-1280x800.png`, base `tests/evidence/ui/1280x800.png` | layouts match the measured modes; no clipping in the sheet |

## Acceptance

| # | Item | Evidence checked | Finding |
|---|---|---|---|
| 1 | Three tabs only, no AppGuard tab/panel in DOM | `index.html:43-56` (3 `role=tab`), panel block deleted (diff -30 lines); `core.js:248`; grep gate; QA C1; P18 | PASS. No hidden panel; the only `ag-` id is `#ag-sheet-error`, created inside the sheet (`appguard.js:801`) |
| 2 | Gear opens full sheet; all controls hit existing `dm appguard` commands | `daemons.js:469-472`; `appguard.js` status :52, lifecycle :111, set :184/:202, once :268, targets set :407, rm :467, add :691, never :536/:551, packages :654, kills :592; backend shapes read in `km-appguard.sh:76-98,100-118,170-212,215-243,247-282,284-313`; QA C2 (26 checks) | PASS on mock. Caveat: bug 7 (picker on an existing target) |
| 3 | Lazy sheet, nothing at load | `appguard.js:841` exports `open` only; `misc.js:231-243` no AppGuard init; P17 | PASS |
| 4 | DSC gear still opens its sheet | QA C3/C3b; `add.js:330` | PASS, but only because of a one-line fix to a pre-existing crash. This contradicts NIGHT-PLAN.md:110 ("add.js diff empty") and "stays as it is"; correct against `km-appguard.sh:466-473` and `tests/run.sh:333-335`. Needs user sign-off |
| 5 | A11y: dialog role, aria-modal, Escape, focus trap, mobile full-screen, 44 px | `core.js:322-326,354-367`; panel rect `[0,0,360,640]` (QA + P19); 44 px audit 158 controls, 0 bad at 360 and 768 with a row confirm open (P19) | PASS for role/Escape/full-screen/44 px. Focus: PARTIAL, bugs 4 and 5 |
| 6 | No-change poll = zero card DOM replacement | `daemons.js:329-340` (fp skip), `:269-295` (reconcile), `:234-253` (morph); QA C4: 0 MutationObserver records, same refs, scrollY 300->300, activeElement same; reproduced | PASS. Changed poll (C5): same nodes, uptime text patched. P3: morphed card `outerHTML` equals a freshly built card in 7 state changes, so no patch drift |
| 7 | 5 s tab gate | `core.js:249-255,270-282`; P5: 0 `list` on return < 5 s, 1 on return > 5 s; QA C7 <= 2 during 100 switches | PASS |
| 8 | Poll pause (tab, hidden, modal); log auto pause; no yank | `daemons.js:364-372`; `misc.js:37-55,88-96`; QA C6 x3, C8; P15: manual refresh keeps scrollTop 400 | PASS |
| 9 | Error boundary, no blank panel, Retry | `core.js:140-169`; daemons `:332`, logs `misc.js:70,83`, about `:196`, sheet sections `appguard.js:33-37`; QA C9; P7 (kills section fails alone, 33 rows + status intact), P7b (`get` fails -> inline error + Retry), P10 (odd/sparse daemon JSON renders, `null` list handled) | PASS for render paths. Gap: bug 6 (one promise path) |
| 10 | Caps, hidden-panel work, backdrop-filter | logs `misc.js:8,63-64`; targets 50/+50/200 `appguard.js:7,330`; picker 200 `:662`; kills 50 `:570`; dirty flags `daemons.js:335`, `misc.js:68,184`; `style.css:308` no `backdrop-filter` | PASS |
| 11 | Stress: 0 pageerror, 0 blank, 0 console error, stable scroll | QA C7 (8 checks) reproduced; P17: after 10 open/close cycles document keydown listeners 0->0, pending timers 1->1 (the poll chain), `__kmCb_` globals 0 | PASS |
| 12 | Ten viewports | QA C10: 20 checks, overflow 0, edge 0, layout/cols/tab bar as expected; 10 PNGs + 3 sheet PNGs | PASS |
| 13 | Backend: no regression from the 638 baseline | 596/42 before and after, identical failure set; zero backend files changed | Substitute gate PASS. The 638 item as written is NOT verified. 17 of the 42 baseline failures are `appguard:` contract tests (once, kills, packages flags, never count), so the "Backend test" column in NIGHT-NOTES.md is unproven for those tonight |
| 14 | Real WebView QA, sign-off, commit/push, live update | not done, correctly recorded as open | OPEN |

## Bugs found (ranked)

**Medium**

1. `appguard.js:399-425` `setTarget` patches the row node it captured, and the model `t` only changes when the response lands. If the rows re-render while `targets set` is in flight (filter input :297-303, Show more :741, remove :472, picker add :700, Never shadow change :529), the visible switch is rebuilt from the old model and never corrected. P9: `com.demo.app00` shows `aria-checked="true"` while `KM.S.ag` and the backend both say `u0=false`. The UI then says an app is watched when it isn't, until the next rows render.
2. `daemons.js:344` drops any `load()` requested while a poll is in flight, and `runAction` (`:398-405`) relies on that call. P6: Start finished during an in-flight `list`; the stale reply won and the card showed `STOPPED` / `Start` for a running daemon until the next 5 s poll. Pre-existing (base `daemons.js:235`), self-healing, but it sits in the loop mission B set out to fix and it was left as is.
3. `appguard.js:165` commits Interval / Default cooldown on blur, and closing the sheet blurs the field. P13: type `999`, press Escape -> `dm appguard set interval 999` is sent and saved. The value is clamped first (:177), and because the sheet is already gone (`alive()` false, :185) there is no toast or error. Dismissing with X or Escape after a half-typed number silently changes config (e.g. `5` becomes interval 10).

**Low**

4. `core.js:372` picks the first body button even when it is disabled. In the AppGuard sheet that is Start (disabled while running, `appguard.js:83-90`). When `appguard get` returns in under 20 ms, focus stays on the gear behind the dialog and Tab walks the page behind it (P1a, mock latency 15 ms). At 250 ms latency focus lands on Close (P1b), so on the device this is probably latent. QA misses it because `qa.py:474-487` force-focuses the last control first.
5. Focus falls to `<body>` after any in-sheet section re-render that destroys the clicked button: Start/Stop/Restart (`appguard.js:92`), Run once / Dry run once (`:242`) (P2). Same on cards: the action button is disabled while busy (`daemons.js:175`), so keyboard focus is lost after Start (P4). Tab re-enters the dialog in Chromium, Escape still works.
6. `appguard.js:512` calls `neverAdd()` with no rejection handler while `:544` rethrows. P8: `never add` failing with `E_BUSY` via the Enter key raises an unhandled rejection (`pageerror: Object`). The inline error still shows; the Add button path (`:749`) is handled. Breaks the plan's "no throw escapes as an unhandled rejection".
7. `appguard.js:691` always sends `targets add`; the backend answers `E_CONFLICT` for a package that is already a target (`km-appguard.sh:191`). Rows tagged `target` are not disabled, and adding user 999 to an existing user-0 target through the picker fails. Pre-existing (base `appguard.js:388`). `tests/ui/mock.js:121-125` upserts instead of failing, so QA can't see it.
8. First load shows an empty list: every caller uses `load(true)`, so the skeleton branch (`daemons.js:300-306`, `:346`) is dead code. P12: with a 1.5 s `list`, `#daemon-list` has 0 children, height 0, count `-` (`tmp/judge/p12-first-load.png`). Pre-existing. Worst case is the 12 s read timeout.
9. Picker: the error box is never cleared after a later success (`appguard.js:678` vs `:657-677`), and replies are guarded by user only (`:658`), so a slow reply for an older query can overwrite a newer one.
10. Sheet Status is a snapshot. Polling is paused while the modal is open and nothing re-reads `appguard get`, so state/PID/uptime don't move until a lifecycle button is pressed.
11. Cosmetic, pre-existing, not a night regression: at 1280x800 the `unverified` chip wraps to two lines and the delete button drops to a second row on cards with a gear. Pixel-identical in base `tests/evidence/ui/1280x800.png`. Not blocking; polish item.

XSS: none found. All package names, log text and error text go through `textContent`; the single `innerHTML` (`core.js:59`) takes constant icon paths only. Shell args are quoted by `shq` (`core.js:70,235`).

## QA quality

- Assertions are real: node-identity checks, MutationObserver records, command-log matches and mock-state reads, not text presence. Loop 2's change (`qa.py:540-545`) reads `textContent` and requires an exact match; that is stricter than the old case-sensitive `inner_text` test, not weaker. Nothing was removed to get green.
- Blind spots: no failure-path coverage inside the sheet (bug 6); focus check force-focuses (bug 4); mock `targets add` diverges from the backend (bug 7); the "zero mutation" proof needs a non-ticking mock (fine, and C5 covers the changed case; P11 shows a changed fingerprint with the same rendered text still writes nothing); the patched-vs-fresh card comparison promised in NIGHT-PLAN.md:128 is not in `qa.py` (I ran it, P3, equal); no in-flight race test (bug 2); the burst "not blank" check accepts a skeleton or the Logs placeholder.

## Open risks

- Everything above is Chromium headless plus a 15 ms mock. Android WebView timing, soft keyboard on the programmatic `focus()` calls (`appguard.js:476,542,555`), touch hit areas and scroll inertia are untested.
- On the device `uptime_s` ticks, so most polls will rebuild one detached card per running daemon and diff it. No DOM replacement, but it is not the zero-work path the mock shows.
- `add.js:330` fixes a crash that exists on live v2.0.0; it was outside the approved file list.
- AppGuard backend contract tests (17) can't run in this clone.

## If the user wants the Mediums closed before sign-off, Planning re-opens

1. `setTarget`: resolve the row by `data-pkg` at response time or update the model optimistically (bug 1).
2. `load()`: queue one follow-up load when a refresh is requested mid-flight (bug 2).
3. Number fields: don't commit on blur caused by sheet close, or drop blur-commit and keep Enter/Save (bug 3).
4. Cheap extras: `KM.sheet` initial focus skips disabled controls; `.catch` on `appguard.js:512`; restore focus after section re-render.

## Stays open for the morning

- Real WebView QA on the phone (KernelSU module WebUI).
- User sign-off, including the unattended decisions: `add.js` fix, 596 gate, `backdrop-filter` removal.
- Commit / push (nothing is committed; no remote).
- Live module update.
- 638-pass backend re-check on the main tree with `reference/live/*`.
