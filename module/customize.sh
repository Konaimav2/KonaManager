#!/system/bin/sh
# KonaManager - KernelSU/Magisk install script (sourced by the installer, so no exit).
# Update in place: the data tree (/data/adb/daemon-manager), AppGuard dir and every
# running daemon are left alone. Only module files change. Nothing is restarted.
SKIPUNZIP=0
ADB=${KM_ADB:-/data/adb}
R=${DM_ROOT:-$ADB/daemon-manager}
OLD=${KM_OLD_MODULE:-$ADB/modules/daemon-manager}
AGDIR=${KM_AG_DIR:-$ADB/appguard}
say() { if command -v ui_print >/dev/null 2>&1; then ui_print "$1"; else echo "$1"; fi; }

say "- KonaManager: preparing update"
mkdir -p "$R/backups" "$R/rollback" 2>/dev/null
TS=$(date '+%Y%m%d-%H%M%S')

# 1. backup the data tree (config + lists only; not staging/backups/rollback/locks), keep 3
if [ -d "$R" ] && command -v tar >/dev/null 2>&1; then
  ( cd "$R" && tar -cf "$R/backups/$TS.tar" --exclude=./backups --exclude=./rollback --exclude=./staging --exclude=./lock --exclude=./jobs . ) >/dev/null 2>&1 \
    && say "- data backup: $R/backups/$TS.tar"
  n=0
  for f in $(ls -1t "$R"/backups/*.tar 2>/dev/null); do
    n=$((n + 1))
    [ "$n" -gt 3 ] && rm -f "$f"
  done
fi

# 2. keep the previous module files for `dm rollback` (only when the old module is a different version)
if [ -f "$OLD/module.prop" ]; then
  OLDVER=$(grep '^version=' "$OLD/module.prop" | head -n 1 | cut -d= -f2 | tr -d 'v \r')
  case $OLDVER in ''|*[!0-9A-Za-z._-]*) OLDVER=prev ;; esac
  RB="$R/rollback/$OLDVER"
  if [ ! -d "$RB" ]; then
    mkdir -p "$RB"
    for item in bin webroot module.prop service.sh daemons.conf; do
      [ -e "$OLD/$item" ] && cp -pR "$OLD/$item" "$RB/$item" 2>/dev/null
    done
    say "- previous module saved for rollback: $RB"
  fi
fi
if [ -f "$AGDIR/appguard.sh" ] && ! grep -q 'KM_APPGUARD_V2' "$AGDIR/appguard.sh" 2>/dev/null; then
  [ -f "$R/rollback/appguard.sh.pre-km" ] || cp -p "$AGDIR/appguard.sh" "$R/rollback/appguard.sh.pre-km" 2>/dev/null
fi

# 3. permissions
if command -v set_perm_recursive >/dev/null 2>&1; then
  set_perm_recursive "$MODPATH" 0 0 0755 0644
  set_perm "$MODPATH/bin/dm" 0 0 0755
  set_perm "$MODPATH/service.sh" 0 0 0755
  set_perm "$MODPATH/uninstall.sh" 0 0 0755
  set_perm "$MODPATH/payload/appguard/appguard.sh" 0 0 0755
else
  chmod 755 "$MODPATH/bin/dm" "$MODPATH/service.sh" "$MODPATH/uninstall.sh" "$MODPATH/payload/appguard/appguard.sh" 2>/dev/null
fi

# 4. migrate now (best effort; otherwise the first dm call or the boot hook does it). Additive and
#    idempotent, no daemon is restarted, service.d scripts are never edited.
if [ -x "$MODPATH/bin/dm" ]; then
  KM_MODULE_DIR="$MODPATH" "$MODPATH/bin/dm" migrate >/dev/null 2>&1 && say "- data migrated to schema 2" || say "- migration deferred to first use"
fi
say "- done. Running daemons were not touched; restart AppGuard from the UI to apply v2."
