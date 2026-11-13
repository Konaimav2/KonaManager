# FIX-JUDGE - fix loop for NIGHT-JUDGE M1/M2/M3 + extras

Judge: independent audit, 2026-11-13 09:44-09:55 WIB, base `8c289b7`, working tree dirty, nothing committed.
Scope judged: the fix-loop delta only (pre-fix snapshot `tmp/prefix-snapshot/` vs current tree), on Chromium
headless + the 15 ms mock. Nothing here was fixed by the Judge.

## Verdict: PASS-WITH-RISKS (final, after loop 2)

Final state, 2026-11-13 10:12 WIB: M-1, L1, L2, L3 and L5 are closed (see "Loop 2 verdict" at the end).
Critical 0, High 0, Medium 0 confirmed, Low 5, plus one Medium device risk that only a real WebView can
clear. The text below is the loop-1 dossier, kept as written.

M1, M2 and M3 are closed as NIGHT-JUDGE described them, and I reproduced the proof myself (140/140 on my own
run, 17 of the new checks fail on the pre-fix webroot). No Critical or High defect. One Medium and six Lows are
new findings below; three of the Lows are small regressions introduced by this loop. The Medium is a judgement
call: the per-app cooldown field still commits a half-typed value when the sheet is closed with X or the
backdrop. That field was not part of M3 as written (`appguard.js:165`, Interval / Default cooldown), so I do not
count M3 as unclosed, but FIX-PLAN T3's own done-line ("Escape or X after typing sends zero `appguard set` /
`targets set`") is not met for it. If the owner reads M3 as "every number field", treat this as M3 partial and
run the second loop. This is not a ship verdict: real WebView QA has still not happened.

Counts: Critical 0, High 0, Medium 1, Low 6.

## What I ran

| Command / action | Result |
|---|---|
| `diff -ru tmp/prefix-snapshot/webroot repo/module/webroot`, `diff -ru tmp/prefix-snapshot/ui repo/tests/ui`, read in full | webroot: `appguard.js`, `core.js`, `daemons.js`, `style.css` (1 line). tests: `mock.js` (hooks + `add` conflict), `qa.py` (+296 lines, additive; only old line touched is the `fresh()` signature) |
| `KM_EVID=tmp/judge-evid KM_QA_PORT=8192 python3 tests/ui/qa.py` (from `repo/`) | `TOTAL: 140 passed, 0 failed`, exit 0, 0 console errors, 0 pageerrors (`tmp/judge-fix-qa.log`, `tmp/judge-evid/report.json`) |
| Check-name comparison: `ui-night/report.json` vs `ui-fix/report.json` vs my run | all 114 night check names present and green in my run; 26 new R checks; my 140 names identical to QA's |
| `tmp/qa-prefix-qa.log` (new qa.py + mock against the pre-fix webroot) read | 123 pass / 17 fail: R1 x2, R1b, R2 x2, R3a, R3b, R3c, R3d-cue, R4, R5 x2, R6, R7, R8 x2, C11 pageerror |
| Own adversarial probes, 9 scenarios, `tmp/judge-fix/probe.py` -> `tmp/judge-fix/probe.log` (port 8191) | see P-letters below |
| `node --check` on 5 webroot JS + `tests/ui/mock.js` | clean |
| `git -C repo log -1`, `status --short`, `diff --stat -- module/bin`, `diff --cached --stat`, `remote -v` | HEAD `8c289b7`; `module/bin` diff empty; nothing staged; no remote |
| Viewports in my `report.json`; screenshot `tmp/judge-evid/ag-sheet-390x844.png` read | 10 viewports overflow 0 / edge 0 / expected layout and columns; 3 sheet rows; sheet full-screen at 390 |

I did not re-run the prefix-snapshot QA myself; the fail-on-old claim rests on QA's log, which I read line by
line. I did not run the backend suite (no `module/bin` change).

## M1 / M2 / M3

| Item | Status | Evidence |
|---|---|---|
| M1 stale switch after in-flight `targets set` + re-render | CLOSED | `appguard.js:454-492`: optimistic model write, `pend[pkg]` token, row resolved by `rowFor(pkg)` (`:435`) at reply time; rebuilt rows render locked (`:412`); `onToggle`/`onCooldown` gated (`:494-506`). R1: mid-flight rebuilt switch `false`/disabled/busy, 1 command sent, final DOM == `KM.S.ag` == mock. R1b (E_BUSY): final DOM == model == mock == pre-toggle, error box shown. Prefix: R1 final `checked:'true'` vs mock `False`. P-C: sheet closed mid-flight, fail and success, model == mock both times, reopen correct. Lock leak: `KM.call` always settles (`core.js:190-196`, 35 s timeout -> catch clears `pend`); `pend = {}` on close/open (`:889`, `:896`). Residuals: L1, L2 |
| M2 refresh dropped during an in-flight poll | CLOSED | `daemons.js:345-367`: mid-flight `load()` sets `S.again`, returns the shared promise; stale reply is not applied; exactly one follow-up. R2: card ends RUNNING / `stop`, no STOPPED sample after STARTING, list offsets `[0, 1507]`, 0 calls in flight, 1 follow-up. Prefix: STOPPED painted, offsets `[0, 4592]`. P-K: three `load(true)` during one flight -> same promise x3, 2 `list` calls total, `loading`/`again` both false after. Poller cannot queue (`canPoll` needs `!S.loading`, `:370`), so hidden/modal pauses are unchanged. Residuals: L3, L4 |
| M3 number fields commit on close | CLOSED for Interval / Default cooldown | `appguard.js:186-198` blur listener gone, Enter + Save only, unsaved cue; `setNum` guard `:206`; `core.js:301` `closing` flag before teardown; `onChange` guard `appguard.js:828-830`. R3a (Escape), R3b (X) green, both fail on prefix. P-B: backdrop click after `999` -> 0 commands, config 60; Tab then Escape -> 0 commands; Enter commits `set cooldown 5`; Enter twice on the same value sends nothing extra. Per-app cooldown: Escape discards (R3c), X and backdrop still commit -> M-1 |

## Extras

| Item | Status | Evidence |
|---|---|---|
| E1 initial focus skips disabled | DONE | `core.js:375`; R4 (prefix: focus stayed on the gear) |
| E2 `neverAdd` Enter rejection | DONE | `appguard.js:579` (and `:822`); R5, prefix raised `pageerror: Object` |
| E3 focus restore in sheet | DONE, untested by QA | `appguard.js:35-59`, `core.js:326`. No R check covers it. P-E: keyboard Stop -> focus on panel while busy, then on Start; never left the dialog. Side effect: L5 |
| E4 picker upsert on existing target | DONE | `appguard.js:759-775` incl. `.catch`; mock now returns `E_CONFLICT` on `add` (`mock.js:127`); R6 |
| E5 first-load skeleton | DONE | `daemons.js:348`; R7 (prefix: 0 children, count `-`) |
| E6 / E7 picker error clear, stale reply guard | DONE | `appguard.js:724-727`, catch `:747`; R8 x2 |

## Bugs found (ranked)

**Medium**

- M-1. `appguard.js:828-832` + `:503-512`. The per-app cooldown commits on `change`, and clicking X or the
  backdrop blurs the field before `closeSheet` sets `closing`, so the guard at `:830` never sees it. P-A / P-B:
  type `77` in the first row's cooldown, click X -> `appguard targets set com.demo.app00 u0=1 u999=0 cooldown=77`
  is sent and the mock stores 77; same with a backdrop click at 1280x800 (`55`). Escape on the same field sends
  nothing. So the result depends on how the sheet is closed, the commit is silent (sheet already gone, no toast),
  and a half-typed `7` on the way to `77` gets saved. Pre-existing behaviour, not in NIGHT-JUDGE's M3, missed by
  QA because R3c only presses Escape (`qa.py` R3 block).

**Low**

- L1 (regression). `appguard.js:478-482` reverts the model to `prev` on a late failure "regardless of alive",
  while `pend` is wiped on close/open (`:889`, `:896`). P-J: toggle U0 with a slow failing `targets set`, press
  Escape, reopen, toggle U999 (succeeds) -> when the old command fails, model becomes `[true,false]` while the
  mock is `[true,true]`; the row still shows `true` until the next rows render, then flips to `false`. Needs a
  command that fails after a close + reopen + second toggle (35 s timeout or a long lock wait), so it is rare.
  The old code returned before touching the model when the sheet was gone.
- L2 (regression). `appguard.js:506` drops a cooldown edit while the same row has a `targets set` in flight, and
  the cooldown input is not disabled (`markBusy` `:441-444` locks switches only). P-D: toggle U0 (1 s reply),
  type `77`, Enter -> only the toggle command is sent; after the reply, and after a later blur, the input still
  shows `77` while model and mock are `null`. Window is one command round-trip on the same row.
- L3. `daemons.js:346-362` discards the in-flight reply for any mid-flight `load()`, including plain tab
  re-activation (`core.js:273`). P-F: first `list` takes 1 s, switch Logs -> Daemons once per flight, three times
  -> 4 `list` calls at 57/1058/2059/3060 ms, three good replies thrown away, cards at 4383 ms instead of about
  1060 ms. Bounded at one follow-up per flight, so not a storm, but the skeleton stays as long as the user keeps
  returning mid-flight. Only mutation callers (`runAction`, add flow) need the discard.
- L4. `daemons.js:404-411` clears `S.busy[id]` before fresh data arrives. P-G: Start during an in-flight poll,
  then any forced render before the follow-up lands (another card's action calls `render(true)`, `:391`) paints
  `STOPPED` with an enabled Start. Heals when the follow-up returns (one `list` round-trip, not 5 s). Pre-existing
  design; R2 passes because nothing renders in that gap.
- L5 (regression). `core.js:364-369`: the Tab trap wraps only when focus is on the first or last control. With
  the new panel fallback focus (`core.js:326`, `appguard.js:57`) P-E: Shift+Tab from the panel lands on a card's
  `delete` button behind the dialog. Window is the busy render of a lifecycle action; keyboard only.
- L6. `appguard.js:55`: once a refocus is "carried", the next render of that section focuses the first enabled
  `[data-ag-act]` in it. After a confirmed remove the stale `{rows, rm-confirm, carried}` entry survives the
  explicit filter focus (`:543`); if focus is on body or the panel at the next rows render it jumps to the first
  row's U0 switch. Read from code, not reproduced.

Not bugs: `S.loadP` now makes mid-flight callers wait for the follow-up (returns `true`, P-K); a first load that
fails while `S.again` is set is retried rather than reported, which is correct. No new unhandled rejection or
console error in any probe.

## QA quality

- R1, R2, R3a, R3b, R4-R8 assert live DOM, `KM.S.ag`, mock state, the command log and `__cmdT` timestamps. None
  is a tautology, and each fails on the pre-fix webroot for the stated reason. No old assertion was changed or
  removed; the mock got stricter (`add` conflict), not looser.
- Weak spots: R1b fails on old code only through the "locked mid-flight" clause (the old final state was right
  by accident) and does not assert the optimistic value mid-flight. R2's follow-up window (1490-1700 ms) is
  timing-based; green in three runs so far. R3c covers Escape only, which is why M-1 slipped through. No check
  for E3, for close-mid-flight in M1, for backdrop close in M3, or for a render in the M2 gap.

## Acceptance

| Item | Result |
|---|---|
| M1/M2/M3 regressions exist, pass, fail on old behaviour | PASS (my run + `tmp/qa-prefix-qa.log`) |
| >= 114 old checks green, 10 viewports, stress, 0 console/page errors | PASS, 114/114 old + 26 new, reproduced |
| `git -C repo diff --stat -- module/bin` empty | PASS |
| Nothing committed / pushed / deployed | PASS, HEAD `8c289b7`, nothing staged, no remote |

## Open risks

- Real WebView QA on the phone is still not done. Blur/change ordering on teardown, the soft keyboard's Done key
  as the only commit path for Interval / Default cooldown, and `focus({preventScroll})` are Chromium-desktop
  results only.
- Dropping blur-commit means a typed Interval that is never confirmed is lost on close. The "Unsaved" hint and
  primary Save are the only cue (R3d checks they appear).
- Mock replies in request order; on the device up to 3 commands run at once (`core.js:216`), so reply order for
  two `targets set` on one package is not guaranteed (L1 class).
- Carried over from NIGHT-JUDGE and untouched here: `add.js:330` sign-off, 638-pass backend re-check, sheet
  Status snapshot (bug 10), 1280px wrap (bug 11), daemon-card focus loss (bug 5, cards part).

## If a second loop is run, Planning re-opens

1. M-1: give the per-app cooldown the same rule as Interval (Enter commits, close discards), or mark the sheet
   closing on `pointerdown` of X / backdrop. Add R3 cases: per-app cooldown + X, + backdrop.
2. L1: skip the model revert when `sid !== my`, or only revert when the model still holds the optimistic value.
3. L2: disable the row's cooldown input while `pend[pkg]`, or replay the edit after the reply.
4. L3: discard-and-requeue only for mutation callers; let tab activation join the in-flight load.
5. L5: in `onKey`, treat `activeElement === panel` (or outside the panel) as an edge and wrap.

## Loop 2 verdict

Judge: same independent audit, 2026-11-13 10:06-10:12 WIB, base `8c289b7`, tree dirty, nothing committed. Delta
judged: `tmp/loop1-snapshot-webroot` vs `repo/module/webroot` (appguard.js, core.js, daemons.js, style.css) and
`tmp/loop1-snapshot-ui/qa.py` vs `repo/tests/ui/qa.py`. Chromium headless + mock only. Nothing was fixed by me.

**Verdict: PASS-WITH-RISKS (final for the whole fix run).** M-1 is closed. L1, L2, L3 and L5 are closed. No
Critical, High or Medium defect was introduced. It is not a clean PASS for two reasons: the per-app cooldown now
has exactly one commit path (an Enter keydown) and nobody has pressed Done on a real Android soft keyboard, and
loop 2 added one small keyboard regression (N1). Real WebView QA is still the gate before ship.

Counts after loop 2: Critical 0, High 0, Medium 0 confirmed (1 Medium unverified device risk, R-1), Low 5
(L4 and L6 carried untouched from loop 1; N1, N2, N3 new).

### What I ran

| Handle | Result |
|---|---|
| `tmp/judge-fix2/cur.log`, `tmp/judge-fix2/cur/report.json` (my full run, current tree, port 8171) | 154 passed, 0 failed, `ok=true`, console/page errors `[]`, 13 viewport rows overflow 0 / edge 0 |
| `tmp/judge-fix2/old.log`, `tmp/judge-fix2/old/report.json` (my full run, loop-1 snapshot webroot, port 8172) | 148 passed, 6 failed: R3c-X, R3c-backdrop, R9, R10 (lock mid-flight), R11, R12 Shift+Tab. Same six as QA's `tmp/qa-fix2-loop1.log` |
| `tmp/judge-fix2/probe.py` -> `probe.out` (current tree) | P1-P8 below, 0 console/page errors |
| `tmp/judge-fix2/probe_old.py` -> `probe_old.out` (loop-1 snapshot) | baseline for P1 and P3 |
| `tmp/judge-fix2/probe_leak.py` -> `probe_leak.out` (current tree, `targets set` that never replies) | lock released by the 35 s timeout |
| `node --check` on `module/webroot/js/*.js` and `tests/ui/mock.js` | clean |
| `git diff --stat -- module/bin`, `git diff --cached --stat`, `git remote`, `git log -1` | empty, empty, none, `8c289b7` |

QA's own evidence (`tests/evidence/ui-fix2/report.json` 154/0, `tmp/qa-fix2-r2.log`, `tmp/qa-fix2-r3.log`,
`tmp/qa-fix2-loop1.log` 148/6) matches what I got. I did not rely on it.

### Scope items

| Item | Result | Evidence |
|---|---|---|
| M-1 per-app cooldown: X / backdrop never commit, Enter commits | CLOSED | `appguard.js:845` (`keydown` Enter only), `:920` (the `change` listener is gone; `grep` finds no `change`/`blur` listener left in appguard.js). R3c-X, R3c-backdrop, R3c-Enter pass in my run and fail on the snapshot with `cooldown=77` / `cooldown=55` sent. P1: type 61 + Tab -> nothing sent (snapshot sent `cooldown=61`). P2: type + Done button -> nothing sent, mock `null`, reopen empty. |
| M-1 for the other number fields (Interval, Default cooldown) | CLOSED | `appguard.js:187-198` Enter or Save only. P5a Interval 777 + X -> no `appguard set`. P5b at 1280x800, Interval and Default cooldown 33 + backdrop click -> closed, nothing sent, reopen shows 60 / 300. R3a/R3b/R3d still pass. |
| L1 stale failure must not revert a newer write | CLOSED | `appguard.js:14`, `:473`, `:498` (`seq[pkg] === n` guards the revert). R9 passes; on the snapshot the model ends `false` while the mock is `true`. |
| L2 cooldown input locked while pending | CLOSED | `appguard.js:397`, `:443`, `:458-459`. R10 passes (`mid=true`, `after=false`); snapshot `mid=false`. Leak check: with a reply that never comes, input and switches are locked at 0.5 s and released at 37 s by the `KM.T.mut` 35 s timeout (`core.js:190-196`), section shows `E_TIMEOUT`. Rebuilt rows read `pend` at build time. No path leaves the input locked. |
| L3 tab activation joins the in-flight load | CLOSED | `daemons.js:345-346`, `:371`, `core.js:273`. R11: 1 `list` call, 6 cards at +1.4 s (snapshot: 2 calls, 0 cards). M2 is intact: mutation callers (`daemons.js:406`, `:410`, `:543`, `core.js:429`) still call `load(true)` and set `S.again`; R2 passes in my run with `list_total=2, in_flight=0, follow_ups=1`, no STOPPED after STARTING. `KM.activate`'s `force` argument has no caller, so no refresh path was turned into a join. |
| L5 Tab / Shift+Tab wrap from the panel | CLOSED | `core.js:368-370`. R12 both directions land inside the dialog; Shift+Tab fails on the snapshot. |

### New findings

**Medium (unverified risk, not a reproduced defect)**

- R-1. `appguard.js:845` is the only way to save a per-app cooldown. There is no Save button on the row and blur
  no longer commits (correct for M-1). If the phone's soft keyboard does not deliver a `keydown` with
  `key === 'Enter'` for the Done key on `type=number`, the per-app cooldown cannot be edited at all, where loop 1
  could at least save on blur. The code does what it can: `enterkeyhint="done"` is set (P7 reads it back as
  `done`, `appguard.js:396`), and Chromium's WebView sends a synthetic Enter for the Done action. So I do not rate
  this a code defect. It has to be pressed once on the real device before ship; Interval / Default cooldown are
  not exposed the same way because they have Save.

**Low**

- N1 (regression, loop 2). `appguard.js:458-459`: `markBusy` disables the cooldown input that has focus, so after
  Enter the focus falls to `<body>` and is not restored by `patchRow` (`:443`). P3 on the current tree:
  `activeElement` is `BODY`, the next Tab goes to the dialog's `Close` button. Same probe on the loop-1 snapshot:
  focus stays on the `INPUT`, the next Tab goes to `Remove com.demo.app00`. Keyboard users lose their place after
  every cooldown commit; the L5 wrap keeps them inside the dialog. Touch users are not affected.
- N2. `appguard.js:845` (and `:197` for Interval / Default) test `ev.key` only. P4a: a `keydown` with
  `key: 'Unidentified', keyCode: 13` commits nothing; P4b: `key: 'Enter'` commits `cooldown=62`. A
  `|| ev.keyCode === 13` fallback is the cheap hardening for R-1.
- N3. The unsaved cue on the per-app input is a border colour plus a `title` (`appguard.js:424-427`,
  `style.css:252`). `title` never shows on touch, and colour alone is the only signal. A typed value is dropped
  without a message on Done (P2) and when the same row is toggled (P8: typed 99, toggled U999, input back to 63,
  cue cleared). That is the agreed close-discards rule; the cue is just weak on the device this UI runs on.
- L4, L6 from loop 1: out of scope for loop 2, untouched, still open.

Still true from loop 1: a late *success* reply is not guarded by `seq` (`appguard.js:481-489`), only the failure
is. With up to 3 commands in flight (`core.js:216`) reply order for two `targets set` on one package is not
guaranteed on the device. FIX-PLAN records it as accepted.

### QA quality

- The C2 (`qa.py:438`) and C7 (`qa.py:731`) change from Tab to Enter is legitimate. The diff touches only the
  key press; both assertion texts and conditions are byte-identical, and they still demand the command and the
  stored mock value. Tab-commit is the behaviour the scope decision removed, so keeping Tab would have tested
  the bug. Not a weakened assertion.
- New checks assert the command log, mock state, `KM.S.ag`, live DOM and `__cmdT` timestamps. Six of them fail on
  the loop-1 webroot for the stated reason. R3c-Enter, R10's second check and R12's Tab case pass on old code
  too; they are positive controls, which is fine.
- Gaps, all covered only by my probes: nothing in `qa.py` pins "blur to another control does not commit", "Done
  button discards", the `unsaved` class, `enterkeyhint=done`, focus after an Enter commit (N1), or the lock
  release on timeout. R9 and R11 are timing-based (2000 ms / 1300 ms windows); green in QA's three runs and mine.

### Acceptance

| Item | Result |
|---|---|
| M-1 closed for Interval, Default cooldown and per-app cooldown (Enter / Save commits, close discards) | PASS |
| L1, L2, L3, L5 closed, each with a check that fails on loop-1 code | PASS |
| 154/154, 10 viewports + 3 sheet viewports overflow 0 / edge 0, 0 console/page errors, reproduced | PASS |
| No new Critical / High / Medium defect | PASS (1 Low regression N1, 1 Medium device risk R-1) |
| `module/bin` untouched, nothing committed / pushed / deployed | PASS |
| Real WebView / soft-keyboard check | NOT DONE (out of reach for this run) |

### If Planning re-opens

1. R-1 + N2: press Done on the phone's keyboard in a per-app cooldown field and confirm `targets set` is sent.
   Add `|| ev.keyCode === 13` at `appguard.js:845` and `:197`. If the device sends no Enter, add a visible
   commit control to the row.
2. N1: after the reply, refocus the row's cooldown input when it had focus at `markBusy` time; add a check that
   `activeElement` is that input after Enter.
3. N3: give the per-app input a visible text cue like the Interval hint. Add `qa.py` checks for Tab-blur and
   Done-button discard.
4. L4, L6 as listed in loop 1.
