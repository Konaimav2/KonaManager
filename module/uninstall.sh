#!/system/bin/sh
# KonaManager - module removal hook. Keeps all data on purpose:
#   /data/adb/daemon-manager (configs, lists, daemon dirs), /data/adb/appguard,
#   deep-sleep-cool.conf and the service.d scripts. Running daemons are not stopped.
# km-<id>.sh wrappers become harmless no-ops (they exit when dm is gone).
BASE=${DM_ROOT:-${KM_ADB:-/data/adb}/daemon-manager}
echo "$(date '+%F %T') uninstall.sh: module removed, data kept in $BASE" >>"$BASE/dm.log" 2>/dev/null
exit 0
