#!/bin/bash
# Every suite, one verdict. What CI runs, on macOS and on Linux, and what a
# contributor runs before pushing:
#
#   bash tests/run-all.sh
#
# On macOS the macOS-only suites run too; on Linux they skip and say so.
# CLAUDE_HTML_TEST_JOBS (how many at once) and CLAUDE_HTML_TEST_NICE (their
# priority, 10 by default; 0 for full) are in docs/SETUP.md.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
failed=0
# One gate at a time on this machine: two at once take each about twice as
# long, and more than that slows every one of them to a crawl. A second run
# waits here for the first to end. The lock holds the owner's pid: one whose
# process is gone (killed, the machine restarted) is taken over.
# CLAUDE_HTML_TEST_LOCK names another lock (docs/SETUP.md); "off" takes none.
GLOCK="${CLAUDE_HTML_TEST_LOCK:-/tmp/claude-html-gate.$(id -u).lock}"
if [ "$GLOCK" != off ]; then
  said=no
  until mkdir "$GLOCK" 2>/dev/null; do
    gp="$(cat "$GLOCK/pid" 2>/dev/null)"
    if [ -n "$gp" ] && ! kill -0 "$gp" 2>/dev/null; then
      rm -rf "$GLOCK"; continue
    fi
    # Just made, its pid not written yet; or left with none by a run killed
    # between the two: after a minute it is taken over too.
    if [ -z "$gp" ] && [ -n "$(find "$GLOCK" -maxdepth 0 -mmin +1 2>/dev/null)" ]; then
      rm -rf "$GLOCK"; continue
    fi
    [ "$said" = yes ] || { echo "waiting for another gate to end (pid ${gp:-?})"; said=yes; }
    sleep 2
  done
  echo $$ > "$GLOCK/pid"
fi
# What a pass is recorded for: this exact tree, and how it was run. A clone
# with changes not committed records nothing, nor one outside git (CI's).
# The CLAUDE_HTML_ settings it was started with are part of how; the run's
# own count and priority are not, they change no check.
MODE="$(env | LC_ALL=C sort | grep '^CLAUDE_HTML_' | grep -Ev '^CLAUDE_HTML_TEST_JOBS=|^CLAUDE_HTML_TEST_NICE=|^CLAUDE_HTML_TEST_LOCK=' | cut -d= -f1 | paste -s -d, -)"
TREE=""
if git -C "$HERE/.." rev-parse --git-dir >/dev/null 2>&1 && [ -z "$(git -C "$HERE/.." status --porcelain 2>/dev/null)" ]; then
  TREE="$(git -C "$HERE/.." rev-parse 'HEAD^{tree}' 2>/dev/null)"
fi
# The suites run node directly below, without lib.sh: nothing of the
# owner's own redaction settings may reach them.
unset CLAUDE_HTML_REDACT
export CLAUDE_HTML_REDACT_FILE="${TMPDIR:-/tmp}/claude-html-tests-no-such.redact"
# Nor ask the network whether a release is out.
export CLAUDE_HTML_UPDATE_CHECK=off
export CLAUDE_HTML_UPDATE_REMOTE="${TMPDIR:-/tmp}/claude-html-tests-no-such-remote"
# Nor register anything with the system, whoever runs them: inside the
# tests' own homes the "only the installed copy registers" rule cannot see
# the real install, and a second app claiming claude-html:// links breaks them.
export CLAUDE_HTML_NO_REGISTER=1
# No suite may build the helper app in this clone either: macOS registers an
# app as soon as it appears. One that was not here before the run is a
# failure, said below, and taken away, unregistered first.
CLONE="$(cd "$HERE/.." && pwd -P)"
HAD_APP=no; [ -e "$CLONE/Claude HTML.app" ] && HAD_APP=yes

# The suites run side by side: each works in a folder and a home of its
# own, so none can see another. CLAUDE_HTML_TEST_JOBS=1 runs them one after
# another, as they used to be.
JOBS="${CLAUDE_HTML_TEST_JOBS:-}"
if [ -z "$JOBS" ]; then
  n="$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"
  JOBS=$(( n / 2 )); [ "$JOBS" -lt 2 ] && JOBS=2; [ "$JOBS" -gt 6 ] && JOBS=6
fi
case "$JOBS" in ''|*[!0-9]*|0) JOBS=1 ;; esac
# Each suite at a lower priority, so the machine stays quick for whoever is
# at it; the run takes no longer when nothing else wants the CPU.
# CLAUDE_HTML_TEST_NICE=0 runs them at full priority, 1 to 19 at that one.
NICE="${CLAUDE_HTML_TEST_NICE:-10}"
case "$NICE" in ''|*[!0-9]*) NICE=10 ;; esac
[ "$NICE" -le 19 ] || NICE=19
OUTD="$(mktemp -d "${TMPDIR:-/tmp}/claude-html-tests.XXXXXX")" || exit 1
trap 'rm -rf "$OUTD"; [ "$GLOCK" = off ] || [ "$(cat "$GLOCK/pid" 2>/dev/null)" != $$ ] || rm -rf "$GLOCK"' EXIT
# Stopped part way (Ctrl-C, a kill, the terminal closed), it stops every
# suite it started, with their children and theirs: each suite runs in a
# process group of its own (set -m below), TERM first, then KILL for what is
# left after five seconds. Then the helper apps they built go, unregistered
# first, and the EXIT trap above takes the temp folder and the lock.
PGIDS=""
stopped() {   # signal, status
  trap '' INT TERM HUP
  local g i=0 a
  for g in $PGIDS; do kill -TERM -- "-$g" 2>/dev/null; done
  while [ $i -lt 25 ]; do
    a="$(ps -A -o pgid= -o stat= 2>/dev/null | awk -v g=" $PGIDS " 'index(g, " " $1 " ") && $2 !~ /^Z/' | grep -c .)"
    [ "$a" = 0 ] && break; sleep 0.2; i=$((i + 1))
  done
  for g in $PGIDS; do kill -KILL -- "-$g" 2>/dev/null; done
  LSREG_U=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  { [ "$HAD_APP" = no ] && [ -e "$CLONE/Claude HTML.app" ] && echo "$CLONE/Claude HTML.app"
    find "$RUNTMP" -type d -name 'Claude HTML.app' -prune 2>/dev/null; } | while IFS= read -r a; do
    [ -x "$LSREG_U" ] && "$LSREG_U" -u "$a" 2>/dev/null; rm -rf "$a"; done
  echo "interrupted ($1): the suites it started are stopped; SOMETHING FAILED"
  exit "$2"
}
trap 'stopped INT 130' INT; trap 'stopped TERM 143' TERM; trap 'stopped HUP 129' HUP
# Every temp folder a suite makes is in this run's own: what it leaves
# behind, a registered helper app above all, is known to be this run's.
RUNTMP="$OUTD/tmp"; mkdir -p "$RUNTMP"; export TMPDIR="$RUNTMP"

# Nor put anything on the screen of whoever runs them: no page, folder,
# server or terminal opened, no window, no banner. CLAUDE_HTML_NO_SCREEN
# makes the command, the hooks and open.js add what they would have shown
# to a file instead (ch_screen_off in platform.sh); and stand-ins for the
# tools that show things come first on the PATH, for anything that calls
# one by name past that switch. A suite that tests showing brings
# stand-ins of its own; one that reaches either of these is a failure,
# said below. osascript cannot be stood in for (it is an engine as well):
# screen.test.sh holds the suites' direct calls of it to a list.
export CLAUDE_HTML_NO_SCREEN="$OUTD/shown"
SHIM="$OUTD/screen-tools"; mkdir -p "$SHIM"
for o in open xdg-open gio wslview notify-send terminal-notifier zenity kdialog yad xmessage; do
  # gio does more than open: its trash, which the delete tests use, goes on.
  cat > "$SHIM/$o" <<EOF
#!/bin/sh
if [ "$o" = gio ] && [ "\${1:-}" != open ]; then
  PATH="\$(printf '%s' "\$PATH" | tr ':' '\n' | grep -vxF '$SHIM' | paste -s -d: -)" exec gio "\$@"
fi
printf '%s %s\n' "$o" "\$*" >> '$OUTD/shown.by-name'
exit 0
EOF
  chmod +x "$SHIM/$o"
done
export PATH="$SHIM:$PATH"
T0="$(date +%s)"

# The longest start first, so the last one to end is not a long one begun late.
QUICK="viewer diff index pages docs settingspage"
SUITES="incremental guard limits settings screen linux update layout usage prices engine install hooks backend archive redact races build agents delete open helper safety gate doctor"
run_one() {   # name
  local t="$1" s rc
  s="$(date +%s)"
  local pri=(); [ "$NICE" = 0 ] || pri=(nice -n "$NICE")
  case " $QUICK " in
    *" $t "*) ${pri[@]+"${pri[@]}"} node "$HERE/$t.test.js" > "$OUTD/$t.out" 2>&1 ;;
    *) ${pri[@]+"${pri[@]}"} bash "$HERE/$t.test.sh" > "$OUTD/$t.out" 2>&1 ;;
  esac
  rc=$?
  echo "$(( $(date +%s) - s ))" > "$OUTD/$t.secs"
  echo "$rc" > "$OUTD/$t.rc"
}
for t in $SUITES $QUICK; do
  while [ "$(jobs -rp | wc -l | tr -d ' ')" -ge "$JOBS" ]; do sleep 0.2; done
  # Its own process group, stdin from /dev/null as without set -m.
  set -m; run_one "$t" < /dev/null & PGIDS="$PGIDS $!"; set +m
done
wait

# The verdicts in a fixed order, whatever order they ended in.
for t in $QUICK $SUITES; do
  printf '%-9s ' "$t"
  rc="$(cat "$OUTD/$t.rc" 2>/dev/null || echo 1)"
  case " $QUICK " in
    *" $t "*) if [ "$rc" = 0 ]; then tail -1 "$OUTD/$t.out"; else tail -3 "$OUTD/$t.out"; failed=1; fi ;;
    # A suite passes on its own verdict, not on its exit status alone: one
    # cut short by an error (its clean-up then exiting 0) has no verdict.
    *) last="$(tail -1 "$OUTD/$t.out")"
       if [ "$rc" = 0 ] && printf '%s' "$last" | grep -Eq '[0-9]+ passed, 0 failed$|^ *skip '; then echo "$last"
       else grep -E "FAIL|failed" "$OUTD/$t.out" | tail -5
         [ "$rc" = 0 ] && echo "FAIL  ended without its verdict; its last lines:" && tail -3 "$OUTD/$t.out"
         [ -s "$OUTD/$t.out" ] || echo "no output"; failed=1; fi ;;
  esac
done

# Unregistered first: macOS registers an app by itself, and one deleted while
# still registered would be left claiming the links.
if [ "$HAD_APP" = no ] && [ -e "$CLONE/Claude HTML.app" ]; then
  LSREG_U=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  [ -x "$LSREG_U" ] && "$LSREG_U" -u "$CLONE/Claude HTML.app" 2>/dev/null
  rm -rf "$CLONE/Claude HTML.app"
  printf '%-9s FAIL  a suite built the helper app in this clone\n' "app"; failed=1
fi

# The suites build helper apps in temp folders. None of them may be left
# registered with macOS, or the real delete button launches a ghost. Only
# this run's: its suites' temp folders are all under $RUNTMP, and an app
# another run left (another worktree's gate, at the same time) is not this
# one's failure. Nor this clone's own, unless it is the installed copy.
if [ -x /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister ]; then
  leaked="$(bash "$HERE/app-leaks.sh" "$RUNTMP" "$CLONE")"
  printf '%-9s ' "leaks"
  if [ "${leaked:-0}" = 0 ]; then echo "no helper app registered from this run's temp folders or this clone"
  else echo "FAIL  $leaked helper app(s) registered from this run's temp folders or this clone"; failed=1; fi
fi

# The same on Linux: a handler registered from a temp folder would leave
# every claude-html:// link launching a script that is gone.
HF="${XDG_DATA_HOME:-$HOME/.local/share}/applications/claude-html-handler.desktop"
if [ "$(uname -s)" = Linux ]; then
  printf '%-9s ' "leaks"
  if [ -f "$HF" ] && grep -Eq '^Exec="?(/tmp/|/var/tmp/|/dev/shm/)' "$HF"; then
    echo "FAIL  the claude-html link handler points into a temp folder"; failed=1
  else echo "no link handler registered from a temp folder"; fi
fi

# Whatever a suite showed, or would have shown, without a stand-in of its own.
printf '%-9s ' "visible"
if [ -s "$OUTD/shown" ] || [ -s "$OUTD/shown.by-name" ]; then
  echo "FAIL  a suite reached a real page, window or banner; without the switch it would be on the screen:"
  cat "$OUTD/shown" "$OUTD/shown.by-name" 2>/dev/null | head -10 | cut -c1-160 | sed 's/^/            /'
  failed=1
else echo "nothing opened, no window, no banner"; fi

echo
SLOW="$(for t in $SUITES $QUICK; do printf '%s %s\n' "$(cat "$OUTD/$t.secs" 2>/dev/null || echo 0)" "$t"; done |
        sort -rn | head -3 | awk '{ printf "%s%s %ss", (NR > 1 ? ", " : ""), $2, $1 }')"
echo "$(( $(date +%s) - T0 ))s, $JOBS at a time$([ "$NICE" = 0 ] || echo ", nice $NICE"); longest: $SLOW"
[ "$failed" = 0 ] && echo "all suites passed" || echo "SOMETHING FAILED"
# A pass on a tree that is still the one tested, unchanged by the run:
# dev/release.sh does not run the gate again on it.
if [ "$failed" = 0 ] && [ -n "$TREE" ] && [ -z "$(git -C "$HERE/.." status --porcelain 2>/dev/null)" ] &&
   [ "$(git -C "$HERE/.." rev-parse 'HEAD^{tree}' 2>/dev/null)" = "$TREE" ]; then
  GD="$(cd "$HERE/.." && cd "$(git rev-parse --git-common-dir)" && pwd)" &&
  printf '%s %s %s %s\n' "$TREE" "$(date +%s)" "$(uname -s)" "${MODE:--}" >> "$GD/claude-html-gates-passed" 2>/dev/null
fi
exit "$failed"
