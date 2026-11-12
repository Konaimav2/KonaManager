#!/system/bin/sh
# KonaManager - late_start service hook (runs as root once the system is up).
# It starts no daemon. Boot entries stay where they are: the x-bit scripts in
# /data/adb/service.d (builtins/imported) and km-<id>.sh wrappers (package/created).
# This only makes sure dm is runnable and the data tree is migrated (lazy, idempotent).
MODDIR=${0%/*}
KM_ADB=${KM_ADB:-/data/adb}
BASE=${DM_ROOT:-$KM_ADB/daemon-manager}
mkdir -p "$BASE" 2>/dev/null
chmod 755 "$MODDIR/bin/dm" 2>/dev/null
echo "$(date '+%F %T') service.sh: root active, dm ready" >>"$BASE/dm.log"
# background so boot is never held up; migration never restarts or edits anything running
( "$MODDIR/bin/dm" migrate >/dev/null 2>&1 ) &
exit 0
