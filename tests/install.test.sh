#!/bin/bash
# install.sh on a second run, from a clone whose path has a space in it, and
# the one rule the hook and the command share for where things are.
#
# Everything runs against a sandbox HOME and a copy of the clone. node, not
# osascript, so the helper app is never built or registered from a temp dir.
#
#   bash tests/install.test.sh
set -u

. "$(dirname "$0")/lib.sh"

HERE="$(cd "$(dirname "$0")/.." && pwd)"
pass=0; fail=0
check() {
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); printf '  ok    %s\n' "$1"
  else fail=$((fail + 1)); printf '  FAIL  %s (expected %s, got %s)\n' "$1" "$3" "$2"; fi
}
T="$(cd "$(tmpdir chinstall)" && pwd)"
trap 'rm -rf "$T"' EXIT

# install.sh takes every path from where it sits, so the clone is copied to a
# folder with a space in its name rather than run from here.
C="$T/my clone/claude-html"
mkdir -p "$C"
for f in "$HERE"/*.sh "$HERE"/*.js "$HERE/claude-html" "$HERE/helper.applescript" "$HERE/viewer"; do
  [ -e "$f" ] && cp -R "$f" "$C/"
done
H="$T/home"; ROOT="$T/my projects"; APP="$ROOT/app"; PAGES="$T/my pages"
mkdir -p "$H/.claude/projects/-elsewhere" "$APP"
CONF="$H/.claude/claude-html.conf"

# Whatever the machine running the suite has set must not leak in.
clean_env() {
  env -u CLAUDE_HTML_OUT -u CLAUDE_HTML_ROOT -u CLAUDE_HTML_CONF -u CLAUDE_HTML_WEEK_RESET -u CLAUDE_HTML_ENGINE \
    HOME="$H" CLAUDE_HTML_FORCE_NODE=1 "$@"
}
install() { clean_env bash "$C/install.sh" "$@" > "$T/install.out" 2>&1; }
exists() { [ -e "$1" ] && echo yes || echo no; }
conf_get() { ( unset CLAUDE_HTML_ROOT CLAUDE_HTML_OUT; . "$CONF"; eval "printf '%s' \"\${$1:-}\"" ); }
hook_cmd() {   # the command settings.json runs for an event
  node -e 'var s=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
    process.stdout.write(s.hooks[process.argv[2]][0].hooks[0].command)' "$H/.claude/settings.json" "$1"
}

ID=eeeeeeee-0000-0000-0000-000000000006
J="$H/.claude/projects/-elsewhere/$ID.jsonl"
printf '%s\n' '{"type":"user","cwd":"/x","timestamp":"2026-11-06T10:00:00Z","message":{"role":"user","content":"saved through a quoted hook"}}' > "$J"
note() { printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","hook_event_name":"SessionEnd"}' "$ID" "$J" "$1"; }
A="$APP/.claude/.claude-conversations/$ID.json"
# A hook as Claude Code runs it: the command string, handed to a shell.
run_hook() {   # dir, event, then any VAR=value for the environment
  local dir="$1" ev="$2"; shift 2
  local cmd; cmd="$(hook_cmd "$ev")"
  # The session-end save hands itself to the background, which would leave
  # nothing to look at when this returns. These checks are about where a save
  # puts things, not about the hand-off (tests/hooks.test.sh has that), so the
  # hook is told it is already the detached copy and runs to the end here.
  note "$dir" | clean_env CLAUDE_HTML_DETACHED=1 "$@" /bin/sh -c "cd \"\$0\" && $cmd" "$dir" >/dev/null 2>&1
}
cli() { clean_env "$@" "$H/.local/bin/claude-html" "$ID" >/dev/null 2>&1; }

# ── first install ──
install --root "$ROOT" --out "$PAGES"
check "installs from a path with a space" "$?" 0
check "  writes the projects given" "$(conf_get CLAUDE_HTML_ROOT)" "$ROOT"
check "  and the pages given" "$(conf_get CLAUDE_HTML_OUT)" "$PAGES"
case "$(hook_cmd Stop)" in
  "bash '$C/save-conversation.sh' --background") q=quoted ;; *) q="$(hook_cmd Stop)" ;;
esac
check "  the hook's path is quoted" "$q" quoted

# ── the hooks it wrote actually run ──
run_hook "$APP" SessionEnd
check "the SessionEnd hook archives through the quoted path" "$(exists "$A")" yes
check "  and rebuilds the pages" "$(exists "$PAGES/sessions/$ID.html")" yes
rm -f "$A"
run_hook "$APP" Stop
for _ in $(seq 1 60); do [ -f "$A" ] && break; sleep 0.25; done
check "the Stop hook detaches and still archives" "$(exists "$A")" yes

# ── a second run keeps what the user chose ──
printf '%s\n' '# mine' 'CLAUDE_HTML_WEEK_RESET="tue 09:00"' 'CLAUDE_HTML_SOMETHING_NEW="kept"' >> "$CONF"
BEFORE="$(cat "$CONF")"
install
check "a bare re-run changes nothing in a complete conf" "$(cat "$CONF")" "$BEFORE"
check "  the pages stay where they were sent" "$(conf_get CLAUDE_HTML_OUT)" "$PAGES"
SETTINGS_BEFORE="$(cat "$H/.claude/settings.json")"
install
check "  and the hooks are not added twice" "$(cat "$H/.claude/settings.json")" "$SETTINGS_BEFORE"

install --out "$T/other pages"
check "--out changes its own line" "$(conf_get CLAUDE_HTML_OUT)" "$T/other pages"
check "  and not the projects" "$(conf_get CLAUDE_HTML_ROOT)" "$ROOT"
check "  the week anchor survives" "$(grep -c '^CLAUDE_HTML_WEEK_RESET="tue 09:00"$' "$CONF")" 1
check "  so does a line it knows nothing about" "$(grep -c '^CLAUDE_HTML_SOMETHING_NEW="kept"$' "$CONF")" 1
check "  and the user's comment" "$(grep -c '^# mine$' "$CONF")" 1
install --out "$PAGES"

# A conf missing a key gets it back; one with the week line commented out is
# not offered it a second time.
grep -v '^CLAUDE_HTML_ROOT=' "$CONF" > "$T/c" && mv "$T/c" "$CONF"
install
check "a missing key is added back" "$(conf_get CLAUDE_HTML_ROOT)" "$(dirname "$C")"
check "  and the rest is untouched" "$(conf_get CLAUDE_HTML_OUT)" "$PAGES"
install --root "$ROOT"

# A conf kept with the user's dotfiles is a symlink, and editors may save it
# without a final newline: what is added must land in their file, on its own line.
mkdir -p "$T/dots"
grep -v '^CLAUDE_HTML_ROOT=' "$CONF" | awk '{ printf "%s%s", sep, $0; sep = "\n" }' > "$T/dots/conf"
rm -f "$CONF"; ln -s "$T/dots/conf" "$CONF"
install --out "$T/other pages"
check "a symlinked conf stays a symlink" "$([ -L "$CONF" ] && echo yes || echo no)" yes
check "  and its file takes the change" "$(conf_get CLAUDE_HTML_OUT)" "$T/other pages"
check "  a key added after an unterminated line gets its own" "$(conf_get CLAUDE_HTML_ROOT)" "$(dirname "$C")"
check "  and that last line keeps its value" "$(conf_get CLAUDE_HTML_SOMETHING_NEW)" kept
rm -f "$CONF"; cp "$T/dots/conf" "$CONF"
install --root "$ROOT" --out "$PAGES"

# ── a hook written before the quoting is repaired, and removal knows both ──
LEGACY="bash $C/save-conversation.sh"
node -e 'var fs=require("fs"),p=process.argv[1],s=JSON.parse(fs.readFileSync(p,"utf8"));
  s.hooks.Stop[0].hooks[0].command=process.argv[2]+" --background";
  s.hooks.SessionEnd[0].hooks[0].command=process.argv[2];
  fs.writeFileSync(p,JSON.stringify(s,null,2))' "$H/.claude/settings.json" "$LEGACY"
install
check "an unquoted hook from an older install is quoted" "$(hook_cmd Stop)" "bash '$C/save-conversation.sh' --background"
check "  and not duplicated" "$(grep -c 'save-conversation.sh' "$H/.claude/settings.json")" 4
node -e 'var fs=require("fs"),p=process.argv[1],s=JSON.parse(fs.readFileSync(p,"utf8"));
  s.hooks.SessionEnd[0].hooks[0].command=process.argv[2];
  fs.writeFileSync(p,JSON.stringify(s,null,2))' "$H/.claude/settings.json" "$LEGACY"
check "remove takes quoted and unquoted alike" \
  "$(CLAUDE_HTML_FORCE_NODE=1 run_js "$C/settings-hooks.js" "$H/.claude/settings.json" "$C" remove)" "removed 4"
install

# ── one rule for where things go: environment, then conf, then default ──
rm -rf "$PAGES"
run_hook "$APP" SessionEnd CLAUDE_HTML_OUT="$T/env pages"
check "the hook: the environment wins over the conf" "$(exists "$T/env pages/sessions/$ID.html")" yes
check "  and the conf's folder is left alone" "$(exists "$PAGES")" no
cli CLAUDE_HTML_OUT="$T/env cli"
check "the command: the environment wins over the conf" "$(exists "$T/env cli/sessions/$ID.html")" yes

rm -rf "$PAGES"
run_hook "$APP" SessionEnd
check "the hook: with no environment, the conf" "$(exists "$PAGES/sessions/$ID.html")" yes
rm -rf "$PAGES"
cli
check "the command: with no environment, the conf" "$(exists "$PAGES/sessions/$ID.html")" yes

rm -f "$A"
run_hook "$APP" SessionEnd CLAUDE_HTML_ROOT="$T/nowhere"
check "the hook: a root from the environment wins too" "$(exists "$A")" no

# No conf at all: both fall back to what install.sh would have written — the
# pages in the clone, the projects beside it.
mv "$CONF" "$T/conf.away"
P2="$(dirname "$C")/proj"; mkdir -p "$P2"
run_hook "$P2" SessionEnd
check "the hook: with no conf, projects beside the clone" "$(exists "$P2/.claude/.claude-conversations/$ID.json")" yes
check "  and pages in the clone" "$(exists "$C/sessions/$ID.html")" yes
rm -rf "$C/sessions"
cli
check "the command: with no conf, pages in the clone" "$(exists "$C/sessions/$ID.html")" yes

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
