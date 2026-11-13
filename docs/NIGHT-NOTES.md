# NIGHT-NOTES - AppGuard sheet + WebUI performance

Base `8c289b7`. Plan: `docs/NIGHT-PLAN.md`. Spec changes: `docs/DESIGN.md` sections 3, 5, 13, 15 (D10-D13) and `docs/PRD.md` R2, R9.

## No backend change

Every control in the AppGuard settings sheet maps to a command that already exists (source `module/bin/lib/km-appguard.sh`, router `cmd_appguard` :370-381; lifecycle via `module/bin/dm:64-66`). Nothing under `module/bin/**` is edited, so the Backend stage is skipped.

| Control | Command | Source | Backend test |
|---|---|---|---|
| Status state/PID/uptime, versions | `appguard get` (`daemon`, `running_version`, `installed_version`, `config`, `counts`) | :97 | `tests/run.sh:650-651` |
| Start/Stop/Restart | `dm start\|stop\|restart appguard` | `dm:64-66` | lifecycle suite `run.sh:176+` |
| Interval / cooldown / dry-run | `appguard set interval\|cooldown\|dry <v>` (10-3600, 0-86400, 0/1) | :100-113 | `run.sh:767, 791-812` |
| Run once / Dry run once | `appguard once [--dry]` | :317-367 | `run.sh:717, 738, 744, 762-774` |
| Matrix toggle, per-app cooldown, add, remove | `appguard targets add\|set\|rm <pkg> u0= u999= cooldown=N\|default` | :128-133, :174-212 | `run.sh:754-780` |
| Never add/remove | `appguard never add\|rm <pkg>` | :214-243 | `run.sh:814-823` |
| Package picker | `appguard packages [--user 0\|999] [--q s]` | :248-282 | `run.sh:830-841` |
| Recent kills | `appguard kills <n>` | :284-313 | `run.sh:734, 747, 848` |

## Backend baseline

`sh tests/run.sh` on this clean clone gives **596 pass / 42 fail**. The 42 failures come from the gitignored `reference/live/*` captures, which a fresh clone doesn't have. They aren't regressions. Tonight's gate: **>= 596 pass and a failure set identical to the baseline list** (`tmp/baseline-failed.txt`). The 638/0 figure in `tests/evidence/backend.txt` needs those captures, so the 638 re-check on the main tree is morning work.

## Open items (cannot be done tonight)

- Real WebView QA on the phone (KernelSU module WebUI). Tonight's QA is Playwright against the mock only.
- Judge sign-off by the user.
- Commit and push (no remote here, no commit verb given).
- Live module update on the device.
- 638 backend re-check with the reference captures (see above).

Doc drift spotted, not fixed (out of scope): DESIGN.md section 13 lists bridge timeouts of reads 10 s and `once` 60 s, but `core.js:7` uses `KM.T = { read: 12000, mut: 35000, once: 70000, install: 60000 }`.
