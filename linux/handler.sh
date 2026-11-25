#!/bin/sh
# The claude-html link handler, on Linux: the desktop hands it a
# claude-html://<action>/<session id> link from the index (or
# claude-html://update), and it asks the
# claude-html command to do exactly that.
#
#   handler.sh 'claude-html://resume/0f6c…'
#
# Any web page can make a browser open such a link, so the link is checked
# before anything else happens and nothing from it ever reaches a shell: it
# must be one of three actions and a session id, with nothing before, after
# or between them - or exactly claude-html://update, which names nothing. Which conversation that is, and every path involved, is
# looked up in the index's own manifest by the command, never taken from here.
# Or claude-html://settings/<payload>, from the Settings page's "apply", in
# a grammar of its own that the command checks whole (settings.sh says it).
# Or claude-html://limits/<payload>, from the Token usage page's "apply":
# new limits in a fixed grammar (limits-cli.sh says it), which the command
# checks again and asks about in a window before anything is written.
#
# Deleting asks first, in a dialog of the desktop's own, or in a terminal
# window when there is no dialog tool; with neither, it refuses.

URL="${1:-}"
[ $# -eq 1 ] || { echo "handler.sh: expected one link" >&2; exit 2; }

# The clone this file's folder is in, which is where the command is too.
HERE="$(cd -P "$(dirname "$0")/.." && pwd)" || exit 2
CLI="$HERE/claude-html"

# The links' grammars: a session id, the limits', the settings' shape.
# shellcheck source=../lib/common.sh
. "$HERE/lib/common.sh"

# The update takes nothing from the link: it is exactly this string, or
# not the update at all.
if [ "$URL" = "claude-html://update" ]; then
  ACTION=update; SID=""
elif [ "${URL#claude-html://settings/}" != "$URL" ]; then
  # From the Settings page: v1/ and then letters, digits and . _ ~ % = / -
  # only, at most 2048; the command reads the grammar whole (settings.sh).
  ACTION=settings; SID="${URL#claude-html://settings/}"
  ch_set_link_shape "$SID" || { echo "handler.sh: not a settings link" >&2; exit 2; }
elif [ "${URL#claude-html://limits/}" != "$URL" ]; then
  ACTION=limits; SID="${URL#claude-html://limits/}"
  ch_lim_link_ok "$SID" || { echo "handler.sh: not a limits link" >&2; exit 2; }
else
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
  ch_is_sid "$SID" || { echo "handler.sh: not a session id" >&2; exit 2; }
fi

# shellcheck source=../lib/platform.sh
. "$HERE/lib/platform.sh"
ch_detect

# Says something to the person who clicked, in whatever this desktop has,
# as every window is shown (platform.sh's ch_dialog_wait): closed after the
# windows' wait, and never on the screen under CLAUDE_HTML_NO_SCREEN.
tell() {
  case "$CH_DIALOG" in
    zenity) ch_dialog_wait "$CH_GUARD_LIMIT" zenity --info --no-markup --title=claude-html --text="$1" ;;
    kdialog) ch_dialog_wait "$CH_GUARD_LIMIT" kdialog --title claude-html --msgbox "$(plain "$1")" ;;
    yad) ch_dialog_wait "$CH_GUARD_LIMIT" yad --title=claude-html --text="$(markup "$1")" --button=OK:0 ;;
    xmessage) ch_dialog_wait "$CH_GUARD_LIMIT" xmessage -center -title claude-html -buttons OK:0 "$1" ;;
    *) printf '%s\n' "$1" >&2 ;;
  esac
  return 0
}

# yad reads markup, so a title with < or & in it is escaped first; kdialog
# guesses whether text is rich, so it gets look-alikes it cannot mistake.
markup() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }
plain() { printf '%s' "$1" | sed -e 's/</‹/g' -e 's/>/›/g'; }

case "$ACTION" in
  settings)
    # Asked in a window, Cancel the default, as the limits are; applied,
    # the command rebuilds and names the Settings page, opened again.
    OUTPUT="$("$CLI" --settings-apply "$SID" 2>&1)"; RC=$?
    if [ "$RC" = 0 ]; then
      case "$OUTPUT" in
        Applied.*) PAGE="$(printf '%s\n' "$OUTPUT" | tail -n 1)"
                   case "$PAGE" in /*/settings.html) ch_open_file "$PAGE" || true ;; esac ;;
      esac
    elif [ "$RC" != 3 ]; then
      tell "The settings were not changed.

$OUTPUT"
    fi
    exit 0 ;;
  limits)
    # The command asks in a window of the desktop's own, Cancel the
    # default, and writes nothing without a yes; with no window to ask in,
    # it refuses and says what to run instead.
    OUTPUT="$("$CLI" --limits-apply "$SID" 2>&1)"; RC=$?
    # 3: a window asking is already up, which said all there is to say.
    [ "$RC" = 0 ] || [ "$RC" = 3 ] || tell "The limits were not changed.

$OUTPUT"
    exit 0 ;;
  update)
    # This clone's own command, in a terminal that stays open to be read.
    OUTPUT="$("$CLI" --update-terminal 2>&1)" || { tell "Could not open a terminal for the update.

$OUTPUT"; exit 1; }
    case "$OUTPUT" in "run: "*) tell "Nothing here can open a terminal. To update, run:

${OUTPUT#run: }" ;; esac
    exit 0 ;;
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
# Asked as every confirmation is (platform.sh's ch_confirm): Cancel the
# default wherever the tool lets it be, closed after the windows' wait, and
# anything but a clear yes - a closed window, a tool that failed - a no.
if [ "$ACT" = hide ]; then
  Q="Hide \"$TITLE\" from the index?"
  SUB="It lives on claude.ai, so it is only hidden here, and a new export will not bring it back."
  ROWS=""
  OK="Hide"
else
  Q="Delete \"$TITLE\"?"
  SUB="These move to the trash, where they can be restored:"
  ROWS="$(printf '%s\n' "$PLAN" | awk -F'\t' '$1 == "ITEM" { n++; if (n <= 10) printf "%s:\t%s\n", $3, $2 } END { if (n > 10) printf "\t...and %d more\n", n - 10 }')"
  N="$(field HISTORY)"
  if [ "${N:-0}" -gt 0 ] 2>/dev/null; then
    ROWS="$ROWS
	$N prompt(s) also come out of your up-arrow history; a copy of them goes to the trash too."
  fi
  OK="Move to Trash"
fi

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

[ "$(ch_confirm "$Q" "$SUB" "$ROWS" "$OK")" = apply ] || exit 0
if OUTPUT="$("$CLI" --delete "$SID" --yes 2>&1)"; then
  tell "Done. $OUTPUT"
else
  tell "Not all of it went through. The index now shows what is left.

$OUTPUT"
  exit 1
fi
