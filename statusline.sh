#!/usr/bin/env bash
# Claude Code's status line, as claude-html writes it. Claude Code runs it
# after every reply (and on a timer, if refreshInterval is set) with a
# JSON note on stdin, and shows what it prints under the input box:
#
#   plan · 5 h ██████░░░░ 62 % ↻16:30 · week ████████▌░ 81 % ↻Tue 08:00 · stop at 80 % from Fri 20:00
#   budget · week $38.20 of $50 ███████▌░░ 76 % ↻Tue 08:00 · this session $1.12
#
#   bash statusline.sh                  ours alone
#   bash statusline.sh --wrap '<cmd>'   the status line you had first, then ours
#
# It also records the plan's figures (rate_limits.five_hour and
# .seven_day, for Pro, Max and Ultra subscribers, from the first reply on)
# and the session's cost in ~/.claude/.claude-html.limits, which the
# pages, the stop rules and their announcements read: written only when
# something changed, or every five minutes while it runs, so "as of" says
# when Claude Code last told it.
#
# bash and its builtins only: no node, no osascript, one date in the
# common case. It never fails: whatever it cannot read, it prints less.

umask 077
WRAP=""
[ "${1:-}" = --wrap ] && WRAP="${2:-}"
IN=""
IFS= read -r -t 2 -d '' IN || true

# Theirs first, beside ours: the same note on its stdin, its output kept,
# and never more than a few seconds of it. A slow or failing command of
# theirs costs its own part of the line, never ours.
if [ -n "$WRAP" ]; then
  _tin="$HOME/.claude/.claude-html.statusline-in.$$"; _tout="$HOME/.claude/.claude-html.statusline-out.$$"
  printf '%s' "$IN" > "$_tin" 2>/dev/null
  /bin/sh -c "$WRAP" < "$_tin" > "$_tout" 2>/dev/null &
  _pid=$!
  ( sleep "${CLAUDE_HTML_STATUSLINE_TEST_LIMIT:-3}"; kill "$_pid" ) >/dev/null 2>&1 &
  _watch=$!
  # Not a job this shell reports on when it is stopped below.
  disown "$_watch" 2>/dev/null
fi

HERE="${BASH_SOURCE[0]%/*}"; [ "$HERE" = "${BASH_SOURCE[0]}" ] && HERE=.
LINE="claude-html"
if . "$HERE/lib/limits.sh" 2>/dev/null; then
  ch_lim_settings; ch_lim_now; ch_lim_read_state

  # ── what the note says, in any order and spacing ─────────────────────
  _num='([0-9]{1,3}(\.[0-9]+)?)'
  N_five=""; N_fiveR=""; N_week=""; N_weekR=""; N_cost=""; N_sid=""
  _win() {   # name -> _WP _WR
    _WP=""; _WR=""
    local re='(^|[{,[:space:]])"'"$1"'"[[:space:]]*:[[:space:]]*\{([^{}]*)\}' body
    [[ "$IN" =~ $re ]] || return 1
    body="${BASH_REMATCH[2]}"
    re='"used_percentage"[[:space:]]*:[[:space:]]*'"$_num"'([^0-9.eE]|$)'
    [[ "$body" =~ $re ]] && _WP="${BASH_REMATCH[1]}"
    re='"resets_at"[[:space:]]*:[[:space:]]*([0-9]{9,11})([^0-9.]|$)'
    [[ "$body" =~ $re ]] && _WR="${BASH_REMATCH[1]}"
    [ -n "$_WP" ] && [ -n "$_WR" ]
  }
  # Leading zeros off, so the state holds a number JSON can read.
  _canon() { local i="${1%%.*}" f=""; [ "$i" != "$1" ] && f=".${1#*.}"; _CN="$((10#$i))$f"; }
  if _win five_hour; then _canon "$_WP"; N_five="$_CN"; N_fiveR="$_WR"; fi
  if _win seven_day; then _canon "$_WP"; N_week="$_CN"; N_weekR="$_WR"; fi
  _re='"total_cost_usd"[[:space:]]*:[[:space:]]*([0-9]{1,9}(\.[0-9]+)?)([eE]([-+]?[0-9]+))?'
  if [[ "$IN" =~ $_re ]]; then
    N_cost="${BASH_REMATCH[1]}"
    # 1.2e-05 is nothing worth a cent; a positive exponent is not a cost.
    case "${BASH_REMATCH[4]}" in -*) N_cost=0 ;; '') ;; *) N_cost="" ;; esac
  fi
  _re='"session_id"[[:space:]]*:[[:space:]]*"([A-Za-z0-9._-]{1,128})"'
  [[ "$IN" =~ $_re ]] && N_sid="${BASH_REMATCH[1]}"

  # ── recorded, when anything changed ──────────────────────────────────
  _dirty=""
  _set() { local v; eval "v=\${S_$1-}"; [ "$v" = "$2" ] || { eval "S_$1=\$2"; _dirty=1; }; }
  if [ -n "$N_week$N_five" ]; then
    if [ -n "$N_five" ]; then
      [ "$N_fiveR" = "${S_five_reset:-}" ] || { ch_lim_label "$N_fiveR"; S_five_label="$_LBL"; }
      _set five_pct "$N_five"; _set five_reset "$N_fiveR"
    fi
    if [ -n "$N_week" ]; then
      [ "$N_weekR" = "${S_week_reset:-}" ] || { ch_lim_wlabel "$N_weekR"; S_week_label="$_LBL"; }
      _set week_pct "$N_week"; _set week_reset "$N_weekR"
    fi
    # Unchanged figures are still news after five minutes: "as of" moves.
    case "${S_asof:-}" in ''|*[!0-9]*) _dirty=1 ;; *) [ $((CH_NOW - S_asof)) -ge 300 ] && _dirty=1 ;; esac
    [ -n "$_dirty" ] && { S_asof=$CH_NOW; S_plan_seen=$CH_NOW; }
  fi
  [ -n "$N_cost" ] && _set cost "$N_cost"
  [ -n "$N_sid" ] && _set session "$N_sid"

  # ── the line ─────────────────────────────────────────────────────────
  if [ -n "${NO_COLOR:-}" ]; then C0=""; CD=""; CG=""; CA=""; CR=""
  else C0=$'\033[0m'; CD=$'\033[2m'; CG=$'\033[32m'; CA=$'\033[38;5;214m'; CR=$'\033[31m'; fi
  _col() {   # tenths -> _C
    if [ "$1" -ge 950 ]; then _C="$CR"; elif [ "$1" -ge 800 ]; then _C="$CA"; else _C="$CG"; fi
  }
  _bar() {   # tenths -> _B, ten cells, half cells too
    local t=$1 full half i=0
    [ "$t" -gt 1000 ] && t=1000; [ "$t" -lt 0 ] && t=0
    full=$((t / 100)); half=$(( t % 100 >= 50 ? 1 : 0 ))
    _B=""
    while [ $i -lt $full ]; do _B="${_B}█"; i=$((i + 1)); done
    [ $half = 1 ] && { _B="${_B}▌"; i=$((i + 1)); }
    while [ $i -lt 10 ]; do _B="${_B}░"; i=$((i + 1)); done
  }
  _part() {   # label tenths reset-label -> appended to _L
    _col "$2"; _bar "$2"
    _L="$_L ${CD}·${C0} $1 $_C$_B $(( ($2 + 5) / 10 )) %$C0${3:+ ${CD}↻$3$C0}"
  }
  _L=""
  _sess=""
  if ch_lim_micro "${N_cost:-}"; then ch_lim_money "$_MIC"; _sess="this session $_MON"; fi
  if [ -n "${S_asof:-}" ] && [ $((CH_NOW - S_asof)) -le "$CH_LIM_STALE" ] &&
     { [ "${S_five_reset:-0}" -gt "$CH_NOW" ] || [ "${S_week_reset:-0}" -gt "$CH_NOW" ]; } 2>/dev/null; then
    [ "${S_five_reset:-0}" -gt "$CH_NOW" ] && ch_lim_tenths "${S_five_pct:-}" && _part "5 h" "$_TEN" "${S_five_label:-}"
    if [ "${S_week_reset:-0}" -gt "$CH_NOW" ] && ch_lim_tenths "${S_week_pct:-}"; then
      _wt=$_TEN
      _part week "$_wt" "${S_week_label:-}"
      if [ -n "$CH_LIM_ON" ] && [ "$CH_LIM_N" -gt 0 ] && ch_lim_week && ch_lim_rule_starts; then
        [ -n "${CH_LIM_STARTS_NEW:-}" ] && _dirty=1
        ch_lim_current
        if [ "$CH_LIM_CUR" != 0 ]; then
          _c=""; [ -n "$CH_LIM_CUR_FORCE" ] && [ "$_wt" -ge $(( CH_LIM_RP[CH_LIM_CUR] * 10 )) ] && _c="$CA"
          _L="$_L ${CD}·${C0} ${_c}stop at ${CH_LIM_RP[$CH_LIM_CUR]} % from ${CH_LIM_RL[$CH_LIM_CUR]}${_c:+$C0}"
        fi
      fi
    fi
    LINE="${CD}plan${C0}$_L"
  elif [ "$CH_LIM_BC" -gt 0 ] && ! ch_lim_on_plan && ch_lim_period; then
    [ -n "${CH_LIM_STARTS_NEW:-}" ] && _dirty=1
    ch_lim_spent "$N_sid"
    ch_lim_period_word "$CH_LIM_BP"; _pw="${_PW#this }"
    if [ -n "$CH_SPENT_KNOWN" ]; then
      ch_lim_budget_tenths; ch_lim_money "$CH_SPENT"
      _col "$CH_BT"; _bar "$CH_BT"
      [ -n "${S_per_label:-}" ] || { ch_lim_wlabel "$CH_PE"; S_per_label="$_LBL"; _dirty=1; }
      LINE="${CD}budget${C0} ${CD}·${C0} $_pw $_MON of \$$CH_LIM_BA $_C$_B $(( (CH_BT + 5) / 10 )) %$C0 ${CD}↻$S_per_label$C0"
    else
      LINE="${CD}budget${C0} ${CD}·${C0} \$$CH_LIM_BA per $CH_LIM_BP, no total yet: claude-html counts it at the next save"
    fi
    [ -n "$_sess" ] && LINE="$LINE ${CD}·${C0} $_sess"
  else
    LINE="${CD}claude-html${C0}${_sess:+ ${CD}·${C0} $_sess}"
  fi
  [ -n "$_dirty" ] && ch_lim_write_state
fi

if [ -n "$WRAP" ]; then
  wait "$_pid" 2>/dev/null
  kill "$_watch" 2>/dev/null
  while IFS= read -r _l || [ -n "$_l" ]; do printf '%s\n' "$_l"; done < "$_tout" 2>/dev/null
  rm -f "$_tin" "$_tout" 2>/dev/null
fi
printf '%s\n' "$LINE"
exit 0
