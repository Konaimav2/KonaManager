# km-json.sh - JSON output helpers. POSIX sh, no jq, no bashisms.
# Every command ends with exactly one JSON object in $OUT; bin/dm prints it.

OUT=
JESC=

# jesc <string>: sets JESC to a JSON-safe string body (no quotes around it).
# Fast path: no fork when the value only has plain characters.
jesc() {
  case $1 in
    *[!A-Za-z0-9._/:@=+,\ -]*)
      JESC=$(printf '%s' "$1" | LC_ALL=C tr '\000-\037' ' ' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
      ;;
    *) JESC=$1 ;;
  esac
}

# err <code> <msg> [extra-json-fragment-starting-with-comma]
err() {
  jesc "$2"
  OUT="{\"ok\":false,\"code\":\"$1\",\"msg\":\"$JESC\"$3}"
  return 1
}

# ok_out <fragment-starting-with-comma or empty>
ok_out() {
  OUT="{\"ok\":true$1}"
  return 0
}

# jbool <0|1|true|false|string>: prints true/false
jbool() {
  case $1 in 1|true|yes) printf 'true' ;; *) printf 'false' ;; esac
}

# jlist_ints "1 2 3" -> [1,2,3]
jlist_ints() {
  JL=
  for _x in $1; do
    case $_x in ''|*[!0-9]*) continue ;; esac
    JL="${JL:+$JL,}$_x"
  done
  JL="[$JL]"
}

# jlist_strs <newline-separated list> -> ["a","b"]
jlist_strs() {
  JL=
  _ifs=$IFS
  IFS='
'
  set -f
  for _x in $1; do
    [ -n "$_x" ] || continue
    jesc "$_x"
    JL="${JL:+$JL,}\"$JESC\""
  done
  set +f
  IFS=$_ifs
  JL="[$JL]"
}
