#!/bin/bash
# Plan limits, the API budget and the stop rules: the status line that
# records Claude Code's figures, the rules' weeks across a change of the
# clocks, the stop in the guard's prompt hook, the announcements, the
# command, the claude-html://limits link and the pages.
#
# Nothing here reads the clock to decide anything: every "now" is given,
# through CLAUDE_HTML_TEST_NOW, and every time zone is named. Everything
# runs in a home of its own.
#
#   bash tests/limits.test.sh
set -u

. "$(dirname "$0")/lib.sh"

HERE="$(cd "$(dirname "$0")/.." && pwd)"
check() { check_long "$@"; }
T="$(cd "$(tmpdir chlimits)" && pwd -P)"
trap 'rm -rf "$T"' EXIT
H="$T/home"; mkdir -p "$H/.claude" "$T/stub" "$T/out" "$T/root"
CONFF="$H/.claude/claude-html.conf"; STATE="$H/.claude/.claude-html.limits"
MARKS="$H/.claude/.claude-html.limits-marks"; SPEND="$H/.claude/.claude-html.spend"
export TZ=Europe/Zurich
ESC=$(printf '\033')
plain() { sed "s/$ESC\\[[0-9;]*m//g"; }
# An epoch from a UTC time, or a local one in this file's zone.
ep() { node -e 'console.log(Math.round(new Date(process.argv[1]).getTime() / 1000))' "$1"; }
conf() { { printf 'CLAUDE_HTML_ROOT="%s"\nCLAUDE_HTML_OUT="%s"\n' "$T/root" "$T/out"; for l in "$@"; do printf '%s\n' "$l"; done; } > "$CONFF"; }
RULES='CLAUDE_HTML_LIMIT_RULES="fri 20:00 80% · sat 00:00 90%"'

# Stand-ins for node and osascript that only say they were started: the
# status line, the rules and the fast paths must never start either.
for s in node osascript; do printf '#!/bin/sh\necho "%s $*" >> "%s/started"\nexit 0\n' "$s" "$T" > "$T/stub/$s"; chmod +x "$T/stub/$s"; done
started() { cat "$T/started" 2>/dev/null | wc -l | tr -d ' '; }

# The figures, a Saturday afternoon in a week that resets Tuesday 07:00 UTC.
R=$(ep 2026-11-24T07:00:00Z)          # the weekly reset, Tue 08:00 in Zurich
NOW=$(ep 2026-11-21T13:29:00Z)        # Sat 14:29
FIVE=$(ep 2026-11-21T15:30:00Z)       # 16:30
FRI=$(ep 2026-11-20T19:00:00Z)        # the rule's start, Fri 20:00
SAT0=$(ep 2026-11-20T23:00:00Z)       # Sat 00:00
payload() {   # file five week [extra json] — real-shaped, as the docs give it
  cat > "$1" <<EOF
{
  "cwd": "/work/app", "session_id": "abc-123", "session_name": "a \"five_hour\": {} name",
  "transcript_path": "/x.jsonl",
  "model": { "id": "claude-opus-5-5", "display_name": "Opus" },
  "workspace": { "current_dir": "/work/app", "project_dir": "/work/app", "added_dirs": [] },
  "version": "2.1.300", "output_style": { "name": "default" },
  "cost": { "total_cost_usd": 1.1234, "total_duration_ms": 45000, "total_api_duration_ms": 2300 },
  "context_window": { "used_percentage": 8, "current_usage": { "input_tokens": 8500 } },
  "rate_limits": {
    "five_hour": { "used_percentage": $2, "resets_at": $FIVE },
    "seven_day": { "used_percentage": $3, "resets_at": $R },
    "spend_limit": { "used_percentage": 12.8, "resets_at": 1740787200, "used_usd": 314.12, "limit_usd": 500, "period": "monthly" }
  }${4:-}
}
EOF
}
sl() {   # payload [env…]
  local f="$1"; shift
  env -i CLAUDE_HTML_NO_SCREEN= PATH="$T/stub:$PATH" HOME="$H" TZ="$TZ" CLAUDE_HTML_CONF="$CONFF" CLAUDE_HTML_TEST_NOW="$NOW" "$@" \
    /bin/bash "$HERE/statusline.sh" < "$f"
}

echo "status line"
conf "$RULES"
payload "$T/p1" 62.4 81.3
L="$(sl "$T/p1")"
check "subscription: the plan's two windows, their resets and the rule" "$(printf '%s' "$L" | plain)" \
  "plan · 5 h ██████░░░░ 62 % ↻16:30 · week ████████░░ 81 % ↻Tue 08:00 · stop at 80 % from Fri 20:00"
check "  green below 80, amber from 80" \
  "$(printf '%s' "$L" | grep -c "${ESC}\[32m██████░░░░ 62 %") $(printf '%s' "$L" | grep -c "${ESC}\[38;5;214m████████░░ 81 %")" "1 1"
check "  the rule in force and reached, amber too" "$(printf '%s' "$L" | grep -c "${ESC}\[38;5;214mstop at 80 %")" 1
payload "$T/p2" 12 96
check "  red from 95" "$(sl "$T/p2" | grep -c "${ESC}\[31m█████████▌ 96 %")" 1
check "  NO_COLOR: none" "$(sl "$T/p2" NO_COLOR=1 | grep -c "$ESC")" 0
check "  and a half cell for a half" "$(sl "$T/p2" | plain | grep -o '█*▌*░* 12 %')" "█░░░░░░░░░ 12 %"
payload "$T/p3" 45.5 30
check "  45.5 %: four cells and a half, 46 %" "$(sl "$T/p3" | plain | grep -o '█*▌░* 46 %')" "████▌░░░░░ 46 %"
check "the state: the figures, their time, the session and its cost" \
  "$(sl "$T/p1" >/dev/null; grep -E '^(asof|five_pct|five_reset|week_pct|week_reset|cost|session)=' "$STATE" | tr '\n' ' ')" \
  "asof=$NOW five_pct=62.4 five_reset=$FIVE week_pct=81.3 week_reset=$R cost=1.1234 session=abc-123 "
check "  readable by its owner only" "$(ls -l "$STATE" | cut -c1-10)" "-rw-------"
check "  the spend limit's percentage is not taken for a window's" "$(grep -c '12.8' "$STATE")" 0

# Written only when something changed: the same figures a minute later
# leave the file as it was; new figures, or five minutes, write it.
touch -t 202001010000 "$STATE"; M0="$(mtime_of "$STATE")"
sl "$T/p1" CLAUDE_HTML_TEST_NOW=$((NOW + 60)) >/dev/null
check "the same figures a minute later: not written" "$(mtime_of "$STATE")" "$M0"
payload "$T/p4" 63 81.3
sl "$T/p4" CLAUDE_HTML_TEST_NOW=$((NOW + 120)) >/dev/null
check "new figures: written, as of then" "$(mtime_of "$STATE" | grep -vc "^$M0\$") $(grep -c "^asof=$((NOW + 120))$" "$STATE")" "1 1"
touch -t 202001010000 "$STATE"; M0="$(mtime_of "$STATE")"
sl "$T/p4" CLAUDE_HTML_TEST_NOW=$((NOW + 120 + 299)) >/dev/null
check "  unchanged 299 s later: not written" "$(mtime_of "$STATE")" "$M0"
sl "$T/p4" CLAUDE_HTML_TEST_NOW=$((NOW + 120 + 300)) >/dev/null
check "  300 s later: written, so \"as of\" moves" "$(grep -c "^asof=$((NOW + 420))$" "$STATE")" 1

# Any order, any spacing, all on one line or spread over many.
node -e 'var f=require("fs"),o=JSON.parse(f.readFileSync(process.argv[1],"utf8"));
  var r={}; Object.keys(o).reverse().forEach(function(k){r[k]=o[k];});
  r.rate_limits={seven_day:{resets_at:o.rate_limits.seven_day.resets_at,used_percentage:o.rate_limits.seven_day.used_percentage},
                 spend_limit:o.rate_limits.spend_limit, five_hour:{resets_at:o.rate_limits.five_hour.resets_at,used_percentage:o.rate_limits.five_hour.used_percentage}};
  f.writeFileSync(process.argv[2], JSON.stringify(r));
  f.writeFileSync(process.argv[3], JSON.stringify(r,null,"\t").replace(/:/g," :\n  "));' "$T/p1" "$T/p1.compact" "$T/p1.spread"
rm -f "$STATE"
A="$(sl "$T/p1" | plain)"; rm -f "$STATE"
check "fields in reverse order, on one line: the same line" "$(sl "$T/p1.compact" | plain)" "$A"; rm -f "$STATE"
check "with tabs and line breaks around every colon: the same line" "$(sl "$T/p1.spread" | plain)" "$A"

# What is missing is left out, never an error.
printf '{"session_id":"s1","cost":{"total_cost_usd":0.5}}' > "$T/api1"
printf '{"session_id":"s1"}' > "$T/bare"
printf 'not json {' > "$T/junk"
rm -f "$STATE"
check "no rate_limits, no budget: this session's cost" "$(sl "$T/api1" | plain)" "claude-html · this session \$0.50"
check "nothing at all: a minimal line" "$(sl "$T/bare" | plain)" "claude-html"
check "not JSON: the same, and exit 0" "$(sl "$T/junk" | plain | tr -d '\n'; echo " ${PIPESTATUS[0]}")" "claude-html 0"
check "no stdin: the same" "$(env -i CLAUDE_HTML_NO_SCREEN="${CLAUDE_HTML_NO_SCREEN:-}" PATH="$PATH" HOME="$H" CLAUDE_HTML_CONF="$CONFF" /bin/bash "$HERE/statusline.sh" </dev/null | plain)" "claude-html"
printf '{"session_id":"s1","cost":{"total_cost_usd":1.2e-05}}' > "$T/tiny"
check "a cost in exponent form: nothing worth a cent" "$(sl "$T/tiny" | plain)" "claude-html · this session \$0.00"
payload "$T/five" 34 81 ; node -e 'var f=require("fs"),o=JSON.parse(f.readFileSync(process.argv[1],"utf8")); delete o.rate_limits.seven_day; f.writeFileSync(process.argv[1],JSON.stringify(o))' "$T/five"
rm -f "$STATE"
check "only the five-hour window: that one" "$(sl "$T/five" | plain)" "plan · 5 h ███░░░░░░░ 34 % ↻16:30"

# The API budget: the week's spend as the build counted it, this
# session's own cost added while the build has not counted it.
rm -f "$STATE"; conf 'CLAUDE_HTML_BUDGET="50 week"' 'CLAUDE_HTML_WEEK_RESET="tue 07:00 UTC"'
printf 'start=%s\nend=%s\nmicro=37080000\nids=11111111-1111-4111-8111-111111111111\n' $((R - 604800)) "$R" > "$SPEND"
printf '{"session_id":"abc-123","cost":{"total_cost_usd":1.12}}' > "$T/api2"
check "API: the budget line, the session added once" "$(sl "$T/api2" | plain)" \
  "budget · week \$38.20 of \$50 ███████▌░░ 76 % ↻Tue 08:00 · this session \$1.12"
printf 'start=%s\nend=%s\nmicro=38200000\nids=abc-123\n' $((R - 604800)) "$R" > "$SPEND"
check "  a session the build counted is not counted twice" "$(sl "$T/api2" | plain | grep -o 'week \$[0-9.]*')" "week \$38.20"
printf 'start=%s\nend=%s\nmicro=38200000\nids=\n' $((R - 2 * 604800)) $((R - 604800)) > "$SPEND"
check "  a total from last week: this week starts from nothing" "$(sl "$T/api2" | plain | grep -o 'week \$[0-9.]* of \$50 [^ ]* [0-9]* %')" "week \$1.12 of \$50 ░░░░░░░░░░ 2 %"
rm -f "$SPEND"
check "  no total yet: says so" "$(sl "$T/api2" | plain)" \
  "budget · \$50 per week, no total yet: claude-html counts it at the next save · this session \$1.12"
check "it never started node or osascript" "$(started)" 0

# ── the line's options ──────────────────────────────────────────────
echo "status line options"
conf "$RULES"; rm -f "$STATE" "$H/.claude/.claude-html.today"
ALL='CLAUDE_HTML_STATUSLINE_ITEMS=five week session today ctx model project stop'
check "the defaults: the line of before, exactly" "$(sl "$T/p1" | plain)" \
  "plan · 5 h ██████░░░░ 62 % ↻16:30 · week ████████░░ 81 % ↻Tue 08:00 · stop at 80 % from Fri 20:00"
check "  a wide terminal changes nothing" "$(sl "$T/p1" COLUMNS=200 | plain)" \
  "plan · 5 h ██████░░░░ 62 % ↻16:30 · week ████████░░ 81 % ↻Tue 08:00 · stop at 80 % from Fri 20:00"
check "  a terminal of 101 columns holds its 97, with the 4 Claude Code keeps" "$(sl "$T/p1" COLUMNS=101 | plain)" \
  "plan · 5 h ██████░░░░ 62 % ↻16:30 · week ████████░░ 81 % ↻Tue 08:00 · stop at 80 % from Fri 20:00"
check "  one of 100 does not: the last item condensed" "$(sl "$T/p1" COLUMNS=100 | plain)" \
  "plan · 5 h ██████░░░░ 62 % ↻16:30 · week ████████░░ 81 % ↻Tue 08:00 · stop80%"
rm -f "$H/.claude/.claude-html.today"
check "every item, normal" "$(sl "$T/p1" "$ALL" CLAUDE_HTML_STATUSLINE_FORM=normal | plain)" \
  "plan · 5 h ██████░░░░ 62 % ↻16:30 · week ████████░░ 81 % ↻Tue 08:00 · this session \$1.12 · today \$1.12 · ctx 8 % · Opus 5.5 · app · stop at 80 % from Fri 20:00"
check "  condensed: each item's short form, the first word gone" "$(sl "$T/p1" "$ALL" CLAUDE_HTML_STATUSLINE_FORM=condensed | plain)" \
  "5h:62% ↻16:30 · wk:81% ↻Tu08 · ses\$1.12 · today\$1.12 · ctx8% · Op5.5 · ap · stop80%"
L="$(sl "$T/p1" "$ALL" | plain)"
check "  auto, 100 columns: condensed from the last listed until it fits" "$L" \
  "plan · 5h:62% ↻16:30 · wk:81% ↻Tu08 · ses\$1.12 · today\$1.12 · ctx8% · Op5.5 · ap · stop80%"
check "  110: the 5-hour window keeps its normal form" "$(sl "$T/p1" "$ALL" CLAUDE_HTML_STATUSLINE_WIDTH=110 | plain)" \
  "plan · 5 h ██████░░░░ 62 % ↻16:30 · wk:81% ↻Tu08 · ses\$1.12 · today\$1.12 · ctx8% · Op5.5 · ap · stop80%"
W="$(node -e 'console.log(Array.from(process.argv[1]).length)' "$L")"
check "  and it fits: $W columns" "$([ "$W" -le 100 ] && echo fits)" fits
check "  the terminal narrower (COLUMNS=60): its width less 4 wins" "$(sl "$T/p1" "$ALL" COLUMNS=60 | plain)" \
  "5h:62% ↻16:30 · wk:81% ↻Tu08 · ses\$1.12 · today\$1.12 · ctx8% · Op5.5 · ap · stop80%"
check "  the width setting, 70: the week condensed too, the first word kept" "$(sl "$T/p1" CLAUDE_HTML_STATUSLINE_WIDTH=70 | plain)" \
  "plan · 5 h ██████░░░░ 62 % ↻16:30 · wk:81% ↻Tu08 · stop80%"
check "  a width that is no number: the default" "$(sl "$T/p1" CLAUDE_HTML_STATUSLINE_WIDTH=wide | plain)" "$(sl "$T/p1" | plain)"
check "items in another order, the 5-hour window last" "$(sl "$T/p1" CLAUDE_HTML_STATUSLINE_ITEMS="week, stop five" | plain)" \
  "plan · week ████████░░ 81 % ↻Tue 08:00 · stop at 80 % from Fri 20:00 · 5 h ██████░░░░ 62 % ↻16:30"
check "  none: the first word alone" "$(sl "$T/p1" CLAUDE_HTML_STATUSLINE_ITEMS=none | plain)" "plan"
check "  a word that is no item is passed over" "$(sl "$T/p1" CLAUDE_HTML_STATUSLINE_ITEMS="week bogus" | plain)" "plan · week ████████░░ 81 % ↻Tue 08:00"
check "bar of 5 blocks, of 20" "$(sl "$T/p3" CLAUDE_HTML_STATUSLINE_BAR=5 | plain | grep -o '5 h [^ ]* ') | $(sl "$T/p3" CLAUDE_HTML_STATUSLINE_BAR=20 | plain | grep -o '5 h [^ ]* ')" \
  "5 h ██░░░  | 5 h █████████░░░░░░░░░░░ "
check "  a bar only from 70 %: none under it" "$(sl "$T/p3" CLAUDE_HTML_STATUSLINE_BAR_FROM=70 | plain)" \
  "plan · 5 h 46 % ↻16:30 · week 30 % ↻Tue 08:00 · stop at 80 % from Fri 20:00"
check "    the 81 % one with its bar, the 62 % one without" "$(sl "$T/p1" CLAUDE_HTML_STATUSLINE_BAR_FROM=70 | plain)" \
  "plan · 5 h 62 % ↻16:30 · week ████████░░ 81 % ↻Tue 08:00 · stop at 80 % from Fri 20:00"
check "colours auto: no colour on a figure, the terminal's own; the rest stays dim" \
  "$(sl "$T/p1" CLAUDE_HTML_STATUSLINE_COLOR=auto | grep -c -e "${ESC}\[3[0-9]m" -e "${ESC}\[9[0-9]m" -e "${ESC}\[38;5;214m") $(sl "$T/p1" CLAUDE_HTML_STATUSLINE_COLOR=auto | grep -c "${ESC}\[2m")" "0 1"
check "  level, and on from an earlier 3.7.0: the line of before" \
  "$(sl "$T/p1" CLAUDE_HTML_STATUSLINE_COLOR=level | od -c | md5sum 2>/dev/null || sl "$T/p1" CLAUDE_HTML_STATUSLINE_COLOR=level | od -c | md5) $(sl "$T/p1" CLAUDE_HTML_STATUSLINE_COLOR=on | od -c | md5sum 2>/dev/null || sl "$T/p1" CLAUDE_HTML_STATUSLINE_COLOR=on | od -c | md5)" \
  "$(sl "$T/p1" | od -c | md5sum 2>/dev/null || sl "$T/p1" | od -c | md5) $(sl "$T/p1" | od -c | md5sum 2>/dev/null || sl "$T/p1" | od -c | md5)"
o=""
for c in green cyan blue magenta yellow red grey; do
  L="$(sl "$T/p1" CLAUDE_HTML_STATUSLINE_COLOR=$c)"
  o="$o$c:$(printf '%s' "$L" | grep -o "${ESC}\[[0-9;]*m[█░▌ ]*[0-9]* %" | sed "s/$ESC\[\([0-9;]*\)m.*/\1/" | sort -u | tr '\n' ',') "
done
check "  a fixed colour: each figure in the terminal's own basic colour" "$o" \
  "green:32, cyan:36, blue:34, magenta:35, yellow:33, red:31, grey:90, "
check "    the stop rule left as it is, the line as wide" \
  "$(sl "$T/p1" CLAUDE_HTML_STATUSLINE_COLOR=cyan | grep -c "${ESC}\[38;5;214mstop") $(sl "$T/p1" CLAUDE_HTML_STATUSLINE_COLOR=cyan "$ALL" | plain)" \
  "0 $(sl "$T/p1" "$ALL" | plain)"
check "colours off, from an earlier 3.7.0: no green, amber or red; the rest stays dim" \
  "$(sl "$T/p1" CLAUDE_HTML_STATUSLINE_COLOR=off | grep -c -e "${ESC}\[32m" -e "${ESC}\[38;5;214m" -e "${ESC}\[31m") $(sl "$T/p1" CLAUDE_HTML_STATUSLINE_COLOR=off | grep -c "${ESC}\[2m")" "0 1"
check "  condensed, the figure coloured" "$(sl "$T/p1" CLAUDE_HTML_STATUSLINE_FORM=condensed | grep -c "5h:${ESC}\[32m62%")" 1
# The agent, from the model's id; one it does not know, by its name.
mj() { payload "$1" 62.4 81.3; node -e 'var f=require("fs"),o=JSON.parse(f.readFileSync(process.argv[1],"utf8")); o.model=JSON.parse(process.argv[2]); f.writeFileSync(process.argv[1],JSON.stringify(o))' "$1" "$2"; }
o=""
for m in '{"id":"claude-opus-5-5","display_name":"Opus"}' '{"id":"claude-fable-5-2"}' '{"id":"claude-sonnet-5-5[1m]"}' \
         '{"id":"claude-haiku-5-5-20261001"}' '{"id":"claude-3-5-sonnet-20241022"}' '{"id":"gpt-x-1","display_name":"Some Big Model"}' '{"id":"x"}'; do
  mj "$T/pm" "$m"
  o="$o$(sl "$T/pm" CLAUDE_HTML_STATUSLINE_ITEMS=model | plain | sed 's/^plan · //')/$(sl "$T/pm" CLAUDE_HTML_STATUSLINE_ITEMS=model CLAUDE_HTML_STATUSLINE_FORM=condensed | plain)|"
done
check "the agent: name and version, and two letters and the version" "$o" \
  "Opus 5.5/Op5.5|Fable 5.2/Fa5.2|Sonnet 5.5/So5.5|Haiku 5.5/Ha5.5|Sonnet 3.5/So3.5|Some Big Model/SomeBi|plan/plan|"
# The project and its branch, read from HEAD: a repository, a worktree's .git file.
mkdir -p "$T/w/Trading/.git" "$T/w/Trading/src" "$T/w/wt" "$T/w/Trading/.git/worktrees/wt"
echo "ref: refs/heads/v2" > "$T/w/Trading/.git/HEAD"
echo "gitdir: $T/w/Trading/.git/worktrees/wt" > "$T/w/wt/.git"; echo "0123456789abcdef0123456789abcdef01234567" > "$T/w/Trading/.git/worktrees/wt/HEAD"
pj() { printf '{"session_id":"s9","workspace":{"current_dir":"%s","project_dir":"%s"}}' "$2" "$3" > "$1"; }
pj "$T/pp1" "$T/w/Trading/src" "$T/w/Trading"; pj "$T/pp2" "$T/w/wt" "$T/w/wt"; pj "$T/pp3" "$T/root" "$T/root"
rm -f "$STATE"
check "project · branch, from a subfolder; condensed" \
  "$(sl "$T/pp1" CLAUDE_HTML_STATUSLINE_ITEMS=project | plain) | $(sl "$T/pp1" CLAUDE_HTML_STATUSLINE_ITEMS=project CLAUDE_HTML_STATUSLINE_FORM=condensed | plain)" \
  "claude-html · Trading · v2 | Tr.v2"
check "  a worktree, detached: its commit, short; no repository: the project alone" \
  "$(sl "$T/pp2" CLAUDE_HTML_STATUSLINE_ITEMS=project | plain) | $(sl "$T/pp3" CLAUDE_HTML_STATUSLINE_ITEMS=project | plain)" \
  "claude-html · wt · 0123456 | claude-html · root"
# Today's cost: each session from what it had cost when the day began.
TODAY="$H/.claude/.claude-html.today"; rm -f "$TODAY"
cs() { printf '{"session_id":"%s","cost":{"total_cost_usd":%s}}' "$2" "$3" > "$1"; }
cs "$T/c1" s1 1.00; cs "$T/c2" s2 2.50; cs "$T/c3" s1 1.20; cs "$T/c4" s1 1.75
sl "$T/c1" "CLAUDE_HTML_STATUSLINE_ITEMS=today" >/dev/null
check "today: two sessions add up" "$(sl "$T/c2" "CLAUDE_HTML_STATUSLINE_ITEMS=today session" | plain)" "claude-html · today \$3.50 · this session \$2.50"
check "  the next day, each from where it stood" "$(sl "$T/c3" "CLAUDE_HTML_STATUSLINE_ITEMS=today" CLAUDE_HTML_TEST_NOW=$((NOW + 86400)) | plain)" "claude-html · today \$0.20"
check "  and on" "$(sl "$T/c4" "CLAUDE_HTML_STATUSLINE_ITEMS=today" CLAUDE_HTML_TEST_NOW=$((NOW + 86500)) | plain)" "claude-html · today \$0.75"
check "  kept for its owner only" "$(ls -l "$TODAY" | cut -c1-10)" "-rw-------"
check "  not kept at all when it is not shown" "$(rm -f "$TODAY"; sl "$T/c1" >/dev/null; [ -e "$TODAY" ] && echo kept || echo none)" none
# API use: the budget item, its short form, and this session as before.
rm -f "$STATE"; conf 'CLAUDE_HTML_BUDGET="50 week"' 'CLAUDE_HTML_WEEK_RESET="tue 07:00 UTC"'
printf 'start=%s\nend=%s\nmicro=37080000\nids=\n' $((R - 604800)) "$R" > "$SPEND"
check "API, condensed: \$38/50 and ses\$1.12" "$(sl "$T/api2" CLAUDE_HTML_STATUSLINE_FORM=condensed | plain)" "\$38/50 · ses\$1.12"
check "  items listed without session: none of it" "$(sl "$T/api2" CLAUDE_HTML_STATUSLINE_ITEMS="budget ctx" | plain)" \
  "budget · week \$38.20 of \$50 ███████▌░░ 76 % ↻Tue 08:00"
rm -f "$SPEND"; conf "$RULES"
check "it still never started node or osascript" "$(started)" 0

# The Settings page's preview draws the same line as the command, item for
# item, for the same figures and settings (build/statusline.js).
rm -f "$STATE" "$TODAY"
PAR=""
while IFS='|' read -r name envs; do
  # shellcheck disable=SC2086
  b="$(eval "sl \"\$T/p1\" $envs" | plain)"
  j="$(node -e '
    var SL=require(process.argv[1]+"/build/statusline.js")(), e={};
    process.argv[2].replace(/"/g,"").split(" CLAUDE_HTML_STATUSLINE_").slice(1).forEach(function(kv){ var i=kv.indexOf("="); e[kv.slice(0,i).toLowerCase()]=kv.slice(i+1).replace(/^"|"$/g,""); });
    var m=/(^| )COLUMNS=(\d+)/.exec(process.argv[2]);
    var st=SL.settings({items:e.items,form:e.form,width:e.width,bar:e.bar,from:e.bar_from,color:e.color,columns:m?m[2]:""});
    var d={mode:"plan",five:{tenths:624,label:"16:30"},week:{tenths:813,label:"Tue 08:00"},stop:{pct:80,from:"Fri 20:00",hit:true},
      session:"$1.12",today:"$1.12",ctx:80,model:{id:"claude-opus-5-5",name:"Opus"},project:{name:"app",branch:""}};
    var h=SL.render(st,d).html, M={g:"32",a:"38;5;214",r:"31",green:"32",cyan:"36",blue:"34",magenta:"35",yellow:"33",red:"31",grey:"90"}, out=[], m, re=/<span class="sl-(\w+)">([^<]*)<\/span>/g;
    while ((m=re.exec(h))) if (m[1]!=="d") out.push(M[m[1]]+":"+m[2]);
    console.log(SL.render(st,d).text+"\t"+out.join("|"));' "$HERE" " $envs")"
  b="$b	$(eval "sl \"\$T/p1\" $envs" | node -e 'var t=require("fs").readFileSync(0,"utf8"),out=[],m,re=/\x1b\[([0-9;]+)m([^\x1b]*)\x1b\[0m/g; while((m=re.exec(t))) if(m[1]!=="2") out.push(m[1]+":"+m[2]); console.log(out.join("|"))')"
  [ "$b" = "$j" ] || PAR="$PAR
    $name: bash  $b
    $name: page  $j"
  rm -f "$TODAY"
done <<'EOF'
defaults|
all normal|"CLAUDE_HTML_STATUSLINE_ITEMS=five week session today ctx model project stop" CLAUDE_HTML_STATUSLINE_FORM=normal
all condensed|"CLAUDE_HTML_STATUSLINE_ITEMS=five week session today ctx model project stop" CLAUDE_HTML_STATUSLINE_FORM=condensed
all auto|"CLAUDE_HTML_STATUSLINE_ITEMS=five week session today ctx model project stop"
auto 60|"CLAUDE_HTML_STATUSLINE_ITEMS=five week session today ctx model project stop" CLAUDE_HTML_STATUSLINE_WIDTH=60
columns 50|"CLAUDE_HTML_STATUSLINE_ITEMS=five week session today ctx model project stop" COLUMNS=50
columns 90|COLUMNS=90
bars|CLAUDE_HTML_STATUSLINE_BAR=5 CLAUDE_HTML_STATUSLINE_BAR_FROM=70 CLAUDE_HTML_STATUSLINE_COLOR=off
bar 20|CLAUDE_HTML_STATUSLINE_BAR=20 "CLAUDE_HTML_STATUSLINE_ITEMS=stop week ctx"
none|CLAUDE_HTML_STATUSLINE_ITEMS=none
auto|CLAUDE_HTML_STATUSLINE_COLOR=auto
level|CLAUDE_HTML_STATUSLINE_COLOR=level
on|CLAUDE_HTML_STATUSLINE_COLOR=on
off|CLAUDE_HTML_STATUSLINE_COLOR=off
green|CLAUDE_HTML_STATUSLINE_COLOR=green "CLAUDE_HTML_STATUSLINE_ITEMS=five week ctx stop"
cyan|CLAUDE_HTML_STATUSLINE_COLOR=cyan "CLAUDE_HTML_STATUSLINE_ITEMS=five week ctx stop"
blue|CLAUDE_HTML_STATUSLINE_COLOR=blue CLAUDE_HTML_STATUSLINE_FORM=condensed
magenta|CLAUDE_HTML_STATUSLINE_COLOR=magenta
yellow|CLAUDE_HTML_STATUSLINE_COLOR=yellow
red|CLAUDE_HTML_STATUSLINE_COLOR=red
grey|CLAUDE_HTML_STATUSLINE_COLOR=grey "CLAUDE_HTML_STATUSLINE_ITEMS=five week ctx stop" CLAUDE_HTML_STATUSLINE_WIDTH=60
EOF
check "the page's preview is the command's line, setting for setting, its colours too (23 cases)" "$PAR" ""

# Theirs first: the same note on its stdin, its output whole, then ours.
conf "$RULES"; rm -f "$STATE"
W="$(sl "$T/p1" | plain)"
O="$(env -i CLAUDE_HTML_NO_SCREEN= PATH="$T/stub:$PATH" HOME="$H" TZ="$TZ" CLAUDE_HTML_CONF="$CONFF" CLAUDE_HTML_TEST_NOW="$NOW" \
     /bin/bash "$HERE/statusline.sh" --wrap "cat > '$T/inner.in'; printf 'theirs one\ntheirs \"two\"'" < "$T/p1" | plain)"
check "wrapped: their lines first, then ours" "$O" "theirs one
theirs \"two\"
$W"
check "  theirs read the same note" "$(cmp -s "$T/inner.in" "$T/p1" && echo same)" same
O="$(env -i CLAUDE_HTML_NO_SCREEN="${CLAUDE_HTML_NO_SCREEN:-}" PATH="$PATH" HOME="$H" TZ="$TZ" CLAUDE_HTML_CONF="$CONFF" CLAUDE_HTML_TEST_NOW="$NOW" \
     /bin/bash "$HERE/statusline.sh" --wrap "echo half; exit 3" < "$T/p1" | plain; echo "rc ${PIPESTATUS[0]}")"
check "  theirs failing: what it printed, ours, exit 0" "$O" "half
$W
rc 0"
S0=$(date +%s)
O="$(env -i CLAUDE_HTML_NO_SCREEN="${CLAUDE_HTML_NO_SCREEN:-}" PATH="$PATH" HOME="$H" TZ="$TZ" CLAUDE_HTML_CONF="$CONFF" CLAUDE_HTML_TEST_NOW="$NOW" CLAUDE_HTML_STATUSLINE_TEST_LIMIT=1 \
     /bin/bash "$HERE/statusline.sh" --wrap "sleep 30; echo late" < "$T/p1" | plain)"
check "  theirs hanging: ours, after its limit" "$O $([ $(( $(date +%s) - S0 )) -lt 20 ] && echo promptly)" "$W promptly"
check "  and nothing of either left behind" "$(ls -A "$H/.claude" | grep -c 'statusline-')" 0

# ── weeks and rules, across the clocks ───────────────────────────────
echo "weeks"
lim() {   # now, then bash run with limits.sh loaded and settings read
  local n="$1"; shift
  env -i CLAUDE_HTML_NO_SCREEN="${CLAUDE_HTML_NO_SCREEN:-}" PATH="$PATH" HOME="$H" TZ="$TZ" CLAUDE_HTML_CONF="$CONFF" CLAUDE_HTML_TEST_NOW="$n" \
    /bin/bash -c '. "$0/lib/platform.sh"; . "$0/lib/limits.sh"; ch_lim_settings; ch_lim_now; ch_lim_read_state; '"$*" "$HERE"
}
rm -f "$STATE"
# Zurich leaves summer time on Sunday 25 October 2026, at 01:00 UTC.
conf 'CLAUDE_HTML_WEEK_RESET="tue 07:00 UTC"' 'CLAUDE_HTML_LIMIT_RULES="sat 09:00 80%, sun 09:00 80%, mon 02:30 70%"'
check "a UTC reset: the same moment every week, across the change" \
  "$(lim "$(ep 2026-10-26T12:00:00Z)" 'ch_lim_week; echo $CH_WSRC $CH_WS $CH_WR')" \
  "conf $(ep 2026-10-20T07:00:00Z) $(ep 2026-10-27T07:00:00Z)"
check "  the rules land on the local hour on either side of it" \
  "$(lim "$(ep 2026-10-26T12:00:00Z)" 'ch_lim_week; ch_lim_rule_starts; echo ${CH_LIM_RS[1]} ${CH_LIM_RS[2]} ${CH_LIM_RS[3]}')" \
  "$(ep 2026-10-24T07:00:00Z) $(ep 2026-10-25T08:00:00Z) $(ep 2026-10-26T01:30:00Z)"
conf 'CLAUDE_HTML_WEEK_RESET="sat 09:00"' 'CLAUDE_HTML_LIMIT_RULES="fri 20:00 80%"'
check "a local reset: 09:00 on the clock both weeks, so this one is 169 hours" \
  "$(lim "$(ep 2026-10-27T12:00:00Z)" 'ch_lim_week; echo $CH_WS $CH_WR $(( (CH_WR - CH_WS) / 3600 ))')" \
  "$(ep 2026-10-24T07:00:00Z) $(ep 2026-10-31T08:00:00Z) 169"
check "  and its rule at 20:00 in winter time" \
  "$(lim "$(ep 2026-10-27T12:00:00Z)" 'ch_lim_week; ch_lim_rule_starts; echo ${CH_LIM_RS[1]}')" "$(ep 2026-10-30T19:00:00Z)"
# Into summer time, Sunday 29 March 2026: 02:30 that night does not exist.
conf 'CLAUDE_HTML_WEEK_RESET="mon 00:00"' 'CLAUDE_HTML_LIMIT_RULES="sun 03:00 80%, sun 01:30 50%, sat 12:00 60%"'
check "spring: a local week of 167 hours, its rules on the local hour" \
  "$(lim "$(ep 2026-03-29T12:00:00Z)" 'ch_lim_week; ch_lim_rule_starts; echo $(( (CH_WR - CH_WS) / 3600 )) ${CH_LIM_RS[1]} ${CH_LIM_RS[2]} ${CH_LIM_RS[3]}')" \
  "167 $(ep 2026-03-29T01:00:00Z) $(ep 2026-03-29T00:30:00Z) $(ep 2026-03-28T11:00:00Z)"
TZ=America/New_York
check "New York, out of summer time on 1 November: a Friday rule at 20:00 local" \
  "$(lim "$(ep 2026-11-02T12:00:00Z)" 'CLAUDE_HTML_WEEK_RESET="thu 10:00"; CLAUDE_HTML_LIMIT_RULES="fri 20:00 80%"; ch_lim_settings; ch_lim_week; ch_lim_rule_starts; echo $CH_WS ${CH_LIM_RS[1]}')" \
  "$(ep 2026-10-29T14:00:00Z) $(ep 2026-10-31T00:00:00Z)"
TZ=Europe/Zurich
# With Claude Code's resets_at the week is exactly the seven days before it.
conf "$RULES"
printf 'asof=%s\nweek_pct=85\nweek_reset=%s\nfive_pct=10\nfive_reset=%s\n' "$NOW" "$R" "$FIVE" > "$STATE"
inforce() { lim "$1" 'ch_lim_week; ch_lim_rule_starts; ch_lim_fresh || { echo stale; exit; }; ch_lim_hit && echo "stop ${CH_LIM_RT[$CH_LIM_HIT]}" || echo go'; }
check "resets_at known: the week ends exactly there" "$(lim "$NOW" 'ch_lim_week; echo $CH_WSRC $CH_WS $CH_WR')" "rate_limits $((R - 604800)) $R"
sed -i.b "s/^asof=.*/asof=$((FRI - 60))/" "$STATE"
check "  a second before Friday 20:00: nothing stops" "$(inforce $((FRI - 1)))" go
sed -i.b "s/^asof=.*/asof=$FRI/" "$STATE"
check "  at Friday 20:00: the rule stops the week at 85 %" "$(inforce "$FRI")" "stop fri 20:00 80%"
sed -i.b "s/^asof=.*/asof=$((R - 60))/" "$STATE"
check "  a second before the reset: still" "$(inforce $((R - 1)))" "stop fri 20:00 80%"
check "  at the reset: last week's figures stop nothing" "$(inforce "$R")" stale
sed -i.b "s/^asof=.*/asof=$((SAT0 + 3600))/" "$STATE"
check "  of two rules in force, the lower" "$(inforce $((SAT0 + 3600)))" "stop fri 20:00 80%"
sed -i.b "s/^week_pct=.*/week_pct=79.9/" "$STATE"
check "  79.9 % is not 80 %" "$(inforce $((SAT0 + 3600)))" go
sed -i.b "s/^asof=.*/asof=$((SAT0 - 6 * 3600 - 1))/; s/^week_pct=.*/week_pct=99/" "$STATE"
check "figures more than six hours old: nothing stops" "$(inforce "$SAT0")" stale
rm -f "$STATE"
check "no figures at all: nothing stops" "$(inforce "$SAT0")" stale
check "and none of it started node or osascript" "$(started)" 0

# ── the stop, in the guard's prompt hook ──────────────────────────────
echo "stop"
note() { printf '{"session_id":"sess-1","prompt":"%s","hook_event_name":"UserPromptSubmit","cwd":"/work/app"}' "$1"; }
fig() { printf 'asof=%s\nweek_pct=%s\nweek_reset=%s\nfive_pct=10\nfive_reset=%s\nplan_seen=%s\n' "$1" "$2" "$R" "$FIVE" "$1" > "$STATE"; }
words() {   # prompt [env…] — no one at the screen: the answer is the next prompt
  local p="$1"; shift
  note "$p" | env -i CLAUDE_HTML_NO_SCREEN= PATH="$T/stub:$PATH" HOME="$H" TZ="$TZ" CLAUDE_HTML_CONF="$CONFF" CLAUDE_HTML_TEST_NOW="$NOW" \
    CLAUDE_HTML_REDACT_FILE="$T/none" CLAUDE_HTML_GUARD_DIALOG=off "$@" /bin/bash "$HERE/guard.sh" prompt
}
reason() { node -e 'var s=require("fs").readFileSync(0,"utf8"); if (!s.trim()) { console.log("(passed)"); process.exit(); }
  var o=JSON.parse(s); console.log(o.decision + ": " + o.reason.split("\n")[0])'; }
conf "$RULES"; fig "$NOW" 81; rm -f "$MARKS"
shape() { node -e 'var o; try { o=JSON.parse(require("fs").readFileSync(0,"utf8")); } catch (e) { console.log("not JSON"); process.exit(); }
  var h=o.hookSpecificOutput||{}; console.log([o.decision, h.hookEventName, h.suppressOriginalPrompt===true, "suppressOriginalPrompt" in o].join(" "))'; }
check "the stop leaves the prompt out of the message (hookSpecificOutput)" "$(words "fix the bug" | shape)" "block UserPromptSubmit true false"
check "  and so does its answer" "$(words cancel | shape)" "block UserPromptSubmit true false"
check "in force and reached: the prompt is stopped, in words" "$(words "fix the bug" | reason)" \
  "block: ⚠ claude-html: your prompt has been interrupted — weekly limit rule reached (81 % of the week, resets Tue 08:00; rule: from Fri 20:00, stop at 80 %)."
check "  with the four answers" "$(words "fix the bug" | node -e 'console.log(JSON.parse(require("fs").readFileSync(0,"utf8")).reason.split("\n").slice(3).join("|"))')" \
  "  cancel  do not send|  allow   send this prompt only|  until   no more asking until the reset (Tue 08:00)|  stop    turn this rule off (claude-html --limits add \"fri 20:00 80%\" brings it back)"
check "cancel: dropped" "$(words cancel | reason)" "block: Dropped. Nothing was sent."
check "  and the next prompt asks again" "$(words "fix the bug" | grep -c 'your prompt has been interrupted')" 1
check "allow (any case, spaces): one prompt goes" "$(words "  Allow " | reason)" "block: Allowed once. Press ↑ and Enter to send it again."
check "  the next one" "$(words "fix the bug" | reason)" "(passed)"
check "  and only that one" "$(words "fix the bug" | grep -c 'your prompt has been interrupted')" 1
check "until: no more asking" "$(words until | reason)" "block: No more asking until the reset. Press ↑ and Enter to send it again."
check "  until the reset exactly" "$(grep -c "^allow=$R$" "$MARKS")" 1
check "  a second before it, prompts go" "$(words "go on" CLAUDE_HTML_TEST_NOW=$((R - 1)) | reason)" "(passed)"
N2=$((FRI + 7 * 86400 + 3600))
printf 'asof=%s\nweek_pct=90\nweek_reset=%s\nplan_seen=%s\n' "$N2" $((R + 604800)) "$N2" > "$STATE"
check "  past the reset, next week's rule stops again" "$(words "go on" CLAUDE_HTML_TEST_NOW="$N2" | grep -c 'your prompt has been interrupted')" 1
rm -f "$H/.claude/.claude-html-guard/limits-sess-1"
rm -f "$MARKS"; fig "$NOW" 81
words "fix the bug" >/dev/null
check "stop: the rule is off" "$(words stop | reason)" \
  "block: The rule \"fri 20:00 80%\" is off. Press ↑ and Enter to send it again; claude-html --limits add \"fri 20:00 80%\" brings it back."
check "  that rule only, its conf line rewritten" "$(grep -c '^CLAUDE_HTML_LIMIT_RULES="sat 00:00 90%"$' "$CONFF") $(grep -c '^CLAUDE_HTML_ROOT=' "$CONFF")" "1 1"
check "  and at 81 % the other one (90 %) lets it go" "$(words "fix the bug" | reason)" "(passed)"
conf "$RULES"
fig "$NOW" 50
check "a word with nothing pending is a prompt like any other" "$(words stop | reason) $(grep -c 'fri 20:00 80%' "$CONFF")" "(passed) 1"
fig $((NOW - 6 * 3600 - 1)) 99
check "figures more than six hours old: the prompt goes" "$(words "fix the bug" | reason)" "(passed)"
rm -f "$STATE"
check "no figures: the prompt goes" "$(words "fix the bug" | reason)" "(passed)"
fig "$NOW" 81
check "limits off: the prompt goes" "$(words "fix the bug" CLAUDE_HTML_LIMITS=off | reason)" "(passed)"
check "the stop never started node or osascript" "$(started)" 0
# Nothing set: nothing to do, not even a date.
printf '#!/bin/sh\necho "date $*" >> "%s/started"\nexec /bin/date "$@"\n' "$T" > "$T/stub/date"; chmod +x "$T/stub/date"
conf
check "no rule, no budget: a prompt costs no command at all" "$(words "hello there" | reason) $(started)" "(passed) 0"
rm -f "$T/stub/date"

# The window, through a stand-in zenity on a simulated Linux desktop.
cat > "$T/stub/zenity" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" >> "$STUB_ARGS"
case "$STUB_ANSWER" in
  sleep) sleep 30 ;;
  yes) exit 0 ;;
  no) exit 1 ;;
  *) for a in "$@"; do case "$a" in "$STUB_ANSWER"*) printf '%s\n' "$a"; exit 0 ;; esac; done; exit 1 ;;
esac
EOF
chmod +x "$T/stub/zenity"
dlg() {   # answer prompt [env…]
  local a="$1" p="$2"; shift 2
  note "$p" | env -i CLAUDE_HTML_NO_SCREEN= PATH="$T/stub:$PATH" HOME="$H" TZ="$TZ" CLAUDE_HTML_CONF="$CONFF" CLAUDE_HTML_TEST_NOW="$NOW" \
    CLAUDE_HTML_REDACT_FILE="$T/none" CLAUDE_HTML_UNAME=Linux DISPLAY=:9 XDG_CURRENT_DESKTOP=GNOME \
    STUB_ARGS="$T/stub.args" STUB_ANSWER="$a" CLAUDE_HTML_GUARD_TEST_LIMIT=120 "$@" /bin/bash "$HERE/guard.sh" prompt
}
conf "$RULES"; fig "$NOW" 81; rm -f "$MARKS"; : > "$T/stub.args"
check "window, Cancel: dropped" "$(dlg Cancel "fix the bug" | reason)" "block: Dropped. Nothing was sent."
check "  the guard's window: its title, the week, the rule, Cancel picked, OK" \
  "$(grep -c "^--text=Your prompt has been interrupted$" "$T/stub.args") $(grep -cx 'Weekly limit rule reached' "$T/stub.args") $(grep -cx 'Used:  81 % of the week  ·  resets Tue 08:00' "$T/stub.args") $(grep -cx 'Rule:  from Fri 20:00, stop at 80 %' "$T/stub.args") $(grep -A1 -x TRUE "$T/stub.args" | tail -1) $(grep -cx -- '--ok-label=OK' "$T/stub.args")" \
  "1 1 1 1 Cancel — do not send 1"
check "  its four choices" "$(grep -x -e 'Cancel — do not send' -e 'Allow once — send this prompt only' -e 'Allow until the reset — no more asking this week' -e 'Stop — turn this rule off' "$T/stub.args" | tr '\n' '|')" \
  "Cancel — do not send|Allow once — send this prompt only|Allow until the reset — no more asking this week|Stop — turn this rule off|"
check "window, Allow once: the prompt goes" "$(dlg "Allow once" "fix the bug" | reason)" "(passed)"
check "  and the next one asks again" "$(dlg Cancel "fix the bug" | reason)" "block: Dropped. Nothing was sent."
check "window, Allow until the reset: goes, and the next one too" "$(dlg "Allow until" "fix the bug" | reason) $(dlg Cancel "again" | reason)" "(passed) (passed)"
check "  until resets_at exactly" "$(grep -c "^allow=$R$" "$MARKS")" 1
rm -f "$MARKS"
check "window, Stop: goes, the rule off" "$(dlg Stop "fix the bug" | reason) $(grep -c '^CLAUDE_HTML_LIMIT_RULES="sat 00:00 90%"$' "$CONFF")" "(passed) 1"
conf "$RULES"; rm -f "$H/.claude/.claude-html-guard/limits-sess-1"
check "nobody answers in time: stopped, the words still answer" \
  "$(dlg sleep "fix the bug" CLAUDE_HTML_GUARD_TEST_LIMIT=2 | reason) | $(words allow | reason)" \
  "block: ⏸ claude-html: weekly limit rule reached and nobody answered within 2 seconds. | block: Allowed once. Press ↑ and Enter to send it again."
words "fix the bug" >/dev/null 2>&1; rm -f "$H/.claude/.claude-html-guard/limits-sess-1"
check "over ssh: in words" "$(dlg Cancel "fix the bug" SSH_CONNECTION="10.0.0.1 22 10.0.0.2 22" | grep -c 'Answer:\\n\\n  cancel  do not send')" 1

# The macOS window: the guard's dialog.js, given the rule's rows.
. "$HERE/lib/platform.sh"
check "macOS: osascript runs dialog.js with the rows and the last two choices" \
  "$(CH_DIALOG=osascript CH_HERE="$HERE" CH_DRY=1 ch_choose_limit "Weekly limit rule reached" "Used:" "81 % of the week  ·  resets Tue 08:00" "Rule:" "from Fri 20:00, stop at 80 %" "Allow until the reset — no more asking this week" "Stop — turn this rule off")" \
  "'osascript' '-l' 'JavaScript' '$HERE/mac/dialog.js' '--limit' '60' 'limits' 'Weekly limit rule reached' 'Used:' '81 % of the week  ·  resets Tue 08:00' 'Rule:' 'from Fri 20:00, stop at 80 %' 'Allow until the reset — no more asking this week' 'Stop — turn this rule off'"
check "  the rules box: in a private file, its path given, never its text" \
  "$(CH_DIALOG=osascript CH_HERE="$HERE" CH_DRY=1 ch_choose_limit "Weekly limit rule reached" "Used:" "81 %" "Rule:" "r" "c3" "c4" "$(printf 'CLAUDE_HTML_LIMIT_RULES=x\nrules')")" \
  "'osascript' '-l' 'JavaScript' '$HERE/mac/dialog.js' '--box' 'Rule:' '${TMPDIR:-/tmp}/chguard.XXXXXX/box' '--limit' '60' 'limits' 'Weekly limit rule reached' 'Used:' '81 %' 'Rule:' 'r' 'c3' 'c4'"
check "  on Linux, in the text, with the time limit" \
  "$(CH_DIALOG=zenity CH_DRY=1 ch_choose_limit h k1 v1 k2 v2 c3 c4 "the rules here" | grep -c -e '^the rules here$' -e '^Closes after 1 minute — counts as Cancel.' )" 2
check "kdialog: a radio list, Cancel on" \
  "$(CH_DIALOG=kdialog CH_DRY=1 ch_choose_limit "Weekly limit rule reached" "Used:" "81 %" "Rule:" "r" "c3" "c4" | grep -c "'cancel' 'Cancel — do not send' 'on' 'allow' 'Allow once — send this prompt only' 'off' 'until' 'c3' 'off' 'stop' 'c4' 'off'")" 1
check "xmessage: four buttons, Cancel the default" \
  "$(CH_DIALOG=xmessage CH_DRY=1 ch_choose_limit h k1 v1 k2 v2 c3 c4 | grep -c "'-buttons' 'Cancel:1,Allow once:2,Until the reset:3,Stop:4' '-default' 'Cancel'")" 1
if [ "$HAVE_OSASCRIPT" = true ]; then
  # A picture, and the window closes at once: nothing waits on anyone, and
  # --offscreen: nobody sees it.
  osascript -l JavaScript "$HERE/mac/dialog.js" --offscreen --limit 8 --snap "$T/stop.png" limits "Weekly limit rule reached" "Used:" "81 % of the week" "Rule:" "from Fri 20:00, stop at 80 %" c3 c4 >/dev/null 2>&1
  osascript -l JavaScript "$HERE/mac/dialog.js" --offscreen --limit 8 --snap "$T/confirm.png" confirm "Change claude-html limits?" "Asked by the Token usage page." "$(printf 'Stop rules:\tfrom Fri 20:00, stop at 80 %%')" >/dev/null 2>&1
  check "macOS: both windows draw" "$(head -c 4 "$T/stop.png" | od -c | head -1 | grep -c 'P   N   G') $(head -c 4 "$T/confirm.png" | od -c | head -1 | grep -c 'P   N   G')" "1 1"
fi

# The Mac window's boxes, through a stand-in osascript on a simulated Mac:
# the rules (or the budget) as the conf holds them, and for the
# confirmation the very lines Apply writes; each in a private file, its
# path the only argument, the file and its folder gone once it closes.
mkdir -p "$T/mac" "$T/mtmp"
cat > "$T/mac/osascript" <<'STUB'
#!/bin/bash
case "$*" in *dialog.js*) ;; *) exit 1 ;; esac
printf '%s\n' "$@" > "$STUB_REC.argv"
while [ $# -gt 0 ]; do
  case "$1" in
    --box|--pre) echo "$3" > "$STUB_REC.file"; ls -ld "${3%/*}" "$3" | cut -c1-10 | tr '\n' ' ' > "$STUB_REC.modes"
                 cat "$3" > "$STUB_REC.content"; rm -f "$3"; shift 3 ;;
    *) shift ;;
  esac
done
echo "$STUB_ANSWER"
STUB
printf '#!/bin/sh\necho Aqua\n' > "$T/mac/launchctl"; chmod +x "$T/mac/osascript" "$T/mac/launchctl"
macdlg() {   # answer prompt
  note "$2" | env -i CLAUDE_HTML_NO_SCREEN= PATH="$T/mac:$T/stub:$PATH" HOME="$H" TZ="$TZ" CLAUDE_HTML_CONF="$CONFF" CLAUDE_HTML_TEST_NOW="$NOW" \
    CLAUDE_HTML_REDACT_FILE="$T/none" CLAUDE_HTML_UNAME=Darwin TMPDIR="$T/mtmp" STUB_REC="$T/mrec" STUB_ANSWER="$1" \
    CLAUDE_HTML_GUARD_TEST_LIMIT=120 /bin/bash "$HERE/guard.sh" prompt
}
conf "$RULES"; fig "$NOW" 81; rm -f "$MARKS" "$T"/mrec.*; rm -rf "$H/.claude/.claude-html-guard"
check "Mac stop window, Cancel: dropped" "$(macdlg cancel "fix the bug" | reason)" "block: Dropped. Nothing was sent."
check "  the arrow on Rule: opens every rule, the one reached marked, as the conf holds them" \
  "$(cat "$T/mrec.content")" 'CLAUDE_HTML_LIMIT_RULES="fri 20:00 80% · sat 00:00 90%"
in ~/.claude/claude-html.conf

  1  from Fri 20:00, stop at 80 %   ← reached
  2  from Sat 00:00, stop at 90 %

claude-html --limits remove 1   takes this rule out'
check "  given by its path, in a private file and folder, both gone after" \
  "$(grep -cx -- '--box' "$T/mrec.argv") $(grep -cx 'Rule:' "$T/mrec.argv") $(cat "$T/mrec.modes")$([ -e "$(dirname "$(cat "$T/mrec.file")")" ] && echo left || echo gone) $(ls -A "$T/mtmp" | wc -l | tr -d ' ')" \
  "1 2 drwx------ -rw------- gone 0"
check "  and its countdown is the test's limit" "$(grep -A1 -x -- '--limit' "$T/mrec.argv" | tail -1)" 120
conf "$RULES"

# The budget, for API use: stopped at 100 %, not before, not on a plan.
conf 'CLAUDE_HTML_BUDGET="50 week"' 'CLAUDE_HTML_WEEK_RESET="tue 07:00 UTC"'
rm -f "$STATE" "$MARKS" "$H/.claude/.claude-html-guard/limits-sess-1"
printf 'start=%s\nend=%s\nmicro=49000000\nids=\n' $((R - 604800)) "$R" > "$SPEND"
printf 'cost=0.99\nsession=sess-1\n' > "$STATE"
check "budget: \$49.99 of \$50, the prompt goes" "$(words "fix the bug" | reason)" "(passed)"
printf 'cost=1.00\nsession=sess-1\n' > "$STATE"
check "  \$50.00: stopped" "$(words "fix the bug" | reason)" \
  "block: ⚠ claude-html: your prompt has been interrupted — API budget reached (\$50.00 of \$50 this week, resets Tue 08:00)."
: > "$T/stub.args"
check "  in the window: Weekly budget reached, spent and budget" \
  "$(dlg "Allow until" "fix the bug" | reason) $(grep -cx 'Weekly budget reached' "$T/stub.args") $(grep -cx 'Spent:  $50.00 of $50 this week  ·  resets Tue 08:00' "$T/stub.args") $(grep -cx 'Budget:  $50 per week, for API use' "$T/stub.args") $(grep -cx 'Stop — turn the budget off' "$T/stub.args")" \
  "(passed) 1 1 1 1"
check "  until the period ends" "$(grep -c "^ballow=$R$" "$MARKS")" 1
rm -f "$MARKS"
check "  Stop: the budget off" "$(dlg Stop "fix the bug" | reason) $(grep -c '^CLAUDE_HTML_BUDGET="off"$' "$CONFF")" "(passed) 1"
conf 'CLAUDE_HTML_BUDGET="50 week"' 'CLAUDE_HTML_WEEK_RESET="tue 07:00 UTC"'
printf 'cost=9\nsession=sess-1\nplan_seen=%s\n' $((NOW - 86400)) > "$STATE"
check "  on a plan (its figures seen this week): the budget stops nothing" "$(words "fix the bug" | reason)" "(passed)"

# ── announcements, in the Stop hook ──────────────────────────────────
echo "announcements"
stophook() {   # now [env…]
  local n="$1"; shift
  printf '{"session_id":"sess-1","hook_event_name":"Stop","transcript_path":"%s/none.jsonl"}' "$T" |
    (cd "$T" && env -i CLAUDE_HTML_NO_SCREEN= PATH="$T/stub:$PATH" HOME="$H" TZ="$TZ" CLAUDE_HTML_CONF="$CONFF" CLAUDE_HTML_TEST_NOW="$n" \
      CLAUDE_HTML_UPDATE_CHECK=off CLAUDE_HTML_NO_REGISTER=1 "$@" /bin/bash "$HERE/save-conversation.sh" --background)
}
msg() { node -e 'var s=require("fs").readFileSync(0,"utf8").trim(); console.log(s ? JSON.parse(s).systemMessage : "(nothing)")'; }
conf "$RULES"; rm -f "$MARKS"
fig $((FRI - 2 * 3600)) 77
check "a rule starting within hours, the week near it: one line" "$(stophook $((FRI - 2 * 3600)) | msg)" \
  "⚠ claude-html · your stop rule starts Fri 20:00 at 80 % · week now 77 %"
check "  once" "$(stophook $((FRI - 3600)) | msg)" "(nothing)"
fig $((FRI + 60)) 81
check "  and once when it starts" "$(stophook $((FRI + 60)) | msg)" \
  "⚠ claude-html · your stop rule is in force since Fri 20:00 at 80 % · week now 81 %"
check "  then nothing" "$(stophook $((FRI + 120)) | msg)" "(nothing)"
fig $((FRI + 7 * 86400 - 3600)) 78; sed -i.b "s/^week_reset=.*/week_reset=$((R + 604800))/" "$STATE"
check "  and again the next week" "$(stophook $((FRI + 7 * 86400 - 3600)) | msg)" \
  "⚠ claude-html · your stop rule starts Fri 20:00 at 80 % · week now 78 %"
rm -f "$MARKS"; fig $((FRI - 30 * 3600)) 79
check "a rule a day and more away: nothing yet" "$(stophook $((FRI - 30 * 3600)) | msg)" "(nothing)"
fig $((FRI - 3600)) 60
check "the week far below it: nothing" "$(stophook $((FRI - 3600)) | msg)" "(nothing)"
conf; fig "$NOW" 99
check "no plan-percentage warning, ever, at 99 %" "$(stophook "$NOW" | msg)" "(nothing)"
conf 'CLAUDE_HTML_LIMIT_RULES="sun 23:00 99%"'; fig "$NOW" 96
check "  nor with a rule far off" "$(stophook "$NOW" | msg)" "(nothing)"
conf 'CLAUDE_HTML_BUDGET="50 week"' 'CLAUDE_HTML_WEEK_RESET="tue 07:00 UTC"'; rm -f "$STATE" "$MARKS"
printf 'start=%s\nend=%s\nmicro=40000000\nids=\n' $((R - 604800)) "$R" > "$SPEND"
check "API budget at 80 %: one line" "$(stophook "$NOW" | msg)" "⚠ claude-html · API budget at 80 % · \$40.00 of \$50 this week"
check "  once" "$(stophook "$NOW" | msg)" "(nothing)"
printf 'start=%s\nend=%s\nmicro=47600000\nids=\n' $((R - 604800)) "$R" > "$SPEND"
check "  at 95 %: one more" "$(stophook "$NOW" | msg)" "⚠ claude-html · API budget at 95 % · \$47.60 of \$50 this week"
check "  once" "$(stophook "$NOW" | msg)" "(nothing)"
rm -f "$MARKS"
check "  straight to 95: the 95 line alone" "$(stophook "$NOW" | msg) | $(stophook "$NOW" | msg)" "⚠ claude-html · API budget at 95 % · \$47.60 of \$50 this week | (nothing)"
check "the Stop hook never started node or osascript for them" "$(started)" 0
# The banner, when asked for: osascript on a Mac, notify-send on Linux,
# none over ssh, headless or under WSL.
printf '#!/bin/sh\nprintf "%%s|" "$0" "$@" >> "%s/banner"; echo >> "%s/banner"\n' "$T" "$T" > "$T/stub/notify-send"; chmod +x "$T/stub/notify-send"
rm -f "$T/stub/osascript"; cp "$T/stub/notify-send" "$T/stub/osascript"
# The banner goes in the background: waited for, up to five seconds, and
# a second more for one that should not come.
banner() {
  local i=0
  rm -f "$MARKS" "$T/banner"; stophook "$NOW" CLAUDE_HTML_LIMIT_NOTIFY=on "$@" >/dev/null
  while [ ! -s "$T/banner" ] && [ $i -lt 25 ]; do sleep 0.2; i=$((i + 1)); done
  sed "s|$T/stub/||g" "$T/banner" 2>/dev/null
}
banner_none() { rm -f "$MARKS" "$T/banner"; stophook "$NOW" "$@" >/dev/null; sleep 1; cat "$T/banner" 2>/dev/null; }
check "banner on a Mac: osascript, the text an argument, never code" "$(banner CLAUDE_HTML_UNAME=Darwin)" \
  "osascript|-e|on run argv|-e|display notification (item 1 of argv) with title \"claude-html\"|-e|end run|API budget at 95 % · \$47.60 of \$50 this week|"
check "  on Linux: notify-send" "$(banner CLAUDE_HTML_UNAME=Linux DISPLAY=:0)" "notify-send|-a|claude-html|claude-html|API budget at 95 % · \$47.60 of \$50 this week|"
check "  none over ssh, headless or under WSL" \
  "$(banner_none CLAUDE_HTML_LIMIT_NOTIFY=on CLAUDE_HTML_UNAME=Linux DISPLAY=:0 SSH_CONNECTION=x)$(banner_none CLAUDE_HTML_LIMIT_NOTIFY=on CLAUDE_HTML_UNAME=Linux)$(banner_none CLAUDE_HTML_LIMIT_NOTIFY=on CLAUDE_HTML_UNAME=Linux DISPLAY=:0 WSL_DISTRO_NAME=Ubuntu)" ""
check "  and off by default" "$(banner_none CLAUDE_HTML_UNAME=Darwin)" ""
rm -f "$T/stub/notify-send"; for s in osascript; do printf '#!/bin/sh\necho "%s $*" >> "%s/started"\nexit 0\n' "$s" "$T" > "$T/stub/$s"; chmod +x "$T/stub/$s"; done; rm -f "$T/started"

# ── the command ──────────────────────────────────────────────────────
echo "command"
# The command, its words and, among them, VAR=value for its environment.
# Always on a Linux with no display unless told otherwise, and with a short
# dialog limit: even a broken tree can never put a real window on the
# screen of whoever runs the suite.
cli() {
  local e=() a=() x
  for x in "$@"; do if [[ "$x" =~ ^[A-Z_]+= ]]; then e+=("$x"); else a+=("$x"); fi; done
  env -i CLAUDE_HTML_NO_SCREEN="${CLAUDE_HTML_NO_SCREEN:-}" PATH="$PATH" HOME="$H" TZ="$TZ" CLAUDE_HTML_CONF="$CONFF" CLAUDE_HTML_TEST_NOW="$NOW" CLAUDE_HTML_NO_REGISTER=1 \
    CLAUDE_HTML_UPDATE_CHECK=off CLAUDE_HTML_UNAME=Linux CLAUDE_HTML_GUARD_TEST_LIMIT=2 \
    ${e[@]+"${e[@]}"} /bin/bash "$HERE/claude-html" ${a[@]+"${a[@]}"} 2>&1
}
conf; rm -f "$STATE" "$MARKS" "$SPEND"
check "add: the rule, numbered" "$(cli --limits add "fri 20:00 80%" | head -1)" "Added rule 1: from Fri 20:00, stop at 80 %."
check "  written as the conf holds it" "$(grep '^CLAUDE_HTML_LIMIT_RULES=' "$CONFF")" 'CLAUDE_HTML_LIMIT_RULES="fri 20:00 80%"'
check "add a second, any case, %, no %" "$(cli --limits add "Saturday 0:00 90" | head -1)" "Added rule 2: from Sat 00:00, stop at 90 %."
check "  joined by ' · '" "$(grep '^CLAUDE_HTML_LIMIT_RULES=' "$CONFF")" 'CLAUDE_HTML_LIMIT_RULES="fri 20:00 80% · sat 00:00 90%"'
for bad in "fri 24:00 80%" "fri 20:60 80%" "fri 20:00 0%" "fri 20:00 101%" "frisbee 20:00 80%" "fri 20 80%" "20:00 fri 80%" "fri 20:00 80%; rm -rf ~" ""; do
  check "add refuses \"$bad\", changing nothing" "$(cli --limits add "$bad" >/dev/null; echo $?) $(grep -c 'sat 00:00 90%"$' "$CONFF")" "2 1"
done
check "add the same start twice: refused" "$(cli --limits add "fri 20:00 70%" | tr -d '\n'; echo " ${PIPESTATUS[0]}")" "rule 1 already starts Fri 20:00: claude-html --limits remove 1 first 1"
S="$(cli --limits)"
check "--limits: the rules, gentle, announced" \
  "$(printf '%s\n' "$S" | grep -c '^  Stop rules     1  from Fri 20:00, stop at 80 %   in force since Fri 20:00$') $(printf '%s\n' "$S" | grep -c '^                 2  from Sat 00:00, stop at 90 %   in force since Sat 00:00$') $(printf '%s\n' "$S" | grep -c 'gentle: asks on a new prompt')" "1 1 1"
check "  the calendar's week, said so" "$(printf '%s\n' "$S" | grep -c '^  Week           resets Mon 00:00 (23:00 UTC), calendar weeks: CLAUDE_HTML_WEEK_RESET sets yours')" 1
check "  no budget, the banner off, no figures yet" \
  "$(printf '%s\n' "$S" | grep -c '^  Budget         none') $(printf '%s\n' "$S" | grep -c '^  Notification   off') $(printf '%s\n' "$S" | grep -c '^  Now            no recent usage values')" "1 1 1"
fig "$NOW" 81.3
S="$(cli --limits)"
check "  with figures: the rule in force, the week, their source and age" \
  "$(printf '%s\n' "$S" | grep -c 'from Fri 20:00, stop at 80 %   in force since Fri 20:00') $(printf '%s\n' "$S" | grep -c '^                 week   81 %   resets Tue 08:00$') $(printf '%s\n' "$S" | grep -c "from Claude Code's status line (rate_limits), as of Sat 14:29 — just now")" "1 1 1"
check "  the week's reset, in UTC too" "$(printf '%s\n' "$S" | grep -c "^  Week           resets Tue 08:00 (07:00 UTC), from Claude Code's status line$")" 1
fig $((NOW - 7 * 3600)) 81.3
check "  old figures: said so" "$(cli --limits | grep -c 'as of Sat 07:29 — 7 h ago: no recent usage values, so nothing is stopped on them')" 1
check "remove 1: renumbered" "$(cli --limits remove 1)" "Removed rule 1 (from Fri 20:00, stop at 80 %). Rule 2 is now rule 1."
check "  the conf" "$(grep '^CLAUDE_HTML_LIMIT_RULES=' "$CONFF")" 'CLAUDE_HTML_LIMIT_RULES="sat 00:00 90%"'
check "remove 5: refused" "$(cli --limits remove 5 | tr -d '\n'; echo " ${PIPESTATUS[0]}")" "no rule 5: there are 1 (claude-html --limits lists them) 1"
check "remove x: usage, exit 2" "$(cli --limits remove x >/dev/null; echo $?)" 2
check "rules: all at once" "$(cli --limits rules "fri 20:00 80%, sat 00:00 90%")" "Stop rules: from Fri 20:00, stop at 80 %; from Sat 00:00, stop at 90 %."
check "rules with one bad: refused, nothing changed" "$(cli --limits rules "fri 20:00 80%, sat 25:00 90%" >/dev/null; echo $?) $(grep -c 'fri 20:00 80% · sat 00:00 90%' "$CONFF")" "2 1"
check "rules none" "$(cli --limits rules none) $(grep -c '^CLAUDE_HTML_LIMIT_RULES=""$' "$CONFF")" "No stop rules. 1"
check "budget week 50" "$(cli --limits budget week 50)" "Budget: \$50 per week, for API use (warnings at 80 % and 95 %)."
check "budget month 12.5" "$(cli --limits budget month 12.5) $(grep '^CLAUDE_HTML_BUDGET=' "$CONFF")" "Budget: \$12.50 per month, for API use (warnings at 80 % and 95 %). CLAUDE_HTML_BUDGET=\"12.50 month\""
check "budget warn 70 90" "$(cli --limits budget warn 70 90) $(grep '^CLAUDE_HTML_BUDGET_WARN=' "$CONFF")" "Budget warnings at 70 % and 90 %, for API use. CLAUDE_HTML_BUDGET_WARN=\"70 90\""
for bad in "warn 90 70" "warn 80" "week" "week 0" "week -5" "week 1.234" "year 50" "week 50 extra" "50 week"; do
  check "budget $bad: refused" "$(cli --limits budget $bad >/dev/null; echo $?)" 2
done
check "budget off" "$(cli --limits budget off) $(grep '^CLAUDE_HTML_BUDGET=' "$CONFF")" "Budget off. CLAUDE_HTML_BUDGET=\"off\""
check "notify on" "$(cli --limits notify on | grep -c '^Desktop banner on, for rule announcements and budget warnings.') $(grep '^CLAUDE_HTML_LIMIT_NOTIFY=' "$CONFF")" "1 CLAUDE_HTML_LIMIT_NOTIFY=\"on\""
check "notify maybe: refused" "$(cli --limits notify maybe >/dev/null; echo $?)" 2
check "off" "$(cli --limits off | grep -c '^Limits off: no stop, no announcement, no budget warning, no banner.') $(grep '^CLAUDE_HTML_LIMITS=' "$CONFF")" "1 CLAUDE_HTML_LIMITS=\"off\""
check "on" "$(cli --limits on) $(grep '^CLAUDE_HTML_LIMITS=' "$CONFF")" "Limits on. CLAUDE_HTML_LIMITS=\"on\""
check "anything else: usage, exit 2" "$(cli --limits frobnicate | head -1; cli --limits frobnicate >/dev/null; echo $?)" "claude-html --limits [status]
2"
check "--limits after another flag: refused" "$(cli --force --limits >/dev/null; echo $?)" 2
check "the rest of the conf as it was" "$(grep -c "^CLAUDE_HTML_ROOT=\"$T/root\"$" "$CONFF")" 1
check "--doctor has a limits line" "$(cli --doctor | grep -c '^  limits    status line not installed · 0 rule(s) · no budget · banner on · week 81 %, 5 h 10 % as of Sat 07:29 (7 h ago): no recent usage values$')" 1
check "an environment value wins over the conf" "$(cli --limits CLAUDE_HTML_LIMIT_RULES="mon 09:00 50%" | grep -c 'from Mon 09:00, stop at 50 %')" 1

# ── the link from the page ───────────────────────────────────────────
echo "link"
GOOD="v1/fri-2000-80.sat-0000-90/50-week/80-95/off
v1/none/none/80-95/on
v1/mon-0000-1/12.50-month/1-99/off
v1/sun-2359-100.mon-0100-5.tue-0200-10.wed-0300-20.thu-0400-30.fri-0500-40.sat-0600-50.sun-0700-60/999999.99-day/50-51/on"
BAD="v1/fri-2400-80/none/80-95/on
v1/fri-2060-80/none/80-95/on
v1/fri-2000-0/none/80-95/on
v1/fri-2000-101/none/80-95/on
v1/fri-2000-080/none/80-95/on
v1/Fri-2000-80/none/80-95/on
V1/fri-2000-80/none/80-95/on
v2/fri-2000-80/none/80-95/on
v1/fri-2000-80/none/80-95/on/
/v1/fri-2000-80/none/80-95/on
v1//none/80-95/on
v1/fri-2000-80..sat-0000-90/none/80-95/on
v1/fri-2000-80./none/80-95/on
v1/fri-2000-80/0.5-week/80-95/on
v1/fri-2000-80/050-week/80-95/on
v1/fri-2000-80/50-year/80-95/on
v1/fri-2000-80/50.123-week/80-95/on
v1/fri-2000-80/1000000-week/80-95/on
v1/fri-2000-80/none/80-100/on
v1/fri-2000-80/none/80/on
v1/fri-2000-80/none/80-95/yes
v1/fri-2000-80/none/80-95/on?x=1
v1/fri-2000-80/none/80-95/on#f
v1/fri-2000-80/none/80-95/on%0a
v1/fri-2000-80/none/80-95/on;id
v1/fri-2000-80/none/80-95/on \$(id)
v1/friday-2000-80/none/80-95/on
v1/sun-2359-100.mon-0100-5.tue-0200-10.wed-0300-20.thu-0400-30.fri-0500-40.sat-0600-50.sun-0700-60.mon-0800-70/none/80-95/on
v1/fri-2000-80/none/80-95/on
v1/fri-2000-80/none/80-95/on"
# The last two: a line break and a space after a good payload.
BAD="$(printf '%s\n' "$BAD" | sed '$d' | sed '$d')"
printf '%s\n' "$GOOD" > "$T/link.good"; printf '%s\n' "$BAD" > "$T/link.bad"
printf 'v1/fri-2000-80/none/80-95/on\nx' > "$T/link.nl"; printf 'v1/fri-2000-80/none/80-95/on ' > "$T/link.sp"
lok() { env -i CLAUDE_HTML_NO_SCREEN="${CLAUDE_HTML_NO_SCREEN:-}" PATH="$PATH" HOME="$H" /bin/bash -c '. "$0/lib/common.sh"; ch_lim_link_ok "$1" && echo ok || echo no' "$HERE" "$1"; }
n=0; while IFS= read -r g; do [ "$(lok "$g")" = ok ] && n=$((n + 1)); done < "$T/link.good"
check "the grammar takes the good ones (4)" "$n" 4
n=0; m=0; while IFS= read -r b; do m=$((m + 1)); [ "$(lok "$b")" = no ] && n=$((n + 1)); done < "$T/link.bad"
check "  and refuses every variant ($m)" "$n" "$m"
check "  a line break or a space after a good one too" "$(lok "$(cat "$T/link.nl")") $(lok "$(cat "$T/link.sp")")" "no no"
check "--limits-apply refuses what is not one, exit 2, nothing asked" \
  "$(cli --limits-apply "v1/fri-2000-80/none/80-95/on/" | tr -d '\n'; echo " ${PIPESTATUS[0]}")" "not a limits link 2"
check "  and a warning pair the wrong way round" "$(cli --limits-apply "v1/none/none/95-80/on" >/dev/null; echo $?)" 2
# Always asked, in this desktop's own window, Cancel the default.
conf "$RULES" 'CLAUDE_HTML_BUDGET="50 week"'
cp "$CONFF" "$T/conf.before"
D="$(cli --limits-apply "v1/fri-2000-80.sun-1200-95/20-day/70-90/on" CLAUDE_HTML_UNAME=Linux DISPLAY=:9 XDG_CURRENT_DESKTOP=GNOME CH_DRY=1 PATH="$T/stub:$PATH")"
check "the confirmation: zenity, a question, Cancel the default, Apply" \
  "$(printf '%s' "$D" | grep -c "^'zenity' '--question' '--no-markup' '--default-cancel' '--title=claude-html' '--ok-label=Apply' '--cancel-label=Cancel'")" 1
check "  listing every value, the new rule marked" \
  "$(printf '%s\n' "$D" | grep -c '^Stop rules:  from Fri 20:00, stop at 80 %$') $(printf '%s\n' "$D" | grep -c '^      from Sun 12:00, stop at 95 %   (new)$') $(printf '%s\n' "$D" | grep -c '^Budget:  \$20 per day, for API use$') $(printf '%s\n' "$D" | grep -c '^Budget warnings:  at 70 % and 90 %, for API use$') $(printf '%s\n' "$D" | grep -c '^Notification:  on$') $(printf '%s\n' "$D" | grep -c '^File:  ~/.claude/claude-html.conf')" \
  "1 1 1 1 1 1"
check "  and nothing written while it was only shown" "$(cmp -s "$CONFF" "$T/conf.before" && echo same)" same
rm -f "$T"/mrec.*
check "on a Mac: the window, Cancel; nothing changed" \
  "$(cli --limits-apply "v1/fri-2000-80.sun-1200-95/20-day/70-90/on" CLAUDE_HTML_UNAME=Darwin PATH="$T/mac:$T/stub:$PATH" TMPDIR="$T/mtmp" STUB_REC="$T/mrec" STUB_ANSWER=cancel CLAUDE_HTML_NO_SCREEN=) $(cmp -s "$CONFF" "$T/conf.before" && echo same)" \
  "Nothing was changed. same"
check "  the arrow on File: opens the very lines Apply writes" "$(cat "$T/mrec.content")" \
  'CLAUDE_HTML_LIMIT_RULES="fri 20:00 80% · sun 12:00 95%"
CLAUDE_HTML_BUDGET="20 day"
CLAUDE_HTML_BUDGET_WARN="70 90"
CLAUDE_HTML_LIMIT_NOTIFY="on"'
check "  by a private file, gone after; the window counts down the same limit" \
  "$(grep -c -x 'File:' "$T/mrec.argv") $(cat "$T/mrec.modes")$(ls -A "$T/mtmp" | wc -l | tr -d ' ') $(grep -A1 -x -- '--limit' "$T/mrec.argv" | tail -1)" \
  "1 drwx------ -rw------- 0 2"
# A folder with the stand-in zenity alone: the rebuild after Apply needs
# the real engines.
mkdir -p "$T/zen"; cp "$T/stub/zenity" "$T/zen/"
# The window is a stand-in's: CLAUDE_HTML_NO_SCREEN off for it.
apply() { cli --limits-apply "$1" CLAUDE_HTML_UNAME=Linux DISPLAY=:9 XDG_CURRENT_DESKTOP=GNOME PATH="$T/zen:$PATH" STUB_ARGS="$T/stub.args" STUB_ANSWER="$2" CLAUDE_HTML_GUARD_TEST_LIMIT=120 CLAUDE_HTML_NO_SCREEN= "${@:3}"; }
check "Cancel: nothing changed" "$(apply "v1/none/none/80-95/off" no) $(cmp -s "$CONFF" "$T/conf.before" && echo same)" "Nothing was changed. same"
check "  the window closed for want of an answer: the same" \
  "$(apply "v1/none/none/80-95/off" sleep CLAUDE_HTML_GUARD_TEST_LIMIT=1) $(cmp -s "$CONFF" "$T/conf.before" && echo same)" "Nothing was changed. same"
mkdir -p "$H/.claude/.claude-html-limits-ask"
check "one window at a time: a second link while one asks, exit 3" "$(apply "v1/none/none/80-95/off" yes >/dev/null; echo $?) $(cmp -s "$CONFF" "$T/conf.before" && echo same)" "3 same"
rmdir "$H/.claude/.claude-html-limits-ask"
check "no window to ask in: refused, the commands said instead" \
  "$(cli --limits-apply "v1/none/none/80-95/off" CLAUDE_HTML_UNAME=Linux PATH="$T/stub:$PATH" | head -2 | tail -1; cmp -s "$CONFF" "$T/conf.before" && echo same)" \
  "claude-html --limits rules \"none\"
same"
for ENG in $([ "$HAVE_OSASCRIPT" = true ] && echo osascript) node; do
  rm -rf "$T/out"; conf "$RULES" 'CLAUDE_HTML_BUDGET="50 week"'; fig "$NOW" 81.3
  R2="$(apply "v1/fri-2000-80.sun-1200-95/20-day/70-90/on" yes CLAUDE_HTML_ENGINE=$ENG)"
  check "$ENG: Apply: written" "$R2 | $(grep -E '^CLAUDE_HTML_(LIMIT_RULES|BUDGET|BUDGET_WARN|LIMIT_NOTIFY)=' "$CONFF" | tr '\n' ' ')" \
    "Applied. | CLAUDE_HTML_LIMIT_RULES=\"fri 20:00 80% · sun 12:00 95%\" CLAUDE_HTML_BUDGET=\"20 day\" CLAUDE_HTML_BUDGET_WARN=\"70 90\" CLAUDE_HTML_LIMIT_NOTIFY=\"on\" "
  check "$ENG:   and the pages rebuilt with it" \
    "$(node -e 'var h=require("fs").readFileSync(process.argv[1],"utf8"); var d=JSON.parse(/id="usage-data">([\s\S]*?)<\/script>/.exec(h)[1]); console.log(d.limits.rules.map(function(r){return r.day+r.time+r.pct}).join(",")+" "+d.limits.budget.amount+"/"+d.limits.budget.period+" "+d.limits.plan.week.pct)' "$T/out/usage.html" 2>&1)" \
    "fri20:0080,sun12:0095 20/day 81.3"
done

# ── what the budget counts ───────────────────────────────────────────
echo "spend"
# Per session: a recorded cost, where Claude Code wrote one, else the
# price table's for its tokens, never both; in the hours of the period.
WS="$(node -e '
var L = new Function(require("fs").readFileSync(process.argv[1] + "/build/limits.js", "utf8") + "\nreturn claudeHtmlLimits();")();
var PR = { total: function (u, o) { var c = 0, n = 0; Object.keys(u).forEach(function (h) {
  var t = Date.parse(h + ":00:00Z"); if (t < o.since || t >= o.until) return;
  Object.keys(u[h]).forEach(function (m) { var k = u[h][m]; c += k[1] * 10; n += k[1]; }); });
  return { calc: c, priced: n, unpriced: 0 }; } };
function cell(out, cost) { var c = [0, out, 0, 0, 1, 0, 0]; if (cost !== undefined) c.push(cost); return c; }
var start = Date.UTC(2026, 10, 17, 7) / 1000, end = start + 604800;
var S = [
  ["rec", { "2026-11-18T09": { m: cell(1000) }, "2026-11-18T12": { m: cell(500, 3000000) } }],
  ["calc", { "2026-11-19T09": { m: cell(200) }, "2026-11-10T09": { m: cell(999) } }],
  ["later", { "2026-11-23T09": { m: cell(50) }, "2026-11-25T09": { m: cell(0, 700000) } }],
  ["before", { "2026-11-16T09": { m: cell(0, 400000) } }]
];
function show(r) { return r.micro + " " + r.unpriced + " " + r.counted.join(","); }
console.log(show(L.weekSpend(S, start, end, PR)));
console.log(show(L.weekSpend(S, start, end, null)));' "$HERE")"
check "recorded for a session that has it, calculated for one that has none, never both" \
  "$(printf '%s\n' "$WS" | sed -n 1p)" "3002000 0 rec,calc"
check "  without a price file, what has no recorded cost is said to be left out" \
  "$(printf '%s\n' "$WS" | sed -n 2p)" "3000000 200 rec"

# ── the pages ─────────────────────────────────────────────────────────
echo "pages"
# The page's own link is one the grammar takes, and applying it writes
# what copy command would.
PJ="$(node -e '
global.CH = require(process.argv[1] + "/viewer/viewer.js"); var P = require(process.argv[1] + "/viewer/plan.js");
var st = { rules: [{ day: "fri", time: "20:00", pct: "80" }, { day: "sat", time: "00:00", pct: "90" }], amount: "12.5", period: "month", w1: "80", w2: "95", notify: true };
var was = JSON.parse(JSON.stringify(st)); was.amount = "50"; was.period = "week";
console.log(P.linkFor(st)); console.log(P.commandsFor(st, was).replace(/\n/g, " | "));
console.log(P.commandsFor(st, st).split("\n").length);' "$HERE")"
LINK="$(printf '%s\n' "$PJ" | sed -n 1p)"
check "the page's link" "$LINK" "claude-html://limits/v1/fri-2000-80.sat-0000-90/12.50-month/80-95/on"
check "  is one the grammar takes" "$(lok "${LINK#claude-html://limits/}")" ok
check "  copy command: what changed" "$(printf '%s\n' "$PJ" | sed -n 2p)" "claude-html --limits budget month 12.50"
check "  or, nothing changed, every line" "$(printf '%s\n' "$PJ" | sed -n 3p)" 4
# The line itself, as the build would embed it.
pl() { node -e '
global.CH = require(process.argv[1] + "/viewer/viewer.js"); var P = require(process.argv[1] + "/viewer/plan.js");
var L = JSON.parse(process.argv[2]), s = process.argv[3] ? JSON.parse(process.argv[3]) : null;
console.log(P.line(L, s).replace(/<[^>]*>/g, "").replace(/\s+/g, " "));
console.log((P.line(L, s).match(/class="(ok|warn|bad)"/g) || []).join(" "));' "$HERE" "$1" "${2:-}"; }
LJ="{\"on\":true,\"rules\":[{\"day\":\"fri\",\"time\":\"20:00\",\"pct\":80,\"start\":$FRI},{\"day\":\"sat\",\"time\":\"00:00\",\"pct\":90,\"start\":$SAT0}],\"budget\":null,\"warn\":[80,95],\"notify\":false,\"week\":{\"start\":$((R - 604800)),\"reset\":$R,\"source\":\"rate_limits\"},\"plan\":{\"five\":{\"pct\":62,\"reset\":$FIVE},\"week\":{\"pct\":81.3,\"reset\":$R},\"asof\":$NOW,\"fresh\":true},\"onPlan\":true,\"now\":$NOW}"
check "plan line, Saturday: both windows, the rule in force, as of" "$(pl "$LJ" | head -1)" \
  "plan · 5 h: 62 % · resets 16:30 · week: from Fri 20:00 81 % · resets Tue 08:00 · stop at 80 % from Fri 20:00 · as of Sat 14:29"
check "  green, then amber" "$(pl "$LJ" | tail -1)" 'class="ok" class="ok" class="warn" class="warn"'
check "  the rule reached: its words amber" "$(node -e 'global.CH=require(process.argv[1]+"/viewer/viewer.js");console.log(/pstop warn/.test(require(process.argv[1]+"/viewer/plan.js").line(JSON.parse(process.argv[2]))))' "$HERE" "$LJ")" true
LW="$(printf '%s' "$LJ" | sed "s/\"pct\":81.3/\"pct\":62/; s/\"now\":$NOW/\"now\":$((FRI - 2 * 86400))/; s/\"asof\":$NOW/\"asof\":$((FRI - 2 * 86400))/")"
check "Wednesday: the next rule's mark, normal colour" "$(pl "$LW" | head -1 | sed 's/resets [^·]* · week/resets X · week/')" \
  "plan · 5 h: 62 % · resets X · week: from Fri 20:00 62 % · resets Tue 08:00 · stop at 80 % from Fri 20:00 · as of Wed 20:00"
LS="$(printf '%s' "$LJ" | sed 's/"fresh":true/"fresh":false/')"
check "old figures: said on the line" "$(pl "$LS" | head -1 | grep -o 'as of .*')" "as of Sat 14:29 · no recent values"
LA="{\"on\":true,\"rules\":[],\"budget\":{\"cents\":5000,\"amount\":\"50\",\"period\":\"week\",\"start\":$((R - 604800)),\"end\":$R},\"warn\":[80,95],\"notify\":false,\"week\":{\"start\":$((R - 604800)),\"reset\":$R,\"source\":\"conf\"},\"plan\":null,\"onPlan\":false,\"now\":$NOW}"
check "API: the budget line" "$(pl "$LA" '{"micro":38200000,"unpriced":0}' | head -1)" \
  "budget · this week \$38.20 of \$50 · 76 % · resets Tue 08:00 · as of 14:29"
check "nothing set, nothing seen: no line" "$(node -e 'global.CH=require(process.argv[1]+"/viewer/viewer.js");console.log(JSON.stringify(require(process.argv[1]+"/viewer/plan.js").line(null)))' "$HERE")" '""'
check "the templates have a place for it" \
  "$(grep -c 'id="plan"' "$HERE/viewer/usage.html") $(grep -c 'id="limits"' "$HERE/viewer/usage.html") $(grep -c 'id="plan"' "$HERE/viewer/index.html") $(grep -c '{{plan}}' "$HERE/viewer/usage.html" "$HERE/viewer/index.html" | grep -c ':1')" "1 1 1 2"
# A build with nothing set writes pages exactly as before: no limits in them.
for ENG in $([ "$HAVE_OSASCRIPT" = true ] && echo osascript) node; do
  rm -rf "$T/out" "$STATE" "$SPEND"; conf
  env -i CLAUDE_HTML_NO_SCREEN="${CLAUDE_HTML_NO_SCREEN:-}" PATH="$PATH" HOME="$H" CLAUDE_HTML_CONF="$CONFF" CLAUDE_HTML_ENGINE=$ENG /bin/bash -c \
    'HERE="$0"; . "$HERE/lib/conf.sh"; . "$HERE/lib/platform.sh"; ch_pick_engine; ch_js "$HERE/build/convert.js" "$(ch_js_opts "$HERE" :cache false)"' "$HERE" >/dev/null 2>&1
  check "$ENG: nothing set: no limits in the pages" "$(grep -c '"limits":' "$T/out/usage.html" "$T/out/index.html" | grep -c ':0')" 2
done

echo
verdict
