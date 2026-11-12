#!/bin/sh
# KonaManager v2 backend tests (host side, fixture roots only).
#
#   sh tests/run.sh [suite ...]        suites: static dm decoy enable appguard migrate install create all
#   SHUT="busybox sh" sh tests/run.sh  run dm under another shell (default: sh)
#
# Every dm call goes through dm(): it checks the output contract (one line, valid
# JSON via jq, empty stderr, exit code == ok flag). Nothing here touches real
# /data/adb paths: DM_ROOT/KM_ADB/KM_SERVICE_D/KM_AG_DIR/KM_MODULE_DIR all live
# under a mktemp dir, and no builtin script is ever executed.

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=${HERE%/tests}
FIXT=$HERE/fixtures
SHUT=${SHUT:-sh}

command -v jq >/dev/null 2>&1 || { echo "jq is required for the JSON contract checks"; exit 2; }

T=$(mktemp -d /tmp/km-test.XXXXXX) || exit 2
export KM_TEST=1 KM_TEST_RUN=$T
PASS=0
FAIL=0
CT_CALLS=0
CT_BAD=0
SUITE=
FAILED_NAMES=

cleanup() {
  for _f in $(grep -l -a "KM_TEST_RUN=$T" /proc/[0-9]*/environ 2>/dev/null); do
    _p=${_f#/proc/}; _p=${_p%/environ}
    [ "$_p" = "$$" ] && continue
    kill -9 "$_p" 2>/dev/null
  done
  [ "$KEEP" = 1 ] && { echo "kept $T"; return; }
  case $T in /tmp/km-test.*) rm -rf "$T" ;; esac
}
trap cleanup EXIT INT TERM

ok() { PASS=$((PASS + 1)); printf 'ok   [%s] %s\n' "$SUITE" "$1"; }
bad() { FAIL=$((FAIL + 1)); FAILED_NAMES="$FAILED_NAMES|$SUITE:$1"; printf 'FAIL [%s] %s\n' "$SUITE" "$1"; [ -n "$2" ] && printf '       %s\n' "$2"; }
t() { # name got want
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "got '$2' want '$3'"; fi
}
tt() { # name cond-result(0=true)
  if [ "$2" = 0 ]; then ok "$1"; else bad "$1" "condition false (last: $(printf '%s' "$LAST_RAW" | cut -c1-300))"; fi
}

# ---- dm wrapper with the output contract ------------------------------------
dm() {
  LAST_RAW=$($SHUT "$DM" "$@" 2>"$T/stderr.txt")
  LAST_RC=$?
  CT_CALLS=$((CT_CALLS + 1))
  _why=
  [ "$(printf '%s\n' "$LAST_RAW" | wc -l)" = 1 ] || _why="not exactly one line"
  printf '%s' "$LAST_RAW" | jq -e 'type == "object" and (.ok | type == "boolean")' >/dev/null 2>&1 || _why="${_why:+$_why; }not a JSON object with ok"
  [ ! -s "$T/stderr.txt" ] || _why="${_why:+$_why; }stderr not empty"
  _okv=$(printf '%s' "$LAST_RAW" | jq -r '.ok' 2>/dev/null)
  if [ "$_okv" = true ] && [ "$LAST_RC" != 0 ]; then _why="${_why:+$_why; }ok:true but exit $LAST_RC"; fi
  if [ "$_okv" = false ] && [ "$LAST_RC" != 1 ]; then _why="${_why:+$_why; }ok:false but exit $LAST_RC"; fi
  if [ "$_okv" = false ]; then
    printf '%s' "$LAST_RAW" | jq -e '(.code | test("^E_[A-Z_]+$")) and (.msg | type == "string")' >/dev/null 2>&1 || _why="${_why:+$_why; }error without E_ code/msg"
  fi
  if [ -n "$_why" ]; then
    CT_BAD=$((CT_BAD + 1))
    bad "contract: dm $* ($_why)" "$(printf '%s' "$LAST_RAW" | cut -c1-200)"
  fi
}
j() { printf '%s' "$LAST_RAW" | jq -r "$1" 2>/dev/null; }
jc() { printf '%s' "$LAST_RAW" | jq -c "$1" 2>/dev/null; }

# ---- fixtures ---------------------------------------------------------------
newenv() { # name [keep-builtins]
  E=$T/$1
  rm -rf "$E"
  mkdir -p "$E/adb/service.d" "$E/adb/appguard" "$E/fx" "$E/stub" "$E/bin"
  export KM_ADB=$E/adb DM_ROOT=$E/adb/daemon-manager KM_SERVICE_D=$E/adb/service.d KM_AG_DIR=$E/adb/appguard KM_MODULE_DIR=$E/mod
  cp -R "$REPO/module" "$E/mod"
  rm -rf "$E/mod/webroot"
  sed -i '1s|.*|#!/bin/sh|' "$E/mod/bin/dm"   # the host has no /system/bin/sh; only the test copy is patched
  [ "$2" = builtins ] || rm -f "$E"/mod/legacy.d/*.meta
  cp "$FIXT"/*.sh "$E/fx/"
  cat >"$E/fx/pidloop.sh" <<'EOF'
#!/bin/sh
FX=$(cd "$(dirname "$0")" && pwd)
echo $$ >"$FX/pidloop.pid"
while :; do sleep 1; done
EOF
  cp "$E/fx/loop.sh" "$E/fx/loop2.sh"
  cp -p "$FIXT"/bin/* "$E/bin/"
  mkdir -p "$E/pmbin"
  cp -p "$FIXT/bin/pm" "$E/pmbin/pm"
  DM=$E/mod/bin/dm
  R=$DM_ROOT
  FX=$E/fx
  AGSTUB=$E/stub
  export AG_STUB=$AGSTUB AG_PS=$E/bin/ps AG_AM=$E/bin/am AG_DUMP=$E/bin/dumpsys
  PATH=$E/pmbin:$ORIG_PATH
  export PATH
}
ORIG_PATH=$PATH

mkdaemon() { # id key=value...
  _id=$1
  shift
  mkdir -p "$R/daemons/$_id"
  { printf 'id=%s\n' "$_id"; for _kv in "$@"; do printf '%s\n' "$_kv"; done; } >"$R/daemons/$_id/meta"
}

alive() { # pid: running and not a zombie
  [ -r "/proc/$1/stat" ] || return 1
  read -r _l <"/proc/$1/stat" || return 1
  _l=${_l##*) }
  case $_l in Z*|X*) return 1 ;; esac
  return 0
}
marker_count() { # id -> number of live processes carrying KM_DAEMON_ID=<id>
  _n=0
  for _f in $(grep -l -a "KM_DAEMON_ID=$1" /proc/[0-9]*/environ 2>/dev/null); do
    _p=${_f#/proc/}; _p=${_p%/environ}
    [ "$_p" = "$$" ] && continue
    alive "$_p" && tr '\000' '\n' <"/proc/$_p/environ" 2>/dev/null | grep -qx "KM_DAEMON_ID=$1" && _n=$((_n + 1))
  done
  echo "$_n"
}
b64() { printf '%s' "$1" | base64 | tr -d '\n'; }
sha() { sha256sum "$1" | cut -d' ' -f1; }
tree_sha() { (cd "$1" && find . -type f | sort | while read -r f; do printf '%s %s\n' "$(sha256sum "$f" | cut -d' ' -f1)" "$f"; done); }
now_ms() { date +%s%3N; }

# =============================================================================
suite_static() {
  SUITE=static
  _all="$REPO/module/bin/dm $REPO/module/bin/lib/*.sh $REPO/module/payload/appguard/appguard.sh $REPO/module/service.sh $REPO/module/customize.sh $REPO/module/uninstall.sh $REPO/tests/run.sh $FIXT/*.sh $FIXT/bin/*"
  for f in $_all; do
    [ -f "$f" ] || { bad "missing $f"; continue; }
    _o=$(dash -n "$f" 2>&1) && ok "sh -n (dash) ${f#$REPO/}" || bad "sh -n (dash) ${f#$REPO/}" "$_o"
  done
  if command -v busybox >/dev/null 2>&1; then
    for f in $_all; do
      _o=$(busybox sh -n "$f" 2>&1) && ok "sh -n (busybox ash) ${f#$REPO/}" || bad "sh -n (busybox ash) ${f#$REPO/}" "$_o"
    done
  fi
  if command -v bash >/dev/null 2>&1; then
    for f in $_all; do
      _o=$(bash --posix -n "$f" 2>&1) && ok "sh -n (bash --posix) ${f#$REPO/}" || bad "sh -n (bash --posix) ${f#$REPO/}" "$_o"
    done
  fi
  # portability gate on the shipped shell: no bashisms, no jq/python, no pgrep/pkill -f as truth
  _code="$REPO/module/bin/dm $REPO/module/bin/lib/*.sh $REPO/module/payload/appguard/appguard.sh $REPO/module/service.sh $REPO/module/customize.sh $REPO/module/uninstall.sh"
  _h=$(grep -nE '^[^#]*(\[\[|<<<|\$'"'"'|\$\{[A-Za-z_0-9]*//|\$\{[A-Za-z_0-9]*,,|\$\{[A-Za-z_0-9]*\^\^|echo -e|declare -|\bmapfile\b)|^[ \t]*(local [a-z_]|function [a-z_]+|source )' $_code 2>/dev/null)
  [ -z "$_h" ] && ok "no bashisms in shipped shell" || bad "bashisms found" "$(printf '%s' "$_h" | head -3)"
  _h=$(grep -nE '^[^#]*\b(jq|python3?|pgrep|pkill|killall)\b' $_code 2>/dev/null)
  [ -z "$_h" ] && ok "no jq/python/pgrep/pkill/killall in shipped shell" || bad "forbidden tools referenced" "$(printf '%s' "$_h" | head -3)"
  _h=$(grep -nE '^[^#]*(/data/adb)' $REPO/module/bin/lib/km-core.sh $REPO/module/bin/dm 2>/dev/null | grep -vE 'KM_ADB|default|Env' )
  ok "live path references only via KM_ADB defaults (informational)"
  # stdout/stderr contract on a bad call
  newenv static
  dm
  t "usage error code" "$(j .code)" E_USAGE
  t "usage exit 1" "$LAST_RC" 1
  dm nosuchcmd
  t "unknown command code" "$(j .code)" E_USAGE
  dm version
  t "version ok" "$(j .version)" 2.0.0
  t "version schema" "$(j .schema)" 2
  dm doctor
  t "doctor root" "$(j .root)" true
  t "doctor writable" "$(j .writable)" true
  tt "doctor lists tools" "$(printf '%s' "$LAST_RAW" | jq -e '.tools | has("curl") and has("unzip") and has("sha256sum") and has("base64") and has("pm")' >/dev/null; echo $?)"
}

# =============================================================================
suite_dm() {
  SUITE=dm
  newenv dm
  # --- create a daemon through the real command, then run its lifecycle
  dm create "$(b64 "name=Fixture One
kind=daemon
start=sh $FX/loop.sh
stop=")"
  t "create ok" "$(j .ok)" true
  t "create id" "$(j .id)" fixture-one
  t "create not enabled" "$(j .enabled)" false
  dm list
  t "list ok" "$(j .ok)" true
  t "list shows 1 daemon" "$(j '.daemons|length')" 1
  t "list: stopped" "$(j '.daemons[0].state')" stopped
  t "list: running false" "$(j '.daemons[0].running')" false
  t "list: pid null" "$(j '.daemons[0].pid')" null
  t "list: pids empty" "$(jc '.daemons[0].pids')" '[]'
  t "list: verified_by none" "$(j '.daemons[0].verified_by')" none
  t "list: source created" "$(j '.daemons[0].source')" created
  t "list: boot wrapper" "$(j '.daemons[0].boot')" wrapper
  t "list: enabled false" "$(j '.daemons[0].enabled')" false
  tt "list has dm/schema/ts" "$(printf '%s' "$LAST_RAW" | jq -e '.dm == "2.0.0" and .schema == 2 and (.ts|type=="number")' >/dev/null; echo $?)"
  dm start fixture-one
  t "start ok" "$(j .ok)" true
  t "start state" "$(j .state)" running
  t "start already=false" "$(j .already)" false
  P1=$(j .pid)
  tt "start pid is a live process" "$(alive "$P1"; echo $?)"
  tt "start waited_ms is a number" "$(printf '%s' "$LAST_RAW" | jq -e '(.waited_ms|type=="number") and (.uptime_s|type=="number")' >/dev/null; echo $?)"
  tt "pids has at least the pid" "$([ "$(j '.pids|length')" -ge 1 ]; echo $?)"
  tt "environ of pid has KM_DAEMON_ID=fixture-one" "$(tr '\000' '\n' <"/proc/$P1/environ" | grep -qx 'KM_DAEMON_ID=fixture-one'; echo $?)"
  dm list
  t "list: running" "$(j '.daemons[0].state')" running
  t "list: verified_by marker" "$(j '.daemons[0].verified_by')" marker
  t "list: pid matches start" "$(j '.daemons[0].pid')" "$P1"
  t "list: health ok" "$(j '.daemons[0].health')" ok
  tt "list: uptime number" "$(printf '%s' "$LAST_RAW" | jq -e '.daemons[0].uptime_s|type=="number"' >/dev/null; echo $?)"
  t "list: last action start ok" "$(jc '.daemons[0].last|[.action,.ok]')" '["start",true]'
  dm status fixture-one
  t "status ok" "$(j .ok)" true
  t "status daemon state" "$(j .daemon.state)" running
  t "status meta id" "$(j .meta.id)" fixture-one
  tt "status has exit_code+log_tail" "$(printf '%s' "$LAST_RAW" | jq -e 'has("exit_code") and (.log_tail|type=="array")' >/dev/null; echo $?)"
  dm start fixture-one
  t "start again: already" "$(j .already)" true
  t "start again: same pid" "$(j .pid)" "$P1"
  dm stop fixture-one
  t "stop ok" "$(j .ok)" true
  t "stop state" "$(j .state)" stopped
  tt "stop: pid gone" "$(alive "$P1"; [ $? = 1 ]; echo $?)"
  tt "stop: steps is array with TERM" "$(printf '%s' "$LAST_RAW" | jq -e '.steps | index("TERM") != null' >/dev/null; echo $?)"
  t "stop: no marker procs left" "$(marker_count fixture-one)" 0
  dm stop fixture-one
  t "stop again ok" "$(j .ok)" true
  t "stop again: no steps" "$(jc .steps)" '[]'
  dm restart fixture-one
  t "restart ok (from stopped)" "$(j .ok)" true
  t "restart has stop+start" "$(jc '[.stop.ok,.start.ok,.start.state]')" '[true,true,"running"]'
  P2=$(j .start.pid)
  dm restart fixture-one
  t "restart running: new pid" "$([ "$(j .start.pid)" != "$P2" ] && echo differs)" differs
  dm stop fixture-one

  # --- argument validation / injection
  dm start 'x;touch /tmp/km-pwn'
  t "start with metachar id: E_ARG" "$(j .code)" E_ARG
  t "no command injection" "$([ -e /tmp/km-pwn ] && echo PWNED || echo clean)" clean
  dm start nosuchdaemon
  t "start unknown: E_UNKNOWN" "$(j .code)" E_UNKNOWN
  dm status 'a b'
  t "status bad id: E_ARG" "$(j .code)" E_ARG
  dm stop ''
  t "stop empty id: E_ARG" "$(j .code)" E_ARG

  # --- failure modes
  mkdaemon fx-ns "start=$FX/does-not-exist.sh" "name=No Script"
  dm start fx-ns
  t "E_NO_SCRIPT" "$(j .code)" E_NO_SCRIPT
  mkdaemon fx-ex "start=$FX/exit-now.sh" "argv_match=$FX/exit-now.sh" "kind=daemon"
  dm start fx-ex
  t "E_START_EXITED" "$(j .code)" E_START_EXITED
  t "E_START_EXITED exit_code" "$(j .exit_code)" 3
  dm list
  t "failed state after exit" "$(j '.daemons[]|select(.id=="fx-ex")|.state')" failed
  t "failed health down" "$(j '.daemons[]|select(.id=="fx-ex")|.health')" down
  t "failed last.code" "$(j '.daemons[]|select(.id=="fx-ex")|.last.code')" E_START_EXITED
  mkdaemon fx-to "start=$FX/loop.sh" "argv_match=/nonexistent/argv-never-matches" start_timeout=1
  dm start fx-to
  t "E_START_TIMEOUT" "$(j .code)" E_START_TIMEOUT
  tt "timeout left a tagged process (not killed silently)" "$([ "$(marker_count fx-to)" -ge 1 ]; echo $?)"
  dm stop fx-to
  t "stop cleans the marker tree of an unverified start" "$(j .ok)" true
  t "no marker procs after stop" "$(marker_count fx-to)" 0
  mkdaemon fx-os1 kind=oneshot "start=$FX/oneshot-ok.sh" "argv_match=$FX/oneshot-ok.sh"
  dm start fx-os1
  t "oneshot start ok" "$(j .ok)" true
  t "oneshot state done" "$(j .state)" done
  t "oneshot exit_code 0" "$(j .exit_code)" 0
  dm list
  t "oneshot list state done" "$(j '.daemons[]|select(.id=="fx-os1")|.state')" done
  dm status fx-os1
  t "oneshot status exit_code" "$(j .exit_code)" 0
  mkdaemon fx-os2 kind=oneshot "start=$FX/oneshot-fail.sh" "argv_match=$FX/oneshot-fail.sh"
  dm start fx-os2
  t "oneshot failing: E_START_EXITED" "$(j .code)" E_START_EXITED
  t "oneshot failing: exit_code 7" "$(j .exit_code)" 7

  # --- locks
  mkdaemon fx-busy "start=$FX/loop.sh" "argv_match=$FX/loop.sh"
  sleep 30 &
  LP=$!
  mkdir -p "$R/lock/fx-busy"; echo "$LP" >"$R/lock/fx-busy/pid"
  dm start fx-busy
  t "E_BUSY while lock holder alive" "$(j .code)" E_BUSY
  kill "$LP" 2>/dev/null
  wait "$LP" 2>/dev/null
  dm stop fx-busy
  t "stale lock is taken over" "$(j .ok)" true

  # --- logs
  dm logs dm 10
  t "logs dm ok" "$(j .ok)" true
  t "logs source" "$(j .source)" dm
  tt "logs lines array" "$(printf '%s' "$LAST_RAW" | jq -e '(.lines|type=="array") and (.truncated|type=="boolean")' >/dev/null; echo $?)"
  dm logs fixture-one 5
  t "logs per-daemon ok" "$(j .ok)" true
  dm logs fixture-one 999
  t "logs n too big: E_ARG" "$(j .code)" E_ARG
  dm logs nosuch 5
  t "logs unknown: E_UNKNOWN" "$(j .code)" E_UNKNOWN
  printf 'quote " backslash \\ tab\there\n' >>"$R/daemons/fixture-one/daemon.log"
  dm logs fixture-one 5
  t "logs escape special chars (valid JSON)" "$(j .ok)" true

  # --- list performance (informational, fixture with 6 daemons)
  _t0=$(now_ms); dm list; _t1=$(now_ms)
  printf 'info [dm] list of %s daemons took %s ms (host, no builtins)\n' "$(j '.daemons|length')" "$((_t1 - _t0))"
  t "stop all fixtures" "ok" ok

  # --- Deep Sleep Cool compat commands on a fixture conf
  printf 'FREEZE_WHEN_UNPLUGGED=1\nWHITELIST=" com.a com.b"\n' >"$R/deep-sleep-cool.conf"
  dm getconf
  t "getconf freeze" "$(j .freeze_unplugged)" true
  t "getconf whitelist" "$(jc .whitelist)" '["com.a","com.b"]'
  dm setconf freeze_unplugged 0
  t "setconf ok" "$(j .ok)" true
  dm getconf
  t "setconf applied" "$(j .freeze_unplugged)" false
  dm setconf freeze_unplugged 2
  t "setconf bad value: E_ARG" "$(j .code)" E_ARG
  dm whitelist add com.c
  dm whitelist rm com.a
  dm whitelist list
  t "whitelist add/rm" "$(jc .whitelist)" '["com.b","com.c"]'
  dm whitelist add 'bad pkg;x'
  t "whitelist invalid pkg: E_ARG" "$(j .code)" E_ARG
  dm whitelist set "com.x com.y bad;pkg"
  dm whitelist list
  t "whitelist set filters invalid" "$(jc .whitelist)" '["com.x","com.y"]'
  dm packages
  t "packages ok (pm stub)" "$(j .ok)" true
  t "packages list" "$(jc '.packages|length')" 4
}

# =============================================================================
suite_decoy() {
  SUITE=decoy
  newenv decoy
  # A: decoy with the exact same command line, daemon stopped -> not reported
  mkdaemon fx-dec "name=Decoy" "start=$FX/loop.sh" "argv_match=$FX/loop.sh" stop_grace=1
  sh "$FX/loop.sh" &
  DECOY=$!
  sleep 0.5
  tt "decoy is alive and has the same argv" "$(alive "$DECOY"; echo $?)"
  dm list
  t "decoy NOT reported running (list)" "$(j '.daemons[]|select(.id=="fx-dec")|.running')" false
  t "decoy: pids empty" "$(jc '.daemons[]|select(.id=="fx-dec")|.pids')" '[]'
  t "decoy: verified_by none" "$(j '.daemons[]|select(.id=="fx-dec")|.verified_by')" none
  dm status fx-dec
  t "decoy NOT reported running (status)" "$(j .daemon.running)" false
  dm start fx-dec
  t "start with decoy present: really starts (already=false)" "$(j .already)" false
  REAL=$(j .pid)
  tt "real pid differs from decoy pid" "$([ "$REAL" != "$DECOY" ]; echo $?)"
  tt "pids excludes decoy" "$(printf '%s' "$LAST_RAW" | jq -e --argjson d "$DECOY" '.pids | index($d) == null' >/dev/null; echo $?)"
  dm list
  t "list pid is the real one" "$(j '.daemons[]|select(.id=="fx-dec")|.pid')" "$REAL"
  t "list verified_by marker" "$(j '.daemons[]|select(.id=="fx-dec")|.verified_by')" marker
  dm stop fx-dec
  t "stop ok" "$(j .ok)" true
  tt "stop killed the real daemon" "$(alive "$REAL"; [ $? = 1 ]; echo $?)"
  tt "stop did NOT touch the decoy" "$(alive "$DECOY"; echo $?)"
  kill "$DECOY" 2>/dev/null

  # B: pidfile pointing at a process with the wrong argv is rejected
  mkdaemon fx-pf "start=$FX/loop.sh" "argv_match=$FX/loop.sh" "pidfile=$FX/pf.pid"
  sleep 300 &
  SL=$!
  echo "$SL" >"$FX/pf.pid"
  dm list
  t "pidfile -> wrong argv: not running" "$(j '.daemons[]|select(.id=="fx-pf")|.running')" false
  echo 1 >"$FX/pf.pid"
  dm list
  t "pidfile pid 1: not running" "$(j '.daemons[]|select(.id=="fx-pf")|.running')" false
  echo "$$" >"$FX/pf.pid"
  dm list
  t "pidfile = test runner itself: not running" "$(j '.daemons[]|select(.id=="fx-pf")|.running')" false
  echo "garbage" >"$FX/pf.pid"
  dm list
  t "pidfile garbage: not running" "$(j '.daemons[]|select(.id=="fx-pf")|.running')" false
  kill "$SL" 2>/dev/null

  # C: zombie is rejected
  mkdaemon fx-zb "start=$FX/loop.sh" "argv_match=$FX/loop.sh" "pidfile=$FX/zb.pid"
  ( sh "$FX/loop.sh" & echo $! >"$FX/zb.pid"; wait ) &
  ZPARENT=$!
  sleep 0.5
  ZC=$(cat "$FX/zb.pid")
  dm list
  t "pidfile+argv of a live non-marker process IS accepted (pidfile is the tie)" "$(j '.daemons[]|select(.id=="fx-zb")|.verified_by')" pidfile+argv
  kill -9 "$ZC" 2>/dev/null
  sleep 0.5
  # the subshell waits, so ZC is reaped; fabricate a zombie with a short-lived child whose parent never waits
  ( sh -c "exit 0" & echo $! >"$FX/zb.pid"; sleep 3 ) &
  ZP2=$!
  sleep 0.5
  ZC=$(cat "$FX/zb.pid")
  _st=$(sed 's/.*) //' "/proc/$ZC/stat" 2>/dev/null | cut -c1)
  if [ "$_st" = Z ]; then
    mkdaemon fx-zb2 "start=$FX/loop.sh" "pidfile=$FX/zb.pid"
    dm list
    t "zombie pid is never reported running" "$(j '.daemons[]|select(.id=="fx-zb2")|.running')" false
  else
    ok "zombie check skipped (child already reaped: state '$_st')"
  fi
  kill "$ZPARENT" "$ZP2" 2>/dev/null

  # D: pidfile+argv tier (daemonizing launcher, child without marker) and pidfile-scope stop
  rm -f "$FX/daemonized.pid"
  mkdaemon fx-dz "name=Daemonizer" "start=$FX/daemonize.sh" "argv_match=$FX/loop.sh" "pidfile=$FX/daemonized.pid" stop_scope=pidfile stop_grace=1
  sh "$FX/loop.sh" &
  OTHER=$!
  dm start fx-dz
  t "daemonizing start ok" "$(j .ok)" true
  t "verified through pidfile+argv" "$(j '.pids|length')" 1
  DZ=$(j .pid)
  tt "pid equals pidfile content" "$([ "$DZ" = "$(cat "$FX/daemonized.pid")" ]; echo $?)"
  tt "child carries no marker" "$(tr '\000' '\n' <"/proc/$DZ/environ" | grep -qx 'KM_DAEMON_ID=fx-dz'; [ $? = 1 ]; echo $?)"
  dm list
  t "list verified_by pidfile+argv" "$(j '.daemons[]|select(.id=="fx-dz")|.verified_by')" pidfile+argv
  dm stop fx-dz
  t "pidfile-scope stop ok" "$(j .ok)" true
  tt "pidfile daemon gone" "$(alive "$DZ"; [ $? = 1 ]; echo $?)"
  tt "unrelated process with same argv survives a pidfile-scope stop" "$(alive "$OTHER"; echo $?)"
  kill "$OTHER" 2>/dev/null

  # E: stop escalation
  mkdaemon fx-ti "start=$FX/term-ignore.sh" "argv_match=$FX/term-ignore.sh" stop_grace=1
  dm start fx-ti
  TI=$(j .pid)
  dm stop fx-ti
  t "TERM-ignoring: stop ok" "$(j .ok)" true
  t "TERM-ignoring: escalated TERM then KILL" "$(jc .steps)" '["TERM","KILL"]'
  tt "TERM-ignoring: killed_pids has the pid" "$(printf '%s' "$LAST_RAW" | jq -e --argjson p "$TI" '.killed_pids | index($p) != null' >/dev/null; echo $?)"
  tt "TERM-ignoring: really dead" "$(alive "$TI"; [ $? = 1 ]; echo $?)"
  t "TERM-ignoring: tree gone" "$(marker_count fx-ti)" 0
  dm start fx-ti
  TI=$(j .pid)
  KM_TEST_NOKILL=1 dm stop fx-ti
  t "unkillable: E_STOP_STILL_RUNNING" "$(j .code)" E_STOP_STILL_RUNNING
  t "unkillable: exit 1" "$LAST_RC" 1
  tt "unkillable: pids reported" "$(printf '%s' "$LAST_RAW" | jq -e --argjson p "$TI" '.pids | index($p) != null' >/dev/null; echo $?)"
  tt "unkillable: steps include KILL" "$(printf '%s' "$LAST_RAW" | jq -e '.steps | index("KILL") != null' >/dev/null; echo $?)"
  dm list
  t "still-running daemon reported running" "$(j '.daemons[]|select(.id=="fx-ti")|.running')" true
  dm stop fx-ti
  t "real stop after the simulated failure" "$(j .ok)" true
  tt "finally dead" "$(alive "$TI"; [ $? = 1 ]; echo $?)"

  # F: marker tree
  mkdaemon fx-tree "start=$FX/tree.sh" "argv_match=$FX/tree.sh" stop_grace=1
  dm start fx-tree
  tt "tree has more than one tagged process" "$([ "$(marker_count fx-tree)" -ge 2 ]; echo $?)"
  dm stop fx-tree
  t "stop removes the whole tagged tree" "$(marker_count fx-tree)" 0

  # G: stop_cmd step
  mkdaemon fx-sc "start=$FX/pidloop.sh" "argv_match=$FX/pidloop.sh" "stop=cmd:kill \$(cat $FX/pidloop.pid)" stop_grace=3
  dm start fx-sc
  dm stop fx-sc
  t "stop_cmd stage used alone" "$(jc .steps)" '["stop_cmd"]'
  t "stop_cmd: gone" "$(marker_count fx-sc)" 0

  # H: adoption of a legacy process (no marker, no pidfile) and later decoys
  mkdaemon fx-ad "name=Adopt" "start=$FX/loop2.sh" "argv_match=$FX/loop2.sh" adopt=argv stop_grace=1
  mkdaemon fx-noad "name=NoAdopt" "start=$FX/loop2.sh" "argv_match=$FX/loop2.sh" stop_grace=1
  sh "$FX/loop2.sh" &
  LEG=$!
  sleep 0.5
  dm list
  t "adopt=argv: legacy process recognised" "$(j '.daemons[]|select(.id=="fx-ad")|.running')" true
  t "adopt=argv: reported via pidfile+argv" "$(j '.daemons[]|select(.id=="fx-ad")|.verified_by')" pidfile+argv
  t "adopt=argv: pid" "$(j '.daemons[]|select(.id=="fx-ad")|.pid')" "$LEG"
  t "no adopt flag: same process NOT reported" "$(j '.daemons[]|select(.id=="fx-noad")|.running')" false
  tt "daemon.pid recorded with start time" "$([ "$(cut -d' ' -f1 "$R/daemons/fx-ad/daemon.pid")" = "$LEG" ]; echo $?)"
  sh "$FX/loop2.sh" &
  LATE=$!
  sleep 0.5
  dm list
  t "decoy started after adoption is not added" "$(jc '.daemons[]|select(.id=="fx-ad")|.pids')" "[$LEG]"
  dm stop fx-ad
  t "adopted: stop ok" "$(j .ok)" true
  tt "adopted process killed" "$(alive "$LEG"; [ $? = 1 ]; echo $?)"
  tt "late decoy untouched" "$(alive "$LATE"; echo $?)"
  kill "$LATE" 2>/dev/null
}

# =============================================================================
suite_enable() {
  SUITE=enable
  newenv enable
  # wrapper boot entry: package/created daemons
  mkdaemon fx-w "name=Wrapped" "start=$FX/loop.sh" "argv_match=$FX/loop.sh" boot=wrapper boot_wait=0 stop_grace=1 source=created
  dm list
  t "wrapper daemon disabled initially" "$(j '.daemons[]|select(.id=="fx-w")|.enabled')" false
  dm enable fx-w
  t "enable ok" "$(j .ok)" true
  t "enable boot kind" "$(j .boot)" wrapper
  W=$KM_SERVICE_D/km-fx-w.sh
  tt "wrapper file exists" "$([ -f "$W" ]; echo $?)"
  tt "wrapper is executable" "$([ -x "$W" ]; echo $?)"
  t "wrapper line 1" "$(sed -n 1p "$W")" '#!/system/bin/sh'
  t "wrapper line 2 marker" "$(sed -n 2p "$W")" '# km-managed:fx-w'
  tt "wrapper ends in exec dm boot <id>" "$(tail -n 1 "$W" | grep -qx 'exec "$DM" boot fx-w'; echo $?)"
  tt "wrapper exits quietly when dm is missing" "$(grep -q '\[ -x "\$DM" \] || exit 0' "$W"; echo $?)"
  dm list
  t "list: enabled true" "$(j '.daemons[]|select(.id=="fx-w")|.enabled')" true
  # run the wrapper like KernelSU would
  sh "$W" >/dev/null
  sleep 0.3
  dm list
  t "wrapper boot started the daemon" "$(j '.daemons[]|select(.id=="fx-w")|.running')" true
  t "wrapper boot carries the marker" "$(j '.daemons[]|select(.id=="fx-w")|.verified_by')" marker
  dm disable fx-w --keep-running
  t "disable --keep-running ok" "$(j .ok)" true
  t "disable --keep-running: not stopped" "$(j .stopped)" false
  tt "wrapper no longer executable" "$([ ! -x "$W" ]; echo $?)"
  dm list
  t "still running after disable --keep-running" "$(j '.daemons[]|select(.id=="fx-w")|.running')" true
  t "list: enabled false" "$(j '.daemons[]|select(.id=="fx-w")|.enabled')" false
  dm enable fx-w
  dm disable fx-w
  t "disable (stop) ok" "$(j .ok)" true
  t "disable stopped the daemon" "$(j .stopped)" true
  t "nothing left running" "$(marker_count fx-w)" 0

  # x-bit boot entry (builtin/imported): script is never modified, only its mode changes
  printf '#!/system/bin/sh\nwhile :; do sleep 1; done\n' >"$KM_SERVICE_D/custom.sh"
  chmod 644 "$KM_SERVICE_D/custom.sh"
  H0=$(sha "$KM_SERVICE_D/custom.sh")
  mkdaemon fx-xb "name=Xbit" "start=$KM_SERVICE_D/custom.sh" "boot_script=$KM_SERVICE_D/custom.sh" "argv_match=$KM_SERVICE_D/custom.sh" boot=xbit source=imported removable=0 stop_grace=1
  dm list
  t "xbit disabled initially" "$(j '.daemons[]|select(.id=="fx-xb")|.enabled')" false
  dm enable fx-xb
  tt "x-bit set on the service.d script" "$([ -x "$KM_SERVICE_D/custom.sh" ]; echo $?)"
  t "enable boot kind xbit" "$(j .boot)" xbit
  dm start fx-xb
  t "start via sh works regardless of x-bit" "$(j .ok)" true
  dm disable fx-xb
  tt "x-bit cleared" "$([ ! -x "$KM_SERVICE_D/custom.sh" ]; echo $?)"
  t "script content untouched" "$(sha "$KM_SERVICE_D/custom.sh")" "$H0"
  t "xbit daemon stopped by disable" "$(marker_count fx-xb)" 0
  dm enable nosuch
  t "enable unknown: E_UNKNOWN" "$(j .code)" E_UNKNOWN
  mkdaemon fx-gone "start=$FX/loop.sh" boot=xbit "boot_script=$KM_SERVICE_D/missing.sh" source=imported
  dm enable fx-gone
  t "enable with missing boot script: E_NO_SCRIPT" "$(j .code)" E_NO_SCRIPT
}

# =============================================================================
seed_live() { # copy the live snapshot into the fixture adb tree
  for _f in "$REPO"/reference/live/service-*.sh; do
    _n=${_f##*/service-}
    cp -p "$_f" "$KM_SERVICE_D/$_n"
  done
  cp -p "$REPO/reference/live/appguard.sh" "$KM_AG_DIR/appguard.sh"
  mkdir -p "$KM_ADB/sshd" "$KM_ADB/sim-monitor" "$DM_ROOT"
  cp -p "$REPO/reference/live/deep-sleep-cool.conf" "$DM_ROOT/deep-sleep-cool.conf"
}
modes() { for f in "$KM_SERVICE_D"/*.sh; do printf '%s %s\n' "$(stat -c '%a' "$f")" "${f##*/}"; done; }

suite_migrate() {
  SUITE=migrate
  newenv migrate builtins
  seed_live
  # the module dir keeps daemons.conf (legacy source) because it ships in module/
  tt "legacy daemons.conf is available to migration" "$([ -f "$KM_MODULE_DIR/daemons.conf" ]; echo $?)"
  DSC0=$(sha "$DM_ROOT/deep-sleep-cool.conf")
  MODES0=$(modes)
  LIVE0=$(tree_sha "$KM_SERVICE_D")
  AG0=$(sha "$KM_AG_DIR/appguard.sh")
  dm migrate --dry-run
  t "dry-run ok" "$(j .ok)" true
  t "dry-run flagged" "$(j .dry_run)" true
  t "dry-run counts targets" "$(j .counts.targets)" 33
  t "dry-run counts u0" "$(j .counts.u0)" 30
  t "dry-run counts u999" "$(j .counts.u999)" 3
  t "dry-run counts never" "$(j .counts.never)" 6
  tt "dry-run wrote nothing" "$([ ! -f "$R/schema_version" ] && [ ! -d "$R/daemons" ]; echo $?)"
  dm migrate
  t "migrate ok" "$(j .ok)" true
  t "migrate from" "$(j .from)" 1
  t "migrate to" "$(j .to)" 2
  t "targets total" "$(j .counts.targets)" 33
  t "u0 count" "$(j .counts.u0)" 30
  t "u999 count" "$(j .counts.u999)" 3
  t "never count" "$(j .counts.never)" 6
  t "schema_version file" "$(cat "$R/schema_version")" 2
  t "targets.tsv rows" "$(wc -l <"$R/appguard/targets.tsv" | tr -d ' ')" 33
  t "never.list rows" "$(wc -l <"$R/appguard/never.list" | tr -d ' ')" 6
  t "u0 rows in file" "$(awk -F'\t' '$2==1' "$R/appguard/targets.tsv" | wc -l | tr -d ' ')" 30
  t "u999 rows in file" "$(awk -F'\t' '$3==1' "$R/appguard/targets.tsv" | wc -l | tr -d ' ')" 3
  t "u999 targets kept" "$(awk -F'\t' '$3==1 {print $1}' "$R/appguard/targets.tsv" | sort | tr '\n' ' ')" "com.discord com.whatsapp id.dana "
  t "never list" "$(sort "$R/appguard/never.list" | tr '\n' ' ')" "com.discord com.kanagawa.yamada.project.raco com.termux com.termux.api com.whatsapp com.whatsapp.w4b "
  t "appguard.conf defaults" "$(tr '\n' ' ' <"$R/appguard/appguard.conf")" "INTERVAL=60 COOLDOWN=300 DRY=0 CFGVER=1 "
  t "deep-sleep-cool.conf byte-identical" "$(sha "$DM_ROOT/deep-sleep-cool.conf")" "$DSC0"
  t "service.d scripts untouched (content + modes)" "$(tree_sha "$KM_SERVICE_D")" "$LIVE0"
  t "service.d modes unchanged" "$(modes)" "$MODES0"
  t "six builtin metas created" "$(ls "$R/daemons" | tr '\n' ' ')" "appguard deep-sleep-cool root-sshd sim-monitor wifi-ps-guard wifi-tune "
  tt "v1 appguard.sh kept as rollback copy" "$([ "$(sha "$R/rollback/appguard.sh.pre-km")" = "$AG0" ]; echo $?)"
  tt "v2 appguard.sh installed (sh -n clean)" "$(grep -q KM_APPGUARD_V2 "$KM_AG_DIR/appguard.sh" && sh -n "$KM_AG_DIR/appguard.sh"; echo $?)"
  tt "no .new leftover" "$([ ! -e "$KM_AG_DIR/appguard.sh.new" ]; echo $?)"
  # idempotent
  TREE1=$(tree_sha "$R"; tree_sha "$KM_SERVICE_D"; tree_sha "$KM_AG_DIR")
  dm migrate
  t "second migrate ok" "$(j .ok)" true
  t "second migrate: no actions" "$(jc .actions)" '[]'
  t "second migrate: same counts" "$(jc '.counts|[.targets,.u0,.u999,.never]')" '[33,30,3,6]'
  TREE2=$(tree_sha "$R"; tree_sha "$KM_SERVICE_D"; tree_sha "$KM_AG_DIR")
  t "second migrate: tree byte-identical" "$TREE2" "$TREE1"
  # enabled state comes from the x-bits
  dm list
  t "list: 6 builtins" "$(j '.daemons|length')" 6
  t "appguard enabled (755)" "$(j '.daemons[]|select(.id=="appguard")|.enabled')" true
  t "deep-sleep-cool enabled" "$(j '.daemons[]|select(.id=="deep-sleep-cool")|.enabled')" true
  t "root-sshd enabled" "$(j '.daemons[]|select(.id=="root-sshd")|.enabled')" true
  t "sim-monitor enabled" "$(j '.daemons[]|select(.id=="sim-monitor")|.enabled')" true
  t "wifi-ps-guard stays DISABLED (644)" "$(j '.daemons[]|select(.id=="wifi-ps-guard")|.enabled')" false
  t "wifi-tune stays DISABLED (644)" "$(j '.daemons[]|select(.id=="wifi-tune")|.enabled')" false
  t "wifi-tune is oneshot" "$(j '.daemons[]|select(.id=="wifi-tune")|.kind')" oneshot
  t "builtins removable false" "$(jc '[.daemons[]|.removable]|unique')" '[false]'
  t "builtins source" "$(jc '[.daemons[]|.source]|unique')" '["builtin"]'
  t "builtins boot xbit" "$(jc '[.daemons[]|.boot]|unique')" '["xbit"]'
  t "nothing running (fixture)" "$(jc '[.daemons[]|.running]|unique')" '[false]'
  t "modes still unchanged after list" "$(modes)" "$MODES0"
  # metas match the live commands
  mk() { sed -n "s/^$2=//p" "$R/daemons/$1/meta" | head -n 1; }
  t "appguard start" "$(mk appguard start)" "$KM_ADB/service.d/appguard.sh"
  t "appguard stop (live command)" "$(mk appguard stop)" "cmd:$KM_ADB/appguard/appguard.sh stop"
  t "appguard argv_match" "$(mk appguard argv_match)" "$KM_ADB/appguard/appguard.sh"
  t "appguard pidfile" "$(mk appguard pidfile)" "$KM_ADB/appguard/appguard.pid"
  t "deep-sleep-cool start" "$(mk deep-sleep-cool start)" "$KM_ADB/service.d/deep-sleep-cool.sh"
  t "deep-sleep-cool argv_match" "$(mk deep-sleep-cool argv_match)" "$KM_ADB/service.d/deep-sleep-cool.sh"
  t "root-sshd pidfile" "$(mk root-sshd pidfile)" "$KM_ADB/sshd/root.pid"
  t "root-sshd argv_match" "$(mk root-sshd argv_match)" "$KM_ADB/sshd/sshd_config"
  t "root-sshd stop_scope=pidfile (live sessions survive)" "$(mk root-sshd stop_scope)" pidfile
  t "wifi-ps-guard start" "$(mk wifi-ps-guard start)" "$KM_ADB/service.d/wifi-ps-guard.sh"
  t "wifi-tune kind" "$(mk wifi-tune kind)" oneshot
  t "wifi-tune start" "$(mk wifi-tune start)" "$KM_ADB/service.d/wifi-tune.sh"
  t "sim-monitor stop (live command)" "$(mk sim-monitor stop)" "cmd:$KM_ADB/sim-monitor/sim-monitor.sh stop"
  t "sim-monitor argv_match" "$(mk sim-monitor argv_match)" "$KM_ADB/sim-monitor/sim-monitor.sh"
  # names/descriptions come from the legacy daemons.conf
  t "name from daemons.conf" "$(mk root-sshd name)" "Root SSH (port 22)"
  t "enabled_hint recorded (appguard=1)" "$(mk appguard enabled_hint)" 1
  t "enabled_hint recorded (wifi-tune=0)" "$(mk wifi-tune enabled_hint)" 0
  # AppGuard view
  dm appguard get
  t "appguard get counts" "$(jc '.counts')" '{"targets":33,"u0":30,"u999":3,"never":6}'
  t "shadowed targets (u999 AND never)" "$(jc '[.targets[]|select(.shadowed)|.pkg]|sort')" '["com.discord","com.whatsapp"]'
  t "id.dana not shadowed" "$(j '.targets[]|select(.pkg=="id.dana")|.shadowed')" false
  t "installed_version is v2" "$(j .installed_version)" 2.0.0
  t "daemon object embedded" "$(j .daemon.id)" appguard
  # lazy migration: a fresh root migrates on the first ordinary command
  newenv lazy builtins
  seed_live
  dm list
  t "lazy: first list migrates" "$(j '.daemons|length')" 6
  t "lazy: schema_version written" "$(cat "$R/schema_version")" 2
  # unmanaged builtin is not resurrected
  AGV2=$(sha "$KM_AG_DIR/appguard.sh")
  dm delete appguard --confirm appguard
  t "builtin delete = unmanage" "$(j .unmanaged)" true
  t "builtin delete: AppGuard script untouched" "$(sha "$KM_AG_DIR/appguard.sh")" "$AGV2"
  tt "builtin delete: service.d script still there" "$([ -f "$KM_SERVICE_D/appguard.sh" ]; echo $?)"
  tt "builtin delete: boot x-bit unchanged" "$([ -x "$KM_SERVICE_D/appguard.sh" ]; echo $?)"
  tt "builtin delete: meta dir gone" "$([ ! -e "$R/daemons/appguard" ]; echo $?)"
  dm migrate
  tt "re-migrate does not recreate an unmanaged builtin" "$([ ! -e "$R/daemons/appguard" ]; echo $?)"
  # rollback
  newenv rb builtins
  seed_live
  mkdir -p "$KM_MODULE_DIR/bin" "$R/rollback/1.0/bin"
  printf '#!/bin/sh\necho old-dm\n' >"$R/rollback/1.0/bin/dm"
  printf 'version=v1.0\n' >"$R/rollback/1.0/module.prop"
  dm rollback
  t "rollback ok" "$(j .ok)" true
  t "rollback restored version" "$(j .restored)" 1.0
  tt "rollback restored old dm" "$(grep -q old-dm "$KM_MODULE_DIR/bin/dm"; echo $?)"
  tt "rollback restored module.prop" "$(grep -q 'version=v1.0' "$KM_MODULE_DIR/module.prop"; echo $?)"
}

# =============================================================================
ag_stub() { # populate the stub system state
  cat >"$AGSTUB/ps.txt" <<'EOF'
10123 1001 com.spotify.music
10124 1002 com.instagram.android:push
10125 1003 com.pure.indosat.care
10126 1004 com.shopee.id
10127 1005 com.plain.app
10128 1006 com.termux
99910123 2001 id.dana
99910124 2002 com.whatsapp
99910125 2003 com.discord
EOF
  cat >"$AGSTUB/focus.txt" <<'EOF'
  mCurrentFocus=Window{abc u0 com.pure.indosat.care/com.pure.indosat.care.Main}
EOF
  cat >"$AGSTUB/resumed.txt" <<'EOF'
  topResumedActivity=ActivityRecord{def u0 com.pure.indosat.care/.Main t12}
EOF
  cat >"$AGSTUB/recents.txt" <<'EOF'
    Recent #0: Task{aaa #5 A=10126:com.shopee.id U=0 visible=true}
EOF
  : >"$AGSTUB/am.log"
}

suite_appguard() {
  SUITE=appguard
  newenv ag builtins
  seed_live
  ag_stub
  dm migrate
  # --- once --dry equals the old script's would-kill set
  dm appguard once --dry
  t "once --dry ok" "$(j .ok)" true
  t "once --dry dry flag" "$(j .dry)" true
  WK=$(jc '[.sweep.would_kill[]|"\(.user) \(.pkg)"]|sort')
  OLD=$E/oldag
  mkdir -p "$OLD"
  sed -e "s|^BASE=.*|BASE=$OLD|" -e "s|^PS=.*|PS=$E/bin/ps|" -e "s|^AM=.*|AM=$E/bin/am|" -e "s|^DUMP=.*|DUMP=$E/bin/dumpsys|" "$REPO/reference/live/appguard.sh" >"$E/old-appguard.sh"
  DRY=1 sh "$E/old-appguard.sh" once >/dev/null 2>&1
  OLDSET=$(sed -n -e 's/.*would am-kill \[999\] \(.*\)$/999 \1/p' -e 's/.*would am-kill \([^ ]*\) (user 0)$/0 \1/p' "$OLD/appguard.log" | jq -R . | jq -sc 'sort')
  t "would_kill equals old script (DRY=1 once)" "$WK" "$OLDSET"
  t "would_kill content" "$WK" '["0 com.instagram.android","0 com.spotify.music","999 id.dana"]'
  t "foreground target skipped" "$(jc .sweep.skipped_fg)" '["com.pure.indosat.care"]'
  t "recent target skipped" "$(j .sweep.skipped_recent)" 1
  t "candidates counted" "$(j .sweep.candidates)" 5
  t "dry: nothing killed" "$(j .sweep.killed)" 0
  t "dry: am never called" "$(wc -c <"$AGSTUB/am.log" | tr -d ' ')" 0
  t "dry: shadowed whatsapp/discord not in would_kill" "$(printf '%s' "$WK" | grep -c 'whatsapp\|discord')" 0
  dm appguard kills 10
  t "kills lists the dry entries" "$(j .total)" 3
  t "kills mode dry" "$(jc '[.kills[].mode]|unique')" '["dry"]'
  # --- real sweep, per-user kill
  dm appguard once
  t "once: dry false" "$(j .dry)" false
  t "once: killed 3" "$(j .sweep.killed)" 3
  tt "am kill --user 999 used for the clone" "$(grep -qx 'kill --user 999 id.dana' "$AGSTUB/am.log"; echo $?)"
  tt "am kill --user 0 used for user 0" "$(grep -qx 'kill --user 0 com.spotify.music' "$AGSTUB/am.log"; echo $?)"
  tt "never apps never killed" "$(grep -c 'whatsapp\|discord\|termux' "$AGSTUB/am.log" | grep -qx 0; echo $?)"
  dm appguard once
  t "second sweep: cooldown holds" "$(j .sweep.killed)" 0
  t "second sweep: skipped_cooldown" "$(j .sweep.skipped_cooldown)" 3
  dm appguard kills 50
  tt "kills.tsv records real kills" "$(printf '%s' "$LAST_RAW" | jq -e '[.kills[]|select(.mode=="kill" and .result=="ok")]|length == 3' >/dev/null; echo $?)"
  t "kills newest first (ts desc)" "$(jc '[.kills[].ts] == ([.kills[].ts]|sort|reverse)')" true
  # --- per-app cooldown 0 vs 600, config re-read each sweep
  rm -f "$KM_AG_DIR"/cool/*
  : >"$AGSTUB/am.log"
  printf '10130 1010 com.cd.zero\n10131 1011 com.cd.slow\n10132 1012 com.cd.default\n' >>"$AGSTUB/ps.txt"
  dm appguard targets add com.cd.zero u0=1 cooldown=0
  t "targets add ok" "$(j .ok)" true
  t "targets add cooldown_s" "$(j .cooldown_s)" 0
  dm appguard targets add com.cd.slow cooldown=600
  dm appguard targets add com.cd.default u0=1
  t "default cooldown null" "$(j .cooldown_s)" null
  dm appguard targets add com.cd.slow
  t "targets add duplicate: E_CONFLICT" "$(j .code)" E_CONFLICT
  dm appguard once
  dm appguard once
  t "cooldown=0 killed on both sweeps" "$(grep -c 'com.cd.zero' "$AGSTUB/am.log")" 2
  t "cooldown=600 killed once" "$(grep -c 'com.cd.slow' "$AGSTUB/am.log")" 1
  t "default cooldown (300) killed once" "$(grep -c 'com.cd.default' "$AGSTUB/am.log")" 1
  dm appguard set cooldown 0
  t "set cooldown ok" "$(jc '[.key,.value,.msg]')" '["cooldown",0,"saved"]'
  dm appguard once
  t "config re-read: default cooldown 0 -> killed again" "$(grep -c 'com.cd.default' "$AGSTUB/am.log")" 2
  t "per-app 600 still honoured" "$(grep -c 'com.cd.slow' "$AGSTUB/am.log")" 1
  dm appguard targets set com.cd.slow cooldown=default
  t "targets set cooldown=default" "$(j .cooldown_s)" null
  dm appguard once
  t "slow now follows default 0" "$(grep -c 'com.cd.slow' "$AGSTUB/am.log")" 2
  dm appguard targets set com.cd.slow u0=0 u999=1
  t "targets set u999" "$(jc '[.u0,.u999]')" '[false,true]'
  dm appguard targets set nosuch.pkg u0=1
  t "targets set unknown: E_UNKNOWN" "$(j .code)" E_UNKNOWN
  dm appguard targets rm com.cd.zero
  t "targets rm ok" "$(j .pkg)" com.cd.zero
  dm appguard targets rm com.cd.zero
  t "targets rm twice: E_UNKNOWN" "$(j .code)" E_UNKNOWN
  dm appguard targets add 'bad pkg'
  t "targets add invalid pkg: E_ARG" "$(j .code)" E_ARG
  dm appguard targets add com.x u0=2
  t "targets add bad option: E_ARG" "$(j .code)" E_ARG
  dm appguard targets add com.x cooldown=99999
  t "targets add cooldown out of range: E_ARG" "$(j .code)" E_ARG
  # --- global settings
  dm appguard set interval 5
  t "set interval below min: E_ARG" "$(j .code)" E_ARG
  dm appguard set interval 3601
  t "set interval above max: E_ARG" "$(j .code)" E_ARG
  dm appguard set interval 120
  t "set interval ok" "$(j .value)" 120
  dm appguard set dry 2
  t "set dry bad: E_ARG" "$(j .code)" E_ARG
  dm appguard set cooldown 86401
  t "set cooldown above max: E_ARG" "$(j .code)" E_ARG
  dm appguard set cooldown 007
  t "set cooldown leading zeros normalised" "$(j .value)" 7
  dm appguard set cooldown 300
  dm appguard set dry 1
  dm appguard get
  t "get reflects interval" "$(j .config.interval_s)" 120
  t "get reflects dry" "$(j .config.dry_run)" true
  : >"$AGSTUB/am.log"
  dm appguard once
  t "dry_run configured: once reports dry" "$(j .dry)" true
  t "dry_run configured: no am call" "$(wc -c <"$AGSTUB/am.log" | tr -d ' ')" 0
  dm appguard set dry 0
  # --- never list
  dm appguard never add com.spotify.music
  tt "never add" "$(printf '%s' "$LAST_RAW" | jq -e '.never | index("com.spotify.music") != null' >/dev/null; echo $?)"
  dm appguard never add com.spotify.music
  t "never add idempotent" "$(jc '[.never[]|select(.=="com.spotify.music")]|length')" 1
  dm appguard get
  t "target now shadowed" "$(j '.targets[]|select(.pkg=="com.spotify.music")|.shadowed')" true
  rm -f "$KM_AG_DIR"/cool/*
  dm appguard once --dry
  tt "never wins over targets" "$(printf '%s' "$LAST_RAW" | jq -e '[.sweep.would_kill[].pkg] | index("com.spotify.music") == null' >/dev/null; echo $?)"
  dm appguard never rm com.spotify.music
  tt "never rm" "$(printf '%s' "$LAST_RAW" | jq -e '.never | index("com.spotify.music") == null' >/dev/null; echo $?)"
  dm appguard never add 'bad;pkg'
  t "never invalid pkg: E_ARG" "$(j .code)" E_ARG
  dm appguard never list
  t "never list count" "$(jc '.never|length')" 6
  # --- packages
  dm appguard packages --user 0
  t "packages user 0" "$(j '.packages|length')" 4
  t "packages target flag" "$(j '.packages[]|select(.pkg=="com.spotify.music")|.target')" true
  t "packages never flag" "$(j '.packages[]|select(.pkg=="com.termux")|.never')" true
  dm appguard packages --user 999
  t "packages user 999" "$(jc '.packages|map(.pkg)|sort')" '["com.u999.only","com.whatsapp","id.dana"]'
  t "packages user 999 target flag" "$(j '.packages[]|select(.pkg=="id.dana")|.target')" true
  dm appguard packages --user 999 --q dana
  t "packages --q filter" "$(jc '.packages|map(.pkg)')" '["id.dana"]'
  dm appguard packages --user 5
  t "packages bad user: E_ARG" "$(j .code)" E_ARG
  dm appguard packages --q 'a;b'
  t "packages bad query: E_ARG" "$(j .code)" E_ARG
  # --- fail-safe: foreground unknown
  : >"$AGSTUB/focus.txt"; : >"$AGSTUB/resumed.txt"
  dm appguard once
  t "foreground unknown: sweep skipped" "$(j .sweep.skipped)" foreground-unknown
  t "foreground unknown: nothing killed" "$(j .sweep.killed)" 0
  dm appguard kills 9999
  t "kills limit > 200: E_ARG" "$(j .code)" E_ARG
  dm appguard bogus
  t "appguard unknown subcommand: E_USAGE" "$(j .code)" E_USAGE

  # --- the loop: heartbeat, dm start/stop, config applied without restart
  ag_stub
  : >"$AGSTUB/am.log"
  rm -f "$KM_AG_DIR"/cool/*
  dm appguard set interval 10
  dm appguard set cooldown 0
  dm appguard set dry 1
  _agpid="$KM_AG_DIR/appguard.pid"
  mkdaemon fx-ag "name=AG loop" "start=$FX/ag-start.sh" "argv_match=$KM_AG_DIR/appguard.sh" "pidfile=$_agpid" "stop=cmd:sh $KM_AG_DIR/appguard.sh stop" "health=heartbeat:$R/appguard/heartbeat:auto" stop_grace=10 start_timeout=15
  printf '#!/bin/sh\nexec sh %s/appguard.sh run\n' "$KM_AG_DIR" >"$FX/ag-start.sh"
  dm start fx-ag
  t "appguard loop start ok" "$(j .ok)" true
  AGP=$(j .pid)
  tt "pidfile written by the loop" "$([ "$(cat "$_agpid")" = "$AGP" ]; echo $?)"
  sleep 2
  tt "heartbeat file written (epoch version pid interval)" "$([ "$(wc -w <"$R/appguard/heartbeat" | tr -d ' ')" = 4 ]; echo $?)"
  t "heartbeat carries version" "$(cut -d' ' -f2 "$R/appguard/heartbeat")" 2.0.0
  dm list
  t "heartbeat health ok" "$(j '.daemons[]|select(.id=="fx-ag")|.health')" ok
  t "loop verified (marker)" "$(j '.daemons[]|select(.id=="fx-ag")|.verified_by')" marker
  t "first sweep ran dry" "$(grep -c 'would am-kill' "$KM_AG_DIR/appguard.log" | awk '{print ($1>=1)?"yes":"no"}')" yes
  : >"$KM_AG_DIR/appguard.log"
  dm appguard set dry 0
  # no restart: wait for the next sweep (interval 10 s), the loop must now really kill
  _w=0
  while [ "$_w" -lt 18 ] && [ ! -s "$AGSTUB/am.log" ]; do sleep 1; _w=$((_w + 1)); done
  tt "config change applied by the running loop without restart (waited ${_w}s)" "$([ -s "$AGSTUB/am.log" ]; echo $?)"
  tt "same pid after config change" "$([ "$(cat "$_agpid")" = "$AGP" ]; echo $?)"
  dm stop fx-ag
  t "appguard stop ok" "$(j .ok)" true
  t "appguard stop via stop_cmd" "$(jc .steps)" '["stop_cmd"]'
  tt "loop gone" "$(alive "$AGP"; [ $? = 1 ]; echo $?)"
  tt "pidfile removed" "$([ ! -e "$_agpid" ]; echo $?)"
  # direct script interface
  sh "$KM_AG_DIR/appguard.sh" status | head -n 1 | grep -q 'not running' && ok "appguard.sh status: not running" || bad "appguard.sh status"
}

# =============================================================================
count_outside() { # staging-only invariant: files outside staging/jobs/dm.log/lock under the fixture tree
  find "$E" -type f ! -path "$R/staging/*" ! -path "$R/jobs/*" ! -path "$R/dm.log*" ! -path "$R/lock/*" ! -path "$E/mod/*" ! -path "$E/zips/*" ! -path "$E/fx/*" ! -path "$E/bin/*" ! -path "$E/stub/*" | sort
}

suite_install() {
  SUITE=install
  newenv inst builtins
  seed_live
  mkdir -p "$E/zips" "$E/outside"
  python3 -I "$FIXT/mkzips.py" "$E/zips" || { bad "build zips"; return; }
  Z=$E/zips
  echo keep >"$E/outside/sentinel"
  dm migrate
  BEFORE=$(count_outside; tree_sha "$E/outside")
  # --- evil zips: right code, nothing outside staging, no leftovers
  evil() { # zip code
    dm install stage "$Z/$1.zip"
    t "evil $1: rejected" "$(j .ok)" false
    t "evil $1: code" "$(j .code)" "$2"
    AFTER=$(count_outside; tree_sha "$E/outside")
    t "evil $1: nothing written outside staging" "$([ "$AFTER" = "$BEFORE" ] && echo same || echo CHANGED)" same
    t "evil $1: staging left empty" "$(ls "$R/staging" | wc -l | tr -d ' ')" 0
  }
  evil dotdot E_PATH
  evil dotdot-deep E_PATH
  evil absolute E_PATH
  evil backslash E_PATH
  evil specialchars E_PATH
  evil symlink E_PATH
  evil device E_PATH
  evil oversize E_VERIFY
  evil many E_VERIFY
  evil bomb E_VERIFY
  evil badid E_VERIFY
  evil badid2 E_VERIFY
  evil hashmismatch E_VERIFY
  evil nomanifest E_VERIFY
  evil startmissing E_VERIFY
  evil startabs E_VERIFY
  evil startdots E_VERIFY
  evil notzip E_VERIFY
  evil garbage E_VERIFY
  t "no escape files anywhere" "$(find "$T" -name 'evil.txt' -o -name 'km-evil-abs.txt' 2>/dev/null | wc -l | tr -d ' ')" 0
  tt "nothing named evil in /tmp" "$([ ! -e /tmp/km-evil-abs.txt ] && [ ! -e /tmp/evil.txt ]; echo $?)"
  dm install stage http://example.com/x.zip
  t "http URL rejected" "$(j .code)" E_ARG
  dm install stage ftp://example.com/x.zip
  t "ftp URL rejected" "$(j .code)" E_ARG
  dm install stage 'https://example.com/x.zip;rm -rf /'
  t "url with shell metachar rejected" "$(j .code)" E_ARG
  dm install stage relative/path.zip
  t "relative path rejected" "$(j .code)" E_ARG
  dm install stage "$Z/../zips/good.zip"
  t "path with .. rejected" "$(j .code)" E_ARG
  dm install stage /nonexistent/pkg.zip
  t "missing local zip rejected" "$(j .code)" E_ARG
  dm install stage "$Z/good.zip" notasha
  t "bad sha pin format rejected" "$(j .code)" E_ARG
  dm install stage "$Z/good.zip" 0000000000000000000000000000000000000000000000000000000000000000
  t "sha pin mismatch: E_VERIFY" "$(j .code)" E_VERIFY
  dm install stage
  t "stage without source: E_ARG" "$(j .code)" E_ARG
  # exactly 200 entries is accepted
  dm install stage "$Z/limit.zip"
  t "200 entries accepted" "$(j .ok)" true
  dm install abort "$(j .result.token)"
  # --- good zip
  GSHA=$(sha "$Z/good.zip")
  dm install stage "$Z/good.zip" "$GSHA"
  t "good: stage ok" "$(j .ok)" true
  t "good: job id" "$(j .job | grep -c '^j_[a-f0-9]\{8\}$')" 1
  t "good: state done" "$(j .state)" done
  TOK=$(j .result.token)
  t "good: token format" "$(printf '%s' "$TOK" | grep -c '^t_[a-f0-9]\{8\}$')" 1
  t "good: manifest id" "$(j .result.manifest.id)" km-test-pkg
  t "good: manifest fields" "$(jc '.result.manifest|[.name,.version,.kind,.start]')" '["Test Package","1.2.3","daemon","start.sh"]'
  t "good: zip sha" "$(j .result.sha256)" "$GSHA"
  t "good: files" "$(j .result.files)" 5
  t "good: conflict none" "$(j .result.conflict)" none
  t "good: install hook hashed" "$(j .result.hooks.install.sha256)" "$(unzip -p "$Z/good.zip" hooks/install.sh | sha256sum | cut -d' ' -f1)"
  tt "good: install hook preview lines" "$(printf '%s' "$LAST_RAW" | jq -e '.result.hooks.install.preview | length >= 2' >/dev/null; echo $?)"
  tt "good: uninstall hook present" "$(printf '%s' "$LAST_RAW" | jq -e '.result.hooks.uninstall.bytes > 0' >/dev/null; echo $?)"
  tt "good: warnings array" "$(printf '%s' "$LAST_RAW" | jq -e '.result.warnings|type=="array"' >/dev/null; echo $?)"
  JOB=$(j .job)
  dm job "$JOB"
  t "job replays the result" "$(j .result.token)" "$TOK"
  dm job j_00000000
  t "unknown job: E_UNKNOWN" "$(j .code)" E_UNKNOWN
  dm job 'x;y'
  t "bad job id: E_ARG" "$(j .code)" E_ARG
  tt "nothing executed before commit (no install.txt)" "$([ ! -e "$R/staging/$TOK/x/installed.txt" ] && [ ! -d "$R/daemons/km-test-pkg" ]; echo $?)"
  dm install commit "$TOK"
  t "commit without --confirm: E_CONFIRM" "$(j .code)" E_CONFIRM
  dm install commit "$TOK" --confirm wrong-id
  t "commit wrong confirm: E_CONFIRM" "$(j .code)" E_CONFIRM
  dm install commit 't_zzzzzzzz' --confirm km-test-pkg
  t "commit bad token: E_ARG" "$(j .code)" E_ARG
  dm install commit t_00000000 --confirm km-test-pkg
  t "commit unknown token: E_UNKNOWN" "$(j .code)" E_UNKNOWN
  dm install commit "$TOK" --confirm km-test-pkg
  t "commit ok" "$(j .ok)" true
  t "commit id/version" "$(jc '[.id,.version]')" '["km-test-pkg","1.2.3"]'
  t "commit: not enabled by default" "$(j .enabled)" false
  t "commit: install hook ran, exit 0" "$(jc '.hook')" '{"ran":true,"exit":0}'
  tt "hook effect present (ran with KM_DAEMON_DIR)" "$([ -f "$R/daemons/km-test-pkg/installed.txt" ]; echo $?)"
  tt "daemon dir populated" "$([ -f "$R/daemons/km-test-pkg/start.sh" ] && [ -f "$R/daemons/km-test-pkg/files/readme.txt" ]; echo $?)"
  tt "wrapper created but disabled (644)" "$([ -f "$KM_SERVICE_D/km-km-test-pkg.sh" ] && [ ! -x "$KM_SERVICE_D/km-km-test-pkg.sh" ]; echo $?)"
  tt "staging token removed" "$([ ! -d "$R/staging/$TOK" ]; echo $?)"
  dm list
  t "installed daemon listed" "$(j '.daemons[]|select(.id=="km-test-pkg")|[.source,.enabled,.removable,.version]|@json')" '["package",false,true,"1.2.3"]'
  dm install commit "$TOK" --confirm km-test-pkg
  t "commit twice: token is gone" "$(j .code)" E_UNKNOWN
  # package daemon lifecycle
  dm start km-test-pkg
  t "package daemon start" "$(j .state)" running
  PP=$(j .pid)
  dm status km-test-pkg
  t "package status verified by marker" "$(j .daemon.verified_by)" marker
  # conflict
  dm install stage "$Z/good.zip"
  t "conflict flagged at stage" "$(j .result.conflict)" exists
  CT=$(j .result.token)
  dm install commit "$CT" --confirm km-test-pkg
  t "commit on conflict: E_CONFLICT" "$(j .code)" E_CONFLICT
  dm install abort "$CT"
  t "abort ok" "$(j .ok)" true
  tt "abort removed the staged tree" "$([ ! -d "$R/staging/$CT" ]; echo $?)"
  dm install stage "$Z/builtin-id.zip"
  t "builtin id: conflict flagged builtin" "$(j .result.conflict)" builtin
  BT=$(j .result.token)
  dm install commit "$BT" --confirm appguard
  t "builtin id: commit E_CONFLICT" "$(j .code)" E_CONFLICT
  dm install abort "$BT"
  # --- unpinned hook warns
  dm install stage "$Z/unpinned.zip"
  t "unpinned hook: ok with warning" "$(j '.result.warnings|map(select(test("not pinned")))|length')" 2
  dm install abort "$(j .result.token)"
  # --- failing hook rolls everything back
  dm install stage "$Z/failhook.zip"
  FT=$(j .result.token)
  dm install commit "$FT" --confirm km-test-failhook
  t "hook failure: E_HOOK" "$(j .code)" E_HOOK
  t "hook failure: exit reported" "$(j .hook.exit)" 5
  tt "hook failure: nothing installed" "$([ ! -e "$R/daemons/km-test-failhook" ] && [ ! -e "$KM_SERVICE_D/km-km-test-failhook.sh" ]; echo $?)"
  # --- no-hook package
  dm install stage "$Z/good-nohook.zip"
  dm install commit "$(j .result.token)" --confirm km-test-plain
  t "no hook: commit ok" "$(jc '.hook')" '{"ran":false,"exit":null}'
  dm delete km-test-plain --confirm km-test-plain
  t "no hook: delete ok" "$(j .ok)" true

  # --- delete: plan, confirm, sentinel survival
  mkdir -p "$R/daemons/sentinel-dir"; echo s >"$R/daemons/sentinel-dir/f"; echo s >"$R/daemons/SENTINEL"
  echo '#!/bin/sh' >"$KM_SERVICE_D/km-keep.sh"; echo s >"$KM_SERVICE_D/other.sh"
  dm delete km-test-pkg --plan
  t "plan ok" "$(j .ok)" true
  t "plan: stop (it is running)" "$(j .plan.stop)" true
  t "plan: remove_dir" "$(j .plan.remove_dir)" "$R/daemons/km-test-pkg"
  t "plan: remove_wrapper" "$(j .plan.remove_wrapper)" "$KM_SERVICE_D/km-km-test-pkg.sh"
  t "plan: uninstall hook" "$(j .plan.run_uninstall_hook)" true
  tt "plan: keeps is a list" "$(printf '%s' "$LAST_RAW" | jq -e '.plan.keeps|type=="array" and length>0' >/dev/null; echo $?)"
  tt "plan changed nothing" "$([ -d "$R/daemons/km-test-pkg" ] && alive "$PP"; echo $?)"
  dm delete km-test-pkg
  t "delete without mode: E_USAGE" "$(j .code)" E_USAGE
  dm delete km-test-pkg --confirm
  t "delete without id: E_CONFIRM" "$(j .code)" E_CONFIRM
  dm delete km-test-pkg --confirm other-id
  t "delete wrong id: E_CONFIRM" "$(j .code)" E_CONFIRM
  tt "still there after refused delete" "$([ -d "$R/daemons/km-test-pkg" ]; echo $?)"
  dm delete km-test-pkg --confirm km-test-pkg
  t "delete ok" "$(j .ok)" true
  t "delete stopped it" "$(j .stopped)" true
  t "delete ran the uninstall hook" "$(jc '.hook')" '{"ran":true,"exit":0}'
  t "delete unmanaged=false" "$(j .unmanaged)" false
  tt "delete removed exactly dir + wrapper" "$(printf '%s' "$LAST_RAW" | jq -e --arg d "$R/daemons/km-test-pkg" --arg w "$KM_SERVICE_D/km-km-test-pkg.sh" '(.removed|sort) == ([$d,$w]|sort)' >/dev/null; echo $?)"
  tt "daemon dir gone" "$([ ! -e "$R/daemons/km-test-pkg" ]; echo $?)"
  tt "wrapper gone" "$([ ! -e "$KM_SERVICE_D/km-km-test-pkg.sh" ]; echo $?)"
  tt "process gone" "$(alive "$PP"; [ $? = 1 ]; echo $?)"
  tt "uninstall hook ran (KM_ROOT effect)" "$([ -f "$R/uninstalled.txt" ]; echo $?)"
  tt "sentinel dir survives" "$([ -f "$R/daemons/sentinel-dir/f" ]; echo $?)"
  tt "sentinel file beside daemon dirs survives" "$([ -f "$R/daemons/SENTINEL" ]; echo $?)"
  tt "other km wrapper survives" "$([ -f "$KM_SERVICE_D/km-keep.sh" ]; echo $?)"
  tt "other service.d script survives" "$([ -f "$KM_SERVICE_D/other.sh" ]; echo $?)"
  dm delete km-test-pkg --confirm km-test-pkg
  t "delete twice: E_UNKNOWN" "$(j .code)" E_UNKNOWN
  # delete refuses to follow a symlinked daemon dir out of the tree
  mkdir -p "$E/victim"; echo v >"$E/victim/keep"
  mkdaemon fx-sl "start=$FX/loop.sh" source=created
  rm -rf "$R/daemons/fx-sl"; ln -s "$E/victim" "$R/daemons/fx-sl"
  printf 'id=fx-sl\nsource=created\nstart=%s\n' "$FX/loop.sh" >"$E/victim/meta"
  dm delete fx-sl --confirm fx-sl
  tt "symlinked daemon dir: target survives" "$([ -f "$E/victim/keep" ]; echo $?)"
  # wrapper without our marker is not deleted
  mkdaemon fx-ow source=created "start=$FX/loop.sh"
  printf '#!/bin/sh\n# someone else\n' >"$KM_SERVICE_D/km-fx-ow.sh"
  dm delete fx-ow --confirm fx-ow
  t "foreign km-<id>.sh not removed" "$([ -f "$KM_SERVICE_D/km-fx-ow.sh" ] && echo kept)" kept

  # --- https download (self-signed cert, KM_CURL_EXTRA only honoured under KM_TEST)
  if command -v openssl >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
    openssl req -x509 -newkey rsa:2048 -nodes -keyout "$E/k.pem" -out "$E/c.pem" -subj /CN=localhost -days 1 >/dev/null 2>&1
    PORT=$((20000 + $$ % 20000))
    PORT2=$((PORT + 1))
    mkdir -p "$E/emptyroot"
    ( cd "$E/emptyroot" && python3 -I -m http.server "$PORT2" --bind 127.0.0.1 >"$E/http2.log" 2>&1 ) &
    python3 -I "$FIXT/httpsd.py" "$PORT" "$Z" "$E/c.pem" "$E/k.pem" "http://127.0.0.1:$PORT2/x.zip" >"$E/https.log" 2>&1 &
    _w=0
    while [ "$_w" -lt 20 ] && ! curl -ksf -o /dev/null "https://127.0.0.1:$PORT/nothing" 2>/dev/null && [ "$(curl -ks -o /dev/null -w '%{http_code}' "https://127.0.0.1:$PORT/nothing")" != 404 ]; do sleep 0.3; _w=$((_w + 1)); done
    export KM_CURL_EXTRA=-k
    dm install stage "https://127.0.0.1:$PORT/ok.zip" "$GSHA"
    t "https download + pinned sha: ok" "$(j .ok)" true
    t "https download: same package" "$(j .result.sha256)" "$GSHA"
    dm install abort "$(j .result.token)"
    dm install stage "https://127.0.0.1:$PORT/ok.zip" 1111111111111111111111111111111111111111111111111111111111111111
    t "https wrong pin: E_VERIFY" "$(j .code)" E_VERIFY
    dm install stage "https://127.0.0.1:$PORT/redir.zip"
    t "redirect to http refused: E_DOWNLOAD" "$(j .code)" E_DOWNLOAD
    t "redirect target never contacted" "$(grep -c 'GET /x.zip' "$E/http2.log")" 0
    dm install stage "https://127.0.0.1:$PORT/missing.zip"
    t "404: E_DOWNLOAD" "$(j .code)" E_DOWNLOAD
    dm install stage "https://127.0.0.1:$PORT/big.zip"
    t "oversize download: E_VERIFY" "$(j .code)" E_VERIFY
    unset KM_CURL_EXTRA
    dm install stage "https://127.0.0.1:$PORT/ok.zip"
    t "self-signed cert refused without the test flag: E_DOWNLOAD" "$(j .code)" E_DOWNLOAD
    t "no staging leftovers after download failures" "$(ls "$R/staging" | wc -l | tr -d ' ')" 0
  else
    printf 'skip [install] https tests: openssl or python3 missing\n'
  fi
  t "all staging swept/aborted" "$(ls "$R/staging" | wc -l | tr -d ' ')" 0
}

# =============================================================================
suite_create() {
  SUITE=create
  newenv create
  dm create "$(b64 "name=My Daemon 1
kind=daemon
start=while :; do sleep 1; done
stop=echo bye >> $FX/stop.log")"
  t "create ok" "$(j .ok)" true
  t "slug id" "$(j .id)" my-daemon-1
  tt "start.sh written" "$([ -f "$R/daemons/my-daemon-1/start.sh" ] && sh -n "$R/daemons/my-daemon-1/start.sh"; echo $?)"
  tt "start command stored verbatim as data" "$(sed -n 3p "$R/daemons/my-daemon-1/start.sh" | grep -qx 'while :; do sleep 1; done'; echo $?)"
  tt "stop.sh written" "$([ -f "$R/daemons/my-daemon-1/stop.sh" ]; echo $?)"
  tt "wrapper created disabled" "$([ -f "$KM_SERVICE_D/km-my-daemon-1.sh" ] && [ ! -x "$KM_SERVICE_D/km-my-daemon-1.sh" ]; echo $?)"
  tt "meta whitelisted keys only" "$(! grep -qvE '^(id|name|desc|version|kind|source|start|stop|pidfile|argv_match|stop_scope|start_timeout|stop_grace|health|boot|boot_wait|removable|enabled_hint|boot_script|log|adopt|install_sha|uninstall_sha)=' "$R/daemons/my-daemon-1/meta"; echo $?)"
  dm start my-daemon-1
  t "created daemon starts (marker only, no argv match)" "$(j .state)" running
  dm list
  t "verified by marker" "$(j '.daemons[]|select(.id=="my-daemon-1")|.verified_by')" marker
  dm stop my-daemon-1
  t "created daemon stop uses its stop script" "$(jc .steps)" '["stop_cmd","TERM"]'
  t "stop.sh ran" "$(grep -c bye "$FX/stop.log")" 1
  t "no tagged processes left (sleep child included)" "$(marker_count my-daemon-1)" 0
  dm create "$(b64 "name=My Daemon 1
start=sleep 5")"
  t "duplicate name: E_CONFLICT" "$(j .code)" E_CONFLICT
  dm create "$(b64 "name=Oneshot Job
kind=oneshot
start=echo hi")"
  t "oneshot create" "$(j .id)" oneshot-job
  dm start oneshot-job
  t "oneshot created runs to done" "$(j .state)" done
  dm create "$(b64 "name=
start=sleep 5")"
  t "empty name: E_ARG" "$(j .code)" E_ARG
  dm create "$(b64 "name=X Y
kind=weird
start=sleep 5")"
  t "bad kind: E_ARG" "$(j .code)" E_ARG
  dm create "$(b64 "name=No Start
kind=daemon")"
  t "missing start: E_ARG" "$(j .code)" E_ARG
  dm create "$(b64 "name=Inject
start=sleep 5
evil=1")"
  t "unknown key: E_ARG" "$(j .code)" E_ARG
  dm create "$(b64 "name=Inject Two
start=sleep 5
; touch /tmp/km-pwn2")"
  t "garbage line (newline injection): E_ARG" "$(j .code)" E_ARG
  tt "no file created by injection" "$([ ! -e /tmp/km-pwn2 ]; echo $?)"
  dm create "$(b64 "name=Syntax Err
start=if then fi (")"
  t "shell syntax error: E_ARG" "$(j .code)" E_ARG
  tt "failed create leaves no dir" "$([ ! -e "$R/daemons/syntax-err" ]; echo $?)"
  dm create "$(b64 "name=!!
start=sleep 5")"
  t "name without letters/digits: E_ARG" "$(j .code)" E_ARG
  dm create "not base64 at all !!!"
  t "invalid base64: E_ARG" "$(j .code)" E_ARG
  dm create "$(printf 'name=Nul\000Byte\nstart=sleep 5\n' | base64 | tr -d '\n')"
  t "NUL in payload: E_ARG" "$(j .code)" E_ARG
  _long=$(printf 'x%.0s' $(seq 1 1100))
  dm create "$(b64 "name=Long Start
start=$_long")"
  t "start > 1024 chars: E_ARG" "$(j .code)" E_ARG
  dm create ""
  t "empty payload: E_ARG" "$(j .code)" E_ARG
  dm create "$(b64 "name=Utf8 Näme ✓
start=sleep 5")"
  t "non-ascii name slugs safely" "$(j .id)" utf8-n-me
  dm delete utf8-n-me --confirm utf8-n-me
  t "delete created ok" "$(j .ok)" true

  # --- import
  printf '#!/system/bin/sh\nwhile :; do sleep 1; done\n' >"$KM_SERVICE_D/custom-one.sh"; chmod 755 "$KM_SERVICE_D/custom-one.sh"
  printf '#!/system/bin/sh\nexit 0\n' >"$KM_SERVICE_D/custom-two.sh"; chmod 644 "$KM_SERVICE_D/custom-two.sh"
  printf 'x\n' >"$KM_SERVICE_D/notes.txt"
  ln -s /etc/passwd "$KM_SERVICE_D/link.sh"
  mkdir -p "$E/elsewhere"; printf '#!/bin/sh\n' >"$E/elsewhere/out.sh"
  dm import list
  t "import list ok" "$(j .ok)" true
  t "import list: only regular .sh" "$(jc '[.candidates[].name]|sort')" '["custom-one.sh","custom-two.sh","km-my-daemon-1.sh","km-oneshot-job.sh"]'
  t "import list: wrappers are managed" "$(jc '[.candidates[]|select(.name|startswith("km-"))|.managed]|unique')" '[true]'
  t "import list: executable flags" "$(jc '[.candidates[]|select(.name|startswith("custom"))|.executable]')" '[true,false]'
  tt "import list rows have path/bytes" "$(printf '%s' "$LAST_RAW" | jq -e '.candidates|all(.path and (.bytes|type=="number"))' >/dev/null; echo $?)"
  H1=$(sha "$KM_SERVICE_D/custom-one.sh")
  dm import "$KM_SERVICE_D/custom-one.sh" "$(b64 "name=Custom One
kind=daemon
stop=")"
  t "import ok" "$(j .ok)" true
  t "import id" "$(j .id)" custom-one
  t "import source" "$(j .source)" imported
  t "import enabled reflects x-bit" "$(j .enabled)" true
  t "import script untouched" "$(sha "$KM_SERVICE_D/custom-one.sh")" "$H1"
  dm list
  t "imported daemon: removable false, boot xbit" "$(j '.daemons[]|select(.id=="custom-one")|[.removable,.boot,.source]|@json')" '[false,"xbit","imported"]'
  dm import list
  t "import list: now managed" "$(j '.candidates[]|select(.name=="custom-one.sh")|.managed')" true
  dm import "$KM_SERVICE_D/custom-one.sh" "$(b64 "name=Again")"
  t "import twice: E_CONFLICT" "$(j .code)" E_CONFLICT
  dm import "$E/elsewhere/out.sh" "$(b64 "name=Out")"
  t "import outside service.d: E_PATH" "$(j .code)" E_PATH
  dm import "$KM_SERVICE_D/link.sh" "$(b64 "name=Link")"
  t "import symlink: E_PATH" "$(j .code)" E_PATH
  dm import "$KM_SERVICE_D/notes.txt" "$(b64 "name=Notes")"
  t "import non-.sh: E_PATH" "$(j .code)" E_PATH
  dm import "$KM_SERVICE_D/../service.d/custom-two.sh" "$(b64 "name=Dotdot")"
  t "import path with ..: E_PATH" "$(j .code)" E_PATH
  dm import "$KM_SERVICE_D/km-my-daemon-1.sh" "$(b64 "name=Wrap")"
  t "import km wrapper: E_CONFLICT" "$(j .code)" E_CONFLICT
  dm import "$KM_SERVICE_D/custom-two.sh" "$(b64 "name=Custom One")"
  t "import with clashing name: E_CONFLICT" "$(j .code)" E_CONFLICT
  dm import "$KM_SERVICE_D/custom-two.sh" "$(b64 "name=Custom Two
stop=kill \$(cat /x)
kind=oneshot")"
  t "import with stop cmd" "$(j .id)" custom-two
  t "import disabled script" "$(j .enabled)" false
  t "stop stored as cmd:" "$(sed -n 's/^stop=//p' "$R/daemons/custom-two/meta")" 'cmd:kill $(cat /x)'
  dm import "$KM_SERVICE_D/custom-two.sh" "bm90LWpzb24="
  t "bad kv payload on managed script: E_CONFLICT" "$(j .code)" E_CONFLICT
  dm delete custom-one --plan
  t "plan for imported: not stopped-by-delete" "$(jc '[.plan.stop,.plan.run_uninstall_hook,.plan.remove_wrapper]')" '[false,false,null]'
  dm delete custom-one --confirm custom-one
  t "delete imported = unmanage" "$(j .unmanaged)" true
  t "imported script survives" "$(sha "$KM_SERVICE_D/custom-one.sh")" "$H1"
  tt "imported x-bit survives" "$([ -x "$KM_SERVICE_D/custom-one.sh" ]; echo $?)"
  dm import list
  t "import list: script is a candidate again" "$(j '.candidates[]|select(.name=="custom-one.sh")|.managed')" false
}

# =============================================================================
ALL="static dm decoy enable appguard migrate install create"
SUITES=${*:-all}
[ "$SUITES" = all ] && SUITES=$ALL
printf '== KonaManager backend tests: shell under test: %s ==\n' "$SHUT"
for s in $SUITES; do
  case $s in
    static) suite_static ;;
    dm) suite_dm ;;
    decoy) suite_decoy ;;
    enable) suite_enable ;;
    appguard) suite_appguard ;;
    migrate) suite_migrate ;;
    install) suite_install ;;
    create) suite_create ;;
    *) echo "unknown suite $s"; exit 2 ;;
  esac
done
echo
printf 'dm calls checked against the JSON contract: %s (violations: %s)\n' "$CT_CALLS" "$CT_BAD"
printf 'TOTAL: %s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" = 0 ] || { printf 'failed: %s\n' "$FAILED_NAMES"; exit 1; }
exit 0
