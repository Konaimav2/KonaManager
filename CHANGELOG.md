# Changelog

## v2.1.0 - 2026-11-13

- Removed the AppGuard tab. Its configuration is now a lazy sheet opened from the AppGuard card gear, like Deep Sleep Cool.
- WebUI performance rewrite: unchanged polls do zero card DOM replacement, cards patch in place by id, tab switches no longer force a reload, polling pauses when hidden or modal-open, logs never yank a scrolled-up view, and render errors are contained with Retry.
- Closed the Judge Mediums: optimistic target state with row-by-package resolution, a coalesced follow-up load after an in-flight poll, and number fields that commit only on Enter/Save, not on sheet close. Also fixed focus, picker conflict, first-load skeleton, and stale picker replies.
- Fixed the Deep Sleep Cool sheet crash (`pkgs.forEach`) that existed in v2.0.0.
- Real ReSukiSU WebView smoke test: three tabs, rapid tab/scroll stress, live AppGuard sheet, Deep Sleep sheet.
- Backend 638/638; browser QA 154/154.

## v2.0.0 - 2026-11-12

- Renamed the module presentation to **KonaManager - Simple Daemon Manager** (module id stays `daemon-manager`).
- Verified daemon lifecycle: marker + pidfile + exact argv checks, start confirmation, stop escalation, health/uptime, and decoy rejection.
- Configurable AppGuard: per-app user 0 / 999 switches, per-app cooldown, global interval/cooldown/dry-run, Never list, package picker, kill history, heartbeat.
- Install daemon packages from an HTTPS zip, create a daemon from a form, or import an existing `service.d` script.
- Delete with a plan preview, typed confirmation, and uninstall hooks.
- New WebUI: Daemons / AppGuard / Logs / About, responsive phone bar, tablet and desktop grids, install stepper, hooks preview, doctor and rollback.
- In-place update: data, AppGuard lists, `deep-sleep-cool.conf`, and `service.d` scripts are preserved. The v1 AppGuard script is kept as `rollback/appguard.sh.pre-km`.
- Backend test suite: 638 checks. UI QA: 31 checks across ten viewports.
