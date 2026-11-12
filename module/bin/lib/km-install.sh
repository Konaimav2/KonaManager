# km-install.sh - install stage/commit/abort, job, create, import, delete.
#
# Install is synchronous: `install stage` downloads (or copies), validates and
# extracts into R/staging/<token>/x and returns the preview immediately.
# Nothing from a package runs before `install commit <token> --confirm <id>`.

INST_MAX_ZIP=5242880
INST_MAX_ENTRIES=200
INST_MAX_UNPACKED=20971520
INST_HOOK_TIMEOUT=30

inst_need_tools() {
  KM_UNZIP=$(find_tool unzip) || { err E_NO_TOOL "unzip not found (install busybox)"; return 1; }
  KM_SHA=$(find_tool sha256sum) || { err E_NO_TOOL "sha256sum not found (install busybox)"; return 1; }
  KM_OD=$(find_tool od) || { err E_NO_TOOL "od not found (install busybox)"; return 1; }
  KM_AWK=$(find_tool awk) || { err E_NO_TOOL "awk not found (install busybox)"; return 1; }
  find_tool base64 >/dev/null || { err E_NO_TOOL "base64 not found (install busybox)"; return 1; }
  return 0
}

sha_of() { # file -> hex on stdout
  $KM_SHA "$1" 2>/dev/null | { read -r _h _; printf '%s' "$_h"; }
}

rand_hex8() {
  _r=$($KM_OD -An -N4 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')
  case $_r in ????????) ;; *) _r=$(printf '%08x' $(( ($(epoch) * 7919 + $$) % 4294967295 ))) ;; esac
  printf '%s' "$_r"
}

# valid_relpath <p>: relative, safe chars, no .. segment
valid_relpath() {
  case $1 in ''|/*|*[!A-Za-z0-9._/-]*|*//*) return 1 ;; esac
  case "/$1/" in *"/../"*|*"/./"*) return 1 ;; esac
  [ "${#1}" -le 128 ]
}

# ---- zip inspection: central directory parsed from raw bytes -----------------
# Independent of the unzip implementation: names, sizes, entry type (symlink,
# device...) and encryption are read from the central directory with od + awk.
# Sets ZI_N ZI_BYTES ZI_NAMES; on failure ZI_CODE/ZI_MSG and return 1.
zip_inspect() {
  _zf=$1
  ZI_N=0 ZI_BYTES=0 ZI_NAMES=
  _sz=$(wc -c <"$_zf" 2>/dev/null)
  _sz=$((_sz + 0))
  if [ "$_sz" -gt "$INST_MAX_ZIP" ]; then ZI_CODE=E_VERIFY ZI_MSG="package is larger than 5 MiB"; return 1; fi
  if [ "$_sz" -lt 22 ]; then ZI_CODE=E_VERIFY ZI_MSG="not a zip file"; return 1; fi
  _eo=$(tail -c 66000 "$_zf" | $KM_OD -An -v -tu1 | $KM_AWK '
    { for (i = 1; i <= NF; i++) b[n++] = $i + 0 }
    END {
      for (p = n - 22; p >= 0; p--) {
        if (b[p] == 80 && b[p+1] == 75 && b[p+2] == 5 && b[p+3] == 6) {
          nent = b[p+10] + 256 * b[p+11]
          cdsz = b[p+12] + 256 * b[p+13] + 65536 * b[p+14] + 16777216 * b[p+15]
          cdoff = b[p+16] + 256 * b[p+17] + 65536 * b[p+18] + 16777216 * b[p+19]
          printf "%.0f %.0f %d\n", cdoff, cdsz, nent
          exit 0
        }
      }
      exit 1
    }') || { ZI_CODE=E_VERIFY ZI_MSG="not a zip file (no end-of-central-directory)"; return 1; }
  set -- $_eo
  _cdoff=$1 _cdsz=$2 _nent=$3
  if [ "$_cdoff" = 4294967295 ] || [ "$_nent" = 65535 ] || [ "$_cdsz" = 4294967295 ]; then
    ZI_CODE=E_VERIFY ZI_MSG="zip64 archives are not supported"; return 1
  fi
  if [ "$_nent" -gt "$INST_MAX_ENTRIES" ]; then
    ZI_CODE=E_VERIFY ZI_MSG="too many entries ($_nent > $INST_MAX_ENTRIES)"; return 1
  fi
  if [ "$_nent" -lt 1 ] || [ "$_cdsz" -gt 262144 ] || [ $((_cdoff + _cdsz)) -gt "$_sz" ]; then
    ZI_CODE=E_VERIFY ZI_MSG="corrupt central directory"; return 1
  fi
  _list=$(tail -c +$((_cdoff + 1)) "$_zf" | head -c "$_cdsz" | $KM_OD -An -v -tu1 | $KM_AWK '
    { for (i = 1; i <= NF; i++) b[n++] = $i + 0 }
    END {
      p = 0; cnt = 0
      while (p + 46 <= n) {
        if (!(b[p] == 80 && b[p+1] == 75 && b[p+2] == 1 && b[p+3] == 2)) { print "BAD"; exit 0 }
        host = b[p+5]; flags = b[p+8] + 256 * b[p+9]
        usz = b[p+24] + 256 * b[p+25] + 65536 * b[p+26] + 16777216 * b[p+27]
        nl = b[p+28] + 256 * b[p+29]; el = b[p+30] + 256 * b[p+31]; cl = b[p+32] + 256 * b[p+33]
        eahi = b[p+40] + 256 * b[p+41]
        typ = 0; if (host == 3) typ = int(eahi / 4096)
        enc = flags % 2
        name = ""
        for (k = 0; k < nl; k++) { c = b[p+46+k]; if (c >= 32 && c <= 126) name = name sprintf("%c", c); else name = name "?" }
        printf "E\t%.0f\t%d\t%d\t%s\n", usz, typ, enc, name
        cnt++
        p = p + 46 + nl + el + cl
      }
      printf "N\t%d\n", cnt
    }') || { ZI_CODE=E_VERIFY ZI_MSG="cannot read central directory"; return 1; }
  _cnt=0
  _tot=0
  _oifs=$IFS
  IFS=$NL
  set -f
  for _ln in $_list; do
    IFS=$TAB
    set -- $_ln
    IFS=$NL
    case $1 in
      BAD) IFS=$_oifs; set +f; ZI_CODE=E_VERIFY ZI_MSG="corrupt central directory"; return 1 ;;
      N) _cnt=$2 ;;
      E)
        _usz=$2 _typ=$3 _enc=$4 _name=$5
        if [ "$_enc" != 0 ]; then IFS=$_oifs; set +f; ZI_CODE=E_VERIFY ZI_MSG="encrypted entries are not allowed"; return 1; fi
        case $_typ in 0|4|8) ;; *) IFS=$_oifs; set +f; ZI_CODE=E_PATH ZI_MSG="entry is a symlink or special file: $_name"; return 1 ;; esac
        case $_name in
          ''|/*) IFS=$_oifs; set +f; ZI_CODE=E_PATH ZI_MSG="absolute or empty entry name"; return 1 ;;
          *[!A-Za-z0-9._/-]*) IFS=$_oifs; set +f; ZI_CODE=E_PATH ZI_MSG="unsafe character in entry name: $_name"; return 1 ;;
        esac
        case "/$_name" in
          *"/../"*|*"/..") IFS=$_oifs; set +f; ZI_CODE=E_PATH ZI_MSG="'..' in entry name: $_name"; return 1 ;;
          *"//"*) IFS=$_oifs; set +f; ZI_CODE=E_PATH ZI_MSG="empty path segment: $_name"; return 1 ;;
        esac
        _tot=$((_tot + _usz))
        ZI_NAMES="$ZI_NAMES$_name$NL"
        ;;
    esac
  done
  IFS=$_oifs
  set +f
  if [ "$_cnt" != "$_nent" ]; then ZI_CODE=E_VERIFY ZI_MSG="entry count mismatch"; return 1; fi
  if [ "$_tot" -gt "$INST_MAX_UNPACKED" ]; then ZI_CODE=E_VERIFY ZI_MSG="unpacked size too large"; return 1; fi
  ZI_N=$_cnt
  ZI_BYTES=$_tot
  return 0
}

# ---- manifest ----------------------------------------------------------------
# inst_manifest <dir>: parses <dir>/daemon.meta into PM_*; on failure sets ZI_CODE/ZI_MSG.
inst_manifest() {
  _d=$1
  PM_id= PM_name= PM_desc= PM_version= PM_kind=daemon PM_start= PM_stop= PM_pidfile=
  PM_argv_match= PM_stop_scope=marker PM_start_timeout=8 PM_stop_grace=5 PM_health=proc
  PM_boot_wait=1 PM_min_dm= PM_inst_sha= PM_uninst_sha= PM_schema= PM_warn=
  _mf=$_d/daemon.meta
  if [ ! -f "$_mf" ] || [ -L "$_mf" ]; then ZI_CODE=E_VERIFY ZI_MSG="daemon.meta is missing"; return 1; fi
  _n=0
  while IFS='=' read -r _k _v || [ -n "$_k" ]; do
    _n=$((_n + 1))
    [ "$_n" -le 100 ] || break
    case $_k in ''|'#'*) continue ;; esac
    _v=$(printf '%s' "$_v" | tr -d '\r')
    case $_k in
      schema) PM_schema=$_v ;;
      id) PM_id=$_v ;;
      name) PM_name=$_v ;;
      desc) PM_desc=$_v ;;
      version) PM_version=$_v ;;
      kind) PM_kind=$_v ;;
      start) PM_start=$_v ;;
      stop) PM_stop=$_v ;;
      pidfile) PM_pidfile=$_v ;;
      argv_match) PM_argv_match=$_v ;;
      stop_scope) PM_stop_scope=$_v ;;
      start_timeout) PM_start_timeout=$_v ;;
      stop_grace) PM_stop_grace=$_v ;;
      health) PM_health=$_v ;;
      boot_wait) PM_boot_wait=$_v ;;
      min_dm) PM_min_dm=$_v ;;
      hooks.install.sha256) PM_inst_sha=$_v ;;
      hooks.uninstall.sha256) PM_uninst_sha=$_v ;;
      *) PM_warn="$PM_warn$NL""unknown manifest key ignored: $_k" ;;
    esac
  done <"$_mf"
  _bad() { ZI_CODE=E_VERIFY ZI_MSG="manifest: $1"; return 1; }
  [ "$PM_schema" = 1 ] || { _bad "schema must be 1"; return 1; }
  valid_id "$PM_id" || { _bad "invalid id (^[a-z0-9][a-z0-9-]{1,30}\$)"; return 1; }
  [ -n "$PM_name" ] && valid_line "$PM_name" 64 || { _bad "name is required (max 64, printable)"; return 1; }
  valid_line "$PM_desc" 200 || { _bad "desc too long or not printable"; return 1; }
  case $PM_version in *[!A-Za-z0-9._+-]*) _bad "invalid version"; return 1 ;; esac
  [ "${#PM_version}" -le 32 ] || { _bad "version too long"; return 1; }
  case $PM_kind in daemon|oneshot) ;; *) _bad "kind must be daemon or oneshot"; return 1 ;; esac
  valid_relpath "$PM_start" || { _bad "start must be a safe relative path"; return 1; }
  [ -f "$_d/$PM_start" ] && [ ! -L "$_d/$PM_start" ] || { _bad "start file not in package: $PM_start"; return 1; }
  if [ -n "$PM_stop" ]; then
    valid_relpath "$PM_stop" || { _bad "stop must be a safe relative path"; return 1; }
    [ -f "$_d/$PM_stop" ] && [ ! -L "$_d/$PM_stop" ] || { _bad "stop file not in package: $PM_stop"; return 1; }
  fi
  if [ -n "$PM_pidfile" ]; then
    case $PM_pidfile in
      /*) case $PM_pidfile in *[!A-Za-z0-9._/-]*|*..*) _bad "invalid pidfile"; return 1 ;; esac ;;
      *) valid_relpath "$PM_pidfile" || { _bad "invalid pidfile"; return 1; } ;;
    esac
  fi
  case $PM_argv_match in *[!A-Za-z0-9._/:@=+,-]*) _bad "invalid argv_match"; return 1 ;; esac
  case $PM_stop_scope in marker|pidfile) ;; *) _bad "stop_scope must be marker or pidfile"; return 1 ;; esac
  valid_int "$PM_start_timeout" 1 120 || { _bad "start_timeout must be 1..120"; return 1; }
  valid_int "$PM_stop_grace" 0 60 || { _bad "stop_grace must be 0..60"; return 1; }
  case $PM_health in
    proc) ;;
    port:*) valid_int "${PM_health#port:}" 1 65535 || { _bad "invalid health port"; return 1; } ;;
    cmd:*) valid_relpath "${PM_health#cmd:}" && [ -f "$_d/${PM_health#cmd:}" ] || { _bad "health command not in package"; return 1; } ;;
    *) _bad "health must be proc, port:<n> or cmd:<relative path>"; return 1 ;;
  esac
  case $PM_boot_wait in 0|1) ;; *) _bad "boot_wait must be 0 or 1"; return 1 ;; esac
  if [ -n "$PM_min_dm" ]; then
    case $PM_min_dm in *[!0-9.]*|''|.*|*.) _bad "invalid min_dm"; return 1 ;; esac
    if ver_gt "$PM_min_dm" "$KM_VERSION"; then _bad "needs dm >= $PM_min_dm (this is $KM_VERSION)"; return 1; fi
  fi
  # hooks: hash pinned in the manifest must match the file; unpinned hooks are allowed with a warning
  HK_INST= HK_UNINST=
  for _h in install uninstall; do
    _hf=$_d/hooks/$_h.sh
    if [ "$_h" = install ]; then _pin=$PM_inst_sha; else _pin=$PM_uninst_sha; fi
    if [ -n "$_pin" ] && ! valid_sha "$_pin"; then _bad "hooks.$_h.sha256 is not a sha256"; return 1; fi
    _pin=$(printf '%s' "$_pin" | LC_ALL=C tr 'A-F' 'a-f')
    if [ -e "$_hf" ] || [ -L "$_hf" ]; then
      [ -f "$_hf" ] && [ ! -L "$_hf" ] || { ZI_CODE=E_PATH ZI_MSG="hooks/$_h.sh is not a regular file"; return 1; }
      _hs=$(sha_of "$_hf")
      if [ -n "$_pin" ] && [ "$_pin" != "$_hs" ]; then
        ZI_CODE=E_VERIFY ZI_MSG="hook hash mismatch: hooks/$_h.sh"; return 1
      fi
      [ -n "$_pin" ] || PM_warn="$PM_warn${NL}hooks/$_h.sh is not pinned by a sha256 in the manifest"
      if [ "$_h" = install ]; then HK_INST=$_hs; else HK_UNINST=$_hs; fi
    elif [ -n "$_pin" ]; then
      ZI_CODE=E_VERIFY ZI_MSG="manifest pins hooks/$_h.sh but the file is missing"; return 1
    fi
  done
  return 0
}

# ver_gt a b: dotted numeric a > b
ver_gt() {
  _a=$1 _b=$2
  _i=0
  while [ "$_i" -lt 4 ]; do
    _x=${_a%%.*}; _y=${_b%%.*}
    [ "$_x" = "$_a" ] && _a= || _a=${_a#*.}
    [ "$_y" = "$_b" ] && _b= || _b=${_b#*.}
    norm_int "${_x:-0}"; _x=$NI
    norm_int "${_y:-0}"; _y=$NI
    [ "$_x" -gt "$_y" ] && return 0
    [ "$_x" -lt "$_y" ] && return 1
    _i=$((_i + 1))
  done
  return 1
}

inst_conflict() { # id -> CONFLICT none|exists|builtin
  CONFLICT=none
  if is_builtin_id "$1" || { [ -f "$R/daemons/$1/meta" ] && grep -qx 'source=builtin' "$R/daemons/$1/meta" 2>/dev/null; }; then
    CONFLICT=builtin
  elif [ -e "$R/daemons/$1" ] || [ -e "$KM_SERVICE_D/km-$1.sh" ]; then
    CONFLICT=exists
  fi
}

# hook_json <file> -> HJ (object or null)
hook_json() {
  HJ=null
  [ -f "$1" ] || return 0
  _hb=$(wc -c <"$1")
  _hb=$((_hb + 0))
  _pv=$(head -n 40 "$1" | cut -c1-200)
  jlist_strs "$_pv"
  HJ="{\"sha256\":\"$(sha_of "$1")\",\"bytes\":$_hb,\"preview\":$JL}"
}

stage_cleanup() { safe_rmtree "$R/staging/$1" "$R/staging"; }

stage_gc() {
  mkdir -p "$R/staging" "$R/jobs"
  for _s in $(find "$R/staging" -mindepth 1 -maxdepth 1 -name 't_*' -mmin +60 2>/dev/null); do
    safe_rmtree "$_s" "$R/staging"
  done
  for _j in $(find "$R/jobs" -mindepth 1 -maxdepth 1 -name 'j_*.json' -mmin +60 2>/dev/null); do
    rm -f "$_j"
  done
}

inst_download() { # url out sha(optional)
  _curl=$(find_tool curl)
  if [ -n "$_curl" ]; then
    _extra=
    [ "$KM_TEST" = 1 ] && _extra=$KM_CURL_EXTRA
    $_curl -fsS -L --proto '=https' --proto-redir '=https' --max-redirs 5 --max-filesize "$INST_MAX_ZIP" \
      --connect-timeout 15 --max-time 90 $_extra -o "$2" "$1" >/dev/null 2>&1
    _rc=$?
    case $_rc in
      0) return 0 ;;
      63) ZI_CODE=E_VERIFY ZI_MSG="download is larger than 5 MiB"; return 1 ;;
      *) ZI_CODE=E_DOWNLOAD ZI_MSG="download failed (curl exit $_rc); redirects to http are refused"; return 1 ;;
    esac
  fi
  _wget=$(find_tool wget)
  if [ -n "$_wget" ]; then
    if [ -z "$3" ]; then
      ZI_CODE=E_NO_TOOL ZI_MSG="curl not found; wget cannot refuse http redirects, so a pinned sha256 is required"; return 1
    fi
    $_wget -q -T 60 -O "$2" "$1" >/dev/null 2>&1 || { ZI_CODE=E_DOWNLOAD ZI_MSG="download failed (wget)"; return 1; }
    return 0
  fi
  ZI_CODE=E_NO_TOOL ZI_MSG="neither curl nor wget found"
  return 1
}

# ---- install stage -------------------------------------------------------------
inst_stage() {
  _src=$1
  _pin=$2
  [ -n "$_src" ] || { err E_ARG "usage: install stage <https-url|/abs/path.zip> [sha256]"; return 1; }
  if [ -n "$_pin" ]; then
    valid_sha "$_pin" || { err E_ARG "sha256 must be 64 hex characters"; return 1; }
    _pin=$(printf '%s' "$_pin" | LC_ALL=C tr 'A-F' 'a-f')
  fi
  _isurl=0
  case $_src in
    https://*)
      case $_src in *[!A-Za-z0-9._~:/?#@!\$\&\(\)*+,\;=%-]*) err E_ARG "url has unsafe characters"; return 1 ;; esac
      [ "${#_src}" -le 2048 ] || { err E_ARG "url too long"; return 1; }
      _isurl=1 ;;
    http://*) err E_ARG "only https URLs are accepted"; return 1 ;;
    /*.zip)
      case $_src in *[!A-Za-z0-9._/-]*|*..*) err E_ARG "path has unsafe characters"; return 1 ;; esac ;;
    *) err E_ARG "source must be an https URL or an absolute path ending in .zip"; return 1 ;;
  esac
  inst_need_tools || return 1
  if [ "$_isurl" = 0 ]; then
    [ -f "$_src" ] && [ ! -L "$_src" ] || { err E_ARG "local zip not found or not a regular file"; return 1; }
  fi
  lock_take install-stage || { err E_BUSY "another install is being staged"; return 1; }
  umask 077
  stage_gc
  _tok=
  _try=0
  while [ "$_try" -lt 5 ]; do
    _tok=t_$(rand_hex8)
    [ -e "$R/staging/$_tok" ] || break
    _try=$((_try + 1))
  done
  _sd=$R/staging/$_tok
  mkdir -p "$_sd/x" || { lock_drop; err E_PATH "cannot create staging dir"; return 1; }
  ZI_CODE= ZI_MSG=
  _zip=$_sd/pkg.zip
  if [ "$_isurl" = 1 ]; then
    inst_download "$_src" "$_zip" "$_pin" || { stage_cleanup "$_tok"; lock_drop; err "$ZI_CODE" "$ZI_MSG"; return 1; }
  else
    _lsz=$(wc -c <"$_src" 2>/dev/null)
    if [ "$((_lsz + 0))" -gt "$INST_MAX_ZIP" ]; then
      stage_cleanup "$_tok"; lock_drop; err E_VERIFY "package is larger than 5 MiB"; return 1
    fi
    cp "$_src" "$_zip" || { stage_cleanup "$_tok"; lock_drop; err E_PATH "cannot read local zip"; return 1; }
  fi
  _zsha=$(sha_of "$_zip")
  if [ -n "$_pin" ] && [ "$_pin" != "$_zsha" ]; then
    stage_cleanup "$_tok"; lock_drop; err E_VERIFY "sha256 mismatch (got $_zsha)"; return 1
  fi
  zip_inspect "$_zip" || { stage_cleanup "$_tok"; lock_drop; err "$ZI_CODE" "$ZI_MSG"; return 1; }
  _nfiles=$ZI_N
  _nbytes=$ZI_BYTES
  $KM_UNZIP -o -q "$_zip" -d "$_sd/x" >/dev/null 2>&1 || { stage_cleanup "$_tok"; lock_drop; err E_VERIFY "unzip failed"; return 1; }
  # post-extract checks: only regular files and dirs, nothing outside x/
  _odd=$(find "$_sd/x" ! -type f ! -type d 2>/dev/null | head -n 1)
  if [ -n "$_odd" ]; then stage_cleanup "$_tok"; lock_drop; err E_PATH "extracted a non-regular file"; return 1; fi
  _stray=$(find "$_sd" -mindepth 1 -maxdepth 1 ! -name x ! -name pkg.zip 2>/dev/null | head -n 1)
  if [ -n "$_stray" ]; then stage_cleanup "$_tok"; lock_drop; err E_PATH "package wrote outside the staging directory"; return 1; fi
  inst_manifest "$_sd/x" || { stage_cleanup "$_tok"; lock_drop; err "$ZI_CODE" "$ZI_MSG"; return 1; }
  inst_conflict "$PM_id"
  printf 'id=%s\nversion=%s\nsha256=%s\nfiles=%s\nbytes=%s\n' "$PM_id" "$PM_version" "$_zsha" "$_nfiles" "$_nbytes" >"$_sd/info"
  hook_json "$_sd/x/hooks/install.sh"; _hi=$HJ
  hook_json "$_sd/x/hooks/uninstall.sh"; _hu=$HJ
  _warn=$(printf '%s' "$PM_warn" | sed '/^$/d')
  [ "$CONFLICT" = none ] || _warn="${_warn:+$_warn$NL}id already in use ($CONFLICT)"
  jlist_strs "$_warn"; _wj=$JL
  jesc "$PM_name"; _n=$JESC
  jesc "$PM_desc"; _de=$JESC
  jesc "$PM_version"; _v=$JESC
  jesc "$PM_start"; _st=$JESC
  jesc "$PM_stop"; _sp=$JESC
  _res="{\"token\":\"$_tok\",\"manifest\":{\"id\":\"$PM_id\",\"name\":\"$_n\",\"version\":\"$_v\",\"kind\":\"$PM_kind\",\"desc\":\"$_de\",\"start\":\"$_st\",\"stop\":\"$_sp\"},\"hooks\":{\"install\":$_hi,\"uninstall\":$_hu},\"files\":$_nfiles,\"bytes\":$_nbytes,\"sha256\":\"$_zsha\",\"conflict\":\"$CONFLICT\",\"warnings\":$_wj}"
  _job=j_$(rand_hex8)
  printf '{"ok":true,"job":"%s","state":"done","step":"validate","pct":100,"result":%s}\n' "$_job" "$_res" >"$R/jobs/$_job.json"
  lock_drop
  km_log "install stage $_tok id=$PM_id"
  ok_out ",\"job\":\"$_job\",\"state\":\"done\",\"step\":\"validate\",\"pct\":100,\"result\":$_res"
}

cmd_job() {
  case $1 in j_????????) ;; *) err E_ARG "invalid job id"; return 1 ;; esac
  case ${1#j_} in *[!a-f0-9]*) err E_ARG "invalid job id"; return 1 ;; esac
  [ -f "$R/jobs/$1.json" ] || { err E_UNKNOWN "unknown job"; return 1; }
  OUT=$(cat "$R/jobs/$1.json")
  return 0
}

inst_abort() {
  valid_token "$1" || { err E_ARG "invalid token"; return 1; }
  stage_cleanup "$1"
  ok_out ""
}

# run_hook <dir> <script-rel> <id> -> HOOK_EXIT
run_hook() {
  _hd=$1
  (
    cd "$_hd" || exit 126
    KM_DAEMON_ID=$3
    KM_DAEMON_DIR=$_hd
    KM_ROOT=$R
    export KM_DAEMON_ID KM_DAEMON_DIR KM_ROOT
    if [ -n "$KM_TIMEOUT" ]; then $KM_TIMEOUT "$INST_HOOK_TIMEOUT" "$KM_SH" "$2"; else "$KM_SH" "$2"; fi
  ) </dev/null >>"$_hd/hook.log" 2>&1
  HOOK_EXIT=$?
}

inst_commit() {
  _tok=$1
  valid_token "$_tok" || { err E_ARG "invalid token"; return 1; }
  [ "$2" = "--confirm" ] && [ -n "$3" ] || { err E_CONFIRM "usage: install commit <token> --confirm <id>"; return 1; }
  _cid=$3
  _sd=$R/staging/$_tok
  [ -d "$_sd/x" ] && [ -f "$_sd/info" ] || { err E_UNKNOWN "unknown or expired token"; return 1; }
  inst_need_tools || return 1
  ZI_CODE= ZI_MSG=
  # revalidate the staged tree; do not trust anything cached
  inst_manifest "$_sd/x" || { err "$ZI_CODE" "$ZI_MSG"; return 1; }
  _odd=$(find "$_sd/x" ! -type f ! -type d 2>/dev/null | head -n 1)
  [ -z "$_odd" ] || { err E_PATH "staged tree contains a non-regular file"; return 1; }
  _zsha=$(grep '^sha256=' "$_sd/info" | head -n 1 | cut -d= -f2)
  [ "$(sha_of "$_sd/pkg.zip")" = "$_zsha" ] || { err E_VERIFY "staged package changed on disk"; return 1; }
  [ "$_cid" = "$PM_id" ] || { err E_CONFIRM "confirmation does not match the package id"; return 1; }
  lock_take "$PM_id" || { err E_BUSY "another action holds the lock for $PM_id"; return 1; }
  inst_conflict "$PM_id"
  if [ "$CONFLICT" != none ]; then lock_drop; err E_CONFLICT "a daemon with id $PM_id already exists ($CONFLICT)"; return 1; fi
  _id=$PM_id
  _dest=$R/daemons/$_id
  umask 077
  mkdir -p "$R/daemons"
  mv "$_sd/x" "$_dest" || { lock_drop; err E_PATH "cannot move package into place"; return 1; }
  {
    printf 'id=%s\nname=%s\ndesc=%s\nversion=%s\nkind=%s\nsource=package\n' "$_id" "$PM_name" "$PM_desc" "$PM_version" "$PM_kind"
    printf 'start=%s\n' "$PM_start"
    [ -n "$PM_stop" ] && printf 'stop=%s\n' "$PM_stop"
    [ -n "$PM_pidfile" ] && printf 'pidfile=%s\n' "$PM_pidfile"
    [ -n "$PM_argv_match" ] && printf 'argv_match=%s\n' "$PM_argv_match"
    printf 'stop_scope=%s\nstart_timeout=%s\nstop_grace=%s\nhealth=%s\n' "$PM_stop_scope" "$PM_start_timeout" "$PM_stop_grace" "$PM_health"
    printf 'boot=wrapper\nboot_wait=%s\nremovable=1\n' "$PM_boot_wait"
    [ -n "$HK_INST" ] && printf 'install_sha=%s\n' "$HK_INST"
    [ -n "$HK_UNINST" ] && printf 'uninstall_sha=%s\n' "$HK_UNINST"
  } | meta_write "$_id"
  _ran=false
  _hex=null
  if [ -f "$_dest/hooks/install.sh" ]; then
    run_hook "$_dest" hooks/install.sh "$_id"
    _ran=true
    _hex=$HOOK_EXIT
    if [ "$HOOK_EXIT" != 0 ]; then
      safe_rmtree "$_dest" "$R/daemons"
      wrapper_owned "$_id" && rm -f "$KM_SERVICE_D/km-$_id.sh"
      stage_cleanup "$_tok"
      lock_drop
      km_log "install commit $_id hook failed exit=$HOOK_EXIT"
      err E_HOOK "the install hook exited with $HOOK_EXIT; nothing was installed" ",\"hook\":{\"ran\":true,\"exit\":$HOOK_EXIT}"
      return 1
    fi
  fi
  wrapper_write "$_id" "$PM_boot_wait" || true
  [ -f "$KM_SERVICE_D/km-$_id.sh" ] && chmod 644 "$KM_SERVICE_D/km-$_id.sh" 2>/dev/null
  stage_cleanup "$_tok"
  lock_drop
  km_log "install commit $_id v$PM_version"
  jesc "$PM_version"
  ok_out ",\"id\":\"$_id\",\"version\":\"$JESC\",\"dir\":\"$_dest\",\"hook\":{\"ran\":$_ran,\"exit\":$_hex},\"enabled\":false"
}

cmd_install() {
  _sub=$1
  [ $# -gt 0 ] && shift
  case $_sub in
    stage) inst_stage "$@" ;;
    commit) inst_commit "$@" ;;
    abort) inst_abort "$@" ;;
    *) err E_USAGE "usage: install stage|commit|abort" ;;
  esac
}

# ---- create / import --------------------------------------------------------------
# kv_get <file> <key> -> KV (last wins)
kv_get() {
  KV=
  while IFS='=' read -r _k _v || [ -n "$_k" ]; do
    [ "$_k" = "$2" ] && KV=$_v
  done <"$1"
}

# kv_check <file> <allowed keys...>: every line must be key=value with an allowed key
kv_check() {
  _f=$1
  shift
  while IFS= read -r _l || [ -n "$_l" ]; do
    [ -n "$_l" ] || continue
    case $_l in *=*) ;; *) return 1 ;; esac
    _k=${_l%%=*}
    _ok=0
    for _a in "$@"; do [ "$_k" = "$_a" ] && _ok=1; done
    [ "$_ok" = 1 ] || return 1
  done <"$_f"
  return 0
}

cmd_create() {
  [ -n "$1" ] || { err E_ARG "usage: create <base64 key=value lines>"; return 1; }
  _t=$R/.create.$$
  mkdir -p "$R"
  b64_decode_to "$1" "$_t"
  case $? in
    0) ;;
    2) rm -f "$_t"; err E_NO_TOOL "base64 not found"; return 1 ;;
    *) rm -f "$_t"; err E_ARG "invalid base64 payload"; return 1 ;;
  esac
  [ "$(wc -c <"$_t")" -le 4096 ] || { rm -f "$_t"; err E_ARG "payload too large"; return 1; }
  kv_check "$_t" name kind start stop || { rm -f "$_t"; err E_ARG "payload must be key=value lines with keys name, kind, start, stop"; return 1; }
  kv_get "$_t" name; _name=$KV
  kv_get "$_t" kind; _kind=${KV:-daemon}
  kv_get "$_t" start; _start=$KV
  kv_get "$_t" stop; _stop=$KV
  rm -f "$_t"
  [ -n "$_name" ] && valid_line "$_name" 64 || { err E_ARG "name is required (max 64, printable, one line)"; return 1; }
  case $_kind in daemon|oneshot) ;; *) err E_ARG "kind must be daemon or oneshot"; return 1 ;; esac
  [ -n "$_start" ] && valid_line "$_start" 1024 || { err E_ARG "start command is required (one line, max 1024)"; return 1; }
  valid_line "$_stop" 1024 || { err E_ARG "stop command must be one line, max 1024"; return 1; }
  slugify "$_name"
  valid_id "$SLUG" || { err E_ARG "name does not produce a valid id (needs 2+ letters or digits)"; return 1; }
  _id=$SLUG
  lock_take "$_id" || { err E_BUSY "another action holds the lock for $_id"; return 1; }
  inst_conflict "$_id"
  if [ "$CONFLICT" != none ]; then lock_drop; err E_CONFLICT "id $_id is already in use ($CONFLICT)"; return 1; fi
  _dir=$R/daemons/$_id
  umask 077
  mkdir -p "$_dir" || { lock_drop; err E_PATH "cannot create daemon dir"; return 1; }
  printf '#!/system/bin/sh\n# km-created:%s\n%s\n' "$_id" "$_start" >"$_dir/start.sh"
  if ! "$KM_SH" -n "$_dir/start.sh" 2>/dev/null; then
    safe_rmtree "$_dir" "$R/daemons"; lock_drop; err E_ARG "start command has a shell syntax error"; return 1
  fi
  _stopm=
  if [ -n "$_stop" ]; then
    printf '#!/system/bin/sh\n# km-created:%s\n%s\n' "$_id" "$_stop" >"$_dir/stop.sh"
    if ! "$KM_SH" -n "$_dir/stop.sh" 2>/dev/null; then
      safe_rmtree "$_dir" "$R/daemons"; lock_drop; err E_ARG "stop command has a shell syntax error"; return 1
    fi
    _stopm=stop.sh
  fi
  {
    printf 'id=%s\nname=%s\nkind=%s\nsource=created\nstart=start.sh\n' "$_id" "$_name" "$_kind"
    [ -n "$_stopm" ] && printf 'stop=%s\n' "$_stopm"
    printf 'stop_scope=marker\nstart_timeout=8\nstop_grace=5\nhealth=proc\nboot=wrapper\nboot_wait=1\nremovable=1\n'
  } | meta_write "$_id"
  wrapper_write "$_id" 1 || true
  [ -f "$KM_SERVICE_D/km-$_id.sh" ] && chmod 644 "$KM_SERVICE_D/km-$_id.sh" 2>/dev/null
  lock_drop
  km_log "create $_id"
  ok_out ",\"id\":\"$_id\",\"dir\":\"$_dir\",\"enabled\":false"
}

# is_managed_path <path>: some daemon already uses it as start/boot script
is_managed_path() {
  [ -d "$R/daemons" ] || return 1
  grep -lxE -e "start=$1" -e "boot_script=$1" "$R"/daemons/*/meta >/dev/null 2>&1
}

import_list() {
  _items=
  for _f in "$KM_SERVICE_D"/*.sh; do
    [ -f "$_f" ] || continue
    [ -L "$_f" ] && continue
    _n=${_f##*/}
    case $_n in *[!A-Za-z0-9._-]*) continue ;; esac
    _ex=false
    [ -x "$_f" ] && _ex=true
    _mg=false
    case $_n in km-*) _mg=true ;; *) is_managed_path "$_f" && _mg=true ;; esac
    _b=$(wc -c <"$_f")
    _b=$((_b + 0))
    jesc "$_f"; _pj=$JESC
    jesc "$_n"; _nj=$JESC
    _items="${_items:+$_items,}{\"path\":\"$_pj\",\"name\":\"$_nj\",\"executable\":$_ex,\"managed\":$_mg,\"bytes\":$_b}"
  done
  ok_out ",\"candidates\":[$_items]"
}

cmd_import() {
  if [ "$1" = list ]; then import_list; return $?; fi
  _path=$1
  [ -n "$_path" ] && [ -n "$2" ] || { err E_ARG "usage: import list | import <path> <base64 key=value lines>"; return 1; }
  case $_path in
    "$KM_SERVICE_D"/*) ;;
    *) err E_PATH "only scripts directly in $KM_SERVICE_D can be imported"; return 1 ;;
  esac
  _base=${_path##*/}
  case $_base in
    *[!A-Za-z0-9._-]*|'') err E_PATH "unsafe file name"; return 1 ;;
    km-*) err E_CONFLICT "km-* wrappers are managed already"; return 1 ;;
    *.sh) ;;
    *) err E_PATH "script name must end in .sh"; return 1 ;;
  esac
  [ "$_path" = "$KM_SERVICE_D/$_base" ] || { err E_PATH "path must be a direct child of $KM_SERVICE_D"; return 1; }
  if [ ! -f "$_path" ] || [ -L "$_path" ]; then err E_PATH "not a regular file"; return 1; fi
  is_managed_path "$_path" && { err E_CONFLICT "script is already managed"; return 1; }
  _t=$R/.import.$$
  mkdir -p "$R"
  b64_decode_to "$2" "$_t"
  case $? in
    0) ;;
    2) rm -f "$_t"; err E_NO_TOOL "base64 not found"; return 1 ;;
    *) rm -f "$_t"; err E_ARG "invalid base64 payload"; return 1 ;;
  esac
  kv_check "$_t" name kind stop || { rm -f "$_t"; err E_ARG "payload keys are name, kind, stop"; return 1; }
  kv_get "$_t" name; _name=$KV
  kv_get "$_t" kind; _kind=${KV:-daemon}
  kv_get "$_t" stop; _stop=$KV
  rm -f "$_t"
  [ -n "$_name" ] && valid_line "$_name" 64 || { err E_ARG "name is required (max 64, printable)"; return 1; }
  case $_kind in daemon|oneshot) ;; *) err E_ARG "kind must be daemon or oneshot"; return 1 ;; esac
  valid_line "$_stop" 1024 || { err E_ARG "stop command must be one line, max 1024"; return 1; }
  slugify "$_name"
  valid_id "$SLUG" || { err E_ARG "name does not produce a valid id"; return 1; }
  _id=$SLUG
  lock_take "$_id" || { err E_BUSY "another action holds the lock for $_id"; return 1; }
  inst_conflict "$_id"
  if [ "$CONFLICT" != none ]; then lock_drop; err E_CONFLICT "id $_id is already in use ($CONFLICT)"; return 1; fi
  {
    printf 'id=%s\nname=%s\nkind=%s\nsource=imported\n' "$_id" "$_name" "$_kind"
    printf 'start=%s\nboot_script=%s\nargv_match=%s\nadopt=argv\n' "$_path" "$_path" "$_path"
    [ -n "$_stop" ] && printf 'stop=cmd:%s\n' "$_stop"
    printf 'stop_scope=marker\nstart_timeout=8\nstop_grace=5\nhealth=proc\nboot=xbit\nremovable=0\n'
  } >"$R/.import.meta.$$"
  case $_path in *[!A-Za-z0-9._/-]*) rm -f "$R/.import.meta.$$"; lock_drop; err E_PATH "unsafe path"; return 1 ;; esac
  meta_write "$_id" <"$R/.import.meta.$$"
  rm -f "$R/.import.meta.$$"
  lock_drop
  _en=false
  is_enabled "$_path" && _en=true
  km_log "import $_id"
  jesc "$_path"
  ok_out ",\"id\":\"$_id\",\"script\":\"$JESC\",\"enabled\":$_en,\"source\":\"imported\""
}

# ---- delete ---------------------------------------------------------------------------
cmd_delete() {
  _id=$1
  valid_id "$_id" || { err E_ARG "invalid id"; return 1; }
  _mode=$2
  _conf=$3
  _ignore=0
  [ "$4" = "--ignore-hook" ] && _ignore=1
  case $_mode in
    --plan|--confirm) ;;
    *) err E_USAGE "usage: delete <id> --plan | delete <id> --confirm <id> [--ignore-hook]"; return 1 ;;
  esac
  meta_load "$_id" || { err E_UNKNOWN "unknown daemon"; return 1; }
  _dir=$R/daemons/$_id
  _managed=0
  case $M_source in package|created) _managed=1 ;; esac
  _wr=
  wrapper_owned "$_id" && _wr=$KM_SERVICE_D/km-$_id.sh
  _hook=0
  if [ "$M_source" = package ] && [ -f "$_dir/hooks/uninstall.sh" ]; then _hook=1; fi
  if [ "$_mode" = --plan ]; then
    proc_init; scan_markers force; dv_run
    _stopb=false
    [ -n "$P_PIDS" ] && [ "$_managed" = 1 ] && _stopb=true
    _hookb=false
    [ "$_hook" = 1 ] && _hookb=true
    _keeps=
    if [ "$_managed" = 0 ]; then
      _bs=$(boot_file "$_id")
      _keeps="${_bs}${NL}"
    fi
    case $M_source in builtin|imported) _keeps="${_keeps}deep-sleep-cool.conf and every other file outside $_dir" ;; *) _keeps="${_keeps}everything outside $_dir and its km wrapper" ;; esac
    jlist_strs "$_keeps"; _kj=$JL
    _wj=null
    [ -n "$_wr" ] && { jesc "$_wr"; _wj="\"$JESC\""; }
    jesc "$_dir"; _dj=$JESC
    ok_out ",\"plan\":{\"stop\":$_stopb,\"remove_dir\":\"$_dj\",\"remove_wrapper\":$_wj,\"run_uninstall_hook\":$_hookb,\"keeps\":$_kj}"
    return 0
  fi
  [ "$_conf" = "$_id" ] || { err E_CONFIRM "confirmation does not match the id"; return 1; }
  lock_take "$_id" || { err E_BUSY "another action holds the lock for $_id"; return 1; }
  # stop first; nothing is deleted if it will not stop
  _stopped=false
  if [ "$_managed" = 1 ]; then
    stop_core "$_id"
    _rc=$?
    if [ $_rc -ne 0 ]; then
      _o=$OUT
      lock_drop
      OUT=${_o%\}},\"deleted\":false}
      return 1
    fi
    case $OUT in *'"steps":[]'*) ;; *) _stopped=true ;; esac
    meta_load "$_id"
  fi
  _hran=false
  _hexit=null
  if [ "$_hook" = 1 ] && [ "$_ignore" = 0 ]; then
    inst_need_tools || { lock_drop; return 1; }
    _hs=$(sha_of "$_dir/hooks/uninstall.sh")
    if [ -n "$M_uninstall_sha" ] && [ "$_hs" != "$M_uninstall_sha" ]; then
      lock_drop
      err E_VERIFY "uninstall hook changed since install; nothing was deleted (use --ignore-hook to skip it)"
      return 1
    fi
    run_hook "$_dir" hooks/uninstall.sh "$_id"
    _hran=true
    _hexit=$HOOK_EXIT
    if [ "$HOOK_EXIT" != 0 ]; then
      lock_drop
      err E_HOOK "the uninstall hook exited with $HOOK_EXIT; nothing was deleted (use --ignore-hook to skip it)" ",\"hook\":{\"ran\":true,\"exit\":$HOOK_EXIT}"
      return 1
    fi
  fi
  _removed=
  if [ -n "$_wr" ] && wrapper_owned "$_id"; then
    rm -f "$_wr" && _removed="${_removed:+$_removed$NL}$_wr"
  fi
  if [ -e "$_dir" ] || [ -L "$_dir" ]; then
    if safe_rmtree "$_dir" "$R/daemons"; then
      _removed="${_removed:+$_removed$NL}$_dir"
    else
      lock_drop
      err E_NOT_REMOVABLE "refusing to remove $_dir (outside the daemons directory or not a plain directory)"
      return 1
    fi
  fi
  _unm=false
  if [ "$_managed" = 0 ]; then
    _unm=true
    printf '%s\n' "$_id" >>"$R/unmanaged"
  fi
  lock_drop
  km_log "delete $_id unmanaged=$_unm"
  jlist_strs "$_removed"
  ok_out ",\"id\":\"$_id\",\"stopped\":$_stopped,\"hook\":{\"ran\":$_hran,\"exit\":$_hexit},\"removed\":$JL,\"unmanaged\":$_unm"
}
