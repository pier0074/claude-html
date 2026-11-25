# Sourced, not run: the few helpers the other lib files share. Each of
# them sources this itself, because each is also sourced without the
# others: the status line has only limits.sh, the Stop hook only
# version.sh, the update runs from a copy of update.sh and version.sh,
# and the Linux link handler, under sh, only platform.sh. So this is
# POSIX sh as well as bash 3.2: no local, no [[ ]], no arrays.
#
#   ch_is_off <value>              a switch's value that means off
#   ch_is_on <value>               one that means on
#   ch_conf_get <conf> <key…>      the conf's values, read without running it
#   ch_with_limit <secs> <cmd…>    a command, stopped when it runs longer
#   ch_is_sid <text>               a whole session id, and nothing else
#   ch_lim_link_ok <payload>       a claude-html://limits link's payload
#   ch_set_link_shape <payload>    a claude-html://settings payload's
#                                  characters and length
#   ch_set_link_ok <payload>       the same payload, its grammar whole

# A switch's value that means off, one way for every setting; and on.
ch_is_off() {
  case "$1" in [Oo][Ff][Ff]|0|[Nn][Oo]|[Ff][Aa][Ll][Ss][Ee]) return 0 ;; esac
  return 1
}
ch_is_on() {
  case "$1" in [Oo][Nn]|1|[Yy][Ee][Ss]|[Tt][Rr][Uu][Ee]) return 0 ;; esac
  return 1
}

# The conf's values for some keys, read line by line, never run: what the
# status line, the Stop hook and the daily check need before (or without)
# conf.sh. One pass for all the keys asked. For each key the conf sets,
# _cf_<key> holds the value of its last line, as the shell would read it:
# inside its quotes, or up to a comment; a key it does not set is unset.
#   ch_conf_get <conf> <key…>
ch_conf_get() {
  _cf_f="$1"; shift
  for _cf_k in "$@"; do unset "_cf_$_cf_k"; done
  [ -f "$_cf_f" ] || return 0
  _cf_ks=" $* "
  while IFS= read -r _cf_l || [ -n "$_cf_l" ]; do
    _cf_l="${_cf_l#"${_cf_l%%[![:space:]]*}"}"; _cf_l="${_cf_l#export }"
    case "$_cf_l" in [A-Za-z_]*=*) ;; *) continue ;; esac
    _cf_k="${_cf_l%%=*}"
    case "$_cf_k" in *[!A-Za-z0-9_]*) continue ;; esac
    case "$_cf_ks" in *" $_cf_k "*) ;; *) continue ;; esac
    _cf_v="${_cf_l#*=}"
    case "$_cf_v" in
      \"*) _cf_v="${_cf_v#\"}"; _cf_v="${_cf_v%%\"*}" ;;
      \'*) _cf_v="${_cf_v#\'}"; _cf_v="${_cf_v%%\'*}" ;;
      *) _cf_v="${_cf_v%%#*}"; _cf_v="${_cf_v%"${_cf_v##*[![:space:]]}"}" ;;
    esac
    eval "_cf_$_cf_k=\$_cf_v"
  done < "$_cf_f"
  return 0
}

# A command run for at most so many seconds: its own status, and
# CH_LIMIT_HIT=1 when it ran out of time and was stopped. macOS has no
# timeout command, so a watcher in the background stops it. The command
# is started as it is, not in a subshell, so what is stopped is the
# command itself; a function given here must end in exec.
#   ch_with_limit <seconds> <command…>
ch_with_limit() {
  _wl_secs="$1"; shift
  "$@" &
  _wl_pid=$!
  ( _n=0
    while [ "$_n" -lt $((_wl_secs * 10)) ]; do
      sleep 0.1; kill -0 "$_wl_pid" 2>/dev/null || exit 0; _n=$((_n + 1))
    done
    kill "$_wl_pid"; exit 3 ) >/dev/null 2>&1 &
  _wl_w=$!
  # (Each status taken so that a caller under set -e is not ended by it.)
  wait "$_wl_pid" && _wl_rc=0 || _wl_rc=$?
  CH_LIMIT_HIT=""
  # Done by itself: the watcher is not needed. Stopped or failed: whether
  # it was the watcher that stopped it is in how the watcher ended.
  if [ "$_wl_rc" = 0 ]; then
    kill "$_wl_w" 2>/dev/null || :; wait "$_wl_w" 2>/dev/null || :
  else
    wait "$_wl_w" 2>/dev/null && _wl_ws=0 || _wl_ws=$?
    [ "$_wl_ws" != 3 ] || CH_LIMIT_HIT=1
  fi
  return "$_wl_rc"
}

# ── the links' grammars ──────────────────────────────────────────────
# Any web page can open a claude-html:// link, so each kind is a fixed
# grammar, checked whole by the command, and by the Linux handler before
# it hands one on (the Mac helper checks the same in AppleScript).

# A session id: every character one bracket of the pattern, so nothing
# else - a space, a quote, a newline, a slash - can be inside it.
_ch_h='[0-9a-fA-F]'
CH_ID_GLOB="$_ch_h$_ch_h$_ch_h$_ch_h$_ch_h$_ch_h$_ch_h$_ch_h-$_ch_h$_ch_h$_ch_h$_ch_h-$_ch_h$_ch_h$_ch_h$_ch_h-$_ch_h$_ch_h$_ch_h$_ch_h-$_ch_h$_ch_h$_ch_h$_ch_h$_ch_h$_ch_h$_ch_h$_ch_h$_ch_h$_ch_h$_ch_h$_ch_h"
unset _ch_h
ch_is_sid() {
  # shellcheck disable=SC2254
  case "$1" in $CH_ID_GLOB) return 0 ;; esac
  return 1
}

# claude-html://limits/<payload>, from the Token usage page's "apply": new
# limits, rules, budget, budget warnings, banner (limits-cli.sh applies it).
#
#   v1/<rules>/<budget>/<warn>/<notify>
#   rules    none, or up to 8 of day-HHMM-pct joined by dots: fri-2000-80.sat-0000-90
#   budget   none, or dollars-period: 50-week, 12.50-month, 5-day
#   warn     two percentages: 80-95
#   notify   on or off
#
# Lower case letters, digits, dots, slashes and hyphens only, at most 160
# of them, in exactly this order of fields.
CH_LIM_LINK_DAY='(mon|tue|wed|thu|fri|sat|sun)'
CH_LIM_LINK_RULE="$CH_LIM_LINK_DAY-([01][0-9]|2[0-3])[0-5][0-9]-([1-9][0-9]?|100)"
CH_LIM_LINK_RE="v1/(none|$CH_LIM_LINK_RULE([.]$CH_LIM_LINK_RULE){0,7})/(none|[1-9][0-9]{0,5}([.][0-9]{1,2})?-(day|week|month))/[1-9][0-9]?-[1-9][0-9]?/(on|off)"
ch_lim_link_ok() {
  case "$1" in ''|*[!a-z0-9./-]*) return 1 ;; esac
  [ "${#1}" -le 160 ] && printf '%s\n' "$1" | LC_ALL=C grep -Eqx "$CH_LIM_LINK_RE"
}

# claude-html://settings/<payload>, from the Settings page's "apply"
# (settings.sh applies it), at most 2048 characters:
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
# the default. The handler checks only its shape before it hands it on.
CH_SET_LINK_ITEM='(forget-safe(=[0-9a-f]{8})?|edit-list|[A-Z][A-Z_]*(=([A-Za-z0-9._~-]|%[0-9A-F][0-9A-F])+)?)'
CH_SET_LINK_RE="v1/(none|[0-9a-f]{16})(/$CH_SET_LINK_ITEM){1,24}"
ch_set_link_shape() {
  case "$1" in v1/*) ;; *) return 1 ;; esac
  case "$1" in *[!A-Za-z0-9._~%=/-]*) return 1 ;; esac
  [ "${#1}" -le 2048 ]
}
ch_set_link_ok() {
  ch_set_link_shape "$1" && printf '%s\n' "$1" | LC_ALL=C grep -Eqx "$CH_SET_LINK_RE" || return 1
  # No control character, encoded or not.
  case "$1" in *%[01][0-9A-F]*|*%7F*) return 1 ;; esac
  return 0
}
