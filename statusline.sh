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
# Bytes, not characters, whatever the terminal's locale: the widths below
# are counted from them. Theirs, started above, keeps its own.
LC_ALL=C
if . "$HERE/lib/limits.sh" 2>/dev/null; then
  CH_LIM_EXTRA_KEYS="CLAUDE_HTML_STATUSLINE_ITEMS CLAUDE_HTML_STATUSLINE_FORM CLAUDE_HTML_STATUSLINE_WIDTH CLAUDE_HTML_STATUSLINE_BAR CLAUDE_HTML_STATUSLINE_BAR_FROM CLAUDE_HTML_STATUSLINE_COLOR"
  CH_UPDATE_STATE_SL="$HOME/.claude/.claude-html.update"
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
  # Its items, each in a normal and a condensed form, in the order the
  # owner listed them (CLAUDE_HTML_STATUSLINE_ITEMS); the first listed is
  # the last condensed. The defaults give the line of before 3.7 exactly.
  if [ -n "${NO_COLOR:-}" ]; then C0=""; CD=""; CG=""; CA=""; CR=""
  else C0=$'\033[0m'; CD=$'\033[2m'; CG=$'\033[32m'; CA=$'\033[38;5;214m'; CR=$'\033[31m'; fi
  # The figures' colour: level (green, amber from 80 %, red from 95 %), auto
  # (none: the terminal's own), or one of its basic colours, which follow
  # its theme. on and off, from an earlier 3.7.0, are level and auto.
  SL_COLOR=level; SL_FIX=""
  ch_lim_lower "$CLAUDE_HTML_STATUSLINE_COLOR"
  case "$_lc" in
    auto|off|0|no|false) SL_COLOR="" ;;
    green) SL_FIX=32 ;; cyan) SL_FIX=36 ;; blue) SL_FIX=34 ;; magenta) SL_FIX=35 ;;
    yellow) SL_FIX=33 ;; red) SL_FIX=31 ;; grey|gray) SL_FIX=90 ;;
  esac
  if [ -n "$SL_FIX" ]; then SL_COLOR=fixed; [ -n "$C0" ] && SL_FIX=$'\033['"${SL_FIX}m" || SL_FIX=""; fi
  SL_BW=10; case "$CLAUDE_HTML_STATUSLINE_BAR" in 5|20) SL_BW=$CLAUDE_HTML_STATUSLINE_BAR ;; esac
  SL_FROM=0; case "$CLAUDE_HTML_STATUSLINE_BAR_FROM" in [0-9]|[1-9][0-9]|100) SL_FROM=$CLAUDE_HTML_STATUSLINE_BAR_FROM ;; esac
  SL_FORM=auto; ch_lim_lower "$CLAUDE_HTML_STATUSLINE_FORM"; case "$_lc" in normal|condensed) SL_FORM=$_lc ;; esac
  SL_MAX=100; case "$CLAUDE_HTML_STATUSLINE_WIDTH" in [2-9][0-9]|[1-3][0-9][0-9]|400) SL_MAX=$((10#$CLAUDE_HTML_STATUSLINE_WIDTH)) ;; esac
  # Claude Code puts the terminal's width in COLUMNS; a line must be four
  # narrower than it, or it is cut with an ellipsis.
  case "${COLUMNS:-}" in [1-9][0-9]|[1-9][0-9][0-9]|[1-9][0-9][0-9][0-9]) [ $((COLUMNS - 4)) -lt "$SL_MAX" ] && SL_MAX=$((COLUMNS - 4)) ;; esac
  SL_LIST=""
  if [ -n "$CLAUDE_HTML_STATUSLINE_ITEMS" ]; then
    ch_lim_lower "${CLAUDE_HTML_STATUSLINE_ITEMS//,/ }"
    for _i in $_lc; do
      case "$_i" in five|week|session|today|ctx|model|project|stop|budget) ;; *) continue ;; esac
      case " $SL_LIST " in *" $_i "*) ;; *) SL_LIST="$SL_LIST $_i" ;; esac
    done
    SL_LIST="${SL_LIST# }"; SL_SET=1
  else SL_LIST="five week stop budget"; SL_SET=""; fi
  _has() { case " $SL_LIST " in *" $1 "*) return 0 ;; esac; return 1; }

  _col() {   # tenths -> _C
    if [ -z "$SL_COLOR" ]; then _C=""
    elif [ "$SL_COLOR" = fixed ]; then _C="$SL_FIX"
    elif [ "$1" -ge 950 ]; then _C="$CR"; elif [ "$1" -ge 800 ]; then _C="$CA"; else _C="$CG"; fi
  }
  _bar() {   # tenths -> _B, SL_BW cells, half cells too
    local t=$1 halves full i=0
    [ "$t" -gt 1000 ] && t=1000; [ "$t" -lt 0 ] && t=0
    halves=$(( t * SL_BW / 500 )); full=$((halves / 2))
    _B=""
    while [ $i -lt $full ]; do _B="${_B}█"; i=$((i + 1)); done
    [ $((halves % 2)) = 1 ] && { _B="${_B}▌"; i=$((i + 1)); }
    while [ $i -lt "$SL_BW" ]; do _B="${_B}░"; i=$((i + 1)); done
  }
  # "16:30" stays; "Tue 08:00" is "Tu08", "Tue 08:30" "Tu08:30".
  _short() {
    case "$1" in
      ???" "??:00) _SH="${1:0:2}${1:4:2}" ;;
      ???" "??:??) _SH="${1:0:2}${1:4:5}" ;;
      *) _SH="$1" ;;
    esac
  }
  # A window: normal "5 h ██████░░░░ 62 % ↻16:30", condensed "5h:62% ↻16:30".
  _win_part() {   # normal-label condensed-label tenths reset-label
    local r=$(( ($3 + 5) / 10 ))
    _col "$3"
    if [ "$r" -ge "$SL_FROM" ]; then _bar "$3"; _N="$1 $_C$_B $r %$C0"; else _N="$1 $_C$r %$C0"; fi
    _short "$4"
    _N="$_N${4:+ ${CD}↻$4$C0}"; _K="$2:$_C$r%$C0${4:+ ${CD}↻$_SH$C0}"
  }
  ch_lim_upper1() {   # word -> _U1, its first letter a capital
    local f="${1:0:1}" u
    case "$f" in a) u=A ;; b) u=B ;; c) u=C ;; d) u=D ;; e) u=E ;; f) u=F ;; g) u=G ;; h) u=H ;; i) u=I ;; j) u=J ;;
      k) u=K ;; l) u=L ;; m) u=M ;; n) u=N ;; o) u=O ;; p) u=P ;; q) u=Q ;; r) u=R ;; s) u=S ;; t) u=T ;; u) u=U ;;
      v) u=V ;; w) u=W ;; x) u=X ;; y) u=Y ;; z) u=Z ;; *) u="$f" ;; esac
    _U1="$u${1:1}"
  }
  _n=0
  _add() { _n=$((_n + 1)); PN[$_n]="$_N"; PK[$_n]="$_K"; }

  # This session's cost, and today's across sessions: a small ledger of
  # the sessions seen today, each from what it had cost when the day began.
  _sess=""; _ses_mic=""
  if ch_lim_micro "${N_cost:-}"; then _ses_mic=$_MIC; ch_lim_money "$_MIC"; _sess="$_MON"; fi
  _today=""
  if _has today; then
    _tf="$HOME/.claude/.claude-html.today"; _day="$(ch_lim_datefmt "$CH_NOW" '+%Y%m%d' 2>/dev/null)"
    _tday=""; _tl=""; _tsum=0; _tch=""; _seen=""
    if [ -f "$_tf" ]; then
      while IFS='=' read -r _k _v || [ -n "$_k" ]; do
        case "$_k" in day) _tday="$_v" ;; s:*) case "${_k#s:}:$_v" in *[!A-Za-z0-9._:-]*) ;; *) _tl="$_tl ${_k#s:}=$_v" ;; esac ;; esac
      done < "$_tf"
    fi
    if [ "$_tday" != "$_day" ]; then
      # A new day: each session starts it from what it had cost by then.
      _o=""; for _e in $_tl; do _l="${_e##*:}"; _o="$_o ${_e%%=*}=$_l:$_l"; done; _tl="$_o"; _tch=1
    fi
    _o=""
    for _e in $_tl; do
      _sid="${_e%%=*}"; _b="${_e#*=}"; _l="${_b#*:}"; _b="${_b%%:*}"
      case "$_b$_l" in *[!0-9]*|'') continue ;; esac
      if [ -n "$N_sid" ] && [ "$_sid" = "$N_sid" ] && [ -n "$_ses_mic" ]; then
        _seen=1; [ "$_l" = "$_ses_mic" ] || { _l=$_ses_mic; _tch=1; }
        [ "$_l" -lt "$_b" ] && _b=0
      fi
      _tsum=$(( _tsum + _l - _b )); _o="$_o s:$_sid=$_b:$_l"
    done
    if [ -z "$_seen" ] && [ -n "$N_sid" ] && [ -n "$_ses_mic" ]; then
      _tsum=$(( _tsum + _ses_mic )); _o="$_o s:$N_sid=0:$_ses_mic"; _tch=1
    fi
    if [ -n "$_tch" ] && [ -n "$_day" ]; then
      { echo "day=$_day"; for _e in $_o; do echo "$_e"; done; } > "$_tf.tmp.$$" 2>/dev/null &&
        mv -f "$_tf.tmp.$$" "$_tf" 2>/dev/null || rm -f "$_tf.tmp.$$" 2>/dev/null
    fi
    ch_lim_money "$_tsum"; _today="$_MON"
  fi

  # The items that need no figures of the plan's or the budget's.
  _other() {   # item
    case "$1" in
      session) [ -n "$_sess" ] || return 1; _N="this session $_sess"; _K="ses$_sess" ;;
      today) [ -n "$_today" ] || return 1; _N="today $_today"; _K="today$_today" ;;
      ctx)
        local re='"context_window"[[:space:]]*:[[:space:]]*\{[^}]*"used_percentage"[[:space:]]*:[[:space:]]*'"$_num"'([^0-9.eE]|$)'
        [[ "$IN" =~ $re ]] && ch_lim_tenths "${BASH_REMATCH[1]}" || return 1
        local r=$(( (_TEN + 5) / 10 )); _col "$_TEN"
        _N="ctx $_C$r %$C0"; _K="ctx$_C$r%$C0" ;;
      model)
        local re='"model"[[:space:]]*:[[:space:]]*\{([^{}]*)\}' body id="" dn="" fam="" ver="" t
        [[ "$IN" =~ $re ]] || return 1
        body="${BASH_REMATCH[1]}"
        re='"id"[[:space:]]*:[[:space:]]*"([^"\\]{1,80})"'; [[ "$body" =~ $re ]] && id="${BASH_REMATCH[1]}"
        re='"display_name"[[:space:]]*:[[:space:]]*"([^"\\]{1,60})"'; [[ "$body" =~ $re ]] && dn="${BASH_REMATCH[1]//[[:cntrl:]]/}"
        # claude-opus-5-5 is Opus 5.5, claude-3-5-sonnet-20241022 Sonnet 3.5.
        id="${id%%\[*}"; id="${id#claude-}"
        for t in ${id//-/ }; do
          case "$t" in
            [0-9]|[0-9][0-9]) ver="${ver:+$ver.}$t" ;;
            [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) ;;
            *[!a-z]*) fam=""; ver=""; break ;;
            *) [ -z "$fam" ] || { fam=""; break; }; fam="$t" ;;
          esac
        done
        if [ -n "$fam" ] && [ -n "$ver" ]; then
          ch_lim_upper1 "$fam"; _N="$_U1 $ver"; _K="${_U1:0:2}$ver"
        elif [ -n "$dn" ]; then
          _N="${dn:0:16}"; _K="${dn// /}"; _K="${_K:0:6}"
        else return 1; fi ;;
      project)
        local re='"(project_dir|current_dir)"[[:space:]]*:[[:space:]]*"([^"\\]+)"' dir="" cwd="" p br="" d h=""
        [[ "$IN" =~ $re ]] || return 1
        re='"project_dir"[[:space:]]*:[[:space:]]*"([^"\\]+)"'; [[ "$IN" =~ $re ]] && dir="${BASH_REMATCH[1]}"
        re='"current_dir"[[:space:]]*:[[:space:]]*"([^"\\]+)"'; [[ "$IN" =~ $re ]] && cwd="${BASH_REMATCH[1]}"
        [ -n "$dir" ] || dir="$cwd"; [ -n "$cwd" ] || cwd="$dir"
        dir="${dir%/}"; p="${dir##*/}"; p="${p//[[:cntrl:]]/}"
        [ -n "$p" ] || return 1
        # The branch from the repository's HEAD, read as a file: no git.
        d="$cwd"
        while [ -n "$d" ]; do
          if [ -f "$d/.git/HEAD" ]; then h="$d/.git/HEAD"; break; fi
          if [ -f "$d/.git" ]; then
            read -r t < "$d/.git" 2>/dev/null; t="${t#gitdir: }"
            case "$t" in /*) ;; *) t="$d/$t" ;; esac
            h="$t/HEAD"; break
          fi
          d="${d%/*}"
        done
        if [ -n "$h" ] && read -r t < "$h" 2>/dev/null; then
          case "$t" in "ref: refs/heads/"*) br="${t#ref: refs/heads/}" ;; [0-9a-f]*) br="${t:0:7}" ;; esac
          br="${br//[[:cntrl:]]/}"; br="${br:0:40}"
        fi
        _N="$p${br:+ · $br}"; _K="${p:0:2}${br:+.$br}" ;;
      *) return 1 ;;
    esac
    return 0
  }

  PREFIX=""
  if [ -n "${S_asof:-}" ] && [ $((CH_NOW - S_asof)) -le "$CH_LIM_STALE" ] &&
     { [ "${S_five_reset:-0}" -gt "$CH_NOW" ] || [ "${S_week_reset:-0}" -gt "$CH_NOW" ]; } 2>/dev/null; then
    PREFIX="${CD}plan${C0}"
    _wt=""
    if [ "${S_week_reset:-0}" -gt "$CH_NOW" ] && ch_lim_tenths "${S_week_pct:-}"; then _wt=$_TEN; fi
    for _i in $SL_LIST; do
      case "$_i" in
        five) [ "${S_five_reset:-0}" -gt "$CH_NOW" ] && ch_lim_tenths "${S_five_pct:-}" &&
                { _win_part "5 h" 5h "$_TEN" "${S_five_label:-}"; _add; } ;;
        week) [ -n "$_wt" ] && { _win_part week wk "$_wt" "${S_week_label:-}"; _add; } ;;
        stop)
          if [ -n "$_wt" ] && [ -n "$CH_LIM_ON" ] && [ "$CH_LIM_N" -gt 0 ] && ch_lim_week && ch_lim_rule_starts; then
            [ -n "${CH_LIM_STARTS_NEW:-}" ] && _dirty=1
            ch_lim_current
            if [ "$CH_LIM_CUR" != 0 ]; then
              _c=""; [ "$SL_COLOR" = level ] && [ -n "$CH_LIM_CUR_FORCE" ] && [ "$_wt" -ge $(( CH_LIM_RP[CH_LIM_CUR] * 10 )) ] && _c="$CA"
              _N="${_c}stop at ${CH_LIM_RP[$CH_LIM_CUR]} % from ${CH_LIM_RL[$CH_LIM_CUR]}${_c:+$C0}"
              _K="${_c}stop${CH_LIM_RP[$CH_LIM_CUR]}%${_c:+$C0}"; _add
            fi
          fi ;;
        budget) ;;
        *) _other "$_i" && _add ;;
      esac
    done
  elif [ "$CH_LIM_BC" -gt 0 ] && ! ch_lim_on_plan && ch_lim_period; then
    PREFIX="${CD}budget${C0}"
    for _i in $SL_LIST $([ -z "$SL_SET" ] && echo session); do
      case "$_i" in
        budget)
          [ -n "${CH_LIM_STARTS_NEW:-}" ] && _dirty=1
          ch_lim_spent "$N_sid"
          ch_lim_period_word "$CH_LIM_BP"; _pw="${_PW#this }"
          if [ -n "$CH_SPENT_KNOWN" ]; then
            ch_lim_budget_tenths; ch_lim_money "$CH_SPENT"
            _col "$CH_BT"; _r=$(( (CH_BT + 5) / 10 ))
            [ -n "${S_per_label:-}" ] || { ch_lim_wlabel "$CH_PE"; S_per_label="$_LBL"; _dirty=1; }
            if [ "$_r" -ge "$SL_FROM" ]; then _bar "$CH_BT"; _N="$_pw $_MON of \$$CH_LIM_BA $_C$_B $_r %$C0"
            else _N="$_pw $_MON of \$$CH_LIM_BA $_C$_r %$C0"; fi
            _N="$_N ${CD}↻$S_per_label$C0"
            _K="$_C\$$((CH_SPENT / 1000000))/${CH_LIM_BA%%.*}$C0"
          else
            _N="\$$CH_LIM_BA per $CH_LIM_BP, no total yet: claude-html counts it at the next save"
            _K="\$?/${CH_LIM_BA%%.*}"
          fi
          _add ;;
        five|week|stop) ;;
        *) _other "$_i" && _add ;;
      esac
    done
  else
    PREFIX="${CD}claude-html${C0}"
    for _i in $SL_LIST; do case "$_i" in five|week|stop|budget) ;; *) _other "$_i" && _add ;; esac; done
    # Nothing listed has anything to say: this session's cost, as ever.
    if [ "$_n" = 0 ] && [ -z "$SL_SET" ] && _other session; then _add; fi
  fi

  # Updated by itself: said for a day.
  if [ -f "$CH_UPDATE_STATE_SL" ]; then
    _ua=""; _uat=""
    while IFS='=' read -r _k _v || [ -n "$_k" ]; do
      case "$_k" in auto) _ua="$_v" ;; autoat) _uat="$_v" ;; esac
    done < "$CH_UPDATE_STATE_SL"
    case "$_ua" in *[!0-9.]*|'') ;; *)
      case "$_uat" in ''|*[!0-9]*) ;; *)
        if [ $((CH_NOW - _uat)) -ge 0 ] && [ $((CH_NOW - _uat)) -lt 86400 ]; then
          _N="${CD}updated to $_ua$C0"; _K="${CD}↑$_ua$C0"; _add
        fi ;;
      esac ;;
    esac
  fi

  # The widths, as the terminal counts them: the colours are not there,
  # a · is two bytes, every other glyph used here three.
  _wid() {
    local s="$1" u
    if [ -n "$C0" ]; then s="${s//"$C0"/}"; s="${s//"$CD"/}"; s="${s//"$CG"/}"; s="${s//"$CA"/}"; s="${s//"$CR"/}"; fi
    [ -z "$SL_FIX" ] || s="${s//"$SL_FIX"/}"
    u="${s//[! -~]/}"; local nb=$(( ${#s} - ${#u} ))
    local d="${s//·/}"; d=$(( (${#s} - ${#d}) / 2 ))
    _W=$(( ${#u} + d + (nb - 2 * d + 2) / 3 ))
  }
  _i=1; _tot=0
  while [ $_i -le $_n ]; do
    _wid "${PN[$_i]}"; WN[$_i]=$_W; _wid "${PK[$_i]}"; WK[$_i]=$_W
    _tot=$(( _tot + WN[_i] + 3 )); _i=$((_i + 1))
  done
  _wid "$PREFIX"; _pw=$_W
  _k=0; _drop=""
  case "$SL_FORM" in
    condensed) _k=$_n; [ "$_n" -gt 0 ] && _drop=1 ;;
    auto)
      _cur=$(( _pw + _tot ))
      while [ "$_cur" -gt "$SL_MAX" ] && [ "$_k" -lt "$_n" ]; do
        _cur=$(( _cur - WN[_n - _k] + WK[_n - _k] )); _k=$((_k + 1))
      done
      [ "$_cur" -gt "$SL_MAX" ] && [ "$_n" -gt 0 ] && _drop=1 ;;
  esac
  if [ -n "$_drop" ]; then LINE=""; else LINE="$PREFIX"; fi
  _i=1
  while [ $_i -le $_n ]; do
    if [ $_i -gt $((_n - _k)) ]; then _p="${PK[$_i]}"; else _p="${PN[$_i]}"; fi
    if [ -z "$LINE" ]; then LINE="$_p"; else LINE="$LINE ${CD}·${C0} $_p"; fi
    _i=$((_i + 1))
  done
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
