#!/system/bin/sh
# KM_APPGUARD_V2
# appguard.sh v2 - configurable idle-app watchdog (KonaManager). Runs as root.
#
# It never SIGKILLs apps: it asks ActivityManager to reap an app's background
# processes ("am kill --user N <pkg>"). Foreground apps and (user 0) apps still
# in recents are skipped. If the foreground cannot be determined the whole
# sweep is skipped (fail-safe).
#
#   appguard.sh start|run|once [--dry]|status|stop
#
# Config is re-read on every sweep, nothing needs a restart:
#   $R/appguard/appguard.conf   INTERVAL= COOLDOWN= DRY= CFGVER=   (KEY=VALUE)
#   $R/appguard/targets.tsv     pkg <TAB> u0 <TAB> u999 <TAB> cooldown_s (blank = default)
#   $R/appguard/never.list      one package per line, never touched, any user
# Written by the script:
#   $R/appguard/kills.tsv       epoch user pkg mode result cooldown reason  (cap 500)
#   $R/appguard/heartbeat       epoch version pid interval  (each sweep)
#   $BASE/appguard.log, $BASE/appguard.pid, $BASE/cool/<pkg>.<user> (stamps)
#
# Test hooks: DM_ROOT, KM_ADB, KM_AG_DIR, AG_PS, AG_AM, AG_DUMP, KM_TEST=1.

AG_VERSION=2.0.0
NL='
'
TAB=$(printf '\t')

if [ -n "$DM_ROOT" ] && [ -z "$KM_ADB" ]; then KM_ADB=$DM_ROOT/_adb; fi
KM_ADB=${KM_ADB:-/data/adb}
R=${DM_ROOT:-$KM_ADB/daemon-manager}
BASE=${KM_AG_DIR:-$KM_ADB/appguard}
CFG=$R/appguard
LOG=$BASE/appguard.log
PIDF=$BASE/appguard.pid
COOL=$BASE/cool
if [ -n "$AG_PS" ]; then PS=$AG_PS; elif [ -x /system/bin/ps ]; then PS=/system/bin/ps; else PS=ps; fi
if [ -n "$AG_AM" ]; then AM=$AG_AM; elif [ -x /system/bin/am ]; then AM=/system/bin/am; else AM=am; fi
if [ -n "$AG_DUMP" ]; then DUMP=$AG_DUMP; elif [ -x /system/bin/dumpsys ]; then DUMP=/system/bin/dumpsys; else DUMP=dumpsys; fi
if [ -x /system/bin/sh ]; then AG_SH=/system/bin/sh; else AG_SH=sh; fi

case $0 in /*) SELF=$0 ;; *) SELF=$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$(basename "$0") ;; esac

mkdir -p "$COOL" "$CFG" 2>/dev/null

log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$LOG"; }

rotate() {
  [ -f "$LOG" ] || return 0
  _n=$(wc -l <"$LOG" 2>/dev/null)
  if [ "${_n:-0}" -gt 1000 ]; then tail -n 600 "$LOG" >"$LOG.tmp" && mv "$LOG.tmp" "$LOG"; fi
  if [ -f "$CFG/kills.tsv" ]; then
    _n=$(wc -l <"$CFG/kills.tsv" 2>/dev/null)
    if [ "${_n:-0}" -gt 500 ]; then tail -n 400 "$CFG/kills.tsv" >"$CFG/kills.tsv.tmp" && mv "$CFG/kills.tsv.tmp" "$CFG/kills.tsv"; fi
  fi
}
logsize() { if [ -f "$LOG" ]; then wc -l <"$LOG"; else echo 0; fi; }

# ---- config ------------------------------------------------------------------
conf_num() { # key default min max
  _v=$(grep "^$1=" "$CFG/appguard.conf" 2>/dev/null | head -n 1 | cut -d= -f2)
  case $_v in ''|*[!0-9]*) _v=$2 ;; esac
  [ "$_v" -ge "$3" ] 2>/dev/null && [ "$_v" -le "$4" ] 2>/dev/null || _v=$2
  printf '%s' "$_v"
}
conf_load() {
  INTERVAL=$(conf_num INTERVAL 60 10 3600)
  COOLDOWN=$(conf_num COOLDOWN 300 0 86400)
  DRY=$(conf_num DRY 0 0 1)
  [ "$FORCE_DRY" = 1 ] && DRY=1
  return 0
}
never_load() {
  NEVER=" "
  [ -f "$CFG/never.list" ] || return 0
  while IFS= read -r _l || [ -n "$_l" ]; do
    case $_l in ''|*[!A-Za-z0-9_.]*) continue ;; esac
    NEVER="$NEVER$_l "
  done <"$CFG/never.list"
}

# ---- system state ------------------------------------------------------------
PSD=
RUN0=" "
RUN999=" "
snap_ps() {
  PSD=$BASE/ps.$$.tmp
  $PS -A -o uid,pid,args >"$PSD" 2>/dev/null
  RUN0=" "
  RUN999=" "
  while read -r _uid _pid _name _rest; do
    case $_uid in ''|*[!0-9]*) continue ;; esac
    _b=${_name%%:*}
    if [ "$_uid" -ge 99900000 ]; then RUN999="$RUN999$_b "; else RUN0="$RUN0$_b "; fi
  done <"$PSD"
  rm -f "$PSD"
  PSD=
}

foreground_pkgs() {
  { $DUMP window 2>/dev/null | grep -E 'mCurrentFocus=|mFocusedApp='
    $DUMP activity activities 2>/dev/null | grep -E 'topResumedActivity=|mResumedActivity='
  } | grep -oE '[a-zA-Z0-9_]+(\.[a-zA-Z0-9_]+)+/' | tr -d '/' | sort -u
}
recent_pkgs() {
  $DUMP activity recents 2>/dev/null | grep -oE 'A=[0-9]+:[a-zA-Z0-9_.]+' | sed 's/.*://' | sort -u
}

cool_get() { # pkg user -> epoch
  if [ -f "$COOL/$1.$2" ]; then cat "$COOL/$1.$2" 2>/dev/null; else echo 0; fi
}
cool_set() { printf '%s\n' "$3" >"$COOL/$1.$2"; }

am_kill() { # pkg user
  if [ "$2" = "999" ]; then
    $AM kill --user 999 "$1" >/dev/null 2>&1
  else
    $AM kill --user 0 "$1" >/dev/null 2>&1
  fi
}

add_kill() { # user pkg mode result cooldown reason
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$NOW" "$1" "$2" "$3" "$4" "$5" "$6" >>"$CFG/kills.tsv"
}

# ---- sweep -------------------------------------------------------------------
# process_one <pkg> <user> <cooldown>
process_one() {
  _pkg=$1
  _user=$2
  _cd=$3
  if [ "$_user" = 999 ]; then
    case $RUN999 in *" $_pkg "*) ;; *) return 0 ;; esac
  else
    case $RUN0 in *" $_pkg "*) ;; *) return 0 ;; esac
  fi
  S_CAND=$((S_CAND + 1))
  case "$NL$TOP$NL" in
    *"$NL$_pkg$NL"*)
      case $S_FG in *" $_pkg "*) ;; *) S_FG="$S_FG$_pkg " ;; esac
      log "skip [$_user] $_pkg (foreground)"
      return 0 ;;
  esac
  if [ "$_user" != 999 ]; then
    case "$NL$RECENT$NL" in
      *"$NL$_pkg$NL"*) S_REC=$((S_REC + 1)); log "skip $_pkg (recent)"; return 0 ;;
    esac
  fi
  _last=$(cool_get "$_pkg" "$_user")
  case $_last in ''|*[!0-9]*) _last=0 ;; esac
  if [ $((NOW - _last)) -lt "$_cd" ]; then
    S_COOL=$((S_COOL + 1))
    return 0
  fi
  if [ "$DRY" = 1 ]; then
    log "would am-kill [$_user] $_pkg"
    printf 'WOULD %s %s\n' "$_user" "$_pkg"
    add_kill "$_user" "$_pkg" dry ok "$_cd" dry-run
  else
    if am_kill "$_pkg" "$_user"; then _res=ok; else _res=fail; fi
    log "am-kill [$_user] $_pkg ($_res)"
    printf 'KILL %s %s\n' "$_user" "$_pkg"
    cool_set "$_pkg" "$_user" "$NOW"
    add_kill "$_user" "$_pkg" kill "$_res" "$_cd" idle
    S_KILLED=$((S_KILLED + 1))
  fi
}

sweep() {
  conf_load
  never_load
  S_CAND=0 S_KILLED=0 S_COOL=0 S_REC=0 S_FG=" "
  TOP=$(foreground_pkgs)
  if [ -z "$TOP" ]; then
    log "skip sweep (foreground unknown)"
    printf 'SWEEP skipped=foreground-unknown candidates=0 killed=0 skipped_cooldown=0 skipped_recent=0\n'
    return 0
  fi
  RECENT=$(recent_pkgs)
  NOW=$(date +%s)
  snap_ps
  if [ -f "$CFG/targets.tsv" ]; then
    while IFS="$TAB" read -r _tp _u0 _u999 _tc || [ -n "$_tp" ]; do
      case $_tp in ''|*[!A-Za-z0-9_.]*) continue ;; esac
      case $NEVER in *" $_tp "*) continue ;; esac
      _cdv=$COOLDOWN
      case $_tc in ''|*[!0-9]*) ;; *) _cdv=$_tc ;; esac
      [ "$_u0" = 1 ] && process_one "$_tp" 0 "$_cdv"
      [ "$_u999" = 1 ] && process_one "$_tp" 999 "$_cdv"
    done <"$CFG/targets.tsv"
  fi
  for _f in $S_FG; do printf 'FG %s\n' "$_f"; done
  printf 'SWEEP skipped=- candidates=%s killed=%s skipped_cooldown=%s skipped_recent=%s\n' "$S_CAND" "$S_KILLED" "$S_COOL" "$S_REC"
  [ "$S_KILLED" -gt 0 ] && log "sweep: $S_KILLED kill request(s)"
  return 0
}

heartbeat() {
  printf '%s %s %s %s\n' "$(date +%s)" "$AG_VERSION" "$$" "$INTERVAL" >"$CFG/heartbeat.tmp" && mv "$CFG/heartbeat.tmp" "$CFG/heartbeat"
}

# ---- process control ---------------------------------------------------------
is_ag_pid() { # pid: alive, not zombie, and really running this script
  case $1 in ''|*[!0-9]*) return 1 ;; esac
  [ "$1" -gt 1 ] || return 1
  [ -r "/proc/$1/cmdline" ] || return 1
  _c=$(tr '\000' '\n' <"/proc/$1/cmdline" 2>/dev/null)
  case "$NL$_c$NL" in *"${NL}appguard.sh$NL"*|*"$NL$BASE/appguard.sh$NL"*|*"$NL$SELF$NL"*) ;; *) return 1 ;; esac
  read -r _l <"/proc/$1/stat" 2>/dev/null || return 1
  _l=${_l##*) }
  case $_l in Z*|X*) return 1 ;; esac
  return 0
}
running() {
  _p=$(cat "$PIDF" 2>/dev/null)
  is_ag_pid "$_p"
}

need_root() { [ "$(id -u)" = "0" ] || [ "$KM_TEST" = 1 ]; }

case $1 in
  once)
    need_root || { echo "need root"; exit 1; }
    FORCE_DRY=0
    [ "$2" = "--dry" ] && FORCE_DRY=1
    sweep
    ;;
  run)
    need_root || exit 1
    if running && [ "$(cat "$PIDF" 2>/dev/null)" != "$$" ]; then echo "already running (pid $(cat "$PIDF"))"; exit 0; fi
    echo $$ >"$PIDF"
    SLP=
    trap '[ -n "$SLP" ] && kill "$SLP" 2>/dev/null; [ "$(cat "$PIDF" 2>/dev/null)" = "$$" ] && rm -f "$PIDF"; exit 0' INT TERM
    conf_load
    log "=== start v$AG_VERSION (interval ${INTERVAL}s, cooldown ${COOLDOWN}s, dry $DRY) ==="
    while :; do
      rotate
      sweep >/dev/null
      heartbeat
      slept=0
      while :; do
        conf_load
        [ "$slept" -ge "$INTERVAL" ] && break
        sleep 5 &
        SLP=$!
        wait "$SLP"
        slept=$((slept + 5))
      done
    done
    ;;
  start)
    if running; then echo "already running (pid $(cat "$PIDF" 2>/dev/null))"; exit 0; fi
    if command -v setsid >/dev/null 2>&1; then
      setsid "$AG_SH" "$SELF" run >/dev/null 2>&1 </dev/null &
    else
      "$AG_SH" "$SELF" run >/dev/null 2>&1 </dev/null &
    fi
    i=0
    while [ "$i" -lt 10 ]; do
      sleep 1
      if running; then echo "started (pid $(cat "$PIDF"))"; exit 0; fi
      i=$((i + 1))
    done
    echo "failed to start"; exit 1
    ;;
  stop)
    P=$(cat "$PIDF" 2>/dev/null)
    if is_ag_pid "$P"; then
      kill "$P" 2>/dev/null
      i=0
      while [ "$i" -lt 10 ] && is_ag_pid "$P"; do sleep 1; i=$((i + 1)); done
      is_ag_pid "$P" && kill -9 "$P" 2>/dev/null
    fi
    rm -f "$PIDF"
    echo "stopped"
    ;;
  status)
    conf_load
    if running; then echo "running (pid $(cat "$PIDF"), interval ${INTERVAL}s, cooldown ${COOLDOWN}s, dry $DRY)"; else echo "not running"; fi
    echo "version: $AG_VERSION"
    echo "log: $LOG ($(logsize) lines)"
    tail -n 6 "$LOG" 2>/dev/null
    ;;
  version) echo "$AG_VERSION" ;;
  *)
    echo "usage: $0 {start|run|once [--dry]|status|stop|version}"
    exit 1
    ;;
esac
