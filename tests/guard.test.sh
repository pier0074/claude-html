#!/bin/bash
# The guard: a prompt or a command holding a secret is stopped before it
# reaches Claude, the user is told what kind and never the value, and the
# answers do what they say. Everything in a sandbox HOME; no fake secret is
# ever printed, nor left anywhere but where the test put it.
#
#   bash tests/guard.test.sh
set -u

. "$(dirname "$0")/lib.sh"

HERE="$(cd "$(dirname "$0")/.." && pwd)"
pass=0; fail=0
check() {
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); printf '  ok    %s\n' "$1"
  else fail=$((fail + 1)); printf '  FAIL  %s (expected %s, got %s)\n' "$1" "$3" "$2"; fi
}
T="$(mktemp -d /tmp/chredact-guard.XXXXXX)"; T="$(cd "$T" && pwd -P)"
trap 'rm -rf "$T"' EXIT
node "$HERE/tests/guard.test.js" fixture "$T"
. "$HERE/lib/platform.sh"
H="$T/home"; mkdir -p "$H/.claude" "$T/bin"
LOG="$T/log"; : > "$LOG"
LIST="$H/.claude/claude-html.redact"; CONFF="$H/.claude/claude-html.conf"; STATE="$H/.claude/.claude-html-guard/sess-1"
printf 'CLAUDE_HTML_ROOT="%s"\nCLAUDE_HTML_OUT="%s"\n' "$T/root" "$T/out" > "$CONFF"

ENGINES=node; [ "$HAVE_OSASCRIPT" = true ] && ENGINES="osascript node"
# The hook as Claude Code runs it, words in the next prompt (no dialog).
hook() {  # kind note-file [env…]
  local kind="$1" f="$2"; shift 2
  env HOME="$H" PATH="$T/bin:$PATH" CLAUDE_HTML_CONF="$CONFF" CLAUDE_HTML_REDACT_FILE="$LIST" \
    CLAUDE_HTML_ENGINE="$ENG" CLAUDE_HTML_GUARD_DIALOG=off "$@" \
    /bin/bash "$HERE/guard.sh" "$kind" < "$f" 2>>"$LOG.err" | tee -a "$LOG"
}
reset() { rm -f "$STATE" "$LIST" "$H/.claude/.claude-html.guard-engine"
          printf 'CLAUDE_HTML_ROOT="%s"\nCLAUDE_HTML_OUT="%s"\n' "$T/root" "$T/out" > "$CONFF"; }
blocked() { case "$1" in *'"decision":"block"'*) echo blocked ;; "") echo passed ;; *) echo other ;; esac; }
# A block's shape as Claude Code reads it: the prompt is left out of the
# message only by hookSpecificOutput.suppressOriginalPrompt; at the top
# level it is ignored, and the prompt is echoed and kept in the transcript.
shape() { node -e 'var o; try { o=JSON.parse(require("fs").readFileSync(0,"utf8")); } catch (e) { console.log("not JSON"); process.exit(); }
  var h=o.hookSpecificOutput||{}; console.log([o.decision, h.hookEventName, h.suppressOriginalPrompt===true, "suppressOriginalPrompt" in o].join(" "))'; }
# How many files printed or kept hold a probe. The guard keeps salts and
# fingerprints (its state, the safe lines), random hex by design; a short
# probe made of hex letters alone turns up in one now and then, which is no
# secret kept. Those fields are blanked first; the rest of each file is read.
leaks() {
  local n=0 f
  while IFS= read -r -d '' f; do
    sed -E 's/"(salt|hash)":"[0-9a-f]*"/"\1":""/g; s/^([[:space:]]*safe:)[0-9a-f]*:[0-9a-f]*/\1:/' "$f" 2>/dev/null |
      grep -qF -f "$T/probes.txt" && n=$((n + 1))
  done < <(find "$H" "$LOG" "$LOG.err" -type f -print0 2>/dev/null)
  echo "$n"
}
# leaks() itself: a fingerprint that happens to hold a probe is not a leak,
# the probe as a value beside it is.
HP="$(grep -xE '[0-9a-f]+' "$T/probes.txt" | awk '{ print length, $0 }' | sort -n | head -1 | cut -d' ' -f2)"
mkdir -p "$H/.claude/.claude-html-guard"
printf '{"pending":{"time":1,"entries":[{"rule":"github","salt":"0%s","hash":"%s0"}]},"session":"sess-x"}' "$HP" "$HP" \
  > "$H/.claude/.claude-html-guard/sess-x"
printf 'safe:0%s:%s0   # github, 2026-11-19\n' "$HP" "$HP" > "$H/.claude/leaks-check.redact"
L1="$(leaks)"; printf 'pw=%s\n' "$HP" >> "$H/.claude/leaks-check.redact"; L2="$(leaks)"
rm -f "$H/.claude/.claude-html-guard/sess-x" "$H/.claude/leaks-check.redact"
check "a fingerprint holding a hex-only probe is not counted as a secret kept, the probe itself is" "$L1 $L2" "0 1"
unset HP L1 L2

# ── the quick look never skips what the rules catch ─────────────────
A="$(node "$HERE/tests/guard.test.js" anchors)"
check "guard.sh's quick look holds every text a rule of redact.js starts at" \
  "$(printf '%s' "$A" | sed -n 's/.*"missing":\(\[[^]]*\]\).*/\1/p')" "[]"

for ENG in $ENGINES; do
  reset
  # ── every rule it is sure of, as a prompt and as a command ──────────
  n=0; np=0; nb=0; nl=0
  while IFS= read -r line; do
    n=$((n + 1))
    printf '%s' "$line" | node -e 'var o=JSON.parse(require("fs").readFileSync(0,"utf8"));
      require("fs").writeFileSync(process.argv[1]+"/p.json", JSON.stringify(o.prompt));
      require("fs").writeFileSync(process.argv[1]+"/b.json", JSON.stringify(o.bash));' "$T"
    rm -f "$STATE"
    R="$(hook prompt "$T/p.json")"
    [ "$(blocked "$R")" = blocked ] && np=$((np + 1))
    case "$R" in *"Nothing was sent. Retype it without it"*"cancel  do not send"*) nl=$((nl + 1)) ;; esac
    rm -f "$STATE"
    B="$(hook bash "$T/b.json")"
    case "$B" in *'"permissionDecision":"ask"'*) nb=$((nb + 1)) ;; esac
  done < "$T/cases.jsonl"
  check "$ENG: each of $n secrets of the rules it is sure of stops the prompt" "$np" "$n"
  check "$ENG:   with the message and its four answers" "$nl" "$n"
  check "$ENG:   and asks before the command runs" "$nb" "$n"
  check "$ENG:   and nothing printed or kept holds one" "$(leaks)" 0

  reset
  check "$ENG: a clean prompt passes, saying nothing" "$(hook prompt "$T/note.clean")" ""
  check "$ENG: the weak form and prose pass" "$(hook prompt "$T/note.weak")" ""
  check "$ENG: nothing is pending after them" "$([ -f "$STATE" ] && echo yes || echo no)" no
  check "$ENG: a sub-agent's report passes, whatever it holds" "$(hook prompt "$T/note.notify")" ""
  check "$ENG:   but not with a secret typed after it, or before" \
    "$(blocked "$(hook prompt "$T/note.notify_after")") $(rm -f "$STATE"; blocked "$(hook prompt "$T/note.notify_before")")" "blocked blocked"
  rm -f "$STATE"

  # ── the four words ─────────────────────────────────────────────────
  R="$(hook prompt "$T/note.secret")"
  check "$ENG: a prompt with two kinds is stopped, by kind and count" \
    "$(printf '%s' "$R" | grep -c 'GitHub token (1), password in a URL (1)')" 1
  check "$ENG:   leaving the prompt out of the message" "$(printf '%s' "$R" | shape)" "block UserPromptSubmit true false"
  check "$ENG:   leaving its fingerprints pending, readable by its owner only" \
    "$(ls -l "$STATE" | cut -c1-10) $(grep -c '"rule":"github"' "$STATE")" "-rw------- 1"
  R="$(hook prompt "$T/note.w_cancel")"
  check "$ENG: cancel drops it" "$(printf '%s' "$R" | grep -c 'Dropped. Nothing was sent.')" 1
  check "$ENG:   its answer leaving the word out too" "$(printf '%s' "$R" | shape)" "block UserPromptSubmit true false"
  check "$ENG:   and nothing is pending" "$([ -f "$STATE" ] && echo yes || echo no)" no

  hook prompt "$T/note.secret" >/dev/null
  check "$ENG: allow (any case, spaces) lets it go once" \
    "$(hook prompt "$T/note.w_allow" | grep -c 'Allowed once. Press')" 1
  check "$ENG:   writing nothing to the list" "$(cat "$LIST" 2>/dev/null | grep -c .)" 0
  check "$ENG:   only in its own session" "$(blocked "$(hook prompt "$T/note.secret2")")" blocked
  check "$ENG:   then the same prompt passes" "$(blocked "$(hook prompt "$T/note.secret")")" passed
  check "$ENG:   once: the next time it is stopped again" "$(blocked "$(hook prompt "$T/note.secret")")" blocked
  hook prompt "$T/note.clean2" >/dev/null
  check "$ENG:   a prompt in another session leaves this one's answer pending" \
    "$(hook prompt "$T/note.w_cancel" | grep -c 'Dropped. Nothing was sent.')" 1
  hook prompt "$T/note.secret" >/dev/null

  RSIG0="$(CLAUDE_HTML_REDACT_FILE="$LIST" ch_redact_sig "$HERE")"
  R="$(hook prompt "$T/note.w_safe")"
  check "$ENG: safe records it as not a secret" "$(printf '%s' "$R" | grep -c 'Recorded as not sensitive')" 1
  check "$ENG:   as two safe lines, by rule and date, no value" \
    "$(grep -cE '^safe:[0-9a-f]{16}:[0-9a-f]{32}   # (github|url-password), [0-9-]{10}$' "$LIST")" 2
  check "$ENG:   which change the redaction's signature" \
    "$([ "$(CLAUDE_HTML_REDACT_FILE="$LIST" ch_redact_sig "$HERE")" != "$RSIG0" ] && echo changed)" changed
  check "$ENG:   and the same prompt passes, now and later" \
    "$(blocked "$(hook prompt "$T/note.secret")") $(blocked "$(hook prompt "$T/note.secret")")" "passed passed"
  check "$ENG:   while another secret is still stopped" "$(blocked "$(hook prompt "$T/note.other")")" blocked
  R="$(hook prompt "$T/note.w_stop")"
  check "$ENG: stop turns the check off" "$(printf '%s' "$R" | grep -c 'The secret check is off')" 1
  check "$ENG:   by its one line in the conf, the rest kept" \
    "$(grep -c '^CLAUDE_HTML_GUARD="off"$' "$CONFF") $(grep -c '^CLAUDE_HTML_ROOT=' "$CONFF")" "1 1"
  check "$ENG:   and the next secret passes" "$(blocked "$(hook prompt "$T/note.other")")" passed

  reset
  check "$ENG: a word with nothing pending is a prompt like any other" "$(hook prompt "$T/note.w_stop")" ""
  hook prompt "$T/note.secret" >/dev/null
  check "$ENG: a word from another session too" "$(hook prompt "$T/note.w_stop2")" ""
  check "$ENG:   and the conf is untouched" "$(grep -c 'CLAUDE_HTML_GUARD' "$CONFF")" 0
  hook prompt "$T/note.secret" >/dev/null
  node -e 'var f=process.argv[1],s=JSON.parse(require("fs").readFileSync(f,"utf8"));s.pending.time-=11*60*1000;require("fs").writeFileSync(f,JSON.stringify(s))' "$STATE"
  check "$ENG: and one after ten minutes" "$(hook prompt "$T/note.w_stop")" ""
  hook prompt "$T/note.secret" >/dev/null
  check "$ENG: an ordinary prompt drops what was pending" "$(hook prompt "$T/note.clean")$([ -f "$STATE" ] && echo yes)" ""

  # ── commands ───────────────────────────────────────────────────────
  reset
  B="$(hook bash "$T/note.bash_mysql")"
  check "$ENG: mysql -p… is put to the user in Claude Code's own dialog" \
    "$(printf '%s' "$B" | grep -c '"permissionDecision":"ask","permissionDecisionReason":"Claude'"'"'s command has been interrupted — sensitive information detected (MySQL password (1)). Deny to stop it; allow to run it this time only.')" 1
  check "$ENG:   naming safe and stop as the next prompt" "$(printf '%s' "$B" | grep -c 'answer `safe` as your next prompt; `stop` turns the check off')" 1
  check "$ENG:   and safe answers it" "$(hook prompt "$T/note.w_safe" | grep -c 'Recorded as not sensitive')" 1
  check "$ENG: a token in a URL is asked about too" "$(hook bash "$T/note.bash_url" | grep -c '"ask"')" 1
  rm -f "$LIST"
  B="$(hook bash "$T/note.bash_bypass")"
  check "$ENG: with permissions bypassed, it is refused, Claude told how to do without" \
    "$(printf '%s' "$B" | grep -c '"permissionDecision":"deny".*~/.my.cnf, an environment variable or a credential helper')" 1
  check "$ENG:   and the user told about safe and stop" "$(printf '%s' "$B" | grep -c '"systemMessage":".*`safe`')" 1
  check "$ENG: a clean command says nothing" "$(hook bash "$T/note.bash_clean")" ""
  check "$ENG: another tool says nothing" "$(hook bash "$T/note.write_tool")" ""
  check "$ENG: with the guard on for prompts only, commands pass" "$(hook bash "$T/note.bash_mysql" CLAUDE_HTML_GUARD=prompt)" ""
  check "$ENG: and with it off, prompts too" "$(hook prompt "$T/note.secret" CLAUDE_HTML_GUARD=off)" ""

  # ── it fails open, quietly ─────────────────────────────────────────
  reset
  mkdir -p "$T/broken/lib" "$T/broken/actions" "$T/broken/build"; cp "$HERE"/guard.sh "$T/broken/"
  cp "$HERE"/lib/conf.sh "$HERE"/lib/platform.sh "$T/broken/lib/"; cp "$HERE"/actions/guard.js "$T/broken/actions/"
  printf 'syntax error (' > "$T/broken/build/redact.js"
  R="$(env HOME="$H" CLAUDE_HTML_CONF="$CONFF" CLAUDE_HTML_REDACT_FILE="$LIST" CLAUDE_HTML_ENGINE="$ENG" \
       CLAUDE_HTML_GUARD_DIALOG=off /bin/bash "$T/broken/guard.sh" prompt < "$T/note.secret" 2>&1; echo "exit $?")"
  check "$ENG: a broken redact.js lets the prompt through, saying nothing" "$R" "exit 0"
  rm -f "$T/broken/build/redact.js"
  R="$(env HOME="$H" CLAUDE_HTML_CONF="$CONFF" CLAUDE_HTML_ENGINE="$ENG" CLAUDE_HTML_GUARD_DIALOG=off \
       /bin/bash "$T/broken/guard.sh" prompt < "$T/note.secret" 2>&1; echo "exit $?")"
  check "$ENG: so does a missing one" "$R" "exit 0"
  R="$(printf 'not json at all {' | env HOME="$H" CLAUDE_HTML_CONF="$CONFF" CLAUDE_HTML_ENGINE="$ENG" \
       /bin/bash "$HERE/guard.sh" prompt 2>&1; echo "exit $?")"
  check "$ENG: and a note it cannot read" "$R" "exit 0"
  R="$(env HOME="$H" CLAUDE_HTML_CONF="$CONFF" CLAUDE_HTML_ENGINE="$ENG" /bin/bash "$HERE/guard.sh" prompt </dev/null 2>&1; echo "exit $?")"
  check "$ENG: and no note at all" "$R" "exit 0"
  chmod 000 "$CONFF"
  R="$(hook prompt "$T/note.clean" 2>&1; echo "exit $?")"
  check "$ENG: an unreadable conf breaks nothing" "$R" "exit 0"
  chmod 644 "$CONFF"
  check "$ENG: nothing printed or kept holds a secret" "$(leaks)" 0
done

# ── the dialog ─────────────────────────────────────────────────────────
# The exact command each desktop is given, never with a secret in it.
DD="$T/dd"; mkdir -p "$DD"; printf 'f' > "$DD/found"; printf 'c' > "$DD/command"; printf 'd' > "$DD/details.txt"
for d in osascript zenity yad kdialog xmessage; do
  CH_DIALOG=$d CH_HERE="$HERE" CH_DRY=1 ch_choose prompt Weather "GitHub token (1)" > "$T/dry.$d"
  CH_DIALOG=$d CH_HERE="$HERE" CH_DRY=1 ch_choose bash Weather "MySQL password (1)" "mysql -u root -p*** db" "$DD" > "$T/drydet.$d"
done
NL='
'
TEXT="Your prompt has been interrupted${NL}Sensitive information detected${NL}${NL}Where:  your prompt in Claude Code  ·  project Weather${NL}Found:  GitHub token (1)${NL}${NL}Closes after 1 minute — counts as Cancel."
TEXTB="Claude's command has been interrupted${NL}Sensitive information detected${NL}${NL}Where:  a command from Claude  ·  project Weather${NL}Found:  MySQL password (1)${NL}Command:  mysql -u root -p*** db${NL}${NL}Details shows what was found and the whole command, on this screen only.${NL}Closes after 1 minute — counts as Cancel."
CH4="'Cancel — do not send' 'FALSE' 'Allow once — it is sensitive, send it this time only' 'FALSE' 'Safe — it is not sensitive, send it and never ask again' 'FALSE' 'Stop — turn this check off'"
CH4B="'Cancel — do not run' 'FALSE' 'Allow once — it is sensitive, run it this time only' 'FALSE' 'Safe — it is not sensitive, run it and never ask again' 'FALSE' 'Stop — turn this check off'"
check "macOS: a window of osascript's own, told the kind and the project only, and its time limit" \
  "$(cat "$T/dry.osascript")" "'osascript' '-l' 'JavaScript' '$HERE/mac/dialog.js' '--limit' '60' 'prompt' 'Weather' 'GitHub token (1)'"
check "  with details: the private files' paths, never what they hold" \
  "$(cat "$T/drydet.osascript")" "'osascript' '-l' 'JavaScript' '$HERE/mac/dialog.js' '--limit' '60' '--box' 'Found:' '$DD/found' '--pre' 'Command:' '$DD/command' 'bash' 'Weather' 'MySQL password (1)' 'mysql -u root -p*** db'"
check "  and the test's limit drives its countdown" \
  "$(CLAUDE_HTML_GUARD_TEST_LIMIT=8 bash -c '. "$1/lib/platform.sh"; CH_DIALOG=osascript CH_HERE="$1" CH_DRY=1 ch_choose prompt P F' _ "$HERE" | grep -c "'--limit' '8' ")" 1
check "zenity: a radio list, Cancel picked, OK, the time limit said" \
  "$(cat "$T/dry.zenity")" "'zenity' '--list' '--radiolist' '--title=claude-html' '--no-markup' '--text=$TEXT' '--ok-label=OK' '--column= ' '--column=Choice' 'TRUE' $CH4"
check "  with details: a Details button, and the file in zenity's own text window" \
  "$(cat "$T/drydet.zenity")" "'zenity' '--list' '--radiolist' '--title=claude-html' '--no-markup' $(ch_quote "--text=$TEXTB") '--ok-label=OK' '--extra-button=Details' '--column= ' '--column=Choice' 'TRUE' $CH4B
'zenity' '--text-info' '--title=claude-html' '--filename=$DD/details.txt' '--width=720' '--height=460'"
check "yad: the same" \
  "$(cat "$T/dry.yad")" "'yad' '--list' '--radiolist' '--title=claude-html' '--text=$TEXT' '--print-column=2' '--separator=' '--button=OK:0' '--column= ' '--column=Choice' 'TRUE' $CH4"
check "  with details: a Details button and its text window" \
  "$(cat "$T/drydet.yad")" "'yad' '--list' '--radiolist' '--title=claude-html' $(ch_quote "--text=$TEXTB") '--print-column=2' '--separator=' '--button=Details:2' '--button=OK:0' '--column= ' '--column=Choice' 'TRUE' $CH4B
'yad' '--text-info' '--title=claude-html' '--filename=$DD/details.txt' '--width=720' '--height=460' '--button=Back:0'"
check "kdialog: a radio list, Cancel on" \
  "$(cat "$T/dry.kdialog")" "'kdialog' '--title' 'claude-html' '--ok-label' 'OK' '--radiolist' '$TEXT' 'cancel' 'Cancel — do not send' 'on' 'allow' 'Allow once — it is sensitive, send it this time only' 'off' 'safe' 'Safe — it is not sensitive, send it and never ask again' 'off' 'stop' 'Stop — turn this check off' 'off'"
check "  with details: a fifth entry, and its text box" \
  "$(cat "$T/drydet.kdialog" | tr '\n' '|' | sed "s/.*'stop' 'Stop — turn this check off' 'off' //")" \
  "'details' 'Details — show what was found and the whole command' 'off'|'kdialog' '--title' 'claude-html' '--textbox' '$DD/details.txt' '720' '460'|"
check "xmessage: four buttons, Cancel the default" \
  "$(cat "$T/dry.xmessage")" "'xmessage' '-center' '-title' 'claude-html' '-buttons' 'Cancel:1,Allow once:2,Safe:3,Stop:4' '-default' 'Cancel' '$TEXT'"
check "  with details: a fifth button, and the file shown by xmessage itself" \
  "$(cat "$T/drydet.xmessage" | grep -c "^'xmessage' '-center' '-title' 'claude-html' '-buttons' 'Cancel:1,Allow once:2,Safe:3,Stop:4,Details:5' '-default' 'Cancel' ") $(tail -1 "$T/drydet.xmessage")" \
  "1 'xmessage' '-center' '-title' 'claude-html' '-buttons' 'Back:0' '-default' 'Back' '-file' '$DD/details.txt'"
check "a command's dialog says run, not send" \
  "$(CH_DIALOG=zenity CH_DRY=1 ch_choose bash Weather "MySQL password (1)" | tr '\n' ' ' | grep -c "command has been interrupted.*'TRUE' 'Cancel — do not run' 'FALSE' 'Allow once — it is sensitive, run it this time only'")" 1
check "the time limit in words" "$(ch_span 600)|$(ch_span 60)|$(ch_span 120)|$(ch_span 1)|$(ch_span 8)" \
  "10 minutes|1 minute|2 minutes|1 second|8 seconds"
# The countdown's words, worked out with no clock: whole seconds, never
# below 0:00, the confirmation's own wording.
check "the countdown's words" \
  "$(node -e 'var c=require(process.argv[1]).countdown; console.log([c(600),c(599),c(61),c(60),c(9),c(0),c(-3),c(3600),c(4271),c(599,"confirm"),c(0,"confirm")].join("|"))' "$HERE/mac/dialog.js")" \
  "Cancel in 10:00|Cancel in 9:59|Cancel in 1:01|Cancel in 1:00|Cancel in 0:09|Cancel in 0:00|Cancel in 0:00|Cancel in 1:00:00|Cancel in 1:11:11|closes in 9:59 — nothing changed|closes in 0:00 — nothing changed"
if [ "$HAVE_OSASCRIPT" = true ]; then
  check "  the same under osascript, nothing shown" \
    "$(osascript -l JavaScript "$HERE/mac/dialog.js" countdown 599)|$(osascript -l JavaScript "$HERE/mac/dialog.js" --limit 8 countdown 0 confirm)" \
    "Cancel in 9:59|closes in 0:00 — nothing changed"
fi

# ── how long the windows wait: CLAUDE_HTML_GUARD_WAIT ───────────────
# Parsed in one place, platform.sh's ch_wait_secs: the seconds, or 1 for
# what is not a wait, 2 for one out of range.
wsecs() { for v in "$@"; do ch_wait_secs "$v"; printf '%s:%s ' "$?" "$_WS"; done; }
check "the wait: every form it accepts" "$(wsecs 45 45s 2m 1m30s 2M ' 2m ' 1m05s 0m30s)" \
  "0:45 0:45 0:120 0:90 0:120 0:120 0:65 0:30 "
check "  its bounds: 30 seconds and 60 minutes in, 29 seconds and 61 minutes out" \
  "$(wsecs 30 30s 60m 3600 29 29s 61m 3601 999999)" "0:30 0:30 0:3600 0:3600 2: 2: 2: 2: 2: "
check "  what is not a wait, and nothing at all" "$(wsecs abc 1m90s 5ms 1s30m -5 1.5m 2h m '' ' ')" \
  "1: 1: 1: 1: 1: 1: 1: 1: 1: 1: "
gwait() { env -u CLAUDE_HTML_GUARD_TEST_LIMIT "$@" bash -c '. "$1/lib/platform.sh"; printf "%s|%s" "$CH_GUARD_LIMIT" "$CH_GUARD_WAIT_BAD"' _ "$HERE"; }
check "the wait in force: a minute unset or empty, the setting, the default for a bad one, said" \
  "$(gwait) $(gwait CLAUDE_HTML_GUARD_WAIT=) $(gwait CLAUDE_HTML_GUARD_WAIT=2m) $(gwait CLAUDE_HTML_GUARD_WAIT=abc) $(gwait CLAUDE_HTML_GUARD_WAIT=29s) $(gwait CLAUDE_HTML_GUARD_WAIT=61m)" \
  "60| 60| 120| 60|abc 60|29s 60|61m"
check "  the tests' own limit wins over it, without the floor" "$(gwait CLAUDE_HTML_GUARD_WAIT=2m CLAUDE_HTML_GUARD_TEST_LIMIT=8)" "8|"
# What the windows are given, dry, by the setting alone.
wdry() { env -u CLAUDE_HTML_GUARD_TEST_LIMIT CLAUDE_HTML_GUARD_WAIT="$1" bash -c '. "$1/lib/platform.sh"; CH_HERE="$1" CH_DRY=1; '"$2" _ "$HERE"; }
check "the setting reaches every window: the guard's, the stop window, the confirmation (macOS)" \
  "$(wdry 45s 'CH_DIALOG=osascript ch_choose prompt P F; CH_DIALOG=osascript ch_choose_limit h k1 v1 k2 v2 c3 c4; CH_DIALOG=osascript ch_confirm t s "$(printf "k\tv")" Apply' | grep -c "'--limit' '45' ")" 3
check "  and their words (Linux)" \
  "$(wdry 1m30s 'CH_DIALOG=zenity ch_choose prompt P F; CH_DIALOG=zenity ch_choose_limit h k1 v1 k2 v2 c3 c4; CH_DIALOG=zenity ch_confirm t s "$(printf "k\tv")" Apply' | grep -c -e '^Closes after 90 seconds — counts as Cancel.' -e '^Closes after 90 seconds — nothing changed.')" 3
check "  a bad one is not obeyed: the default minute" \
  "$(wdry 9h 'CH_DIALOG=osascript ch_choose prompt P F' | grep -c "'--limit' '60' ")" 1
# The countdown starts at the limit the window is given.
check "the countdown starts at --limit" \
  "$(node -e 'var d=require(process.argv[1]),o=d.options(["--limit","45","countdown","start"]);console.log(d.countdown(o.limit)+"|"+d.countdown(d.options(["--limit","3600"]).limit))' "$HERE/mac/dialog.js")" \
  "Cancel in 0:45|Cancel in 1:00:00"
if [ "$HAVE_OSASCRIPT" = true ]; then
  check "  the same under osascript, nothing shown" \
    "$(osascript -l JavaScript "$HERE/mac/dialog.js" --limit 45 countdown start)|$(osascript -l JavaScript "$HERE/mac/dialog.js" --limit 90 countdown start confirm)" \
    "Cancel in 0:45|closes in 1:30 — nothing changed"
fi

# Where the answer is kept while the dialog is up: a folder of its own,
# made by mktemp, and gone after. No name next to it that another user of
# a shared /tmp could guess and make first. The window is a stand-in's, so
# CLAUDE_HTML_NO_SCREEN is off for it.
mkdir -p "$T/bin2" "$T/gtmp"
printf '#!/bin/sh\nls -l "$TMPDIR" | grep -v "^total" > "%s/tmp-seen"\necho "Cancel — do not send"\n' "$T" > "$T/bin2/zenity"; chmod +x "$T/bin2/zenity"
A_="$(PATH="$T/bin2:$PATH" TMPDIR="$T/gtmp" CH_DIALOG=zenity CLAUDE_HTML_NO_SCREEN= ch_choose prompt P "GitHub token (1)")"
check "the dialog's answer is kept in a folder of its own, gone after" \
  "$A_ $(grep -c '^d' "$T/tmp-seen") $(grep -c . "$T/tmp-seen") $(ls -A "$T/gtmp" | wc -l | tr -d ' ')" "cancel 1 1 0"

# Each answer through a stand-in zenity on a simulated Linux desktop.
cat > "$T/bin/zenity" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" >> "$STUB_ARGS"
case "$STUB_ANSWER" in
  sleep) sleep 30 ;;
  fail) exit 3 ;;
  close) exit 1 ;;
  *) for a in "$@"; do case "$a" in "$STUB_ANSWER"*) printf '%s\n' "$a"; exit 0 ;; esac; done; exit 1 ;;
esac
EOF
chmod +x "$T/bin/zenity"
ENG=node
# The window is a stand-in's, so CLAUDE_HTML_NO_SCREEN (lib.sh) is off for it.
# An answered dialog is given a long limit: only the two "nobody answers"
# cases set a short one, so a busy machine cannot turn an answer into a timeout.
dlg() {  # answer kind note [env…]
  local a="$1" k="$2" f="$3"; shift 3
  env HOME="$H" PATH="$T/bin:$PATH" CLAUDE_HTML_CONF="$CONFF" CLAUDE_HTML_REDACT_FILE="$LIST" \
    CLAUDE_HTML_ENGINE=node CLAUDE_HTML_UNAME=Linux DISPLAY=:9 XDG_CURRENT_DESKTOP=GNOME \
    SSH_CONNECTION= SSH_TTY= STUB_ARGS="$T/stub.args" STUB_ANSWER="$a" CLAUDE_HTML_GUARD_TEST_LIMIT=120 CLAUDE_HTML_NO_SCREEN= "$@" \
    /bin/bash "$HERE/guard.sh" "$k" < "$f" 2>>"$LOG.err" | tee -a "$LOG"
}
reset; : > "$T/stub.args"
check "dialog Cancel: blocked, nothing sent" "$(dlg Cancel prompt "$T/note.secret" | grep -c 'Dropped. Nothing was sent.')" 1
check "  the dialog was asked, by kind, Cancel picked" \
  "$(grep -c '^Found:  GitHub token (1), password in a URL (1)$' "$T/stub.args") $(grep -cx TRUE "$T/stub.args") $(grep -cx 'Cancel — do not send' "$T/stub.args")" "1 1 1"
check "  nothing pending, nothing recorded" "$([ -f "$STATE" ] && echo yes || echo no) $([ -f "$LIST" ] && echo yes || echo no)" "no no"
check "dialog Allow: the prompt goes, now" "$(dlg Allow prompt "$T/note.secret")" ""
check "  nothing recorded, nothing pending" "$([ -f "$LIST" ] && echo yes || echo no) $([ -f "$STATE" ] && echo yes || echo no)" "no no"
check "  and the next time it is asked again" "$(dlg Cancel prompt "$T/note.secret" | grep -c Dropped)" 1
check "dialog Safe: the prompt goes" "$(dlg Safe prompt "$T/note.secret")" ""
check "  and two safe lines are recorded" "$(grep -c '^safe:' "$LIST")" 2
check "  the conf untouched" "$(grep -c CLAUDE_HTML_GUARD "$CONFF")" 0
check "dialog Stop: the prompt goes" "$(dlg Stop prompt "$T/note.other")" ""
check "  the conf line is off, the list as it was" "$(grep -c '^CLAUDE_HTML_GUARD="off"$' "$CONFF") $(grep -c '^safe:' "$LIST")" "1 2"
reset
check "no answer in time: the window closes, nothing is sent, the answer pending" \
  "$(dlg sleep prompt "$T/note.secret" CLAUDE_HTML_GUARD_TEST_LIMIT=2 | grep -c 'nobody answered within 2 seconds.\\n  Nothing was sent. Retype the prompt without it, or answer:  allow · safe · stop')$([ -f "$STATE" ] && echo ' pending')" "1 pending"
check "  and the stand-in dialog was closed" "$(pgrep -f "$T/bin/zenity" | wc -l | tr -d ' ')" 0
check "  and the typed word still works" "$(hook prompt "$T/note.w_cancel" | grep -c Dropped)" 1
check "a dialog that fails: the same" "$(dlg fail prompt "$T/note.secret" | grep -c 'Nothing was sent. Retype it without it')" 1
rm -f "$STATE"
check "its window closed: Cancel" "$(dlg close prompt "$T/note.secret" | grep -c 'Dropped')" 1
: > "$T/stub.args"
check "CLAUDE_HTML_GUARD_DIALOG=off: in words, no dialog" \
  "$(dlg Allow prompt "$T/note.secret" CLAUDE_HTML_GUARD_DIALOG=off | grep -c 'Nothing was sent. Retype it without it') $(grep -c . "$T/stub.args")" "1 0"
rm -f "$STATE"
check "over ssh: in words, no dialog" \
  "$(dlg Allow prompt "$T/note.secret" SSH_CONNECTION="10.0.0.1 22 10.0.0.2 22" | grep -c 'Nothing was sent. Retype it without it') $(grep -c . "$T/stub.args")" "1 0"
rm -f "$STATE"
check "with no display: in words, no dialog" \
  "$(dlg Allow prompt "$T/note.secret" DISPLAY= | grep -c 'Nothing was sent. Retype it without it') $(grep -c . "$T/stub.args")" "1 0"
rm -f "$STATE"
check "a command with no one to ask: Claude Code's own dialog asks" \
  "$(dlg Allow bash "$T/note.bash_mysql" DISPLAY= | grep -c '"permissionDecision":"ask"')" 1
rm -f "$STATE"
check "a command, dialog Allow: no decision, so Claude Code's own permission check still runs" \
  "$(dlg Allow bash "$T/note.bash_mysql")" ""
check "  and nothing left pending" "$([ -f "$STATE" ] && echo yes || echo no)" no
: > "$T/stub.args"
check "the dialog shows the command's first line, masked, quotes and all" \
  "$(dlg Allow bash "$T/note.bash_multi"; grep -c '^Command:  echo "a\\b" mysql .*\*\*\*.* …$' "$T/stub.args")" 1
check "a command, dialog Cancel: refused, Claude told how to do without" \
  "$(dlg Cancel bash "$T/note.bash_mysql" | grep -c '"permissionDecision":"deny".*~/.my.cnf')" 1
check "  the command's dialog said so" "$(grep -c "^--text=Claude's command has been interrupted$" "$T/stub.args") $(grep -cx 'Cancel — do not run' "$T/stub.args")" "2 2"
check "a command, no answer in time: refused, Claude told to stop, not retry" \
  "$(rm -f "$STATE"; dlg sleep bash "$T/note.bash_mysql" CLAUDE_HTML_GUARD_TEST_LIMIT=2 | grep -c '"deny".*nobody answered within 2 seconds. It was not run. Stop here and do not retry it')" 1
check "the dialog was never given a secret" "$(grep -cF -f "$T/probes.txt" "$T/stub.args")" 0
check "nothing printed or kept holds a secret" "$(leaks)" 0

# ── what the window is given, and what is left after it ───────────────
# The boxes show the secret itself, on the owner's own screen. So it must
# never be an argument of the window (any local process reads those), nor
# in its environment, nor left on disk once the window has closed, nor in
# anything kept. Stand-ins for osascript (a Mac, simulated) and zenity
# (Linux) record what they were given: their arguments, their environment,
# and the files they were pointed to, which are compared with what the
# boxes must show, worked out on their own by guard.test.js.
REC="$T/rec"; GT="$T/gtmp2"; mkdir -p "$T/binmac" "$T/binlin" "$GT"
cat > "$T/binmac/osascript" <<'STUB'
#!/bin/bash
# Only the window: anything else asked of osascript is not here.
case "$*" in *dialog.js*) ;; *) exit 1 ;; esac
mkdir -p "$STUB_REC"; n=$(( $(cat "$STUB_REC/n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$STUB_REC/n"
printf '%s\n' "$@" > "$STUB_REC/argv.$n"; env > "$STUB_REC/env.$n"
while [ $# -gt 0 ]; do
  case "$1" in
    --box|--pre)
      k="${2%:}"; echo "$3" >> "$STUB_REC/files"
      ls -ld "${3%/*}" "$3" 2>/dev/null | cut -c1-10 | tr '\n' ' ' >> "$STUB_REC/modes"
      [ -f "$3" ] && cat "$3" > "$STUB_REC/content.$k"
      # As the window does: read, then deleted at once.
      [ -n "$STUB_KEEP" ] || rm -f "$3"
      shift 3 ;;
    *) shift ;;
  esac
done
case "$STUB_ANSWER" in sleep) sleep 30 ;; fail) exit 3 ;; *) echo "$STUB_ANSWER" ;; esac
STUB
printf '#!/bin/sh\necho Aqua\n' > "$T/binmac/launchctl"
cat > "$T/binlin/zenity" <<'STUB'
#!/bin/sh
mkdir -p "$STUB_REC"; n=$(( $(cat "$STUB_REC/n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$STUB_REC/n"
printf '%s\n' "$@" > "$STUB_REC/argv.$n"; env > "$STUB_REC/env.$n"
for a in "$@"; do
  case "$a" in --filename=*)
    f="${a#--filename=}"; echo "$f" >> "$STUB_REC/files"
    ls -ld "${f%/*}" "$f" 2>/dev/null | cut -c1-10 | tr '\n' ' ' >> "$STUB_REC/modes"
    cat "$f" > "$STUB_REC/content.details" ;;
  esac
done
[ "$1" = --text-info ] && exit 0
# The first time, Details, when asked to: then the question again.
if [ "$n" = 1 ] && [ -n "$STUB_DETAILS" ]; then echo Details; exit 1; fi
case "$STUB_ANSWER" in
  sleep) sleep 30 ;; fail) exit 3 ;;
  *) for a in "$@"; do case "$a" in "$STUB_ANSWER"*) printf '%s\n' "$a"; exit 0 ;; esac; done; exit 1 ;;
esac
STUB
chmod +x "$T/binmac/osascript" "$T/binmac/launchctl" "$T/binlin/zenity"
# A stand-in's window again: CLAUDE_HTML_NO_SCREEN off for it.
win() {  # mac|linux answer kind note [env…]
  local os="$1" a="$2" k="$3" f="$4"; shift 4
  rm -rf "$REC"; mkdir -p "$REC"
  if [ "$os" = mac ]; then set -- CLAUDE_HTML_UNAME=Darwin PATH="$T/binmac:$PATH" "$@"
  else set -- CLAUDE_HTML_UNAME=Linux DISPLAY=:9 XDG_CURRENT_DESKTOP=GNOME PATH="$T/binlin:$PATH" "$@"; fi
  env HOME="$H" CLAUDE_HTML_CONF="$CONFF" CLAUDE_HTML_REDACT_FILE="$LIST" CLAUDE_HTML_ENGINE=node \
    SSH_CONNECTION= SSH_TTY= TMPDIR="$GT" STUB_REC="$REC" STUB_ANSWER="$a" STUB_DETAILS= STUB_KEEP= CLAUDE_HTML_NO_SCREEN= \
    CLAUDE_HTML_GUARD_TEST_LIMIT=120 "$@" /bin/bash "$HERE/guard.sh" "$k" < "$f" 2>>"$LOG.err" | tee -a "$LOG"
}
# What must hold after every window: nothing of it left, and no secret
# where it must not be.
after() {
  local gone=yes f
  while IFS= read -r f; do if [ -e "$f" ] || [ -e "${f%/*}" ]; then gone=no; fi; done < <(cat "$REC/files" 2>/dev/null)
  printf '%s tmp:%s argv:%s env:%s kept:%s' "$gone" "$(ls -A "$GT" | wc -l | tr -d ' ')" \
    "$(cat "$REC"/argv.* 2>/dev/null | grep -cF -f "$T/probes.txt")" \
    "$(cat "$REC"/env.* 2>/dev/null | grep -cF -f "$T/probes.txt")" "$(leaks)"
}
CLEAN="yes tmp:0 argv:0 env:0 kept:0"
EXP="$T/expect"; mkdir -p "$EXP/heredoc" "$EXP/prompt"
node "$HERE/tests/guard.test.js" expect "$T/note.bash_heredoc" bash "$EXP/heredoc"
node "$HERE/tests/guard.test.js" expect "$T/note.secret" prompt "$EXP/prompt"

reset
R="$(win mac cancel bash "$T/note.bash_heredoc")"
check "Mac, a long command, Cancel: refused" "$(printf '%s' "$R" | grep -c '"permissionDecision":"deny"')" 1
check "  the window was given two private files, its time limit, and the first line masked" \
  "$(grep -c '^--box$' "$REC/argv.1") $(grep -c '^--pre$' "$REC/argv.1") $(grep -cx -- '--limit' "$REC/argv.1") $(grep -c '^cat > deploy.sh <<.EOF. …$' "$REC/argv.1")" "1 1 1 1"
check "  each readable by its owner only, in a folder of its own" "$(cat "$REC/modes")" "drwx------ -rw------- drwx------ -rw------- "
check "  Found: each match with 40 characters around it, marked, one a line" \
  "$(cmp -s "$REC/content.Found" "$EXP/heredoc/found" && echo same)" same
check "  Command: the whole command, every line, as Claude wrote it" \
  "$(cmp -s "$REC/content.Command" "$EXP/heredoc/command" && echo same) $(tr -d '\001\002' < "$REC/content.Command" | grep -c .)" "same 30"
check "  never an argument, nor in its environment; nothing left, nothing kept" "$(after)" "$CLEAN"
rm -f "$REC"/content.*
reset; R="$(win mac allow bash "$T/note.bash_heredoc")"
check "Mac, Allow: no decision; nothing left, nothing kept" "${R:-none} $(after)" "none $CLEAN"
reset; R="$(win mac safe bash "$T/note.bash_heredoc")"
check "Mac, Safe: recorded by fingerprint; nothing left, nothing kept" "${R:-none} $(grep -c '^safe:' "$LIST") $(after)" "none 1 $CLEAN"
reset; R="$(win mac stop bash "$T/note.bash_heredoc")"
check "Mac, Stop: the check off; nothing left, nothing kept" "${R:-none} $(grep -c '^CLAUDE_HTML_GUARD="off"$' "$CONFF") $(after)" "none 1 $CLEAN"
reset; R="$(win mac timeout bash "$T/note.bash_heredoc")"
check "Mac, closed by itself at 0:00: refused as nobody answered; nothing left" \
  "$(printf '%s' "$R" | grep -c 'nobody answered within 2 minutes') $(after)" "1 $CLEAN"
reset; R="$(win mac fail bash "$T/note.bash_heredoc")"
check "Mac, the window failed: Claude Code's own dialog asks; nothing left" "$(printf '%s' "$R" | grep -c '"ask"') $(after)" "1 $CLEAN"
reset; R="$(win mac cancel bash "$T/note.bash_heredoc" STUB_KEEP=1)"
check "  a window that died before reading its files: they go with the hook all the same" "$(after)" "$CLEAN"
reset; R="$(win mac sleep bash "$T/note.bash_heredoc" CLAUDE_HTML_GUARD_TEST_LIMIT=1)"
check "  a window that never closed: closed from outside, refused, nothing left" \
  "$(printf '%s' "$R" | grep -c 'nobody answered within 1 second') $(after)" "1 $CLEAN"
check "  and it is not running any more" "$(pgrep -f "$T/binmac/osascript" | wc -l | tr -d ' ')" 0
rm -f "$REC"/content.*
reset; R="$(win mac cancel prompt "$T/note.secret")"
check "Mac, a prompt: Found's box only, what was found in its context" \
  "$(grep -c '^--box$' "$REC/argv.1") $(grep -c '^--pre$' "$REC/argv.1") $(cmp -s "$REC/content.Found" "$EXP/prompt/found" && echo same)" "1 0 same"
check "  nothing left, nothing kept" "$(after)" "$CLEAN"
rm -f "$REC"/content.*

reset; R="$(win linux Cancel bash "$T/note.bash_heredoc" STUB_DETAILS=1)"
check "Linux, Details then Cancel: the question, its text window, the question again; refused" \
  "$(cat "$REC/n") $(grep -c '^--extra-button=Details$' "$REC/argv.1") $(head -1 "$REC/argv.2") $(grep -c '^--extra-button=Details$' "$REC/argv.3") $(printf '%s' "$R" | grep -c '"deny"')" \
  "3 1 --text-info 1 1"
check "  the text window read the private file: what was found, then the whole command" \
  "$(cmp -s "$REC/content.details" "$EXP/heredoc/details.txt" && echo same) $(cat "$REC/modes")" "same drwx------ -rw------- "
check "  the question's text: kinds, the first line masked, the time limit, never a secret" \
  "$(grep -c '^Closes after 2 minutes — counts as Cancel.$' "$REC/argv.1") $(grep -c '^Command:  cat > deploy.sh' "$REC/argv.1")" "1 1"
check "  never an argument, nor in its environment; nothing left, nothing kept" "$(after)" "$CLEAN"
rm -f "$REC"/content.*
reset; R="$(win linux Allow bash "$T/note.bash_heredoc")"
check "Linux, Allow: no decision; nothing left" "${R:-none} $(after)" "none $CLEAN"
reset; R="$(win linux sleep prompt "$T/note.secret" CLAUDE_HTML_GUARD_TEST_LIMIT=1)"
check "Linux, nobody answers: closed, nothing left" "$(printf '%s' "$R" | grep -c 'nobody answered within 1 second') $(after)" "1 $CLEAN"
reset; R="$(win linux fail prompt "$T/note.secret")"
check "Linux, the dialog failed: in words; nothing left" "$(printf '%s' "$R" | grep -c 'Retype it without it') $(after)" "1 $CLEAN"
rm -rf "$REC" "$EXP"

# The setting, through the hook as Claude Code runs it, under each engine:
# the conf's CLAUDE_HTML_GUARD_WAIT is the window's --limit and the words
# when nobody answers. A stand-in osascript for the window; anything else
# asked of osascript (the engine itself) goes to the real one.
mkdir -p "$T/binmac2"; cp "$T/binmac/launchctl" "$T/binmac2/"
sed 's|^case "\$\*" in \*dialog.js\*) ;; \*) exit 1 ;; esac$|case "$*" in *dialog.js*) ;; *) exec /usr/bin/osascript "$@" ;; esac|' "$T/binmac/osascript" > "$T/binmac2/osascript"
chmod +x "$T/binmac2/osascript"
for ENG in $ENGINES; do
  reset; printf 'CLAUDE_HTML_GUARD_WAIT="45s"\n' >> "$CONFF"
  R="$(win mac timeout bash "$T/note.bash_heredoc" PATH="$T/binmac2:$PATH" CLAUDE_HTML_ENGINE="$ENG" CLAUDE_HTML_GUARD_TEST_LIMIT=)"
  check "$ENG: the conf's wait is the window's limit, and the words when nobody answers" \
    "$(grep -A1 -x -- '--limit' "$REC/argv.1" | tail -1) $(printf '%s' "$R" | grep -c 'nobody answered within 45 seconds')" "45 1"
  reset; printf 'CLAUDE_HTML_GUARD_WAIT="1m"\nCLAUDE_HTML_GUARD_WAIT="99"\n' >> "$CONFF"
  R="$(win mac timeout prompt "$T/note.secret" PATH="$T/binmac2:$PATH" CLAUDE_HTML_ENGINE="$ENG" CLAUDE_HTML_GUARD_TEST_LIMIT=)"
  check "  the conf's last line wins, as a shell reads it: 99 seconds" \
    "$(grep -A1 -x -- '--limit' "$REC/argv.1" | tail -1) $(printf '%s' "$R" | grep -c 'nobody answered within 99 seconds')" "99 1"
done
reset

# The window's answer comes once it has closed, up to an hour after what
# it answers was put on record: it must still find it. Each engine runs
# guard.js as the hook does.
gj() { if [ "$1" = osascript ]; then shift; osascript -l JavaScript "$HERE/actions/guard.js" "$@"; else shift; node "$HERE/actions/guard.js" "$@"; fi; }
age() { node -e 'var f=process.argv[1],s=JSON.parse(require("fs").readFileSync(f));s.pending.time-=process.argv[2]*1000;require("fs").writeFileSync(f,JSON.stringify(s))' "$STATE" "$1"; }
mkdir -p "$(dirname "$STATE")" "$T/ddj"
for ENG in $ENGINES; do
  reset
  gj "$ENG" prompt "$HERE" "$STATE" "$LIST" "$CONFF" dialog "$T/ddj" < "$T/note.secret" >/dev/null
  age 3590
  check "$ENG: an hour's window, unanswered: still stopped, not let through" \
    "$(gj "$ENG" answer-prompt "$HERE" "$STATE" "$LIST" "$CONFF" timeout 3600 < "$T/note.secret" | grep -c 'nobody answered within 60 minutes')" 1
  check "  and the words answer it, ten minutes from the window's closing" \
    "$(gj "$ENG" prompt "$HERE" "$STATE" "$LIST" "$CONFF" < "$T/note.w_cancel" 2>/dev/null | grep -c 'Dropped. Nothing was sent.')" 1
done
reset

# ── what safe and allow mean for the saved pages ─────────────────────
# A safe value is shown in the pages; one allowed once stays masked. And
# with safe lines in the list, both engines still write the same bytes,
# and a build carried on from the last writes what one from nothing does.
B="$T/build"; APP="$B/root/app"; PROJ="$B/home/.claude/projects/$(printf '%s' "$APP" | tr '/' '-')"
mkdir -p "$PROJ" "$APP"
SID=5ec1e7a1-0000-4000-8000-0000000000b1
TOK="$(node -e 'var F=require(process.argv[1]); process.stdout.write(F.cases.filter(function(c){return c.rule==="github"})[0].secret)' "$HERE/tests/fixtures/fake-secrets.js")"
node -e '
var fs=require("fs"), P=process.argv[1], A=process.argv[2], S=process.argv[3], tok=process.argv[4];
function l(o){return JSON.stringify(o)+"\n";}
var t=l({type:"user",cwd:A,sessionId:S,uuid:"u1",timestamp:"2026-11-02T09:00:00Z",message:{role:"user",content:"deploy with "+tok}})+
  l({type:"assistant",cwd:A,sessionId:S,uuid:"a1",timestamp:"2026-11-02T09:01:00Z",message:{id:"m1",role:"assistant",model:"claude-opus-5",content:[{type:"text",text:"done, the token "+tok+" works"}]}});
for (var i=0;i<30;i++) t+=l({type:"user",cwd:A,sessionId:S,uuid:"q"+i,timestamp:"2026-11-02T09:0"+(i%10)+":00Z",message:{role:"user",content:"question "+i}});
fs.writeFileSync(P+"/"+S+".jsonl",t);' "$PROJ" "$APP" "$SID" "$TOK"
BJ="$PROJ/$SID.jsonl"; BL="$B/list.redact"
# The transcript's time is part of what a page says, so it is held still.
touch -t 202611020910 "$BJ"
bld() {  # out engine
  local o="$1"; shift
  env HOME="$B/home" CLAUDE_HTML_REDACT_FILE="$BL" CLAUDE_HTML_ENGINE="$1" /bin/bash -c \
    '. "$0/lib/platform.sh"; ch_pick_engine; ch_js "$0/build/convert.js" "$1"' "$HERE" \
    "{\"root\":\"$B/root\",\"out\":\"$o\",\"here\":\"$HERE\",\"exportPath\":\"/nonexistent\"}" >/dev/null 2>&1
}
tree() { (cd "$1" && find . -type f | sort | while IFS= read -r f; do printf '%s %s\n' "$f" "$(sed 's/"built":[0-9]*,/"built":0,/' "$f" | cksum)"; done); }
: > "$BL"; bld "$B/o-none" node
check "a value allowed once is masked in the pages" "$(grep -rlF "$TOK" "$B/o-none" | wc -l | tr -d ' ')" 0
SALT=0123456789abcdef
printf 'safe:%s:%s   # github, 2026-11-19\n' "$SALT" \
  "$(node -e 'var s=require("fs").readFileSync(process.argv[1],"utf8"); process.stdout.write(new Function(s+"\nreturn fingerprint;")()(process.argv[2],process.argv[3]))' "$HERE/build/redact.js" "$SALT" "$TOK")" > "$BL"
bld "$B/o-safe" node
check "a safe value is shown in the pages" "$(grep -c "deploy with $TOK" "$B/o-safe/sessions/$SID.html")" 1
check "  where it was masked before: the signature made the page again" \
  "$([ "$(tree "$B/o-none")" != "$(tree "$B/o-safe")" ] && echo rebuilt)" rebuilt
if [ "$HAVE_OSASCRIPT" = true ]; then
  bld "$B/o-safe-osa" osascript
  check "  osascript writes the same bytes as node" "$([ "$(tree "$B/o-safe")" = "$(tree "$B/o-safe-osa")" ] && echo same)" same
fi
cp -p "$BJ" "$B/whole"; head -c 900 "$B/whole" > "$BJ"; touch -t 202611020905 "$BJ"
bld "$B/o-inc" node; cp -p "$B/whole" "$BJ"; bld "$B/o-inc" node
check "  and a build carried on writes what one from nothing does" \
  "$([ "$(tree "$B/o-inc")" = "$(tree "$B/o-safe")" ] && echo same)" same

# ── the command ──────────────────────────────────────────────────────
reset
printf 'safe:0123456789abcdef:0123456789abcdef0123456789abcdef   # github, 2026-11-19\n' > "$LIST"
cli() { env HOME="$H" CLAUDE_HTML_CONF="$CONFF" CLAUDE_HTML_REDACT_FILE="$LIST" CLAUDE_HTML_NO_REGISTER=1 \
          /bin/bash "$HERE/claude-html" "$@" 2>&1; }
G="$(cli --guard status)"
check "--guard status: the mode and the safe values, by rule and date only" \
  "$(printf '%s\n' "$G" | grep -c '^guard on · 1 safe value(s) · hooks 0 of 2') $(printf '%s\n' "$G" | grep -cx '  safe  github, 2026-11-19') $(printf '%s' "$G" | grep -c 0123456789abcdef)" "1 1 0"
check "--guard status with no list file says 0, not a blank" \
  "$(env HOME="$H" CLAUDE_HTML_CONF="$CONFF" CLAUDE_HTML_REDACT_FILE="$H/no-such-list" CLAUDE_HTML_NO_REGISTER=1 \
       /bin/bash "$HERE/claude-html" --guard status 2>&1 | grep -c '^guard on · 0 safe value(s) · ')" 1
cli --guard prompt >/dev/null
check "--guard prompt: its one line in the conf" "$(grep -c '^CLAUDE_HTML_GUARD="prompt"$' "$CONFF") $(grep -c '^CLAUDE_HTML_ROOT=' "$CONFF")" "1 1"
cli --guard off >/dev/null
check "--guard off: the same line" "$(grep -c '^CLAUDE_HTML_GUARD=' "$CONFF") $(grep -c '"off"' "$CONFF")" "1 1"
check "--doctor has a guard line" "$(cli --doctor | grep -c '^  guard off · 1 safe value(s)')" 1
check "--guard with anything else says how to use it" "$(cli --guard maybe) $(cli --guard maybe >/dev/null; echo $?)" "claude-html --guard on|prompt|off|status|wait 2"

# --guard wait: shown, set through the conf writer after it is checked,
# and taken out again.
wcli() { env -u CLAUDE_HTML_GUARD_WAIT -u CLAUDE_HTML_GUARD_TEST_LIMIT HOME="$H" CLAUDE_HTML_CONF="$CONFF" CLAUDE_HTML_REDACT_FILE="$LIST" \
           CLAUDE_HTML_NO_REGISTER=1 /bin/bash "$HERE/claude-html" "$@" 2>&1; }
W="$(wcli --guard wait)"
check "--guard wait: the wait, the default, and the range" \
  "$(printf '%s\n' "$W" | grep -c "^The guard's windows wait 1 minute (the default), then close as Cancel.$") $(printf '%s\n' "$W" | grep -c 'from 30 seconds to 60 minutes, written 45, 45s, 2m or 1m30s')" "1 1"
check "--guard wait 2m: set in the conf, the rest kept" \
  "$(wcli --guard wait 2m | grep -c 'wait 2 minutes') $(grep -c '^CLAUDE_HTML_GUARD_WAIT="2m"$' "$CONFF") $(grep -c '^CLAUDE_HTML_ROOT=' "$CONFF")" "1 1 1"
check "  then shown, from the conf" "$(wcli --guard wait | grep -c "^The guard's windows wait 2 minutes (CLAUDE_HTML_GUARD_WAIT in $CONFF), then close as Cancel.$")" 1
check "  and in the guard's line" "$(wcli --guard status | grep -c '^guard off · .* · waits 2 minutes · ')" 1
cp "$CONFF" "$T/conf.before"
for v in 29s 61m 3601 abc 1m90s ""; do
  R="$(wcli --guard wait "$v")"; rc=$?
  [ -n "$v" ] || { R="$(wcli --guard wait 2m 3m)"; rc=$?; v="two words"; }
  check "--guard wait $v: refused, the conf unchanged" \
    "$rc $(printf '%s' "$R" | grep -c -e '^not a wait: ' -e '^out of range: ' -e '^claude-html --guard wait \[') $(cmp -s "$CONFF" "$T/conf.before" && echo same)" "2 1 same"
done
check "  out of range is said so" "$(wcli --guard wait 61m)" "out of range: 61m — from 30 seconds to 60 minutes, written 45, 45s, 2m or 1m30s; nothing was changed"
printf 'CLAUDE_HTML_GUARD_WAIT="10 minutes"\n' >> "$CONFF"
check "a bad wait in the conf: the default, and said where the guard is reported" \
  "$(wcli --guard wait | grep -c "^The guard's windows wait 1 minute (the default)") $(wcli --guard status | grep -c '^  Ignored  CLAUDE_HTML_GUARD_WAIT="10 minutes" (in .*): not a wait, ') $(wcli --doctor | grep -c '^    Ignored  CLAUDE_HTML_GUARD_WAIT="10 minutes"')" "1 1 1"
check "--guard wait default: every line of it out, the rest kept" \
  "$(wcli --guard wait default | grep -c 'the default, 1 minute') $(grep -c 'CLAUDE_HTML_GUARD_WAIT' "$CONFF") $(grep -c '^CLAUDE_HTML_ROOT=' "$CONFF") $(wcli --guard wait | grep -c '(the default)')" "1 0 1 1"
check "  the environment's wins, and is said to" \
  "$(env CLAUDE_HTML_GUARD_WAIT=45 HOME="$H" CLAUDE_HTML_CONF="$CONFF" CLAUDE_HTML_REDACT_FILE="$LIST" /bin/bash "$HERE/claude-html" --guard wait 2m | grep -c 'environment wins over the conf, so here they wait 45 seconds')" 1
wcli --guard wait default >/dev/null

# ── beside the limits (limits.sh) ────────────────────────────────────
# The same prompt hook stops a prompt by the owner's weekly rule before the
# secret check; let through, it still meets the secret check.
reset; ENG=node
LNOW=1795267740; LR=1795503600
printf 'asof=%s\nweek_pct=81\nweek_reset=%s\nplan_seen=%s\n' "$LNOW" "$LR" "$LNOW" > "$H/.claude/.claude-html.limits"
printf 'CLAUDE_HTML_LIMIT_RULES="fri 20:00 80%%"\n' >> "$CONFF"
lh() { hook prompt "$1" CLAUDE_HTML_TEST_NOW="$LNOW" TZ=Europe/Zurich; }
check "a rule in force, a secret in the prompt: the rule asks first" \
  "$(lh "$T/note.secret" | grep -c 'weekly limit rule reached')" 1
SIDL="$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).session_id)' "$T/note.secret")"
printf '{"session_id":"%s","prompt":"allow"}' "$SIDL" > "$T/note.lallow"
check "  allowed once, the secret check still stops it" \
  "$(lh "$T/note.lallow" | grep -c 'Allowed once') $(lh "$T/note.secret" | grep -c 'sensitive information detected')" "1 1"
rm -f "$H/.claude/.claude-html-guard/limits-$SIDL"
check "  and with the guard off, the rule still stops a prompt" \
  "$(hook prompt "$T/note.clean" CLAUDE_HTML_TEST_NOW="$LNOW" TZ=Europe/Zurich CLAUDE_HTML_GUARD=off | grep -c 'weekly limit rule reached')" 1
check "  a sub-agent's report is never stopped by a rule" "$(lh "$T/note.notify")" ""
check "  a command is never stopped by a rule" "$(hook bash "$T/note.bash_clean" CLAUDE_HTML_TEST_NOW="$LNOW" TZ=Europe/Zurich)" ""
rm -f "$H/.claude/.claude-html.limits" "$H/.claude/.claude-html.limits-marks"; rm -rf "$H/.claude/.claude-html-guard"

# ── installed beside what is there, once ─────────────────────────────
S="$T/settings.json"
printf '{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"theirs.sh"}]}]}}\n' > "$S"
node "$HERE/actions/settings-hooks.js" "$S" "$HERE" add >/dev/null
node "$HERE/actions/settings-hooks.js" "$S" "$HERE" add >/dev/null
check "install adds the two guard hooks once, beside the user's" \
  "$(grep -c 'guard.sh' "$S") $(grep -c 'theirs.sh' "$S") $(grep -c '"matcher": "Bash"' "$S")" "2 1 1"
check "  with a timeout past the longest wait, 60 minutes" "$(grep -A2 'guard.sh' "$S" | grep -c '"timeout": 3660')" 2
# An install from when the window waited ten minutes: its two at 660.
node -e 'var fs=require("fs"),p=process.argv[1],s=JSON.parse(fs.readFileSync(p,"utf8"));
  ["UserPromptSubmit","PreToolUse"].forEach(function(e){s.hooks[e].forEach(function(g){g.hooks.forEach(function(h){
    if (/guard\.sh/.test(h.command)) h.timeout=660;});});});
  fs.writeFileSync(p,JSON.stringify(s,null,2))' "$S"
R="$(node "$HERE/actions/settings-hooks.js" "$S" "$HERE" add)"
check "an older install's 660 is set to 3660 where it stands, nothing added" \
  "$(grep -c 'guard.sh' "$S") $(grep -A2 'guard.sh' "$S" | grep -c '"timeout": 3660') $(grep -c '"timeout": 660' "$S") $(grep -c 'theirs.sh' "$S")" "2 2 0 1"
check "  and the installer says so" "$(printf '%s' "$R" | grep -c '"UserPromptSubmit timeout 3660","PreToolUse/Bash timeout 3660"')" 1
check "  a second run finds nothing to do" "$(node "$HERE/actions/settings-hooks.js" "$S" "$HERE" add | grep -c timeout)" 0
node "$HERE/actions/settings-hooks.js" "$S" "$HERE" add no-guard >/dev/null
check "--no-guard leaves them out, and takes out ones already there" "$(grep -c 'guard.sh' "$S") $(grep -c 'theirs.sh' "$S")" "0 1"
node "$HERE/actions/settings-hooks.js" "$S" "$HERE" add >/dev/null
node "$HERE/actions/settings-hooks.js" "$S" "$HERE" remove >/dev/null
check "uninstall removes only its own" "$(grep -c 'guard.sh\|save-conversation' "$S") $(grep -c 'theirs.sh' "$S")" "0 1"

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
