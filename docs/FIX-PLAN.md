# FIX-PLAN - close Judge Mediums M1/M2/M3 + cheap extras

Spec: `/root/temp/konamanager-night/FIX_PROMPT.md` (Goal, Acceptance). Source of findings:
`docs/NIGHT-JUDGE.md` "Bugs found" 1-9. Line numbers are against the current (uncommitted night) tree.

## Objective

Close M1 (stale switch after in-flight `targets set` + row re-render), M2 (refresh dropped during an
in-flight poll), M3 (number fields commit on the blur caused by closing the sheet), plus the cheap
extras below. Every fix gets a browser regression in `tests/ui/qa.py` that passes on the new code and
FAILS on the pre-fix snapshot `/root/temp/konamanager-night/tmp/prefix-snapshot/webroot`.

Limits: edit only `repo/module/webroot/**` and `repo/tests/ui/**`. No `module/bin/**`. No cosmetic
1280px wrap fix. No backend redesign. No commit/push. Scratch under `/root/temp/konamanager-night/tmp/`.

Executors: implementation = **opus-5.5 (high), UI stage**, one subagent, items in the order below.
QA = **sonnet-5.5 (high)**. Judge = fable (writes `docs/FIX-JUDGE.md`).

## TODO (implementation order)

- [ ] T0 mock.js hooks (delay/snapshot, failOn, timestamps, add=E_CONFLICT)
- [ ] T1 M1 setTarget optimistic + resolve row by pkg
- [ ] T2 M2 load() coalesced follow-up
- [ ] T3 M3 number fields: Enter/Save only, close never commits
- [ ] T4 extras (E1 sheet focus, E2 neverAdd catch, E3 focus restore, E4 picker upsert, E5 skeleton, E6 picker error clear, E7 stale picker guard)
- [ ] T5 qa.py regressions R1-R8 + `fresh(pre_js=)`
- [ ] T6 `node --check` all changed JS; full QA new tree; QA against prefix snapshot (must FAIL R1-R3)

---

## T0 - `tests/ui/mock.js` hooks (executor: opus, UI stage)

File: `tests/ui/mock.js:2-9` (state init) and `:185-197` (`window.ksu.exec`), `:121-126` (`targets add`).

Edit:
1. Init: `st.delays = st.delays || {}; st.failOn = st.failOn || {}; window.__cmdT = [];`
2. `exec(cmd, cb)`:
   ```
   window.__cmds.push(cmd); window.__cmdT.push(performance.now());
   let ms = 15; for (const k in st.delays) if (cmd.indexOf(k) >= 0) ms = Math.max(ms, st.delays[k]);
   let code = null; for (const k in st.failOn) if (cmd.indexOf(k) >= 0) code = st.failOn[k];
   const pre = ms > 15 ? run() : null;     // delayed cmds are answered from state AT REQUEST TIME
   setTimeout(() => { const r = pre || run(); window[cb](r.errno, r.stdout, r.stderr); }, ms);
   function run() { try { return code ? fail(code, 'mock fault ' + code) : handle(cmd); } catch (e) { return {errno: 1, stdout: '', stderr: String(e)}; } }
   ```
   Keep the existing 15 ms / handle-at-delivery behaviour when no rule matches (no change to old checks).
   Why snapshot: a real backend reads state when the command runs; without it the "in-flight" `list`
   would see the post-start state and M2 could never reproduce.
3. `targets add` on an existing target returns `fail('E_CONFLICT', 'already a target')`, matching the
   backend (`km-appguard.sh:191`, Judge bug 7). Do not change `targets set`.

Verify: `node --check tests/ui/mock.js`; existing checks unchanged in the full run.
Done: hooks usable as `window.__mockState.delays = {"'list'": 1500}` / `failOn = {"'never' 'add'": 'E_BUSY'}`.

## T1 - M1 `module/webroot/js/appguard.js` setTarget (executor: opus)

Lines: `findTarget` :382, `patchRow` :385-397, `setTarget` :399-425, `onToggle` :427-434,
`onCooldown` :436-445, `ucell` :~366-380, sheet open/reset (where `sid` increments).

Edit:
1. Module var `var pend = {};` reset to `{}` wherever `sid` is incremented (sheet open).
2. Helper `rowFor(pkg)`: iterate `v && v.sec.targets.body.querySelectorAll('.target-row')`, return the
   one with `dataset.pkg === pkg` (no CSS selector built from the package name), else null.
3. `setTarget(pkg, u0, u999, cooldown)` (drop the captured `row` param; callers stop passing it):
   - `t = findTarget(pkg)`; return if `!t || pend[pkg]`.
   - `prev = {u0,u999,cooldown_s}`; **optimistic model write**: `t.u0 = !!u0; t.u999 = !!u999;
     t.cooldown_s = cooldown === 'default' ? null : Number(cooldown)`; `var tok = pend[pkg] = {}`.
   - `markBusy(rowFor(pkg))` (switches disabled + aria-busy) then `patchRow`-style aria write from `t`.
   - `.then(r)`: `if (pend[pkg] === tok) delete pend[pkg];` `t2 = findTarget(pkg)` (model may have been
     replaced); if `t2`: apply `r` (same field rules as today) to `t2`. If `!alive(my)` return.
     `secOk('targets'); patchRow(rowFor(pkg), t2); patchCounts();`
   - `.catch(e)`: `delete pend[pkg]` (if same tok); `t2 = findTarget(pkg)`; revert `t2` to `prev`
     **regardless of alive** (model must not keep the optimistic value); if alive: `var row = rowFor(pkg);
     patchRow(row, t2);` set cooldown input value from `t2`; `secError('targets', e)`.
4. `ucell` / `targetRow`: when `pend[t.pkg]`, render switches `disabled = true` + `aria-busy="true"`,
   so a row rebuilt mid-flight shows the optimistic state AND stays locked.
5. `onToggle` / `onCooldown`: return early when `pend[pkg]` (a rebuilt row must not fire a second
   concurrent `targets set`).

Why: rows rebuilt mid-flight (filter :297-303, Show more, remove, picker add, Never shadow) read the
model, so the model must already hold the intended value and the response must patch whatever row is
live at response time.
Verify: R1 + R1b; existing "C2 U0/U999 toggle ... same row node" stay green.
Done: after a forced re-render during a 1200 ms `targets set`, the live switch `aria-checked` ==
`KM.S.ag` == mock; on `E_BUSY` all three equal the pre-toggle value.

## T2 - M2 `module/webroot/js/daemons.js` load() (executor: opus)

Lines: `load` :343-360, `canPoll` :364 (unchanged), `runAction` :398-405 (unchanged callers).

Edit:
```
function load(silent) {
  if (S.loading) { S.again = true; return S.loadP; }      // coalesce: one follow-up max
  S.loading = true;
  if (!silent || !S.loaded) render();                      // E5: first load paints the skeleton
  S.loadP = KM.call(['list'], KM.T.read).then(<ok as today>, <err as today>).then(function () {
    S.loading = false;
    if (S.again) { S.again = false; return load(true); }   // reply is stale: skip paint, chain one reload
    render();
    return true;
  });
  return S.loadP;
}
```
`pollTick`/`canPoll` keep skipping while loading, so the 5 s poller never queues; only explicit
refresh callers (runAction, Retry, Refresh button, add.js, activate) set `S.again`. N refreshes during
one flight => exactly 1 follow-up. Skipping the stale paint keeps the card on `STARTING…` instead of
flashing `STOPPED`.
Why: Judge P6 - stale `list` reply won, `STOPPED` for up to 5 s.
Verify: R2; C7 "no-change poll ... pollNow True" stays green (pollNow still resolves `true`).
Done: card goes STARTING… -> RUNNING with no STOPPED sample; `list` bound below holds.

## T3 - M3 `module/webroot/js/appguard.js` number fields (executor: opus)

Lines: `numField` :152-170 (blur listener :165), `setNum` :172-195, `onChange` :755-758;
`module/webroot/js/core.js` `closeSheet` :297-310.

Decision: **drop blur-commit; commit only on Enter or Save click.** Escape/X/backdrop discard.
Justification: a "blur not caused by close" test is not reliable. X click focuses the X button first, so
`relatedTarget` is inside the panel. Backdrop click and Tab to a non-focusable area both give
`relatedTarget = null`, the same as Escape. Android WebView `relatedTarget` is also untested. Dropping
blur is the simplest option with no ordering race, and it's what FIX_PROMPT prefers.

Edit:
1. Delete the `blur` listener (:165). Keep the Enter keydown and Save click.
2. Unsaved cue (no new CSS): on `input`, if `i.value !== String(saved value)` add class `primary` to
   Save and set the hint span text to `'Unsaved - press Enter or Save'`; restore hint `min–max` and
   drop `primary` after a successful save or when the value matches again.
3. Defense in depth: `core.js closeSheet`: before `clear(root)` set `if (KM.S.modal) KM.S.modal.closing = true;`.
   In `setNum` and `onChange` (targets cooldown `change` path) return early when
   `!alive(sid) || (KM.S.modal && KM.S.modal.closing)`. This also covers a `change` fired by removal.

Why: Judge P13 - Escape sent `appguard set interval 999` silently.
Verify: R3a/R3b/R3c; existing "C2 interval set 90 / default cooldown 450" (Enter path) stay green.
Done: Escape or X after typing sends zero `appguard set` / `targets set`, config unchanged, reopen shows old value.

## T4 - extras (executor: opus)

| # | Item | Decision | Edit | Reason |
|---|------|----------|------|--------|
| E1 | `core.js:372` initial focus skips disabled | **DO** | selector -> `'button:not([disabled]),input:not([disabled]),select:not([disabled]),textarea:not([disabled])'`, fallback `x` | one line, Judge bug 4 |
| E2 | `appguard.js:512` neverAdd via Enter rejection | **DO** | `neverAdd(inp.value.trim(), inp).catch(function () {});` (error already shown by secError in neverAdd :544) | one line, kills unhandled rejection |
| E3 | focus restore after in-sheet section re-render | **DO (sheet only)** | in `guarded(key, fn)` :33: before `fn`, if `document.activeElement` is inside `sh.panel` and has `data-ag-act`, store `v.refocus = act`. After `fn`, if focus is no longer inside `sh.panel` (body/null), focus the first `[data-ag-act="<v.refocus>"]:not([disabled])` in the panel (`{preventScroll:true}`) and clear `v.refocus`; if none is enabled yet (busy render), focus `sh.panel` (give it `tabindex="-1"` in core KM.sheet) and keep `v.refocus` for the next render of that section | keeps focus inside the dialog after Start/Stop/Restart/Run once |
| E3b | focus restore on daemon cards (`daemons.js:175`) | **SKIP** | - | out of the sheet; morph keeps nodes, Low, not requested |
| E4 | picker `targets add` on existing target | **DO (upsert)** | `appguard.js:~689`: `ex = findTarget(pkg)`; if `ex` send `['appguard','targets','set',pkg,'u0='+(u===999 ? (ex.u0?1:0) : 1),'u999='+(u===999 ? 1 : (ex.u999?1:0)),'cooldown='+(ex.cooldown_s==null?'default':ex.cooldown_s)]`, else today's `add`. Response handling unchanged (it already merges into `findTarget`); add `.catch` that re-enables row + `KM.showError(err, e)` if missing | matches backend E_CONFLICT; ~6 lines |
| E5 | first-load skeleton | **DO** | covered in T2 (`if (!silent \|\| !S.loaded) render()`); skeleton is `.skeleton`, not `.card`, so `fresh()`'s card wait is unaffected | one line, dead branch becomes live |
| E6 | clear picker error on success | **DO** | in `loadRows` success (:658) call `KM.hideError(err)` before painting | one line |
| E7 | stale picker replies | **DO** | `loadRows`: `var seq = p.seq = (p.seq \|\| 0) + 1;` and in then/catch `if (seq !== p.seq) return;` (keep existing user/alive guards) | two lines |
| E8 | sheet Status live refresh (bug 10) | **SKIP** | - | not requested; needs a timer while modal open |
| E9 | 1280px wrap (bug 11) | **SKIP** | - | explicitly excluded |

Verify: R4-R8 below. Done: every DO row has a passing check.

---

## T5 - QA changes, `tests/ui/qa.py` (executor: opus writes, sonnet runs)

Harness edits:
- `fresh(w, h, section, url=None, wait_cards=True, pre_js=None)`: if `pre_js`, `pg.add_init_script(pre_js)`
  after the mock (lets a section set delays before the first `list`).
- New sections run on their own `fresh()` page, after C9 and before C10 viewports. Wrap every wait in
  `try/except TimeoutError` and record a FAIL `check(...)` instead of aborting, so the snapshot run
  completes and shows which regressions fail.
- Every section ends with `check('<id>: zero console/page errors', errs_now() == e0, ...)` and resets
  `delays`/`failOn` to `{}`.

Regressions (each must FAIL on the prefix snapshot; the "old fails because" column is the proof):

| ID | Steps | Assert | Old code fails because |
|----|-------|--------|------------------------|
| R1 M1 | sheet open; `pkg0` = first target, `u0` before = B; `delays={"'targets' 'set'":1200}`; click its `.u0 .switch`; within 100 ms fill the Targets filter (`.ag-sec[data-sec=targets] input[type=search]`) with `pkg0`, wait 300 ms, fill `''`, wait 300 ms (two full `renderRows`, still in flight); sample live switch; then wait for no `aria-busy` (<=3 s) + 200 ms | mid-flight: live switch `aria-checked == str(!B)` and `disabled`; final: live `aria-checked` == `KM.S.ag` `u0` == mock `u0` == `!B`, switch enabled, row node is the live one | re-rendered row shows B; response patches the detached row, so final live `aria-checked` == B != mock |
| R1b M1 err | same, `failOn={"'targets' 'set'":'E_BUSY'}` + delay 600, re-render mid-flight | final live `aria-checked` == `KM.S.ag` == mock == B; `.ag-sec[data-sec=targets]` error box visible | old reverts only the detached row |
| R2 M2 | fresh daemons page; `delays={"'list'":1500}`; `n0`; `evaluate("() => { KM.pollNow(); return 1 }")`; wait 150 ms; start a 25 ms sampler of `.card[data-id=sim-monitor] .state` text into `window.__samp`; click `.card[data-id=sim-monitor] [data-act=start]`; then `evaluate("() => { KM.daemons.load(true); KM.daemons.load(true); return 1 }")`; wait until `.card[data-id=sim-monitor]` state `data-s == 'running'` (timeout 6 s); +300 ms; stop sampler | (a) final RUNNING and primary button `data-act=stop`; (b) after the first `STARTING…` sample no `STOPPED` sample; (c) **bound**: `list` calls issued while the first list was in flight == 0, follow-ups issued within 200 ms of its completion (via `__cmdT`) == exactly 1, total `list` calls in the window <= 3 (2 expected; +1 tolerates one 5 s poll tick) | (b) deterministic: the stale in-flight reply paints `STOPPED`; (c) zero follow-ups |
| R3a M3 | sheet open; `cfg0 = mock interval_s`; `n0`; click Interval, `fill('999')`; press Escape; wait 400 ms | sheet closed; no `cmds[n0:]` containing `'appguard' 'set'`; mock `interval_s == cfg0`; reopen sheet: Interval value == `str(cfg0)` | blur on close sends `set interval 999` (Judge P13) |
| R3b M3 | as R3a with Default cooldown, `fill('5')`, close via the X (`[aria-label=Close]` in modal head) | no `'appguard' 'set'`; mock `cooldown_s` unchanged | blur with relatedTarget=X commits |
| R3c M3 guard | target cooldown `fill('77')`, Escape | no `'targets' 'set'` with `cooldown=77` | not required to fail on old (guard check only) |
| R3d positive | Interval `fill('120')` then click Save | `'set' 'interval' '120'` sent, mock 120 | (sanity, passes on both) |
| R4 E1 | fresh page, click gear without any force-focus, wait 300 ms | `document.activeElement` inside `.modal-panel` and `!activeElement.disabled` | focus stays on the gear (disabled Start chosen) |
| R5 E2 | `failOn={"'never' 'add'":'E_BUSY'}`; type `com.demo.x` in Never input; Enter; wait 400 ms | Never error box shows `E_BUSY`; `page_errors` unchanged | unhandled rejection -> pageerror |
| R6 E4 | target `pkg0` with u0=1,u999=0 in mock; open picker in U999 mode (picker user control, `appguard.js ~600-640`); click `pkg0` row | a `'targets' 'set' '<pkg0>'` with `u0=1` and `u999=1` sent, no `'targets' 'add' '<pkg0>'`; mock u0 & u999 true; no picker error | old sends `add` -> E_CONFLICT (new mock) |
| R7 E5 | `fresh(..., wait_cards=False, pre_js="window.__mockState.delays={\"'list'\":1500}")`; at 300 ms | `#daemon-list .skeleton` count == 3, `#daemon-count` text `loading`; then cards appear | list empty (0 children) |
| R8 E6/E7 | picker: `failOn` packages once -> error shown; clear `failOn`, type query -> success | picker error box hidden after success. Stale: `delays={"'packages'":900}` type `a`, then clear delay and type `b` | rows reflect query `b` (first row/request order via `__cmds`); error hidden | error stays; slow `a` reply overwrites `b` |

R3 note: the snapshot also has the blur path for R3b. R6 note: on old code other mocks also return
E_CONFLICT for existing-target adds; that only affects new checks.

## T6 - verification (executor: sonnet, QA stage)

From `repo/`:
```
node --check module/webroot/js/appguard.js module/webroot/js/daemons.js module/webroot/js/core.js tests/ui/mock.js
KM_EVID=tests/evidence/ui-fix KM_QA_PORT=8198 python3 tests/ui/qa.py 2>&1 | tee /root/temp/konamanager-night/tmp/qa-fix.log
# proof the regressions bite: same new qa.py + mock against the pre-fix webroot
KM_WEBROOT=/root/temp/konamanager-night/tmp/prefix-snapshot/webroot KM_EVID=/root/temp/konamanager-night/tmp/qa-prefix KM_QA_PORT=8199 \
  python3 tests/ui/qa.py 2>&1 | tee /root/temp/konamanager-night/tmp/qa-prefix.log   # expected exit 1
grep -E '^FAIL (R1|R1b|R2|R3a|R3b|R4|R5|R6|R7|R8)' /root/temp/konamanager-night/tmp/qa-prefix.log
git -C /root/temp/konamanager-night/repo diff --stat -- module/bin   # must print nothing
```
`KM_WEBROOT` already exists (`qa.py:23`). The snapshot run uses the new `tests/ui/mock.js`, so only
the webroot differs.

## Acceptance checklist

- [ ] `node --check` passes on every changed JS file.
- [ ] New tree: all checks PASS, total >= 114 + new checks, 10 viewports, C7 stress green,
      C11 zero console error / pageerror, warnings only from C9.
- [ ] Snapshot run: R1, R2, R3a, R3b, R4, R5, R6, R7 FAIL (R1b, R8 expected FAIL; R3c/R3d not required).
- [ ] R2 bound holds: 0 list calls during flight, exactly 1 coalesced follow-up, <= 3 total in window.
- [ ] `git -C repo diff --stat` shows no `module/bin/**`; changes only under `module/webroot/**`, `tests/ui/**`, `docs/`.
- [ ] Nothing committed, pushed, deployed or copied to the phone.

## Risks and fallbacks

| Risk | Cause | Consequence | Fallback |
|------|-------|-------------|----------|
| Snapshot run doesn't fail R2 | a 5 s poll tick lands between flight end and the sample | old code could self-heal | (b) "no STOPPED sample" is deterministic: the stale paint happens before any tick can run (`canPoll` false while loading) |
| Optimistic M1 leaves the model wrong if sheet closes and call fails | `alive` false | stale model until next `appguard get` | catch reverts model regardless of `alive` (T1.3) |
| `pend` lock never clears | promise never settles | row stuck busy | `KM.call` has `KM.T.mut` timeout -> catch path clears `pend` |
| Coalesced follow-up loop | `S.again` set during each follow-up | extra list calls | only explicit callers set it; poller never does; bounded by R2 (c) |
| Dropping blur-commit surprises users who Tab away | value stays typed but unsaved | lost edit on close | visible "Unsaved - press Enter or Save" hint + primary Save; Enter is the IME Done action on Android |
| Skeleton (E5) breaks an old check (e.g. count text, MutationObserver) | first-load paint now visible | check fails | revert E5 only (single line), mark SKIP in FIX-REPORT |
| E3 focus restore fights the existing explicit focus calls (`appguard.js:242,476,542,555`) | double focus | focus jumps | restore only when focus left the panel (activeElement is body/null) |
| mock E_CONFLICT breaks an existing check that re-adds a target | old checks relied on upsert | FAIL in C2/C7 | point that check at a non-target package; never weaken an assertion |
| Loop limit | Judge FAIL twice | blocked | stop, record exact failing checks in FIX-REPORT.md |

## Loop 2 addendum

Scope: M-1, L1, L2, L3, L5 (all MUST). Nothing else. Edits only under `repo/module/webroot/**` and `repo/tests/ui/**`.
Executors: W1 = UI stage, opus-5.5 (high), one subagent, does every code + qa.py edit below in order. QA = sonnet-5.5 (high). Judge = fable.
Every new check must FAIL on `KM_WEBROOT=/root/temp/konamanager-night/tmp/loop1-snapshot-webroot` and PASS on `repo/module/webroot`; record both runs.

### T1 M-1 per-app cooldown commits on Enter only (W1)
- `appguard.js:907` delete `sh.body.addEventListener('change', onChange);` and replace with `sh.body.addEventListener('keydown', onCoolKey);`.
- `appguard.js:828-832` replace `onChange` with:
  `function onCoolKey(ev) { var t = ev.target; if (ev.key !== 'Enter' || !t || !t.dataset || !t.dataset.agCool) return; ev.preventDefault(); if (!alive(sid) || (S.modal && S.modal.closing)) return; onCooldown(t); }`
- `appguard.js:390-394` (row build) add `ci.enterKeyHint = 'done';` and an `input` listener that toggles class `unsaved` + `title='Unsaved - press Enter'` when `value.trim()` differs from the model value; `patchRow` (`:431`) clears both when it writes the value. CSS: one rule `.target-row .cool input.unsaved { border-color: var(--warn, #c80); }` in the existing sheet stylesheet.
- Why: blur from X / backdrop fires `change` before `closing` is set; Interval already uses Enter/Save only (M3).
- Old check C2 (`qa.py:437-438`): replace `pg.keyboard.press('Tab')` with `pg.keyboard.press('Enter')`. The assertion text and condition stay byte-identical. Decision recorded: Tab-commit is the removed behaviour, so the trigger changes and the assertion does not.
- Tests, in the R3 block after R3c (`qa.py:992`), using the same row-0 input, reopened sheet each time:
  - R3c-X: click, fill `77`, click `#modal-root .modal-head [aria-label=Close]`, wait 400 -> no cmd with `'targets' 'set'` and `cooldown=` after n0; mock `cooldown_s` of pkg0 unchanged; reopen shows the old value.
  - R3c-backdrop: viewport 1280x800 (`fresh(1280, 800, ...)`), fill `55`, `pg.mouse.click(5, 5)` on `.modal-backdrop`, same three asserts.
  - R3c-Enter (positive): fill `77`, press Enter -> exactly one `targets set ... cooldown=77`, mock stores 77.
- Done: 3 new checks PASS; R3c-X and R3c-backdrop FAIL on the snapshot (it sends `cooldown=77/55`).

### T2 L1 stale failure must not revert a newer write (W1)
- `appguard.js` top (near `:12`): add `var seq = {}; /* pkg -> last request no., never reset by open/cleanup */`.
- `setTarget` `:455`: after the `pend` check add `var n = seq[pkg] = (seq[pkg] || 0) + 1;`.
- `:480-481` change to `var t2 = findTarget(pkg); if (t2 && seq[pkg] === n) { t2.u0 = prev.u0; t2.u999 = prev.u999; t2.cooldown_s = prev.cooldown_s; }`. Leave the success branch as is (mock and device apply in command order; noted as open risk).
- Test R9 (new `fresh(390, 844, 'R9 L1')`): open AG, read pkg0 u0/u999 (b0, c0). Set `failOn` and `delays` keyed by the exact first-command substring `"'<pkg0>' 'u0=<1-b0>' 'u999=<c0>'"` -> `E_BUSY`, 2000 ms. Click U0, press Escape, `open_ag`, click U999 of pkg0 (fast, succeeds), wait 2600 ms, force a rows re-render (`rerender_mid_flight` helper or filter type+clear). Assert `KM.S.ag` u999 == mock u999 == `not c0` and live switch aria-checked matches.
- Done: R9 PASS; FAIL on the snapshot (model reverts u999).

### T3 L2 cooldown input locked while the row's `targets set` is in flight (W1)
- `markBusy` `:441-444`: also `var ci = row && row.querySelector('input[data-ag-cool]'); if (ci) ci.disabled = true;`.
- `patchRow` `:426-431`: set `ci.disabled = false` (before the value write).
- Row build `:390-394`: `if (pend[t.pkg]) ci.disabled = true;`.
- Catch path `:486-487` already calls `patchRow` first, so it re-enables; no other change.
- Test R10: `delays {"'targets' 'set'": 1000}`, click row-0 U0, after 100 ms read `input[data-ag-cool]` of pkg0 -> `disabled === true`; `wait_unbusy` -> `disabled === false`; then fill `77` + Enter -> one `cooldown=77` cmd, mock stores 77.
- Done: R10 PASS; FAIL on snapshot (input enabled mid-flight).

### T4 L3 tab activation joins the in-flight load (W1)
- `daemons.js:345-346`: `function load(silent, join) { if (S.loading) { if (!join) S.again = true; return S.loadP; }`.
- `daemons.js:371` pollTick: `load(true, true)`. `core.js:273`: `KM.daemons.load(true, true)`. Mutation callers (`daemons.js:406,410,543`, `add.js`, `core.js:428` refresh) unchanged, so R2 coalescing stays.
- Check `KM.daemons.load` is exported as `load` itself (not a wrapper dropping args); if wrapped, pass the 2nd arg through.
- Test R11: `fresh(390, 844, 'R11 L3', wait_cards=False, pre_js="window.__mockState.delays = {\"'list'\": 1000};")`; within the flight switch Logs -> Daemons 3 times (existing tab-click selectors in qa.py). Assert `list` calls with `ts < t_first + 1300` == 1, and cards present by `t_first + 1400`.
- Done: R11 PASS, R2 still PASS; R11 FAIL on snapshot (2+ list calls, cards late).

### T5 L5 Tab trap wraps from the panel fallback (W1)
- `core.js:367-369` replace with:
  `var a = document.activeElement, out = a === panel || !panel.contains(a);`
  `if (ev.shiftKey && (a === first || out)) { ev.preventDefault(); lastEl.focus(); }`
  `else if (!ev.shiftKey && (a === lastEl || out)) { ev.preventDefault(); first.focus(); }`
- Test R12: open AG sheet, `KM.S.modal.panel.focus()`, Shift+Tab -> `panel.contains(activeElement) && activeElement !== panel`; repeat with Tab.
- Done: R12 PASS; Shift+Tab case FAIL on snapshot (focus lands behind the dialog).

### Gates (QA)
- `node --check` on appguard.js, core.js, daemons.js; full `qa.py` green: 114 old + 26 loop-1 + new (R3c x3, R9-R12), 10 viewports, 0 console/page errors.
- Snapshot run: every new check except R3c-Enter fails. `git -C repo diff --stat -- module/bin` empty. No commit.

### Risks
- Enter on Android soft keyboard for `type=number`: if the IME sends no Enter keydown, per-app cooldown can't be committed. Mitigation: `enterKeyHint='done'`; real-WebView check stays an open risk in the report.
- R9/R11 are timing-based (2000 ms / 1300 ms windows); run three times, and widen margins (don't weaken the assertion) if they flake.
- Fallback: if any task breaks an old check and can't be fixed in one try, revert that task alone and mark it BLOCKED in FIX-REPORT.md.
