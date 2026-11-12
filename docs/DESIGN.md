# KonaManager - Simple Daemon Manager: DESIGN

Implements `docs/PRD.md` on the `dm` contract in `PLAN.md` section 4. Every `dm` name below is `DM=/data/adb/modules/daemon-manager/bin/dm` (one path, fixes the old two-path bug). Decisions are tagged **[D#]**.

## 1. Brand
- **Name:** `KonaManager - Simple Daemon Manager`. Header shows "KonaManager" with the subtitle "Simple Daemon Manager" (subtitle hidden below 600 px; full text stays in `<title>` and the About tab). `config.json` title = `KonaManager`.
- **Mark:** 28 px rounded square, accent stroke on ink, a "K" built from a vertical stem and two arms meeting at a signal dot. Inline SVG, no external file:
  `<svg viewBox="0 0 32 32" aria-hidden="true"><rect x="1" y="1" width="30" height="30" rx="8" class="mk-bg"/><path d="M11 8v16M11 16l9-8M11 16l9 8" class="mk-k"/><circle cx="22" cy="16" r="2.4" class="mk-dot"/></svg>` (`mk-k`: stroke accent, width 2.6, round caps; `mk-dot` pulses once on load, static under reduced motion).
- **Tone:** terse, factual, operator voice. "Stopped. 2 pids still alive (412, 977)." Never "Oops". Error text = what happened + what to do next. Numbers over adjectives.
- **Visual language: dark control room.** Near-black ink canvas with a faint 24 px dot grid (CSS radial-gradient, no image). Panels are slightly lifted slabs with a 1 px hairline and a 3 px **status rail** on the card's left edge colored by state. Telemetry (pid, uptime, ports, versions, packages, logs) is monospace; labels are small caps-style uppercase 12 px with letter spacing. State is always a dot + text label + shape (never color alone). Accent is signal cyan; green/amber/red are reserved for state. Replaces the old flat card list.

## 2. Design tokens (CSS custom properties, `css/tokens.css`, system fonts only)
```css
:root {
  /* color: surfaces */
  --km-bg:#080b0f; --km-bg-grid:#0d1218; --km-panel:#0f151c; --km-panel-2:#141c25; --km-panel-3:#1b2530;
  --km-line:#1f2a36; --km-line-strong:#2c3a49; --km-scrim:rgba(4,7,10,.72);
  /* color: text (on --km-panel: 15.8 / 8.1 / 5.4 : 1) */
  --km-text:#e6edf3; --km-text-2:#9fadbb; --km-text-3:#8493a2;
  /* color: signal */
  --km-accent:#5cc8ff; --km-accent-ink:#04141f; --km-accent-soft:rgba(92,200,255,.12); --km-accent-line:rgba(92,200,255,.42);
  --km-ok:#3ddc97; --km-ok-soft:rgba(61,220,151,.12);
  --km-warn:#f5b942; --km-warn-soft:rgba(245,185,66,.12);
  --km-err:#ff6b6b; --km-err-soft:rgba(255,107,107,.12); --km-err-line:rgba(255,107,107,.45);
  --km-idle:#8593a1; --km-idle-soft:rgba(133,147,161,.14);
  /* type */
  --km-font:system-ui,-apple-system,"Segoe UI",Roboto,"Helvetica Neue",Arial,sans-serif;
  --km-mono:ui-monospace,SFMono-Regular,Menlo,Consolas,"Roboto Mono",monospace;
  --km-fs-xs:12px; --km-fs-sm:13px; --km-fs-md:15px; --km-fs-lg:17px; --km-fs-xl:22px; --km-fs-2xl:28px;
  --km-lh-tight:1.2; --km-lh:1.45; --km-fw:400; --km-fw-med:550; --km-fw-bold:700; --km-track-label:.08em;
  /* spacing (4 px base) */
  --km-s1:4px; --km-s2:8px; --km-s3:12px; --km-s4:16px; --km-s5:24px; --km-s6:32px; --km-s7:48px;
  --km-hit:44px; --km-pad-x:12px; --km-header-h:52px; --km-bar-h:60px; --km-content-max:1120px;
  /* radius */
  --km-r-sm:6px; --km-r-md:10px; --km-r-lg:14px; --km-r-pill:999px;
  /* elevation */
  --km-e0:none; --km-e1:0 1px 0 rgba(255,255,255,.03) inset,0 1px 2px rgba(0,0,0,.5);
  --km-e2:0 8px 24px rgba(0,0,0,.45); --km-e3:0 20px 60px rgba(0,0,0,.65);
  --km-focus:0 0 0 2px var(--km-bg),0 0 0 4px var(--km-accent);
  /* motion */
  --km-ease:cubic-bezier(.2,.7,.2,1); --km-dur-1:120ms; --km-dur-2:200ms; --km-dur-3:320ms;
  /* readable by QA: active layout mode */
  --km-layout:phone;
}
@media (min-width:600px){:root{--km-layout:tablet;--km-pad-x:24px;--km-header-h:60px}}
@media (min-width:1000px){:root{--km-layout:desktop;--km-pad-x:32px}}
@media (prefers-reduced-motion:reduce){:root{--km-dur-1:0ms;--km-dur-2:0ms;--km-dur-3:0ms}}
```
Sizes: body `--km-fs-md`, card title `--km-fs-lg` bold, telemetry `--km-fs-sm` mono, labels `--km-fs-xs` uppercase. Minimum touch target `--km-hit`. Input font-size is at least 16 px on phone so the WebView does not zoom. Motion: state-dot color 200 ms, card busy sweep (a 2 px indeterminate bar on the status rail), modal enter 200 ms translateY 12 px + fade, no motion over 320 ms, nothing animates layout properties.

## 3. App shell
```
header  [mark] KonaManager  Simple Daemon Manager        [conn chip] [refresh]
tabs    Daemons | AppGuard | Logs | About        (tablist)
main    <section role=tabpanel> one visible at a time
toast   bottom-center live region (polite), errors use role=alert inline instead
```
- **Header:** sticky, `--km-header-h`, blur-free solid `--km-panel`, bottom hairline. Right side: connection chip (`ksu ok` / `no ksu` / `dm error`) and a refresh icon button (44 px) that re-runs the active tab's primary read.
- **Tab bar:** four tabs with icons (inline SVG) + labels. **Phone (<600 px): fixed bottom bar**, `--km-bar-h` + `env(safe-area-inset-bottom)`, equal-width, thumb reachable; active tab = accent label + top 2 px rail. **Tablet/desktop (>=600 px): under the header**, left-aligned, underline style. [D1: bottom bar on phone is the simplest one-handed layout and removes a second sticky layer.]
- **Content width:** fluid with `padding-inline: var(--km-pad-x)`, `max-width: var(--km-content-max)` (1120), centered; above 1120 the ink grid shows in the gutters. Main gets `padding-bottom: calc(var(--km-bar-h) + 16px)` on phone so the bar never covers the last row.
- **Daemons toolbar:** title "Daemons", count chip (`n running / n total`), primary button **Add** (opens the Add modal, section 6). Polling: `list` every 5 s while the Daemons tab is visible and `document.visibilityState==='visible'`; paused otherwise; every action also triggers one `list`. [D2]
- Tab state in `location.hash` (`#daemons|#appguard|#logs|#about`) so reloads keep the tab. Last tab restored from hash only (no localStorage required).

## 4. Daemons tab: health card
Source: one `list` call renders all cards; `status <id>` is called when the card's details drawer opens.

**Anatomy (top to bottom):**
1. **Status rail** (3 px left edge) + **state dot** and label: `RUNNING`, `STOPPED`, `FAILED`, `DONE`, `UNKNOWN`, `BUSY`.
2. **Title row:** `name` (lg bold), id in mono muted, `source` chip (`builtin|package|created|imported`), `kind` chip when `oneshot`.
3. **Desc:** `desc`, 2 lines clamp, full text in the drawer.
4. **Telemetry grid (mono, 2x2 on phone, 4x1 from 600 px):** `PID` (`pid`, or `pids` joined if more than one), `UPTIME` (`uptime_s` formatted `3d 4h`, `5m 02s`, `-` when null), `HEALTH` (`health` chip: `ok` green, `degraded` amber, `down` red, `na` shown as `n/a` idle; `health_detail` as tooltip-free inline text below when non-empty), `VERIFIED` (`verified_by` chip: `marker` accent "marker", `pidfile+argv` amber "pidfile+argv", `none` idle "unverified"; a `?` button toggles a one-line explanation).
5. **Enabled switch:** `<button role="switch" aria-checked>` labelled "Start at boot" (reads `enabled`). Wrapper-vs-xbit shown in the drawer (`boot`).
6. **Action row:** `Start` / `Stop` / `Restart` (44 px). Stop shown when `running`; Start when not. Oneshot: `Run` / `Run again`, no Stop/Restart. Secondary icon buttons: **Settings** (gear), **Details** (chevron, opens drawer), **Delete** (trash, labelled "Remove" for `removable:false`: "Unmanage"). Phone: primary action is full width, icon buttons share the row below.
7. **Failure strip** (only when the last action failed): `last.ok==false` shows `last.code` + message + timestamp (`last.ts`), role=alert, dismissible.
8. **Details drawer** (inline expand): `status` -> `meta` key/values (mono), `exit_code`, last 10 of `log_tail`, `boot`, `version`, `last` action.

**Settings button** [D3]: only `deep-sleep-cool` exposes Settings (kept compat commands `getconf`, `setconf`, `whitelist`, `packages`); `appguard` Settings switches to the AppGuard tab; other cards hide it. Deep Sleep Cool sheet: toggle "Freeze while unplugged" (`setconf freeze_unplugged 0|1`, revert on failure) and the "Never freeze" whitelist editor with a searchable add list, same behavior as `docs/specs/SPEC-webui-settings.md`.

**Card states:**
| State | Rail / dot | Content |
|---|---|---|
| loading (first `list`) | skeleton pulse (static under reduced motion) | 3 skeleton cards: 4 text bars + 2 button blocks, `aria-busy=true` on the list |
| running | `--km-ok`, solid dot | all telemetry, Stop + Restart enabled |
| stopped | `--km-idle`, hollow dot | PID/UPTIME `-`, Start enabled |
| failed | `--km-err`, square dot | failure strip with `last.code`; Start (labelled Retry) + Details open |
| done (oneshot) | `--km-ok` outline, check dot | "Ran OK" + exit code `0`, `Run again` |
| busy | `--km-accent`, ring dot + indeterminate rail | label `STARTING...`/`STOPPING...`/`RESTARTING...`; all card buttons `disabled`, `aria-busy=true`; other cards stay live |
| unknown | `--km-warn`, diamond dot | "State could not be verified" + `verified_by:none`; only Details and Refresh enabled; Start/Stop still allowed (dm re-verifies) |
| busy elsewhere | warn strip | `E_BUSY`: "Another action is running for this daemon. Retry in a few seconds." |

**Action rules.** Start/Stop/Restart set the card busy, call `start|stop|restart <id>` (blocking, 30 s timeout), then re-run `list`. Switch on -> `enable <id>`. Switch off on a **running** daemon opens a small confirm sheet: "Disable and stop now" (`disable <id>`) or "Disable, keep running" (`disable <id> --keep-running`) [D4]. `E_STOP_STILL_RUNNING` on disable: switch shows the new (disabled) state with a failure strip listing `pids` (dm leaves enabled changed). Stopping `root-sshd` asks a one-line confirm ("Ends the port 22 listener. Live sessions stay up.") [D5]. Optimistic UI is not used; the card shows busy until dm answers.

## 5. AppGuard tab
Reads `appguard get` once on entry and after each write (counts, config, targets, never, `daemon`, versions). Debounce: switches apply immediately; number fields apply on Enter/blur.

**Layout: phone single column; desktop (>=1000 px) two panes: left 340 px "Control", right fluid "Targets".**
1. **Status block:** `daemon.state` dot, `pid`, `uptime_s`, Start/Stop/Restart (same commands as the Daemons card), `counts` chips (`33 targets`, `30 u0`, `3 u999`, `6 never`). **Version hint:** if `running_version != installed_version`, an amber strip "Running v{running_version}, installed v{installed_version}. Restart AppGuard to apply." with a Restart button (`restart appguard`). Note under global settings: "Settings apply on the next sweep. No restart needed."
2. **Global:** `Interval` stepper/number (`config.interval_s`, 10-3600) -> `appguard set interval <v>`; `Default cooldown` (`config.cooldown_s`, 0-86400) -> `appguard set cooldown <v>`; `Dry run` switch (`config.dry_run`) -> `appguard set dry <0|1>`. Out-of-range input shows inline error before sending; `E_ARG` shown inline if dm still rejects it.
3. **Actions:** `Run once` (`appguard once`, confirm sheet "Kills matching apps now") and `Dry run once` (`appguard once --dry`, no confirm). Both blocking, 60 s timeout, busy state on both buttons. **Result card** from `sweep`: `candidates`, `killed`, `would_kill` list (`user`, `pkg`), `skipped_fg` list, `skipped_cooldown`, `ms`; if `sweep.skipped=="foreground-unknown"` show "Sweep skipped: foreground app unknown (fail-safe)".
4. **Targets list:** search box (client filter over `targets`), `Add app` button (opens picker: user tabs 0 / 999 -> `appguard packages --user N [--q substr]`, rows show `pkg`, chips `target` and `never`; tap -> `appguard targets add <pkg> u0=1 u999=0` for user 0 or `u0=0 u999=1` for 999). Each row (the **user matrix**):
   - `pkg` (mono, wraps with `overflow-wrap:anywhere`)
   - **User 0** switch (`u0`) and **User 999** switch (`u999`) -> `appguard targets set <pkg> u0=<0|1> u999=<0|1>`; both off is allowed (dormant row, chip "inactive")
   - **Cooldown** number, blank placeholder "default {cooldown_s}s" (`cooldown_s` null = default) -> `... set <pkg> cooldown=<N|default>`
   - **Blocked by Never** chip when `shadowed:true` (explains: "Never list overrides this target"), with a "Remove from Never" button (`appguard never rm <pkg>`)
   - Remove (`appguard targets rm <pkg>`) with an undo-free confirm sheet.
   Phone: each row is a stacked card (pkg on top, two switches side by side, cooldown full width). Tablet+: a 5-column grid row `pkg | U0 | U999 | cooldown | remove` with a sticky header line (CSS grid, not `<table>`, so it never overflows). Rendering is virtualized by paging: first 50 rows, "Show more" +50 [D6].
5. **Never list:** chips with remove (x) -> `appguard never rm <pkg>`; add field + picker -> `appguard never add <pkg>`; package regex checked client-side (`^[A-Za-z0-9_.]+$`, <=128) before send. One global list (no per-user).
6. **Recent kills:** `appguard kills 50` -> rows `ts` (relative + absolute), `user`, `pkg`, `mode` chip (`kill`/`dry`), `result` chip (`ok` green / `fail` red), `cooldown_s`, `reason`. Header shows `total`. Empty: "No kills recorded yet." Refresh button; auto-refresh after Run once.

## 6. Add: Install, Create, Import
Add button opens one modal with a segmented control: **Install**, **Create**, **Import** (radio group). Modals are full-height sheets on phone, centered 560 px dialogs from 600 px.

### 6.1 Install (4 steps + result; stepper shows `Source > Fetch > Review > Confirm`)
1. **Source:** two inputs in one field set: `https` URL or absolute path ending `.zip` (single field, auto-detected), optional "Pin sha256" (64 hex). Client checks: URL must start with `https`, path must start with `/`, else inline `E_ARG`-style hint. Button **Stage package** -> `install stage <src> [sha256]` -> `{job}`.
2. **Fetch:** poll `job <job>` every 1 s. Progress bar from `pct`, step labels `download -> verify -> extract -> validate` from `step`, current one highlighted; for a local path the download step is shown as "skipped". Cancel button (calls nothing mid-job; the job finishes and the staged token is aborted on the next screen) [D7]. Failure (`state:"failed"`): inline error panel with `code` + `msg` and **Back** (keeps the entered source).
3. **Review (`result` = P):** manifest summary (`id`, `name`, `version`, `kind`, `desc`, `start`, `stop`), `files`, `bytes` (human), `sha256` (mono, wrap), `warnings[]` (amber list). `conflict`: `exists` or `builtin` -> red banner "Id already in use. Remove it first" and Confirm stays disabled. **Hooks:** one panel per non-null of `hooks.install`, `hooks.uninstall`: header "Runs as root" with a red-bordered shield icon, `sha256`, `bytes`, a scrollable monospace preview of `preview` (40 lines, wraps, max-height 40 vh, `tabindex=0` so it is keyboard scrollable) and the line "This script runs with full root access. Read it before continuing." If the hook is null: "No install hook."
4. **Confirm:** "Type `{manifest.id}` to install." text field; **Install** enabled only on an exact match -> `install commit <token> --confirm <id>`. Blocking up to 45 s: spinner + "Running install hook as root (up to 30 s)" when `hooks.install` exists; Escape and backdrop are disabled while it runs. **Cancel / Escape / close at any step after staging** -> `install abort <token>` (best-effort, fire and forget).
5. **Result:** success: "Installed `{id}` v{version}. It is disabled." + `hook.ran`/`hook.exit` line + buttons **Enable** (`enable <id>`) and **Done**; the list is refreshed.

**Install failure codes** (inline panel, role=alert, always show `code` in mono):
| Code | Message shown | Next step |
|---|---|---|
| `E_ARG` | "Source or hash is malformed." | fix the field |
| `E_NO_TOOL` | "A required tool is missing (curl/unzip/sha256sum/base64)." | open About > Doctor |
| `E_DOWNLOAD` | "Download failed or the server downgraded to http." | check URL/network |
| `E_VERIFY` | "Size, entry, checksum or hook-hash check failed." | re-download, check pinned sha256 |
| `E_PATH` | "The package contains an unsafe path." | do not install; contact the author |
| `E_CONFLICT` | "A daemon with this id already exists." | remove it first |
| `E_HOOK` | "The install hook exited with {hook.exit}." | read daemon log; nothing is enabled |
| `E_BUSY` | "Another operation holds the lock." | retry |
| `E_CONFIRM` | "Confirmation did not match." | retype the id |
Unknown codes fall back to `code` + `msg` verbatim.

### 6.2 Create
Fields: **Name** (required, <=64), **Kind** (radio `daemon` / `oneshot`), **Start command** (single-line mono input, <=1024, no newline), **Stop command** (optional, same limits, hint "Leave empty to stop by TERM then KILL"). Submit builds `b64(name=..\nkind=..\nstart=..\nstop=..\n)` -> `create <b64>`. dm assigns the id; success shows "Created `{id}` (disabled)" and offers **Start now** (`start <id>`) and **Done**. Errors: `E_ARG` (inline on the offending field when dm names it, else top banner), `E_CONFLICT` (name slugs to an existing id).

### 6.3 Import
`import list` -> rows (`name`, `path` mono, `bytes`, `executable` chip "enabled/disabled", `managed` -> row disabled with "Already managed"). Select a row -> short form: Name (prefilled from `name`), Kind, Stop command (optional) -> `import <path> <b64(name=..\nkind=..\nstop=..\n)>`. Success: "Imported `{id}`" + `enabled` state + note "The script was not moved or edited." Empty: "No unmanaged scripts in service.d." Errors: `E_PATH`, `E_CONFLICT`, `E_ARG`.

## 7. Delete flow
Trigger: trash icon on a card -> modal. `delete <id> --plan` -> plan view:
- list: **Stops the daemon** (`plan.stop`), **Removes** `plan.remove_dir`, **Removes** `plan.remove_wrapper`, **Runs uninstall hook as root** (`plan.run_uninstall_hook`, red "Runs as root" tag), and a muted **Leaves alone** list (`plan.keeps`). Null items are omitted.
- builtin/imported (`removable:false`): title "Unmanage {name}", note "Only the manager record and its km wrapper are removed. The script stays and keeps its boot state."
- type-to-confirm: "Type `{id}` to continue" -> **Delete** (danger button, enabled on exact match) -> `delete <id> --confirm <id>`. Blocking up to 45 s (uninstall hook), controls disabled, Escape disabled while running.
- **Result:** success lists `removed[]` (mono), `stopped`, `hook.ran`/`hook.exit`, `unmanaged`; closes to the refreshed list. Failures: `E_CONFIRM` (retype), `E_NOT_REMOVABLE`, `E_BUSY`, `E_STOP_STILL_RUNNING` (lists `pids`, "Daemon still running; nothing was deleted"), `E_HOOK`, `E_UNKNOWN`.

## 8. Logs tab
Source select (`dm`, `appguard`, then every daemon id from the last `list`) and a lines select (50 / 100 / 200). Refresh button; auto-refresh toggle (off by default, 5 s). `logs <src> <n>` -> `lines[]` in a monospace panel (`white-space:pre-wrap; overflow-wrap:anywhere`, never horizontal scroll), newest at the bottom with scroll pinned unless the user scrolled up; `truncated:true` adds "Showing last {n} lines". Empty: "Log is empty." Panel is `role=log`, `tabindex=0`. Lines are inserted with `textContent`, never `innerHTML`.

## 9. About tab
- **Identity:** mark, "KonaManager - Simple Daemon Manager", module id `daemon-manager`, `version` -> `{version, schema}` shown as `dm 2.0.0 / schema 2`, `module.prop` version not read by the UI.
- **Doctor:** button **Run doctor** (also auto-run once on entry) -> `doctor`: rows `root` (ok/fail), each of `tools.curl|unzip|sha256sum|base64|pm` (path or "missing" red), `selinux`, `writable`. Failure highlights the line and links the matching fix text ("`E_NO_TOOL`: install busybox or Termux curl").
- **Links:** project `github.com/Konaimav2/KonaManager` and `Report an issue` shown as selectable mono text, no anchors and no `://` [D8: a WebView may open links outside the sandbox; plain text avoids any navigation and keeps the no-`http` grep clean].
- **Maintenance:** `Rollback` button (danger, typed confirm "rollback") -> `rollback` -> "Restored {restored}. Reboot or restart daemons to apply." Hidden unless a rollback directory exists (`rollback` returns an error otherwise, shown inline).

## 10. States: empty, loading, error, offline
| Situation | Behavior |
|---|---|
| No `window.ksu` | Shell and tabs render; header chip `no ksu`; panels show a centered notice "Open KonaManager from KernelSU's module WebUI. No bridge is available here." Mutating controls absent; static copy of About remains. No retries. |
| `dm` error (errno != 0, empty stdout, or non-JSON) | Panel error: "dm did not return valid JSON." + exit code + first 200 chars of stderr (text only) + **Retry**; other tabs unaffected. Chip `dm error`. |
| `ok:false` | Inline error (card strip, form banner or sheet) with `code`, mapped text, `msg`. |
| `E_NOT_ROOT` | Full panel "dm is not running as root. Open this page from the KernelSU module list." |
| Empty daemon list | "No daemons yet." + **Add** primary button. |
| Empty targets / never / kills / logs | One-line muted text per section as written above, each with its action. |
| Loading | Skeletons for lists; inline spinner (CSS ring) in buttons; every loading region has `aria-busy`. |
| Timeout | After the bridge timeout: "Command timed out after {n} s. The action may still be running; refresh to check." Card state is re-read, not assumed. |
| Poll failure while visible | Keep last data, mark chip `stale` (amber), retry next tick. |
Error code map (reused everywhere): `E_USAGE/E_UNKNOWN` "Unexpected request", `E_BUSY` "Busy, retry", `E_ARG` "Invalid value", `E_NOT_ROOT` "Not running as root", `E_NO_SCRIPT` "Script missing or not executable", `E_START_TIMEOUT` "Did not come up in time", `E_START_EXITED` "Exited right after start", `E_STOP_STILL_RUNNING` "Still running after KILL", plus the install table above, `E_NOT_REMOVABLE` "Cannot delete files outside its folder". Unknown code: `code` + `msg`.

## 11. Responsive rules (exactly ten viewports)
Layout mode is `--km-layout` (phone <600, tablet 600-999, desktop >=1000), read by QA with `getComputedStyle(document.documentElement).getPropertyValue('--km-layout')`. **Hard rule at all ten:** `document.documentElement.scrollWidth - window.innerWidth === 0`; zero elements cross the viewport edge; no `<table>`, no fixed pixel widths above the viewport (`min-width:0` on grid/flex children, `overflow-wrap:anywhere` on pkg/id/path/hash/log text, `max-width:100%` on inputs). There are no intentional horizontal scroll strips.
| Viewport | Mode | Changes |
|---|---|---|
| 360x640 | phone | 1 col, pad 12, bottom tab bar (icons + 11 px labels), card telemetry 2x2, primary action full width, icon buttons below, subtitle hidden, modals full-screen, AppGuard rows stacked. Short height: sticky header 52, bar 60, so ~528 px of content; modals scroll internally (`max-height:100dvh`), footer actions sticky |
| 390x844 | phone | same as 360, pad 16, labels 12 px |
| 414x896 | phone | same as 390, action buttons show text + icon on one row (Start/Stop + Restart share a line) |
| 768x1024 | tablet | top tabs, 2 card columns, pad 24, centered modals 560 px, AppGuard single column, matrix as 5-column grid rows, subtitle shown |
| 820x1180 | tablet | same as 768, pad 24, columns 2, larger vertical rhythm only (`--km-s5` gaps) |
| 1024x1366 | desktop | AppGuard two panes (340 px + fluid), 3 card columns (`repeat(auto-fill,minmax(300px,1fr))`), pad 32; modals 560-640 px |
| 1280x800 | desktop | content max 1120 centered, 3 columns, header 60; short height, logs/kills panels capped at `max-height:calc(100dvh - 220px)` |
| 1440x900 | desktop | same as 1280, wider gutters showing the ink grid |
| 1920x1080 | desktop | content stays 1120 (no stretch), 3 columns, centered, 400+ px gutters each side |
| 1080x1080 | desktop | square; width >=1000 so desktop mode, 3 columns of ~320 px, no height-dependent layout (nothing sized in `vh` except `max-height` caps) |
Modals use `max-height:min(90dvh,720px)` on tablet+, `100dvh` on phone; internal scroll only vertical. Safe-area insets (`env(safe-area-inset-*)`) on header, bar and sheets.

## 12. Accessibility
- **Focus order:** skip link ("Skip to content") > header refresh > tablist (one tab stop, arrows move, Home/End jump, Enter/Space activate; roving `tabindex`) > active panel top-to-bottom (toolbar, then cards, within a card: switch, primary action, Restart, Settings, Details, Delete). Opening a dialog moves focus to its heading; focus is trapped; closing returns focus to the opener.
- **ARIA:** `role=tablist/tab/tabpanel` with `aria-selected`, `aria-controls`, `aria-labelledby`; dialogs `role=dialog aria-modal=true aria-labelledby aria-describedby`; typed-confirm dialogs use `role=alertdialog`; switches `role=switch aria-checked` (`aria-busy` while pending, never silently flip); progress `role=progressbar aria-valuenow`; toasts in `aria-live=polite`, errors `role=alert`; logs `role=log`; state dot has a text twin (`aria-hidden` on the dot only).
- **Keyboard:** Escape closes the topmost dialog or sheet and aborts a staged install (`install abort`), except while a blocking commit or delete is running. Enter submits forms; Space/Enter toggles switches.
- **Visual:** `:focus-visible` uses `--km-focus` (2 px ring, 3:1 against every surface); contrast at least 4.5:1 for text; targets at least 44 px; state never by color alone.
- **Motion:** `prefers-reduced-motion: reduce` zeros all `--km-dur-*`, stops skeleton pulse, the mark pulse and the busy sweep (busy is then shown by label + static ring).

## 13. CSP, bridge, polling, error surface
- **CSP (identical in `index.html` meta and `config.json`):** `default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data:; font-src 'self'; connect-src 'none'; base-uri 'none'; form-action 'none'`. No inline `<script>`, no `on*=` handlers, no `style=` attributes (classes, and CSSOM `el.style.x=` only), no `eval`, no external URLs, fonts, images, or fetch/XHR. Scripts are plain files in `js/`, loaded with `<script src defer>`. SVG icons are inline in the HTML or created with DOM APIs. Fallback if the KSU WebView blocks `'self'` styles: `style-src 'unsafe-inline'`, recorded as a deviation after T9.
- **Bridge (`js/bridge.js`):** `ksu.exec(cmd, callbackName)`: a unique global callback per call (`__km_<seq>_<ts>`) receives `(errno, stdout, stderr)` and is deleted after use; a late callback after timeout hits a no-op. A promise wraps it and resolves `JSON.parse(stdout)` or rejects with `{kind:'nojson'|'timeout'|'nobridge', errno, stderr}`. Each call is blocking and returns stdout only at exit, so output stays under ~64 KB. Concurrency is capped at 3 with a FIFO queue; an identical in-flight command string is shared (de-duplicated); mutating commands are never de-duplicated and the card is locked by the UI (`busy`). Timeouts: reads 10 s, start/stop/restart/enable/disable 30 s, `once` 60 s, `install commit` and `delete --confirm` 45 s.
- **Command builder:** `DM + ' ' + tokens`. Only tokens that match a fixed validator are interpolated: ids `^[a-z0-9][a-z0-9-]{1,30}$`, pkg `^[A-Za-z0-9_.]+$` (<=128), ints in range, `u0|u999=0|1`, `cooldown=<int>|default`, tokens `^t_[a-z0-9]+$`, jobs `^j_[a-z0-9]+$`, sha256 `^[a-f0-9]{64}$`. URLs and paths are validated (`^https` or `^/[A-Za-z0-9._/-]+\.zip$`) and single-quoted with `'` -> `'\''`; free text (name, start, stop) travels only as base64 (`btoa` of UTF-8 bytes). A failed validator throws before the bridge is called.
- **Blocking call vs job:** everything is a blocking call except `install stage`, which returns a job; the UI polls `job <id>` every 1 s until `state != running`, max 10 min, and stops polling on tab close. Polling backs off to 3 s after 30 s.
- **Error surface:** one `errorView(err)` maps `{kind|code}` to text and places it where the user acted (card strip, form banner, modal panel, tab panel). Toasts only confirm success (3 s, `aria-live`). Raw stderr is shown as text (`textContent`), capped at 200 characters. Nothing is swallowed: unparsable output is shown as `dm error`.

## 14. UI element -> `dm` command -> JSON fields
| UI element / action | Command | Fields used |
|---|---|---|
| Daemons list, cards, chips | `list` | `dm`, `schema`, `ts`, `daemons[].{id,name,desc,kind,version,source,enabled,state,running,pid,pids,uptime_s,health,health_detail,verified_by,removable,boot,last}` |
| Card Details drawer | `status <id>` | `daemon`, `meta`, `exit_code`, `log_tail` |
| Start / Run / Retry | `start <id>` | `ok,state,pid,pids,uptime_s,waited_ms,already,msg,exit_code`; fail `code,msg,waited_ms,state,exit_code` |
| Stop | `stop <id>` | `state,steps,killed_pids,waited_ms`; fail `E_STOP_STILL_RUNNING`, `pids` |
| Restart | `restart <id>` | `stop{...}`, `start{...}` |
| Enabled switch on | `enable <id>` | `enabled,boot,msg` |
| Enabled switch off | `disable <id>` / `disable <id> --keep-running` | `enabled,boot,stopped,msg` |
| Deep Sleep settings | `getconf`, `setconf freeze_unplugged 0\|1`, `whitelist list\|add <pkg>\|rm <pkg>`, `packages` | `freeze_unplugged`, `whitelist`, `ok,msg` (compat kept in PLAN section 4) |
| Add > Install: Stage | `install stage <src> [sha256]` | `job` |
| Install progress | `job <id>` | `state,step,pct,result,code,msg` |
| Install review | (from `result`) | `token`, `manifest.{id,name,version,kind,desc,start,stop}`, `hooks.{install,uninstall}.{sha256,bytes,preview}`, `files`, `bytes`, `sha256`, `conflict`, `warnings` |
| Install confirm | `install commit <token> --confirm <id>` | `id,version,dir,hook.{ran,exit},enabled` |
| Install cancel | `install abort <token>` | `ok` |
| Add > Create | `create <b64kv>` | `id,dir,enabled` |
| Add > Import list | `import list` | `candidates[].{path,name,executable,managed,bytes}` |
| Import confirm | `import <path> <b64kv>` | `id,script,enabled,source` |
| Delete plan | `delete <id> --plan` | `plan.{stop,remove_dir,remove_wrapper,run_uninstall_hook,keeps}` |
| Delete confirm | `delete <id> --confirm <id>` | `id,stopped,hook.{ran,exit},removed,unmanaged` |
| AppGuard screen load | `appguard get` | `config.{interval_s,cooldown_s,dry_run}`, `never`, `targets[].{pkg,u0,u999,cooldown_s,shadowed}`, `counts`, `daemon`, `running_version`, `installed_version` |
| Interval / cooldown / dry-run | `appguard set interval\|cooldown\|dry <v>` | `key,value,msg` |
| U0 / U999 switches, per-app cooldown | `appguard targets set <pkg> u0=.. u999=.. cooldown=..\|default` | `pkg,u0,u999,cooldown_s` |
| Add app | `appguard targets add <pkg> [u0=1 u999=0 cooldown=N]` | `pkg,u0,u999,cooldown_s` |
| Remove target | `appguard targets rm <pkg>` | `pkg,u0,u999,cooldown_s` |
| Never add / remove | `appguard never add\|rm <pkg>` | `never` |
| Package picker | `appguard packages --user 0\|999 [--q <s>]` | `user,packages[].{pkg,target,never}` |
| Run once / Dry run once | `appguard once` / `appguard once --dry` | `dry,sweep.{skipped,candidates,killed,would_kill,skipped_fg,skipped_cooldown},ms` |
| Recent kills | `appguard kills <n<=200>` | `total,kills[].{ts,user,pkg,mode,result,cooldown_s,reason}` |
| AppGuard restart hint | `restart appguard` | `stop,start` |
| Logs tab | `logs <id\|dm\|appguard> <n<=200>` | `source,lines,truncated` |
| About version | `version` | `version,schema` |
| About doctor | `doctor` | `root,tools.{curl,unzip,sha256sum,base64,pm},selinux,writable` |
| About rollback | `rollback` | `restored` |
| Every failure | any | `ok:false,code,msg` (and per-command extras above) |
Not in the UI in v1: `migrate` (lazy, runs on first `dm` call or boot) and the old unversioned `list` output; the UI never calls anything outside PLAN section 4.

## 15. Decisions summary
D1 bottom tab bar on phone. D2 5 s visible-only polling. D3 Settings only for `deep-sleep-cool` (and a jump link for `appguard`). D4 disable on a running daemon asks stop-or-keep. D5 confirm before stopping `root-sshd`. D6 targets paged 50 at a time. D7 install Cancel during a job aborts the staged token afterward. D8 links are plain text, no anchors. D9 no optimistic UI, cards show busy until dm answers.
