# Sourced by claude-html (bash), after conf.sh and platform.sh: every user
# setting as lib/settings.tsv describes it, for claude-html --config, the
# claude-html://settings link from the Settings page, and the page's data.
#
#   claude-html --config                          every setting, its value, where from, its default
#   claude-html --config set KEY=VALUE [KEY=VALUE…]   all checked first; one bad, nothing written
#   claude-html --config unset KEY…               back to the default
#   claude-html --config safe                     the guard's safe values: an id, a kind and a date each
#   claude-html --config forget-safe [ID…]        those values out of the own list, all or by id
#   claude-html --config edit-list                the own list in your text editor (made if missing)
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
    number)
      local lo="${vals%%..*}" hi="${vals##*..}"
      case "$v" in *[!0-9]*) _SE="a whole number, from $lo to $hi"; return 1 ;; esac
      [ "${#v}" -le 4 ] && [ $((10#$v)) -ge "$lo" ] && [ $((10#$v)) -le "$hi" ] || { _SE="a whole number, from $lo to $hi"; return 1; }
      _SV="$((10#$v))"; ch_set_f "$k" def; [ "$_SV" = "$_SF" ] && { _SV=""; _SU=1; }
      return 0 ;;
    items)
      # Each of the values at most once, in the order given, spaces or
      # commas between them; none: an empty line.
      local lv one out="" ok
      lv="$(printf '%s' "$v" | tr '[:upper:],' '[:lower:] ')"
      [ "$lv" = none ] && { _SV=none; return 0; }
      for one in $lv; do
        ok=""; case "|$vals|" in *"|$one|"*) ok=1 ;; esac
        [ -n "$ok" ] || { _SE="$one is not one of ${vals//|/, }"; return 1; }
        case " $out " in *" $one "*) _SE="$one given twice"; return 1 ;; esac
        out="${out:+$out }$one"
      done
      [ -n "$out" ] || { _SE="one or more of ${vals//|/, }, or none"; return 1; }
      ch_set_f "$k" def; [ "$out" = "$_SF" ] && { _SU=1; return 0; }
      _SV="$out"; return 0 ;;
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
claude-html --config safe
claude-html --config forget-safe [ID…]
claude-html --config edit-list
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
      if [ -z "$_SN" ]; then printf '    %-32s %s  · default\n' "$k" "$_SF"
      else printf '    %-32s %s  · %s · default: %s\n' "$k" "$_SN" "$src" "$_SF"; fi
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
ch_set_plan_add() {   # set|unset|forget|forget1|edit [name] [value]
  local op="$1" name="${2:-}" value="${3:-}"
  case "$op:$CH_SET_SEEN" in forget*" edit "*) CH_SET_BAD="${CH_SET_BAD}edit-list: alone, with nothing else
"; return 1 ;; esac
  if [ "$op" = forget ]; then
    case "$CH_SET_SEEN" in *" forget "*|*" forget:"*) CH_SET_BAD="${CH_SET_BAD}forget-safe: given twice
"; return 1 ;; esac
    CH_SET_SEEN="$CH_SET_SEEN""forget "; CH_SET_OPS="${CH_SET_OPS}forget
"; return 0
  fi
  # One safe value, by the id the Settings page and --config safe show:
  # one that is in the list now, and only once.
  if [ "$op" = forget1 ]; then
    case "$name" in ????????) ;; *) name=x ;; esac
    case "$name" in *[!0-9a-f]*) CH_SET_BAD="${CH_SET_BAD}forget-safe $2: not an id (8 of 0-9 a-f, as claude-html --config safe shows them)
"; return 1 ;; esac
    case "$CH_SET_SEEN" in *" forget "*|*" forget:$name "*) CH_SET_BAD="${CH_SET_BAD}forget-safe $name: given twice
"; return 1 ;; esac
    ch_set_safe_rows
    case "$CH_SAFE_ROWS" in
      *"$name	"*) ;;
      *) CH_SET_BAD="${CH_SET_BAD}forget-safe $name: no safe value has that id now
"; return 1 ;;
    esac
    CH_SET_SEEN="$CH_SET_SEEN""forget:$name "; CH_SET_OPS="${CH_SET_OPS}forget1	$name
"; return 0
  fi
  if [ "$op" = edit ]; then
    case "$CH_SET_SEEN" in " ") ;; *) CH_SET_BAD="${CH_SET_BAD}edit-list: alone, with nothing else
"; return 1 ;; esac
    CH_SET_SEEN="$CH_SET_SEEN""edit "; CH_SET_OPS="${CH_SET_OPS}edit
"; return 0
  fi
  case "$CH_SET_SEEN" in *" edit "*) CH_SET_BAD="${CH_SET_BAD}edit-list: alone, with nothing else
"; return 1 ;; esac
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

# Each safe value, as the Settings page shows it: an id, its kind and its
# date, never the value nor anything to find it by. The id is the first 8
# hex digits of SHA-256("safe-id", NUL, the line's salt:fingerprint), what
# build/redact.js's fingerprint() gives for the same, so the page and the
# command agree on it without either showing the salt or the fingerprint:
# 32 bits of a hash of a hash of a random salt, nothing to test a guess
# against. The kind and date are what the guard wrote after the line's #
# (guard.js recordSafe); a line without them is of a kind unknown.
# Into CH_SAFE_ROWS: id<TAB>kind<TAB>date, a line each, in the list's order.
ch_sha256() {
  if ch_have sha256sum; then sha256sum | cut -c1-64
  elif ch_have shasum; then shasum -a 256 | cut -c1-64
  else openssl dgst -sha256 -r 2>/dev/null | cut -c1-64; fi
}
CH_SAFE_RE='^safe:([0-9a-f]{16}):([0-9a-f]{32})([[:space:]]|$)'
CH_SAFE_NOTE_RE='^([a-z0-9][a-z0-9 -]{0,39}),[[:space:]]*([0-9]{4}-[0-9]{2}-[0-9]{2})$'
ch_set_safe_id() {   # salt hash -> _SID
  _SID="$(printf 'safe-id\000%s:%s' "$1" "$2" | ch_sha256)"; _SID="${_SID:0:8}"
}
ch_set_safe_rows() {
  [ -z "${CH_SAFE_READ:-}" ] || return 0
  CH_SAFE_ROWS=""; CH_SAFE_READ=1
  local f="$CLAUDE_HTML_REDACT_FILE" line t c kind date
  [ -f "$f" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    t="${line#"${line%%[![:space:]]*}"}"
    [[ "$t" =~ $CH_SAFE_RE ]] || continue
    ch_set_safe_id "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    kind=""; date=""
    case "$t" in
      *"#"*) c="${t#*#}"; c="${c#"${c%%[![:space:]]*}"}"; c="${c%"${c##*[![:space:]]}"}"
             if [[ "$c" =~ $CH_SAFE_NOTE_RE ]]; then kind="${BASH_REMATCH[1]}"; date="${BASH_REMATCH[2]}"; fi ;;
    esac
    CH_SAFE_ROWS="$CH_SAFE_ROWS$_SID	${kind:-kind unknown}	${date:--}
"
  done < "$f"
}
# The words for one: "github, 2026-11-19", or "kind unknown".
ch_set_safe_words() {   # id -> _SW
  local i k d
  _SW="kind unknown"
  while IFS='	' read -r i k d; do
    [ "$i" = "$1" ] || continue
    _SW="$k"; [ "$d" = - ] || _SW="$_SW, $d"; return 0
  done <<EOF
$CH_SAFE_ROWS
EOF
}
# The lines of those ids out of the list, and nothing else, copied back in
# place. Into CH_SAFE_GONE, how many went.
ch_forget_safe_ids() {   # id…
  local f="$CLAUDE_HTML_REDACT_FILE" tmp line t
  CH_SAFE_GONE=0
  [ -f "$f" ] || return 0
  tmp="$f.tmp.$$"
  while IFS= read -r line || [ -n "$line" ]; do
    t="${line#"${line%%[![:space:]]*}"}"
    if [[ "$t" =~ $CH_SAFE_RE ]]; then
      ch_set_safe_id "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
      case " $* " in *" $_SID "*) CH_SAFE_GONE=$((CH_SAFE_GONE + 1)); continue ;; esac
    fi
    printf '%s\n' "$line"
  done < "$f" > "$tmp" && cat "$tmp" > "$f"
  rm -f "$tmp"
  CH_SAFE_READ=""
}
ch_set_safe_show() {
  ch_set_safe_rows
  local i k d n=0
  echo "The guard's safe values in $(ch_set_tilde "$CLAUDE_HTML_REDACT_FILE"): never the value, only what it was and when"
  while IFS='	' read -r i k d; do
    [ -n "$i" ] || continue
    n=$((n + 1)); printf '  %s  %-24s %s\n' "$i" "$k" "$([ "$d" = - ] || echo "$d")"
  done <<EOF
$CH_SAFE_ROWS
EOF
  [ "$n" -gt 0 ] || echo "  none"
  [ "$n" = 0 ] || echo "  claude-html --config forget-safe ID … forgets those; forget-safe alone, all of them"
}

# The own list, in the text editor, made first with a header if it is not
# there: the opener's, as a page is opened (CLAUDE_HTML_NO_SCREEN honoured).
CH_LIST_HEADER="# claude-html: your own list of things to mask, one a line, never shown anywhere.
# A line is a value written as it is, or /a regular expression/ (flags i, m, s, u).
# A line starting with # is a comment. safe: lines are the guard's: values you
# answered Safe for, as fingerprints; claude-html --config forget-safe takes them out.
# See Secrets in docs/SETUP.md.
"
ch_set_edit_list() {
  local f="$CLAUDE_HTML_REDACT_FILE"
  if [ ! -e "$f" ]; then
    mkdir -p "${f%/*}" 2>/dev/null
    ( umask 077; printf '%s' "$CH_LIST_HEADER" > "$f" ) || { echo "could not make $f" >&2; return 1; }
    echo "Made $(ch_set_tilde "$f"), with a few lines that say what goes in it."
  fi
  ch_detect
  case "$CH_OPENER" in
    open) ch_run /usr/bin/open -t "$f" >/dev/null 2>&1 ;;
    '') echo "nothing here opens files: edit $(ch_set_tilde "$f") in your editor" >&2; return 1 ;;
    *) ch_open_file "$f" ;;
  esac || { echo "could not open $(ch_set_tilde "$f"): edit it in your editor" >&2; return 1; }
  echo "Opened $(ch_set_tilde "$f") in your text editor."
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
      forget1) ;;
      *) continue ;;
    esac
    # The daily check's switch does what claude-html --update on|off does.
    if [ "$k" = CLAUDE_HTML_UPDATE_CHECK ] && { [ "$op" = set ] || [ "$op" = unset ]; }; then
      . "$HERE/lib/version.sh" 2>/dev/null && ch_update_switched "${v:-on}"
    fi
    k=""
  done <<EOF
$CH_SET_OPS
EOF
  # The safe values by id, all in one pass over the list.
  local ids
  ids="$(printf '%s' "$CH_SET_OPS" | sed -n 's/^forget1	//p' | tr '\n' ' ')"
  [ -z "${ids// /}" ] || { ch_set_safe_rows; CH_SAFE_WORDS=""
    for k in $ids; do ch_set_safe_words "$k"; CH_SAFE_WORDS="$CH_SAFE_WORDS$k	$_SW
"; done
    ch_forget_safe_ids $ids; }
}

# What --config set and unset say they did, a line each.
ch_set_said() {
  local op k v w
  while IFS='	' read -r op k v; do
    case "$op" in
      set) echo "$k=$v" ;;
      unset) ch_set_f "$k" def; echo "$k: its line is out of the conf; the default applies ($_SF)" ;;
      forget) echo "forgot $CH_SAFE_GONE safe value(s); your own entries in $(ch_set_tilde "$CLAUDE_HTML_REDACT_FILE") stay" ;;
      forget1) printf '%s' "$CH_SAFE_WORDS" | while IFS='	' read -r i w; do [ "$i" = "$k" ] && echo "forgot the safe value $k ($w)"; done; continue ;;
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
    forget-safe)
      if [ $# = 0 ]; then ch_set_plan_add forget
      else for a in "$@"; do ch_set_plan_add forget1 "$a"; done; fi ;;
    safe) [ $# = 0 ] || { ch_set_usage; return 2; }; ch_set_safe_show; return 0 ;;
    edit-list) [ $# = 0 ] || { ch_set_usage; return 2; }; ch_set_edit_list; return $? ;;
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
#                 forget-safe, the guard's safe values forgotten; forget-safe=ID,
#                 the one of that id (8 of 0-9 a-f), as many as there are;
#                 edit-list, alone: the own list opened in the text editor
#   KEY           a setting's name without CLAUDE_HTML_, one the page edits
#   VALUE         1 to 512 of A-Z a-z 0-9 . _ ~ - and %XX (UTF-8, percent-
#                 encoded), never a control character
#
# Each value then passes the same check as --config set. Nothing in it is
# ever run; nothing is written until a person says so in a window, Cancel
# the default. The helper and handler.sh check its characters and length
# before they hand it on.
CH_SET_LINK_ITEM='(forget-safe(=[0-9a-f]{8})?|edit-list|[A-Z][A-Z_]*(=([A-Za-z0-9._~-]|%[0-9A-F][0-9A-F])+)?)'
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
      forget-safe=*) ch_set_plan_add forget1 "${item#forget-safe=}" ;;
      edit-list) ch_set_plan_add edit ;;
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

  # The own list, opened: asked first all the same, since any page can
  # open such a link, and what the list holds would then be on the screen.
  if [ "$CH_SET_OPS" = "edit
" ]; then
    local ask="$HOME/.claude/.claude-html-settings-ask" f="$CLAUDE_HTML_REDACT_FILE"
    rows="Open:	$(ch_set_tilde "$f") in your text editor$([ -e "$f" ] || echo ", made first with a few lines that say what goes in it")
Note:	it holds your own secrets: they will be on the screen"
    ch_ask_take "$ask"; rc=$?
    if [ $rc = 3 ]; then echo "a window asking about the settings is already open; nothing was opened" >&2; return 3
    elif [ $rc != 0 ]; then echo "could not ask; nothing was opened" >&2; return 1; fi
    ch_detect; CH_HERE="$HERE"
    ans="$(ch_confirm "Open your own list in the text editor?" "Asked by the Settings page." "$rows" Open)"; rc=$?
    rm -rf "$ask"
    if [ $rc != 0 ]; then
      echo "Open your own list in the text editor? There is no window to ask you in here, so nothing was opened. To open it, run:" >&2
      echo "claude-html --config edit-list" >&2
      return 1
    fi
    if [ -n "${CH_DRY:-}" ]; then printf '%s\n' "$ans"; return 0; fi
    [ "$ans" = apply ] || { echo "Nothing was opened."; return 0; }
    ch_set_edit_list
    return $?
  fi

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
    if [ "$op" = forget1 ]; then
      ch_set_safe_rows; ch_set_safe_words "$k"
      rows="$rows${rows:+
}Safe value $k:	$_SW → forgotten: asked about again"
      lines="$lines${lines:+
}# in $(ch_set_tilde "$CLAUDE_HTML_REDACT_FILE"): the safe: line of $k taken out, nothing else"
      case "$cmd" in *"--config forget-safe "*) cmd="$cmd $k" ;; *) cmd="$cmd${cmd:+
}claude-html --config forget-safe $k" ;; esac
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
  # Safe values forgotten and nothing else: asked as that, its button
  # Forget; any setting among the changes, Apply.
  local q="Change claude-html settings?" ok=Apply
  if ! printf '%s' "$CH_SET_OPS" | grep -qv '^forget'; then
    ok=Forget
    case "$CH_SET_OPS" in "forget1	"*"
forget1	"*) q="Forget these safe values?" ;; "forget1	"*) q="Forget this safe value?" ;; *) q="Forget the safe values?" ;; esac
  fi
  ans="$(ch_confirm "$q" "$sub" "$rows" "$ok" File: "$lines")"; rc=$?
  rm -rf "$ask"
  if [ $rc != 0 ]; then
    echo "$q There is no window to ask you in here, so nothing was changed. To make the same change, run:" >&2
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
