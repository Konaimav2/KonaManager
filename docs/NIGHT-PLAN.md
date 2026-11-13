# NIGHT-PLAN - AppGuard sheet + WebUI performance (code-only night run)

Base: `8c289b7` (KonaManager v2.0.0). Planning stage output. Every line number below is from that commit.
Scope = mission A + B in `../../NIGHT_PROMPT.md`. No commit, no push, no phone, no network beyond 127.0.0.1.

## 1. Current state (evidence)

**AppGuard tab/panel**
- Tab button `index.html:48-51` (`#tab-appguard`), panel `index.html:81-105` (`#panel-appguard`, ids `ag-count ag-error ag-status ag-controls ag-actions ag-result ag-never ag-targets ag-kills`).
- `core.js:38-39` holds `S.ag/agKills/agError/agBusy/agResult/agSearch/agPage`; `core.js:211` `KM.tabs = ['daemons','appguard','logs','about']`; `core.js:225` loads AppGuard on activate; `core.js:364` header Refresh branch.
- `appguard.js` (439 lines) renders straight into the panel ids: `renderStatus` :15, `renderControls` :68 (interval :78, cooldown :85, dry switch :94), `renderActions` :114 (Run once via `KM.confirm` :120, Dry run :126), `renderTargets/renderRows/targetRow` :164-236 (page 50, "Show more" +50), `setTarget` :249, `renderNever` :255 (text add only), `renderKills` :285 (slices 100), `load` :335 (`get` then `kills 50`, then full `render()`), `picker(mode)` :350 (opens its own `KM.sheet`), `init` :411 (delegated click on `#panel-appguard`). `picker('never')` exists but is never wired (dead code).
- `daemons.js:175-181` gear only for `appguard` and `deep-sleep-cool`; `daemons.js:345-348` `settingsFor`: appguard -> `KM.activate('appguard')`, DSC -> `KM.settings.open()`.
- `misc.js:153` `KM.appguard.init()` in `boot()`.
- CSS: `.ag-status` :208-210, `.ag-grid/.ag-column` :211-213, `.target-row` :217-233 (switch 40x24, `.rm` 36x36, input min-height 36 - all under 44 px), `.never-chip button` 24x24 :237, `.btn.small` min-height 36 :107, `.picker-row` padding 9 px :312.

**Load / render / poll loop (the defect)**
- `KM.activate` `core.js:212-228`: toggles `hidden`, then unconditionally `KM.daemons.load(true)` / `appguard.load()` / `logs.load()` / `about.load()` on every switch.
- `daemons.load` `daemons.js:234-250`: `list` -> replaces `S.daemons` -> `render()` always.
- `daemons.render` `daemons.js:204-232`: `clear(list)` then `card()` for every daemon. Every action (`runAction` :258-285 renders on busy + `load(true)` after), `openDetails` :318-333 also full re-render. Focus and scroll inside the list are destroyed each time.
- Poll `daemons.js:442-444`: `setInterval` 5 s, guarded only by `S.tab==='daemons' && visible && !S.loading`. Not paused while a modal is open.
- Logs `misc.js:30-47`: `fillSources()` rebuilds the `<select>` on every load; `box.textContent = ...` then `box.scrollTop = box.scrollHeight` always (yanks). Auto timer `misc.js:57-63` 5 s, guarded by tab + visible only.
- About `misc.js:76-145`: clears and rebuilds three blocks on every activation.
- No error boundary anywhere: an exception in `card()`/`render*()` inside a `.then` leaves a cleared, empty panel.
- `style.css:267` `.modal-backdrop{backdrop-filter:blur(2px)}` (only use in the file).

**Deep Sleep Cool sheet (the pattern to reuse)** `add.js:325-376` `openSettings()`:
`KM.sheet({title, sub})` -> body "Loading..." -> `Promise.all([getconf, packages])` -> builds body nodes -> footer `Done` (closes + `KM.daemons.load(true)`). After each write it calls `openSettings()` again (full re-open). Errors via `KM.showError(body, e)`. `KM.sheet` (`core.js:257-312`) already gives `role=dialog`, `aria-modal`, `aria-labelledby`, Escape, Tab focus trap, backdrop close, focus restore, blocking mode; CSS `style.css:276-281` already makes it full-screen < 600 px. **Limitation:** `KM.sheet` is single-instance (`closeSheet(true)` at :259), so `KM.confirm` or `picker()` opened from inside a sheet would close the AppGuard sheet. DSC stays untouched.

## 2. Proposed change - exact file list

UI/UX stage may edit only: `module/webroot/index.html`, `module/webroot/style.css`, `module/webroot/js/core.js`, `module/webroot/js/daemons.js`, `module/webroot/js/appguard.js`, `module/webroot/js/misc.js`. `add.js` read-only (DSC sheet unchanged). QA stage edits only `tests/ui/qa.py`, `tests/ui/mock.js` (+ evidence). Docs stage edits only `docs/PRD.md`, `docs/DESIGN.md`, optional new `docs/NIGHT-NOTES.md`. No `module/bin/**` change (section 3).

### A. AppGuard tab -> gear sheet

| File | Change |
|---|---|
| `index.html` | Delete lines 48-51 and 81-105. Tabs = Daemons / Logs / About. Keep `<script src="js/appguard.js">` (now the sheet module). |
| `core.js` | `KM.tabs = ['daemons','logs','about']`; drop the appguard branches at :225 and :364; drop `agError`, keep `ag/agKills/agResult/agSearch/agPage` (sheet state). Legacy `#appguard` hash falls back to `daemons` (no auto-open). Add `KM.sheet` option `cls` (extra class on `.modal-panel`, e.g. `ag-sheet`) - additive, defaults unchanged. |
| `daemons.js` | `settingsFor`: appguard -> `KM.appguard.open()`. Gear label stays `AppGuard settings`. |
| `misc.js` | Remove `KM.appguard.init()` from `boot()`. |
| `appguard.js` | Rewrite as a lazy sheet module exporting `KM.appguard = { open }`. Nothing runs at load except defining functions. `open()`: `KM.sheet({title:'AppGuard', sub:'Idle app watchdog', cls:'ag-sheet'})`, body "Loading...", then `appguard get` + `appguard kills 50`, then render sections into the sheet body (scoped queries on `sh.body`, no global ids except one `#ag-sheet-error`). On close: drop all node refs, timers and listeners; reset `S.agPage=50`, `S.agSearch=''`. |
| `style.css` | Delete `.ag-grid/.ag-column` (:211-213). Scope AppGuard rules under `.ag-sheet`. `.modal-panel.ag-sheet{width:min(760px,100%)}`. 44 px hit targets inside `.ag-sheet` (switch, `.rm`, cooldown input, never-chip x, `.btn.small`, picker rows, segmented buttons). Phone (<600) stays full-screen via existing rules. |

**Sheet sections (top to bottom), each a `<section>` with its own render function and error boundary:**
1. **Status** - `daemon.state` dot, `PID`, `uptime` (`fmtUptime`), counts chips, version-pending warning (`running_version != installed_version`), Start / Stop / Restart. Lifecycle calls go through `KM.daemons.runAction('appguard', act)` (reuses busy state, toast, list refresh), then re-`get` and patch Status only.
2. **Settings** - Interval (10-3600) -> `appguard set interval N`; Default cooldown (0-86400) -> `appguard set cooldown N`; Dry-run switch -> `appguard set dry 0|1`. Apply on Enter/blur/Save, clamp client-side, inline error on `E_ARG`.
3. **Run now** - `Run once` (inline two-step confirm strip inside the sheet: "Sends real am-kill requests. Confirm / Cancel"; no nested `KM.confirm`) -> `appguard once`; `Dry run once` -> `appguard once --dry`. Both buttons busy while running (70 s `KM.T.once`). Result box as `resultView`. When `config.dry_run` is on, show "Dry-run is on: Run once will not kill" (backend forces dry, `km-appguard.sh:330`).
4. **Targets** - filter input, `Add app`, user matrix rows `pkg | U0 | U999 | cooldown | remove`. Toggle -> `appguard targets set <pkg> u0= u999= cooldown=`; on success patch **only that row** from the response (`pkg,u0,u999,cooldown_s` are returned, `km-appguard.sh:212`) and recompute counts locally; on failure revert the switch and show the inline error. Cooldown input change -> same command with `cooldown=N|default`. Remove -> inline confirm on the row -> `targets rm`. Paging: 50 per page, `Show more` +50, hard cap 200 rendered rows (beyond that: "Refine the filter"); filter change resets to 50; filter input debounced 150 ms; build rows into a `DocumentFragment`.
5. **Never** - chips with remove -> `never rm`; text add (regex `KM.RE.pkg`, <=128) -> `never add`; `Pick` button opens the package picker.
6. **Recent kills** - `appguard kills 50`, render at most 50 rows, Refresh button, "Showing n of total".

**Package picker** = an in-sheet sub-view (replaces the sheet body, `Back` button returns and restores the previous body scrollTop), not a second `KM.sheet`. Modes `target` (user 0 / 999 segmented -> `packages --user N [--q s]`, tap -> `targets add <pkg> u0=1 u999=0` or `u0=0 u999=1`) and `never` (`packages --user 0`, tap -> `never add`). Search debounce 250 ms (as today). Focus moves to the picker search on open and back to the opener on Back.

**A11y**: inherits `role=dialog`, `aria-modal`, `aria-labelledby`, Escape, focus trap from `KM.sheet`; Escape inside the picker sub-view goes Back first, second Escape closes. Switches keep `role=switch` + `aria-checked` + per-row `aria-label`. Every interactive element in `.ag-sheet` measures >= 44x44 CSS px.

### B. Performance and crash

1. **Fingerprint + in-place patch (`daemons.js`)**. Keep `S.lastGood` (last good `list` JSON) and `S.fp` = `JSON.stringify` of `daemons` (drop top-level `ts`) + busy map + openDetails keys + details revision + error code. `load()` success: if `fp === S.fp` -> return, no DOM write at all (not even count text). Else `reconcile()`: map existing `article.card[data-id]`; for each daemon in order, patch existing card or create; remove cards whose id vanished; move a node only if it is out of order (`insertBefore` only when needed). `card()` tags sub-nodes with `data-f` (`state`, `pid`, `uptime`, `health`, `verified`, `switch`, `primary`, `restart`, `gear`, `delete`, `failure`, `details`); `patchCard(el,item)` sets text/attrs/classes/`disabled` only when different. Primary button: change label, icon and `data-act` on the **same** button element (focus survives). Skeleton/empty state only when the list is empty. Per-card fingerprint (`el._fp`) skips untouched cards. Real device note: `uptime_s` ticks, so a real poll patches only uptime text - still zero card replacement. Save/restore `window.scrollY` and `document.activeElement` around reconcile as a belt-and-braces guard.
2. **Tab switch (`core.js`)**: `activate()` calls a panel loader only if `Date.now() - lastOk[tab] >= 5000` (or never loaded); `lastOk` set on success only. Header Refresh and explicit actions bypass the gate. About loads once, then on the 5 s rule.
3. **Poll pause (`core.js` + `daemons.js` + `misc.js`)**: replace `setInterval` with one `setTimeout` chain per poller. Daemon tick runs only if `S.tab==='daemons' && !document.hidden && !S.modal && !S.loading`. `visibilitychange` -> visible + daemons + stale -> one load. Log auto tick runs only if `S.tab==='logs' && !document.hidden && S.logs.auto && atBottom(box)` (`scrollHeight - scrollTop - clientHeight <= 24`). Logs render: skip if text identical; if the user was at the bottom stick to bottom, else keep `scrollTop` unchanged; first load goes to bottom. `fillSources()` rebuilds the `<select>` only when the source-list signature changes. Expose `KM.pollNow()` (runs the same guarded daemon tick) for QA.
4. **Lazy sheet**: covered in A; grep gate: `ag-` ids and `appguard` render code run only after `KM.appguard.open()`.
5. **Error boundary (`core.js`)**: `KM.guard(hostEl, name, fn, retry)` wraps every panel/section render (daemons list, logs, about blocks, each AppGuard section, picker). On throw: `console.warn` (not `console.error`), replace only that host's content with `.panel-error` (`code E_RENDER`, short message, `Retry` button calling `retry`). Shell, tabs, header and other panels stay usable. Wrap promise `.then(render)` paths too so a throw never escapes as an unhandled rejection.
6. **Reduce work**: logs `lines` capped at 200 (select already 50/100/200; clamp client-side `lines.slice(-200)`); kills <=50 rows; targets cap above; no rendering into hidden panels (daemons render while hidden sets `S.dirty` and reconciles on activation); no read-after-write layout loops (build in fragments, read `scrollTop` once before writes); **drop `backdrop-filter`** at `style.css:267` and raise `--km-scrim` alpha to `.78` (can't measure WebView jank tonight; blur on a full-screen layer is the known cost, so removal is the conservative choice).

## 3. Backend verdict: no backend change

Every sheet control maps to an existing command (source `module/bin/lib/km-appguard.sh`, router `cmd_appguard` :370-381; lifecycle via `module/bin/dm:64-66`):

| Control | Command | Source | Backend test |
|---|---|---|---|
| Status state/PID/uptime, versions | `appguard get` (`daemon`, `running_version`, `installed_version`, `config`, `counts`) | :97 | `tests/run.sh:650-651` |
| Start/Stop/Restart | `dm start|stop|restart appguard` | `dm:64-66` | lifecycle suite `run.sh:176+` |
| Interval / cooldown / dry-run | `appguard set interval|cooldown|dry <v>` (10-3600, 0-86400, 0/1) | :100-113 | `run.sh:767, 791-812` |
| Run once / Dry run once | `appguard once [--dry]` | :317-367 | `run.sh:717, 738, 744, 762-774` |
| Matrix toggle, per-app cooldown, add, remove | `appguard targets add|set|rm <pkg> u0= u999= cooldown=N|default` | :128-133, :174-212 | `run.sh:754-780` |
| Never add/remove | `appguard never add|rm <pkg>` | :214-243 | `run.sh:814-823` |
| Package picker | `appguard packages [--user 0|999] [--q s]` | :248-282 | `run.sh:830-841` |
| Recent kills | `appguard kills <n>` | :284-313 | `run.sh:734, 747, 848` |

No command is missing, so the Backend stage is **skipped**; the docs stage records this table in `docs/NIGHT-NOTES.md` as the "no backend change" note.

## 4. QA plan (sonnet high)

Files: `tests/ui/mock.js`, `tests/ui/qa.py`. Run: `KM_EVID=tests/evidence/ui-night KM_QA_PORT=8199 python3 tests/ui/qa.py` from `repo/`. **Never write to `tests/evidence/ui/` or `tests/evidence/backend.txt`** (morning baselines). Scratch in `/root/temp/konamanager-night/tmp/`.

**mock.js additions**: expose `window.__mockState = st`; `getconf`, `setconf`, `whitelist add|rm`, `packages` (DSC sheet); `logs` returns `n` numbered lines (`a[2]`, default 100) and appends a new line per call when `st.logGrow`; fault switch `st.faults.list='poison'` appends `{id:'zz-bad', name:'Bad', pids:{}, running:true}` after `sync()` so `card()` throws (exercises the boundary). Keep the 15 ms async callback.

**qa.py changes** (replace the old AppGuard-tab steps at :109-123):
- Structure: assert `[role=tab]` count === 3 with labels Daemons/Logs/About; `#tab-appguard`, `#panel-appguard`, `[id^="ag-"]` outside `#modal-root` all absent.
- AppGuard sheet: click `.card[data-id=appguard] [data-act=settings]` -> `#modal-root [role=dialog]` with title AppGuard; assert sections Status/Settings/Run now/Targets/Never/Recent kills; PID `17741`; toggle first U0 switch -> `targets set` command seen and `aria-checked` flips, **and the row element is the same node** before/after; change one cooldown to `120` -> `cooldown=120` command; interval + dry-run set commands; Dry run once -> result box `candidates`; Run once -> inline confirm -> `appguard once` without `--dry`; picker (target + never) adds a package; never chip remove; kills rows == 3. Focus trap (Tab from last wraps), Escape closes and focus returns to the gear. 44 px audit at 390x844: every `button,input,select,[role=switch]` in `.ag-sheet` has rect `w>=44 && h>=44` (or a `.hit` ancestor that does). Sheet at 360x640 is full-screen (panel rect == viewport).
- DSC gear still opens "Deep Sleep Cool" sheet with the "Freeze while unplugged" switch.
- No-change poll: at 390x844 scroll window to 300, store refs to every `.card`, attach `MutationObserver` on `#daemon-list` (`childList, subtree, attributes, characterData`), call `KM.pollNow()` and also wait one real 5.5 s tick; assert `list` command was issued, **0 mutation records**, same node refs, `scrollY` unchanged, `activeElement` unchanged.
- Changed poll: set `__mockState.daemons[0].uptime_s += 60`, poll; assert card refs identical, zero `.card` removals, uptime text updated.
- Pauses: with the sheet open wait 6 s -> zero new `list`; on Logs tab wait 6 s -> zero `list`; fake `document.hidden=true` + `visibilitychange` wait 6 s -> zero `list`.
- Tab gate: 100 rapid switches Daemons->Logs->About (no waits) -> zero pageerror/console error, active panel never empty (`innerText.trim()` non-empty after each 10th switch), `list` calls during the burst <= 2.
- Scroll stress: 40 `mouse.wheel` +-1200 on the daemon list (390x844) and on `#log-output` (200 lines); then no-change poll keeps both positions.
- Logs: auto on, scroll `#log-output` to top, `logGrow` on, wait 6 s -> `scrollTop` unchanged (and no `logs` call while away from bottom); scroll to bottom, wait 6 s -> new line visible and still at bottom.
- Error boundary: set `faults.list='poison'`, Refresh -> `.panel-error` with Retry in Daemons panel, tabs still switch, no pageerror; clear fault, Retry -> cards back.
- Ten viewports (existing loop :183-202, keep expectations `1024x1366`=desktop by CSS breakpoint): for each of 360x640, 390x844, 414x896, 768x1024, 820x1180, 1024x1366, 1280x800, 1440x900, 1920x1080, 1080x1080: `scrollWidth-innerWidth===0`, zero edge-crossing elements (selector list + `.modal-panel` when open), `--km-layout` + `.cards` column count + tab bar `position` match, one screenshot `tests/evidence/ui-night/<w>x<h>.png`; plus one AppGuard-sheet screenshot at 390x844 and 1280x800 (`ag-sheet-<w>x<h>.png`) with the same overflow checks.
- Global: zero `pageerror`, zero console `error`, zero blank panel; `report.json` in the evidence dir.

**Backend suite**: `sh tests/run.sh > /root/temp/konamanager-night/tmp/night-backend.txt`. Gate (per `FLOW.md` 06:20 decision): **>= 596 pass and the failure list identical to `tmp/baseline-failed.txt`**. The 638/0 figure in `tests/evidence/backend.txt` needs the gitignored `reference/live/*` captures, which this clone lacks; 638 is re-checked in the morning on the main tree. `run.sh:19` uses `mktemp -d /tmp/km-test.*` with a cleanup trap (`:37`); accepted as already exercised by the baseline, not edited.

Static gates: `node --check` on all five JS files; `grep -n 'panel-appguard\|tab-appguard' module/webroot` prints nothing; `grep -n backdrop-filter module/webroot/style.css` prints nothing.

## 5. Acceptance checklist

- [ ] Exactly 3 `[role=tab]`; no `#tab-appguard`, `#panel-appguard`, or `ag-*` node outside the open sheet (QA DOM assert + grep).
- [ ] AppGuard gear opens the sheet; all 13 controls (state/PID/uptime, Start, Stop, Restart, interval, default cooldown, dry-run, Run once, Dry run once, matrix toggle, per-app cooldown, Never add/remove + picker, kills) issue the commands in section 3 (QA `__cmds` asserts).
- [ ] DSC gear opens its unchanged sheet; `git diff --stat module/webroot/js/add.js` empty.
- [ ] Sheet: `role=dialog`, `aria-modal=true`, Escape closes, focus trapped and restored, full-screen at 360x640, every control >= 44x44.
- [ ] No-change poll: 0 MutationObserver records on `#daemon-list`, identical node refs, `scrollY` delta 0.
- [ ] Changed poll: 0 card replacements, uptime text updated.
- [ ] Poll paused for: Logs/About tab, `document.hidden`, open modal (0 `list` calls in 6 s each).
- [ ] 100 rapid tab switches: 0 pageerror, 0 console error, 0 blank panels, <= 2 `list` calls.
- [ ] Log scroll never changes while the user is away from the bottom.
- [ ] Error boundary shows `.panel-error` + Retry; Retry recovers; shell usable.
- [ ] 10/10 viewports pass with screenshots in `tests/evidence/ui-night/`; `tests/evidence/ui/` untouched (`git status` shows no change there).
- [ ] Backend: >= 596 pass, failure set == baseline; `node --check` x5 clean.
- [ ] `docs/DESIGN.md` (tabs line 54/59/62, D3 line 77, section 5 -> "AppGuard settings sheet", section 13 polling/render rules, decisions D10-D13) and `docs/PRD.md` (R8 responsiveness: no full re-render on unchanged data, scroll/focus preserved, render errors contained) updated; `docs/NIGHT-NOTES.md` holds the no-backend-change table.
- [ ] Open (cannot be done tonight): real WebView QA, Judge sign-off by the user, commit/push, live module update, 638 backend re-check with reference captures.

## 6. Risks

| Risk | Cause | Consequence | Fix / fallback |
|---|---|---|---|
| Nested sheet closes AppGuard sheet | `KM.sheet` is single-instance (`core.js:259`); old code uses `KM.confirm` and `picker()` sheets | Run once / remove / picker would kill the config sheet and lose state | In-sheet confirm strip + picker sub-view (section 2). Do not add a modal stack to `core.js` tonight. |
| Patch drift: patched card differs from a fresh card | `patchCard` misses a field that `card()` sets | Stale button label/disabled state, wrong action | Single source: `card()` builds, `patchCard()` writes the same `data-f` slots; QA compares a patched card's `outerHTML` with a freshly built one after a state change (start/stop). |
| Fingerprint never stable on device | real `uptime_s`/`ts` change every poll | Every poll patches (cheap) - acceptable, but "no-change" claim only proven on mock | Exclude `ts`; uptime goes through text-only patch; note in NIGHT-REPORT that real WebView QA is open. |
| Sheet re-render loses focus/scroll | after each write calling a full re-render (DSC pattern) | Focus jumps, sheet scrolls to top on every toggle | Section-level re-render; row-level patch for targets from the `targets set` response; keep `sh.body.scrollTop` across section renders. |
| Boundary hides real bugs / console noise | catching everything | QA "0 console errors" passes while bugs hide | Boundary uses `console.warn` with name + message; QA fault test proves it fires only on the injected fault; normal runs must show 0 `.panel-error`. |
| 44 px rule breaks the target matrix grid | wider switches/inputs at 360 px | horizontal overflow in the sheet | Phone grid already 2-row (`style.css:226-233`); QA checks overflow with the sheet open at 360x640. |
| QA flake on timing | 5 s real ticks, 15 ms mock latency | false FAIL | Use `KM.pollNow()` for determinism plus one real tick; waits >= 6 s for pause checks; one re-run allowed, then report. |
| Backend gate misread | 638 baseline vs 596 in this clone | false regression alarm or fake green | Use the FLOW gate (>=596 + identical failure set) and say so explicitly in the report. |
| Hash `#appguard` bookmarks | removed tab | lands on Daemons | Intended; documented in DESIGN.md. |

## 7. Executors and order

Order: **Docs delta -> UI/UX (A then B in one pass, same files) -> QA -> Judge**. UI before backend because the backend contract is already complete (section 3); Backend stage skipped with written evidence.

| Step | Executor (model, effort) | Files | Done when |
|---|---|---|---|
| 1 Docs delta | opus, high | `docs/DESIGN.md`, `docs/PRD.md`, `docs/NIGHT-NOTES.md` | Checklist docs item true; no code touched. |
| 2 UI/UX | opus, high | the 6 webroot files in section 2 | `node --check` x5 clean; greps clean; self smoke with existing mock loads 3 tabs. |
| 3 Backend | opus, high - **not run** | none | "No backend change" table in NIGHT-NOTES. |
| 4 QA | sonnet, high | `tests/ui/qa.py`, `tests/ui/mock.js`, `tests/evidence/ui-night/**` | `report.json ok:true`, 10 screenshots + 2 sheet shots, backend gate met. FAIL -> back to Planning (max 2 loops). |
| 5 Judge | fable, high (fallback opus, high) | `docs/NIGHT-JUDGE.md` only | Pass/fail with evidence paths; never fixes code. |

TODO: [ ] docs delta [ ] UI A [ ] UI B [ ] QA mock [ ] QA tests + evidence [ ] backend gate [ ] Judge [ ] NIGHT-REPORT

## 8. Loop 1 addendum (QA C3 fail)

**Trigger.** QA run 1 is 112/113 (`tests/evidence/ui-night/SUMMARY.md`, `report.json`). Only FAIL: C3. The Deep Sleep Cool gear opens its sheet, but the body shows `E_UNKNOWN pkgs.forEach is not a function` and the "Freeze while unplugged" switch never renders.

**Cause (pre-existing in base 8c289b7, not introduced tonight).** `module/webroot/js/add.js:329-330` calls `KM.call(['packages'])` and does `pkgs = res[1] || []`, then `pkgs.forEach(...)` (datalist `ds-pkgs`, about line 362). Backend `cmd_packages` (`module/bin/lib/km-appguard.sh:466-473`) returns `{"ok":true,"packages":["pkg",...]}`; its comment notes v1 printed a bare array. `tests/run.sh:333-335` pins the object shape. So the frontend still expects the v1 shape and the DSC sheet is broken on the real device too. Element type is the same in both shapes (package name strings), so only the outer wrapper needs normalizing.

**Fix (the only code change in this loop).** In `add.js` `openSettings()`, replace line 330:

```js
      var c = res[0], pkgs = res[1] || [];
```

with:

```js
      var r = res[1], c = res[0], pkgs = Array.isArray(r) ? r : (r && r.packages) || [];
```

Nothing else in the DSC sheet changes: same layout, same switch, same `setconf freeze_unplugged` write and `openSettings()` re-render, same "Never freeze" input and datalist.

**Other call sites checked.** `add.js` has one consumer of `packages` (line 329). `appguard.js:654-661` calls the different `appguard packages --user N` subcommand and already reads `r.packages || []`, so it doesn't have this bug and stays untouched.

**Why it's in scope.** The mission says the DSC sheet "stays as it is" (design and behaviour), and acceptance requires "Deep Sleep Cool gear still opens its sheet". Today it opens to an error, so this fix makes the existing sheet work as designed. It's a crash fix: no redesign, no new behaviour, no backend or test-contract change, and the backend stays on the pinned object shape.

**Unattended decision (recorded).** The user is asleep. I'm fixing the frontend to accept both shapes instead of (a) leaving C3 failing or (b) changing the backend back to a bare array. (b) would break `tests/run.sh:333-335` and the documented v1-to-v2 contract. Accepting both shapes is the most conservative option: it works with the current backend and with any older v1 module. Goes into NIGHT-REPORT.

**Executor.** UI/UX: opus, high. Edit only `module/webroot/js/add.js`, line 330 as above. Done when `node --check module/webroot/js/add.js` is clean and `git diff --stat` shows exactly one file and one changed line.

**QA delta (sonnet, high).** No edits to `qa.py`/`mock.js` unless a harness bug turns up (then record it).
- C3 (default mock, real `{ok,packages}` shape from `tests/ui/mock.js:74`): sheet title "Deep Sleep Cool", switch renders, switch toggles via `setconf freeze_unplugged`. Must PASS.
- C3b (diagnostic, `faults.packages='array'`, bare array, `mock.js:73`): must keep PASSING. Together with C3, this proves both shapes work.
- Re-run the full `tests/ui/qa.py` (all ten viewports plus sheet shots). Target `report.json ok:true`, 113/113 (or the new total with 0 FAIL). Refresh `tests/evidence/ui-night/SUMMARY.md` and `report.json`, and confirm the backend gate (`tests/run.sh` >= 596 with an identical failure set) is unchanged, since no backend file was touched.
- FAIL goes back to Planning loop 2 (the last one). If it still fails after that, report `blocked` in NIGHT-REPORT and don't fake a pass.

**Then.** Judge (fable, high; fallback opus, high) re-runs over the updated evidence.

TODO: [ ] add.js line 330 fix [ ] node --check [ ] QA full re-run (C3 + C3b PASS) [ ] evidence refreshed [ ] Judge
