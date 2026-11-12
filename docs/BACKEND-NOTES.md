# KonaManager backend notes

Stage: backend implementation (Claude Code on the VPS, then fixed/tested locally).

## Implemented
- `module/bin/dm` plus `km-core`, `km-json`, `km-proc`, `km-migrate`, `km-appguard`, `km-install`.
- Daemon commands: list, status, start, stop, restart, enable, disable, boot, logs, doctor,
  version, migrate, rollback, plus the legacy `getconf`/`setconf`/`whitelist`/`packages`.
- Lifecycle verification: pidfile, `KM_DAEMON_ID` marker, and exact argv check. For
  package/created daemons `argv_match` defaults to the resolved start-script path, which
  prevents an install hook or another module with the same marker from being adopted.
- Start waits for a verified process and catches immediate exits. Stop runs stop_cmd, then
  TERM, then KILL after the grace period, and returns `E_STOP_STILL_RUNNING` if needed.
- AppGuard: configurable `INTERVAL`, `COOLDOWN`, `DRY`, per-app user-0/user-999 flags,
  per-app cooldown, never list, kills history, heartbeat, and `once` for a dry sweep.
- Migration: lazy/idempotent, parses the legacy `daemons.conf`, the live service.d x-bits,
  and the live AppGuard U0/U999/NEVER heredocs. Builtins keep their existing boot method.
- Install: URL or local zip staging, size/entry/path/symlink checks, manifest validation,
  hook hashes and previews, commit/abort, optional install/uninstall hooks, typed confirm.
- Create from form, import existing service.d scripts, delete with plan/confirm. Delete only
  removes the managed daemon dir and its `km-<id>.sh` wrapper; builtins are unmanage-only.
- Tests: `tests/run.sh` with fixture roots, decoys, TERM-ignoring processes, evil zips,
  AppGuard migration/cooldown, create/import/delete, and HTTPS download cases.

## Deliberate differences from PLAN.md
- Install stage is synchronous. It still returns a job-shaped object so the UI can poll or
  display progress, but there is no background worker process.
- `rollback` is best-effort (restores the latest backup/rollback snapshot if present).
- The UI stage must follow the actual JSON emitted by `dm`; run `dm <cmd>` on a fixture or
  read the tests for exact shapes. `module/webroot` was not touched in this stage.

## Test result
`sh tests/run.sh` on the VPS: 638 passed, 0 failed, 0 JSON contract violations.
On-device Android/mksh verification is the next gate.
