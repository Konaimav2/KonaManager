#!/bin/sh
# like sshd: the launcher exits, a child keeps running and writes a pidfile.
# The child is started without the dm marker so only pidfile+argv can verify it.
FX=$(cd "$(dirname "$0")" && pwd)
env -u KM_DAEMON_ID sh "$FX/loop.sh" >/dev/null 2>&1 &
echo $! >"${KM_FX_PIDFILE:-$FX/daemonized.pid}"
exit 0
