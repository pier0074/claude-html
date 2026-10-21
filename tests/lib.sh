#!/bin/bash
# Shared by every suite: the same tests run on macOS and on Linux, under
# whichever JavaScript engine the machine has.
#
#   . "$(dirname "$0")/lib.sh"
#
#   run_js file.js args…    osascript on macOS, node elsewhere
#   tmpdir prefix           a temp dir both mktemps agree to make
#   size_of file            bytes, from either stat
#   mtime_of file           whole seconds, from either stat
#   need_osascript          end a macOS-only suite as a clean skip

# CLAUDE_HTML_FORCE_NODE=1 pretends osascript is not there, so the Linux
# code paths can be exercised on a Mac. The GNU userland it cannot fake is
# what the Linux half of CI is for.
if [ -z "${CLAUDE_HTML_FORCE_NODE:-}" ] && command -v osascript >/dev/null 2>&1; then
  run_js() { osascript -l JavaScript "$@"; }; HAVE_OSASCRIPT=true
else
  run_js() { node "$@"; }; HAVE_OSASCRIPT=false
fi

# BSD mktemp takes -t prefix; GNU mktemp wants X's in a template. A literal
# template under TMPDIR is the one spelling they both accept.
tmpdir() { mktemp -d "${TMPDIR:-/tmp}/$1.XXXXXX"; }

# GNU first: BSD's stat -c genuinely fails, but GNU's stat -f means
# "filesystem status" and SUCCEEDS — printing the mount point where a
# timestamp should be. CI on real Ubuntu caught that.
size_of()  { stat -c %s "$1" 2>/dev/null || stat -f %z "$1"; }
mtime_of() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"; }

need_osascript() {
  if [ "$HAVE_OSASCRIPT" != true ]; then
    echo "  skip  $1 is macOS-only — nothing to test here"
    exit 0
  fi
}
