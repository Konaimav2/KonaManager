# Changelog

## v2.0.0 - 2026-11-12

- Renamed the module presentation to **KonaManager - Simple Daemon Manager** (module id stays `daemon-manager`).
- Verified daemon lifecycle: marker + pidfile + exact argv checks, start confirmation, stop escalation, health/uptime, and decoy rejection.
- Configurable AppGuard: per-app user 0 / 999 switches, per-app cooldown, global interval/cooldown/dry-run, Never list, package picker, kill history, heartbeat.
- Install daemon packages from an HTTPS zip, create a daemon from a form, or import an existing `service.d` script.
- Delete with a plan preview, typed confirmation, and uninstall hooks.
- New WebUI: Daemons / AppGuard / Logs / About, responsive phone bar, tablet and desktop grids, install stepper, hooks preview, doctor and rollback.
- In-place update: data, AppGuard lists, `deep-sleep-cool.conf`, and `service.d` scripts are preserved. The v1 AppGuard script is kept as `rollback/appguard.sh.pre-km`.
- Backend test suite: 638 checks. UI QA: 31 checks across ten viewports.
