# km-migrate.sh - lazy, idempotent, additive v1 -> v2 migration.
# Never edits /data/adb/service.d scripts, never touches deep-sleep-cool.conf,
# never chmods a boot script (x-bits are the enabled state and stay as they are).

MIG_ACT=
mig_act() { jesc "$1"; MIG_ACT="${MIG_ACT:+$MIG_ACT,}\"$JESC\""; }

needs_migrate() {
  _sv= _mf=
  [ -r "$R/schema_version" ] && read -r _sv <"$R/schema_version"
  [ -r "$R/migrated_for" ] && read -r _mf <"$R/migrated_for"
  [ "$_sv" = "$KM_SCHEMA" ] && [ "$_mf" = "$KM_VERSION" ] && return 1
  return 0
}

mig_conf_file() { # prints the legacy daemons.conf to read
  if [ -f "$KM_MODDIR/daemons.conf" ]; then printf '%s' "$KM_MODDIR/daemons.conf"; return 0; fi
  _best=
  for _f in "$R"/rollback/*/daemons.conf; do [ -f "$_f" ] && _best=$_f; done
  [ -n "$_best" ] && printf '%s' "$_best"
  return 0
}

# mig_parse_v1 <file>: sets V1_U0 V1_U999 V1_NEVER (space separated, validated)
mig_parse_v1() {
  V1_U0= V1_U999= V1_NEVER=
  [ -f "$1" ] || return 1
  _cur= _body=
  while IFS= read -r _line || [ -n "$_line" ]; do
    if [ -n "$_cur" ]; then
      case $_line in
        *\"*) _body="$_body ${_line%%\"*}"; mig_assign "$_cur" "$_body"; _cur= ;;
        *) _body="$_body $_line" ;;
      esac
      continue
    fi
    case $_line in
      U0=\"*|U999=\"*|NEVER=\"*)
        _name=${_line%%=*}
        _rest=${_line#*=\"}
        case $_rest in
          *\"*) mig_assign "$_name" "${_rest%%\"*}" ;;
          *) _cur=$_name; _body=$_rest ;;
        esac
        ;;
    esac
  done <"$1"
  [ -n "$V1_U0$V1_U999" ]
}
mig_assign() { # NAME body
  _out=
  set -f
  for _t in $2; do
    valid_pkg "$_t" || continue
    case " $_out " in *" $_t "*) continue ;; esac
    _out="$_out $_t"
  done
  set +f
  case $1 in
    U0) V1_U0=${_out# } ;;
    U999) V1_U999=${_out# } ;;
    NEVER) V1_NEVER=${_out# } ;;
  esac
}

# mig_seed <file>: tsv "pkg u0 u999 cooldown"; lines "#never<TAB>pkg" are never entries
mig_seed() {
  V1_U0= V1_U999= V1_NEVER=
  [ -f "$1" ] || return 1
  while IFS="$TAB" read -r _p _a _b _c || [ -n "$_p" ]; do
    case $_p in
      '#never') valid_pkg "$_a" && V1_NEVER="$V1_NEVER $_a"; continue ;;
      ''|'#'*) continue ;;
    esac
    valid_pkg "$_p" || continue
    [ "$_a" = 1 ] && V1_U0="$V1_U0 $_p"
    [ "$_b" = 1 ] && V1_U999="$V1_U999 $_p"
  done <"$1"
  V1_U0=${V1_U0# }; V1_U999=${V1_U999# }; V1_NEVER=${V1_NEVER# }
  [ -n "$V1_U0$V1_U999" ]
}

mig_counts() { # sets C_T C_U0 C_U999 C_N from V1_* lists
  C_U0=0 C_U999=0 C_N=0 C_T=0
  set -f
  for _p in $V1_U0; do C_U0=$((C_U0 + 1)); C_T=$((C_T + 1)); done
  for _p in $V1_U999; do
    C_U999=$((C_U999 + 1))
    case " $V1_U0 " in *" $_p "*) ;; *) C_T=$((C_T + 1)) ;; esac
  done
  for _p in $V1_NEVER; do C_N=$((C_N + 1)); done
  set +f
}

mig_counts_files() {
  C_T=0 C_U0=0 C_U999=0 C_N=0
  if [ -f "$R/appguard/targets.tsv" ]; then
    while IFS="$TAB" read -r _p _a _b _c || [ -n "$_p" ]; do
      [ -n "$_p" ] || continue
      C_T=$((C_T + 1))
      [ "$_a" = 1 ] && C_U0=$((C_U0 + 1))
      [ "$_b" = 1 ] && C_U999=$((C_U999 + 1))
    done <"$R/appguard/targets.tsv"
  fi
  if [ -f "$R/appguard/never.list" ]; then
    while IFS= read -r _p || [ -n "$_p" ]; do [ -n "$_p" ] && C_N=$((C_N + 1)); done <"$R/appguard/never.list"
  fi
}

mig_ag_installed_is_v2() {
  [ -f "$KM_AG_DIR/appguard.sh" ] && grep -q 'KM_APPGUARD_V2' "$KM_AG_DIR/appguard.sh" 2>/dev/null
}

# mig_set_key <file> <key> <value>: replace/append one key=value line
mig_set_key() {
  grep -v "^$2=" "$1" >"$1.2" 2>/dev/null
  printf '%s=%s\n' "$2" "$3" >>"$1.2"
  mv "$1.2" "$1"
}

# migrate_run <dry 0|1>: sets OUT. Idempotent.
migrate_run() {
  _dry=$1
  MIG_ACT=
  _from=1
  [ -r "$R/schema_version" ] && read -r _from <"$R/schema_version"
  case $_from in ''|*[!0-9]*) _from=1 ;; esac
  _lw=0
  while ! lock_take migrate; do
    _lw=$((_lw + 1))
    if [ "$_lw" -gt 25 ]; then err E_BUSY "migration is running in another process"; return 1; fi
    msleep
  done

  # 1. directories
  for _d in daemons appguard staging jobs lock backups rollback; do
    if [ ! -d "$R/$_d" ]; then
      mig_act "mkdir $R/$_d"
      [ "$_dry" = 1 ] || mkdir -p "$R/$_d" 2>/dev/null
    fi
  done
  if [ "$_dry" != 1 ] && [ ! -d "$R/daemons" ]; then
    lock_drop
    err E_NOT_ROOT "cannot create $R (not root?)"
    return 1
  fi

  # 2. builtin metas from legacy.d + legacy daemons.conf + live x-bits
  _conf=$(mig_conf_file)
  for _m in "$KM_MODDIR"/legacy.d/*.meta; do
    [ -f "$_m" ] || continue
    _id=${_m##*/}
    _id=${_id%.meta}
    valid_id "$_id" || continue
    if [ -f "$R/unmanaged" ] && grep -qx "$_id" "$R/unmanaged" 2>/dev/null; then continue; fi
    [ -f "$R/daemons/$_id/meta" ] && continue
    if [ "$_dry" != 1 ]; then
      _tmp=$R/.mig.$$.$_id
      sed -e "s|@ADB@|$KM_ADB|g" -e "s|@R@|$R|g" "$_m" >"$_tmp"
      if [ -n "$_conf" ]; then
        _cl=$(grep "^$_id|" "$_conf" 2>/dev/null | head -n 1)
        if [ -n "$_cl" ]; then
          _oifs=$IFS
          IFS='|'
          set -f
          set -- $_cl
          IFS=$_oifs
          set +f
          _cn=$2 _ck=$6 _cd=$7
          [ -n "$_cn" ] && mig_set_key "$_tmp" name "$_cn"
          [ -n "$_cd" ] && mig_set_key "$_tmp" desc "$_cd"
          case $_ck in daemon|oneshot) mig_set_key "$_tmp" kind "$_ck" ;; esac
        fi
      fi
      _bs=$(grep '^boot_script=' "$_tmp" | head -n 1 | cut -d= -f2-)
      [ -n "$_bs" ] || _bs=$(grep '^start=' "$_tmp" | head -n 1 | cut -d= -f2-)
      _hint=0
      [ -n "$_bs" ] && is_enabled "$_bs" && _hint=1
      mig_set_key "$_tmp" enabled_hint "$_hint"
      meta_write "$_id" <"$_tmp"
      rm -f "$_tmp"
    fi
    mig_act "daemon $_id: meta created (boot x-bit untouched)"
  done

  # 3. AppGuard lists from the v1 heredocs
  if [ ! -f "$R/appguard/targets.tsv" ]; then
    _src=
    _got=0
    if [ -f "$KM_AG_DIR/appguard.sh" ] && ! mig_ag_installed_is_v2; then
      _src=$KM_AG_DIR/appguard.sh
    elif [ -f "$R/rollback/appguard.sh.pre-km" ]; then
      _src=$R/rollback/appguard.sh.pre-km
    fi
    if [ -n "$_src" ] && mig_parse_v1 "$_src"; then
      _got=1
      mig_act "appguard: parsed lists from $_src"
    else
      for _sf in "$KM_SEED" "$KM_MODDIR/local/appguard-seed.tsv" "$R/appguard-seed.tsv"; do
        if [ -n "$_sf" ] && mig_seed "$_sf"; then
          _got=1
          mig_act "appguard: lists from seed $_sf (v1 script unreadable)"
          break
        fi
      done
    fi
    if [ "$_got" = 1 ]; then
      mig_counts
      if [ "$_dry" != 1 ]; then
        _t=$R/appguard/targets.tsv.tmp.$$
        _tn=$R/appguard/never.list.tmp.$$
        : >"$_t"
        : >"$_tn"
        set -f
        for _p in $V1_U0; do
          _b=0
          case " $V1_U999 " in *" $_p "*) _b=1 ;; esac
          printf '%s\t1\t%s\t\n' "$_p" "$_b" >>"$_t"
        done
        for _p in $V1_U999; do
          case " $V1_U0 " in *" $_p "*) continue ;; esac
          printf '%s\t0\t1\t\n' "$_p" >>"$_t"
        done
        for _p in $V1_NEVER; do printf '%s\n' "$_p" >>"$_tn"; done
        set +f
        mv "$_t" "$R/appguard/targets.tsv"
        if [ -f "$R/appguard/never.list" ]; then rm -f "$_tn"; else mv "$_tn" "$R/appguard/never.list"; fi
      fi
      mig_act "appguard: targets.tsv ($C_T rows: $C_U0 u0, $C_U999 u999), never.list ($C_N)"
    else
      mig_act "appguard: WARNING no lists found (no v1 script, no seed); targets.tsv left empty"
      [ "$_dry" = 1 ] || : >"$R/appguard/targets.tsv"
    fi
  fi
  if [ ! -f "$R/appguard/appguard.conf" ]; then
    mig_act "appguard: appguard.conf defaults (60/300/0)"
    [ "$_dry" = 1 ] || printf 'INTERVAL=60\nCOOLDOWN=300\nDRY=0\nCFGVER=1\n' >"$R/appguard/appguard.conf"
  fi
  if [ "$_dry" != 1 ]; then
    for _f in never.list kills.tsv; do
      [ -f "$R/appguard/$_f" ] || : >"$R/appguard/$_f"
    done
  fi

  # 4. new AppGuard script: cp .new + sh -n + mv (new inode; a running v1 loop keeps its old one)
  _pl=$KM_MODDIR/payload/appguard/appguard.sh
  if [ -f "$_pl" ]; then
    if [ ! -f "$KM_AG_DIR/appguard.sh" ] || ! cmp -s "$_pl" "$KM_AG_DIR/appguard.sh"; then
      mig_act "appguard: install v2 script to $KM_AG_DIR/appguard.sh (v1 kept as rollback/appguard.sh.pre-km)"
      if [ "$_dry" != 1 ]; then
        mkdir -p "$KM_AG_DIR" "$R/rollback"
        if [ -f "$KM_AG_DIR/appguard.sh" ] && ! mig_ag_installed_is_v2 && [ ! -f "$R/rollback/appguard.sh.pre-km" ]; then
          cp -p "$KM_AG_DIR/appguard.sh" "$R/rollback/appguard.sh.pre-km"
        fi
        if cp "$_pl" "$KM_AG_DIR/appguard.sh.new" && "$KM_SH" -n "$KM_AG_DIR/appguard.sh.new" \
           && chmod 755 "$KM_AG_DIR/appguard.sh.new" && mv "$KM_AG_DIR/appguard.sh.new" "$KM_AG_DIR/appguard.sh"; then
          :
        else
          rm -f "$KM_AG_DIR/appguard.sh.new"
          mig_act "appguard: WARNING script install failed"
        fi
      fi
    fi
  fi

  # 5. markers (written last, so an interrupted run is simply retried)
  if [ "$_dry" != 1 ]; then
    printf '%s\n' "$KM_SCHEMA" >"$R/schema_version.tmp" && mv "$R/schema_version.tmp" "$R/schema_version"
    printf '%s\n' "$KM_VERSION" >"$R/migrated_for.tmp" && mv "$R/migrated_for.tmp" "$R/migrated_for"
    [ -n "$MIG_ACT" ] && km_log "migrate from=$_from done"
  fi
  lock_drop

  if [ "$_dry" = 1 ] && [ -n "$C_T" ]; then :; else mig_counts_files; fi
  _dryb=false
  [ "$_dry" = 1 ] && _dryb=true
  ok_out ",\"from\":$_from,\"to\":$KM_SCHEMA,\"dry_run\":$_dryb,\"actions\":[$MIG_ACT],\"counts\":{\"targets\":$C_T,\"u0\":$C_U0,\"u999\":$C_U999,\"never\":$C_N}"
}

cmd_migrate() {
  case $1 in
    '') migrate_run 0 ;;
    --dry-run) C_T= ; migrate_run 1 ;;
    *) err E_ARG "usage: migrate [--dry-run]"; return 1 ;;
  esac
}

# lazy hook, called by bin/dm before commands that need the v2 tree
ensure_migrated() {
  needs_migrate || return 0
  migrate_run 0 >/dev/null
  OUT=
  return 0
}

# ---- rollback (best effort) -------------------------------------------------
cmd_rollback() {
  _best=
  for _d in "$R"/rollback/*/; do [ -d "$_d" ] && _best=${_d%/}; done
  if [ -z "$_best" ]; then err E_UNKNOWN "no rollback copy found under $R/rollback"; return 1; fi
  _ver=${_best##*/}
  [ -n "$KM_MODDIR" ] || { err E_UNKNOWN "module dir unknown"; return 1; }
  for _item in bin webroot module.prop service.sh daemons.conf; do
    [ -e "$_best/$_item" ] || continue
    _new=$KM_MODDIR/$_item.rb.$$
    if [ -d "$_best/$_item" ]; then
      if cp -pR "$_best/$_item" "$_new"; then
        [ -d "$KM_MODDIR/$_item" ] && mv "$KM_MODDIR/$_item" "$KM_MODDIR/$_item.old.$$"
        mv "$_new" "$KM_MODDIR/$_item"
      fi
    else
      cp -p "$_best/$_item" "$_new" && mv "$_new" "$KM_MODDIR/$_item"
    fi
  done
  if [ -f "$R/rollback/appguard.sh.pre-km" ]; then
    cp -p "$R/rollback/appguard.sh.pre-km" "$KM_AG_DIR/appguard.sh.new" && mv "$KM_AG_DIR/appguard.sh.new" "$KM_AG_DIR/appguard.sh"
  fi
  rm -f "$R/migrated_for"
  km_log "rollback restored $_ver"
  jesc "$_ver"
  ok_out ",\"restored\":\"$JESC\",\"msg\":\"module files restored; AppGuard and daemons were not restarted\""
}
