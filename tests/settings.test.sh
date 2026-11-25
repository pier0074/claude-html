#!/bin/bash
# Every user setting, from lib/settings.tsv: claude-html --config, the
# claude-html://settings link from the Settings page and its confirmation,
# the write and the rebuild, forgetting the guard's safe values, the page
# itself under both engines, and the page defaults a browser starts with.
#
# Everything runs in a home of its own. The confirmation window is a
# stand-in zenity on a simulated Linux desktop, or a stand-in osascript on a
# simulated Mac: no window is ever shown.
#
#   bash tests/settings.test.sh
set -u

. "$(dirname "$0")/lib.sh"

HERE="$(cd "$(dirname "$0")/.." && pwd)"
pass=0; fail=0
check() {
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); printf '  ok    %s\n' "$1"
  else fail=$((fail + 1)); printf '  FAIL  %s\n        expected: %s\n        got:      %s\n' "$1" "$3" "$2"; fi
}
T="$(cd "$(tmpdir chsettings)" && pwd -P)"
trap 'rm -rf "$T"' EXIT
H="$T/home"; mkdir -p "$H/.claude" "$T/stub" "$T/root/proj" "$T/mac" "$T/mtmp"
CONFF="$H/.claude/claude-html.conf"; LIST="$H/.claude/claude-html.redact"
conf() { { printf 'CLAUDE_HTML_ROOT="%s"\nCLAUDE_HTML_OUT="%s"\n' "$T/root" "$T/out"; for l in "$@"; do printf '%s\n' "$l"; done; } > "$CONFF"; }
SECRET="Own-List-Entry-7f3a9c-never-shown"
list() {
  printf '# my list\n%s\n/acme_[0-9a-f]{8}/\nsafe:0123456789abcdef:0123456789abcdef0123456789abcdef   # github, 2026-11-19\n  safe:fedcba9876543210:fedcba9876543210fedcba9876543210   # jwt, 2026-11-20\n' "$SECRET" > "$LIST"
}
# One conversation, so the pages have something in them.
SID=aaaaaaaa-1111-4111-8111-000000000001
mkdir -p "$H/.claude/projects/-p"
printf '{"type":"user","sessionId":"%s","cwd":"%s","timestamp":"2026-11-01T10:00:00Z","message":{"role":"user","content":"fix the build"}}\n' \
  "$SID" "$T/root/proj" > "$H/.claude/projects/-p/$SID.jsonl"

# The command, in a home of its own and nothing of this shell's. A build
# that names no session opens the index, by /usr/bin/open on a Mac: noted
# in this suite's own file instead (CLAUDE_HTML_NO_SCREEN), and checked.
cli() {
  local e=() a=() x
  for x in "$@"; do if [[ "$x" =~ ^[A-Z_]+= ]]; then e+=("$x"); else a+=("$x"); fi; done
  env -i CLAUDE_HTML_NO_SCREEN="$T/shown" PATH="$PATH" HOME="$H" CLAUDE_HTML_CONF="$CONFF" CLAUDE_HTML_NO_REGISTER=1 \
    CLAUDE_HTML_REDACT_FILE="$LIST" ${e[@]+"${e[@]}"} /bin/bash "$HERE/claude-html" ${a[@]+"${a[@]}"} 2>&1
}
# claude-html --config <words…> [-- <environment…>]
cfg() {
  local a=()
  while [ $# -gt 0 ] && [ "$1" != -- ]; do a+=("$1"); shift; done
  [ $# -gt 0 ] && shift
  env -i CLAUDE_HTML_NO_SCREEN="$T/shown" PATH="$PATH" HOME="$H" CLAUDE_HTML_CONF="$CONFF" CLAUDE_HTML_NO_REGISTER=1 \
    CLAUDE_HTML_REDACT_FILE="$LIST" "$@" /bin/bash "$HERE/claude-html" --config ${a[@]+"${a[@]}"} 2>&1
}
# The shell's own pieces, as the command loads them.
sh_() { local c="$1"; shift; env -i CLAUDE_HTML_NO_SCREEN="$T/shown" PATH="$PATH" HOME="$H" CLAUDE_HTML_CONF="$CONFF" CLAUDE_HTML_REDACT_FILE="$LIST" /bin/bash -c \
  'set +u; HERE="$0"; . "$HERE/lib/conf.sh"; . "$HERE/lib/platform.sh"; . "$HERE/lib/limits.sh"; . "$HERE/lib/settings.sh"; '"$c" "$HERE" "$@"; }
data() {   # page field-expression — what the Settings page carries
  node -e 'var h=require("fs").readFileSync(process.argv[1],"utf8");
    var d=JSON.parse(/id="settings-data">([\s\S]*?)<\/script>/.exec(h)[1]); console.log(eval(process.argv[2]))' "$1" "$2"
}

# ── the description ──────────────────────────────────────────────────
echo "description"
check "every line of the description has its nine fields" \
  "$(awk -F'\t' '/^(CLAUDE_HTML_|CH_)/ && NF != 9' "$HERE/lib/settings.tsv" | wc -l | tr -d ' ')" 0
check "  and the shell and the JavaScript read the same keys" \
  "$(sh_ 'ch_set_load; echo $CH_SET_LIST' | tr ' ' '\n' | sed '/^$/d' | tr '\n' ' ')" \
  "$(node -e 'var S=require(process.argv[1]+"/build/settings.js")(require("fs").readFileSync(process.argv[1]+"/lib/settings.tsv","utf8"));console.log(S.list.map(function(s){return s.key}).join(" ")+" ")' "$HERE")"

# ── claude-html --config ─────────────────────────────────────────────
echo "--config"
conf 'CLAUDE_HTML_GUARD="prompt"'; list
S="$(cli --config)"
check "show: every setting, a line each" \
  "$(printf '%s\n' "$S" | grep -cE '^    (CLAUDE_HTML_|CH_)')" "$(grep -cE '^(CLAUDE_HTML_|CH_)' "$HERE/lib/settings.tsv")"
check "  one from the conf: its value, conf, its default" \
  "$(printf '%s\n' "$S" | grep -E '^    CLAUDE_HTML_GUARD ' | tr -s ' ')" " CLAUDE_HTML_GUARD prompt · conf · default: on"
check "  one left at its default: the default" \
  "$(printf '%s\n' "$S" | grep -E '^    CLAUDE_HTML_GUARD_WAIT ' | tr -s ' ')" " CLAUDE_HTML_GUARD_WAIT 1m · default"
check "  one from the environment: said, and that the conf can do nothing" \
  "$(cli --config CLAUDE_HTML_GUARD_WAIT=2m | grep -A1 -E '^    CLAUDE_HTML_GUARD_WAIT ' | tr -s ' ')" \
  " CLAUDE_HTML_GUARD_WAIT 2m · environment · default: 1m
 set in the environment, which wins over the conf: a change there does nothing here while it is set"
cp "$CONFF" "$T/conf.before"
R="$(cfg set guard_wait=90s CLAUDE_HTML_WEEK_RESET="Tuesday 7 utc" GUARD=OFF ENGINE=auto)"; RC=$?
check "set: KEY with or without CLAUDE_HTML_, any case; exit 0" "$RC" 0
check "  written as the conf holds them, the week in its own words" \
  "$(grep -E '^CLAUDE_HTML_(GUARD|GUARD_WAIT|WEEK_RESET|ENGINE)=' "$CONFF" | LC_ALL=C sort | tr '\n' ' ')" \
  'CLAUDE_HTML_GUARD="off" CLAUDE_HTML_GUARD_WAIT="90s" CLAUDE_HTML_WEEK_RESET="tue 07:00 UTC" '
check "  an enum's default takes its line out (ENGINE=auto)" "$(printf '%s\n' "$R" | grep -c 'CLAUDE_HTML_ENGINE: its line is out of the conf')" 1
check "  and the pages are rebuilt with it" "$(data "$T/out/settings.html" 'd.values.CLAUDE_HTML_GUARD_WAIT.v+" "+d.values.CLAUDE_HTML_GUARD_WAIT.src')" "90s conf"
check "unset: back to the default, its line gone" \
  "$(cfg unset GUARD_WAIT >/dev/null; grep -c GUARD_WAIT "$CONFF") $(data "$T/out/settings.html" 'd.values.CLAUDE_HTML_GUARD_WAIT.src')" "0 default"
cp "$CONFF" "$T/conf.before"
R="$(cfg set GUARD=on GUARD_WAIT=10s PRICES=relative/p.tsv OUT=/x LIMIT_RULES="fri 25:00 80%" NOPE=1 BUDGET_WARN="95 80")"; RC=$?
check "one bad value of several: nothing written, exit 2" "$RC $(cmp -s "$CONFF" "$T/conf.before" && echo same)" "2 same"
check "  each bad one said, and why" \
  "$(printf '%s\n' "$R" | grep -c -e 'GUARD_WAIT=10s: out of range' -e 'PRICES=relative/p.tsv: a path is written from / or ~/' -e 'OUT=/x: set by ./install.sh --out DIR' -e 'LIMIT_RULES=fri 25:00 80%: not rules' -e 'NOPE: no such setting' -e 'BUDGET_WARN=95 80: two percentages')" 6
check "  the good one among them not written either" "$(grep -c '^CLAUDE_HTML_GUARD="on"' "$CONFF")" 0
check "an environment-only setting is refused" "$(cfg set CONF=/x; echo " $?")" \
  "not changed: CLAUDE_HTML_CONF=/x: read from the environment only, never from the conf
nothing was written
 2"
check "the limits' settings, by their own parsers, written in their own words" \
  "$(cfg set LIMIT_RULES="Friday 20:00 80, sat 0:00 90%" BUDGET='$12.5 / month' BUDGET_WARN="70,90" >/dev/null; grep -E '^CLAUDE_HTML_(LIMIT_RULES|BUDGET|BUDGET_WARN)=' "$CONFF" | LC_ALL=C sort | tr '\n' ' ')" \
  'CLAUDE_HTML_BUDGET="12.50 month" CLAUDE_HTML_BUDGET_WARN="70 90" CLAUDE_HTML_LIMIT_RULES="fri 20:00 80% · sat 00:00 90%" '
check "set to a value the environment overrides: said" \
  "$(cfg set GUARD_DIALOG=off -- CLAUDE_HTML_GUARD_DIALOG=on | grep -c 'but CLAUDE_HTML_GUARD_DIALOG is set in the environment, which wins over the conf: here it stays on')" 1
check "a path with ~ is written whole" "$(cfg set PRICES='~/prices.tsv' >/dev/null; grep '^CLAUDE_HTML_PRICES=' "$CONFF")" "CLAUDE_HTML_PRICES=\"$H/prices.tsv\""
check "  and a plain line in the conf reaches the build" \
  "$(data "$T/out/settings.html" 'd.prices.path')" "$H/prices.tsv"
cfg unset PRICES >/dev/null
check "--limits and --guard keep working, and the page follows them" \
  "$(cli --guard wait 2m >/dev/null; cli --limits notify on >/dev/null; cli >/dev/null; data "$T/out/settings.html" 'd.values.CLAUDE_HTML_GUARD_WAIT.v+" "+d.values.CLAUDE_HTML_LIMIT_NOTIFY.v')" "2m on"

# ── forgetting the safe values ───────────────────────────────────────
echo "forget-safe"
list; cp "$LIST" "$T/list.before"
R="$(cfg forget-safe)"
check "the safe: lines go, and nothing else" "$(diff "$T/list.before" "$LIST" | grep -c '^<') $(grep -c 'safe:' "$LIST") $(grep -cx "$SECRET" "$LIST") $(grep -c '^# my list$' "$LIST") $(grep -c '^/acme_' "$LIST")" "2 0 1 1 1"
check "  said without what the list says" "$(printf '%s\n' "$R" | grep -c 'forgot 2 safe value(s); your own entries in ~/.claude/claude-html.redact stay') $(printf '%s' "$R" | grep -c "$SECRET")" "1 0"

# ── the link's grammar ───────────────────────────────────────────────
echo "link"
lok() { env -i CLAUDE_HTML_NO_SCREEN="$T/shown" PATH="$PATH" HOME="$H" /bin/bash -c 'HERE="$0"; . "$HERE/lib/settings.sh"; ch_set_link_ok "$1" && echo ok || echo no' "$HERE" "$1"; }
n=0; m=0
for p in "v1/none/GUARD=off" "v1/0123456789abcdef/GUARD_WAIT=2m/ENGINE/forget-safe" \
         "v1/none/WEEK_RESET=tue%2007%3A00%20UTC" "v1/none/PRICES=%2FUsers%2Fme%2Fp%20q.tsv" "v1/none/EXPORT=~%2Fx.json"; do
  m=$((m + 1)); [ "$(lok "$p")" = ok ] && n=$((n + 1))
done
check "the grammar takes the good ones ($m)" "$n" "$m"
LONG="v1/none/PRICES=%2F$(printf 'a%.0s' $(seq 1 2100))"
n=0; m=0
for p in "" "v1" "v1/none" "v1/none/" "v2/none/GUARD=off" "V1/none/GUARD=off" "v1/NONE/GUARD=off" "v1/0123/GUARD=off" \
         "v1/none/GUARD=off/" "v1/none//GUARD=off" "v1/none/guard=off" "v1/none/GUARD=" "v1/none/GUARD=off;id" \
         "v1/none/GUARD=\$(id)" "v1/none/GUARD=%0aoff" "v1/none/PRICES=%2Fa%0Ab" "v1/none/PRICES=%2Fa%7Fb" "v1/none/PRICES=%2Fa%00" \
         "v1/none/GUARD=off?x=1" "v1/none/GUARD=off#f" "v1/none/GUARD=o'ff" 'v1/none/GUARD="off"' "v1/none/GUARD=off x" \
         "v1/none/PRICES=%2fx" "v1/none/GUARD=%zz" "$LONG" \
         "v1/none$(printf '/GUARD=off%.0s' $(seq 1 25))" "v1/none/GUARD=off
v1/none/GUARD=on"; do
  m=$((m + 1)); [ "$(lok "$p")" = no ] && n=$((n + 1)) || echo "        taken: $p" | cut -c1-120
done
check "  and refuses every variant ($m): case, quotes, \$(), line breaks, control characters, too long, too many" "$n" "$m"
# Past the grammar, each value is checked as --config set checks it. The
# simulated Linux desktop has its zenity, a stand-in, from here on: without
# it the dry runs would find whatever dialog this machine happens to have
# (XQuartz's xmessage on a Mac), or none, as on CI, and ask nothing.
cat > "$T/stub/zenity" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" >> "$STUB_ARGS"
case "$STUB_ANSWER" in sleep) sleep 30 ;; yes) exit 0 ;; *) exit 1 ;; esac
EOF
chmod +x "$T/stub/zenity"
conf; cp "$CONFF" "$T/conf.before"
apply_dry() { cli --settings-apply "$1" CLAUDE_HTML_UNAME=Linux DISPLAY=:9 XDG_CURRENT_DESKTOP=GNOME PATH="$T/stub:$PATH" CH_DRY=1 "${@:2}"; }
for p in "v1/none/NOPE=1" "v1/none/OUT=%2Ftmp" "v1/none/CONF=%2Ftmp" "v1/none/LIMIT_RULES=fri" "v1/none/GUARD=maybe" \
         "v1/none/PRICES=%2Ftmp%2F..%2Fetc%2Fpasswd" "v1/none/PRICES=..%2Fx" "v1/none/EXPORT=%2Fx%24(id)" "v1/none/EXPORT=%2Fx%22y" \
         "v1/none/EXPORT=%2Fx%60id%60" "v1/none/GUARD_WAIT=1h" "v1/none/WEEK_RESET=tue%2025%3A00" "v1/none/GUARD=off/GUARD=on" \
         "v1/none/forget-safe/forget-safe" "v1/none/CLAUDE_HTML_GUARD=off"; do
  R="$(apply_dry "$p")"; RC=$?
  check "refused, nothing asked or written: $p" "$RC $(printf '%s' "$R" | grep -c "^'zenity'") $(cmp -s "$CONFF" "$T/conf.before" && echo same)" "2 0 same"
done
check "  and the window says why" "$(apply_dry "v1/none/GUARD_WAIT=1h/PRICES=..%2Fx" | tr '\n' '|')" \
  "not a settings link, so nothing was changed:|CLAUDE_HTML_GUARD_WAIT=1h: not a wait: from 30 seconds to 60 minutes, written 45, 45s, 2m or 1m30s|CLAUDE_HTML_PRICES=../x: a path is written from / or ~/|"

# The page's own check and link are the shell's: the same answer for the
# same value, and a link the grammar takes, read back to the same values.
PAIRS='CLAUDE_HTML_GUARD	OFF
CLAUDE_HTML_GUARD	on
CLAUDE_HTML_GUARD	maybe
CLAUDE_HTML_ENGINE	auto
CLAUDE_HTML_ENGINE	node
CLAUDE_HTML_GUARD_WAIT	45
CLAUDE_HTML_GUARD_WAIT	1m30s
CLAUDE_HTML_GUARD_WAIT	1m90s
CLAUDE_HTML_GUARD_WAIT	29s
CLAUDE_HTML_GUARD_WAIT	60m
CLAUDE_HTML_GUARD_WAIT	61m
CLAUDE_HTML_GUARD_WAIT	1mm5s
CLAUDE_HTML_GUARD_WAIT	2 m
CLAUDE_HTML_GUARD_WAIT	000045
CLAUDE_HTML_WEEK_RESET	Tuesday 7 utc
CLAUDE_HTML_WEEK_RESET	thu 17
CLAUDE_HTML_WEEK_RESET	fri 24:00
CLAUDE_HTML_WEEK_RESET	frisbee 8
CLAUDE_HTML_WEEK_RESET	sat 9:60
CLAUDE_HTML_PRICES	/a b/p.tsv
CLAUDE_HTML_PRICES	~/p.tsv
CLAUDE_HTML_PRICES	p.tsv
CLAUDE_HTML_PRICES	/a/../p
CLAUDE_HTML_PRICES	/a/./p
CLAUDE_HTML_PRICES	/a/..b/p
CLAUDE_HTML_PRICES	/a$b
CLAUDE_HTML_EXPORT	/é/ü x.json
CLAUDE_HTML_OUT	/x
CLAUDE_HTML_CONF	/x
CLAUDE_HTML_VIEW_THEME	Dark
CLAUDE_HTML_VIEW_PRICES	today
CLAUDE_HTML_VIEW_SESSION	talk'
printf '%s\n' "$PAIRS" > "$T/pairs"
SHA="$(while IFS='	' read -r k v; do sh_ 'ch_set_load; if ch_set_check "$1" "$2"; then echo "ok ${_SU:+unset}$(ch_set_tilde "$_SV")"; else echo no; fi' "$k" "$v"; done < "$T/pairs")"
JSA="$(node -e '
  var fs=require("fs"), h=process.argv[1], CH=require(h+"/viewer/viewer.js");
  var S=require(h+"/build/settings.js")(fs.readFileSync(h+"/lib/settings.tsv","utf8"), CH.parseReset);
  fs.readFileSync(process.argv[2],"utf8").split("\n").filter(Boolean).forEach(function(l){
    var p=l.split("\t"), r=S.check(p[0],p[1]); console.log(r.ok ? "ok " + (r.unset ? "unset" : r.value) : "no"); });' "$HERE" "$T/pairs")"
check "the page's check answers as the shell's, value for value ($(printf '%s\n' "$PAIRS" | wc -l | tr -d ' '))" "$JSA" "$SHA"
LINK="$(node -e '
  var fs=require("fs"), h=process.argv[1], CH=require(h+"/viewer/viewer.js");
  var S=require(h+"/build/settings.js")(fs.readFileSync(h+"/lib/settings.tsv","utf8"), CH.parseReset);
  console.log(S.linkFor("0123456789abcdef", [{key:"CLAUDE_HTML_EXPORT",op:"set",value:"/é/it'"'"'s (a) x*!.json"},
    {key:"CLAUDE_HTML_WEEK_RESET",op:"set",value:"tue 07:00 UTC"},{key:"CLAUDE_HTML_ENGINE",op:"unset"},{op:"forget"}]));
  console.log(S.commandFor([{key:"CLAUDE_HTML_EXPORT",op:"set",value:"/é/it'"'"'s x.json"},{key:"CLAUDE_HTML_GUARD",op:"set",value:"off"},
    {key:"CLAUDE_HTML_ENGINE",op:"unset"},{op:"forget"}]));
  var many=[]; for (var i=0;i<4;i++) many.push({key:"CLAUDE_HTML_PRICES",op:"set",value:"/"+new Array(400).join("é")});
  console.log(S.linkFor("none", many));' "$HERE")"
L1="$(printf '%s\n' "$LINK" | sed -n 1p)"
check "the page's link" "$L1" "claude-html://settings/v1/0123456789abcdef/EXPORT=%2F%C3%A9%2Fit%27s%20%28a%29%20x%2A%21.json/WEEK_RESET=tue%2007%3A00%20UTC/ENGINE/forget-safe"
check "  is one the grammar takes" "$(lok "${L1#claude-html://settings/}")" ok
check "  read back by the command to the very values (as the dry run quotes them)" \
  "$(apply_dry "${L1#claude-html://settings/}" | grep -e '^CLAUDE_HTML_EXPORT=' -e '^CLAUDE_HTML_WEEK_RESET=')" \
  "CLAUDE_HTML_EXPORT=\"/é/it'\\''s (a) x*!.json\"
CLAUDE_HTML_WEEK_RESET=\"tue 07:00 UTC\""
check "  copy command: the same as --config lines, quoted where it must be" "$(printf '%s\n' "$LINK" | sed -n '2,4p')" \
  "claude-html --config set 'EXPORT=/é/it'\\''s x.json' GUARD=off
claude-html --config unset ENGINE
claude-html --config forget-safe"
check "  too long for a link: none, and the page says copy the command" "$(printf '%s\n' "$LINK" | sed -n 5p)" null

# ── the confirmation ─────────────────────────────────────────────────
echo "confirmation"
conf 'CLAUDE_HTML_GUARD="prompt"'; list; cp "$CONFF" "$T/conf.before"
FP="$(sh_ 'ch_set_fp')"
D="$(apply_dry "v1/$FP/GUARD=off/REDACT=off/GUARD_WAIT=2m/forget-safe")"
check "zenity: a question, Cancel the default, Apply" \
  "$(printf '%s' "$D" | grep -c "^'zenity' '--question' '--no-markup' '--default-cancel' '--title=claude-html' '--ok-label=Apply' '--cancel-label=Cancel'")" 1
check "  each change as it is now and as it will be, protection lowered said" \
  "$(printf '%s\n' "$D" | grep -e '^Guard:' -e '^Masking:' -e '^Windows wait:' -e '^Safe values:' -e '^File:')" \
  "Guard:  prompt → off   ⚠ lowers protection
Masking:  on (default) → off   ⚠ lowers protection
Windows wait:  1m (default) → 2m
Safe values:  2 → 0: forgotten, your own 2 entries stay
File:  ~/.claude/claude-html.conf"
check "  the very lines Apply writes, and the list's lines by count only" \
  "$(printf '%s\n' "$D" | sed -n '/^Written to the file:$/,/^$/p' | sed '1d;$d')" \
  'CLAUDE_HTML_GUARD="off"
CLAUDE_HTML_REDACT="off"
CLAUDE_HTML_GUARD_WAIT="2m"
# in ~/.claude/claude-html.redact: its 2 safe: line(s) taken out, nothing else'
check "  not stale: it says only who asked" "$(printf '%s\n' "$D" | grep -c '^Asked by the Settings page.$')" 1
check "  and nothing written while it was only shown" "$(cmp -s "$CONFF" "$T/conf.before" && echo same) $(printf '%s' "$D" | grep -c "$SECRET")" "same 0"
printf '# edited in a terminal\n' >> "$CONFF"; cp "$CONFF" "$T/conf.before"
D="$(apply_dry "v1/$FP/GUARD=off/GUARD_WAIT=2m")"
check "the conf changed since the page was built: said, and each value now beside the one asked" \
  "$(printf '%s\n' "$D" | grep -e '^Asked by' -e '^Guard:' -e '^Windows wait:')" \
  "Asked by the Settings page — the conf changed since this page was built.
Guard:  now prompt · asked off   ⚠ lowers protection
Windows wait:  now 1m (default) · asked 2m"
check "  a value the environment overrides: said in the window" \
  "$(apply_dry "v1/$FP/GUARD_WAIT=2m" CLAUDE_HTML_GUARD_WAIT=45s | grep -c '(set in the environment, which wins: no change here while it is)')" 1
# On a Mac: the window of dialog.js, through a stand-in osascript; the
# lines in a private file, gone after.
cat > "$T/mac/osascript" <<'STUB'
#!/bin/bash
case "$*" in *dialog.js*) ;; *) exit 1 ;; esac
printf '%s\n' "$@" > "$STUB_REC.argv"
while [ $# -gt 0 ]; do
  case "$1" in --box) ls -ld "${3%/*}" "$3" | cut -c1-10 | tr '\n' ' ' > "$STUB_REC.modes"; cat "$3" > "$STUB_REC.content"; rm -f "$3"; shift 3 ;; *) shift ;; esac
done
echo "$STUB_ANSWER"
STUB
printf '#!/bin/sh\necho Aqua\n' > "$T/mac/launchctl"; chmod +x "$T/mac/osascript" "$T/mac/launchctl"
# The window is the stand-in's, so CLAUDE_HTML_NO_SCREEN is off for it.
R="$(cli --settings-apply "v1/$FP/GUARD=off" CLAUDE_HTML_UNAME=Darwin PATH="$T/mac:$PATH" TMPDIR="$T/mtmp" STUB_REC="$T/mrec" STUB_ANSWER=cancel CLAUDE_HTML_GUARD_TEST_LIMIT=7 CLAUDE_HTML_NO_SCREEN=)"
check "on a Mac: the confirmation window, Cancel: nothing changed" "$R $(cmp -s "$CONFF" "$T/conf.before" && echo same)" "Nothing was changed. same"
check "  its rows, its File ▸ lines in a private file gone after, the test's limit" \
  "$(grep -c '^confirm$' "$T/mrec.argv") $(grep -c 'Guard:	now prompt · asked off   ⚠ lowers protection' "$T/mrec.argv") $(cat "$T/mrec.content") $(cat "$T/mrec.modes")$(ls -A "$T/mtmp" | wc -l | tr -d ' ') $(grep -A1 -x -- '--limit' "$T/mrec.argv" | tail -1)" \
  '1 1 CLAUDE_HTML_GUARD="off" drwx------ -rw------- 0 7'
mkdir -p "$H/.claude/.claude-html-settings-ask"
check "one window at a time: a second link while one asks, exit 3" \
  "$(cli --settings-apply "v1/$FP/GUARD=off" CLAUDE_HTML_UNAME=Linux DISPLAY=:9 XDG_CURRENT_DESKTOP=GNOME PATH="$T/stub:$PATH" STUB_ANSWER=yes >/dev/null; echo $?) $(cmp -s "$CONFF" "$T/conf.before" && echo same)" "3 same"
rmdir "$H/.claude/.claude-html-settings-ask"
check "no window to ask in: refused, the command said instead" \
  "$(cli --settings-apply "v1/$FP/GUARD=off/forget-safe" CLAUDE_HTML_UNAME=Linux PATH="$T/stub:$PATH" | sed -n '2,3p'; cmp -s "$CONFF" "$T/conf.before" && echo same)" \
  "claude-html --config set GUARD=off
claude-html --config forget-safe
same"

# ── Apply: the write, then the rebuild ───────────────────────────────
echo "apply"
# The window is the stand-in's: CLAUDE_HTML_NO_SCREEN off for it.
apply() { cli --settings-apply "$1" CLAUDE_HTML_UNAME=Linux DISPLAY=:9 XDG_CURRENT_DESKTOP=GNOME PATH="$T/stub:$PATH" STUB_ARGS="$T/stub.args" STUB_ANSWER="$2" CLAUDE_HTML_GUARD_TEST_LIMIT=60 CLAUDE_HTML_NO_SCREEN= "${@:3}"; }
check "Cancel: nothing changed" "$(apply "v1/$FP/GUARD=off" no) $(cmp -s "$CONFF" "$T/conf.before" && echo same)" "Nothing was changed. same"
check "  the window closed for want of an answer: the same" \
  "$(apply "v1/$FP/GUARD=off" sleep CLAUDE_HTML_GUARD_TEST_LIMIT=1) $(cmp -s "$CONFF" "$T/conf.before" && echo same)" "Nothing was changed. same"
for ENG in $([ "$HAVE_OSASCRIPT" = true ] && echo osascript) node; do
  conf 'CLAUDE_HTML_GUARD="prompt"' 'CLAUDE_HTML_VIEW_GROUP="project"'; list; rm -rf "$T/out"
  cli CLAUDE_HTML_ENGINE=$ENG >/dev/null
  FP="$(sh_ 'ch_set_fp')"
  R="$(apply "v1/$FP/GUARD_WAIT=2m/VIEW_THEME=dark/VIEW_GROUP/UPDATE_CHECK=off/forget-safe" yes CLAUDE_HTML_ENGINE=$ENG)"
  check "$ENG: Apply: written, and the page named to open again" "$R" "Applied.
$T/out/settings.html"
  check "$ENG:   the conf's lines" "$(grep -E '^CLAUDE_HTML_(GUARD|GUARD_WAIT|VIEW_THEME|VIEW_GROUP|UPDATE_CHECK)=' "$CONFF" | tr '\n' ' ')" \
    'CLAUDE_HTML_GUARD="prompt" CLAUDE_HTML_GUARD_WAIT="2m" CLAUDE_HTML_VIEW_THEME="dark" CLAUDE_HTML_UPDATE_CHECK="off" '
  check "$ENG:   the safe values forgotten, the own entries kept" "$(grep -c 'safe:' "$LIST") $(grep -cx "$SECRET" "$LIST")" "0 1"
  check "$ENG:   the pages rebuilt with it: the values, their sources, the page defaults" \
    "$(data "$T/out/settings.html" '[d.values.CLAUDE_HTML_GUARD_WAIT.v, d.values.CLAUDE_HTML_GUARD_WAIT.src, d.values.CLAUDE_HTML_VIEW_GROUP.src, d.redact.safe, d.redact.own, d.shell.engine.name].join(" ")') $(grep -o '"theme":"[a-z]*","group":"[a-z]*"' "$T/out/defaults.js")" \
    "2m conf default 0 2 $ENG \"theme\":\"dark\",\"group\":\"date\""
  check "$ENG:   the fingerprint is the conf's new one" "$(data "$T/out/settings.html" 'd.shell.fp') " "$(sh_ 'ch_set_fp') "
done

# ── the page ─────────────────────────────────────────────────────────
echo "page"
conf 'CLAUDE_HTML_GUARD="prompt"'; list
for ENG in $([ "$HAVE_OSASCRIPT" = true ] && echo osascript) node; do
  rm -rf "$T/out"; cli CLAUDE_HTML_ENGINE=$ENG CLAUDE_HTML_GUARD_WAIT=45s >/dev/null
  P="$T/out/settings.html"
  check "$ENG: the page, linked from the index and the dashboard" \
    "$([ -f "$P" ] && echo there) $(grep -c 'href="settings.html"' "$T/out/index.html") $(grep -c 'href="settings.html"' "$T/out/usage.html")" "there 1 1"
  check "$ENG:   every setting of the description, with where it comes from" \
    "$(data "$P" 'Object.keys(d.values).length+" "+d.values.CLAUDE_HTML_GUARD.src+" "+d.values.CLAUDE_HTML_GUARD_WAIT.src+" "+d.values.CLAUDE_HTML_REDACT.src+" "+d.partial')" \
    "$(grep -cE '^(CLAUDE_HTML_|CH_)' "$HERE/lib/settings.tsv") conf environment default false"
  check "$ENG:   what the machine is, and the engine that built it" \
    "$(data "$P" '[d.shell.engine.name, d.shell.version === d.update.installed, !!d.shell.system, d.shell.fp.length].join(" ")')" \
    "$ENG true true 16"
  check "$ENG:   the own list by count only: never a word of it, nor the safe values' hashes" \
    "$(data "$P" 'd.redact.own+" "+d.redact.safe') $(grep -rl -e "$SECRET" -e acme_ -e 0123456789abcdef0123456789abcdef "$T/out" | wc -l | tr -d ' ')" "2 2 0"
  check "$ENG:   the hooks as settings.json has them (none here), and cleanupPeriodDays" \
    "$(data "$P" 'JSON.stringify(d.hooks)')" \
    '{"Stop":false,"SessionEnd":false,"PreCompact":false,"guardPrompt":false,"guardBash":false,"statusLine":"none","cleanupPeriodDays":null}'
  cp -R "$T/out" "$T/out-$ENG"
done
check "the same page under both engines but for which built it" \
  "$( [ "$HAVE_OSASCRIPT" = true ] || { echo same; exit 0; }
     diff <(sed 's/"js":"osascript"/"js":"X"/; s/"name":"osascript"/"name":"X"/; s/"why":"[^"]*"/"why":""/; s/"node":"[^"]*","nodeVersion":"[^"]*"/"node":""/' "$T/out-osascript/settings.html") \
          <(sed 's/"js":"node"/"js":"X"/; s/"name":"node"/"name":"X"/; s/"why":"[^"]*"/"why":""/; s/"node":"[^"]*","nodeVersion":"[^"]*"/"node":""/; s/"CLAUDE_HTML_ENGINE":{"v":"node"/"CLAUDE_HTML_ENGINE":{"v":"osascript"/' "$T/out-node/settings.html") >/dev/null && echo same)" same
# Incremental, as a save builds after a change, is what a build from
# scratch writes.
rm -rf "$T/out"; cli CLAUDE_HTML_ENGINE=node >/dev/null
cfg set GUARD_WAIT=3m -- CLAUDE_HTML_ENGINE=node >/dev/null
cp "$T/out/settings.html" "$T/inc.html"; cp "$T/out/defaults.js" "$T/inc.js"
rm -rf "$T/out"; cli CLAUDE_HTML_ENGINE=node >/dev/null
check "incremental, then a change: the same bytes as built from scratch" \
  "$(cmp -s "$T/inc.html" "$T/out/settings.html" && cmp -s "$T/inc.js" "$T/out/defaults.js" && echo same)" same
check "the page's files are its owner's alone" "$(ls -l "$T/out/settings.html" "$T/out/defaults.js" | cut -c1-10 | sort -u | tr -d '\n')" "-rw-------"

# ── the page defaults ────────────────────────────────────────────────
echo "page defaults"
conf 'CLAUDE_HTML_VIEW_THEME="dark"' 'CLAUDE_HTML_VIEW_GROUP="project"' 'CLAUDE_HTML_VIEW_SESSION="conversation"' \
     'CLAUDE_HTML_VIEW_PERIOD="month"' 'CLAUDE_HTML_VIEW_BREAKDOWN="project"' 'CLAUDE_HTML_VIEW_PRICES="today"'
rm -rf "$T/out"; cli CLAUDE_HTML_ENGINE=node >/dev/null
check "the conf's defaults, in the file every page loads" "$(sed -n 2p "$T/out/defaults.js")" \
  'var CH_DEFAULTS = {"theme":"dark","group":"project","session":"conversation","period":"month","breakdown":"project","prices":"today"};'
check "  a session page and a sub-agent's load it from where the index is" \
  "$(grep -c '<script src="../defaults.js"></script>' "$T/out/sessions/$SID.html")" 1
# Each page's head and CH.pref, run against a stand-in browser: the conf's
# default when this browser remembers nothing; what it remembers wins.
PD="$(node -e '
var fs=require("fs"), vm=require("vm"), h=process.argv[1];
function browser(store, defaults) {
  var attrs={}, ls={ getItem:function(k){return Object.prototype.hasOwnProperty.call(store,k)?store[k]:null;},
    setItem:function(k,v){store[k]=String(v);}, removeItem:function(k){delete store[k];},
    key:function(i){return Object.keys(store)[i];}, get length(){return Object.keys(store).length;} };
  var ctx={ localStorage:ls, document:{documentElement:{setAttribute:function(a,v){attrs[a]=v;},removeAttribute:function(a){delete attrs[a];}}} };
  ctx.window=ctx; vm.createContext(ctx);
  if (defaults) vm.runInContext(defaults, ctx);
  return { ctx:ctx, attrs:attrs, store:store };
}
var defs=fs.readFileSync(process.argv[2],"utf8"), out=[];
["index.html","usage.html","page.html","settings.html"].forEach(function(f){
  var html=fs.readFileSync(h+"/viewer/"+f,"utf8"), head=/<script>(\(function\(\)\{var t=null;[\s\S]*?)<\/script>/.exec(html)[1];
  var r=[[{}, defs],[{"ch-theme":"light"}, defs],[{"ch-theme":"auto"}, defs],[{}, null]].map(function(c){
    var b=browser(c[0], c[1]); vm.runInContext(head,b.ctx); return b.attrs["data-theme"]||"-"; });
  out.push(f+" "+r.join(" ")+" "+/<script src="[^"]*defaults\.js"><\/script>\n<script>\(function\(\)\{var t=null/.test(html));
});
var vsrc=fs.readFileSync(h+"/viewer/viewer.js","utf8");
function prefs(store, withDefs) {
  var b=browser(store, withDefs ? defs : null); vm.runInContext(vsrc, b.ctx);
  var CH=vm.runInContext("CH", b.ctx);
  return ["theme","group","session","period","breakdown","prices"].map(function(n){return CH.pref(n, "own");}).join(",");
}
out.push(prefs({}, true));
out.push(prefs({"ch-theme":"auto","ch-group":"0","ch-mode":"all","ch-usage-period":"all","ch-usage-dim":"model","ch-usage-prices":"then"}, true));
out.push(prefs({"ch-group":"bogus"}, false));
var r=browser({"ch-theme":"dark","ch-mode":"talk","ch-limits-open":"1","other-site":"x"}, null); vm.runInContext(vsrc, r.ctx);
out.push(vm.runInContext("CH.forgetPrefs()", r.ctx)+" "+Object.keys(r.store).join(","));
console.log(out.join("\n"));' "$HERE" "$T/out/defaults.js" 2>&1)"
check "each page's head: the conf's theme, else what the browser remembers, auto included" \
  "$(printf '%s\n' "$PD" | sed -n 1,4p)" \
  "index.html dark light - - true
usage.html dark light - - true
page.html dark light - - true
settings.html dark light - - true"
check "each view: the conf's default when nothing is remembered" "$(printf '%s\n' "$PD" | sed -n 5p)" "dark,1,talk,month,project,now"
check "  what the browser remembers wins over it" "$(printf '%s\n' "$PD" | sed -n 6p)" "auto,0,all,all,model,then"
check "  without the file, or with a value it does not know, the page's own" "$(printf '%s\n' "$PD" | sed -n 7p)" "own,own,own,own,own,own"
check "reset this browser: claude-html's keys go, nothing else" "$(printf '%s\n' "$PD" | sed -n 8p)" "3 other-site"
check "opening a session page remembers nothing; only a click does" \
  "$(grep -c 'if (!opening) { try { localStorage.setItem("ch-mode", m)' "$HERE/viewer/page.js") $(grep -c 'localStorage.setItem("ch-usage-period"' "$HERE/viewer/usage.js")" "1 1"

# A Mac always has a way to open a page, so the index must be noted there;
# a Linux machine without a display (CI) has none, and nothing is tried.
# Either way, nothing but the index may be noted.
_ni="$(grep -c "/out/index\.html'\$" "$T/shown" 2>/dev/null)"; _no="$(grep -vc "/out/index\.html'\$" "$T/shown" 2>/dev/null)"
check "the index was never opened, only noted, each time a build named no session" \
  "$({ [ "${_ni:-0}" -gt 0 ] || [ "$(uname)" != Darwin ]; } && echo noted) ${_no:-0}" "noted 0"

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
