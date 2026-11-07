#!/bin/sh
# The claude-html link handler, on Linux: the desktop hands it a
# claude-html://<action>/<session id> link from the index, and it asks the
# claude-html command to do exactly that.
#
#   handler.sh 'claude-html://resume/0f6c…'
#
# Any web page can make a browser open such a link, so the link is checked
# before anything else happens and nothing from it ever reaches a shell: it
# must be one of three actions and a session id, with nothing before, after
# or between them. Which conversation that is, and every path involved, is
# looked up in the index's own manifest by the command, never taken from here.
#
# Deleting asks first, in a dialog of the desktop's own, or in a terminal
# window when there is no dialog tool; with neither, it refuses.

URL="${1:-}"
[ $# -eq 1 ] || { echo "handler.sh: expected one link" >&2; exit 2; }

# The clone this file is in, which is where the command is too.
HERE="$(cd -P "$(dirname "$0")" && pwd)" || exit 2
CLI="$HERE/claude-html"

H='[0-9a-fA-F]'
ID_GLOB="$H$H$H$H$H$H$H$H-$H$H$H$H-$H$H$H$H-$H$H$H$H-$H$H$H$H$H$H$H$H$H$H$H$H"

# Every character of an id matches one bracket of the pattern, so nothing
# else - a space, a quote, a newline, a slash - can be inside it.
REST="${URL#claude-html://}"
[ "$REST" != "$URL" ] || { echo "handler.sh: not a claude-html link" >&2; exit 2; }
ACTION="${REST%%/*}"
SID="${REST#*/}"
[ "$SID" != "$REST" ] || { echo "handler.sh: no session id in the link" >&2; exit 2; }
SID="${SID%/}"
case "$ACTION" in
  delete|open|resume) ;;
  *) echo "handler.sh: not an action it knows" >&2; exit 2 ;;
esac
# shellcheck disable=SC2254
case "$SID" in
  $ID_GLOB) ;;
  *) echo "handler.sh: not a session id" >&2; exit 2 ;;
esac

# shellcheck source=platform.sh
. "$HERE/platform.sh"
ch_detect

# Says something to the person who clicked, in whatever this desktop has.
tell() {
  case "$CH_DIALOG" in
    zenity) zenity --info --no-markup --title=claude-html --text="$1" >/dev/null 2>&1 ;;
    kdialog) kdialog --title claude-html --msgbox "$(plain "$1")" >/dev/null 2>&1 ;;
    yad) yad --title=claude-html --text="$(markup "$1")" --button=OK:0 >/dev/null 2>&1 ;;
    xmessage) printf '%s\n' "$1" | xmessage -center -title claude-html -buttons OK:0 -file - >/dev/null 2>&1 ;;
    *) printf '%s\n' "$1" >&2 ;;
  esac
}

# yad reads markup, so a title with < or & in it is escaped first; kdialog
# guesses whether text is rich, so it gets look-alikes it cannot mistake.
markup() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }
plain() { printf '%s' "$1" | sed -e 's/</‹/g' -e 's/>/›/g'; }

case "$ACTION" in
  open)
    OUTPUT="$("$CLI" --open "$SID" 2>&1)" || tell "Could not open that project.

$OUTPUT"
    exit 0 ;;
  resume)
    OUTPUT="$("$CLI" --resume-session "$SID" 2>&1)" || { tell "Could not resume that conversation.

$OUTPUT"; exit 1; }
    # No terminal to open: the command is the answer, so it is shown.
    case "$OUTPUT" in "run: "*) tell "Nothing here can open a terminal. To resume it, run:

${OUTPUT#run: }" ;; esac
    exit 0 ;;
esac

# ── delete ───────────────────────────────────────────────────────────
PLAN="$("$CLI" --delete-plan "$SID" 2>&1)" || { tell "Could not look that conversation up.

$PLAN"; exit 1; }
field() { printf '%s\n' "$PLAN" | awk -F'\t' -v k="$1" '$1 == k { print $2; exit }'; }
TITLE="$(field TITLE)"; ACT="$(field ACTION)"
if [ "$ACT" = refuse ]; then tell "$(field REASON)"; exit 1; fi
if [ "$ACT" = hide ]; then
  MSG="Hide \"$TITLE\" from the index?

It lives on claude.ai, so it is only hidden here, and a new export will not bring it back."
  OK="Hide"
else
  MSG="Delete \"$TITLE\"?

These move to the trash, where they can be restored:
$(printf '%s\n' "$PLAN" | awk -F'\t' '$1 == "ITEM" { n++; if (n <= 10) printf "  %s:  %s\n", $3, $2 } END { if (n > 10) printf "  ...and %d more\n", n - 10 }')"
  N="$(field HISTORY)"
  if [ "${N:-0}" -gt 0 ] 2>/dev/null; then
    MSG="$MSG

$N prompt(s) also come out of your up-arrow history; a copy of them goes to the trash too."
  fi
  OK="Move to Trash"
fi

# Each tool's own way of asking, with Cancel the default wherever the tool
# lets it be. Anything but a clear yes - a closed window, a tool that
# failed - is a no.
confirm() {
  case "$CH_DIALOG" in
    zenity) zenity --question --no-markup --default-cancel --title=claude-html \
              --ok-label="$OK" --cancel-label=Cancel --text="$MSG" >/dev/null 2>&1 ;;
    kdialog) kdialog --title claude-html --continue-label "$OK" \
               --warningcontinuecancel "$(plain "$MSG")" >/dev/null 2>&1 ;;
    yad) yad --title=claude-html --text="$(markup "$MSG")" \
           --button="Cancel:1" --button="$OK:0" >/dev/null 2>&1 ;;
    xmessage)
      printf '%s\n' "$MSG" | xmessage -center -title claude-html \
        -buttons "Cancel:1,$OK:0" -default Cancel -file - >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

case "$CH_DIALOG" in
  terminal)
    # The command asks for itself, on the terminal, and the window waits for
    # Enter so its answer can be read before it closes.
    ch_term_run sh -c '"$0" --delete "$1"; printf "\nPress Enter to close. "; read -r _' "$CLI" "$SID"
    exit $? ;;
  none)
    echo "handler.sh: no way to ask you first here, so nothing was deleted - run: claude-html --delete $SID" >&2
    exit 1 ;;
esac

confirm || exit 0
if OUTPUT="$("$CLI" --delete "$SID" --yes 2>&1)"; then
  tell "Done. $OUTPUT"
else
  tell "Not all of it went through. The index now shows what is left.

$OUTPUT"
  exit 1
fi
