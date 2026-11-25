#!/bin/bash
# Secrets never reach what claude-html writes: the archives, the pages, the
# search, the index, the launchers, the caches. Claude Code's transcript is
# never touched. Changing the rules or the own list makes everything again;
# an old archive is never carried on; the two commands do what they say;
# and no command ever prints a secret.
#
#   bash tests/redact.test.sh
#
# A failure names the check, never the secret: what is looked for is in
# the sandbox's probes.txt, and only how many files hold one is printed.
set -u

. "$(dirname "$0")/lib.sh"

HERE="$(cd "$(dirname "$0")/.." && pwd)"
AF="$(. "$HERE/lib/version.sh"; printf "%s" "$CH_ARCHIVE_FORMAT")"
pass=0; fail=0
check() {
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); printf '  ok    %s\n' "$1"
  else fail=$((fail + 1)); printf '  FAIL  %s (expected %s, got %s)\n' "$1" "$3" "$2"; fi
}

# The unit half first, under the engine this machine tests with.
ENGINE=node; [ "$HAVE_OSASCRIPT" = true ] && ENGINE=osascript
out="$(node "$HERE/tests/redact.test.js" --engine "$ENGINE" 2>&1)"
check "the redactor on its own ($(printf '%s' "$out" | tail -1 | sed 's/^ *//'))" \
  "$(printf '%s' "$out" | grep -c FAIL)" 0
printf '%s\n' "$out" | grep FAIL

T="$(mktemp -d /tmp/chredact-test.XXXXXX)"
T="$(cd "$T" && pwd -P)"
trap 'rm -rf "$T"' EXIT
node "$HERE/tests/redact.test.js" fixture "$T"
APP="$T/root/app"; OUT="$T/root/pages"; CONV="$APP/.claude/.claude-conversations"
PROJ="$T/home/.claude/projects"
S1=$(sed -n 1p "$T/ids"); S2=$(sed -n 2p "$T/ids"); S3=$(sed -n 3p "$T/ids")
Q=$(sed -n 4p "$T/ids"); W=$(sed -n 5p "$T/ids")
LOG="$T/log"; : > "$LOG"

# Everything a command needs, pointed into the sandbox and nowhere else.
printf 'CLAUDE_HTML_ROOT="%s"\nCLAUDE_HTML_OUT="%s"\n' "$T/root" "$OUT" > "$T/home/.claude/claude-html.conf"
# The index is not to be opened in a browser.
printf '#!/bin/sh\nexit 0\n' > "$T/bin/open"; cp "$T/bin/open" "$T/bin/xdg-open"; chmod +x "$T/bin/"*
sandbox() {
  env HOME="$T/home" PATH="$T/bin:$PATH" CLAUDE_HTML_CONF="$T/home/.claude/claude-html.conf" \
    CLAUDE_HTML_ROOT="$T/root" CLAUDE_HTML_OUT="$OUT" CLAUDE_HTML_EXPORT="$T/conversations.json" \
    CLAUDE_HTML_REDACT_FILE="${LIST:-$T/home/.claude/claude-html.redact}" CLAUDE_HTML_NO_REGISTER=1 "$@"
}
case "$T" in /tmp/chredact-*|/private/tmp/chredact-*) ;; *) echo "not a sandbox: $T"; exit 1 ;; esac
# A save as the hook makes it, run by hand: every session of the project.
save() { sandbox /bin/bash -c "cd '$APP' && /bin/bash '$HERE/save-conversation.sh' --try" </dev/null >>"$LOG" 2>&1; }
ch() { sandbox /bin/bash "$HERE/claude-html" "$@" 2>&1 | tee -a "$LOG"; }

# How many files under a folder hold any of the probes. Only the count.
leaky() { grep -rlF -f "$T/probes.txt" "$@" 2>/dev/null | wc -l | tr -d ' '; }
fingerprint() { find "$PROJ" -type f | sort | while IFS= read -r f; do printf '%s %s\n' "$f" "$(ch_md5 "$f")"; done; }
. "$HERE/lib/platform.sh"
BEFORE="$(fingerprint)"
cp -p "$CONV/$Q.json" "$T/q.before"

# ── a save, as after a reply ─────────────────────────────────────────
save
check "a save archives every session with a transcript" "$(ls "$CONV" | grep -c '\.json$')" 4
check "  and builds their pages" "$(ls "$OUT/sessions" | grep -c '\.html$')" 5
check "  with the sub-agent's" "$(ls "$OUT/sessions/$S1" 2>/dev/null | grep -c 'agent-s1.html')" 1
check "no page, search file, index, launcher or cache holds a secret" "$(leaky "$OUT")" 0
check "  and the cache is there to look in" "$(ls "$OUT/.cache" | grep -c "$S1.build\$")" 1
check "  nor does any archive the save wrote" \
  "$(leaky "$CONV/$S1.json" "$CONV/$S2.json" "$CONV/$S3.json")" 0
check "  while their text is still there" "$(grep -c 'Here is everything' "$CONV/$S1.json") $(grep -c 'is what I pasted' "$OUT/search/$S2.js")" "1 1"
check "the title is masked where it is shown" \
  "$(grep -c 'Fix the login, using \*\*\*' "$OUT/index.html") $(grep -c 'Fix the login, using \*\*\*' "$OUT/sessions/$S1.html")" "1 1"
check "an archive records the redaction it was made with" \
  "$(head -c 200 "$CONV/$S1.json" | grep -c "\"format\":$AF,\"redact\":\"$(ch_redact_sig "$HERE")\",")" 1
check "an old archive beside its transcript is made again, not carried on" \
  "$(head -c 200 "$CONV/$S3.json" | grep -c "\"format\":$AF,") $(leaky "$CONV/$S3.json")" "1 0"
check "the archive whose transcript is gone is not rewritten by a save" \
  "$(cmp -s "$CONV/$Q.json" "$T/q.before" && echo kept)" kept
check "  but its page is masked" "$(leaky "$OUT/sessions/$Q.html" "$OUT/search/$Q.js")" 0
check "the claude.ai chat is masked, title and all" \
  "$(leaky "$OUT/sessions/$W.html") $(grep -c 'Chat about \*\*\*' "$OUT/index.html")" "0 1"
check "a picture's data is never stored as text" "$(grep -c 'iVBORw0KGgo' "$OUT/sessions/$S1.html")" 0

check "the save left Claude Code's transcripts byte for byte as they were" \
  "$([ "$(fingerprint)" = "$BEFORE" ] && echo same || echo changed)" same

# An archive the next save would carry on from, turned back into format 3
# with a secret in it, its state left as it was: a save after one more
# reply must make it again, not extend it.
node -e 'var fs=require("fs"),p=process.argv[1],a=JSON.parse(fs.readFileSync(p,"utf8"));
  a.format=3; delete a.redact; a.messages[0].text += " " + process.argv[2]; fs.writeFileSync(p,JSON.stringify(a))' \
  "$CONV/$S1.json" "$(head -1 "$T/probes.txt")"
printf '%s\n' '{"type":"user","cwd":"'"$APP"'","sessionId":"'"$S1"'","timestamp":"2026-11-02T09:00:00Z","message":{"role":"user","content":"one more"}}' \
  >> "$PROJ/$(printf '%s' "$APP" | tr '/' '-')/$S1.jsonl"
BEFORE="$(fingerprint)"
save
check "an old-format archive is never carried on, even with its state in place" \
  "$(leaky "$CONV/$S1.json") $(grep -c 'one more' "$CONV/$S1.json")" "0 1"

# ── the build says what is left, and the commands ────────────────────
R="$(ch)"
check "the build says an archive still holds secrets, and what fixes it" \
  "$(printf '%s' "$R" | grep -c '1 archive(s) still hold secrets the pages hide: claude-html --redact-archives')" 1
D="$(ch --doctor)"
check "--doctor has a redact line" "$(printf '%s\n' "$D" | grep -c '^  redact    on · [0-9]* built-in rules · no own list')" 1
check "  and counts the archives holding secrets" "$(printf '%s\n' "$D" | grep -c '1 holding secrets the pages hide')" 1
C="$(ch --redact-check)"
check "--redact-check names the sessions and counts by rule" \
  "$(printf '%s\n' "$C" | grep -c "^$S1  app  transcript: .*github [0-9]")" 1
check "  and the archive at rest" "$(printf '%s\n' "$C" | grep -c "^archive $CONV/$Q.json: .*aws-key-id 1")" 1
check "  and the export" "$(printf '%s\n' "$C" | grep -c "^$W  claude.ai  claude.ai: ")" 1
check "  without a secret in what it says" "$(printf '%s' "$C" | grep -cF -f "$T/probes.txt")" 0
check "  and changes nothing" "$(cmp -s "$CONV/$Q.json" "$T/q.before" && echo kept)" kept
A="$(ch --redact-archives)"
check "--redact-archives rewrites the archive that holds secrets" \
  "$(printf '%s\n' "$A" | grep -c "^rewrote $CONV/$Q.json: ") $(leaky "$CONV/$Q.json")" "1 0"
check "  as format 4, with the signature where the save looks for it" \
  "$(head -c 200 "$CONV/$Q.json" | grep -c "\"format\":4,\"redact\":\"$(ch_redact_sig "$HERE")\",")" 1
check "  keeping the rest of it" "$(grep -c 'archived long ago' "$CONV/$Q.json")" 1
check "  and the build no longer counts it" \
  "$(ch | grep -c 'still hold secrets')" 0
A2="$(ch --redact-archives)"
check "  a second time it rewrites nothing" "$(printf '%s\n' "$A2" | grep -c ' 0 rewritten')" 1

# ── the owner's own list ─────────────────────────────────────────────
cp "$T/list.redact" "$T/home/.claude/claude-html.redact"
grep -vxF "" "$T/own.txt" >> "$T/probes.txt"
check "before the list, its strings are on the page" "$(leaky "$OUT/sessions/$S1.html")" 1
D="$(ch --doctor)"
check "--doctor counts the own rules and the lines it ignored, by number" \
  "$(printf '%s\n' "$D" | grep -c '2 own rules, 4 ignored (lines 3, 4, 5, 6)')" 1
check "  and never says what the list holds" "$(printf '%s' "$D" | grep -cF -e 'Zebra' -e 'Mango' -e 'unclosed')" 0
P1="$(ch_md5 "$OUT/sessions/$S1.html")"
save
check "a changed list rebuilds the pages, sub-agents and caches" \
  "$(leaky "$OUT") $([ "$(ch_md5 "$OUT/sessions/$S1.html")" != "$P1" ] && echo rebuilt)" "0 rebuilt"
check "  and the archives, though no transcript grew" "$(leaky "$CONV")" 0
check "  under the new signature" \
  "$(head -c 200 "$CONV/$S2.json" | grep -c "\"redact\":\"$(CLAUDE_HTML_REDACT_FILE="$T/home/.claude/claude-html.redact" ch_redact_sig "$HERE")\"")" 1
check "a list it cannot fully use never fails a save" "$(ls "$OUT/.archive-errors" 2>/dev/null | wc -l | tr -d ' ')" 0

# ── off ──────────────────────────────────────────────────────────────
OFF="$T/off"; mkdir -p "$OFF"
sandbox env CLAUDE_HTML_OUT="$OFF" CLAUDE_HTML_REDACT=off /bin/bash "$HERE/claude-html" >/dev/null 2>&1
check "CLAUDE_HTML_REDACT=off leaves the text as it was" \
  "$([ "$(leaky "$OFF/sessions")" -gt 0 ] && echo intact)" intact
sandbox env CLAUDE_HTML_OUT="$OFF" /bin/bash "$HERE/claude-html" >/dev/null 2>&1
check "  and on again, the same pages are masked" "$(leaky "$OFF")" 0
rm -rf "$OFF"

# ── both engines write the same bytes ────────────────────────────────
# From the same sandbox, from nothing: the archives and every page.
if [ "$HAVE_OSASCRIPT" = true ] && command -v node >/dev/null 2>&1; then
  snap() {
    rm -rf "$OUT" "$T/home/.claude/claude-html.archives"; mkdir -p "$OUT"
    rm -f "$CONV/$S1.json" "$CONV/$S2.json" "$CONV/$S3.json"
    CLAUDE_HTML_ENGINE="$1" save
    # The Settings page says which engine is set and in use, as --doctor does.
    (cd "$OUT" && find . -type f ! -name .last-save ! -name settings.html | sort | while IFS= read -r f; do
       printf '%s %s\n' "$f" "$(sed 's/"built":[0-9]*,/"built":0,/' "$f" | cksum)"; done)
    cksum < "$CONV/$S1.json"
  }
  A1="$(snap osascript)"; A2="$(snap node)"
  check "osascript and node write the same archives, pages, search and caches" \
    "$([ "$A1" = "$A2" ] && echo same || echo differ)" same
fi

# ── as the hook leaves it, then --force, under each engine ───────────
# Secrets with no known prefix in every place: a prompt, thinking, a reply,
# a command, a nested input key, a result across the cut, the title.
H="$T/hook"; mkdir -p "$H"
node "$HERE/tests/redact.test.js" hook-fixture "$H"
HID="$(cat "$H/id")"; HAPP="$H/root/app"; HOUT="$H/root/pages"
HJ="$H/home/.claude/projects/$(printf '%s' "$HAPP" | tr '/' '-')/$HID.jsonl"
printf 'CLAUDE_HTML_ROOT="%s"\nCLAUDE_HTML_OUT="%s"\n' "$H/root" "$HOUT" > "$H/home/.claude/claude-html.conf"
HSUM="$(ch_md5 "$HJ")"
ENGINES=node; [ "$HAVE_OSASCRIPT" = true ] && ENGINES="osascript node"
for eng in $ENGINES; do
  rm -rf "$HOUT" "$HAPP/.claude" "$H/home/.claude/claude-html.archives"; mkdir -p "$HOUT"
  : > "$H/log.$eng"
  hk() {
    env HOME="$H/home" PATH="$T/bin:$PATH" CLAUDE_HTML_CONF="$H/home/.claude/claude-html.conf" \
      CLAUDE_HTML_ROOT="$H/root" CLAUDE_HTML_OUT="$HOUT" CLAUDE_HTML_EXPORT=/nonexistent \
      CLAUDE_HTML_REDACT_FILE="$H/home/.claude/claude-html.redact" CLAUDE_HTML_ENGINE="$eng" "$@"
  }
  printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","hook_event_name":"Stop"}' "$HID" "$HJ" "$HAPP" |
    hk CLAUDE_HTML_DETACHED=1 /bin/bash -c "cd '$HAPP' && /bin/bash '$HERE/save-conversation.sh'" >>"$H/log.$eng" 2>&1
  hk /bin/bash "$HERE/claude-html" --force >>"$H/log.$eng" 2>&1
  check "$eng: the hook then --force archive and build the session" \
    "$(ls "$HAPP/.claude/.claude-conversations" | grep -c "$HID.json") $(ls "$HOUT/sessions" | grep -c "$HID.html")" "1 1"
  check "$eng:   and no page, cache, archive or output holds a secret with no known prefix" \
    "$(grep -rlF -f "$H/probes.txt" "$HOUT" "$HAPP/.claude/.claude-conversations" "$H/log.$eng" 2>/dev/null | wc -l | tr -d ' ')" 0
  check "$eng:   while the text around them is kept" "$(grep -c 'for the staging box' "$HOUT/sessions/$HID.html")" 1
done
check "  and the transcript is byte for byte as it was" "$([ "$(ch_md5 "$HJ")" = "$HSUM" ] && echo same)" same

# ── nothing was changed that is not ours, nothing was said ──────────
check "Claude Code's transcripts are byte for byte as they were" \
  "$([ "$(fingerprint)" = "$BEFORE" ] && echo same || echo changed)" same
check "no command printed a secret" "$(grep -cF -f "$T/probes.txt" "$LOG")" 0

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
