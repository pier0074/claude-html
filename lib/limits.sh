# Sourced, not run: plan limits, the API budget and the stop rules.
#
#   . "$HERE/lib/limits.sh"
#
# Claude Code hands its status-line command the plan's usage — for Pro,
# Max and Ultra subscribers rate_limits.five_hour and .seven_day, each a
# used_percentage and a resets_at — and the session's cost at list price.
# statusline.sh records the latest of those here; the guard's prompt hook
# stops a new prompt by the owner's rules; the Stop hook announces a rule
# once; the build puts the figures on the pages; claude-html --limits sets
# the rules. All of them read and decide through this file, so they never
# disagree about what is in force.
#
# bash 3.2, BSD and GNU, nothing installed. The status line runs after
# every reply, so the common path starts no command at all but one date:
# what costs a fork (a weekday's local time) is worked out once per week
# and kept in the state file.
#
# Times are epoch seconds. "now" is CLAUDE_HTML_TEST_NOW when set, for the
# tests, which never read the clock to decide anything.

CH_LIM_LOADED=1
CH_LIM_STATE="$HOME/.claude/.claude-html.limits"        # the figures, from the status line
CH_LIM_MARKS="$HOME/.claude/.claude-html.limits-marks"  # what was announced, what is allowed
CH_LIM_SPEND="$HOME/.claude/.claude-html.spend"         # the period's spend, from the build
# Values older than this never stop anything and say so.
CH_LIM_STALE=$((6 * 3600))
CH_LIM_WEEK=604800

ch_lim_now() {
  if [ -n "${CLAUDE_HTML_TEST_NOW:-}" ]; then CH_NOW="$CLAUDE_HTML_TEST_NOW"
  else CH_NOW="$(date +%s)"; fi
}

# Lower case without a command: A-Z only, which is all a setting holds.
ch_lim_lower() {
  _lc="$1"
  for _p in A:a B:b C:c D:d E:e F:f G:g H:h I:i J:j K:k L:l M:m N:n O:o P:p Q:q R:r S:s T:t U:u V:v W:w X:x Y:y Z:z; do
    _lc="${_lc//${_p%:*}/${_p#*:}}"
  done
}

# ── dates, with nothing but date's formatting ─────────────────────────
# Formatting an epoch is the one thing BSD and GNU date both do, each
# with its own flag; the rest is arithmetic. A local time is turned into
# an epoch by guessing its offset and checking it, so a week across a
# change of the clocks lands on the right hour.
ch_lim_datefmt() {   # epoch format   -> stdout
  case "${OSTYPE:-}" in
    darwin*|*bsd*|dragonfly*) LC_ALL=C date -r "$1" "$2" ;;
    *) LC_ALL=C date -d "@$1" "$2" ;;
  esac
}
# The local time of an epoch, into _LY _LM _LD _LU (1 Monday … 7 Sunday)
# _LH _LMI and _LOFF (seconds east of UTC). One fork.
ch_lim_local() {
  local s
  s="$(ch_lim_datefmt "$1" '+%Y %m %d %u %H %M %z')" || return 1
  set -- $s
  _LY=$((10#$1)); _LM=$((10#$2)); _LD=$((10#$3)); _LU=$((10#$4)); _LH=$((10#$5)); _LMI=$((10#$6))
  local z="$7" sign=1
  case "$z" in -*) sign=-1 ;; esac
  z="${z#[+-]}"
  _LOFF=$(( sign * ( 10#${z:0:2} * 3600 + 10#${z:2:2} * 60 ) ))
}
# Days since 1970-01-01 of a civil date, and back (H. Hinnant's).
ch_lim_days() {   # y m d -> _DAYS
  local y=$1 m=$2 d=$3 era yoe doy doe mm
  [ "$m" -le 2 ] && y=$((y - 1))
  era=$(( (y >= 0 ? y : y - 399) / 400 )); yoe=$((y - era * 400))
  if [ "$m" -gt 2 ]; then mm=$((m - 3)); else mm=$((m + 9)); fi
  doy=$(( (153 * mm + 2) / 5 + d - 1 ))
  doe=$(( yoe * 365 + yoe / 4 - yoe / 100 + doy ))
  _DAYS=$(( era * 146097 + doe - 719468 ))
}
ch_lim_civil() {   # days -> _CY _CM _CD
  local z=$(( $1 + 719468 )) era doe yoe doy mp
  era=$(( (z >= 0 ? z : z - 146096) / 146097 )); doe=$((z - era * 146097))
  yoe=$(( (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365 ))
  doy=$(( doe - (365 * yoe + yoe / 4 - yoe / 100) )); mp=$(( (5 * doy + 2) / 153 ))
  _CD=$(( doy - (153 * mp + 2) / 5 + 1 ))
  if [ "$mp" -lt 10 ]; then _CM=$((mp + 3)); else _CM=$((mp - 9)); fi
  _CY=$(( yoe + era * 400 )); [ "$_CM" -le 2 ] && _CY=$((_CY + 1))
}
# The epoch of a local day number at h:m, offset guessed by $4 and then
# checked: two forks at most, three across a change of the clocks.
ch_lim_mktime() {   # days h m hint_offset -> _LT
  local t0=$(( $1 * 86400 + $2 * 3600 + $3 * 60 )) off="$4" n=0
  _LT=$(( t0 - off ))
  while [ $n -lt 2 ]; do
    ch_lim_local "$_LT" || return 1
    [ "$_LOFF" = "$off" ] && return 0
    off="$_LOFF"; _LT=$(( t0 - off )); n=$((n + 1))
  done
}

# ── settings ─────────────────────────────────────────────────────────
# The environment wins over the conf, the conf over the default, as for
# every setting. A script that sourced conf.sh already has them decided;
# the status line reads the conf itself, line by line, without running it.
CH_LIM_KEYS="CLAUDE_HTML_LIMITS CLAUDE_HTML_LIMIT_RULES CLAUDE_HTML_BUDGET CLAUDE_HTML_BUDGET_WARN CLAUDE_HTML_LIMIT_NOTIFY CLAUDE_HTML_WEEK_RESET"
# CH_LIM_EXTRA_KEYS: more keys read in the same pass, for a caller that
# needs its own settings too (the status line's), without a second read.
ch_lim_settings() {
  local k unset_keys="" line v conf="${CLAUDE_HTML_CONF:-$HOME/.claude/claude-html.conf}"
  for k in $CH_LIM_KEYS ${CH_LIM_EXTRA_KEYS:-}; do eval "[ -n \"\${$k+x}\" ]" || unset_keys="$unset_keys $k"; done
  if [ -n "$unset_keys" ] && [ -f "$conf" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      line="${line#"${line%%[![:space:]]*}"}"; line="${line#export }"
      case "$line" in CLAUDE_HTML_[A-Z_]*=*) ;; *) continue ;; esac
      k="${line%%=*}"
      case " $unset_keys " in *" $k "*) ;; *) continue ;; esac
      v="${line#*=}"
      case "$v" in
        \"*) v="${v#\"}"; v="${v%%\"*}" ;;
        \'*) v="${v#\'}"; v="${v%%\'*}" ;;
        *) v="${v%%#*}"; v="${v%"${v##*[![:space:]]}"}" ;;
      esac
      eval "_set_$k=\$v"
    done < "$conf"
  fi
  for k in $CH_LIM_KEYS ${CH_LIM_EXTRA_KEYS:-}; do
    case " $unset_keys " in
      *" $k "*) eval "if [ -n \"\${_set_$k+x}\" ]; then $k=\"\$_set_$k\"; unset _set_$k; else $k=; fi" ;;
    esac
  done
  CH_LIM_ON=1
  case "$CLAUDE_HTML_LIMITS" in [Oo][Ff][Ff]|0|[Nn][Oo]|[Ff][Aa][Ll][Ss][Ee]) CH_LIM_ON="" ;; esac
  CH_LIM_NOTIFY=""
  case "$CLAUDE_HTML_LIMIT_NOTIFY" in [Oo][Nn]|1|[Yy][Ee][Ss]|[Tt][Rr][Uu][Ee]) CH_LIM_NOTIFY=1 ;; esac
  ch_lim_parse_rules "$CLAUDE_HTML_LIMIT_RULES"
  ch_lim_parse_budget "$CLAUDE_HTML_BUDGET"
  ch_lim_parse_warn "$CLAUDE_HTML_BUDGET_WARN" || :
}

# A rule: from a weekday and a local time until the weekly reset, a new
# prompt is stopped once the week is past its percentage. Written
# "fri 20:00 80%", several joined by " · " (or a comma or semicolon).
# Into CH_LIM_N and, from 1, CH_LIM_RD (1 Monday … 7 Sunday), CH_LIM_RH,
# CH_LIM_RM, CH_LIM_RP, CH_LIM_RT (canonical) and CH_LIM_RL ("Fri 20:00");
# what is not a rule goes to CH_LIM_BAD.
CH_LIM_DAYS="mon tue wed thu fri sat sun"
ch_lim_day_num() {   # word -> _DN (0 if none)
  _DN=0; local i=1 d
  for d in $CH_LIM_DAYS; do case "$1" in "$d"*) _DN=$i; return 0 ;; esac; i=$((i + 1)); done
  return 1
}
ch_lim_day_name() {   # 1..7 -> _DW mon, _DL Mon
  set -- $CH_LIM_DAYS "$1"; local n="${8}"
  eval "_DW=\${$n}"
  case "$_DW" in mon) _DL=Mon ;; tue) _DL=Tue ;; wed) _DL=Wed ;; thu) _DL=Thu ;; fri) _DL=Fri ;; sat) _DL=Sat ;; sun) _DL=Sun ;; esac
}
CH_LIM_RULE_RE='^(mon|tue|wed|thu|fri|sat|sun)[a-z]*[[:space:]]+([0-9]{1,2}):([0-9]{2})[[:space:]]+([0-9]{1,3})[[:space:]]*%?$'
ch_lim_parse_one() {   # text -> _RD _RH _RM _RP, or fails
  local t="$1"
  t="${t#"${t%%[![:space:]]*}"}"; t="${t%"${t##*[![:space:]]}"}"
  ch_lim_lower "$t"; t="$_lc"
  [[ "$t" =~ $CH_LIM_RULE_RE ]] || return 1
  ch_lim_day_num "${BASH_REMATCH[1]}"; _RD=$_DN
  # The day as written must be a day's name, or the start of one ("fri",
  # "friday"), not "frisbee".
  case "${BASH_REMATCH[0]%%[[:space:]]*}" in
    mon|monday|tue|tues|tuesday|wed|weds|wednesday|thu|thur|thurs|thursday|fri|friday|sat|saturday|sun|sunday) ;;
    *) return 1 ;;
  esac
  _RH=$((10#${BASH_REMATCH[2]})); _RM=$((10#${BASH_REMATCH[3]})); _RP=$((10#${BASH_REMATCH[4]}))
  [ "$_RH" -le 23 ] && [ "$_RM" -le 59 ] && [ "$_RP" -ge 1 ] && [ "$_RP" -le 100 ]
}
CH_LIM_MAX_RULES=8
ch_lim_parse_rules() {
  CH_LIM_N=0; CH_LIM_BAD=""
  local raw="$1" item rest
  raw="${raw//·/,}"; raw="${raw//;/,}"
  while [ -n "$raw" ]; do
    item="${raw%%,*}"
    if [ "$item" = "$raw" ]; then raw=""; else raw="${raw#*,}"; fi
    rest="${item//[[:space:]]/}"
    [ -n "$rest" ] || continue
    if ch_lim_parse_one "$item" && [ "$CH_LIM_N" -lt "$CH_LIM_MAX_RULES" ]; then
      CH_LIM_N=$((CH_LIM_N + 1))
      ch_lim_day_name "$_RD"
      CH_LIM_RD[$CH_LIM_N]=$_RD; CH_LIM_RH[$CH_LIM_N]=$_RH; CH_LIM_RM[$CH_LIM_N]=$_RM; CH_LIM_RP[$CH_LIM_N]=$_RP
      printf -v _hm '%02d:%02d' "$_RH" "$_RM"
      CH_LIM_RT[$CH_LIM_N]="$_DW $_hm ${_RP}%"
      CH_LIM_RL[$CH_LIM_N]="$_DL $_hm"
    else
      item="${item#"${item%%[![:space:]]*}"}"; item="${item%"${item##*[![:space:]]}"}"
      CH_LIM_BAD="${CH_LIM_BAD:+$CH_LIM_BAD, }$item"
    fi
  done
}
# The rules as the conf holds them, into _RTXT.
ch_lim_rules_text() {
  local i=1
  _RTXT=""
  while [ $i -le "$CH_LIM_N" ]; do _RTXT="${_RTXT:+$_RTXT · }${CH_LIM_RT[$i]}"; i=$((i + 1)); done
}

# The budget: an amount in dollars and a period, "50 week" (or day,
# month); off or empty is none. Into CH_LIM_BC (cents, 0 for none),
# CH_LIM_BA ("50" or "12.50") and CH_LIM_BP.
CH_LIM_BUDGET_RE='^\$?([0-9]{1,6})(\.([0-9]{1,2}))?[[:space:]]*(/|per)?[[:space:]]*(day|week|month)$'
ch_lim_parse_budget() {
  CH_LIM_BC=0; CH_LIM_BA=""; CH_LIM_BP=""; CH_LIM_BBAD=""
  local t="$1" c
  t="${t#"${t%%[![:space:]]*}"}"; t="${t%"${t##*[![:space:]]}"}"
  ch_lim_lower "$t"; t="$_lc"
  case "$t" in ''|off|none|0|no|false) return 0 ;; esac
  if [[ "$t" =~ $CH_LIM_BUDGET_RE ]]; then
    c="${BASH_REMATCH[3]}"; [ ${#c} = 1 ] && c="${c}0"; [ -z "$c" ] && c=00
    CH_LIM_BC=$(( 10#${BASH_REMATCH[1]} * 100 + 10#$c ))
    CH_LIM_BP="${BASH_REMATCH[5]}"
    if [ "$CH_LIM_BC" -le 0 ]; then CH_LIM_BC=0; CH_LIM_BP=""; CH_LIM_BBAD="$1"; return 0; fi
    if [ $((CH_LIM_BC % 100)) = 0 ]; then CH_LIM_BA="$((CH_LIM_BC / 100))"
    else CH_LIM_BA="$((CH_LIM_BC / 100)).$(printf '%02d' $((CH_LIM_BC % 100)))"; fi
  else
    CH_LIM_BBAD="$1"
  fi
}
# Budget warnings, two percentages: "80 95". Fails for what is not two
# such, the first lower, which leaves the default in force.
ch_lim_parse_warn() {
  CH_LIM_W1=80; CH_LIM_W2=95
  local t="$1"
  t="${t//,/ }"; t="${t//%/ }"
  set -- $t
  if [ $# = 2 ] && [[ "$1" =~ ^[0-9]{1,2}$ ]] && [[ "$2" =~ ^[0-9]{1,2}$ ]] &&
     [ $((10#$1)) -ge 1 ] && [ $((10#$1)) -lt $((10#$2)) ]; then
    CH_LIM_W1=$((10#$1)); CH_LIM_W2=$((10#$2))
  else
    [ $# = 0 ] || return 1
  fi
  return 0
}
ch_lim_period_word() {   # day|week|month -> _PW ("today", "this week", "this month")
  case "$1" in day) _PW=today ;; month) _PW="this month" ;; *) _PW="this week" ;; esac
}

# ── the state ────────────────────────────────────────────────────────
# key=value lines, written whole beside the file and moved over it, so a
# reader never sees half. Readable by its owner only.
CH_LIM_SKEYS="asof five_pct five_reset week_pct week_reset plan_seen cost session five_label week_label wk_key wk_starts per_key per_start per_end per_label"
ch_lim_read_state() {
  local k v
  for k in $CH_LIM_SKEYS; do eval "S_$k="; done
  [ -f "$CH_LIM_STATE" ] || return 1
  while IFS='=' read -r k v || [ -n "$k" ]; do
    case " $CH_LIM_SKEYS " in *" $k "*) ;; *) continue ;; esac
    case "$v" in *[!A-Za-z0-9.:\ _,-]*) continue ;; esac
    eval "S_$k=\$v"
  done < "$CH_LIM_STATE"
  return 0
}
ch_lim_write_kv() {   # file, then "key" for each key whose value is in $S_key / $M_key
  local f="$1" pre="$2" k v tmp; shift 2
  tmp="$f.tmp.$$"
  mkdir -p "${f%/*}" 2>/dev/null
  # The callers run under umask 077: the file is its owner's alone.
  { for k in "$@"; do eval "v=\${$pre$k-}"; [ -n "$v" ] && printf '%s=%s\n' "$k" "$v"; done; :; } > "$tmp" 2>/dev/null &&
    mv -f "$tmp" "$f" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
}
ch_lim_write_state() { ch_lim_write_kv "$CH_LIM_STATE" S_ $CH_LIM_SKEYS; }

# What was announced, and what was allowed: tokens, each ending at a
# time after which it means nothing.
#   told   <until>:<what> …     a rule or a budget level announced this period
#   allow  <until>              no more asking about the week until then
#   ballow <until>              the same for the budget
CH_LIM_MKEYS="told allow ballow"
ch_lim_read_marks() {
  local k v
  M_told=""; M_allow=0; M_ballow=0
  [ -f "$CH_LIM_MARKS" ] || return 1
  while IFS='=' read -r k v || [ -n "$k" ]; do
    case "$v" in *[!A-Za-z0-9.:\ _,-]*) continue ;; esac
    case "$k" in
      told) M_told="$v" ;;
      allow) case "$v" in ''|*[!0-9]*) ;; *) M_allow="$v" ;; esac ;;
      ballow) case "$v" in ''|*[!0-9]*) ;; *) M_ballow="$v" ;; esac ;;
    esac
  done < "$CH_LIM_MARKS"
}
ch_lim_write_marks() {
  # Gone: what ended before now.
  local t keep=""
  for t in $M_told; do [ "${t%%:*}" -gt "$CH_NOW" ] 2>/dev/null && keep="$keep $t"; done
  M_told="${keep# }"
  [ "${M_allow:-0}" -gt "$CH_NOW" ] 2>/dev/null || M_allow=""
  [ "${M_ballow:-0}" -gt "$CH_NOW" ] 2>/dev/null || M_ballow=""
  ch_lim_write_kv "$CH_LIM_MARKS" M_ $CH_LIM_MKEYS
}
ch_lim_told() {   # until what -> 0 if already told
  case " $M_told " in *" $1:$2 "*) return 0 ;; esac
  return 1
}

# A percentage as Claude Code gives it ("81", "81.4", "8.1e1" never) in
# tenths, for comparing without floating point.
ch_lim_tenths() {   # text -> _TEN (or fails)
  local t="$1" i f
  [[ "$t" =~ ^([0-9]{1,3})(\.([0-9]+))?$ ]] || return 1
  i=$((10#${BASH_REMATCH[1]})); f="${BASH_REMATCH[3]:-0}"
  _TEN=$(( i * 10 + 10#${f:0:1} ))
}
# Whole percent, rounded half up, for the eye.
ch_lim_round() {   # text -> _RND
  ch_lim_tenths "$1" || { _RND=""; return 1; }
  _RND=$(( (_TEN + 5) / 10 ))
}
# Dollars ("1.1234", "12", "0.5") in micro-dollars.
ch_lim_micro() {   # text -> _MIC
  local t="$1" f
  [[ "$t" =~ ^([0-9]{1,9})(\.([0-9]*))?$ ]] || { _MIC=""; return 1; }
  f="${BASH_REMATCH[3]}000000"; f="${f:0:6}"
  _MIC=$(( 10#${BASH_REMATCH[1]} * 1000000 + 10#$f ))
}
ch_lim_money() {   # micro -> _MON "$38.20"
  local c=$(( ($1 + 5000) / 10000 ))
  _MON="\$$((c / 100)).$(printf '%02d' $((c % 100)))"
}

# ── the week ─────────────────────────────────────────────────────────
# Into CH_WS (start) and CH_WR (the reset that ends it), and CH_WSRC:
#   rate_limits   Claude Code's own seven_day.resets_at: exact
#   rate_limits*  the same, last seen before a reset has since passed
#   conf          CLAUDE_HTML_WEEK_RESET
#   calendar      Monday 00:00, local
# Needs ch_lim_read_state and CH_NOW.
CH_LIM_RESET_RE='^(sun|mon|tue|wed|thu|fri|sat)[a-z]*[[:space:],]+([0-9]{1,2})(:([0-9]{2}))?([[:space:]]*(utc|gmt|z))?$'
# CLAUDE_HTML_WEEK_RESET read, as the dashboard's parseReset reads it: into
# _WDOW (0 Sunday … 6 Saturday), _WH, _WM and _WUTC ("" for local time), and
# _WSPEC as it is written back ("tue 07:00 UTC"); fails for what is not one.
ch_lim_reset_parse() {   # text
  local spec="$1"
  spec="${spec#"${spec%%[![:space:]]*}"}"; spec="${spec%"${spec##*[![:space:]]}"}"
  ch_lim_lower "$spec"; spec="$_lc"
  [[ "$spec" =~ $CH_LIM_RESET_RE ]] || return 1
  ch_lim_day_num "${BASH_REMATCH[1]}"; _WDOW=$((_DN % 7))
  _WH=$((10#${BASH_REMATCH[2]})); _WM=$((10#${BASH_REMATCH[4]:-0})); _WUTC="${BASH_REMATCH[6]}"
  [ "$_WH" -le 23 ] && [ "$_WM" -le 59 ] || return 1
  printf -v _WSPEC '%s %02d:%02d%s' "${BASH_REMATCH[1]}" "$_WH" "$_WM" "${_WUTC:+ UTC}"
}
ch_lim_week() {
  local r="${S_week_reset:-}" k spec dow h m utc day back cand
  case "$r" in ''|*[!0-9]*) r="" ;; esac
  if [ -n "$r" ]; then
    if [ "$r" -gt "$CH_NOW" ]; then CH_WR=$r; CH_WSRC=rate_limits
    else k=$(( (CH_NOW - r) / CH_LIM_WEEK + 1 )); CH_WR=$(( r + k * CH_LIM_WEEK )); CH_WSRC='rate_limits*'; fi
    CH_WS=$(( CH_WR - CH_LIM_WEEK ))
    return 0
  fi
  if ch_lim_reset_parse "${CLAUDE_HTML_WEEK_RESET:-}"; then
    dow=$_WDOW; h=$_WH; m=$_WM; utc=$_WUTC; CH_WSRC=conf
  else
    dow=1; h=0; m=0; utc=""; CH_WSRC=calendar
  fi
  if [ -n "$utc" ]; then
    # Fixed in UTC: arithmetic, the same moment every week.
    day=$(( CH_NOW / 86400 )); back=$(( ( (day + 4) % 7 - dow + 7) % 7 ))
    cand=$(( (day - back) * 86400 + h * 3600 + m * 60 ))
    [ "$cand" -gt "$CH_NOW" ] && cand=$((cand - CH_LIM_WEEK))
    CH_WS=$cand; CH_WR=$((cand + CH_LIM_WEEK))
    return 0
  fi
  # Local: the same hour on the clock every week, whatever the offset.
  ch_lim_local "$CH_NOW" || return 1
  ch_lim_days "$_LY" "$_LM" "$_LD"; day=$_DAYS
  back=$(( (_LU % 7 - dow + 7) % 7 ))
  ch_lim_mktime $((day - back)) "$h" "$m" "$_LOFF" || return 1
  if [ "$_LT" -gt "$CH_NOW" ]; then back=$((back + 7)); ch_lim_mktime $((day - back)) "$h" "$m" "$_LOFF" || return 1; fi
  CH_WS=$_LT
  ch_lim_mktime $((day - back + 7)) "$h" "$m" "$_LOFF" || return 1
  CH_WR=$_LT
}

# When each rule starts in the week [CH_WS, CH_WR): the first time its
# weekday and local hour come round from the week's start. Into
# CH_LIM_RS[i]. Kept in the state by the week and the rules, so the
# status line works it out once a week.
ch_lim_rule_starts() {
  local key i base off
  ch_lim_rules_text
  key="${_RTXT//[ ·:%]/}"; key="$CH_WS:$key"
  if [ "${S_wk_key:-}" = "$key" ] && [ -n "${S_wk_starts:-}" ]; then
    i=1
    for off in ${S_wk_starts//,/ }; do CH_LIM_RS[$i]=$off; i=$((i + 1)); done
    [ $((i - 1)) = "$CH_LIM_N" ] && return 0
  fi
  [ "$CH_LIM_N" -gt 0 ] || return 0
  ch_lim_local "$CH_WS" || return 1
  ch_lim_days "$_LY" "$_LM" "$_LD"; base=$_DAYS
  local u=$_LU hint=$_LOFF starts=""
  i=1
  while [ $i -le "$CH_LIM_N" ]; do
    off=$(( (CH_LIM_RD[$i] - u + 7) % 7 ))
    ch_lim_mktime $((base + off)) "${CH_LIM_RH[$i]}" "${CH_LIM_RM[$i]}" "$hint" || return 1
    [ "$_LT" -lt "$CH_WS" ] && { ch_lim_mktime $((base + off + 7)) "${CH_LIM_RH[$i]}" "${CH_LIM_RM[$i]}" "$hint" || return 1; }
    CH_LIM_RS[$i]=$_LT; starts="${starts:+$starts,}$_LT"
    i=$((i + 1))
  done
  S_wk_key="$key"; S_wk_starts="$starts"; CH_LIM_STARTS_NEW=1
}

# Whether the figures are recent enough to act on: seen within six hours,
# and for a week that has not reset since.
ch_lim_fresh() {
  case "${S_asof:-}" in ''|*[!0-9]*) return 1 ;; esac
  [ -n "${S_week_pct:-}" ] || return 1
  [ $(( CH_NOW - S_asof )) -le "$CH_LIM_STALE" ] || return 1
  case "${S_week_reset:-}" in ''|*[!0-9]*) return 1 ;; esac
  [ "$S_week_reset" -gt "$CH_NOW" ]
}
# Plan figures seen within a week: the budget is for API use, and a
# subscriber's list-price cost is not what they pay.
ch_lim_on_plan() {
  case "${S_plan_seen:-}" in ''|*[!0-9]*) return 1 ;; esac
  [ $(( CH_NOW - S_plan_seen )) -le $((CH_LIM_WEEK + 86400)) ]
}

# The rule that matters now, into CH_LIM_CUR (0 for none) and
# CH_LIM_CUR_FORCE (1 when it is in force): of those in force, the one
# with the lowest percentage; else the next to start. Needs the starts.
ch_lim_current() {
  local i best=0 bestp=101 next=0 nexts=0
  CH_LIM_CUR=0; CH_LIM_CUR_FORCE=""
  i=1
  while [ $i -le "$CH_LIM_N" ]; do
    if [ "${CH_LIM_RS[$i]}" -le "$CH_NOW" ] && [ "$CH_NOW" -lt "$CH_WR" ]; then
      [ "${CH_LIM_RP[$i]}" -lt "$bestp" ] && { best=$i; bestp=${CH_LIM_RP[$i]}; }
    elif [ "$next" = 0 ] || [ "${CH_LIM_RS[$i]}" -lt "$nexts" ]; then
      next=$i; nexts=${CH_LIM_RS[$i]}
    fi
    i=$((i + 1))
  done
  if [ "$best" != 0 ]; then CH_LIM_CUR=$best; CH_LIM_CUR_FORCE=1; else CH_LIM_CUR=$next; fi
}
# The rule that stops a prompt now, into CH_LIM_HIT (0 for none): in
# force, and the week at or past its percentage. Needs fresh figures.
ch_lim_hit() {
  local i bestp=101
  CH_LIM_HIT=0
  ch_lim_tenths "${S_week_pct:-}" || return 1
  i=1
  while [ $i -le "$CH_LIM_N" ]; do
    if [ "${CH_LIM_RS[$i]}" -le "$CH_NOW" ] && [ "$CH_NOW" -lt "$CH_WR" ] &&
       [ "$_TEN" -ge $(( CH_LIM_RP[$i] * 10 )) ] && [ "${CH_LIM_RP[$i]}" -lt "$bestp" ]; then
      CH_LIM_HIT=$i; bestp=${CH_LIM_RP[$i]}
    fi
    i=$((i + 1))
  done
  [ "$CH_LIM_HIT" != 0 ]
}

# A time to show: "16:30" today, else "Tue 08:00". One fork.
ch_lim_label() {   # epoch -> _LBL
  local a b
  a="$(ch_lim_datefmt "$1" '+%Y%m%d|%a %H:%M')" || { _LBL=""; return 1; }
  b="$(ch_lim_datefmt "$CH_NOW" '+%Y%m%d')"
  if [ "${a%%|*}" = "$b" ]; then _LBL="${a##* }"; else _LBL="${a#*|}"; fi
}
ch_lim_wlabel() {   # epoch -> _LBL "Tue 08:00", always with its day
  _LBL="$(ch_lim_datefmt "$1" '+%a %H:%M')"
}

# ── the budget's period and what was spent in it ─────────────────────
# Into CH_PS and CH_PE. A week is the plan's week as above; a day and a
# month are local, from midnight.
ch_lim_period() {
  # Kept in the state while it lasts: a local week, a day or a month costs
  # a few forks to work out, and the status line asks after every reply.
  local key="$CH_LIM_BP|${CLAUDE_HTML_WEEK_RESET:-}|${S_week_reset:-}"
  key="${key//[!A-Za-z0-9:|]/_}"
  if [ "${S_per_key:-}" = "$key" ] && [ "${S_per_start:-x}" -le "$CH_NOW" ] 2>/dev/null &&
     [ "$CH_NOW" -lt "${S_per_end:-0}" ] 2>/dev/null; then
    CH_PS=$S_per_start; CH_PE=$S_per_end; return 0
  fi
  ch_lim_period_calc || return 1
  S_per_key="$key"; S_per_start=$CH_PS; S_per_end=$CH_PE; S_per_label=""; CH_LIM_STARTS_NEW=1
}
ch_lim_period_calc() {
  case "$CH_LIM_BP" in
    week) ch_lim_week || return 1; CH_PS=$CH_WS; CH_PE=$CH_WR ;;
    day|month)
      ch_lim_local "$CH_NOW" || return 1
      local hint=$_LOFF y=$_LY m=$_LM d=$_LD
      if [ "$CH_LIM_BP" = day ]; then
        ch_lim_days $y $m $d; ch_lim_mktime "$_DAYS" 0 0 "$hint" || return 1; CH_PS=$_LT
        ch_lim_mktime $((_DAYS + 1)) 0 0 "$hint" || return 1; CH_PE=$_LT
      else
        ch_lim_days $y $m 1; ch_lim_mktime "$_DAYS" 0 0 "$hint" || return 1; CH_PS=$_LT
        if [ $m = 12 ]; then ch_lim_days $((y + 1)) 1 1; else ch_lim_days $y $((m + 1)) 1; fi
        ch_lim_mktime "$_DAYS" 0 0 "$hint" || return 1; CH_PE=$_LT
      fi ;;
    *) return 1 ;;
  esac
}
# What the build last counted for the period (limits.js weekSpend: the
# recorded cost, or the price table's for a session with none), plus this
# session's own cost where the build has not counted it yet. Into CH_SPENT (micro-dollars) and
# CH_SPENT_KNOWN (1, or empty when no build has counted it).
ch_lim_spent() {   # [session id]
  local k v start="" end="" micro="" ids=""
  CH_SPENT=0; CH_SPENT_KNOWN=""
  if [ -f "$CH_LIM_SPEND" ]; then
    while IFS='=' read -r k v || [ -n "$k" ]; do
      case "$k" in
        start) start="$v" ;; end) end="$v" ;; micro) micro="$v" ;; ids) ids="$v" ;;
      esac
    done < "$CH_LIM_SPEND"
  fi
  case "$start$end$micro" in *[!0-9]*) start=""; end="" ;; esac
  if [ -n "$start" ] && [ "$start" = "$CH_PS" ] && [ -n "$micro" ]; then
    CH_SPENT=$micro; CH_SPENT_KNOWN=1
  elif [ -n "$end" ] && [ "$end" -le "$CH_PS" ]; then
    # Counted for a period that has ended: nothing recorded in this one yet.
    CH_SPENT=0; CH_SPENT_KNOWN=1; ids=""
  fi
  if [ -n "${1:-}" ] && [ "${S_session:-}" = "$1" ] && ch_lim_micro "${S_cost:-}"; then
    case ",$ids," in *",$1,"*) ;; *) CH_SPENT=$((CH_SPENT + _MIC)) ;; esac
  fi
}
# The budget's share spent, in tenths of a percent, into CH_BT.
ch_lim_budget_tenths() { CH_BT=$(( CH_SPENT / (CH_LIM_BC > 0 ? CH_LIM_BC : 1) / 10 )); }

# ── a desktop banner, when asked for ─────────────────────────────────
# macOS through osascript (its source shows as Script Editor), Linux
# through notify-send where the desktop has one; nothing over ssh, with
# no display, or under WSL. In the background: nothing waits on it.
ch_lim_banner() {   # text
  [ -n "$CH_LIM_NOTIFY" ] || return 0
  [ -z "${SSH_CONNECTION:-}${SSH_TTY:-}" ] || return 0
  # CLAUDE_HTML_NO_SCREEN, as platform.sh's ch_screen_off has it: noted, not shown.
  if [ -n "${CLAUDE_HTML_NO_SCREEN:-}" ]; then
    printf 'banner %s\n' "$1" 2>/dev/null >> "$CLAUDE_HTML_NO_SCREEN" || true; return 0
  fi
  case "${CLAUDE_HTML_UNAME:-${OSTYPE:-}}" in
    Darwin|darwin*)
      command -v osascript >/dev/null 2>&1 || return 0
      osascript -e 'on run argv' -e 'display notification (item 1 of argv) with title "claude-html"' \
        -e 'end run' "$1" </dev/null >/dev/null 2>&1 & ;;
    *)
      [ -n "${WSL_DISTRO_NAME:-}" ] && return 0
      [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] || return 0
      command -v notify-send >/dev/null 2>&1 || return 0
      notify-send -a claude-html claude-html "$1" </dev/null >/dev/null 2>&1 & ;;
  esac
  return 0
}

# ── announcements, from the Stop hook ────────────────────────────────
# One line in Claude Code after a reply, never twice for the same thing:
# a rule about to apply (it starts within the next twelve hours and the
# week is already within five points of it), a rule that has started
# (the same nearness), a budget level reached (for API use). Never the
# plan's own percentages: Claude Code warns about those itself. Prints
# the lines, one per thing; remembers them in the marks.
CH_LIM_SOON=$((12 * 3600))
ch_lim_announce() {   # [session id]
  CH_ANN=""
  [ -n "$CH_LIM_ON" ] || return 0
  [ "$CH_LIM_N" -gt 0 ] || [ "$CH_LIM_BC" -gt 0 ] || return 0
  ch_lim_now; ch_lim_read_state; ch_lim_read_marks
  local i p wk changed="" line
  if [ "$CH_LIM_N" -gt 0 ] && ch_lim_fresh && ch_lim_week && ch_lim_rule_starts && ch_lim_tenths "$S_week_pct"; then
    ch_lim_round "$S_week_pct"; wk=$_RND
    i=1
    while [ $i -le "$CH_LIM_N" ]; do
      p=${CH_LIM_RP[$i]}
      if [ "$_TEN" -ge $(( (p - 5) * 10 )) ]; then
        line=""
        if [ "$CH_NOW" -ge "${CH_LIM_RS[$i]}" ]; then
          ch_lim_told "$CH_WR" "start-${CH_LIM_RS[$i]}-$p" ||
            { line="your stop rule is in force since ${CH_LIM_RL[$i]} at $p % · week now $wk %"
              M_told="$M_told $CH_WR:start-${CH_LIM_RS[$i]}-$p $CH_WR:soon-${CH_LIM_RS[$i]}-$p"; }
        elif [ $(( CH_LIM_RS[$i] - CH_NOW )) -le "$CH_LIM_SOON" ]; then
          ch_lim_told "$CH_WR" "soon-${CH_LIM_RS[$i]}-$p" ||
            { line="your stop rule starts ${CH_LIM_RL[$i]} at $p % · week now $wk %"
              M_told="$M_told $CH_WR:soon-${CH_LIM_RS[$i]}-$p"; }
        fi
        [ -n "$line" ] && { CH_ANN="${CH_ANN:+$CH_ANN
}$line"; changed=1; }
      fi
      i=$((i + 1))
    done
  fi
  if [ "$CH_LIM_BC" -gt 0 ] && ! ch_lim_on_plan && ch_lim_period; then
    ch_lim_spent "${1:-}"
    if [ -n "$CH_SPENT_KNOWN" ]; then
      ch_lim_budget_tenths; ch_lim_period_word "$CH_LIM_BP"; ch_lim_money "$CH_SPENT"
      for p in $CH_LIM_W2 $CH_LIM_W1; do
        if [ "$CH_BT" -ge $((p * 10)) ]; then
          ch_lim_told "$CH_PE" "budget-$CH_PS-$p" || {
            CH_ANN="${CH_ANN:+$CH_ANN
}API budget at $(( (CH_BT + 5) / 10 )) % · $_MON of \$$CH_LIM_BA $_PW"
            changed=1
          }
          # The higher level says it all: the lower one is not said after it.
          local q; for q in $CH_LIM_W1 $CH_LIM_W2; do
            [ "$q" -le "$p" ] && ! ch_lim_told "$CH_PE" "budget-$CH_PS-$q" && M_told="$M_told $CH_PE:budget-$CH_PS-$q"
          done
          break
        fi
      done
    fi
  fi
  [ -n "$changed" ] && ch_lim_write_marks
  return 0
}

# ── the page's data ──────────────────────────────────────────────────
# Everything the plan line, the budget line and the Limits & budget
# section show, as JSON for the build: settings, the week, the rules with
# their starts, the latest figures with their time. The pages stay
# static; this is as of the build.
ch_lim_json() {
  ch_lim_settings
  # Nothing set and nothing seen: nothing to show, and the pages stay as
  # they were before any of this existed.
  if [ "$CH_LIM_N" = 0 ] && [ "$CH_LIM_BC" = 0 ] && [ ! -f "$CH_LIM_STATE" ]; then printf 'null'; return 0; fi
  ch_lim_now; ch_lim_read_state
  ch_lim_week || { printf 'null'; return 0; }
  ch_lim_rule_starts >/dev/null 2>&1
  local i o rules="" plan="null" budget="null" fresh=false five="null" week="null"
  i=1
  while [ $i -le "$CH_LIM_N" ]; do
    ch_lim_day_name "${CH_LIM_RD[$i]}"
    printf -v _hm '%02d:%02d' "${CH_LIM_RH[$i]}" "${CH_LIM_RM[$i]}"
    o="{\"day\":\"$_DW\",\"time\":\"$_hm\",\"pct\":${CH_LIM_RP[$i]},\"start\":${CH_LIM_RS[$i]:-null}}"
    rules="${rules:+$rules,}$o"
    i=$((i + 1))
  done
  ch_lim_fresh && fresh=true
  if [ -n "${S_asof:-}" ] && [ -n "${S_week_pct:-}${S_five_pct:-}" ]; then
    ch_lim_tenths "${S_five_pct:-}" && [ -n "${S_five_reset:-}" ] && five="{\"pct\":$S_five_pct,\"reset\":$S_five_reset}"
    ch_lim_tenths "${S_week_pct:-}" && [ -n "${S_week_reset:-}" ] && week="{\"pct\":$S_week_pct,\"reset\":$S_week_reset}"
    plan="{\"five\":$five,\"week\":$week,\"asof\":$S_asof,\"fresh\":$fresh}"
  fi
  if [ "$CH_LIM_BC" -gt 0 ] && ch_lim_period; then
    budget="{\"cents\":$CH_LIM_BC,\"amount\":\"$CH_LIM_BA\",\"period\":\"$CH_LIM_BP\",\"start\":$CH_PS,\"end\":$CH_PE}"
  fi
  local onplan=false; ch_lim_on_plan && onplan=true
  local on=false notify=false; [ -n "$CH_LIM_ON" ] && on=true; [ -n "$CH_LIM_NOTIFY" ] && notify=true
  printf '{"on":%s,"rules":[%s],"budget":%s,"warn":[%s,%s],"notify":%s,"week":{"start":%s,"reset":%s,"source":"%s"},"plan":%s,"onPlan":%s,"now":%s,"spendFile":%s}' \
    "$on" "$rules" "$budget" "$CH_LIM_W1" "$CH_LIM_W2" "$notify" "$CH_WS" "$CH_WR" "$CH_WSRC" "$plan" "$onplan" "$CH_NOW" \
    "$(ch_json_str "$CH_LIM_SPEND")"
}

# ── the stop, from the guard's prompt hook ───────────────────────────
# Gentle: only a new prompt is ever stopped, never a task already running
# and never a command. When a rule is in force and the week is at or past
# its percentage — or, for API use, the budget is spent — the prompt waits
# for an answer in the guard's own window: Cancel (picked already), Allow
# once, Allow until the reset, Stop (the rule, or the budget, off). With
# no one at the screen, the answer is the next prompt, one word: cancel,
# allow, until or stop. Figures more than six hours old, or none, never
# stop anything. Prints the hook's decision, or nothing to let it go.
ch_lim_block() {
  local r="$1"
  r="${r//\\/\\\\}"; r="${r//\"/\\\"}"; r="${r//$'\n'/\\n}"
  # Left out of the message only from inside hookSpecificOutput; at the top
  # level Claude Code ignores it and keeps the prompt in the transcript.
  printf '{"decision":"block","reason":"%s","hookSpecificOutput":{"hookEventName":"UserPromptSubmit","suppressOriginalPrompt":true}}\n' "$r"
}
ch_lim_conf_rules_without() {   # canonical rule text -> the conf line without it
  local i=1 out=""
  while [ $i -le "$CH_LIM_N" ]; do
    [ "${CH_LIM_RT[$i]}" = "$1" ] || out="${out:+$out · }${CH_LIM_RT[$i]}"
    i=$((i + 1))
  done
  ch_conf_set CLAUDE_HTML_LIMIT_RULES "$out"
}
ch_lim_prompt() {   # note clone
  local note="$1" here="$2" sid=unknown re word="" dir pend pass ptime=0 pkind="" prule="" ans
  re='"session_id"[[:space:]]*:[[:space:]]*"([A-Za-z0-9._-]{1,128})"'
  [[ "$note" =~ $re ]] && sid="${BASH_REMATCH[1]}"
  dir="$HOME/.claude/.claude-html-guard"; pend="$dir/limits-$sid"; pass="$dir/limits-pass-$sid"
  ch_lim_now
  re='"prompt"[[:space:]]*:[[:space:]]*"[[:space:]]*([A-Za-z]{1,8})[[:space:]]*"'
  if [[ "$note" =~ $re ]]; then ch_lim_lower "${BASH_REMATCH[1]}"; word="$_lc"; fi
  if [ -f "$pend" ]; then
    read -r ptime pkind prule < "$pend" 2>/dev/null
    case "$ptime" in ''|*[!0-9]*) ptime=0 ;; esac
    [ $((CH_NOW - ptime)) -lt 600 ] || pkind=""
  fi
  ch_lim_read_state; ch_lim_read_marks
  prule="${prule//_/ }"
  # ── an answer in words, to what was stopped just before ──
  if [ -n "$pkind" ]; then
    case "$word" in
      cancel) rm -f "$pend"; ch_lim_block "Dropped. Nothing was sent."; return 0 ;;
      allow) rm -f "$pend"; printf '%s\n' "$CH_NOW" > "$pass"
             ch_lim_block "Allowed once. Press ↑ and Enter to send it again."; return 0 ;;
      until)
        rm -f "$pend"
        if [ "$pkind" = budget ]; then ch_lim_period && M_ballow=$CH_PE
        else ch_lim_week && M_allow=$CH_WR; fi
        ch_lim_write_marks
        ch_lim_block "No more asking until the reset. Press ↑ and Enter to send it again."; return 0 ;;
      stop)
        rm -f "$pend"
        if [ "$pkind" = budget ]; then
          ch_conf_set CLAUDE_HTML_BUDGET off
          ch_lim_block "The budget is off. Press ↑ and Enter to send it again; claude-html --limits budget $CH_LIM_BP $CH_LIM_BA brings it back."
        else
          ch_lim_conf_rules_without "$prule"
          ch_lim_block "The rule \"$prule\" is off. Press ↑ and Enter to send it again; claude-html --limits add \"$prule\" brings it back."
        fi
        return 0 ;;
    esac
    # Anything else is a prompt like any other, and what was pending goes.
    rm -f "$pend"
  fi
  # A one-time allow, given in words, is good for the next prompt.
  if [ -f "$pass" ]; then
    read -r ptime < "$pass" 2>/dev/null; rm -f "$pass"
    case "$ptime" in ''|*[!0-9]*) ;; *) [ $((CH_NOW - ptime)) -lt 600 ] && return 0 ;; esac
  fi

  # ── is anything reached ──
  local kind="" head k1 v1 k2 v2 c3 c4 text box conf="$CONF"
  case "$conf" in "$HOME"/*) conf="~/${conf#"$HOME"/}" ;; esac
  if [ "$CH_LIM_N" -gt 0 ] && ch_lim_fresh && ch_lim_week && ch_lim_rule_starts && ch_lim_hit &&
     ! [ "${M_allow:-0}" -gt "$CH_NOW" ] 2>/dev/null; then
    kind=rule
    local i=$CH_LIM_HIT
    ch_lim_round "$S_week_pct"; ch_lim_wlabel "$CH_WR"
    head="Weekly limit rule reached"
    k1="Used:"; v1="$_RND % of the week  ·  resets $_LBL"
    k2="Rule:"; v2="from ${CH_LIM_RL[$i]}, stop at ${CH_LIM_RP[$i]} %"
    c3="Allow until the reset — no more asking this week"; c4="Stop — turn this rule off"
    prule="${CH_LIM_RT[$i]}"
    # What the arrow on the rule opens: every rule, this one marked, as
    # the conf holds them.
    ch_lim_rules_text
    box="CLAUDE_HTML_LIMIT_RULES=\"$_RTXT\"
in $conf
"
    local j=1
    while [ $j -le "$CH_LIM_N" ]; do
      box="$box
  $j  from ${CH_LIM_RL[$j]}, stop at ${CH_LIM_RP[$j]} %"
      [ $j = "$i" ] && box="$box   ← reached"
      j=$((j + 1))
    done
    box="$box

claude-html --limits remove $i   takes this rule out"
    text="⚠ claude-html: your prompt has been interrupted — weekly limit rule reached ($_RND % of the week, resets $_LBL; rule: from ${CH_LIM_RL[$i]}, stop at ${CH_LIM_RP[$i]} %).
  Nothing was sent. Answer:

  cancel  do not send
  allow   send this prompt only
  until   no more asking until the reset ($_LBL)
  stop    turn this rule off (claude-html --limits add \"$prule\" brings it back)"
  elif [ "$CH_LIM_BC" -gt 0 ] && ! ch_lim_on_plan && ch_lim_period &&
       ! [ "${M_ballow:-0}" -gt "$CH_NOW" ] 2>/dev/null; then
    ch_lim_spent "$sid"
    if [ -n "$CH_SPENT_KNOWN" ] && [ "$CH_SPENT" -ge $((CH_LIM_BC * 10000)) ]; then
      kind=budget; prule=budget
      ch_lim_money "$CH_SPENT"; ch_lim_period_word "$CH_LIM_BP"; ch_lim_wlabel "$CH_PE"
      case "$CH_LIM_BP" in day) head="Daily budget reached" ;; month) head="Monthly budget reached" ;; *) head="Weekly budget reached" ;; esac
      k1="Spent:"; v1="$_MON of \$$CH_LIM_BA $_PW  ·  resets $_LBL"
      k2="Budget:"; v2="\$$CH_LIM_BA per $CH_LIM_BP, for API use"
      c3="Allow until the reset — no more asking $_PW"; c4="Stop — turn the budget off"
      box="CLAUDE_HTML_BUDGET=\"$CH_LIM_BA $CH_LIM_BP\"
in $conf

$_MON spent $_PW, for API use; the period resets $_LBL.

claude-html --limits budget off   turns the budget off"
      text="⚠ claude-html: your prompt has been interrupted — API budget reached ($_MON of \$$CH_LIM_BA $_PW, resets $_LBL).
  Nothing was sent. Answer:

  cancel  do not send
  allow   send this prompt only
  until   no more asking until the reset ($_LBL)
  stop    turn the budget off (claude-html --limits budget $CH_LIM_BP $CH_LIM_BA brings it back)"
    fi
  fi
  [ -n "$kind" ] || return 0

  # Pending before anything is asked: if Claude Code gives up on this hook
  # while the window waits, the words still answer it.
  mkdir -p "$dir" 2>/dev/null
  printf '%s %s %s\n' "$CH_NOW" "$kind" "${prule// /_}" > "$pend"
  ans=""
  if ! ch_is_off "${CLAUDE_HTML_GUARD_DIALOG:-on}" && . "$here/lib/platform.sh" 2>/dev/null; then
    CH_HERE="$here"
    if ch_detect 2>/dev/null && ch_can_ask; then
      ans="$(ch_choose_limit "$head" "$k1" "$v1" "$k2" "$v2" "$c3" "$c4" "$box" 2>/dev/null)" || ans=""
    fi
  fi
  case "$ans" in
    cancel) rm -f "$pend"; ch_lim_block "Dropped. Nothing was sent." ;;
    allow) rm -f "$pend" ;;
    until)
      rm -f "$pend"
      if [ "$kind" = budget ]; then M_ballow=$CH_PE; else M_allow=$CH_WR; fi
      ch_lim_write_marks ;;
    stop)
      rm -f "$pend"
      if [ "$kind" = budget ]; then ch_conf_set CLAUDE_HTML_BUDGET off
      else ch_lim_conf_rules_without "$prule"; fi ;;
    timeout)
      # The words answer it for ten minutes from now, the window closed:
      # it may have waited up to an hour (CLAUDE_HTML_GUARD_WAIT).
      ch_lim_now
      printf '%s %s %s\n' "$CH_NOW" "$kind" "${prule// /_}" > "$pend"
      ch_lim_lower "$head"
      ch_lim_block "⏸ claude-html: ${_lc/api/API} and nobody answered within $(ch_span "$CH_GUARD_LIMIT").
  Nothing was sent. Answer:  cancel · allow · until · stop" ;;
    *) ch_lim_block "$text" ;;
  esac
  return 0
}
