# KonaManager - Simple Daemon Manager: PRD

Module id `daemon-manager` (unchanged); display name `KonaManager - Simple Daemon Manager`. Repo `Konaimav2/KonaManager`. Contract source: `PLAN.md` section 4 (`dm` JSON). UI source: `docs/DESIGN.md`.

## 1. Problem
The current manager is a plain card list over a 176-line `dm`. Three things are wrong:
- **State is guessed.** A daemon counts as "running" if `pgrep -f` matches its command line. A decoy process, or a launcher that exits at once (`wifi-ps-guard`), gives a wrong answer. Stop uses `pkill -f`, which can hit the wrong process.
- **AppGuard is hard-coded.** The package lists live in script heredocs. Changing a target, a user, or a cooldown means editing a root script by hand. One real bug hides there: three user-999 targets are shadowed by the NEVER list, so only one is ever killed.
- **No way to add or remove daemons.** Everything is a fixed list in `daemons.conf`. Installing a new daemon means a root shell and hand-made files.

## 2. Users
- **Primary: the device owner / power user.** Rooted Android (KernelSU), comfortable with root daemons, uses the module WebUI on a phone, mostly one-handed, occasionally on a tablet or in a desktop browser against the mock.
- **Secondary: daemon authors** who publish a small zip package for others to install.

## 3. Jobs to be done
1. "Tell me which daemons are really running, and prove it."
2. "Start, stop, restart, or toggle boot-enable for a daemon and see the real result, or the real reason it failed."
3. "Tune AppGuard (interval, cooldown, dry-run, which apps, which Android user, per-app cooldown, never-kill list) without touching a script, and preview what it would kill."
4. "Add a daemon: install a package from a URL or file, write one myself, or adopt a script already in `service.d`."
5. "Remove a daemon and know exactly what is deleted and what is left alone."
6. "Read logs and diagnose the device (root, tools, SELinux) from the UI."
7. "Update the module in place without losing my lists, configs, or running daemons."

## 4. Product requirements
**R1 Verified lifecycle.** State comes from `dm`, never from the UI. Each daemon shows `state`, `pid`, `uptime_s`, `health`, and `verified_by` (`marker`, `pidfile+argv`, `none`). Start/stop return only after verification (`waited_ms`, `already`). Stop escalates stop command, TERM, KILL, and reports `E_STOP_STILL_RUNNING` with the surviving pids. Oneshot daemons show `done` and the exit code. Enabled = the boot entry's executable bit (single source of truth).
**R2 Configurable AppGuard.** Global interval (10-3600 s), cooldown (0-86400 s), dry-run. Per app: kill in user 0, kill in user 999, own cooldown or the default. One global NEVER list. "Run once" and "Dry run once" with a result summary. Kill history. Config applies on the next sweep with no restart. The UI flags a target shadowed by NEVER and a running version that differs from the installed one.
**R3 Install / create / import / delete.** Install from an HTTPS URL or an absolute local `.zip` path, with optional pinned sha256. A staged job shows progress, then a preview (manifest, files, sizes, hashes, conflicts, warnings, full hook preview marked "runs as root"). Nothing runs before the user types the daemon id to confirm. Create from a name, kind, start and stop command. Import adopts a script already in `service.d` without moving or editing it. Delete shows a plan first, needs the typed id, and reports exactly what was removed. Builtins can only be unmanaged, never have their scripts deleted.
**R4 Logs.** View `dm`, `appguard`, and per-daemon logs (last 200 lines), with a refresh and a truncated notice.
**R5 Branding.** Name, compact inline mark, dark control-room look. No external assets or fonts.
**R6 Safe by construction.** Strict CSP, no inline script/style/handlers, no network requests from the page. Free text reaches the shell only as base64 or validated tokens. Every failure shows its `E_*` code and a plain-language next step.
**R7 Live update preserves data.** A zip flashed over the live module changes only module files. `/data/adb/daemon-manager`, `/data/adb/appguard`, `deep-sleep-cool.conf`, daemon dirs, AppGuard lists, and running daemons survive; migration is additive and idempotent; `dm rollback` restores the previous module. The user sees "restart to apply" when versions differ, never a surprise restart.
**R8 Works everywhere it should.** Usable without horizontal scroll at ten fixed viewports (360x640 to 1920x1080 plus 1080x1080), keyboard and screen-reader operable, readable without `window.ksu` (offline state).

## 5. Non-goals
No new daemons shipped. No Termux or sshd changes. No per-user NEVER lists. No remote package index or store. No commit, push, or deploy without an explicit verb. No light theme in v1. No i18n. No backend commands beyond PLAN.md section 4. No auth (the KSU WebUI is already root-gated).

## 6. Success criteria
- `dm list` over 6 daemons returns under 500 ms; every output parses as one JSON object (`jq -e .`).
- A decoy process with an identical command line is never reported `running`; stop on a stubborn fixture ends in KILL or `E_STOP_STILL_RUNNING`.
- Migration yields AppGuard U0=30, U999=3, NEVER=6; `once --dry` matches the old script's would-kill set.
- All evil zips (`../x`, `/abs`, `a\..\b`, symlink, 6 MiB, 201 entries, bad id, hook hash mismatch, http URL, redirect to http) are rejected with the right code and nothing is written outside staging.
- Update-in-place rehearsal: all current daemons keep their PIDs, configs and lists are byte-identical, `rollback` works.
- UI QA: 10/10 viewports pass (scrollWidth - innerWidth = 0, zero off-edge elements, intended layout mode active, one screenshot each), 0 console errors, 0 CSP violations; `grep -rEn ' on[a-z]+=|style=|https?://' module/webroot` prints nothing.
- Judge passes the dossier (T6, T8, T9 evidence) before any ship.

## 7. Open risks (tracked in PLAN.md section 8)
User-999 kill may be refused on some ROMs. A strict CSP may be blocked by the KSU WebView (verify in T9; the fallback is a recorded deviation). Environ-based process marking fails for daemons that sanitize their environment (pidfile + argv fallback).
