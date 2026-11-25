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
# code paths, and node doing the data work, can be exercised on a Mac. The GNU userland it cannot fake is
# what the Linux half of CI is for.
if [ -z "${CLAUDE_HTML_FORCE_NODE:-}" ] && command -v osascript >/dev/null 2>&1; then
  run_js() { osascript -l JavaScript "$@"; }; HAVE_OSASCRIPT=true
  # Left to itself, a save on a Mac with node would build with node, and the
  # osascript half of every suite would go untested. engine.test.sh is where
  # the choice itself is tested.
  export CLAUDE_HTML_ENGINE=osascript
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

# No suite may tell macOS to route claude-html:// links to an app it built in
# a temp folder: the folder goes, the routing stays, and the real delete
# button breaks. helper-build.sh refuses temp paths on its own; this says it
# out loud for everything a test launches.
export CLAUDE_HTML_NO_REGISTER=1

# No suite reads the owner's own list of secrets, nor takes on a switch
# from the shell it was started in: each one that needs a list makes its own.
unset CLAUDE_HTML_REDACT
export CLAUDE_HTML_REDACT_FILE="${TMPDIR:-/tmp}/claude-html-tests-no-such.redact"

# No suite may ask the network whether a release is out: a contributor runs
# them from a clone of the release repository, where the daily check would.
# update.test.sh turns it on against repositories of its own.
export CLAUDE_HTML_UPDATE_CHECK=off
export CLAUDE_HTML_UPDATE_REMOTE="${TMPDIR:-/tmp}/claude-html-tests-no-such-remote"

# Nothing on the screen of whoever runs a suite: no page, folder or terminal
# opened, no window, no banner (ch_screen_off in platform.sh). run-all.sh
# points it at a file it checks; a suite run alone throws the record away.
# One that tests showing something unsets it for its own stand-ins.
export CLAUDE_HTML_NO_SCREEN="${CLAUDE_HTML_NO_SCREEN:-/dev/null}"

# Whether text on stdin is laid out as --doctor lays everything out: its
# header, then titled sections a single blank line apart, each line two
# spaces and a label padded to the one width all labels share, or a wrapped
# value's next line under the value column. With a width, no line is wider,
# unless it is one word that is (and the dot after it). Prints "ok" or what
# is wrong, and where.
#   doctor_layout [header|noheader] [width]
doctor_layout() {
  LC_ALL=C awk -v head="${1:-header}" -v width="${2:-0}" '
    function len(s,  t) { t = s; return length(s) - gsub(/[\200-\277]/, "", t) }
    function bad(why) { if (!err) err = why " at line " NR ": [" $0 "]" }
    {
      if (NR == 1 && head == "header") {
        if ($0 !~ /^claude-html doctor · [^ ]+$/) bad("no header"); prev = "header"; next
      }
      if ($0 == "") {
        if (prev == "blank") bad("two blank lines")
        else if (prev == "title") bad("an empty section")
        prev = "blank"; next
      }
      if (prev == "blank") {
        if ($0 !~ /^[A-Za-z][^ ]*( [^ ]+)*$/) bad("no title after a blank line"); prev = "title"; next
      }
      if (prev == "header") bad("no blank line after the header")
      if (match($0, /^  [a-z][a-z-]* +[^ ]/)) {
        if (!col) col = RLENGTH
        if (RLENGTH != col) bad("a value not in the value column (" col ")")
        lab = substr($0, 3, col - 3); sub(/ +$/, "", lab)
        if (col - 3 - length(lab) < 2) bad("a label without two spaces after it")
        rest = substr($0, col)
      } else if (col && substr($0, 1, col - 1) ~ /^ +$/ && substr($0, col, 1) != " " && prev != "title") {
        rest = substr($0, col)
      } else { bad("a line out of the layout"); rest = "" }
      sub(/ ·$/, "", rest)
      if (width > 0 && len($0) > width && rest ~ / /) bad("a line wider than " width)
      prev = "item"
    }
    END {
      if (prev == "blank") bad("a blank line at the end")
      if (!NR) err = "nothing at all"
      print err ? err : "ok"
    }'
}
