#!/bin/bash
# claude-html --update, and the daily look for a new release.
#
# Everything is built here from throwaway repositories: a bare "release
# repository" whose main is one commit per release, each made from this very
# tree with its VERSION and changelog changed and a stub install.sh that
# records that it ran; and clones of it as the installs. The claude-html,
# lib/update.sh, lib/version.sh, lib/conf.sh, save-conversation.sh and build/convert.js under
# test are this tree's own. Nothing here ever uses the network: HOME, the
# conf, the projects, the pages and the release remote all point into the
# sandbox, and every remote is a local path.
#
#   bash tests/update.test.sh
set -u

. "$(dirname "$0")/lib.sh"

HERE="$(cd "$(dirname "$0")/.." && pwd)"
T="$(cd "$(tmpdir chupdate)" && pwd -P)"
SLEEPERS=""
trap 'for p in $SLEEPERS; do kill "$p" 2>/dev/null; done; rm -rf "$T"' EXIT

H="$T/home"; PROJ="$T/projects"; CONF="$H/.claude/claude-html.conf"
mkdir -p "$H/.claude" "$PROJ/app"
printf '# a comment of the owner\nCLAUDE_HTML_WEEK_RESET="tue 09:00"\n' > "$CONF"

# git with nothing of the machine's own configuration in it.
export GIT_CONFIG_NOSYSTEM=1

# ── the release repository ───────────────────────────────────────────
# A release's tree: this one's files, its own VERSION and changelog, and a
# stub install.sh. 2.0.0 writes archive format 3; 3.1.0 changes the viewer
# (so its pages are rebuilt) and the hooks (so the update says so).
FILES="claude-html save-conversation.sh guard.sh statusline.sh .gitignore lib build actions mac linux viewer"
changelog_for() {   # the newest version, then all it includes
  echo "# Changelog"; echo
  local v
  for v in "$@"; do
    echo "## $v — 2026-11-20"; echo
    echo "- what $v brought."
    [ "$v" = 3.1.0 ] && echo "- After updating: nothing to do, the pages rebuild themselves."
    echo
  done
}
make_tree() {   # dir, version, then the changelog's versions (none: no changelog)
  local d="$1" v="$2"; shift 2
  find "$d" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
  local f; for f in $FILES; do cp -R "$HERE/$f" "$d/"; done
  echo "$v" > "$d/VERSION"
  [ $# -gt 0 ] && changelog_for "$@" > "$d/CHANGELOG.md"
  cat > "$d/install.sh" <<'EOF'
#!/bin/bash
# A stand-in for install.sh: says it ran, and as which release.
here="$(cd "$(dirname "$0")" && pwd)"; v="$(cat "$here/VERSION")"
echo "$v" >> "$UPD_TEST_DIR/installs"
[ -f "$UPD_TEST_DIR/fail-install-$v" ] && { echo "the stub install failed on purpose" >&2; exit 1; }
mkdir -p "$HOME/.claude"
sed "s|@HERE@|$here|g" "$here/hooks.json" > "$HOME/.claude/settings.json"
echo "  built:    0 session(s), 0 rebuilt"
EOF
  chmod +x "$d/install.sh"
  printf '{\n  "hooks": {\n    "Stop": [\n      {\n        "hooks": [\n          {\n            "type": "command",\n            "command": "bash '"'"'@HERE@/save-conversation.sh'"'"' --background"\n          }\n        ]\n      }\n    ]%s\n  }\n}\n' \
    "$([ "$v" = 3.1.0 ] && printf ',\n    "PreCompact": [\n      {\n        "hooks": [\n          {\n            "type": "command",\n            "command": "bash '"'"'@HERE@/save-conversation.sh'"'"'"\n          }\n        ]\n      }\n    ]')" \
    > "$d/hooks.json"
  case "$v" in
    # 2.x as releases before 3.1.3 were: the number written in the save
    # script, on a line of its own ("format: 3,"), and no CH_ARCHIVE_FORMAT
    # in lib/version.sh.
    2.*) awk '/^[[:space:]]*archive\.field\("format", FORMAT\);/ {
             print "  archive.field(\"format\", {"; print "    format: 3,"; print "  }.format);"; next } { print }' \
           "$d/save-conversation.sh" > "$d/s.tmp" && mv "$d/s.tmp" "$d/save-conversation.sh"
         grep -v '^CH_ARCHIVE_FORMAT=' "$d/lib/version.sh" > "$d/r.tmp" && mv "$d/r.tmp" "$d/lib/version.sh" ;;
    3.1.0) echo "/* 3.1.0 */" >> "$d/viewer/page.js" ;;
  esac
}
release() {   # work repo, version, changelog versions…
  local w="$1" v="$2"
  make_tree "$@"
  gitx -C "$w" add -A >/dev/null && gitx -C "$w" commit -q -m "$v" && gitx -C "$w" tag "v$v"
}
W="$T/work"; mkdir -p "$W"; gitx init -q "$W"
release "$W" 2.0.0 2.0.0
release "$W" 3.0.0
release "$W" 3.0.1 3.0.1 3.0.0 2.0.0
release "$W" 3.1.0 3.1.0 3.0.1 3.0.0 2.0.0
# Tags that are not releases: one off main, one not named as a release.
gitx -C "$W" checkout -q -b side v3.0.1
gitx -C "$W" commit -q --allow-empty -m side && gitx -C "$W" tag v9.0.0
gitx -C "$W" checkout -q main
gitx -C "$W" tag v3.2.0-rc1; gitx -C "$W" tag latest
BARE="$T/release.git"
gitx clone -q --bare "$W" "$BARE"
gitx -C "$BARE" branch -D side >/dev/null 2>&1

# A second release repository whose numbers a string sort or the commit
# order would get wrong: 3.10.0 is the newest, and main ends at 3.9.0.
W2="$T/work2"; mkdir -p "$W2"; gitx init -q "$W2"
release "$W2" 3.0.1 3.0.1
release "$W2" 3.10.0
release "$W2" 3.9.0
BARE2="$T/release2.git"; gitx clone -q --bare "$W2" "$BARE2"

# A third, whose newest is a major release: 3.0.1, then 4.0.0.
W3="$T/work3"; mkdir -p "$W3"; gitx init -q "$W3"
release "$W3" 3.0.1 3.0.1
release "$W3" 4.0.0 4.0.0 3.0.1
BARE3="$T/release3.git"; gitx clone -q --bare "$W3" "$BARE3"

# What each upload-pack call leaves: a mark, to prove whether the remote
# was asked anything at all.
UP="$T/upload-pack"
cat > "$UP" <<EOF
#!/bin/sh
echo asked >> "$T/asked"
[ -f "$T/offline" ] && { echo "offline" >&2; exit 1; }
[ -f "$T/hang" ] && { sleep 120 </dev/null >/dev/null 2>&1; echo finished >> "$T/hang.finished"; exit 0; }
exec git-upload-pack "\$@"
EOF
chmod +x "$UP"
asked() { [ -f "$T/asked" ] && wc -l < "$T/asked" | tr -d ' ' || echo 0; }

# An install: a clone of the release repository, at a release.
clone() {   # name, ref, [remote]
  local d="$T/$1/claude-html"
  rm -rf "$T/$1"; mkdir -p "$T/$1"
  gitx clone -q "${3:-$BARE}" "$d"
  gitx -C "$d" config remote.origin.uploadpack "$UP"
  case "$2" in
    detached:*) gitx -C "$d" checkout -q --detach "${2#detached:}" ;;
    *) gitx -C "$d" reset -q --hard "$2" ;;
  esac
  INST="$(cd -P "$d" && pwd)"
}

# Every command runs with the sandbox for HOME, conf, projects and pages,
# the release remote pointed at the sandbox's, and nothing of the shell's.
run() {
  env -u CLAUDE_HTML_OUT -u CLAUDE_HTML_ROOT -u CLAUDE_HTML_ENGINE -u CLAUDE_HTML_GUARD -u CLAUDE_HTML_AUTO_UPDATE \
    -u CLAUDE_HTML_GUARD_DIALOG -u CLAUDE_HTML_UPDATE_CHECK -u CLAUDE_HTML_WEEK_RESET \
    HOME="$H" XDG_CONFIG_HOME="$H/.config" CLAUDE_HTML_CONF="$CONF" CLAUDE_HTML_ROOT="$PROJ" \
    CLAUDE_HTML_OUT="$INST" CLAUDE_HTML_UPDATE_REMOTE="${REMOTE:-$BARE}" CLAUDE_HTML_NO_REGISTER=1 \
    CLAUDE_HTML_UPDATE_LOCK_WAIT=2 UPD_TEST_DIR="$T" "$@"
}
ch() { run bash "$INST/claude-html" "$@" </dev/null 2>&1; }
at() { printf 'v%s' "$(cat "$INST/VERSION")"; }
branch() { gitx -C "$INST" symbolic-ref -q --short HEAD || echo detached; }
installs() { tr '\n' ' ' < "$T/installs" 2>/dev/null | sed 's/ $//'; }
state() { sed -n "s/^$1=//p" "$H/.claude/.claude-html.update" 2>/dev/null; }

# A session, so a build has a page to make, and the update one to rebuild.
ID=aaaaaaaa-0000-0000-0000-000000000001
D="$(printf '%s' "$PROJ/app" | tr '/' '-')"
mkdir -p "$H/.claude/projects/$D"
printf '{"type":"user","cwd":"%s","timestamp":"2026-11-20T10:00:00Z","message":{"role":"user","content":"a question"}}\n{"type":"assistant","cwd":"%s","timestamp":"2026-11-20T10:00:01Z","message":{"role":"assistant","content":[{"type":"text","text":"an answer"}]}}\n' \
  "$PROJ/app" "$PROJ/app" > "$H/.claude/projects/$D/$ID.jsonl"
build() { (cd / && run bash "$INST/claude-html" "$ID" </dev/null 2>&1); }
# Saves detached by a test finish before the next step.
# A detached save is already a process when the one that started it
# returns (save-conversation.sh starts it with nohup before it ends), so
# there is nothing to wait for before looking.
settle() {
  local i
  for i in $(seq 1 300); do
    ps ax -o command= 2>/dev/null | grep -F "$INST/save-conversation.sh" | grep -qv grep || return 0
    sleep 0.1
  done
}

# ── release numbers ──────────────────────────────────────────────────
. "$HERE/lib/version.sh"
o=""
for p in "3.10.0 3.9.0" "3.0.10 3.0.9" "4.0.0 3.99.99" "3.1.0 3.0.1" "10.0.0 9.0.0"; do
  ch_ver_gt ${p% *} ${p#* } && o="$o+" || o="$o-"
  ch_ver_gt ${p#* } ${p% *} && o="$o+" || o="$o-"
done
ch_ver_gt 3.0.1 3.0.1 && o="$o+" || o="$o-"
check "release numbers compare as numbers: 3.10.0 after 3.9.0, and none after itself" "$o" "+-+-+-+-+--"

# ── status and list ─────────────────────────────────────────────────
clone a v3.0.1
build >/dev/null
out="$(ch --update status)"; rc=$?
has "status, behind: installed and newest" "$out" "installed 3.0.1 · newest 3.1.0"
has "  with the changelog in between, from the newest's own" "$out" "what 3.1.0 brought."
hasnt "  and nothing from before" "$out" "what 3.0.1 brought."
has "  and whether the daily check is on" "$out" "the daily check is on"
check "  exit 0" "$rc" 0
hasnt "  a tag off main is not a release" "$out" "9.0.0"
check "  and nothing moved" "$(at)" v3.0.1
out="$(ch --update --check)"
has "--check is status too" "$out" "installed 3.0.1 · newest 3.1.0"

out="$(ch --update list)"; rc=$?
day() { gitx -C "$BARE" log -1 --format=%cd --date=short "v$1"; }
check "list: every release, newest first, with the marks" \
  "$(printf '%s\n' "$out" | awk '{ printf "%s|", $0 }')" \
  "  3.1.0   $(day 3.1.0)   newest|* 3.0.1   $(day 3.0.1)   installed|  3.0.0   $(day 3.0.0)|  2.0.0   $(day 2.0.0)|"
check "  exit 0" "$rc" 0
hasnt "  no tag off main" "$out" "9.0.0"
hasnt "  no tag not named as a release" "$out" "rc1"

touch "$T/offline"
out="$(ch --update status)"; rc=$?
has "status, offline: says it could not reach the releases" "$out" "could not reach the releases"
check "  and fails" "$rc" 1
out="$(ch --update list)"; rc=$?
check "list, offline: one line, and fails" "$(printf '%s\n' "$out" | wc -l | tr -d ' ') $rc" "1 1"
out="$(ch --update)"; rc=$?
has "update, offline: nothing changed" "$out" "nothing was changed"
check "  fails, and the clone stays" "$rc $(at)" "1 v3.0.1"
rm -f "$T/offline"

REMOTE="$BARE2" clone s v3.0.1 "$BARE2"
out="$(REMOTE="$BARE2" ch --update status)"
has "3.10.0 is newer than 3.9.0, wherever main ends" "$out" "newest 3.10.0"
has "  a release without a changelog is shown without one" "$out" "claude-html --update goes to 3.10.0"
out="$(REMOTE="$BARE2" ch --update list)"
check "  and list orders them by number" "$(printf '%s\n' "$out" | awk '{ printf "%s ", ($1 == "*" ? $2 : $1) }')" "3.10.0 3.9.0 3.0.1 "
out="$(REMOTE="$BARE2" ch --update)"
check "  and the update goes to 3.10.0" "$(at) $(cat "$INST/VERSION")" "v3.10.0 3.10.0"

clone a v3.1.0
out="$(ch --update status)"
has "status, newest: says so" "$out" "3.1.0 is the newest release"
out="$(ch --update)"; rc=$?
check "update, newest: nothing to do" "$out $rc" "3.1.0 is the newest release 0"

# ── words ───────────────────────────────────────────────────────────
for w in latest 3.2.0-rc1 3.1 "status extra"; do
  # shellcheck disable=SC2086
  out="$(ch --update $w)"; rc=$?
  check "--update $w: the usage line, exit 2" "$rc $(printf '%s' "$out" | head -1)" \
    "2 claude-html --update [X.Y.Z|list|status|on|off] [--yes]"
done

# ── updates ─────────────────────────────────────────────────────────
clone a v3.0.1
: > "$T/installs"
echo "my own notes" > "$INST/notes.txt"
build >/dev/null
check "  (the pages live in the clone, untracked)" \
  "$([ -f "$INST/sessions/$ID.html" ] && [ -d "$INST/.cache" ] && echo yes) $(gitx -C "$INST" status --porcelain | wc -l | tr -d ' ')" "yes 1"
out="$(ch --update)"; rc=$?
check "from a branch, to the newest: on main at 3.1.0" "$rc $(branch) $(at)" "0 main v3.1.0"
has "  says so" "$out" "Updated 3.0.1 → 3.1.0."
has "  with the changelog's after-updating line" "$out" "After updating: nothing to do, the pages rebuild themselves."
has "  its viewer changed, so the page was rebuilt" "$out" "1 session(s) rebuilt"
has "  and its hooks changed, so it says when they apply" "$out" "sessions started from now on"
check "  the new release's install ran" "$(installs)" "3.1.0"
check "  untracked files stay: notes, pages, cache" \
  "$(cat "$INST/notes.txt") $([ -f "$INST/sessions/$ID.html" ] && [ -d "$INST/.cache" ] && echo pages)" "my own notes pages"

clone a detached:v3.0.1
: > "$T/installs"
out="$(ch --upgrade)"; rc=$?
check "from a detached tag, by --upgrade: on main at 3.1.0" "$rc $(branch) $(at)" "0 main v3.1.0"
hasnt "  the same hooks would not have been mentioned" "$(clone b v3.0.0; run bash "$INST/install.sh" >/dev/null 2>&1; ch --update 3.0.1)" "started from now on"

clone a v3.0.0
out="$(ch --update 3.0.1)"; rc=$?
check "to a given release: detached at it" "$rc $(branch) $(at)" "0 detached v3.0.1"
clone a v3.0.0
out="$(ch --update v3.0.1)"; rc=$?
check "  and with its v" "$rc $(branch) $(at)" "0 detached v3.0.1"
out="$(ch --update)"
check "  and from there to the newest" "$(branch) $(at)" "main v3.1.0"

clone a v3.0.1
out="$(ch --update 3.7.0)"; rc=$?
has "an unknown release: refused, with the ones there are" "$out" "there is no release 3.7.0 (there are: "
check "  nothing moved" "$rc $(at)" "1 v3.0.1"
gitx -C "$INST" fetch -q origin "+refs/tags/*:refs/tags/*"
out="$(ch --update 9.0.0)"; rc=$?
has "a tag off main: refused, as not a release" "$out" "v9.0.0 is a tag, but not a release"
check "  nothing moved" "$rc $(at)" "1 v3.0.1"

# Through the symlink on PATH, from another folder.
mkdir -p "$T/bin" "$T/elsewhere"; ln -sf "$INST/claude-html" "$T/bin/claude-html"
out="$(cd "$T/elsewhere" && run "$T/bin/claude-html" --update 2>&1 </dev/null)"; rc=$?
check "through a symlink, from another folder" "$rc $(at)" "0 v3.1.0"

# ── refusals ────────────────────────────────────────────────────────
clone a v3.0.1
echo "# mine" >> "$INST/lib/conf.sh"
out="$(ch --update)"; rc=$?
has "a changed file of the release: refused" "$out" "conf.sh"
check "  nothing moved, the change kept" "$rc $(at) $(tail -1 "$INST/lib/conf.sh")" "1 v3.0.1 # mine"
gitx -C "$INST" checkout -q -- lib/conf.sh
echo "# staged" >> "$INST/build/redact.js"; gitx -C "$INST" add build/redact.js
out="$(ch --update)"; rc=$?
check "  a staged one too" "$rc $(at)" "1 v3.0.1"
gitx -C "$INST" reset -q --hard

sleep 30 & SLEEPER=$!; SLEEPERS="$SLEEPERS $SLEEPER"
mkdir -p "$H/.claude/.claude-html.lock"; echo "$SLEEPER" > "$H/.claude/.claude-html.lock/pid"
# No clock is read here: what is checked is what it said and did, so a fast
# machine and a slow one give the same answer.
out="$(ch --update)"; rc=$?
has "a save holding the lock: it says it is waiting" "$out" "a save is running; waiting for it to finish"
has "  then refused, politely" "$out" "a save is still running; try again in a moment"
check "  and nothing moved" "$rc $(at)" "1 v3.0.1"
# The save ends while it waits: the update goes ahead. It may wait far
# longer than the save takes, so only the order of things decides.
: > "$T/waiting.out"
( n=0   # the save "ends" once the update has said it is waiting, not after a guess at how long that takes
  until grep -q "waiting for it to finish" "$T/waiting.out" 2>/dev/null || [ "$n" -ge 600 ]; do sleep 0.1; n=$((n + 1)); done
  rm -rf "$H/.claude/.claude-html.lock" ) &
RELEASER=$!
run env CLAUDE_HTML_UPDATE_LOCK_WAIT=120 bash "$INST/claude-html" --update </dev/null > "$T/waiting.out" 2>&1; rc=$?
wait "$RELEASER" 2>/dev/null
out="$(cat "$T/waiting.out")"
has "a save that ends while it waits: waited" "$out" "a save is running; waiting for it to finish"
check "  then updated" "$rc $(at)" "0 v3.1.0"
kill "$SLEEPER" 2>/dev/null; rm -rf "$H/.claude/.claude-html.lock"

# Going back.
clone a v3.1.0
out="$(ch --update 3.0.0)"; rc=$?
# The format this tree writes, which every release made from it writes too.
AFNOW="$(. "$HERE/lib/version.sh"; printf '%s' "$CH_ARCHIVE_FORMAT")"
has "going back: warned, with the archive format" "$out" "archive format $AFNOW"
has "  refused without a yes and no terminal" "$out" "going back needs a yes"
check "  nothing moved" "$rc $(at)" "1 v3.1.0"
: > "$T/installs"
out="$(ch --update 3.0.0 --yes)"; rc=$?
check "  done with --yes" "$rc $(at) $(installs)" "0 v3.0.0 3.0.0"
clone a v3.1.0
out="$(ch -y --update 2.0.0)"; rc=$?
has "  to 2.x, whose format is in its save script: it cannot read format $AFNOW" "$out" "2.0.0 cannot read the archives 3.1.0 writes (archive format $AFNOW; 2.0.0 knows format 3 and older)"
has "  and the way back is said" "$out" "git checkout main && git pull && ./install.sh"
check "  done" "$rc $(at)" "0 v2.0.0"

# A failed install puts everything back.
clone a v3.0.1
: > "$T/installs"; touch "$T/fail-install-3.1.0"
out="$(ch --update)"; rc=$?
has "a failed install: says what failed" "$out" "its install.sh failed"
check "  back where it was, its own install run again, exit 1" "$rc $(branch) $(at) $(installs)" "1 main v3.0.1 3.1.0 3.0.1"
rm -f "$T/fail-install-3.1.0"

# Not a release checkout: never fetched for.
clone d v3.0.1
gitx -C "$INST" commit -q --allow-empty -m "my own work"
touch "$T/hang"; n="$(asked)"
out="$(ch --update)"; rc=$?
check "a development checkout: refused" "$(printf '%s' "$out" | grep -c 'development checkout') $rc" "1 1"
check "  answered without asking the remote" "$(asked)" "$n"
out="$(ch --update status)"; rc=$?
has "  status says so, without fetching" "$out" "development checkout"
check "  exit 0, the remote not asked" "$rc $(asked)" "0 $n"
out="$(ch --update list)"
check "  list lists nothing" "$(printf '%s\n' "$out" | grep -c '^[ *] [0-9]') $(asked)" "0 $n"
rm -f "$T/hang"

mkdir -p "$T/zip"; cp -R "$INST" "$T/zip/"; rm -rf "$T/zip/claude-html/.git"
out="$(INST="$T/zip/claude-html" ch --update)"; rc=$?
has "not a clone: says how to re-install" "$out" "is not a git clone"
check "  exit 1" "$rc" 1
# Nor asked about with git at all: what is not a clone is known from the
# disk, and its daily look is recorded, so it is not made after every reply.
REALGIT="$(command -v git)"
mkdir -p "$T/gitlog"; printf '#!/bin/sh\necho "$*" >> "%s/gitcalls"\nexec "%s" "$@"\n' "$T" "$REALGIT" > "$T/gitlog/git"
chmod +x "$T/gitlog/git"; rm -f "$H/.claude/.claude-html.update" "$T/gitcalls"
run env PATH="$T/gitlog:$PATH" bash "$T/zip/claude-html/lib/update.sh" "$T/zip/claude-html" --daily
check "  its daily check runs no git, and is recorded for the day" \
  "$(cat "$T/gitcalls" 2>/dev/null | wc -l | tr -d ' ') $(state here) $([ -n "$(state checked)" ] && [ "$(state checked)" != 0 ] && echo checked)" \
  "0 $T/zip/claude-html checked"
# A Mac without Apple's developer tools, whose /usr/bin/git only offers to
# install them, in a dialog: not run.
mkdir -p "$T/noclt"; printf '#!/bin/sh\nexit 2\n' > "$T/noclt/xcode-select"; chmod +x "$T/noclt/xcode-select"
clone a v3.0.1
out="$(run env PATH="$T/noclt:/usr/bin:/bin" CLAUDE_HTML_UNAME=Darwin bash "$INST/lib/update.sh" "$INST" unset status 2>&1)"
has "a Mac without developer tools: its git stand-in is never run" "$out" "git is not installed"


# ── the daily check ─────────────────────────────────────────────────
save() { (cd "$PROJ/app" && run CLAUDE_HTML_UPDATE_CHECK="${CHK:-on}" bash "$INST/save-conversation.sh" --try </dev/null >/dev/null 2>&1); }
clone a v3.0.1
rm -f "$H/.claude/.claude-html.update"; n="$(asked)"
t0="$(date +%s)"; save; t1="$(date +%s)"
check "a save asks once, and remembers the newest" "$(state newest) $(state here) $(( $(asked) - n ))" "3.1.0 $INST 1"
c="$(state checked)"
check "  with when: during that save" "$([ "$t0" -le "$c" ] && [ "$c" -le "$t1" ] && echo then)" then
save
check "  not again within a day" "$(( $(asked) - n ))" 1
now="$(date +%s)"   # not a timing: the state is aged by a day and a bit, by hand
sed "s/^checked=.*/checked=$((now - 90000))/" "$H/.claude/.claude-html.update" > "$T/st" && mv "$T/st" "$H/.claude/.claude-html.update"
save
check "  again after one" "$(( $(asked) - n ))" 2
has "  the index says so" "$(cat "$INST/index.html")" '"update":"3.1.0"'
out="$(build)"
has "  and a build in the terminal" "$out" "claude-html 3.1.0 is out · update with claude-html --update"
# In Claude Code, once: the reply's hook prints a systemMessage.
msg() { printf '{}' | run bash "$INST/save-conversation.sh" --background 2>/dev/null; }
m1="$(msg)"; settle; m2="$(msg)"; settle
check "  and Claude Code is told, once" "$m1|$m2" \
  '{"systemMessage":"claude-html 3.1.0 is out · update with: claude-html --update"}|'
CHK=off; sed "s/^checked=.*/checked=0/" "$H/.claude/.claude-html.update" > "$T/st" && mv "$T/st" "$H/.claude/.claude-html.update"
n2="$(asked)"; save
check "CLAUDE_HTML_UPDATE_CHECK=off: no question asked" "$(asked)" "$n2"
hasnt "  and no notice on the index" "$(cat "$INST/index.html")" '"update":"'
CHK=on

# A remote that hangs is given five seconds.
sed "s/^checked=.*/checked=0/" "$H/.claude/.claude-html.update" > "$T/st" && mv "$T/st" "$H/.claude/.claude-html.update"
rm -f "$T/hang.finished"; touch "$T/hang"; save; rm -f "$T/hang"
# No clock: the slow remote writes a mark only if it was let run to its end.
check "a remote that hangs: given up on, not waited for, the newest kept" \
  "$([ -f "$T/hang.finished" ] && echo waited || echo no) $(state newest)" "no 3.1.0"

# The notice goes once the update is made.
out="$(ch --update)"
hasnt "after the update, the index has no notice" "$(cat "$INST/index.html")" '"update":"'
hasnt "  nor the terminal" "$(build)" "is out"

# Never in a development checkout.
clone d v3.0.1
gitx -C "$INST" commit -q --allow-empty -m "my own work"
sed "s/^checked=.*/checked=0/" "$H/.claude/.claude-html.update" > "$T/st" && mv "$T/st" "$H/.claude/.claude-html.update"
n="$(asked)"; save
check "a development checkout's save asks nothing" "$(asked)" "$n"
hasnt "  and its index has no notice" "$(cat "$INST/index.html")" '"update":"'
hasnt "  nor its terminal" "$(build)" "is out"

# ── on and off ──────────────────────────────────────────────────────
clone a v3.0.1
rm -f "$H/.claude/.claude-html.update"; save
cp "$CONF" "$T/conf.before"
out="$(ch --update off)"
check "off: one sentence" "$out" "The daily check for new releases is off. claude-html --update on turns it back on."
check "  one line of the conf, and nothing else" \
  "$(diff "$T/conf.before" "$CONF" | grep -c '^[<>]') $(grep -c '^CLAUDE_HTML_UPDATE_CHECK="off"$' "$CONF")" "1 1"
n="$(asked)"; sed "s/^checked=.*/checked=0/" "$H/.claude/.claude-html.update" > "$T/st" && mv "$T/st" "$H/.claude/.claude-html.update"
(cd "$PROJ/app" && run bash "$INST/save-conversation.sh" --try </dev/null >/dev/null 2>&1)
check "  a save asks nothing" "$(asked)" "$n"
hasnt "  the notice gone from the index" "$(cat "$INST/index.html")" '"update":"'
hasnt "  and the terminal" "$(build)" "is out"
has "  status says it is off" "$(ch --update status)" "the daily check is off"
out="$(ch --update)"
check "  the update by hand still works" "$(branch) $(at)" "main v3.1.0"
clone a v3.0.1
out="$(ch --update on)"
check "on: one sentence" "$out" "The daily check for new releases is on. claude-html --update off turns it off."
check "  the same line, changed back" "$(diff "$T/conf.before" "$CONF" | grep -c '^[<>]') $(grep -c '^CLAUDE_HTML_UPDATE_CHECK=' "$CONF")" "1 1"
n="$(asked)"; (cd "$PROJ/app" && run bash "$INST/save-conversation.sh" --try </dev/null >/dev/null 2>&1)
check "  and the next save asks again" "$(( $(asked) - n )) $(state newest)" "1 3.1.0"
out="$(run CLAUDE_HTML_UPDATE_CHECK=off bash "$INST/claude-html" --update on 2>&1 </dev/null)"
has "an environment that disagrees is said to win" "$out" "CLAUDE_HTML_UPDATE_CHECK=off in your environment wins"
out="$(run CLAUDE_HTML_UPDATE_CHECK=off bash "$INST/claude-html" --update status 2>&1 </dev/null)"
has "  in status too" "$out" "CLAUDE_HTML_UPDATE_CHECK=off in the environment wins"
save
out="$(ch --doctor)"
has "--doctor: version, newest known, when checked" "$out" "update    3.0.1 · newest known 3.1.0 · last checked"
ch --update off >/dev/null
has "  or that checks are off" "$(ch --doctor)" "update    3.0.1 · checks off"

# ── the automatic update ────────────────────────────────────────────
# A save nobody waits on starts it, detached, once the save is over: what
# is checked is what it did once it has ended, never how long it took.
auto_wait() {
  local i
  settle
  for i in $(seq 1 600); do
    ps ax -o command= 2>/dev/null | grep -F -- "update.sh $INST --auto" | grep -qv grep || { settle; return 0; }
    sleep 0.1
  done
}
asave() { (cd "$PROJ/app" && run CLAUDE_HTML_UPDATE_CHECK=on CLAUDE_HTML_AUTO_UPDATE="${AUTOSET:-on}" "$@" bash "$INST/save-conversation.sh" --try </dev/null >/dev/null 2>&1); auto_wait; }
seen() {   # the daily check's state, as if it had just seen <newest> for this clone
  printf 'checked=%s\nnewest=%s\nhere=%s\ntold=\n' "$(date +%s)" "$1" "$INST" > "$H/.claude/.claude-html.update"
}
clone a v3.0.1; : > "$T/installs"; rm -f "$H/.claude/.claude-html.update"
AUTOSET=off asave
check "auto-update off (the default): the daily check sees 3.1.0, nothing is installed" "$(state newest) $(at) $(installs)" "3.1.0 v3.0.1 "
check "  and its notice stays" "$(grep -c '"update":"3.1.0"' "$INST/index.html")" 1
asave
check "on: the next save over, 3.1.0 is installed, its install run" "$(at) $(branch) $(installs)" "v3.1.0 main 3.1.0"
check "  recorded: what, and when" "$(state auto) $([ "$(state autoat)" -gt 0 ] 2>/dev/null && echo at)" "3.1.0 at"
has "  the index says so for a day" "$(cat "$INST/index.html")" '"updated":{"to":"3.1.0"'
hasnt "  and no longer that it is out" "$(cat "$INST/index.html")" '"update":"3.1.0"'
SLN="$(printf '{"session_id":"s1"}' | run CLAUDE_HTML_TEST_NOW="$(state autoat)" NO_COLOR=1 bash "$INST/statusline.sh")"
check "  and the status line" "$SLN" "claude-html · updated to 3.1.0"
SLN="$(printf '{"session_id":"s1"}' | run CLAUDE_HTML_TEST_NOW="$(( $(state autoat) + 86400 ))" NO_COLOR=1 bash "$INST/statusline.sh")"
check "  a day later, not any more" "$SLN" "claude-html"
check "  its log says what it did, and nothing was left in the temp folder" \
  "$(grep -c 'Updated 3.0.1 → 3.1.0.' "$H/.claude/.claude-html.autoupdate.log") $(ls -d "${TMPDIR:-/tmp}"/claude-html-autoupdate.* 2>/dev/null | wc -l | tr -d ' ')" "1 0"

# A major release: said, never installed.
REMOTE="$BARE3" clone m v3.0.1 "$BARE3"; : > "$T/installs"; rm -f "$H/.claude/.claude-html.update"
REMOTE="$BARE3" asave; REMOTE="$BARE3" asave
check "a major release (4.0.0 from 3.0.1): not installed, held for the owner" "$(at) $(installs) $(state held)" "v3.0.1  4.0.0"
has "  and announced as ever" "$(cat "$INST/index.html")" '"update":"4.0.0"'
out="$(REMOTE="$BARE3" run bash "$INST/lib/update.sh" "$INST" --auto 2>&1; cat "$H/.claude/.claude-html.autoupdate.log")"
check "  even when --auto is started by hand" "$(at) $(installs)" "v3.0.1 "

# A development checkout: never, even with the state saying a release is out.
clone d v3.0.1; gitx -C "$INST" commit -q --allow-empty -m "my own work"; : > "$T/installs"
seen 3.1.0; asave
check "a development checkout (its HEAD not a release): untouched" "$(gitx -C "$INST" log -1 --format=%s) $(installs)" "my own work "
clone a v3.0.1; mkdir -p "$INST/dev"; : > "$T/installs"
seen 3.1.0; asave
check "  a clone at a release with a dev/ folder, the owner's own: untouched" "$(at) $(installs)" "v3.0.1 "
rmdir "$INST/dev"

# From the save Claude Code waits on, or any save that is not detached: never.
seen 3.1.0
(cd "$PROJ/app" && run CLAUDE_HTML_UPDATE_CHECK=on CLAUDE_HTML_AUTO_UPDATE=on CLAUDE_HTML_TRANSCRIPT=/nonexistent bash "$INST/save-conversation.sh" </dev/null >/dev/null 2>&1); auto_wait
check "a save in the foreground (not detached): it starts nothing" "$(at) $(installs)" "v3.0.1 "

# A save running: put off, then done when the next save is over.
sleep 60 & SLEEPER=$!; SLEEPERS="$SLEEPERS $SLEEPER"
mkdir -p "$H/.claude/.claude-html.lock"; echo "$SLEEPER" > "$H/.claude/.claude-html.lock/pid"
seen 3.1.0
run CLAUDE_HTML_UPDATE_CHECK=on CLAUDE_HTML_AUTO_UPDATE=on bash "$INST/lib/update.sh" "$INST" --auto >/dev/null 2>&1
check "a save holding the lock: put off, nothing moved" "$(at) $(installs) $(state deferred)" "v3.0.1  3.1.0"
has "  and said so in its log" "$(cat "$H/.claude/.claude-html.autoupdate.log")" "a save is running: put off"
kill "$SLEEPER" 2>/dev/null; rm -rf "$H/.claude/.claude-html.lock"
asave
check "  the next save over: installed" "$(at) $(installs) $(state deferred)" "v3.1.0 3.1.0 "

# A failure: rolled back, the old release working, tried again a day later.
clone a v3.0.1; : > "$T/installs"; touch "$T/fail-install-3.1.0"
seen 3.1.0; asave
check "a failed install: back on 3.0.1, its own install run again" "$(at) $(branch) $(installs)" "v3.0.1 main 3.1.0 3.0.1"
check "  recorded as failed, nothing said as installed" "$(state failed) $(state auto)" "3.1.0 "
rm -f "$INST/sessions/$ID.html"; out="$(build)"; rc=$?
check "  and the old release still builds its pages" "$rc $([ -f "$INST/sessions/$ID.html" ] && echo built) $(cat "$INST/VERSION")" "0 built 3.0.1"
: > "$T/installs"; asave
check "  not tried again after the next reply" "$(installs)" ""
sed "s/^failedat=.*/failedat=$(( $(date +%s) - 90000 ))/" "$H/.claude/.claude-html.update" > "$T/st" && mv "$T/st" "$H/.claude/.claude-html.update"
rm -f "$T/fail-install-3.1.0"; asave
check "  a day later, tried again, and done" "$(at) $(installs) $(state failed)" "v3.1.0 3.1.0 "

# Through --config and the Settings page's link, as every setting.
clone a v3.0.1
ch --config set AUTO_UPDATE=on >/dev/null
check "--config set AUTO_UPDATE=on: one line in the conf" "$(grep -c '^CLAUDE_HTML_AUTO_UPDATE="on"$' "$CONF")" 1
ch --config unset AUTO_UPDATE >/dev/null

echo
verdict
