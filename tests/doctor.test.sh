#!/bin/bash
# What --doctor prints, laid out one way: its header, titled sections a
# single blank line apart, every line two spaces and a label padded to one
# width, and a value too wide for the terminal wrapped under the value
# column, never inside a word. A pipe gets one line per item.
#
#   bash tests/doctor.test.sh
#
# --doctor reads and writes nothing of the owner's: it runs here in a home
# and a pages folder of its own. The Linux desktops' doctor is checked in
# linux.test.sh, against the desktops it fakes; the guard's own command in
# guard.test.sh.
set -u

. "$(dirname "$0")/lib.sh"

HERE="$(cd "$(dirname "$0")/.." && pwd)"
check() { check_long "$@"; }
T="$(cd "$(tmpdir chdoctor)" && pwd)"
trap 'rm -rf "$T"' EXIT

# A home whose projects folder has a long name, so that one word is wider
# than a narrow terminal and must be left whole.
H="$T/home"; ROOT="$T/projects-with-a-name-far-too-long-for-a-narrow-terminal"; OUT="$ROOT/pages"
mkdir -p "$H/.claude" "$OUT"
printf 'CLAUDE_HTML_ROOT="%s"\nCLAUDE_HTML_OUT="%s"\n' "$ROOT" "$OUT" > "$H/.claude/claude-html.conf"
doctor() { env -u COLUMNS -u CLAUDE_HTML_DOCTOR_COLUMNS HOME="$H" "$@" bash "$HERE/claude-html" --doctor 2>&1; }
# The text with each wrapped value put back on one line.
unwrap() { awk '/^ {12}[^ ]/ && prev != "" { sub(/^ +/, ""); prev = prev " " $0; next }
                { if (NR > 1) print prev; prev = $0 } END { print prev }'; }
labels() { sed -n 's/^  \([a-z][a-z-]*\)  *[^ ].*/\1/p' | tr '\n' ' ' | sed 's/ $//'; }

echo "the layout"
D="$(doctor)"
check "one header, sections a blank line apart, every line two spaces and a padded label" \
  "$(printf '%s\n' "$D" | doctor_layout)" ok
check "  the header names the version" "$(printf '%s\n' "$D" | head -1)" "claude-html doctor · $(cat "$HERE/VERSION")"
check "  the sections, in order" "$(printf '%s\n' "$D" | grep '^[A-Za-z]' | sed 1d | tr '\n' '|')" \
  "This machine|Tools|claude-html|Protection|Limits|"
check "  every label, in order, each once" \
  "$(printf '%s\n' "$D" | labels | sed 's/ note / /')" \
  "system desktop session wsl terminal opener trash dialog links engine missing update pages private projects git redact archives guard limits"
check "  one value column, under the widest label" \
  "$(printf '%s\n' "$D" | sed -n 's/^\(  [a-z][a-z-]*  *\)[^ ].*/\1/p' | awk '{ print length($0) }' | sort -u)" 12
check "  one separator: no gap of three spaces inside a value" \
  "$(printf '%s\n' "$D" | sed 's/^ *[a-z-]*  *//' | grep -c '   ')" 0
check "  what was 'unavailable:' is a labelled line" \
  "$(printf '%s\n' "$D" | grep -c '^  missing   ') $(printf '%s\n' "$D" | grep -c '^ *unavailable:')" "1 0"
check "  the guard has its label too" "$(printf '%s\n' "$D" | grep -c '^  guard     o[nf]')" 1
check "  not a terminal: nothing is wrapped, even with COLUMNS set" \
  "$(doctor COLUMNS=40 | grep -c '^            ')" 0

echo "wrapping, as at a terminal that wide"
for w in 120 80 60 40; do
  N="$(doctor CLAUDE_HTML_DOCTOR_COLUMNS=$w)"
  check "$w columns: the same layout, no line wider unless one word is" \
    "$(printf '%s\n' "$N" | doctor_layout header "$w")" ok
  check "  and the same words: put back on one line, it is the unwrapped doctor" \
    "$(printf '%s\n' "$N" | unwrap)" "$(printf '%s\n' "$D" | unwrap)"
done
check "at 60 columns, something does wrap" "$(doctor CLAUDE_HTML_DOCTOR_COLUMNS=60 | grep -c '^            [^ ]' | awk '$1 > 0 { print "yes" }')" yes
check "  and a folder wider than that is left whole" \
  "$(doctor CLAUDE_HTML_DOCTOR_COLUMNS=40 | grep -cxF "  projects  $ROOT")" 1

echo "the helper"
dl() { env -u COLUMNS bash -c '. "$1/lib/platform.sh"; shift; ch_dl "$@"' _ "$HERE" "$@"; }
check "values joined by ' · ', the empty ones left out" "$(dl trash gio "" "gio trash -- <file>")" \
  "  trash     gio · gio trash -- <file>"
check "a label and nothing else has no trailing spaces" "$(dl wsl "" | tr ' ' _)" "__wsl"
LONG="on · 3 safe value(s) · hooks 2 of 2 in settings.json · asks in a dialog when someone is at the screen · waits 1 minute"
check "a pipe gets it on one line" "$(dl guard "$LONG" | wc -l | tr -d ' ')" 1
check "wrapped, it breaks at ' · ' first, the dot ending the line" \
  "$(CLAUDE_HTML_DOCTOR_COLUMNS=60 dl guard "$LONG" | tr '\n' '|')" \
  "  guard     on · 3 safe value(s) ·|            hooks 2 of 2 in settings.json ·|            asks in a dialog when someone is at the screen ·|            waits 1 minute|"
check "  then at a space, when a part is wider than the room" \
  "$(CLAUDE_HTML_DOCTOR_COLUMNS=40 dl guard "$LONG" | tr '\n' '|')" \
  "  guard     on · 3 safe value(s) ·|            hooks 2 of 2 in|            settings.json ·|            asks in a dialog when|            someone is at the screen ·|            waits 1 minute|"
check "  never inside a word" \
  "$(CLAUDE_HTML_DOCTOR_COLUMNS=32 dl pages "in /a/folder/name/far/longer/than/the/room/is" | tr '\n' '|')" \
  "  pages     in|            /a/folder/name/far/longer/than/the/room/is|"
check "a value of several lines: each under the first" \
  "$(dl git "2 folders:
/one
/two" | tr '\n' '|')" "  git       2 folders:|            /one|            /two|"
check "  and each of them wrapped the same way" \
  "$(CLAUDE_HTML_DOCTOR_COLUMNS=32 dl git "two folders git would commit:
/one" | tr '\n' '|')" "  git       two folders git|            would commit:|            /one|"
check "a section: one blank line, then its title" "$(bash -c '. "$1/lib/platform.sh"; ch_dl_section Tools' _ "$HERE" | tr '\n' '|')" "|Tools|"
check "nor one too narrow to leave 20 for the value" \
  "$(CLAUDE_HTML_DOCTOR_COLUMNS=31 dl guard "$LONG" | wc -l | tr -d ' ')" 1
check "a width that is not a number wraps nothing" \
  "$(CLAUDE_HTML_DOCTOR_COLUMNS=wide dl guard "$LONG" | wc -l | tr -d ' ')" 1
check "the dry-run command reads as typed, quoted only where it must be" \
  "$(bash -c '. "$1/lib/platform.sh"; CH_DRY=show ch_run /usr/bin/open "<launcher>.command" "a b" "it'"'"'s" "\$x" ""' _ "$HERE")" \
  "/usr/bin/open <launcher>.command \"a b\" \"it's\" '\$x' ''"

# At a real terminal: a pseudo-terminal from script(1), which puts nothing on
# the screen. COLUMNS says how wide it is.
echo "at a terminal"
on_tty() {   # command…, in a pseudo-terminal 50 columns wide
  if script --version 2>/dev/null | grep -q util-linux; then
    COLUMNS=50 script -qec "$(ch_quote_args "$@")" /dev/null </dev/null
  else COLUMNS=50 script -q /dev/null "$@" </dev/null; fi 2>/dev/null | tr -d '\r' | sed 's/^^D[[:cntrl:]]*//'
}
. "$HERE/lib/platform.sh"
if command -v script >/dev/null 2>&1 && [ -n "$(on_tty echo yes)" ]; then
  Y="$(on_tty env -u CLAUDE_HTML_DOCTOR_COLUMNS HOME="$H" bash "$HERE/claude-html" --doctor)"
  check "a terminal 50 wide is wrapped to it" "$(printf '%s\n' "$Y" | doctor_layout header 50)" ok
  check "  and the same words" "$(printf '%s\n' "$Y" | unwrap)" "$(printf '%s\n' "$D" | unwrap)"
else
  echo "  skip  no script(1) to make a terminal with"
fi

echo
verdict
