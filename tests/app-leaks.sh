#!/bin/bash
# How many helper apps one run of the suites left registered with macOS:
# those under that run's own temp folder, and this clone's own unless it is
# the installed copy. An app another run made - another worktree's gate, the
# release script - is that run's to answer for, not this one's.
#
#   bash tests/app-leaks.sh <run folder> <clone> [<lsregister -dump output>]
#
# Prints the count. run-all.sh runs every suite with TMPDIR inside its run
# folder, so each app a suite built in a temp folder is under it. The dump
# can be given as a file, which is how screen.test.sh tries it.
set -u
RUN="$1"; CLONE="$2"; DUMP="${3:-}"
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
if [ -n "$DUMP" ]; then D="$(cat "$DUMP")"
elif [ -x "$LSREG" ]; then D="$("$LSREG" -dump 2>/dev/null)"
else D=""; fi

# The run folder as given and as the disk has it (/var is /private/var).
RUNP="$(cd "$RUN" 2>/dev/null && pwd -P)" || RUNP="$RUN"
paths() { printf '%s\n' "$D" | sed -n 's/^path:[[:space:]]*//p' | sed 's/ (0x[0-9a-fA-F]*)$//'; }
n="$(paths | grep -F -e "$RUN/" -e "$RUNP/" | grep -c '/Claude HTML\.app$' || true)"
# Nor this clone's own, unless it is the installed copy.
INSTALLED_AT="$(cd "$(dirname "$(readlink "$HOME/.local/bin/claude-html" 2>/dev/null)")" 2>/dev/null && pwd -P)"
if [ "$INSTALLED_AT" != "$CLONE" ] && paths | grep -qxF "$CLONE/Claude HTML.app"; then n=$((n + 1)); fi
echo "${n:-0}"
