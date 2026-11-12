# km-appguard.sh - `dm appguard ...` plus the Deep Sleep Cool compat commands.
# Config lives in $R/appguard (appguard.conf, targets.tsv, never.list, kills.tsv,
# heartbeat). The AppGuard loop re-reads it every sweep.

AGC_INTERVAL=60 AGC_COOLDOWN=300 AGC_DRY=0 AGC_VER=1

ag_conf_load() {
  AGC_INTERVAL=60 AGC_COOLDOWN=300 AGC_DRY=0 AGC_VER=1
  [ -r "$KM_AG_CFG/appguard.conf" ] || return 0
  while IFS='=' read -r _k _v || [ -n "$_k" ]; do
    case $_k in
      INTERVAL) valid_int "$_v" 10 3600 && { norm_int "$_v"; AGC_INTERVAL=$NI; } ;;
      COOLDOWN) valid_int "$_v" 0 86400 && { norm_int "$_v"; AGC_COOLDOWN=$NI; } ;;
      DRY) valid_int "$_v" 0 1 && { norm_int "$_v"; AGC_DRY=$NI; } ;;
      CFGVER) valid_int "$_v" 0 999999999 && { norm_int "$_v"; AGC_VER=$NI; } ;;
    esac
  done <"$KM_AG_CFG/appguard.conf"
}

ag_conf_save() {
  AGC_VER=$((AGC_VER + 1))
  printf 'INTERVAL=%s\nCOOLDOWN=%s\nDRY=%s\nCFGVER=%s\n' "$AGC_INTERVAL" "$AGC_COOLDOWN" "$AGC_DRY" "$AGC_VER" \
    | atomic_write "$KM_AG_CFG/appguard.conf"
}

ag_never_set() { # newline-separated never list -> " a b "
  AG_NEVER=" "
  [ -f "$KM_AG_CFG/never.list" ] || return 0
  while IFS= read -r _l || [ -n "$_l" ]; do
    [ -n "$_l" ] && AG_NEVER="$AG_NEVER$_l "
  done <"$KM_AG_CFG/never.list"
}

# ag_target_obj <pkg> <u0> <u999> <cd>: builds TOBJ
ag_target_obj() {
  _b0=false _b9=false _sh=false _cdj=null
  [ "$2" = 1 ] && _b0=true
  [ "$3" = 1 ] && _b9=true
  case $4 in ''|*[!0-9]*) ;; *) _cdj=$4 ;; esac
  case $AG_NEVER in *" $1 "*) { [ "$2" = 1 ] || [ "$3" = 1 ]; } && _sh=true ;; esac
  TOBJ="{\"pkg\":\"$1\",\"u0\":$_b0,\"u999\":$_b9,\"cooldown_s\":$_cdj,\"shadowed\":$_sh}"
}

ag_targets_json() { # sets TJ (array body), counts T_N T_U0 T_U999
  ag_never_set
  TJ= T_N=0 T_U0=0 T_U999=0
  [ -f "$KM_AG_CFG/targets.tsv" ] || return 0
  while IFS="$TAB" read -r _p _a _b _c || [ -n "$_p" ]; do
    valid_pkg "$_p" || continue
    T_N=$((T_N + 1))
    [ "$_a" = 1 ] && T_U0=$((T_U0 + 1))
    [ "$_b" = 1 ] && T_U999=$((T_U999 + 1))
    ag_target_obj "$_p" "$_a" "$_b" "$_c"
    TJ="${TJ:+$TJ,}$TOBJ"
  done <"$KM_AG_CFG/targets.tsv"
}

ag_never_json() { # sets NJ (json array), N_N
  NJ= N_N=0
  [ -f "$KM_AG_CFG/never.list" ] || { NJ='[]'; return 0; }
  while IFS= read -r _l || [ -n "$_l" ]; do
    valid_pkg "$_l" || continue
    N_N=$((N_N + 1))
    NJ="${NJ:+$NJ,}\"$_l\""
  done <"$KM_AG_CFG/never.list"
  NJ="[$NJ]"
}

ag_installed_version() {
  AG_INST=
  [ -f "$KM_AG_DIR/appguard.sh" ] || return 0
  AG_INST=$(grep '^AG_VERSION=' "$KM_AG_DIR/appguard.sh" 2>/dev/null | head -n 1 | cut -d= -f2)
  [ -n "$AG_INST" ] || AG_INST=legacy
}

ag_get() {
  ag_conf_load
  ag_targets_json
  ag_never_json
  _dj=null
  _rv=
  if [ -f "$R/daemons/appguard/meta" ]; then
    daemon_obj appguard && _dj=$DOBJ
    if [ -n "$P_PIDS" ]; then
      _rv=legacy
      if [ -r "$KM_AG_CFG/heartbeat" ]; then
        read -r _he _hv _ <"$KM_AG_CFG/heartbeat" 2>/dev/null
        [ -n "$_hv" ] && _rv=$_hv
      fi
    fi
  fi
  ag_installed_version
  jesc "$_rv"; _rvj=$JESC
  jesc "$AG_INST"; _ivj=$JESC
  _dryb=false
  [ "$AGC_DRY" = 1 ] && _dryb=true
  ok_out ",\"config\":{\"interval_s\":$AGC_INTERVAL,\"cooldown_s\":$AGC_COOLDOWN,\"dry_run\":$_dryb},\"never\":$NJ,\"targets\":[$TJ],\"counts\":{\"targets\":$T_N,\"u0\":$T_U0,\"u999\":$T_U999,\"never\":$N_N},\"daemon\":$_dj,\"running_version\":\"$_rvj\",\"installed_version\":\"$_ivj\""
}

ag_set() {
  case $1 in
    interval) valid_int "$2" 10 3600 || { err E_ARG "interval must be 10..3600"; return 1; } ;;
    cooldown) valid_int "$2" 0 86400 || { err E_ARG "cooldown must be 0..86400"; return 1; } ;;
    dry) valid_int "$2" 0 1 || { err E_ARG "dry must be 0 or 1"; return 1; } ;;
    *) err E_ARG "usage: appguard set interval|cooldown|dry <value>"; return 1 ;;
  esac
  norm_int "$2"; _nv=$NI
  lock_take appguard-cfg || { err E_BUSY "config is being written"; return 1; }
  ag_conf_load
  case $1 in
    interval) AGC_INTERVAL=$_nv ;;
    cooldown) AGC_COOLDOWN=$_nv ;;
    dry) AGC_DRY=$_nv ;;
  esac
  mkdir -p "$KM_AG_CFG"
  ag_conf_save || { lock_drop; err E_PATH "cannot write appguard.conf"; return 1; }
  lock_drop
  km_log "appguard set $1=$2"
  ok_out ",\"key\":\"$1\",\"value\":$_nv,\"msg\":\"saved\""
}

# ---- targets ----------------------------------------------------------------
# ag_parse_opts: parses key=value args into O_U0 O_U999 O_CD (empty = unset); O_CD may be "default"
ag_parse_opts() {
  O_U0= O_U999= O_CD=
  for _o in "$@"; do
    case $_o in
      u0=0|u0=1) O_U0=${_o#u0=} ;;
      u999=0|u999=1) O_U999=${_o#u999=} ;;
      cooldown=default) O_CD=default ;;
      cooldown=*)
        valid_int "${_o#cooldown=}" 0 86400 || return 1
        norm_int "${_o#cooldown=}"; O_CD=$NI ;;
      *) return 1 ;;
    esac
  done
  return 0
}

ag_row_find() { # pkg -> sets F_U0 F_U999 F_CD, returns 0 if found (uses its own loop vars)
  F_U0= F_U999= F_CD=
  [ -f "$KM_AG_CFG/targets.tsv" ] || return 1
  while IFS="$TAB" read -r _rfp _rfa _rfb _rfc || [ -n "$_rfp" ]; do
    if [ "$_rfp" = "$1" ]; then F_U0=$_rfa F_U999=$_rfb F_CD=$_rfc; return 0; fi
  done <"$KM_AG_CFG/targets.tsv"
  return 1
}

# ag_rows_write <pkg> <mode add|set|rm> <u0> <u999> <cd>
ag_rows_write() {
  _t=$KM_AG_CFG/targets.tsv.tmp.$$
  : >"$_t"
  _hit=0
  if [ -f "$KM_AG_CFG/targets.tsv" ]; then
    while IFS="$TAB" read -r _p _a _b _c || [ -n "$_p" ]; do
      [ -n "$_p" ] || continue
      if [ "$_p" = "$1" ]; then
        _hit=1
        [ "$2" = rm ] && continue
        printf '%s\t%s\t%s\t%s\n' "$_p" "$3" "$4" "$5" >>"$_t"
      else
        printf '%s\t%s\t%s\t%s\n' "$_p" "$_a" "$_b" "$_c" >>"$_t"
      fi
    done <"$KM_AG_CFG/targets.tsv"
  fi
  [ "$2" = add ] && printf '%s\t%s\t%s\t%s\n' "$1" "$3" "$4" "$5" >>"$_t"
  mv "$_t" "$KM_AG_CFG/targets.tsv"
}

ag_targets() {
  _sub=$1
  [ $# -gt 0 ] && shift
  case $_sub in
    list)
      ag_targets_json
      ok_out ",\"targets\":[$TJ]"
      return 0 ;;
    add|set|rm) ;;
    *) err E_ARG "usage: appguard targets list|add|set|rm <pkg> [u0=0|1] [u999=0|1] [cooldown=N|default]"; return 1 ;;
  esac
  _pkg=$1
  [ $# -gt 0 ] && shift
  valid_pkg "$_pkg" || { err E_ARG "invalid package name"; return 1; }
  ag_parse_opts "$@" || { err E_ARG "options are u0=0|1 u999=0|1 cooldown=<0..86400>|default"; return 1; }
  lock_take appguard-cfg || { err E_BUSY "config is being written"; return 1; }
  mkdir -p "$KM_AG_CFG"
  ag_never_set
  if ag_row_find "$_pkg"; then _exists=1; else _exists=0; fi
  case $_sub in
    add)
      if [ "$_exists" = 1 ]; then lock_drop; err E_CONFLICT "already a target; use targets set"; return 1; fi
      _u0=${O_U0:-1}; _u9=${O_U999:-0}; _cd=
      case $O_CD in ''|default) ;; *) _cd=$O_CD ;; esac
      ag_rows_write "$_pkg" add "$_u0" "$_u9" "$_cd" ;;
    set)
      if [ "$_exists" = 0 ]; then lock_drop; err E_UNKNOWN "not a target"; return 1; fi
      _u0=${O_U0:-$F_U0}; _u9=${O_U999:-$F_U999}; _cd=$F_CD
      case $O_CD in default) _cd= ;; '') ;; *) _cd=$O_CD ;; esac
      ag_rows_write "$_pkg" set "$_u0" "$_u9" "$_cd" ;;
    rm)
      if [ "$_exists" = 0 ]; then lock_drop; err E_UNKNOWN "not a target"; return 1; fi
      _u0=$F_U0; _u9=$F_U999; _cd=$F_CD
      ag_rows_write "$_pkg" rm "$_u0" "$_u9" "$_cd" ;;
  esac
  lock_drop
  km_log "appguard targets $_sub $_pkg"
  _cdj=null
  case $_cd in ''|*[!0-9]*) ;; *) _cdj=$_cd ;; esac
  _b0=false; _b9=false
  [ "$_u0" = 1 ] && _b0=true
  [ "$_u9" = 1 ] && _b9=true
  ok_out ",\"pkg\":\"$_pkg\",\"u0\":$_b0,\"u999\":$_b9,\"cooldown_s\":$_cdj"
}

ag_never() {
  _sub=$1
  case $_sub in
    list) ;;
    add|rm)
      valid_pkg "$2" || { err E_ARG "invalid package name"; return 1; }
      lock_take appguard-cfg || { err E_BUSY "config is being written"; return 1; }
      mkdir -p "$KM_AG_CFG"
      _t=$KM_AG_CFG/never.list.tmp.$$
      : >"$_t"
      _seen=0
      if [ -f "$KM_AG_CFG/never.list" ]; then
        while IFS= read -r _l || [ -n "$_l" ]; do
          [ -n "$_l" ] || continue
          if [ "$_l" = "$2" ]; then
            _seen=1
            [ "$_sub" = rm ] && continue
          fi
          printf '%s\n' "$_l" >>"$_t"
        done <"$KM_AG_CFG/never.list"
      fi
      [ "$_sub" = add ] && [ "$_seen" = 0 ] && printf '%s\n' "$2" >>"$_t"
      mv "$_t" "$KM_AG_CFG/never.list"
      lock_drop
      km_log "appguard never $_sub $2" ;;
    *) err E_ARG "usage: appguard never list|add|rm <pkg>"; return 1 ;;
  esac
  ag_never_json
  ok_out ",\"never\":$NJ"
}

# ---- packages ----------------------------------------------------------------
ag_packages() {
  _user=0
  _q=
  while [ $# -gt 0 ]; do
    case $1 in
      --user) valid_int "$2" 0 999 && { [ "$2" = 0 ] || [ "$2" = 999 ]; } || { err E_ARG "user must be 0 or 999"; return 1; }
              _user=$2; shift 2 ;;
      --q) case $2 in *[!A-Za-z0-9_.-]*) err E_ARG "invalid query"; return 1 ;; esac
           [ "${#2}" -le 64 ] || { err E_ARG "query too long"; return 1; }
           _q=$2; shift 2 ;;
      *) err E_ARG "usage: appguard packages [--user 0|999] [--q <substr>]"; return 1 ;;
    esac
  done
  _pm=$(find_tool pm) || { err E_NO_TOOL "pm not found"; return 1; }
  _list=$($_pm list packages -3 --user "$_user" 2>/dev/null | sed -n 's/^package://p' | tr -d '\r' | sort)
  ag_never_set
  _items=
  _cnt=0
  for _p in $_list; do
    valid_pkg "$_p" || continue
    if [ -n "$_q" ]; then
      case $_p in *"$_q"*) ;; *) continue ;; esac
    fi
    _tg=false
    if ag_row_find "$_p"; then
      if [ "$_user" = 999 ]; then [ "$F_U999" = 1 ] && _tg=true; else [ "$F_U0" = 1 ] && _tg=true; fi
    fi
    _nv=false
    case $AG_NEVER in *" $_p "*) _nv=true ;; esac
    _items="${_items:+$_items,}{\"pkg\":\"$_p\",\"target\":$_tg,\"never\":$_nv}"
    _cnt=$((_cnt + 1))
    [ "$_cnt" -ge 1000 ] && break
  done
  ok_out ",\"user\":$_user,\"packages\":[$_items]"
}

# ---- kills --------------------------------------------------------------------
ag_kills() {
  _lim=${1:-50}
  valid_int "$_lim" 1 200 || { err E_ARG "limit must be 1..200"; return 1; }
  _tot=0
  _items=
  if [ -f "$KM_AG_CFG/kills.tsv" ]; then
    _tot=$(wc -l <"$KM_AG_CFG/kills.tsv")
    _tot=$((_tot + 0))
    _tmp=$(tail -n "$_lim" "$KM_AG_CFG/kills.tsv")
    _oifs=$IFS
    IFS=$NL
    set -f
    for _ln in $_tmp; do
      IFS="$TAB"
      set -- $_ln
      IFS=$NL
      [ $# -ge 6 ] || continue
      valid_pkg "$3" || continue
      case $1 in *[!0-9]*) continue ;; esac
      case $2 in 0|999) ;; *) continue ;; esac
      case $4 in kill|dry) ;; *) continue ;; esac
      case $5 in ok|fail) ;; *) continue ;; esac
      case $6 in ''|*[!0-9]*) _c=null ;; *) _c=$6 ;; esac
      jesc "$7"
      _items="{\"ts\":$1,\"user\":$2,\"pkg\":\"$3\",\"mode\":\"$4\",\"result\":\"$5\",\"cooldown_s\":$_c,\"reason\":\"$JESC\"}${_items:+,$_items}"
    done
    set +f
    IFS=$_oifs
  fi
  ok_out ",\"total\":$_tot,\"kills\":[$_items]"
}

# ---- once --------------------------------------------------------------------
ag_once() {
  _dry=0
  case $1 in
    '') ;;
    --dry) _dry=1 ;;
    *) err E_ARG "usage: appguard once [--dry]"; return 1 ;;
  esac
  _script=$KM_AG_DIR/appguard.sh
  if [ ! -f "$_script" ] || ! grep -q 'KM_APPGUARD_V2' "$_script" 2>/dev/null; then
    _script=$KM_MODDIR/payload/appguard/appguard.sh
  fi
  [ -f "$_script" ] || { err E_NO_SCRIPT "appguard.sh not found"; return 1; }
  ag_conf_load
  [ "$AGC_DRY" = 1 ] && _dry=1
  mkdir -p "$KM_AG_DIR" "$KM_AG_CFG"
  now_ms; _t0=$NOW_MS
  if [ "$_dry" = 1 ] && [ "$1" = --dry ]; then _arg=--dry; else _arg=; fi
  _tp=
  [ -n "$KM_TIMEOUT" ] && _tp="$KM_TIMEOUT 55"
  _outp=$(DM_ROOT=$R KM_ADB=$KM_ADB KM_AG_DIR=$KM_AG_DIR $_tp "$KM_SH" "$_script" once $_arg 2>/dev/null)
  _rc=$?
  now_ms; _ms=$(( NOW_MS - _t0 ))
  case $_outp in *SWEEP*) ;; *) err E_UNKNOWN "sweep failed (exit $_rc)"; return 1 ;; esac
  _wk= _fg= _skip=null _cand=0 _killed=0 _scool=0 _srec=0
  _oifs=$IFS
  IFS=$NL
  set -f
  for _ln in $_outp; do
    IFS=' '
    set -- $_ln
    IFS=$NL
    case $1 in
      WOULD) valid_pkg "$3" && _wk="${_wk:+$_wk,}{\"user\":$2,\"pkg\":\"$3\"}" ;;
      FG) valid_pkg "$2" && _fg="${_fg:+$_fg,}\"$2\"" ;;
      SWEEP)
        shift
        for _kv in "$@"; do
          case $_kv in
            skipped=foreground-unknown) _skip='"foreground-unknown"' ;;
            candidates=*) _cand=${_kv#*=} ;;
            killed=*) _killed=${_kv#*=} ;;
            skipped_cooldown=*) _scool=${_kv#*=} ;;
            skipped_recent=*) _srec=${_kv#*=} ;;
          esac
        done ;;
    esac
  done
  set +f
  IFS=$_oifs
  km_log "appguard once dry=$_dry killed=$_killed"
  ok_out ",\"dry\":$(jbool "$_dry"),\"sweep\":{\"skipped\":$_skip,\"candidates\":$_cand,\"killed\":$_killed,\"would_kill\":[$_wk],\"skipped_fg\":[$_fg],\"skipped_cooldown\":$_scool,\"skipped_recent\":$_srec},\"ms\":$_ms"
}

cmd_appguard() {
  _sub=$1
  [ $# -gt 0 ] && shift
  case $_sub in
    get) ag_get ;;
    set) ag_set "$@" ;;
    targets) ag_targets "$@" ;;
    never) ag_never "$@" ;;
    packages) ag_packages "$@" ;;
    kills) ag_kills "$@" ;;
    once) ag_once "$@" ;;
    *) err E_USAGE "usage: appguard get|set|targets|never|packages|kills|once" ;;
  esac
}

# ---- Deep Sleep Cool compat (getconf / setconf / whitelist / packages) ---------
DSCONF=$R/deep-sleep-cool.conf
DEFAULT_WL="com.whatsapp com.whatsapp.w4b com.discord com.termux com.termux.boot com.termux.api com.wireguard.android com.kanagawa.yamada.project.raco com.digibites.accubattery"

conf_wl() {
  _w=$(grep '^WHITELIST=' "$DSCONF" 2>/dev/null | head -n 1 | cut -d= -f2- | tr -d '"')
  [ -n "$_w" ] || _w=$DEFAULT_WL
  printf '%s' "$_w"
}
conf_freeze() {
  _f=$(grep '^FREEZE_WHEN_UNPLUGGED=' "$DSCONF" 2>/dev/null | head -n 1 | cut -d= -f2)
  case $_f in 1) printf '1' ;; *) printf '0' ;; esac
}
ensure_dsconf() {
  [ -f "$DSCONF" ] && return 0
  printf 'FREEZE_WHEN_UNPLUGGED=0\nWHITELIST="%s"\n' "$DEFAULT_WL" >"$DSCONF"
}
write_wl() { # only ever called by whitelist add/rm/set, never by migration
  ensure_dsconf
  _t=$DSCONF.tmp.$$
  _done=0
  while IFS= read -r _l || [ -n "$_l" ]; do
    case $_l in
      WHITELIST=*) if [ "$_done" = 0 ]; then printf 'WHITELIST="%s"\n' "$1" >>"$_t"; _done=1; fi ;;
      *) printf '%s\n' "$_l" >>"$_t" ;;
    esac
  done <"$DSCONF"
  [ "$_done" = 1 ] || printf 'WHITELIST="%s"\n' "$1" >>"$_t"
  cat "$_t" >"$DSCONF" && rm -f "$_t"
}

cmd_getconf() {
  [ "$(conf_freeze)" = 1 ] && _fj=true || _fj=false
  _w=$(conf_wl)
  _l=
  for _p in $_w; do _l="${_l:+$_l,}\"$_p\""; done
  ok_out ",\"freeze_unplugged\":$_fj,\"whitelist\":[$_l]"
}

cmd_setconf() {
  [ "$1" = freeze_unplugged ] || { err E_ARG "unknown setting"; return 1; }
  case $2 in 0|1) ;; *) err E_ARG "value must be 0 or 1"; return 1 ;; esac
  ensure_dsconf
  _t=$DSCONF.tmp.$$
  _done=0
  while IFS= read -r _l || [ -n "$_l" ]; do
    case $_l in
      FREEZE_WHEN_UNPLUGGED=*) if [ "$_done" = 0 ]; then printf 'FREEZE_WHEN_UNPLUGGED=%s\n' "$2" >>"$_t"; _done=1; fi ;;
      *) printf '%s\n' "$_l" >>"$_t" ;;
    esac
  done <"$DSCONF"
  [ "$_done" = 1 ] || printf 'FREEZE_WHEN_UNPLUGGED=%s\n' "$2" >>"$_t"
  cat "$_t" >"$DSCONF" && rm -f "$_t"
  km_log "set freeze_unplugged=$2"
  ok_out ",\"msg\":\"saved\""
}

cmd_whitelist() {
  case $1 in
    list) cmd_getconf ;;
    add)
      valid_pkg "$2" || { err E_ARG "invalid package"; return 1; }
      _w=$(conf_wl)
      case " $_w " in *" $2 "*) ;; *) _w="$_w $2" ;; esac
      write_wl "$_w"; km_log "whitelist add $2"
      ok_out ",\"msg\":\"added\"" ;;
    rm)
      valid_pkg "$2" || { err E_ARG "invalid package"; return 1; }
      _w=$(conf_wl); _nw=
      for _p in $_w; do [ "$_p" = "$2" ] || _nw="$_nw $_p"; done
      write_wl "${_nw# }"; km_log "whitelist rm $2"
      ok_out ",\"msg\":\"removed\"" ;;
    set)
      _nw=
      for _p in $2; do valid_pkg "$_p" && _nw="$_nw $_p"; done
      write_wl "${_nw# }"; km_log "whitelist set"
      ok_out ",\"msg\":\"saved\"" ;;
    *) err E_ARG "usage: whitelist list|add|rm|set" ;;
  esac
}

# packages (compat): {"ok":true,"packages":["pkg",...]} (v1 printed a bare array)
cmd_packages() {
  _pm=$(find_tool pm) || { err E_NO_TOOL "pm not found"; return 1; }
  _l=
  for _p in $($_pm list packages -3 2>/dev/null | sed -n 's/^package://p' | tr -d '\r' | sort); do
    valid_pkg "$_p" && _l="${_l:+$_l,}\"$_p\""
  done
  ok_out ",\"packages\":[$_l]"
}
