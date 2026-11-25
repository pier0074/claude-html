# Sourced by claude-html: claude-html --limits, which shows and sets the
# stop rules, the API budget and the desktop banner, and --limits-apply,
# which a claude-html://limits link from the Token usage page reaches.
#
#   claude-html --limits                         what is set, and the latest figures
#   claude-html --limits add "fri 20:00 80%"     a stop rule
#   claude-html --limits remove <n>
#   claude-html --limits rules "<rule> · <rule>"|none
#   claude-html --limits budget day|week|month <dollars> | off | warn <a> <b>
#   claude-html --limits notify on|off
#   claude-html --limits on|off
#   claude-html --limits-apply <payload>         asks in a window, then writes
#
# Every change is one line of the conf, written by conf.sh's ch_conf_set.
# Needs conf.sh, platform.sh and limits.sh.

ch_lim_usage() {
  cat >&2 <<'EOF'
claude-html --limits [status]
claude-html --limits add "fri 20:00 80%"
claude-html --limits remove <n>
claude-html --limits rules "fri 20:00 80% · sat 00:00 90%"|none
claude-html --limits budget day|week|month <dollars>
claude-html --limits budget off
claude-html --limits budget warn <percent> <percent>
claude-html --limits notify on|off
claude-html --limits on|off
EOF
}

# A rule in words: "from Fri 20:00, stop at 80 %".
ch_lim_words() { printf 'from %s, stop at %s %%' "${CH_LIM_RL[$1]}" "${CH_LIM_RP[$1]}"; }

ch_lim_tilde() { case "$1" in "$HOME"/*) printf '~/%s' "${1#"$HOME"/}" ;; *) printf '%s' "$1" ;; esac; }

# How long ago, in the one unit that reads at a glance.
ch_lim_ago() {
  local m=$(( ($CH_NOW - $1) / 60 ))
  if [ "$m" -lt 1 ]; then echo "just now"
  elif [ "$m" -lt 60 ]; then echo "$m min ago"
  elif [ "$m" -lt 2880 ]; then echo "$((m / 60)) h ago"
  else echo "$((m / 1440)) days ago"; fi
}

# Whether the status line and the prompt hook are in settings.json.
ch_lim_statusline_state() {
  local s="$HOME/.claude/settings.json"
  if ! grep -q '/statusline\.sh' "$s" 2>/dev/null; then echo "not installed: ./install.sh adds it"
  elif grep -q '/statusline\.sh'"'"' --wrap' "$s" 2>/dev/null; then echo "claude-html's, around yours"
  else echo "claude-html's"; fi
}
ch_lim_prompt_hook() { grep -qE "/guard\.sh' prompt\"" "$HOME/.claude/settings.json" 2>/dev/null; }

ch_lim_show() {
  ch_lim_now; ch_lim_read_state
  local i force since
  echo "claude-html limits  $(ch_lim_tilde "$CONF")"
  echo
  [ -n "$CH_LIM_ON" ] || echo "  Limits off: no stop, no announcement, no budget warning, no banner · claude-html --limits on"
  ch_lim_week; ch_lim_rule_starts >/dev/null 2>&1
  if [ "$CH_LIM_N" = 0 ]; then
    echo "  Stop rules     none · claude-html --limits add \"fri 20:00 80%\""
  else
    i=1
    while [ $i -le "$CH_LIM_N" ]; do
      since=""
      if [ -n "${CH_LIM_RS[$i]:-}" ] && [ "${CH_LIM_RS[$i]}" -le "$CH_NOW" ] && [ "$CH_NOW" -lt "$CH_WR" ]; then
        since="   in force since ${CH_LIM_RL[$i]}"
      fi
      if [ $i = 1 ]; then printf '  Stop rules     %s  %s%s\n' "$i" "$(ch_lim_words $i)" "$since"
      else printf '                 %s  %s%s\n' "$i" "$(ch_lim_words $i)" "$since"; fi
      i=$((i + 1))
    done
    echo "                 gentle: asks on a new prompt; a running task is never interrupted"
    echo "                 announced once in Claude Code before a rule starts, and when it starts"
  fi
  [ -z "$CH_LIM_BAD" ] || echo "  Ignored        $CH_LIM_BAD (a rule is written \"fri 20:00 80%\")"
  if [ "$CH_LIM_BC" -gt 0 ]; then
    echo "  Budget         \$$CH_LIM_BA per $CH_LIM_BP, warnings at $CH_LIM_W1 % and $CH_LIM_W2 %  (API use only: Claude Code warns about plan limits itself)"
  else
    echo "  Budget         none · claude-html --limits budget week 50  (for API use)"
  fi
  [ -z "$CH_LIM_BBAD" ] || echo "  Ignored        budget \"$CH_LIM_BBAD\" (written \"50 week\", \"20 day\" or \"200 month\")"
  if [ -n "$CH_LIM_NOTIFY" ]; then echo "  Notification   on · claude-html --limits notify off"
  else echo "  Notification   off · claude-html --limits notify on"; fi
  local src utc
  ch_lim_wlabel "$CH_WR"
  case "$CH_WSRC" in
    rate_limits) src="from Claude Code's status line" ;;
    'rate_limits*') src="from Claude Code's status line, last seen before a reset" ;;
    conf) src="from CLAUDE_HTML_WEEK_RESET" ;;
    *) src="calendar weeks: CLAUDE_HTML_WEEK_RESET sets yours until Claude Code reports it" ;;
  esac
  utc="$(TZ=UTC ch_lim_datefmt "$CH_WR" '+%H:%M')"
  echo "  Week           resets $_LBL ($utc UTC), $src"
  echo "  Status line    $(ch_lim_statusline_state)"
  if { [ "$CH_LIM_N" -gt 0 ] || [ "$CH_LIM_BC" -gt 0 ]; } && ! ch_lim_prompt_hook; then
    echo "  Note           the prompt hook is not in settings.json, so nothing is stopped: ./install.sh in $HERE adds it"
  fi
  echo
  if [ -n "${S_asof:-}" ] && [ -n "${S_week_pct:-}${S_five_pct:-}" ]; then
    local first=1 lbl
    if [ -n "${S_five_pct:-}" ] && [ "${S_five_reset:-0}" -gt "$CH_NOW" ] && ch_lim_round "$S_five_pct"; then
      ch_lim_label "$S_five_reset"
      printf '  Now            5 h  %4s %%   resets %s\n' "$_RND" "$_LBL"; first=""
    fi
    if [ -n "${S_week_pct:-}" ] && ch_lim_round "$S_week_pct"; then
      ch_lim_wlabel "$S_week_reset"
      if [ -n "$first" ]; then printf '  Now            week %4s %%   resets %s\n' "$_RND" "$_LBL"
      else printf '                 week %4s %%   resets %s\n' "$_RND" "$_LBL"; fi
    fi
    ch_lim_wlabel "$S_asof"; lbl="$_LBL"
    if ch_lim_fresh; then
      echo "                 from Claude Code's status line (rate_limits), as of $lbl — $(ch_lim_ago "$S_asof")"
    else
      echo "                 as of $lbl — $(ch_lim_ago "$S_asof"): no recent usage values, so nothing is stopped on them"
      echo "                 (they update while Claude Code runs)"
    fi
  else
    echo "  Now            no recent usage values: Claude Code's status line gives them while it runs"
    echo "                 (Pro, Max and Ultra plans, from a session's first reply)"
  fi
  if [ "$CH_LIM_BC" -gt 0 ] && ! ch_lim_on_plan && ch_lim_period; then
    ch_lim_spent "${S_session:-}"; ch_lim_period_word "$CH_LIM_BP"; ch_lim_wlabel "$CH_PE"
    if [ -n "$CH_SPENT_KNOWN" ]; then
      ch_lim_budget_tenths; ch_lim_money "$CH_SPENT"
      echo "  Spent          $_MON of \$$CH_LIM_BA $_PW ($(( (CH_BT + 5) / 10 )) %) · resets $_LBL"
      echo "                 the cost Claude Code recorded (else the price table's), counted at the last save, and this session's so far"
    else
      echo "  Spent          not counted yet: the next save (or claude-html) counts it"
    fi
  fi
}

# Writes a setting and keeps the shell's copy in step, so a build run
# after it in this same command sees the new value.
ch_lim_set() { ch_conf_set "$1" "$2"; eval "$1=\$2"; }

ch_lim_cli() {
  ch_lim_settings
  local sub="${1:-}"
  [ $# -gt 0 ] && shift
  case "$sub" in
    ""|status)
      [ $# = 0 ] || { ch_lim_usage; return 2; }
      ch_lim_show ;;
    add)
      local t="$*" i n
      [ -n "$t" ] || { ch_lim_usage; return 2; }
      if ! ch_lim_parse_one "$t"; then
        echo "not a rule: $t — a rule is a day, a time and a percentage: claude-html --limits add \"fri 20:00 80%\"" >&2
        return 2
      fi
      i=1
      while [ $i -le "$CH_LIM_N" ]; do
        if [ "${CH_LIM_RD[$i]}" = "$_RD" ] && [ "${CH_LIM_RH[$i]}" = "$_RH" ] && [ "${CH_LIM_RM[$i]}" = "$_RM" ]; then
          echo "rule $i already starts ${CH_LIM_RL[$i]}: claude-html --limits remove $i first" >&2; return 1
        fi
        i=$((i + 1))
      done
      [ "$CH_LIM_N" -lt "$CH_LIM_MAX_RULES" ] || { echo "$CH_LIM_MAX_RULES rules at most: remove one first" >&2; return 1; }
      ch_lim_rules_text
      ch_lim_day_name "$_RD"
      ch_lim_set CLAUDE_HTML_LIMIT_RULES "${_RTXT:+$_RTXT · }$_DW $(printf '%02d:%02d' "$_RH" "$_RM") ${_RP}%"
      ch_lim_parse_rules "$CLAUDE_HTML_LIMIT_RULES"; n=$CH_LIM_N
      echo "Added rule $n: $(ch_lim_words "$n")."
      [ -n "$CH_LIM_ON" ] || echo "Limits are off: claude-html --limits on turns them on."
      ch_lim_prompt_hook || echo "The prompt hook is not in settings.json, so nothing is stopped yet: ./install.sh in $HERE adds it." ;;
    remove)
      [ $# = 1 ] && [[ "$1" =~ ^[0-9]{1,2}$ ]] || { ch_lim_usage; return 2; }
      n=$((10#$1))
      if [ "$n" -lt 1 ] || [ "$n" -gt "$CH_LIM_N" ]; then
        if [ "$CH_LIM_N" = 0 ]; then echo "there is no stop rule to remove" >&2
        else echo "no rule $n: there are $CH_LIM_N (claude-html --limits lists them)" >&2; fi
        return 1
      fi
      local gone; gone="$(ch_lim_words "$n")"
      local keep="" j=1
      while [ $j -le "$CH_LIM_N" ]; do
        [ $j = "$n" ] || keep="${keep:+$keep · }${CH_LIM_RT[$j]}"
        j=$((j + 1))
      done
      ch_lim_set CLAUDE_HTML_LIMIT_RULES "$keep"
      printf 'Removed rule %s (%s).' "$n" "$gone"
      if [ "$n" -lt "$CH_LIM_N" ]; then
        if [ $((CH_LIM_N - n)) = 1 ]; then printf ' Rule %s is now rule %s.' "$CH_LIM_N" "$n"
        else printf ' Rules %s to %s are now %s to %s.' $((n + 1)) "$CH_LIM_N" "$n" $((CH_LIM_N - 1)); fi
      fi
      echo ;;
    rules)
      [ $# = 1 ] || { ch_lim_usage; return 2; }
      case "$1" in none|"") ch_lim_set CLAUDE_HTML_LIMIT_RULES ""; echo "No stop rules."; return 0 ;; esac
      ch_lim_parse_rules "$1"
      if [ -n "$CH_LIM_BAD" ] || [ "$CH_LIM_N" = 0 ]; then
        echo "not rules: ${CH_LIM_BAD:-$1} — each is a day, a time and a percentage, joined by \" · \" or commas" >&2
        return 2
      fi
      ch_lim_rules_text; ch_lim_set CLAUDE_HTML_LIMIT_RULES "$_RTXT"
      i=1; printf 'Stop rules:'
      while [ $i -le "$CH_LIM_N" ]; do printf ' %s%s' "$(ch_lim_words $i)" "$([ $i -lt "$CH_LIM_N" ] && echo ';' || echo .)"; i=$((i + 1)); done
      echo ;;
    budget)
      case "${1:-}" in
        off|none)
          [ $# = 1 ] || { ch_lim_usage; return 2; }
          ch_lim_set CLAUDE_HTML_BUDGET off; echo "Budget off." ;;
        warn)
          [ $# = 3 ] && [[ "$2" =~ ^[0-9]{1,2}$ ]] && [[ "$3" =~ ^[0-9]{1,2}$ ]] &&
            [ $((10#$2)) -ge 1 ] && [ $((10#$2)) -lt $((10#$3)) ] ||
            { echo "budget warnings are two percentages, the first lower: claude-html --limits budget warn 80 95" >&2; return 2; }
          ch_lim_set CLAUDE_HTML_BUDGET_WARN "$((10#$2)) $((10#$3))"
          echo "Budget warnings at $((10#$2)) % and $((10#$3)) %, for API use." ;;
        day|week|month)
          [ $# = 2 ] && [[ "$2" =~ ^\$?[0-9]{1,6}(\.[0-9]{1,2})?$ ]] ||
            { echo "a budget is a period and an amount in dollars: claude-html --limits budget week 50" >&2; return 2; }
          ch_lim_parse_budget "${2#\$} $1"
          [ "$CH_LIM_BC" -gt 0 ] || { echo "a budget of nothing is no budget: claude-html --limits budget off" >&2; return 2; }
          ch_lim_set CLAUDE_HTML_BUDGET "$CH_LIM_BA $CH_LIM_BP"
          echo "Budget: \$$CH_LIM_BA per $CH_LIM_BP, for API use (warnings at $CH_LIM_W1 % and $CH_LIM_W2 %)." ;;
        *) ch_lim_usage; return 2 ;;
      esac ;;
    notify)
      case "$*" in
        on) ch_lim_set CLAUDE_HTML_LIMIT_NOTIFY on
            echo "Desktop banner on, for rule announcements and budget warnings. On macOS the first one may ask for permission, and shows \"Script Editor\" as its source." ;;
        off) ch_lim_set CLAUDE_HTML_LIMIT_NOTIFY off; echo "Desktop banner off." ;;
        *) ch_lim_usage; return 2 ;;
      esac ;;
    on)
      [ $# = 0 ] || { ch_lim_usage; return 2; }
      ch_lim_set CLAUDE_HTML_LIMITS on; echo "Limits on." ;;
    off)
      [ $# = 0 ] || { ch_lim_usage; return 2; }
      ch_lim_set CLAUDE_HTML_LIMITS off
      echo "Limits off: no stop, no announcement, no budget warning, no banner. Your rules stay in the file; claude-html --limits on brings them back." ;;
    *) ch_lim_usage; return 2 ;;
  esac
  return 0
}

# ── from the page: claude-html://limits/<payload> ────────────────────
# Any web page can open such a link, so what it carries is a fixed
# grammar and nothing else, at most 160 characters, checked here as the
# helper and the Linux handler check it before: version, rules, budget,
# budget warnings, banner.
#
#   v1/<rules>/<budget>/<warn>/<notify>
#   rules    none, or up to 8 of day-HHMM-pct joined by dots: fri-2000-80.sat-0000-90
#   budget   none, or dollars-period: 50-week, 12.50-month, 5-day
#   warn     two percentages: 80-95
#   notify   on or off
#
# Nothing in it is ever run; it only picks values. And nothing is written
# until a person says so in a window, Cancel the default.
CH_LIM_LINK_DAY='(mon|tue|wed|thu|fri|sat|sun)'
CH_LIM_LINK_RULE="$CH_LIM_LINK_DAY-([01][0-9]|2[0-3])[0-5][0-9]-([1-9][0-9]?|100)"
CH_LIM_LINK_RE="^v1/(none|$CH_LIM_LINK_RULE(\\.$CH_LIM_LINK_RULE){0,7})/(none|[1-9][0-9]{0,5}(\\.[0-9]{1,2})?-(day|week|month))/[1-9][0-9]?-[1-9][0-9]?/(on|off)\$"
ch_lim_link_ok() {
  case "$1" in *[!a-z0-9./-]*) return 1 ;; esac
  [ "${#1}" -le 160 ] && [[ "$1" =~ $CH_LIM_LINK_RE ]]
}

ch_lim_apply() {   # payload
  local p="${1:-}" v rules budget warn notify w1 w2 r rows newrules="" nb nw nn cmd old
  if ! ch_lim_link_ok "$p"; then echo "not a limits link" >&2; return 2; fi
  IFS=/ read -r v rules budget warn notify <<EOF
$p
EOF
  w1=$((10#${warn%-*})); w2=$((10#${warn#*-}))
  [ "$w1" -lt "$w2" ] || { echo "not a limits link: the first budget warning must be the lower" >&2; return 2; }
  ch_lim_settings
  ch_lim_rules_text; old=" · $_RTXT · "
  # What will be written, as the conf holds it.
  if [ "$rules" != none ]; then
    for r in ${rules//./ }; do
      newrules="${newrules:+$newrules · }${r%%-*} ${r:4:2}:${r:6:2} ${r##*-}%"
    done
  fi
  if [ "$budget" = none ]; then nb=off; else nb="${budget%-*} ${budget##*-}"; fi
  nw="$w1 $w2"; nn="$notify"
  ch_lim_parse_rules "$newrules"; ch_lim_parse_budget "$nb"
  [ -z "$CH_LIM_BAD$CH_LIM_BBAD" ] || { echo "not a limits link" >&2; return 2; }
  # The window: every value it will write, the new rules marked.
  rows=""
  if [ "$CH_LIM_N" = 0 ]; then rows="Stop rules:	none"
  else
    local i=1 mark
    while [ $i -le "$CH_LIM_N" ]; do
      mark=""; case "$old" in *" · ${CH_LIM_RT[$i]} · "*) ;; *) mark="   (new)" ;; esac
      if [ $i = 1 ]; then rows="Stop rules:	$(ch_lim_words $i)$mark"
      else rows="$rows
	$(ch_lim_words $i)$mark"; fi
      i=$((i + 1))
    done
  fi
  if [ "$CH_LIM_BC" -gt 0 ]; then rows="$rows
Budget:	\$$CH_LIM_BA per $CH_LIM_BP, for API use"
  else rows="$rows
Budget:	none"; fi
  rows="$rows
Budget warnings:	at $w1 % and $w2 %, for API use
Notification:	$nn
File:	$(ch_lim_tilde "$CONF")"
  cmd="claude-html --limits rules \"${newrules:-none}\"
claude-html --limits budget $( [ "$CH_LIM_BC" -gt 0 ] && echo "$CH_LIM_BP $CH_LIM_BA" || echo off )
claude-html --limits budget warn $w1 $w2
claude-html --limits notify $nn"

  # One window at a time: a page that opens the link again and again
  # gets one question, not a pile of them.
  local ask="$HOME/.claude/.claude-html-limits-ask"
  ch_ask_take "$ask"; case $? in
    0) ;;
    3) echo "a window asking about the limits is already open; nothing was changed" >&2; return 3 ;;
    *) echo "could not ask; nothing was changed" >&2; return 1 ;;
  esac
  ch_detect; CH_HERE="$HERE"
  local ans
  # The arrow on File: the very lines Apply writes, as ch_conf_set writes them.
  local lines
  lines="CLAUDE_HTML_LIMIT_RULES=$(ch_conf_value "$newrules")
CLAUDE_HTML_BUDGET=$(ch_conf_value "$nb")
CLAUDE_HTML_BUDGET_WARN=$(ch_conf_value "$nw")
CLAUDE_HTML_LIMIT_NOTIFY=$(ch_conf_value "$nn")"
  ans="$(ch_confirm "Change claude-html limits?" "Asked by the Token usage page." "$rows" Apply File: "$lines")"
  local rc=$?
  rm -rf "$ask"
  if [ $rc != 0 ]; then
    echo "no way to ask you first here, so nothing was changed. To make the same change, run:" >&2
    printf '%s\n' "$cmd" >&2
    return 1
  fi
  if [ -n "${CH_DRY:-}" ]; then printf '%s\n' "$ans"; return 0; fi
  if [ "$ans" != apply ]; then echo "Nothing was changed."; return 0; fi
  ch_lim_set CLAUDE_HTML_LIMIT_RULES "$newrules"
  ch_lim_set CLAUDE_HTML_BUDGET "$nb"
  ch_lim_set CLAUDE_HTML_BUDGET_WARN "$nw"
  ch_lim_set CLAUDE_HTML_LIMIT_NOTIFY "$nn"
  echo "Applied."
  return 10   # the caller rebuilds the pages
}

# One line for --doctor.
ch_lim_doctor() {
  ch_lim_settings; ch_lim_now; ch_lim_read_state
  local out
  out="status line $(ch_lim_statusline_state | sed 's/: .*//') · $CH_LIM_N rule(s)"
  if [ "$CH_LIM_BC" -gt 0 ]; then out="$out · budget \$$CH_LIM_BA/$CH_LIM_BP"; else out="$out · no budget"; fi
  [ -n "$CH_LIM_ON" ] || out="$out · off"
  [ -n "$CH_LIM_NOTIFY" ] && out="$out · banner on"
  if [ -n "${S_asof:-}" ] && [ -n "${S_week_pct:-}" ]; then
    ch_lim_round "$S_week_pct"; out="$out · week $_RND %"
    ch_lim_round "${S_five_pct:-}" && out="$out, 5 h $_RND %"
    ch_lim_wlabel "$S_asof"
    out="$out as of $_LBL ($(ch_lim_ago "$S_asof"))"
    ch_lim_fresh || out="$out: no recent usage values"
  else
    out="$out · no usage values yet"
  fi
  printf '%s\n' "$out"
}
