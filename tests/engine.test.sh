#!/bin/bash
# Which engine does the data work. node when a working one is here, wherever
# it was installed; osascript when not; never a failed save because of the
# setting that chooses between them.
#
#   bash tests/engine.test.sh
#
# Every node here is a fake in a temp folder, a script that runs the real one
# or refuses to, and the usual places are pointed at them, so the machine's
# own node and PATH decide nothing.
set -u

. "$(dirname "$0")/lib.sh"

HERE="$(cd "$(dirname "$0")/.." && pwd)"
pass=0; fail=0
check() {
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); printf '  ok    %s\n' "$1"
  else fail=$((fail + 1)); printf '  FAIL  %s (expected %s, got %s)\n' "$1" "$3" "$2"; fi
}
T="$(cd "$(tmpdir chengine)" && pwd)"
trap 'rm -rf "$T"' EXIT

REAL="$(command -v node)"
OSA=no; [ -z "${CLAUDE_HTML_FORCE_NODE:-}" ] && command -v osascript >/dev/null 2>&1 && OSA=yes

# A node that works and notes each time it is run, and from where; one too
# old for the code, which notes any run but the check; one that cannot start
# at all; one that hangs; and a version manager's shim, which notes that it
# would have installed a node. Folder names with spaces, as a home can have.
fake() {   # folder, kind
  mkdir -p "$1"
  case "$2" in
    good) printf '#!/bin/sh\nprintf "%%s|%%s\\n" "$PWD" "$*" >> "%s/runs"\nexec "%s" "$@"\n' "$1" "$REAL" ;;
    old) printf '#!/bin/sh\n[ "$1" = -e ] && exit 3\nprintf "%%s\\n" "$*" >> "%s/runs"\nexec "%s" "$@"\n' "$1" "$REAL" ;;
    broken) printf '#!/bin/sh\nexit 1\n' ;;
    hangs) printf '#!/bin/sh\nexec sleep 30\n' ;;
    shim) printf '#!/bin/sh\necho installed >> "%s/installs"\nexec "%s" "$@"\n' "$1" "$REAL" ;;
  esac > "$1/node"
  chmod +x "$1/node"
}
fake "$T/good one" good
fake "$T/old one" old
fake "$T/broken one" broken
fake "$T/hangs" hangs
fake "$T/vm/.volta/bin" shim
fake "$T/vm/.volta/tools/image/node/20.0.0/bin" good
mkdir -p "$T/empty"
# The system's own commands, without any node a distribution put among them,
# so "no node on PATH" means that on every machine the suite runs on.
SYS="$T/system"; mkdir -p "$SYS"
for f in /usr/bin/* /bin/*; do
  case "${f##*/}" in node|nodejs) continue ;; esac
  [ -e "$SYS/${f##*/}" ] || ln -s "$f" "$SYS/${f##*/}"
done

# The pick, in a clean shell: only what is passed in is set.
pick() {   # PATH, node dirs, then VAR=value…
  local p="$1" d="$2"; shift 2
  env -u CLAUDE_HTML_ENGINE PATH="$p" CLAUDE_HTML_NODE_DIRS="$d" "$@" \
    /bin/bash -c '. "$0/platform.sh"; ch_pick_engine; printf "%s|%s|%s" "$CH_ENGINE" "$CH_NODE" "$CH_ENGINE_NOTE"' "$HERE"
}
engine() { pick "$@" | cut -d'|' -f1; }
nodeat() { pick "$@" | cut -d'|' -f2; }
note() { pick "$@" | cut -d'|' -f3; }
# Where there is no osascript, a machine without node can only say so.
WITHOUT=osascript; [ "$OSA" = yes ] || WITHOUT=node
# Where each run of the working node started.
wherefrom() { grep '|' "$T/good one/runs" | cut -d'|' -f1 | sort -u; }
# A project folder, for runs that must not start in it.
APP0="$T/a project"; mkdir -p "$APP0"

echo "finding node"
check "node on PATH does the data work" "$(engine "$T/good one:$SYS" "")" node
check "  and is the one used" "$(nodeat "$T/good one:$SYS" "")" "$T/good one/node"
check "a hook's thin PATH still finds node where it is usually installed" \
  "$(nodeat "$SYS" "$T/empty:$T/good one")" "$T/good one/node"
check "a node too old for the code is passed over" \
  "$(nodeat "$T/old one:$SYS" "$T/good one")" "$T/good one/node"
check "so is one that cannot start" \
  "$(nodeat "$T/broken one:$SYS" "$T/broken one:$T/good one")" "$T/good one/node"
check "no working node anywhere: osascript on a Mac, nothing else elsewhere" \
  "$(engine "$SYS" "$T/old one:$T/broken one:$T/empty")" "$WITHOUT"
check "  and nothing was installed to get one" "$(ls "$T/empty" | wc -l | tr -d ' ')" 0
check "a version manager's shim is passed over for the node it installed" \
  "$(nodeat "$T/vm/.volta/bin:$SYS" "$T/vm/.volta/bin:$T/vm/.volta/tools/image/node/20.0.0/bin")" \
  "$T/vm/.volta/tools/image/node/20.0.0/bin/node"
check "  and never run, so it cannot fetch one" "$(cat "$T/vm/.volta/bin/installs" 2>/dev/null | wc -l | tr -d ' ')" 0
rm -f "$T/good one/runs"
(cd "$APP0" && nodeat "$T/good one:$SYS" "" >/dev/null)
check "node is checked from /, not from the project a version manager reads" \
  "$(wherefrom)" /
started=$(date +%s)
check "one that hangs is given up on" \
  "$(nodeat "$T/hangs:$SYS" "$T/good one" CH_NODE_PROBE_LIMIT=1)" "$T/good one/node"
check "  within moments" "$(( $(date +%s) - started < 10 ))" 1

# No usable node and no osascript: nothing runs, and it says why, as
# --doctor does, rather than running the node it turned down.
# A script of its own, which does nothing, so a run that should not happen
# cannot touch anything either.
rm -f "$T/old one/runs"; printf '1;\n' > "$T/nothing.js"
refused="$(env -u CLAUDE_HTML_ENGINE HOME="$T/home" PATH="$T/old one:$SYS" CLAUDE_HTML_NODE_DIRS="" CLAUDE_HTML_FORCE_NODE=1 \
  /bin/bash -c '. "$0/platform.sh"; ch_pick_engine; ch_js "$1"; echo "status $?"' "$HERE" "$T/nothing.js" 2>&1)"
check "with only a node too old and no osascript, nothing is run" "$(cat "$T/old one/runs" 2>/dev/null | wc -l | tr -d ' ')" 0
check "  and it says why" "$(printf '%s\n' "$refused" | sed -n 1p)" \
  "claude-html: no working node 14.14 or later and no osascript: the pages cannot be built until there is one"
check "  and fails" "$(printf '%s\n' "$refused" | sed -n 2p)" "status 127"

echo "choosing"
if [ "$OSA" = yes ]; then
  check "CLAUDE_HTML_ENGINE=osascript chooses osascript, node or not" \
    "$(engine "$T/good one:$SYS" "" CLAUDE_HTML_ENGINE=osascript)" osascript
  check "CLAUDE_HTML_ENGINE=node with no node falls back to osascript" \
    "$(engine "$SYS" "$T/empty" CLAUDE_HTML_ENGINE=node)" osascript
  check "  and says why" "$(note "$SYS" "$T/empty" CLAUDE_HTML_ENGINE=node)" \
    "CLAUDE_HTML_ENGINE=node, but no working node 14.14 or later was found"
fi
check "CLAUDE_HTML_ENGINE=node chooses node" \
  "$(engine "$T/good one:$SYS" "" CLAUDE_HTML_ENGINE=node)" node
check "a choice that is neither is ignored" \
  "$(engine "$T/good one:$SYS" "" CLAUDE_HTML_ENGINE=jsc)" node
check "  with a note" "$(note "$T/good one:$SYS" "" CLAUDE_HTML_ENGINE=jsc)" \
  "CLAUDE_HTML_ENGINE=jsc is neither osascript nor node, so it is ignored"
check "CLAUDE_HTML_FORCE_NODE still means node" \
  "$(engine "$T/good one:$SYS" "" CLAUDE_HTML_FORCE_NODE=1)" node
check "  and outranks a choice of osascript, with a note" \
  "$(engine "$T/good one:$SYS" "" CLAUDE_HTML_FORCE_NODE=1 CLAUDE_HTML_ENGINE=osascript)|$(note "$T/good one:$SYS" "" CLAUDE_HTML_FORCE_NODE=1 CLAUDE_HTML_ENGINE=osascript)" \
  "node|CLAUDE_HTML_ENGINE=osascript, but there is no osascript here"

# ── what a save and the command actually run ──────────────────────────
ROOT="$T/root"; APP="$ROOT/app"; H="$T/home"
D="$(printf '%s' "$APP" | tr '/' '-')"
mkdir -p "$H/.claude/projects/$D" "$APP" "$ROOT/pages"
CONF="$H/.claude/claude-html.conf"
printf 'CLAUDE_HTML_ROOT="%s"\nCLAUDE_HTML_OUT="%s"\n' "$ROOT" "$ROOT/pages" > "$CONF"
ID=eeeeeeee-0000-0000-0000-000000000007
J="$H/.claude/projects/$D/$ID.jsonl"
printf '%s\n' "{\"type\":\"user\",\"cwd\":\"$APP\",\"timestamp\":\"2026-11-06T10:00:00Z\",\"message\":{\"role\":\"user\",\"content\":\"which engine saved me\"}}" > "$J"
NOTE="{\"session_id\":\"$ID\",\"transcript_path\":\"$J\",\"cwd\":\"$APP\",\"hook_event_name\":\"Stop\"}"
save() {   # then VAR=value…
  rm -f "$T/good one/runs" "$APP/.claude/.claude-conversations/$ID.json"
  rm -rf "$ROOT/pages/sessions"
  printf '%s' "$NOTE" | env -u CLAUDE_HTML_ENGINE HOME="$H" \
    PATH="$SYS" CLAUDE_HTML_NODE_DIRS="$T/good one" "$@" \
    /bin/bash -c "cd '$APP' && /bin/bash '$HERE/save-conversation.sh' --try" >/dev/null 2>&1
}
ran() { grep -c "$1" "$T/good one/runs" 2>/dev/null || echo 0; }
saved() { [ -s "$APP/.claude/.claude-conversations/$ID.json" ] && [ -s "$ROOT/pages/sessions/$ID.html" ] && echo yes || echo no; }

echo "saving"
save
check "a save with node here archives with it" "$(ran archive.js)" 1
check "  and builds the pages with it" "$(ran convert.js)" 1
check "  and both are written" "$(saved)" yes
check "  and node ran from /, not from the project" "$(wherefrom)" /
save CLAUDE_HTML_ENGINE=bogus
check "a bad choice does not cost the save" "$(saved)" yes
if [ "$OSA" = yes ]; then
  save CLAUDE_HTML_ENGINE=osascript
  check "with osascript chosen, node runs none of it" "$(ran archive.js)+$(ran convert.js)" "0+0"
  check "  and the save is made all the same" "$(saved)" yes
  printf 'CLAUDE_HTML_ENGINE=osascript\n' >> "$CONF"
  save
  check "the conf can choose too" "$(ran convert.js)" 0
  save CLAUDE_HTML_ENGINE=node
  check "  and the environment wins over the conf" "$(ran convert.js)" 1
  sed -i.bak '/CLAUDE_HTML_ENGINE/d' "$CONF" && rm -f "$CONF.bak"
fi

# The actions behind the links, where they are node's (no osascript): with
# the node that was found, which a thin PATH does not have.
NOOSA="$T/system-no-osascript"; mkdir -p "$NOOSA"
for f in "$SYS"/*; do [ "${f##*/}" = osascript ] || ln -s "$(readlink "$f")" "$NOOSA/${f##*/}"; done
rm -f "$T/good one/runs"
env -u CLAUDE_HTML_ENGINE HOME="$H" PATH="$NOOSA" CLAUDE_HTML_NODE_DIRS="$T/good one" CLAUDE_HTML_FORCE_NODE=1 \
  /bin/bash "$HERE/claude-html" --open-plan "$ID" >/dev/null 2>&1
check "an action on a thin PATH runs the node that was found" "$(ran open.js)" 1

echo "doctor"
doctor() {
  env -u CLAUDE_HTML_ENGINE HOME="$H" PATH="$SYS" "$@" \
    /bin/bash "$HERE/claude-html" --doctor 2>&1
}
field() { sed -n "s/^  $1 *//p" | head -n 1; }
check "--doctor names the engine and the node" \
  "$(doctor CLAUDE_HTML_NODE_DIRS="$T/good one" | field engine | sed 's/ [0-9.]* / /; s/)   .*/)/')" "node ($T/good one/node)"
check "  and why" "$(doctor CLAUDE_HTML_NODE_DIRS="$T/good one" | field engine | sed 's/.*)   //')" \
  "node is here, and is the faster of the two"
check "  and a choice it set aside" \
  "$(doctor CLAUDE_HTML_NODE_DIRS="$T/good one" CLAUDE_HTML_ENGINE=jsc | field note)" \
  "CLAUDE_HTML_ENGINE=jsc is neither osascript nor node, so it is ignored"
if [ "$OSA" = yes ]; then
  check "  and says so when it is osascript, and why" \
    "$(doctor CLAUDE_HTML_NODE_DIRS="$T/empty" | field engine)" \
    "osascript   no working node 14.14 or later here, so the system's own osascript"
fi

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
