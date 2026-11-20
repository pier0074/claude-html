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
. "$HERE/platform.sh"
H="$T/home"; mkdir -p "$H/.claude" "$T/bin"
LOG="$T/log"; : > "$LOG"
LIST="$H/.claude/claude-html.redact"; CONFF="$H/.claude/claude-html.conf"; STATE="$H/.claude/.claude-html.guard"
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
leaks() { grep -rlF -f "$T/probes.txt" "$H" "$LOG" "$LOG.err" 2>/dev/null | wc -l | tr -d ' '; }

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

  # ── the four words ─────────────────────────────────────────────────
  R="$(hook prompt "$T/note.secret")"
  check "$ENG: a prompt with two kinds is stopped, by kind and count" \
    "$(printf '%s' "$R" | grep -c 'GitHub token (1), password in a URL (1)')" 1
  check "$ENG:   leaving its fingerprints pending, readable by its owner only" \
    "$(ls -l "$STATE" | cut -c1-10) $(grep -c '"rule":"github"' "$STATE")" "-rw------- 1"
  check "$ENG: cancel drops it" "$(hook prompt "$T/note.w_cancel" | grep -c 'Dropped. Nothing was sent.')" 1
  check "$ENG:   and nothing is pending" "$([ -f "$STATE" ] && echo yes || echo no)" no

  hook prompt "$T/note.secret" >/dev/null
  check "$ENG: allow (any case, spaces) lets it go once" \
    "$(hook prompt "$T/note.w_allow" | grep -c 'Allowed once. Press')" 1
  check "$ENG:   writing nothing to the list" "$([ -f "$LIST" ] && grep -c . "$LIST" || echo 0)" 0
  check "$ENG:   only in its own session" "$(blocked "$(hook prompt "$T/note.secret2")")" blocked
  hook prompt "$T/note.secret" >/dev/null; hook prompt "$T/note.w_allow" >/dev/null
  check "$ENG:   then the same prompt passes" "$(blocked "$(hook prompt "$T/note.secret")")" passed
  check "$ENG:   once: the next time it is stopped again" "$(blocked "$(hook prompt "$T/note.secret")")" blocked

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
  mkdir -p "$T/broken"; cp "$HERE"/guard.sh "$HERE"/guard.js "$HERE"/conf.sh "$HERE"/platform.sh "$T/broken/"
  printf 'syntax error (' > "$T/broken/redact.js"
  R="$(env HOME="$H" CLAUDE_HTML_CONF="$CONFF" CLAUDE_HTML_REDACT_FILE="$LIST" CLAUDE_HTML_ENGINE="$ENG" \
       CLAUDE_HTML_GUARD_DIALOG=off /bin/bash "$T/broken/guard.sh" prompt < "$T/note.secret" 2>&1; echo "exit $?")"
  check "$ENG: a broken redact.js lets the prompt through, saying nothing" "$R" "exit 0"
  rm -f "$T/broken/redact.js"
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
for d in osascript zenity yad kdialog xmessage; do
  CH_DIALOG=$d CH_HERE="$HERE" CH_DRY=1 ch_choose prompt Weather "GitHub token (1)" > "$T/dry.$d"
done
NL='
'
TEXT="Your prompt has been interrupted${NL}Sensitive information detected${NL}${NL}Where:  your prompt in Claude Code  ·  project Weather${NL}Found:  GitHub token (1)"
CH4="'Cancel — do not send' 'FALSE' 'Allow once — it is sensitive, send it this time only' 'FALSE' 'Safe — it is not sensitive, send it and never ask again' 'FALSE' 'Stop — turn this check off'"
check "macOS: a window of osascript's own, told the kind and the project only" \
  "$(cat "$T/dry.osascript")" "'osascript' '-l' 'JavaScript' '$HERE/dialog.js' 'prompt' 'Weather' 'GitHub token (1)'"
check "zenity: a radio list, Cancel picked, OK" \
  "$(cat "$T/dry.zenity")" "'zenity' '--list' '--radiolist' '--title=claude-html' '--no-markup' '--text=$TEXT' '--ok-label=OK' '--column= ' '--column=Choice' 'TRUE' $CH4"
check "yad: the same" \
  "$(cat "$T/dry.yad")" "'yad' '--list' '--radiolist' '--title=claude-html' '--text=$TEXT' '--print-column=2' '--separator=' '--button=OK:0' '--column= ' '--column=Choice' 'TRUE' $CH4"
check "kdialog: a radio list, Cancel on" \
  "$(cat "$T/dry.kdialog")" "'kdialog' '--title' 'claude-html' '--ok-label' 'OK' '--radiolist' '$TEXT' 'cancel' 'Cancel — do not send' 'on' 'allow' 'Allow once — it is sensitive, send it this time only' 'off' 'safe' 'Safe — it is not sensitive, send it and never ask again' 'off' 'stop' 'Stop — turn this check off' 'off'"
check "xmessage: four buttons, Cancel the default" \
  "$(cat "$T/dry.xmessage")" "'xmessage' '-center' '-title' 'claude-html' '-buttons' 'Cancel:1,Allow once:2,Safe:3,Stop:4' '-default' 'Cancel' '$TEXT'"
check "a command's dialog says run, not send" \
  "$(CH_DIALOG=zenity CH_DRY=1 ch_choose bash Weather "MySQL password (1)" | tr '\n' ' ' | grep -c "command has been interrupted.*'TRUE' 'Cancel — do not run' 'FALSE' 'Allow once — it is sensitive, run it this time only'")" 1

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
dlg() {  # answer kind note [env…]
  local a="$1" k="$2" f="$3"; shift 3
  env HOME="$H" PATH="$T/bin:$PATH" CLAUDE_HTML_CONF="$CONFF" CLAUDE_HTML_REDACT_FILE="$LIST" \
    CLAUDE_HTML_ENGINE=node CLAUDE_HTML_UNAME=Linux DISPLAY=:9 XDG_CURRENT_DESKTOP=GNOME \
    SSH_CONNECTION= SSH_TTY= STUB_ARGS="$T/stub.args" STUB_ANSWER="$a" CLAUDE_HTML_GUARD_TEST_LIMIT=2 "$@" \
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
  "$(dlg sleep prompt "$T/note.secret" | grep -c 'nobody answered within 2 seconds.\\n  Nothing was sent. Retype the prompt without it, or answer:  allow · safe · stop')$([ -f "$STATE" ] && echo ' pending')" "1 pending"
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
check "a command, dialog Allow: allowed" "$(dlg Allow bash "$T/note.bash_mysql" | grep -c '"permissionDecision":"allow"')" 1
check "a command, dialog Cancel: refused, Claude told how to do without" \
  "$(dlg Cancel bash "$T/note.bash_mysql" | grep -c '"permissionDecision":"deny".*~/.my.cnf')" 1
check "  the command's dialog said so" "$(grep -c "^--text=Claude's command has been interrupted$" "$T/stub.args") $(grep -cx 'Cancel — do not run' "$T/stub.args")" "2 2"
check "a command, no answer in time: refused, Claude told to stop, not retry" \
  "$(rm -f "$STATE"; dlg sleep bash "$T/note.bash_mysql" | grep -c '"deny".*nobody answered within 2 seconds. It was not run. Stop here and do not retry it')" 1
check "the dialog was never given a secret" "$(grep -cF -f "$T/probes.txt" "$T/stub.args")" 0
check "nothing printed or kept holds a secret" "$(leaks)" 0

# ── what safe and allow mean for the saved pages ─────────────────────
# A safe value is shown in the pages; one allowed once stays masked. And
# with safe lines in the list, both engines still write the same bytes,
# and a build carried on from the last writes what one from nothing does.
B="$T/build"; APP="$B/root/app"; PROJ="$B/home/.claude/projects/$(printf '%s' "$APP" | tr '/' '-')"
mkdir -p "$PROJ" "$APP"
SID=5ec1e7a1-0000-4000-8000-0000000000b1
TOK="$(node -e 'var F=require(process.argv[1]); process.stdout.write(F.cases.filter(function(c){return c.rule==="github"})[0].secret)' "$HERE/tests/fake-secrets.js")"
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
    '. "$0/platform.sh"; ch_pick_engine; ch_js "$0/convert.js" "$1"' "$HERE" \
    "{\"root\":\"$B/root\",\"out\":\"$o\",\"here\":\"$HERE\",\"exportPath\":\"/nonexistent\"}" >/dev/null 2>&1
}
tree() { (cd "$1" && find . -type f | sort | while IFS= read -r f; do printf '%s %s\n' "$f" "$(sed 's/"built":[0-9]*,/"built":0,/' "$f" | cksum)"; done); }
: > "$BL"; bld "$B/o-none" node
check "a value allowed once is masked in the pages" "$(grep -rlF "$TOK" "$B/o-none" | wc -l | tr -d ' ')" 0
SALT=0123456789abcdef
printf 'safe:%s:%s   # github, 2026-11-19\n' "$SALT" \
  "$(node -e 'var s=require("fs").readFileSync(process.argv[1],"utf8"); process.stdout.write(new Function(s+"\nreturn fingerprint;")()(process.argv[2],process.argv[3]))' "$HERE/redact.js" "$SALT" "$TOK")" > "$BL"
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
cli --guard prompt >/dev/null
check "--guard prompt: its one line in the conf" "$(grep -c '^CLAUDE_HTML_GUARD="prompt"$' "$CONFF") $(grep -c '^CLAUDE_HTML_ROOT=' "$CONFF")" "1 1"
cli --guard off >/dev/null
check "--guard off: the same line" "$(grep -c '^CLAUDE_HTML_GUARD=' "$CONFF") $(grep -c '"off"' "$CONFF")" "1 1"
check "--doctor has a guard line" "$(cli --doctor | grep -c '^  guard off · 1 safe value(s)')" 1
check "--guard with anything else says how to use it" "$(cli --guard maybe) $(cli --guard maybe >/dev/null; echo $?)" "claude-html --guard on|prompt|off|status 2"

# ── installed beside what is there, once ─────────────────────────────
S="$T/settings.json"
printf '{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"theirs.sh"}]}]}}\n' > "$S"
node "$HERE/settings-hooks.js" "$S" "$HERE" add >/dev/null
node "$HERE/settings-hooks.js" "$S" "$HERE" add >/dev/null
check "install adds the two guard hooks once, beside the user's" \
  "$(grep -c 'guard.sh' "$S") $(grep -c 'theirs.sh' "$S") $(grep -c '"matcher": "Bash"' "$S")" "2 1 1"
check "  with a timeout past the dialog's ten minutes" "$(grep -A2 'guard.sh' "$S" | grep -c '"timeout": 660')" 2
node "$HERE/settings-hooks.js" "$S" "$HERE" add no-guard >/dev/null
check "--no-guard leaves them out, and takes out ones already there" "$(grep -c 'guard.sh' "$S") $(grep -c 'theirs.sh' "$S")" "0 1"
node "$HERE/settings-hooks.js" "$S" "$HERE" add >/dev/null
node "$HERE/settings-hooks.js" "$S" "$HERE" remove >/dev/null
check "uninstall removes only its own" "$(grep -c 'guard.sh\|save-conversation' "$S") $(grep -c 'theirs.sh' "$S")" "0 1"

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
