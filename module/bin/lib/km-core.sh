# km-core.sh - environment, tools, validation, locks, meta, logging.
# POSIX sh for Android mksh/toybox. No arrays, no [[ ]], no jq, no python.

KM_VERSION=2.0.0
KM_SCHEMA=2
NL='
'
TAB=$(printf '\t')

# ---- paths -----------------------------------------------------------------
# DM_ROOT alone (tests) must never reach the real /data/adb tree, so without an
# explicit KM_ADB the other live paths move under the test root.
if [ -n "$DM_ROOT" ] && [ -z "$KM_ADB" ]; then
  KM_ADB=$DM_ROOT/_adb
fi
KM_ADB=${KM_ADB:-/data/adb}
R=${DM_ROOT:-$KM_ADB/daemon-manager}
KM_MODDIR=${KM_MODULE_DIR:-$KM_ADB/modules/daemon-manager}
KM_SERVICE_D=${KM_SERVICE_D:-$KM_ADB/service.d}
KM_AG_DIR=${KM_AG_DIR:-$KM_ADB/appguard}
KM_AG_CFG=$R/appguard

# ---- tools -----------------------------------------------------------------
km_tools_init() {
  KM_BB=
  for _c in "$KM_BUSYBOX" "$KM_ADB/ksu/bin/busybox" "$KM_ADB/magisk/busybox" "$KM_ADB/ap/bin/busybox"; do
    if [ -n "$_c" ] && [ -x "$_c" ]; then KM_BB=$_c; break; fi
  done
  [ -n "$KM_BB" ] || KM_BB=$(command -v busybox 2>/dev/null)
  KM_BBLIST=
  if [ -n "$KM_BB" ]; then
    KM_BBLIST=" $("$KM_BB" --list 2>/dev/null | tr '\n' ' ') "
  fi
  if [ -x /system/bin/sh ]; then KM_SH=/system/bin/sh; else KM_SH=$(command -v sh 2>/dev/null); fi
  [ -n "$KM_SH" ] || KM_SH=sh
  KM_SETSID=$(find_tool setsid)
  KM_TIMEOUT=$(find_tool timeout)
}

# find_tool <name>: prints a command string (busybox applet first, then PATH).
find_tool() {
  case $KM_BBLIST in
    *" $1 "*) printf '%s %s' "$KM_BB" "$1"; return 0 ;;
  esac
  _p=$(command -v "$1" 2>/dev/null)
  if [ -n "$_p" ]; then printf '%s' "$_p"; return 0; fi
  if [ "$1" = curl ] && [ -x /data/data/com.termux/files/usr/bin/curl ]; then
    printf '%s' /data/data/com.termux/files/usr/bin/curl
    return 0
  fi
  return 1
}

# ---- time and sleep (no forks) ---------------------------------------------
now_ms() {
  read -r _u _ </proc/uptime
  _i=${_u%%.*}
  _f=${_u#*.}00
  _f=${_f%"${_f#??}"}
  case $_f in 0?) _f=${_f#0} ;; esac
  NOW_MS=$(( _i * 1000 + _f * 10 ))
}
uptime_s_now() {
  read -r _u _ </proc/uptime
  UP_NOW=${_u%%.*}
}
msleep() { sleep 0.2 2>/dev/null || sleep 1; }
epoch() { date +%s; }

# ---- logging ---------------------------------------------------------------
km_log() {
  [ -d "$R" ] || return 0
  printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$R/dm.log" 2>/dev/null
  _n=$(wc -l <"$R/dm.log" 2>/dev/null)
  if [ "${_n:-0}" -gt 1000 ]; then
    tail -n 600 "$R/dm.log" >"$R/dm.log.tmp" 2>/dev/null && mv "$R/dm.log.tmp" "$R/dm.log"
  fi
  return 0
}

# ---- validation ------------------------------------------------------------
valid_id() {
  case $1 in ''|-*|*[!a-z0-9-]*) return 1 ;; esac
  [ "${#1}" -ge 2 ] && [ "${#1}" -le 31 ]
}
valid_pkg() {
  case $1 in ''|*[!A-Za-z0-9_.]*) return 1 ;; esac
  [ "${#1}" -le 128 ]
}
# valid_int <v> <min> <max>
valid_int() {
  case $1 in ''|*[!0-9]*) return 1 ;; esac
  [ "${#1}" -le 9 ] || return 1
  [ "$1" -ge "$2" ] && [ "$1" -le "$3" ]
}
valid_token() { # t_xxxxxxxx
  case $1 in t_????????) ;; *) return 1 ;; esac
  case ${1#t_} in *[!a-f0-9]*) return 1 ;; esac
  return 0
}
valid_sha() {
  case $1 in *[!a-fA-F0-9]*|'') return 1 ;; esac
  [ "${#1}" -eq 64 ]
}
# single-line text, no control chars, bounded
valid_line() { # <text> <maxlen>
  case $1 in *"$NL"*) return 1 ;; esac
  [ "${#1}" -le "$2" ] || return 1
  _vl_a=$(printf '%s' "$1" | wc -c)
  _vl_b=$(printf '%s' "$1" | LC_ALL=C tr -d '[:cntrl:]' | wc -c)
  [ "$_vl_a" = "$_vl_b" ]
}

# norm_int <digits>: strips leading zeros into NI (JSON-safe, never octal)
norm_int() {
  NI=$1
  while :; do
    case $NI in 0?*) NI=${NI#0} ;; *) break ;; esac
  done
}

# safe_rmtree <path> <prefix>: rm -rf only strictly inside prefix, never through a symlink
safe_rmtree() {
  [ -n "$1" ] && [ -n "$2" ] || return 1
  case $1 in "$2"/?*) ;; *) return 1 ;; esac
  case $1 in *..*) return 1 ;; esac
  if [ -L "$1" ]; then rm -f "$1"; return 0; fi
  [ -e "$1" ] || return 0
  _rp=$(cd "$1" 2>/dev/null && pwd -P) || return 1
  _pp=$(cd "$2" 2>/dev/null && pwd -P) || return 1
  case $_rp in "$_pp"/?*) ;; *) return 1 ;; esac
  rm -rf "$1"
}

# ---- base64 ----------------------------------------------------------------
# b64_decode_to <b64> <outfile>: 0 ok, 1 bad. Rejects NUL bytes.
b64_decode_to() {
  _b=$(find_tool base64) || return 2
  printf '%s' "$1" | tr -d ' \n\r' | $_b -d >"$2" 2>/dev/null || return 1
  _a=$(wc -c <"$2")
  _z=$(tr -d '\000' <"$2" | wc -c)
  [ "$_a" = "$_z" ] || return 1
  return 0
}

# ---- atomic write ----------------------------------------------------------
# atomic_write <file>   (content on stdin)
atomic_write() {
  _t=$1.tmp.$$
  cat >"$_t" && mv "$_t" "$1" || { rm -f "$_t"; return 1; }
}

# ---- locks (mkdir based, stale-safe) ---------------------------------------
KM_LOCK=
lock_take() {
  _ld=$R/lock
  mkdir -p "$_ld" 2>/dev/null
  _l=$_ld/$1
  if mkdir "$_l" 2>/dev/null; then
    echo $$ >"$_l/pid"; KM_LOCK=$_l; return 0
  fi
  _p=$(cat "$_l/pid" 2>/dev/null)
  case $_p in ''|*[!0-9]*) _p= ;; esac
  if [ -n "$_p" ] && kill -0 "$_p" 2>/dev/null; then return 1; fi
  rm -rf "$_l"
  mkdir "$_l" 2>/dev/null || return 1
  echo $$ >"$_l/pid"; KM_LOCK=$_l; return 0
}
lock_drop() {
  [ -n "$KM_LOCK" ] && rm -rf "$KM_LOCK"
  KM_LOCK=
  return 0
}

# ---- meta (key=value, whitelist, never sourced) ----------------------------
KM_META_KEYS="id name desc version kind source start stop pidfile argv_match stop_scope start_timeout stop_grace health boot boot_wait removable enabled_hint boot_script log adopt install_sha uninstall_sha"

meta_reset() {
  M_id= M_name= M_desc= M_version= M_kind= M_source= M_start= M_stop=
  M_pidfile= M_argv_match= M_stop_scope= M_start_timeout= M_stop_grace=
  M_health= M_boot= M_boot_wait= M_removable= M_enabled_hint= M_boot_script=
  M_log= M_adopt= M_install_sha= M_uninstall_sha=
}

# meta_load <id>: loads $R/daemons/<id>/meta, applies defaults. 1 if missing.
meta_load() {
  _f=$R/daemons/$1/meta
  [ -f "$_f" ] || return 1
  meta_reset
  while IFS='=' read -r _k _v || [ -n "$_k" ]; do
    case $_k in
      id) M_id=$_v ;;
      name) M_name=$_v ;;
      desc) M_desc=$_v ;;
      version) M_version=$_v ;;
      kind) M_kind=$_v ;;
      source) M_source=$_v ;;
      start) M_start=$_v ;;
      stop) M_stop=$_v ;;
      pidfile) M_pidfile=$_v ;;
      argv_match) M_argv_match=$_v ;;
      stop_scope) M_stop_scope=$_v ;;
      start_timeout) M_start_timeout=$_v ;;
      stop_grace) M_stop_grace=$_v ;;
      health) M_health=$_v ;;
      boot) M_boot=$_v ;;
      boot_wait) M_boot_wait=$_v ;;
      removable) M_removable=$_v ;;
      enabled_hint) M_enabled_hint=$_v ;;
      boot_script) M_boot_script=$_v ;;
      log) M_log=$_v ;;
      adopt) M_adopt=$_v ;;
      install_sha) M_install_sha=$_v ;;
      uninstall_sha) M_uninstall_sha=$_v ;;
    esac
  done <"$_f"
  [ "$M_id" = "$1" ] || M_id=$1
  [ -n "$M_name" ] || M_name=$1
  case $M_kind in oneshot) ;; *) M_kind=daemon ;; esac
  [ -n "$M_source" ] || M_source=created
  if [ -z "$M_argv_match" ] && { [ "$M_source" = package ] || [ "$M_source" = created ]; }; then
    _am=$(meta_abs "$1" "$M_start" 2>/dev/null)
    [ -n "$_am" ] && M_argv_match=$_am
  fi
  case $M_stop_scope in pidfile) ;; *) M_stop_scope=marker ;; esac
  valid_int "$M_start_timeout" 1 600 || M_start_timeout=8
  valid_int "$M_stop_grace" 0 120 || M_stop_grace=5
  [ -n "$M_health" ] || M_health=proc
  case $M_boot in xbit) ;; *) M_boot=wrapper ;; esac
  case $M_removable in 0) ;; *) M_removable=1 ;; esac
  # argv_match is only ever a plain path-like token (also used as a grep prefilter)
  case $M_argv_match in *[!A-Za-z0-9._/:@=+,-]*) M_argv_match= ;; esac
  return 0
}

# meta_abs <id> <value>: prints an absolute path; relative values must stay
# inside the daemon's own dir. 1 on rejection.
meta_abs() {
  case $2 in
    '') return 1 ;;
    /*) printf '%s' "$2" ;;
    *..*|*'\'*) return 1 ;;
    *) printf '%s' "$R/daemons/$1/$2" ;;
  esac
}

# meta_write <id> <k=v lines on stdin>: whitelist keys only, atomic.
meta_write() {
  _d=$R/daemons/$1
  mkdir -p "$_d" || return 1
  _tmp=$_d/meta.tmp.$$
  : >"$_tmp"
  while IFS='=' read -r _k _v || [ -n "$_k" ]; do
    case " $KM_META_KEYS " in *" $_k "*) ;; *) continue ;; esac
    case $_v in *"$NL"*) continue ;; esac
    printf '%s=%s\n' "$_k" "$_v" >>"$_tmp"
  done
  mv "$_tmp" "$_d/meta"
}

# record_last <id> <action> <ok 0|1> <code>
record_last() {
  [ -d "$R/daemons/$1" ] || return 0
  printf '%s %s %s %s\n' "$(epoch)" "$2" "$3" "${4:--}" >"$R/daemons/$1/last" 2>/dev/null
  return 0
}

# ---- boot entry (enable/disable) -------------------------------------------
# boot_file <id>: prints the file whose x-bit is "enabled".
boot_file() {
  if [ "$M_boot" = xbit ]; then
    if [ -n "$M_boot_script" ]; then printf '%s' "$M_boot_script"; else printf '%s' "$M_start"; fi
  else
    printf '%s' "$KM_SERVICE_D/km-$1.sh"
  fi
}
is_enabled() { [ -f "$1" ] && [ ! -L "$1" ] && [ -x "$1" ]; }

# wrapper_write <id> <boot_wait 0|1>: creates the km wrapper (mode 644) unless present.
wrapper_write() {
  _w=$KM_SERVICE_D/km-$1.sh
  [ -f "$_w" ] && return 0
  mkdir -p "$KM_SERVICE_D" || return 1
  _t=$_w.new.$$
  {
    printf '#!/system/bin/sh\n# km-managed:%s\n' "$1"
    [ "$KM_ADB" = /data/adb ] || printf 'KM_ADB=%s; export KM_ADB\n' "$KM_ADB"
    [ -z "$DM_ROOT" ] || printf 'DM_ROOT=%s; export DM_ROOT\n' "$DM_ROOT"
    [ -z "$KM_MODULE_DIR" ] || printf 'KM_MODULE_DIR=%s; export KM_MODULE_DIR\n' "$KM_MODULE_DIR"
    printf 'DM=%s/bin/dm\n' "$KM_MODDIR"
    printf '[ -x "$DM" ] || exit 0\n'
    if [ "$2" = 1 ]; then
      printf 'i=0\nwhile [ "$(getprop sys.boot_completed)" != "1" ] && [ "$i" -lt 60 ]; do\n  sleep 5\n  i=$((i + 1))\ndone\n'
    fi
    printf 'exec "$DM" boot %s\n' "$1"
  } >"$_t" && chmod 644 "$_t" && mv "$_t" "$_w"
}
# wrapper_owned <id>: true if km-<id>.sh carries the managed marker on line 2.
wrapper_owned() {
  _w=$KM_SERVICE_D/km-$1.sh
  [ -f "$_w" ] && [ ! -L "$_w" ] || return 1
  _l2=$(sed -n 2p "$_w" 2>/dev/null)
  [ "$_l2" = "# km-managed:$1" ]
}

# builtin ids are the legacy.d/*.meta names
is_builtin_id() {
  [ -f "$KM_MODDIR/legacy.d/$1.meta" ]
}

# slug <text>: lowercase id candidate (may still be invalid)
slugify() {
  _s=$(printf '%s' "$1" | LC_ALL=C tr 'A-Z' 'a-z' | LC_ALL=C tr -c 'a-z0-9' '-' | LC_ALL=C sed -e 's/--*/-/g' -e 's/^-//' -e 's/-$//')
  _s=$(printf '%s' "$_s" | cut -c1-31 | sed -e 's/-$//')
  SLUG=$_s
}
