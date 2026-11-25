#!/bin/bash
# The hooks name their transcript on stdin, so a save need not search for it.
#
# The session here is filed under another directory and records another cwd,
# as after a project is renamed — so searching this folder's sessions cannot
# find it, and only the hook's note can. That is what tells the two apart.
#
#   bash tests/hooks.test.sh
set -u

. "$(dirname "$0")/lib.sh"

HERE="$(cd "$(dirname "$0")/.." && pwd)"
AF="$(. "$HERE/lib/version.sh"; printf "%s" "$CH_ARCHIVE_FORMAT")"
pass=0; fail=0
check() {
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); printf '  ok    %s\n' "$1"
  else fail=$((fail + 1)); printf '  FAIL  %s (expected %s, got %s)\n' "$1" "$3" "$2"; fi
}
T="$(cd "$(tmpdir chhooks)" && pwd)"
trap 'rm -rf "$T"' EXIT

ROOT="$T/root"; APP="$ROOT/app"
D="$(printf '%s' "$APP" | tr '/' '-')"
mkdir -p "$T/home/.claude/projects/$D" "$T/home/.claude/projects/-elsewhere" "$APP" "$ROOT/pages"
printf 'CLAUDE_HTML_ROOT="%s"\nCLAUDE_HTML_OUT="%s"\n' "$ROOT" "$ROOT/pages" \
  > "$T/home/.claude/claude-html.conf"

ID=eeeeeeee-0000-0000-0000-000000000005
J="$T/home/.claude/projects/-elsewhere/$ID.jsonl"
printf '%s\n' '{"type":"user","cwd":"/somewhere/old","timestamp":"2026-09-11T10:00:00Z","message":{"role":"user","content":"named by the hook"}}' > "$J"
A="$APP/.claude/.claude-conversations/$ID.json"
NOTE="{\"session_id\":\"$ID\",\"transcript_path\":\"$J\",\"cwd\":\"$APP\",\"hook_event_name\":\"Stop\"}"
save() { env HOME="$T/home" /bin/bash -c "cd '$APP' && /bin/bash '$HERE/save-conversation.sh' $1" >/dev/null 2>&1; }
found() { sed -n 's/.*found=\([a-z]*\).*/\1/p' "$ROOT/pages/.last-save" 2>/dev/null; }
exists() { [ -f "$1" ] && echo yes || echo no; }

save "" </dev/null
check "run by hand, it searches" "$(found)" search
check "  and cannot find a session filed elsewhere" "$(exists "$A")" no

printf '%s' "$NOTE" | save "--try"
check "given the hook's note, it does not search" "$(found)" hook
check "  and archives the session it names" "$(exists "$A")" yes

# The reply hook detaches, and the detached copy has no stdin: the note must
# survive the hand-off.
rm -f "$A"
printf '%s' "$NOTE" | save "--background"
for _ in $(seq 1 600); do [ -f "$A" ] && break; sleep 0.2; done
check "the detached save still knows which transcript" "$(exists "$A")" yes

# A save that fails must leave the last good archive where it was: the
# transcript it was made from may already have been cleaned up.
GOOD="$(cat "$A")"
# The detached save above may still hold the lock, and --try would give way.
for _ in $(seq 1 1200); do [ -d "$T/home/.claude/.claude-html.lock" ] || break; sleep 0.1; done
printf '%s\n' '{"type":"user","cwd":"/somewhere/old","timestamp":"2026-09-11T10:01:00Z","message":{"role":"user","content":"more"}}' >> "$J"
chmod 000 "$J"
printf '%s' "$NOTE" | save "--try"
chmod 644 "$J"
check "a failed save keeps the previous archive" "$(cat "$A" 2>/dev/null)" "$GOOD"
check "  records the failure" "$(exists "$ROOT/pages/.archive-errors/$ID.json")" yes
check "  and leaves no partial file behind" \
  "$(ls -A "$APP/.claude/.claude-conversations" | grep -c partial)" 0

# Nor may one that is cut short, as a full disk leaves it: the engine exits
# cleanly having written only part. A stand-in node does exactly that.
mkdir -p "$T/shim"
printf '#!/bin/sh\nprintf %%s %s\n' "'{\"sourceBytes\":1,\"messages\":[{\"role\"'" > "$T/shim/node"
chmod +x "$T/shim/node"
rm -f "$ROOT/pages/.archive-errors/$ID.json"
printf '%s' "$NOTE" | env PATH="$T/shim:$PATH" CLAUDE_HTML_FORCE_NODE=1 \
  HOME="$T/home" /bin/bash -c "cd '$APP' && /bin/bash '$HERE/save-conversation.sh' --try" >/dev/null 2>&1
check "a save cut short keeps the previous archive" "$(cat "$A" 2>/dev/null)" "$GOOD"
check "  and records the failure" "$(exists "$ROOT/pages/.archive-errors/$ID.json")" yes
printf '%s' "$NOTE" | save "--try"
check "the next good save replaces it" "$(grep -c '"more"' "$A")" 1
check "  and clears the failure" "$(exists "$ROOT/pages/.archive-errors/$ID.json")" no

# Cut just after a "}", the end the old check looked for: the full archive
# made, then only part of it written, the engine exiting cleanly. Moved over
# the good one, it was never made again: its size said it was up to date.
GOOD="$(cat "$A")"
REAL_NODE="$(command -v node)"
cat > "$T/shim/node" <<SHIM
#!/bin/sh
case "\$1" in
  */archive.js) out="\$("$REAL_NODE" "\$@")" || exit \$?
    out="\${out%\}*}"; printf '%s}\n' "\${out%\}*}"; exit 0 ;;
esac
exec "$REAL_NODE" "\$@"
SHIM
chmod +x "$T/shim/node"
printf '%s\n' '{"type":"user","cwd":"/somewhere/old","timestamp":"2026-09-11T10:02:00Z","message":{"role":"user","content":"and more"}}' >> "$J"
rm -f "$ROOT/pages/.archive-errors/$ID.json"
printf '%s' "$NOTE" | env PATH="$T/shim:$PATH" CLAUDE_HTML_FORCE_NODE=1 \
  HOME="$T/home" /bin/bash -c "cd '$APP' && /bin/bash '$HERE/save-conversation.sh' --try" >/dev/null 2>&1
check "a save cut off just after a } keeps the previous archive" "$(cat "$A" 2>/dev/null)" "$GOOD"
check "  and records the failure" "$(exists "$ROOT/pages/.archive-errors/$ID.json")" yes
printf '%s' "$NOTE" | save "--try"
check "  and the next save makes it whole" \
  "$(node -e 'var a=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")); console.log(a.messageCount)' "$A" 2>&1)" 3
# The length is counted in bytes, whichever engine counts it: two, three
# and four bytes to a character are all whole.
printf '%s\n' '{"type":"user","cwd":"/somewhere/old","timestamp":"2026-09-11T10:03:00Z","message":{"role":"user","content":"caf\u00e9 \u2713 \ud83d\ude00"}}' >> "$J"
printf '%s' "$NOTE" | save "--try"
check "  as is one with characters of every width" \
  "$(node -e 'var a=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")); console.log(a.messages[3].text)' "$A" 2>&1) $(exists "$ROOT/pages/.archive-errors/$ID.json")" "café ✓ 😀 no"

# An archive written before the format carried tokens and thinking is
# written again once while its transcript is still here, though the
# transcript has not grown — and only once.
check "an archive says which format it is" "$(head -c 200 "$A" | grep -c "\"format\":$AF,")" 1
node -e 'var fs=require("fs"),p=process.argv[1],a=JSON.parse(fs.readFileSync(p,"utf8"));
  delete a.format; delete a.usage; delete a.replies; fs.writeFileSync(p,JSON.stringify(a))' "$A"
printf '%s' "$NOTE" | save "--try"
check "an older archive is brought up to date from the same transcript" \
  "$(head -c 200 "$A" | grep -c "\"format\":$AF,") $(grep -c '"usage":{' "$A")" "1 1"
touch -t 202001010000 "$A"
printf '%s' "$NOTE" | save "--try"
check "  and then left alone" "$(mtime_of "$A")" "$(touch -t 202001010000 "$T/ref" && mtime_of "$T/ref")"

# Cost arrived with format 3. A format 2 archive of a transcript that has
# stopped growing — a session long since ended, its final cost already
# written — is rewritten once, or the cost would be lost with the transcript.
printf '%s\n' '{"type":"cost-state","sessionId":"'"$ID"'","totalCostUSD":1.25,"startTime":1789000000000,"modelUsage":{"claude-opus-5":{"costUSD":1.25}}}' >> "$J"
printf '%s' "$NOTE" | save "--try"
node -e 'var fs=require("fs"),p=process.argv[1],a=JSON.parse(fs.readFileSync(p,"utf8")); a.format=2;
  Object.keys(a.usage).forEach(function(h){ Object.keys(a.usage[h]).forEach(function(m){ a.usage[h][m].length=Math.min(5,a.usage[h][m].length); }); });
  fs.writeFileSync(p,JSON.stringify(a))' "$A"
printf '%s' "$NOTE" | save "--try"
check "a format 2 archive of an unchanged transcript is rewritten with its cost" \
  "$(head -c 200 "$A" | grep -c "\"format\":$AF,") $(node -e 'var a=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")),n=0;
  Object.keys(a.usage).forEach(function(h){ Object.keys(a.usage[h]).forEach(function(m){ var r=a.usage[h][m]; if(r.length>7) n+=r[7]; }); }); console.log(n)' "$A")" "1 1250000"

# A nested folder the build cannot find on its own — the transcript is filed
# elsewhere and names another cwd — goes on the durable list when the hook
# archives there, so the build reads it once the transcript has expired.
NAPP="$ROOT/group/site"; mkdir -p "$NAPP"
NID=eeeeeeee-0000-0000-0000-000000000006
NJ="$T/home/.claude/projects/-elsewhere/$NID.jsonl"
printf '%s\n' '{"type":"user","cwd":"/somewhere/older","timestamp":"2026-09-11T10:00:00Z","message":{"role":"user","content":"nested"}}' > "$NJ"
LIST="$T/home/.claude/claude-html.archives"
check "the build has started the list" "$(exists "$LIST")" yes
printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","hook_event_name":"Stop"}' "$NID" "$NJ" "$NAPP" |
  env HOME="$T/home" /bin/bash -c "cd '$NAPP' && /bin/bash '$HERE/save-conversation.sh' --try" >/dev/null 2>&1
check "the hook puts a nested folder it archived into on the list" "$(grep -cxF "$NAPP" "$LIST")" 1
rm -f "$NJ"; rm -rf "$ROOT/pages"
HOME="$T/home" run_js "$HERE/build/convert.js" \
  "{\"root\":\"$ROOT\",\"out\":\"$ROOT/pages\",\"here\":\"$HERE\",\"exportPath\":\"/nonexistent\"}" >/dev/null
check "  and with its transcript and the pages gone, the build still finds it" \
  "$(exists "$ROOT/pages/sessions/$NID.html")" yes
printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","hook_event_name":"Stop"}' "$ID" "$J" "$NAPP" |
  env HOME="$T/home" /bin/bash -c "cd '$NAPP' && /bin/bash '$HERE/save-conversation.sh' --try" >/dev/null 2>&1
check "  and a second save there does not list it twice" "$(grep -cxF "$NAPP" "$LIST")" 1

# Session end: Claude Code cancels a hook that is still running as it quits,
# so the save must hand itself off and return at once — and still happen.
rm -f "$A"
END_NOTE="{\"session_id\":\"$ID\",\"transcript_path\":\"$J\",\"cwd\":\"$APP\",\"hook_event_name\":\"SessionEnd\"}"
# hold the lock, as a save already in progress would, so a hook that waited
# for its turn in the foreground would visibly hang here
mkdir -p "$T/home/.claude/.claude-html.lock" && echo $$ > "$T/home/.claude/.claude-html.lock/pid"
printf '%s' "$END_NOTE" | save ""
# No clock. The lock is released only once the hook has returned, and the
# checks below see the save made after that: so it was not the hook that made
# it, but the copy it left waiting. A hook that waited in the foreground would
# give up and leave nothing, and the last check would fail.
check "the session-end hook returns with another save still holding the lock" \
  "$(cat "$T/home/.claude/.claude-html.lock/pid" 2>/dev/null)" "$$"
check "  and has not saved yet: it is waiting its turn in the background" "$(exists "$A")" no
rm -rf "$T/home/.claude/.claude-html.lock"
for _ in $(seq 1 600); do [ -f "$A" ] && break; sleep 0.2; done   # an event, waited for up to two minutes
check "  and the save still happens once it can" "$(exists "$A")" yes

# Before a compaction, the same: Claude Code waits for the hook, and the
# transcript keeps what the compaction summarises, so nothing is lost by
# saving it just after.
for _ in $(seq 1 1200); do [ -d "$T/home/.claude/.claude-html.lock" ] || break; sleep 0.1; done
rm -f "$A"
PC_NOTE="{\"session_id\":\"$ID\",\"transcript_path\":\"$J\",\"cwd\":\"$APP\",\"hook_event_name\":\"PreCompact\",\"trigger\":\"auto\"}"
mkdir -p "$T/home/.claude/.claude-html.lock" && echo $$ > "$T/home/.claude/.claude-html.lock/pid"
printf '%s' "$PC_NOTE" | save ""
check "the pre-compaction hook returns at once, with another save holding the lock" \
  "$(cat "$T/home/.claude/.claude-html.lock/pid" 2>/dev/null) $(exists "$A")" "$$ no"
rm -rf "$T/home/.claude/.claude-html.lock"
for _ in $(seq 1 600); do [ -f "$A" ] && break; sleep 0.2; done
check "  and its save happens in the background" "$(exists "$A")" yes

# ── for its owner only ──────────────────────────────────────────────
# Claude Code keeps transcripts readable by their owner alone; what is made
# of them is kept the same way. What an earlier release left readable by
# everyone is made so too, and a file of the owner's own in the pages
# folder is left as it was.
mode() { ls -ld "$1" | cut -c1-10; }
P1="$(ls "$ROOT/pages/sessions/"*.html | head -1)"
chmod 755 "$ROOT/pages/sessions" "$APP/.claude/.claude-conversations"; chmod 644 "$P1" "$A"
printf 'mine\n' > "$ROOT/pages/notes.txt"; chmod 644 "$ROOT/pages/notes.txt"
printf '%s\n' '{"type":"user","cwd":"/somewhere/old","timestamp":"2026-09-11T10:03:00Z","message":{"role":"user","content":"and once more"}}' >> "$J"
for _ in $(seq 1 1200); do [ -d "$T/home/.claude/.claude-html.lock" ] || break; sleep 0.1; done
printf '%s' "$NOTE" | save "--try"
check "pages, their folders and the archive are its owner's alone" \
  "$(mode "$P1") $(mode "$ROOT/pages/sessions") $(mode "$A") $(mode "$APP/.claude/.claude-conversations")" \
  "-rw------- drwx------ -rw------- drwx------"
check "  new ones too" "$(mode "$ROOT/pages/.manifest.json") $(mode "$ROOT/pages/index.html")" "-rw------- -rw-------"
check "  and the owner's own file there is left as it was" "$(mode "$ROOT/pages/notes.txt")" "-rw-r--r--"
check "--doctor says so" "$(env HOME="$T/home" bash "$HERE/claude-html" --doctor 2>/dev/null | grep -c '^  private   what it wrote there is readable by you alone$')" 1

# ── archives stay out of git ────────────────────────────────────────
G() { HOME="$T/home" GIT_CONFIG_NOSYSTEM=1 git -c user.name=t -c user.email=t@example.invalid -C "$APP" "$@"; }
G init -q
check "the archive folder ignores itself" "$(cat "$APP/.claude/.claude-conversations/.gitignore" | grep -cx '\*')" 1
check "  so a project's git never sees an archive" "$(G status --porcelain --untracked-files=all | grep -c claude-conversations)" 0
rm "$APP/.claude/.claude-conversations/.gitignore"
check "--doctor names an archive folder git would commit" \
  "$(env HOME="$T/home" bash "$HERE/claude-html" --doctor 2>/dev/null | grep -c "^            $APP/.claude/.claude-conversations\$")" 1
for _ in $(seq 1 1200); do [ -d "$T/home/.claude/.claude-html.lock" ] || break; sleep 0.1; done
printf '%s' "$NOTE" | save "--try"
check "  and the next save there puts the .gitignore back" "$(G status --porcelain --untracked-files=all | grep -c claude-conversations)" 0

# ── a save run from a folder below the project ──────────────────────
# A hook runs in the session's current folder, which Claude may have
# changed: the archive still goes to the folder the session was launched
# in, which the transcript names, and the page keeps that project.
ID2=eeeeeeee-0000-0000-0000-000000000077
J2="$T/home/.claude/projects/$D/$ID2.jsonl"
printf '{"type":"user","cwd":"%s","timestamp":"2026-09-12T10:00:00Z","message":{"role":"user","content":"launched in the app"}}\n' "$APP" > "$J2"
printf '{"type":"user","cwd":"%s/src","timestamp":"2026-09-12T10:01:00Z","message":{"role":"user","content":"then went into src"}}\n' "$APP" >> "$J2"
mkdir -p "$APP/src"
for _ in $(seq 1 1200); do [ -d "$T/home/.claude/.claude-html.lock" ] || break; sleep 0.1; done
printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s/src","hook_event_name":"Stop"}' "$ID2" "$J2" "$APP" |
  env HOME="$T/home" /bin/bash -c "cd '$APP/src' && /bin/bash '$HERE/save-conversation.sh' --try" >/dev/null 2>&1
check "a save run in a folder below the project archives into the project" \
  "$(exists "$APP/.claude/.claude-conversations/$ID2.json") $([ -d "$APP/src/.claude" ] && echo stray)" "yes "
# One left there by an earlier release, newer than the right one, does not
# move the session to a project called src.
mkdir -p "$APP/src/.claude/.claude-conversations"
cp "$APP/.claude/.claude-conversations/$ID2.json" "$APP/src/.claude/.claude-conversations/$ID2.json"
touch -t 203001010000 "$APP/src/.claude/.claude-conversations/$ID2.json"
printf "%s\n" "$APP/src" >> "$T/home/.claude/claude-html.archives"
env HOME="$T/home" bash "$HERE/claude-html" "$ID2" >/dev/null 2>&1
check "  and of two archives, the one in the transcript's folder names the project" \
  "$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))[process.argv[2]].project)' "$ROOT/pages/.manifest.json" "$ID2")" app

# ── no /bin/bash taken for granted ──────────────────────────────────
# Some systems (NixOS) have no /bin/bash: a save that relaunched itself
# through it failed there, detached, so nobody saw. The scripts start
# through env, and relaunch with the bash that runs them.
check "no script starts with #!/bin/bash, nor runs one through it" \
  "$(grep -l '^#!/bin/bash' "$HERE"/*.sh "$HERE"/lib/*.sh "$HERE"/mac/*.sh "$HERE"/linux/*.sh "$HERE/claude-html" | wc -l | tr -d ' ') $(grep -cE '(^|[;&|(]|nohup)[[:space:]]*/bin/bash[[:space:]]' "$HERE/save-conversation.sh")" "0 0"

# ── the helper app: a Mac's only ────────────────────────────────────
# The save and the command keep the helper app in step on a Mac; elsewhere
# there is none to build, and the build script is never run. A stand-in
# for it, in a copy of the clone, says when it is.
CL="$T/clone"; mkdir -p "$CL"
for f in "$HERE"/*.sh "$HERE/claude-html" "$HERE/VERSION" "$HERE/lib" "$HERE/build" "$HERE/actions" "$HERE/mac" "$HERE/linux" "$HERE/viewer"; do cp -R "$f" "$CL/"; done
printf '#!/bin/sh\necho "$*" >> "%s/helper-calls"\n' "$T" > "$CL/mac/helper-build.sh"; chmod +x "$CL/mac/helper-build.sh"
hsave() { env -u CLAUDE_HTML_NO_REGISTER HOME="$T/home" "$@" /bin/bash -c "cd '$APP' && bash '$CL/save-conversation.sh' --try" </dev/null >/dev/null 2>&1
          env -u CLAUDE_HTML_NO_REGISTER HOME="$T/home" "$@" bash "$CL/claude-html" "$ID" >/dev/null 2>&1; }
for _ in $(seq 1 1200); do [ -d "$T/home/.claude/.claude-html.lock" ] || break; sleep 0.1; done
rm -f "$T/helper-calls"; hsave CLAUDE_HTML_UNAME=Linux CLAUDE_HTML_FORCE_NODE=1
check "on Linux neither the save nor the command runs the helper's build" "$(cat "$T/helper-calls" 2>/dev/null | wc -l | tr -d ' ')" 0
if [ "$HAVE_OSASCRIPT" = true ]; then
  rm -f "$T/helper-calls"; hsave CLAUDE_HTML_UNAME=Darwin
  check "  on a Mac both keep it in step" "$(grep -c -- '--register --if-stale' "$T/helper-calls" 2>/dev/null)" 2
fi

# ── a state file that cannot be written ─────────────────────────────
# The reply's hook tells of a newer release and notes that it did. A note
# it cannot write (a full disk, a folder it may not write in) stopped the
# hook under set -e, before it started the save: no save after any reply.
for _ in $(seq 1 1200); do [ -d "$T/home/.claude/.claude-html.lock" ] || break; sleep 0.1; done
printf 'checked=%s\nnewest=99.0.0\nhere=%s\ntold=\n' "$(date +%s)" "$(cd -P "$HERE" && pwd)" \
  > "$T/home/.claude/.claude-html.update"
rm -f "$ROOT/pages/.last-save"
chmod 555 "$T/home/.claude"
if ( : > "$T/home/.claude/.w" ) 2>/dev/null; then
  rm -f "$T/home/.claude/.w"; chmod 755 "$T/home/.claude"
  echo "  skip  a state file that cannot be written: this user writes anywhere"
else
  out="$(printf '%s' "$NOTE" | env HOME="$T/home" CLAUDE_HTML_UPDATE_CHECK=on \
    /bin/bash -c "cd '$APP' && /bin/bash '$HERE/save-conversation.sh' --background" 2>/dev/null; echo "exit=$?")"
  # The save it starts finds the lock's folder shut too, and gives way: said
  # in .last-save, which is outside it.
  for _ in $(seq 1 600); do [ -s "$ROOT/pages/.last-save" ] && break; sleep 0.2; done
  chmod 755 "$T/home/.claude"
  check "a reply's hook that cannot note the notice still tells it, and exits cleanly" \
    "$(printf '%s' "$out" | tr '\n' '|')" '{"systemMessage":"claude-html 99.0.0 is out · update with: claude-html --update"}|exit=0'
  check "  and still starts the save" "$([ -s "$ROOT/pages/.last-save" ] && echo started || echo none)" started
fi
rm -f "$T/home/.claude/.claude-html.update"

# ── archive failures of sessions that are gone ──────────────────────
GONE_ID=ffffffff-0000-0000-0000-00000000dead
mkdir -p "$ROOT/pages/.archive-errors"
printf '{"id":"%s","source":"/x","error":"archiving failed: old","kind":"archive"}\n' "$GONE_ID" > "$ROOT/pages/.archive-errors/$GONE_ID.json"
printf '{"id":"%s","source":"/x","error":"archiving failed: now","kind":"archive"}\n' "$ID" > "$ROOT/pages/.archive-errors/$ID.json"
env HOME="$T/home" bash -c '. "$0/lib/conf.sh"; . "$0/lib/platform.sh"; ch_pick_engine; ch_js "$0/build/convert.js" "$(ch_js_opts "$0")"' "$HERE" >/dev/null 2>&1
check "an archive failure of a session no longer there is cleared by the build, one still there kept" \
  "$(exists "$ROOT/pages/.archive-errors/$GONE_ID.json") $(exists "$ROOT/pages/.archive-errors/$ID.json")" "no yes"
rm -f "$ROOT/pages/.archive-errors/$ID.json"

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
