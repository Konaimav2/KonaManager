# km-proc.sh - process verification and daemon lifecycle.
#
# Truth for "is daemon X running" is: a live, non-zombie process that is not
# pid<=1, not dm itself or an ancestor, whose exact argv matches the meta AND
# that is tied to the daemon by (a) /proc/<pid>/environ KM_DAEMON_ID=<id>, or
# (b) a pidfile (the meta pidfile or R/daemons/<id>/daemon.pid). pgrep -f and
# pkill -f are never used. A decoy with the same command line has neither tie.

KM_ANC=
DV_NOADOPT=0

proc_init() {
  [ -n "$KM_ANC" ] && return 0
  KM_ANC=" $$ "
  _p=$$
  _i=0
  while [ "$_i" -lt 64 ]; do
    pstat "$_p" || break
    _p=$S_PPID
    case $_p in ''|0|1) break ;; esac
    KM_ANC="$KM_ANC$_p "
    _i=$((_i + 1))
  done
  return 0
}

# pstat <pid>: S_STATE S_PPID S_START from /proc/<pid>/stat (no forks). 1 if gone.
pstat() {
  S_STATE= S_PPID= S_START=
  _pp=$1
  [ -r "/proc/$_pp/stat" ] || return 1
  read -r _line <"/proc/$_pp/stat" || return 1
  [ -n "$_line" ] || return 1
  _rest=${_line##*) }
  set -- $_rest
  S_STATE=$1
  S_PPID=$2
  S_START=${20}
  return 0
}

# scan_markers [force]: one grep over every environ; caches pids carrying any marker.
KM_MARKED=
KM_SCANNED=0
scan_markers() {
  [ "$KM_SCANNED" = 1 ] && [ "$1" != force ] && return 0
  KM_MARKED=" "
  for _pth in $(grep -l -e 'KM_DAEMON_ID=' /proc/[0-9]*/environ 2>/dev/null); do
    _pid=${_pth#/proc/}
    _pid=${_pid%/environ}
    KM_MARKED="$KM_MARKED$_pid "
  done
  KM_SCANNED=1
}

# pverify <pid>: identity check against loaded M_*.
# Sets V_MARK (0/1), V_ARGV (0/1), V_START. Returns 1 if the pid must be ignored
# (unsafe, gone, zombie, dm itself).
pverify() {
  V_MARK=0 V_ARGV=1 V_START=
  _vp=$1
  case $_vp in ''|*[!0-9]*) return 1 ;; esac
  [ "$_vp" -gt 1 ] || return 1
  case $KM_ANC in *" $_vp "*) return 1 ;; esac
  pstat "$_vp" || return 1
  case $S_STATE in Z|X|x) return 1 ;; esac
  V_START=$S_START
  _cmd=$(tr '\000' '\n' <"/proc/$_vp/cmdline" 2>/dev/null)
  [ -n "$_cmd" ] || return 1
  case "$NL$_cmd$NL" in *"$NL$KM_SELF$NL"*|*"$NL$KM_ARG0$NL"*) return 1 ;; esac
  if [ -n "$M_argv_match" ]; then
    V_ARGV=0
    case "$NL$_cmd$NL" in *"$NL$M_argv_match$NL"*) V_ARGV=1 ;; esac
    if [ "$V_ARGV" = 0 ]; then
      # processes that rewrite their title (sshd) show one element holding the
      # whole command line; accept the match only as a whole word there
      case $_cmd in
        *"$NL"*) ;;
        *) case " $_cmd " in *" $M_argv_match "*) V_ARGV=1 ;; esac ;;
      esac
    fi
  fi
  case $KM_MARKED in
    *" $_vp "*)
      _env=$(tr '\000' '\n' <"/proc/$_vp/environ" 2>/dev/null)
      case "$NL$_env$NL" in *"${NL}KM_DAEMON_ID=$M_id$NL"*) V_MARK=1 ;; esac
      ;;
  esac
  return 0
}

in_set() { case $2 in *" $1 "*) return 0 ;; esac; return 1; }

# dv_run: verify the loaded daemon. Sets
#   P_PIDS    verified pids (identity proven)         P_PID  root pid or empty
#   P_TREE    P_PIDS + every other marker-tagged pid  P_BY   marker|pidfile+argv|none
#   P_PFPIDS  pids verified through a pidfile
dv_run() {
  P_PIDS= P_TREE= P_PFPIDS= P_PID= P_BY=none
  _opid=$R/daemons/$M_id/daemon.pid
  _pf=" "
  for _f in "$M_pidfile" "$_opid"; do
    [ -n "$_f" ] && [ -r "$_f" ] || continue
    _a= _b=
    read -r _a _b <"$_f" 2>/dev/null
    case $_a in ''|*[!0-9]*) continue ;; esac
    if [ "$_f" = "$_opid" ] && [ -n "$_b" ]; then
      pstat "$_a" || continue
      [ "$S_START" = "$_b" ] || continue
    fi
    _pf="$_pf$_a "
  done
  scan_markers
  _cands=" "
  for _c in $KM_MARKED $_pf; do
    in_set "$_c" "$_cands" || _cands="$_cands$_c "
  done
  _bymark=0
  for _c in $_cands; do
    pverify "$_c" || continue
    _inpf=0
    in_set "$_c" "$_pf" && _inpf=1
    if [ "$V_MARK" = 1 ]; then
      P_TREE="$P_TREE $_c"
      if [ "$V_ARGV" = 1 ]; then P_PIDS="$P_PIDS $_c"; _bymark=1; fi
    elif [ "$_inpf" = 1 ] && [ "$V_ARGV" = 1 ] && [ -n "$M_argv_match" ]; then
      P_PIDS="$P_PIDS $_c"
      P_PFPIDS="$P_PFPIDS $_c"
      P_TREE="$P_TREE $_c"
    fi
  done
  if [ -z "$P_PIDS" ] && [ "$M_adopt" = argv ] && [ -n "$M_argv_match" ] && [ "$DV_NOADOPT" != 1 ]; then
    dv_adopt
  fi
  [ -n "$P_PIDS" ] || return 0
  if [ "$_bymark" = 1 ]; then P_BY=marker; else P_BY=pidfile+argv; fi
  # root pid: the verified pid whose parent is not itself verified
  P_PID=
  for _c in $P_PIDS; do
    pstat "$_c" || continue
    if ! in_set "$S_PPID" " $P_PIDS "; then
      if [ -z "$P_PID" ] || [ "$_c" -lt "$P_PID" ]; then P_PID=$_c; fi
    fi
  done
  if [ -z "$P_PID" ]; then
    for _c in $P_PIDS; do
      if [ -z "$P_PID" ] || [ "$_c" -lt "$P_PID" ]; then P_PID=$_c; fi
    done
  fi
  return 0
}

# dv_adopt: legacy daemons started at boot carry no marker and (for some) no
# pidfile. Trust-on-first-sight: a process with the exact argv is recorded in
# daemon.pid (pid + start time), so a later decoy is not adopted over it.
dv_adopt() {
  _ad=
  for _pth in $(grep -l -e "$M_argv_match" /proc/[0-9]*/cmdline 2>/dev/null); do
    _c=${_pth#/proc/}
    _c=${_c%/cmdline}
    pverify "$_c" || continue
    [ "$V_ARGV" = 1 ] || continue
    _ad="$_ad $_c"
  done
  [ -n "$_ad" ] || return 0
  _root=
  for _c in $_ad; do
    pstat "$_c" || continue
    if ! in_set "$S_PPID" " $_ad "; then
      if [ -z "$_root" ] || [ "$_c" -lt "$_root" ]; then _root=$_c; fi
    fi
  done
  if [ -z "$_root" ]; then _root=${_ad# }; _root=${_root%% *}; fi
  pstat "$_root" || return 0
  printf '%s %s\n' "$_root" "$S_START" >"$R/daemons/$M_id/daemon.pid" 2>/dev/null
  P_PIDS=$_ad
  P_PFPIDS=$_ad
  P_TREE=$_ad
}

# ---- health ----------------------------------------------------------------
# dv_health: sets H_STATE ok|degraded|down|na and H_DETAIL (after dv_run).
dv_health() {
  H_STATE=na H_DETAIL=
  [ -n "$P_PIDS" ] || return 0
  case $M_health in
    proc|'') H_STATE=ok ;;
    port:*)
      _hp=${M_health#port:}
      if valid_int "$_hp" 1 65535; then
        _hex=$(printf '%04X' "$_hp")
        if grep -qiE ":$_hex [0-9A-F]+:[0-9A-F]+ 0A " /proc/net/tcp /proc/net/tcp6 2>/dev/null; then
          H_STATE=ok
        else
          H_STATE=degraded; H_DETAIL="port $_hp not listening"
        fi
      else
        H_STATE=ok
      fi
      ;;
    cmd:*)
      _hc=$(meta_abs "$M_id" "${M_health#cmd:}")
      if [ -n "$_hc" ] && [ -f "$_hc" ]; then
        if $KM_TIMEOUT 5 "$KM_SH" "$_hc" >/dev/null 2>&1; then H_STATE=ok; else H_STATE=degraded; H_DETAIL="health command failed"; fi
      else
        H_STATE=degraded; H_DETAIL="health command missing"
      fi
      ;;
    heartbeat:*)
      _hh=${M_health#heartbeat:}
      _hmax=${_hh##*:}
      _hf=${_hh%:*}
      if [ -r "$_hf" ]; then
        _he= _hv= _hp2= _hi=
        read -r _he _hv _hp2 _hi <"$_hf" 2>/dev/null
        case $_he in ''|*[!0-9]*) _he=0 ;; esac
        if [ "$_hmax" = auto ]; then
          case $_hi in ''|*[!0-9]*) _hmax=300 ;; *) _hmax=$((_hi * 3 + 30)) ;; esac
        fi
        _age=$(( $(epoch) - _he ))
        if [ "$_age" -le "$_hmax" ]; then H_STATE=ok; else H_STATE=degraded; H_DETAIL="heartbeat stale (${_age}s)"; fi
      else
        H_STATE=degraded; H_DETAIL="no heartbeat file (legacy version running, restart to apply)"
      fi
      ;;
    *) H_STATE=ok ;;
  esac
}

# ---- daemon object ---------------------------------------------------------
# daemon_obj <id>: loads meta, verifies, builds DOBJ. 1 if unknown.
daemon_obj() {
  _oid=$1
  meta_load "$_oid" || return 1
  proc_init
  dv_run
  _bf=$(boot_file "$_oid")
  _en=false
  is_enabled "$_bf" && _en=true
  _dir=$R/daemons/$_oid
  _lts= _lact= _lok= _lcode=
  [ -r "$_dir/last" ] && read -r _lts _lact _lok _lcode <"$_dir/last" 2>/dev/null
  _run=false
  _state=stopped
  EXITC=null
  if [ -n "$P_PIDS" ]; then
    _run=true; _state=running
  else
    if [ -r "$_dir/exit" ]; then
      read -r _ec _ <"$_dir/exit" 2>/dev/null
      case $_ec in ''|*[!0-9]*) ;; *) EXITC=$_ec ;; esac
    fi
    if [ "$M_kind" = oneshot ] && [ "$EXITC" != null ]; then
      if [ "$EXITC" = 0 ]; then _state=done; else _state=failed; fi
    elif [ "$_lact" = start ] && [ "$_lok" = 0 ]; then
      _state=failed
    fi
  fi
  [ -r /proc/1/stat ] || _state=unknown
  _pid=null
  _up=null
  if [ -n "$P_PID" ]; then
    _pid=$P_PID
    if pstat "$P_PID"; then
      uptime_s_now
      case $S_START in ''|*[!0-9]*) ;; *) _up=$(( UP_NOW - S_START / 100 )); [ "$_up" -ge 0 ] || _up=0 ;; esac
    fi
  fi
  dv_health
  if [ "$_state" = failed ] && [ "$H_STATE" = na ]; then H_STATE=down; fi
  jlist_ints "$P_PIDS"; _pids=$JL
  _lastj=null
  if [ -n "$_lts" ]; then
    case $_lts in *[!0-9]*) _lts=0 ;; esac
    jesc "$_lact"; _la=$JESC
    if [ "$_lcode" = "-" ]; then _lcode=; fi
    jesc "$_lcode"; _lc=$JESC
    _lokb=false
    [ "$_lok" = 1 ] && _lokb=true
    _lastj="{\"action\":\"$_la\",\"ts\":$_lts,\"ok\":$_lokb,\"code\":\"$_lc\"}"
  fi
  _remb=true
  [ "$M_removable" = 1 ] || _remb=false
  jesc "$M_name"; _n=$JESC
  jesc "$M_desc"; _d=$JESC
  jesc "$M_version"; _v=$JESC
  jesc "$H_DETAIL"; _hd=$JESC
  DOBJ="{\"id\":\"$_oid\",\"name\":\"$_n\",\"desc\":\"$_d\",\"kind\":\"$M_kind\",\"version\":\"$_v\",\"source\":\"$M_source\",\"enabled\":$_en,\"state\":\"$_state\",\"running\":$_run,\"pid\":$_pid,\"pids\":$_pids,\"uptime_s\":$_up,\"health\":\"$H_STATE\",\"health_detail\":\"$_hd\",\"verified_by\":\"$P_BY\",\"removable\":$_remb,\"boot\":\"$M_boot\",\"last\":$_lastj}"
  return 0
}

# ---- commands: list / status ----------------------------------------------
cmd_list() {
  proc_init
  scan_markers force
  _items=
  for _d in "$R"/daemons/*/; do
    [ -d "$_d" ] || continue
    _id=${_d%/}
    _id=${_id##*/}
    valid_id "$_id" || continue
    daemon_obj "$_id" || continue
    _items="${_items:+$_items,}$DOBJ"
  done
  ok_out ",\"dm\":\"$KM_VERSION\",\"schema\":$KM_SCHEMA,\"ts\":$(epoch),\"daemons\":[$_items]"
}

cmd_status() {
  valid_id "$1" || { err E_ARG "invalid id"; return 1; }
  [ -f "$R/daemons/$1/meta" ] || { err E_UNKNOWN "unknown daemon"; return 1; }
  proc_init
  scan_markers force
  daemon_obj "$1" || { err E_UNKNOWN "unknown daemon"; return 1; }
  _sdobj=$DOBJ
  _mj=
  while IFS='=' read -r _k _v || [ -n "$_k" ]; do
    case " $KM_META_KEYS " in *" $_k "*) ;; *) continue ;; esac
    jesc "$_v"
    _mj="${_mj:+$_mj,}\"$_k\":\"$JESC\""
  done <"$R/daemons/$1/meta"
  _lf=$(log_file_for "$1")
  _tail=
  [ -f "$_lf" ] && _tail=$(tail -n 20 "$_lf" 2>/dev/null | cut -c1-500)
  jlist_strs "$_tail"
  ok_out ",\"daemon\":$_sdobj,\"meta\":{$_mj},\"exit_code\":$EXITC,\"log_tail\":$JL"
}

log_file_for() { # id -> path (meta log=, else daemon.log)
  meta_load "$1" || return 1
  if [ -n "$M_log" ]; then printf '%s' "$M_log"; else printf '%s' "$R/daemons/$1/daemon.log"; fi
}

# ---- start ----------------------------------------------------------------
spawn_daemon() { # needs M_*, SPATH
  _dir=$R/daemons/$M_id
  mkdir -p "$_dir"
  (
    KM_DAEMON_ID=$M_id
    export KM_DAEMON_ID
    cd "$_dir" 2>/dev/null
    if [ -n "$KM_SETSID" ]; then exec $KM_SETSID "$KM_SH" "$SPATH"; fi
    exec "$KM_SH" "$SPATH"
  ) </dev/null >>"$_dir/daemon.log" 2>&1 &
  SP_PID=$!
}

start_fail() { # code msg state exit_code
  record_last "$M_id" start 0 "$1"
  jesc "$2"
  OUT="{\"ok\":false,\"code\":\"$1\",\"msg\":\"$JESC\",\"waited_ms\":${WAITED:-0},\"state\":\"$3\",\"exit_code\":${4:-null}}"
  km_log "start $M_id failed $1"
  return 1
}

start_ok() { # already(0/1) state exit_code
  record_last "$M_id" start 1 -
  jlist_ints "$P_PIDS"; _pl=$JL
  _up=0
  if [ -n "$P_PID" ] && pstat "$P_PID"; then
    uptime_s_now
    case $S_START in ''|*[!0-9]*) ;; *) _up=$(( UP_NOW - S_START / 100 )); [ "$_up" -ge 0 ] || _up=0 ;; esac
  fi
  _pidv=${P_PID:-null}
  _msg=started
  [ "$1" = 1 ] && _msg="already running"
  _alr=false
  [ "$1" = 1 ] && _alr=true
  if [ "$2" = done ]; then
    OUT="{\"ok\":true,\"id\":\"$M_id\",\"action\":\"start\",\"state\":\"done\",\"exit_code\":${3:-0},\"waited_ms\":${WAITED:-0},\"already\":false,\"pid\":null,\"pids\":[],\"uptime_s\":null,\"msg\":\"ran to completion\"}"
  else
    OUT="{\"ok\":true,\"id\":\"$M_id\",\"action\":\"start\",\"state\":\"running\",\"pid\":$_pidv,\"pids\":$_pl,\"uptime_s\":$_up,\"waited_ms\":${WAITED:-0},\"already\":$_alr,\"msg\":\"$_msg\"}"
  fi
  [ "$1" = 1 ] || km_log "start $M_id ok pid=${P_PID:-}"
  return 0
}

# start_core <id>: lock handled by the caller. Sets OUT.
start_core() {
  DV_NOADOPT=0
  meta_load "$1" || { err E_UNKNOWN "unknown daemon"; return 1; }
  SPATH=$(meta_abs "$1" "$M_start")
  WAITED=0
  if [ -z "$SPATH" ] || [ ! -f "$SPATH" ]; then
    start_fail E_NO_SCRIPT "start script missing" stopped null
    return 1
  fi
  proc_init
  scan_markers force
  dv_run
  if [ -n "$P_PIDS" ]; then
    start_ok 1 running
    return 0
  fi
  now_ms; _t0=$NOW_MS
  DV_NOADOPT=1   # from here on only what dm itself started (marker) or a pidfile may verify
  _limit=$(( M_start_timeout * 1000 ))
  if [ "$M_kind" = oneshot ]; then
    start_oneshot "$_t0" "$_limit"
    return $?
  fi
  SP_PID=
  spawn_daemon
  _exit_at=0
  _wex=null
  while :; do
    now_ms; WAITED=$(( NOW_MS - _t0 ))
    scan_markers force
    dv_run
    if [ -n "$P_PIDS" ]; then
      msleep   # settle: a process that dies right away is not "started"
      scan_markers force
      dv_run
      now_ms; WAITED=$(( NOW_MS - _t0 ))
      if [ -n "$P_PIDS" ]; then
        start_ok 0 running
        return 0
      fi
      start_fail E_START_EXITED "exited right after start" failed "$_wex"
      return 1
    fi
    if [ -n "$SP_PID" ]; then
      if ! pstat "$SP_PID" || [ "$S_STATE" = Z ]; then
        wait "$SP_PID" 2>/dev/null
        _wex=$?
        SP_PID=
        _exit_at=$NOW_MS
      fi
    fi
    if [ -z "$SP_PID" ] && [ "$_exit_at" != 0 ] && [ $(( NOW_MS - _exit_at )) -gt 1500 ]; then
      start_fail E_START_EXITED "start script exited (code $_wex) and no process was found" failed "$_wex"
      return 1
    fi
    if [ "$WAITED" -ge "$_limit" ]; then
      start_fail E_START_TIMEOUT "no verified process within ${M_start_timeout}s" unknown null
      return 1
    fi
    msleep
  done
}

start_oneshot() { # t0 limit
  _dir=$R/daemons/$M_id
  rm -f "$_dir/exit" "$_dir/exit.tmp"
  (
    KM_DAEMON_ID=$M_id
    export KM_DAEMON_ID
    cd "$_dir" 2>/dev/null
    "$KM_SH" "$SPATH" </dev/null >>"$_dir/daemon.log" 2>&1
    _c=$?
    printf '%s %s\n' "$_c" "$(epoch)" >"$_dir/exit.tmp" && mv "$_dir/exit.tmp" "$_dir/exit"
  ) </dev/null >/dev/null 2>&1 &
  while :; do
    now_ms; WAITED=$(( NOW_MS - $1 ))
    if [ -f "$_dir/exit" ]; then
      read -r _ec _ <"$_dir/exit"
      if [ "$_ec" = 0 ]; then
        P_PIDS= P_PID=
        start_ok 0 done 0
        return 0
      fi
      start_fail E_START_EXITED "exited with code $_ec" failed "$_ec"
      return 1
    fi
    if [ "$WAITED" -ge "$2" ]; then
      start_fail E_START_TIMEOUT "still running after ${M_start_timeout}s" running null
      return 1
    fi
    msleep
  done
}

cmd_start() {
  valid_id "$1" || { err E_ARG "invalid id"; return 1; }
  [ -f "$R/daemons/$1/meta" ] || { err E_UNKNOWN "unknown daemon"; return 1; }
  lock_take "$1" || { err E_BUSY "another action holds the lock for $1"; return 1; }
  start_core "$1"
  _rc=$?
  lock_drop
  return $_rc
}

# ---- stop -----------------------------------------------------------------
# stop_targets: pids that may be signalled, from the last dv_run.
stop_targets() {
  if [ "$M_stop_scope" = pidfile ]; then
    if [ -n "$P_PFPIDS" ]; then ST_PIDS=$P_PFPIDS; else ST_PIDS=$P_PIDS; fi
  else
    ST_PIDS="$P_TREE $P_PIDS"
  fi
}

stop_alive() { # re-scan; true while something stop must remove is left
  scan_markers force
  dv_run
  stop_targets
  case $ST_PIDS in *[0-9]*) return 0 ;; esac
  return 1
}

# sig_all <SIG>: signal every current target once (deduplicated, never <=1 or ancestors)
sig_all() {
  _sent=" "
  for _p in $ST_PIDS; do
    in_set "$_p" "$_sent" && continue
    _sent="$_sent$_p "
    case $KM_ANC in *" $_p "*) continue ;; esac
    [ "$_p" -gt 1 ] || continue
    if [ "$1" = KILL ] && [ "$KM_TEST" = 1 ] && [ "$KM_TEST_NOKILL" = 1 ]; then
      continue
    fi
    kill "-$1" "$_p" 2>/dev/null
    in_set "$_p" " $KILLED " || KILLED="$KILLED $_p"
  done
}

# wait_gone <ms>: poll until nothing is left or time is up. 0 when gone.
wait_gone() {
  now_ms; _w0=$NOW_MS
  while :; do
    stop_alive || return 0
    now_ms
    [ $(( NOW_MS - _w0 )) -ge "$1" ] && return 1
    msleep
  done
}

run_stop_cmd() {
  _logf=$R/daemons/$M_id/daemon.log
  _to=$(( M_stop_grace + 5 ))
  [ "$_to" -le 20 ] || _to=20
  (
    KM_DAEMON_ID=$M_id
    export KM_DAEMON_ID
    case $M_stop in
      cmd:*)
        _line=${M_stop#cmd:}
        if [ -n "$KM_TIMEOUT" ]; then $KM_TIMEOUT "$_to" "$KM_SH" -c "$_line"; else "$KM_SH" -c "$_line"; fi ;;
      *)
        _sp=$(meta_abs "$M_id" "$M_stop")
        [ -f "$_sp" ] || exit 127
        if [ -n "$KM_TIMEOUT" ]; then $KM_TIMEOUT "$_to" "$KM_SH" "$_sp"; else "$KM_SH" "$_sp"; fi ;;
    esac
  ) </dev/null >>"$_logf" 2>&1
}

stop_core() {
  DV_NOADOPT=0
  meta_load "$1" || { err E_UNKNOWN "unknown daemon"; return 1; }
  proc_init
  KILLED=
  STEPS=
  now_ms; _t0=$NOW_MS
  if ! stop_alive; then
    record_last "$1" stop 1 -
    OUT="{\"ok\":true,\"id\":\"$1\",\"action\":\"stop\",\"state\":\"stopped\",\"steps\":[],\"killed_pids\":[],\"waited_ms\":0,\"msg\":\"already stopped\"}"
    return 0
  fi
  DV_NOADOPT=1   # never adopt a new process while stopping
  _grace=$(( M_stop_grace * 1000 ))
  if [ -n "$M_stop" ]; then
    run_stop_cmd
    STEPS="\"stop_cmd\""
    if wait_gone "$_grace"; then stop_done "$_t0"; return 0; fi
  fi
  sig_all TERM
  STEPS="${STEPS:+$STEPS,}\"TERM\""
  if wait_gone "$_grace"; then stop_done "$_t0"; return 0; fi
  stop_alive
  sig_all KILL
  STEPS="${STEPS:+$STEPS,}\"KILL\""
  if wait_gone 3000; then stop_done "$_t0"; return 0; fi
  jlist_ints "$ST_PIDS"
  _pl=$JL
  now_ms
  record_last "$1" stop 0 E_STOP_STILL_RUNNING
  km_log "stop $1 still running"
  err E_STOP_STILL_RUNNING "still running after KILL" ",\"pids\":$_pl,\"steps\":[$STEPS],\"waited_ms\":$(( NOW_MS - _t0 ))"
  return 1
}

stop_done() { # t0
  _sid=$M_id
  now_ms
  _kp=
  for _p in $KILLED; do
    if pstat "$_p" && [ "$S_STATE" != Z ]; then continue; fi
    _kp="${_kp:+$_kp,}$_p"
  done
  rm -f "$R/daemons/$_sid/daemon.pid"
  record_last "$_sid" stop 1 -
  km_log "stop $_sid ok steps=$STEPS"
  OUT="{\"ok\":true,\"id\":\"$_sid\",\"action\":\"stop\",\"state\":\"stopped\",\"steps\":[$STEPS],\"killed_pids\":[$_kp],\"waited_ms\":$(( NOW_MS - $1 )),\"msg\":\"stopped\"}"
}

cmd_stop() {
  valid_id "$1" || { err E_ARG "invalid id"; return 1; }
  [ -f "$R/daemons/$1/meta" ] || { err E_UNKNOWN "unknown daemon"; return 1; }
  lock_take "$1" || { err E_BUSY "another action holds the lock for $1"; return 1; }
  stop_core "$1"
  _rc=$?
  lock_drop
  return $_rc
}

cmd_restart() {
  valid_id "$1" || { err E_ARG "invalid id"; return 1; }
  [ -f "$R/daemons/$1/meta" ] || { err E_UNKNOWN "unknown daemon"; return 1; }
  lock_take "$1" || { err E_BUSY "another action holds the lock for $1"; return 1; }
  _rid=$1
  stop_core "$_rid"
  _rc=$?
  _s=$OUT
  if [ $_rc -ne 0 ]; then
    lock_drop
    OUT="{\"ok\":false,\"code\":\"E_STOP_STILL_RUNNING\",\"msg\":\"restart aborted: stop failed\",\"stop\":$_s,\"start\":null}"
    return 1
  fi
  KM_SCANNED=0
  start_core "$_rid"
  _rc=$?
  _st=$OUT
  lock_drop
  if [ $_rc -eq 0 ]; then
    OUT="{\"ok\":true,\"id\":\"$_rid\",\"action\":\"restart\",\"stop\":$_s,\"start\":$_st}"
  else
    _code=${_st#*\"code\":\"}
    _code=${_code%%\"*}
    OUT="{\"ok\":false,\"code\":\"$_code\",\"msg\":\"restart: start failed\",\"stop\":$_s,\"start\":$_st}"
  fi
  return $_rc
}

# boot <id>: entry used by km-<id>.sh wrappers. Same result as start.
cmd_boot() { cmd_start "$1"; }

# ---- enable / disable -------------------------------------------------------
cmd_enable() {
  valid_id "$1" || { err E_ARG "invalid id"; return 1; }
  meta_load "$1" || { err E_UNKNOWN "unknown daemon"; return 1; }
  lock_take "$1" || { err E_BUSY "another action holds the lock for $1"; return 1; }
  _bf=$(boot_file "$1")
  if [ "$M_boot" = wrapper ]; then
    wrapper_write "$1" "${M_boot_wait:-1}" || { lock_drop; err E_PATH "cannot write boot wrapper"; return 1; }
  fi
  if [ ! -f "$_bf" ] || [ -L "$_bf" ]; then
    lock_drop
    record_last "$1" enable 0 E_NO_SCRIPT
    err E_NO_SCRIPT "boot script missing"
    return 1
  fi
  chmod 755 "$_bf" 2>/dev/null
  lock_drop
  km_log "enable $1"
  record_last "$1" enable 1 -
  ok_out ",\"id\":\"$1\",\"enabled\":true,\"boot\":\"$M_boot\",\"stopped\":false,\"msg\":\"enabled\""
}

cmd_disable() {
  _keep=0
  _did=$1
  [ "$2" = "--keep-running" ] && _keep=1
  valid_id "$_did" || { err E_ARG "invalid id"; return 1; }
  meta_load "$_did" || { err E_UNKNOWN "unknown daemon"; return 1; }
  lock_take "$_did" || { err E_BUSY "another action holds the lock for $_did"; return 1; }
  _bf=$(boot_file "$_did")
  [ -f "$_bf" ] && [ ! -L "$_bf" ] && chmod 644 "$_bf" 2>/dev/null
  km_log "disable $_did"
  _stopped=false
  if [ "$_keep" = 0 ]; then
    stop_core "$_did"
    _rc=$?
    if [ $_rc -ne 0 ]; then
      lock_drop
      return 1
    fi
    case $OUT in *'"steps":[]'*) ;; *) _stopped=true ;; esac
  fi
  meta_load "$_did"
  lock_drop
  record_last "$_did" disable 1 -
  ok_out ",\"id\":\"$_did\",\"enabled\":false,\"boot\":\"$M_boot\",\"stopped\":$_stopped,\"msg\":\"disabled\""
}

# ---- logs ------------------------------------------------------------------
cmd_logs() {
  _src=$1
  _n=${2:-100}
  valid_int "$_n" 1 200 || { err E_ARG "n must be 1..200"; return 1; }
  case $_src in
    dm) _f=$R/dm.log ;;
    appguard) _f=$KM_AG_DIR/appguard.log ;;
    *) valid_id "$_src" || { err E_ARG "invalid source"; return 1; }
       [ -f "$R/daemons/$_src/meta" ] || { err E_UNKNOWN "unknown daemon"; return 1; }
       _f=$(log_file_for "$_src") ;;
  esac
  _lines=
  _trunc=false
  if [ -f "$_f" ]; then
    _total=$(wc -l <"$_f" 2>/dev/null)
    [ "${_total:-0}" -gt "$_n" ] && _trunc=true
    _lines=$(tail -n "$_n" "$_f" 2>/dev/null | cut -c1-500)
  fi
  jlist_strs "$_lines"
  jesc "$_src"
  ok_out ",\"source\":\"$JESC\",\"lines\":$JL,\"truncated\":$_trunc"
}

# ---- doctor / version -------------------------------------------------------
cmd_version() {
  ok_out ",\"version\":\"$KM_VERSION\",\"schema\":$KM_SCHEMA"
}

cmd_doctor() {
  _tj=
  for _t in curl unzip sha256sum base64 pm; do
    _v=$(find_tool "$_t")
    if [ -n "$_v" ]; then jesc "$_v"; _e="\"$JESC\""; else _e=null; fi
    _tj="${_tj:+$_tj,}\"$_t\":$_e"
  done
  _root=false
  [ "$(id -u 2>/dev/null)" = 0 ] && _root=true
  _se=unknown
  if command -v getenforce >/dev/null 2>&1; then _se=$(getenforce 2>/dev/null); fi
  [ -n "$_se" ] || _se=unknown
  jesc "$_se"; _se=$JESC
  _w=false
  if mkdir -p "$R" 2>/dev/null && : >"$R/.w.$$" 2>/dev/null; then _w=true; rm -f "$R/.w.$$"; fi
  jesc "$R"; _r=$JESC
  jesc "${KM_BB:-}"; _bb=$JESC
  ok_out ",\"root\":$_root,\"tools\":{$_tj},\"selinux\":\"$_se\",\"writable\":$_w,\"busybox\":\"$_bb\",\"dm_root\":\"$_r\",\"version\":\"$KM_VERSION\""
}
