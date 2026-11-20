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
    -u CLAUDE_HTML_GUARD -u CLAUDE_HTML_GUARD_DIALOG \
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
check "the first install adds the guard's two hooks" "$(grep -c 'guard.sh' "$H/.claude/settings.json")" 2

# ── --no-guard: the guard's hooks out, and off in the conf ──
install --no-guard
check "--no-guard takes the guard's hooks out" \
  "$(grep -c 'guard.sh' "$H/.claude/settings.json") $(grep -c 'save-conversation.sh' "$H/.claude/settings.json")" "0 4"
check "  and turns it off in the conf, the rest kept" \
  "$(conf_get CLAUDE_HTML_GUARD) $(grep -c '^CLAUDE_HTML_ROOT=' "$CONF")" "off 1"
# A bare run is what an update makes: it must not undo the choice.
install
check "a later bare install leaves them out, the guard off" \
  "$(grep -c 'guard.sh' "$H/.claude/settings.json") $(conf_get CLAUDE_HTML_GUARD)" "0 off"
check "  and keeps --out and --root" "$(conf_get CLAUDE_HTML_ROOT) | $(conf_get CLAUDE_HTML_OUT)" "$ROOT | $PAGES"
clean_env bash "$C/claude-html" --guard on >/dev/null 2>&1
install
check "turned on again, the next install puts the hooks back, once" "$(grep -c 'guard.sh' "$H/.claude/settings.json")" 2
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
for _ in $(seq 1 600); do [ -f "$A" ] && break; sleep 0.2; done
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
  "$(CLAUDE_HTML_FORCE_NODE=1 run_js "$C/settings-hooks.js" "$H/.claude/settings.json" "$C" remove)" "removed 6"
install

# ── which hooks are ours: the whole command, never a script's name ──
# Under the engine lib.sh picked, osascript on a Mac: settings-hooks.js is
# run by both. A user's own scripts named like ours are theirs; another
# clone's hooks are replaced as a set; nothing else is touched.
S2="$T/hooks/settings.json"; OLD="$T/old clone"; GONE="$T/gone clone"; MINE="$T/u dir"
mkdir -p "$T/hooks" "$OLD" "$MINE"
: > "$OLD/convert.js"; : > "$OLD/guard.js"; : > "$MINE/guard.sh"
sh_js() { HOME="$H" run_js "$C/settings-hooks.js" "$S2" "$C" "$@"; }
mk_settings() {
  node -e 'function q(p){return "\x27"+p+"\x27";}
    var o=process.argv[1], g=process.argv[2], m=process.argv[3];
    function h(c){return {hooks:[{type:"command",command:c}]};}
    var s={hooks:{
      UserPromptSubmit:[h("bash ~/bin/prompt-guard.sh"), h("bash "+q(m+"/guard.sh")+" prompt"), h("bash "+q(o+"/guard.sh")+" prompt")],
      PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:"bash "+q(o+"/guard.sh")+" bash"}]}],
      Stop:[h("bash "+q(o+"/save-conversation.sh")+" --background"), h("/usr/local/bin/save-conversation.sh")],
      SessionEnd:[h("bash "+q(g+"/save-conversation.sh"))],
      PreCompact:[{matcher:"auto",hooks:[{type:"command",command:"bash "+q(o+"/save-conversation.sh")}]}]}};
    require("fs").writeFileSync(process.argv[4], JSON.stringify(s,null,2));' \
    "$OLD" "$GONE" "$MINE" "$S2"
}
theirs3() {
  printf '%s %s %s' "$(grep -c 'bash ~/bin/prompt-guard.sh"' "$S2")" \
    "$(grep -cF "$MINE/guard.sh' prompt" "$S2")" "$(grep -c '"/usr/local/bin/save-conversation.sh"' "$S2")"
}
mk_settings
R="$(sh_js add)"
check "install adds its guard though the user has a prompt-guard.sh and a guard.sh of their own" \
  "$(grep -cF "$C/guard.sh' prompt" "$S2") $(grep -cF "$C/guard.sh' bash" "$S2")" "1 1"
check "  the user's three hooks are left exactly as they were" "$(theirs3)" "1 1 1"
check "  another clone's hooks, and a gone one's, are replaced as a set by this clone's" \
  "$(grep -cF "$OLD/" "$S2") $(grep -cF "$GONE/" "$S2") $(grep -cF "$C/" "$S2")" "0 0 6"
check "  and the installer says so" "$(printf '%s' "$R" | grep -c 'replaced 5 hook(s) of')" 1
check "  counting the user's as theirs" "$(printf '%s' "$R" | sed -n 's/.*"theirs":\([0-9]*\).*/\1/p')" 3
sh_js add no-guard >/dev/null
check "--no-guard takes out this clone's guard only" \
  "$(grep -cF "$C/guard.sh" "$S2") $(theirs3)" "0 1 1 1"
sh_js add >/dev/null
check "remove takes out this clone's hooks only" "$(sh_js remove) $(grep -cF "$C/" "$S2") $(theirs3)" "removed 6 0 1 1 1"
mk_settings
sh_js remove >/dev/null
check "  and never another clone's" "$(grep -cF "$OLD/" "$S2") $(theirs3)" "4 1 1 1"
# A settings.json kept in a dotfiles folder, as a symlink, stays one.
mkdir -p "$T/dots2"; mv "$S2" "$T/dots2/settings.json"; ln -s "$T/dots2/settings.json" "$S2"
sh_js add >/dev/null
check "a symlinked settings.json stays a symlink, its file takes the hooks" \
  "$([ -L "$S2" ] && echo link) $(grep -cF "$C/" "$T/dots2/settings.json")" "link 6"

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

# ── folders with a quote or a backslash, and relative ones ──
# Every option handed to the JavaScript is JSON made by one helper: a name
# that holds a quote or a backslash once broke every build, silently in the
# hook. And --out and --root are written whole, or each project would read
# them from its own folder.
mv "$T/conf.away" "$CONF"
Q="$T/we\"ird \\dir"; QAPP="$Q/app"; mkdir -p "$QAPP"
install --root "$Q" --out "$Q/pages"
check "a root and pages folder with a quote and a backslash are kept as given" \
  "$(conf_get CLAUDE_HTML_ROOT)|$(conf_get CLAUDE_HTML_OUT)" "$Q|$Q/pages"
run_hook "$QAPP" SessionEnd
check "  the hook archives there and builds the pages" \
  "$(exists "$QAPP/.claude/.claude-conversations/$ID.json") $(exists "$Q/pages/sessions/$ID.html")" "yes yes"
rm -rf "$Q/pages/sessions"
cli
check "  and so does the command" "$(exists "$Q/pages/sessions/$ID.html")" yes
mkdir -p "$T/here"
( cd "$T/here" && install --out "rel pages" --root ./projs/ )
check "relative --out and --root are written whole" \
  "$(conf_get CLAUDE_HTML_OUT)|$(conf_get CLAUDE_HTML_ROOT)" "$T/here/rel pages|$T/here/projs"

# ── another install's command is its own ──
mkdir -p "$T/other/claude-html"; printf '#!/bin/sh\necho other\n' > "$T/other/claude-html/claude-html"
chmod +x "$T/other/claude-html/claude-html"
ln -sf "$T/other/claude-html/claude-html" "$H/.local/bin/claude-html"
install
check "an install from a second clone leaves the first's command where it is" \
  "$(readlink "$H/.local/bin/claude-html") $(grep -c "another install's" "$T/install.out")" "$T/other/claude-html/claude-html 1"
clean_env bash "$C/install.sh" --uninstall > "$T/install.out" 2>&1
check "  and uninstalling from it leaves that command too" "$(readlink "$H/.local/bin/claude-html")" "$T/other/claude-html/claude-html"
rm -f "$H/.local/bin/claude-html"; install
check "with none there, it puts its own" "$(readlink "$H/.local/bin/claude-html")" "$C/claude-html"
for f in .claude-html.update .claude-html.guard .claude-html.guard-engine .claude-html-update.command; do : > "$H/.claude/$f"; done
mkdir -p "$H/.claude/.claude-html-guard"; : > "$H/.claude/.claude-html-guard/sess"
: > "$H/.claude/claude-html.archives"
clean_env bash "$C/install.sh" --uninstall > "$T/install.out" 2>&1
check "  and uninstalling takes its own away" "$([ -L "$H/.local/bin/claude-html" ] && echo there || echo gone)" gone
check "  and its own state in ~/.claude, leaving the conf and the archive list" \
  "$(ls -A "$H/.claude" | grep -c "^\.claude-html") $(exists "$CONF") $(exists "$H/.claude/claude-html.archives")" "0 yes yes"

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
