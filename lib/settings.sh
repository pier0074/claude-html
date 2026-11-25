# Sourced by claude-html (bash), after conf.sh and platform.sh: every user
# setting as lib/settings.tsv describes it, for claude-html --config, the
# claude-html://settings link from the Settings page, and the page's data.
#
#   claude-html --config                          every setting, its value, where from, its default
#   claude-html --config set KEY=VALUE [KEY=VALUE…]   all checked first; one bad, nothing written
#   claude-html --config unset KEY…               back to the default
#   claude-html --config forget-safe              the guard's safe values out of the own list
#   claude-html --settings-apply <payload>        asks in a window, then writes
#
# KEY is written with or without CLAUDE_HTML_. Each value is checked by the
# checks the setting already has: ch_wait_secs for the wait, limits.sh's
# parsers for the week, the rules, the budget and its warnings. Every
# change is one line of the conf, written by ch_conf_set or taken out by
# ch_conf_unset; the caller rebuilds the pages after (status 10).

CH_SET_TSV="$HERE/lib/settings.tsv"

# The description, into _SK_<field>_<key> and the order of keys and groups.
ch_set_load() {
  [ -z "${CH_SET_LOADED:-}" ] || return 0
  CH_SET_LIST=""; CH_SET_GROUPS=""
  local k g label kind values def anchor flags help
  [ -f "$CH_SET_TSV" ] || return 1
  while IFS='	' read -r k g label kind values def anchor flags help; do
    case "$k" in
      @*) CH_SET_GROUPS="$CH_SET_GROUPS ${k#@}"; eval "_SG_${k#@}=\$g"; continue ;;
      CLAUDE_HTML_*|CH_*) ;;
      *) continue ;;
    esac
    CH_SET_LIST="$CH_SET_LIST $k"
    [ "$values" = - ] && values=""; [ "$flags" = - ] && flags=""
    eval "_SK_group_$k=\$g; _SK_label_$k=\$label; _SK_kind_$k=\$kind; _SK_values_$k=\$values"
    eval "_SK_def_$k=\$def; _SK_anchor_$k=\$anchor; _SK_flags_$k=\$flags; _SK_help_$k=\$help"
  done < "$CH_SET_TSV"
  CH_SET_LOADED=1
}
ch_set_f() { eval "_SF=\${_SK_$2_$1:-}"; }   # key field -> _SF
ch_set_flag() {   # key flag
  ch_set_f "$1" flags
  case ",$_SF," in *",$2,"*|*",$2:"*) return 0 ;; esac
  return 1
}
# Which value of a key lowers protection ("off"), or nothing.
ch_set_low() { ch_set_f "$1" flags; _SL=""; case ",$_SF," in *,low:*) _SL="${_SF#*low:}"; _SL="${_SL%%,*}" ;; esac; }

# A name as typed, to the key: GUARD_WAIT, guard_wait and CLAUDE_HTML_GUARD_WAIT
# are one. Into CH_SK; fails for a name that is no setting.
ch_set_name() {
  ch_set_load || return 1
  local n
  n="$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"
  case "$n" in *[!A-Z0-9_]*|'') return 1 ;; esac
  for CH_SK in "$n" "CLAUDE_HTML_$n"; do
    case " $CH_SET_LIST " in *" $CH_SK "*) return 0 ;; esac
  done
  CH_SK=""; return 1
}
# What the Settings page may change through its link: not what install.sh
# sets, not what only the environment can, not what the Limits & budget
# panel sends by its own link.
ch_set_editable() { ! ch_set_flag "$1" ro && ! ch_set_flag "$1" env && ! ch_set_flag "$1" panel && ! ch_set_flag "$1" hidden; }

# A path as a setting takes one: whole (/…) or from the home folder (~/…),
# with no . or .. in it, no control character and none of " ` $ \, at most
# 512 characters. The conf would quote any of them safely; a path holding
# one is refused anyway, the page's link and the command alike.
ch_set_path_ok() {
  case "$1" in /*|"~/"*) ;; *) _SE="a path is written from / or ~/"; return 1 ;; esac
  case "$1" in *[[:cntrl:]]*|*'"'*|*'`'*|*'$'*|*'\'*) _SE="a path may not hold a control character, \", \`, \$ or \\"; return 1 ;; esac
  case "/$1/" in */./*|*/../*) _SE="a path may not go through . or .."; return 1 ;; esac
  [ "${#1}" -le 512 ] || { _SE="a path of 512 characters at most"; return 1; }
  return 0
}

# A value checked for a key, by the checks the setting already has. Into
# _SV, as the conf will hold it, or "" with _SU=1 when it means the default
# (an enum's default value takes the line out); else _SE says why not.
ch_set_check() {   # key value
  _SV=""; _SE=""; _SU=""
  local k="$1" v="$2" kind vals
  ch_set_f "$k" kind; kind="$_SF"
  ch_set_f "$k" values; vals="$_SF"
  v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"
  if ch_set_flag "$k" ro; then
    case "$k" in
      CLAUDE_HTML_OUT) _SE="set by ./install.sh --out DIR, in $HERE" ;;
      *) _SE="set by ./install.sh --root DIR, in $HERE" ;;
    esac
    return 1
  fi
  if ch_set_flag "$k" env; then _SE="read from the environment only, never from the conf"; return 1; fi
  [ -n "$v" ] || { _SE="empty: claude-html --config unset ${k#CLAUDE_HTML_} puts the default back"; return 1; }
  case "$kind" in
    enum)
      local lv one
      lv="$(printf '%s' "$v" | tr '[:upper:]' '[:lower:]')"
      for one in ${vals//|/ }; do
        if [ "$one" = "$lv" ]; then
          ch_set_f "$k" def
          if [ "$lv" = "$_SF" ]; then _SU=1; else _SV="$lv"; fi
          return 0
        fi
      done
      _SE="one of ${vals//|/, }"; return 1 ;;
    duration)
      ch_wait_secs "$v"; case $? in
        0) _SV="$v"; return 0 ;;
        2) _SE="out of range: from 30 seconds to 60 minutes, written 45, 45s, 2m or 1m30s" ;;
        *) _SE="not a wait: from 30 seconds to 60 minutes, written 45, 45s, 2m or 1m30s" ;;
      esac
      return 1 ;;
    week)
      ch_lim_reset_parse "$v" || { _SE="not a day and an hour: tue 07:00 UTC, thu 17, Friday 8:30"; return 1; }
      _SV="$_WSPEC"; return 0 ;;
    path)
      ch_set_path_ok "$v" || return 1
      # Whole, as the conf holds a path: in its quotes a ~ is not the home.
      _SV="${v/#\~/$HOME}"; return 0 ;;
    rules)
      case "$v" in none) _SU=1; return 0 ;; esac
      ch_lim_parse_rules "$v"
      if [ -n "$CH_LIM_BAD" ] || [ "$CH_LIM_N" = 0 ]; then
        _SE="not rules: ${CH_LIM_BAD:-$v} — each is a day, a time and a percentage, 8 at most: fri 20:00 80%"; return 1
      fi
      ch_lim_rules_text; _SV="$_RTXT"; return 0 ;;
    budget)
      ch_lim_parse_budget "$v"
      [ -z "$CH_LIM_BBAD" ] || { _SE="not a budget: written 50 week, 20 day, 200 month, or off"; return 1; }
      if [ "$CH_LIM_BC" -gt 0 ]; then _SV="$CH_LIM_BA $CH_LIM_BP"; else _SV=off; fi
      return 0 ;;
    warn)
      ch_lim_parse_warn "$v" || { _SE="two percentages, the first lower: 80 95"; return 1; }
      _SV="$CH_LIM_W1 $CH_LIM_W2"; return 0 ;;
  esac
  _SE="not a setting that can be set"; return 1
}

# A setting as it stands: its value in force, into _SN ("" when it is the
# default), and where it comes from, into _SS: environment, conf or default.
ch_set_now() {   # key
  eval "_SS=\${CH_SRC_$1:-default}"
  case "$1" in
    CLAUDE_HTML_OUT) _SN="$OUT" ;;
    CLAUDE_HTML_ROOT) _SN="$ROOT" ;;
    CLAUDE_HTML_CONF) _SN="$CONF" ;;
    *) if [ "$_SS" = default ]; then _SN=""; else eval "_SN=\${$1:-}"; fi ;;
  esac
}
# The same, in words, for the window and --config.
ch_set_words() {   # key
  ch_set_now "$1"; ch_set_f "$1" def
  if [ "$_SS" = default ] || [ -z "$_SN" ]; then _SW="$_SF (default)"; else _SW="$_SN"; fi
}

# A word for a command line, quoted only when it must be (as the page's).
ch_set_q() { case "$1" in *[!A-Za-z0-9._~/:@%+=,-]*|'') ch_quote "$1" ;; *) printf '%s' "$1" ;; esac; }
ch_set_tilde() { case "$1" in "$HOME"/*) printf '~/%s' "${1#"$HOME"/}" ;; *) printf '%s' "$1" ;; esac; }

# ── claude-html --config ──────────────────────────────────────────────
ch_set_usage() {
  cat >&2 <<'EOF'
claude-html --config
claude-html --config set KEY=VALUE [KEY=VALUE…]
claude-html --config unset KEY [KEY…]
claude-html --config forget-safe
EOF
}

ch_set_show() {
  ch_set_load || { echo "lib/settings.tsv is missing from $HERE" >&2; return 1; }
  local g k w src
  echo "claude-html settings  $(ch_set_tilde "$CONF")"
  for g in $CH_SET_GROUPS; do
    eval "w=\$_SG_$g"
    echo
    echo "  $w"
    for k in $CH_SET_LIST; do
      ch_set_f "$k" group; [ "$_SF" = "$g" ] || continue
      ch_set_now "$k"
      case "$_SS" in
        environment) src="environment" ;;
        conf) src="conf" ;;
        *) src="default" ;;
      esac
      ch_set_f "$k" def
      if [ -z "$_SN" ]; then printf '    %-27s %s  · default\n' "$k" "$_SF"
      else printf '    %-27s %s  · %s · default: %s\n' "$k" "$_SN" "$src" "$_SF"; fi
      if [ "$_SS" = environment ] && ! ch_set_flag "$k" env; then
        echo "      set in the environment, which wins over the conf: a change there does nothing here while it is set"
      fi
    done
  done
  echo
  echo "  claude-html --config set KEY=VALUE … · claude-html --config unset KEY … (KEY with or without CLAUDE_HTML_)"
}

# The changes asked for, checked, all of them before any is written: into
# CH_SET_OPS (one per line: set<TAB>key<TAB>value, unset<TAB>key, or forget).
# What is wrong goes to CH_SET_BAD, one line per item.
ch_set_plan_reset() { CH_SET_OPS=""; CH_SET_BAD=""; CH_SET_SEEN=" "; }
ch_set_plan_add() {   # set|unset|forget [name] [value]
  local op="$1" name="${2:-}" value="${3:-}"
  if [ "$op" = forget ]; then
    case "$CH_SET_SEEN" in *" forget "*) CH_SET_BAD="${CH_SET_BAD}forget-safe: given twice
"; return 1 ;; esac
    CH_SET_SEEN="$CH_SET_SEEN""forget "; CH_SET_OPS="${CH_SET_OPS}forget
"; return 0
  fi
  if ! ch_set_name "$name"; then CH_SET_BAD="${CH_SET_BAD}$name: no such setting
"; return 1; fi
  case "$CH_SET_SEEN" in *" $CH_SK "*) CH_SET_BAD="${CH_SET_BAD}$CH_SK: given twice
"; return 1 ;; esac
  CH_SET_SEEN="$CH_SET_SEEN$CH_SK "
  if [ "$op" = unset ]; then
    if ch_set_flag "$CH_SK" ro || ch_set_flag "$CH_SK" env; then
      ch_set_check "$CH_SK" x; CH_SET_BAD="${CH_SET_BAD}$CH_SK: $_SE
"; return 1
    fi
    CH_SET_OPS="${CH_SET_OPS}unset	$CH_SK
"; return 0
  fi
  if ! ch_set_check "$CH_SK" "$value"; then
    CH_SET_BAD="${CH_SET_BAD}$CH_SK=$value: $_SE
"; return 1
  fi
  if [ -n "$_SU" ]; then CH_SET_OPS="${CH_SET_OPS}unset	$CH_SK
"
  else CH_SET_OPS="${CH_SET_OPS}set	$CH_SK	$_SV
"; fi
}

# The safe values, the guard's, out of the own list: the lines that start
# safe:, and nothing else, the rest as it was, copied back so a list kept as
# a symlink stays one. Into CH_SAFE_GONE, how many went.
ch_set_safe_count() { grep -c '^[[:space:]]*safe:' "$CLAUDE_HTML_REDACT_FILE" 2>/dev/null || true; }
ch_set_own_count() { grep -cvE '^[[:space:]]*(#|safe:|$)' "$CLAUDE_HTML_REDACT_FILE" 2>/dev/null || true; }
ch_forget_safe() {
  local f="$CLAUDE_HTML_REDACT_FILE" tmp
  CH_SAFE_GONE="$(ch_set_safe_count)"; CH_SAFE_GONE="${CH_SAFE_GONE:-0}"
  [ "$CH_SAFE_GONE" -gt 0 ] || return 0
  tmp="$f.tmp.$$"
  grep -v '^[[:space:]]*safe:' "$f" > "$tmp"; cat "$tmp" > "$f"; rm -f "$tmp"
}

# Writes CH_SET_OPS, and keeps the shell's copy of each in step, so the
# build after it in this same command sees the new values.
ch_set_write() {
  local op k v
  while IFS='	' read -r op k v; do
    case "$op" in
      set) ch_conf_set "$k" "$v"
           ch_set_now "$k"; [ "$_SS" = environment ] || { eval "$k=\$v; CH_SRC_$k=conf"; export "$k"; } ;;
      unset) ch_conf_unset "$k"; ch_set_now "$k"; [ "$_SS" = environment ] || eval "unset $k; CH_SRC_$k=default" ;;
      forget) ch_forget_safe ;;
      *) continue ;;
    esac
    # The daily check's switch does what claude-html --update on|off does.
    if [ "$k" = CLAUDE_HTML_UPDATE_CHECK ] && [ "$op" != forget ]; then
      . "$HERE/lib/version.sh" 2>/dev/null && ch_update_switched "${v:-on}"
    fi
    k=""
  done <<EOF
$CH_SET_OPS
EOF
}

# What --config set and unset say they did, a line each.
ch_set_said() {
  local op k v w
  while IFS='	' read -r op k v; do
    case "$op" in
      set) echo "$k=$v" ;;
      unset) ch_set_f "$k" def; echo "$k: its line is out of the conf; the default applies ($_SF)" ;;
      forget) echo "forgot $CH_SAFE_GONE safe value(s); your own entries in $(ch_set_tilde "$CLAUDE_HTML_REDACT_FILE") stay" ;;
      *) continue ;;
    esac
    if [ "$op" != forget ]; then
      eval "w=\${CH_SRC_$k:-}"
      [ "$w" != environment ] || echo "  but $k is set in the environment, which wins over the conf: here it stays ${!k}"
    fi
  done <<EOF
$CH_SET_OPS
EOF
}

ch_set_cli() {
  ch_set_load || { echo "lib/settings.tsv is missing from $HERE" >&2; return 1; }
  local sub="${1:-}" a
  [ $# -gt 0 ] && shift
  ch_set_plan_reset
  case "$sub" in
    ""|status|show) [ $# = 0 ] || { ch_set_usage; return 2; }; ch_set_show; return 0 ;;
    set)
      [ $# -gt 0 ] || { ch_set_usage; return 2; }
      for a in "$@"; do
        case "$a" in
          *=*) ch_set_plan_add set "${a%%=*}" "${a#*=}" ;;
          *) CH_SET_BAD="${CH_SET_BAD}$a: written KEY=VALUE
" ;;
        esac
      done ;;
    unset)
      [ $# -gt 0 ] || { ch_set_usage; return 2; }
      for a in "$@"; do ch_set_plan_add unset "$a"; done ;;
    forget-safe) [ $# = 0 ] || { ch_set_usage; return 2; }; ch_set_plan_add forget ;;
    *) ch_set_usage; return 2 ;;
  esac
  if [ -n "$CH_SET_BAD" ]; then
    printf '%s' "$CH_SET_BAD" | sed 's/^/not changed: /' >&2
    echo "nothing was written" >&2
    return 2
  fi
  ch_set_write
  echo "In $(ch_set_tilde "$CONF"):"
  ch_set_said | sed 's/^/  /'
  return 10
}

# ── from the page: claude-html://settings/<payload> ──────────────────
# Any web page can open such a link, so what it carries is a fixed grammar
# and nothing else, at most 2048 characters, checked here whole:
#
#   v1/<conf fingerprint>/<change>[/<change>…]        24 changes at most
#   fingerprint   none, or the first 16 hex digits of the conf's md5 as the
#                 page was built
#   change        KEY=VALUE, a setting set; KEY alone, back to its default;
#                 forget-safe, the guard's safe values forgotten
#   KEY           a setting's name without CLAUDE_HTML_, one the page edits
#   VALUE         1 to 512 of A-Z a-z 0-9 . _ ~ - and %XX (UTF-8, percent-
#                 encoded), never a control character
#
# Each value then passes the same check as --config set. Nothing in it is
# ever run; nothing is written until a person says so in a window, Cancel
# the default. The helper and handler.sh check its characters and length
# before they hand it on.
CH_SET_LINK_ITEM='(forget-safe|[A-Z][A-Z_]*(=([A-Za-z0-9._~-]|%[0-9A-F][0-9A-F])+)?)'
CH_SET_LINK_RE="^v1/(none|[0-9a-f]{16})(/$CH_SET_LINK_ITEM){1,24}\$"
ch_set_link_ok() {
  case "$1" in *[!A-Za-z0-9._~%=/-]*|'') return 1 ;; esac
  [ "${#1}" -le 2048 ] && [[ "$1" =~ $CH_SET_LINK_RE ]] || return 1
  # No control character, encoded or not.
  case "$1" in *%[01][0-9A-F]*|*%7F*) return 1 ;; esac
  return 0
}
ch_set_fp() {
  local m
  if [ -f "$CONF" ]; then m="$(ch_md5 "$CONF")"; printf '%s' "${m:0:16}"; else printf none; fi
}
# %XX back to bytes: only after the grammar holds, so nothing else in it
# can be an escape.
ch_set_decode() { local e="${1//%/\\x}"; printf -v _SD '%b' "$e"; }

ch_set_apply() {   # payload
  local p="${1:-}" fp item name enc rows lines cmd stale="" ans rc k v op w now low
  ch_set_load || { echo "lib/settings.tsv is missing from $HERE" >&2; return 1; }
  if ! ch_set_link_ok "$p"; then echo "not a settings link" >&2; return 2; fi
  fp="${p#v1/}"; fp="${fp%%/*}"
  ch_set_plan_reset
  local IFS_was="$IFS" items
  IFS=/; set -f; items=(${p#v1/*/}); set +f; IFS="$IFS_was"
  for item in "${items[@]}"; do
    case "$item" in
      CLAUDE_HTML_*) CH_SET_BAD="${CH_SET_BAD}${item%%=*}: a link names a setting without CLAUDE_HTML_
" ;;
      forget-safe) ch_set_plan_add forget ;;
      *=*) name="${item%%=*}"; enc="${item#*=}"
           ch_set_decode "$enc"
           if ! ch_set_name "$name" || ! ch_set_editable "$CH_SK"; then
             CH_SET_BAD="${CH_SET_BAD}$name: not a setting the page can change
"; continue; fi
           ch_set_plan_add set "$CH_SK" "$_SD" ;;
      *) if ! ch_set_name "$item" || ! ch_set_editable "$CH_SK"; then
           CH_SET_BAD="${CH_SET_BAD}$item: not a setting the page can change
"; continue; fi
         ch_set_plan_add unset "$CH_SK" ;;
    esac
  done
  if [ -n "$CH_SET_BAD" ]; then
    printf 'not a settings link, so nothing was changed:\n%s' "$CH_SET_BAD" >&2
    return 2
  fi
  [ "$fp" = "$(ch_set_fp)" ] || stale=1

  # The window: each change as it is now and as it will be, flagged where
  # it lowers protection; File ▸ the very lines Apply writes.
  rows=""; lines=""; cmd=""
  local sets="" unsets=""
  while IFS='	' read -r op k v; do
    [ -n "$op" ] || continue
    if [ "$op" = forget ]; then
      local n own
      n="$(ch_set_safe_count)"; own="$(ch_set_own_count)"
      rows="$rows${rows:+
}Safe values:	${n:-0} → 0: forgotten, your own ${own:-0} entries stay"
      lines="$lines${lines:+
}# in $(ch_set_tilde "$CLAUDE_HTML_REDACT_FILE"): its ${n:-0} safe: line(s) taken out, nothing else"
      cmd="$cmd${cmd:+
}claude-html --config forget-safe"
      continue
    fi
    ch_set_f "$k" label; w="$_SF"
    ch_set_words "$k"; now="$_SW"
    if [ "$op" = set ]; then
      ch_set_low "$k"; low=""; [ -n "$_SL" ] && [ "$v" = "$_SL" ] && low="   ⚠ lowers protection"
      lines="$lines${lines:+
}$k=$(ch_conf_value "$v")"
      sets="$sets $(ch_set_q "${k#CLAUDE_HTML_}=$v")"
    else
      ch_set_f "$k" def; v="$_SF (default)"
      ch_set_low "$k"; low=""; [ -n "$_SL" ] && [ "$_SF" = "$_SL" ] && low="   ⚠ lowers protection"
      lines="$lines${lines:+
}# $k: its line taken out, the default applies"
      unsets="$unsets ${k#CLAUDE_HTML_}"
    fi
    if [ -n "$stale" ]; then rows="$rows${rows:+
}$w:	now $now · asked $v$low"
    else rows="$rows${rows:+
}$w:	$now → $v$low"; fi
    ch_set_now "$k"
    [ "$_SS" != environment ] || rows="$rows
	(set in the environment, which wins: no change here while it is)"
  done <<EOF
$CH_SET_OPS
EOF
  rows="$rows
File:	$(ch_set_tilde "$CONF")"
  [ -z "$sets" ] || cmd="claude-html --config set$sets${cmd:+
$cmd}"
  [ -z "$unsets" ] || cmd="claude-html --config unset$unsets${cmd:+
$cmd}"
  local sub="Asked by the Settings page."
  [ -z "$stale" ] || sub="Asked by the Settings page — the conf changed since this page was built."

  # One window at a time: a page that opens the link again and again gets
  # one question, not a pile of them.
  local ask="$HOME/.claude/.claude-html-settings-ask"
  ch_ask_take "$ask"; rc=$?
  if [ $rc = 3 ]; then echo "a window asking about the settings is already open; nothing was changed" >&2; return 3
  elif [ $rc != 0 ]; then echo "could not ask; nothing was changed" >&2; return 1; fi
  ch_detect; CH_HERE="$HERE"
  ans="$(ch_confirm "Change claude-html settings?" "$sub" "$rows" Apply File: "$lines")"; rc=$?
  rm -rf "$ask"
  if [ $rc != 0 ]; then
    echo "no way to ask you first here, so nothing was changed. To make the same change, run:" >&2
    printf '%s\n' "$cmd" >&2
    return 1
  fi
  if [ -n "${CH_DRY:-}" ]; then printf '%s\n' "$ans"; return 0; fi
  if [ "$ans" != apply ]; then echo "Nothing was changed."; return 0; fi
  ch_set_write
  echo "Applied."
  return 10   # the caller rebuilds the pages
}

# ── the page's data ──────────────────────────────────────────────────
# What the Settings page shows that only the shell knows: each setting's
# value and where it comes from, the conf and its fingerprint, the engine,
# the system, the link handler. Never a secret: the own list is counted by
# the build, never read here.
ch_settings_json() {   # clone
  ch_set_load || return 1
  local k vals="" sys links lok=false
  for k in $CH_SET_LIST; do
    ch_set_now "$k"
    vals="$vals${vals:+,}$(ch_json_str "$k"):{\"v\":$(ch_json_str "$_SN"),\"src\":\"$_SS\"}"
  done
  ch_detect
  case "$CH_OS" in
    darwin) sys="macOS $(sw_vers -productVersion 2>/dev/null)" ;;
    *) sys="$CH_OS${CH_PRETTY:+ · $CH_PRETTY}"; [ "$CH_WSL" = yes ] && sys="$sys · WSL" ;;
  esac
  if [ "$CH_OS" = darwin ]; then
    if [ -d "$1/Claude HTML.app" ]; then links="Claude HTML.app, in the clone"; lok=true
    else links="no helper app yet: ./install.sh builds it"; fi
  else
    links="$(ch_links_status)" && case "$links" in registered*) lok=true ;; esac
  fi
  printf '{"fp":"%s","conf":%s,"here":%s,"version":%s,"values":{%s},"engine":{"name":%s,"why":%s,"node":%s,"nodeVersion":%s,"note":%s},"system":%s,"links":%s,"linksOk":%s,"os":"%s"}' \
    "$(ch_set_fp)" "$(ch_json_str "$CONF")" "$(ch_json_str "$1")" "$(ch_json_str "$(cat "$1/VERSION" 2>/dev/null)")" "$vals" \
    "$(ch_json_str "${CH_ENGINE:-}")" "$(ch_json_str "${CH_ENGINE_WHY:-}")" "$(ch_json_str "${CH_NODE:-}")" \
    "$(ch_json_str "${CH_NODE_VERSION:-}")" "$(ch_json_str "${CH_ENGINE_NOTE:-}")" \
    "$(ch_json_str "$sys")" "$(ch_json_str "$links")" "$lok" "$CH_OS"
}
