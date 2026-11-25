#!/bin/bash
# Nothing on the screen: CLAUDE_HTML_NO_SCREEN=<file>, which every suite runs
# under (lib.sh, run-all.sh), stops each way claude-html shows something -
# the index opened after a build, a project opened, a terminal, a window
# asking, a banner - and notes it in the file instead.
#
# Every case runs on a simulated Linux desktop with stand-ins first on the
# PATH for the tools that would show it, so even with the switch broken
# nothing reaches the screen: the stand-in is called instead, and the check
# fails. The one Mac case opens a file that is not there, which shows nothing.
#
#   bash tests/screen.test.sh
set -u

. "$(dirname "$0")/lib.sh"

HERE="$(cd "$(dirname "$0")/.." && pwd)"
pass=0; fail=0
check() {
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); printf '  ok    %s\n' "$1"
  else fail=$((fail + 1)); printf '  FAIL  %s (expected %s, got %s)\n' "$1" "$3" "$2"; fi
}
T="$(cd "$(tmpdir chscreen)" && pwd -P)"
trap 'rm -rf "$T"' EXIT

H="$T/home"; ROOT="$T/root"; OUT="$ROOT/pages"; PROJ="$ROOT/a-project"; STUB="$T/bin"
mkdir -p "$H/.claude/projects" "$OUT" "$PROJ" "$STUB"
printf 'CLAUDE_HTML_ROOT="%s"\nCLAUDE_HTML_OUT="%s"\n' "$ROOT" "$OUT" > "$H/.claude/claude-html.conf"
printf 'ID=ubuntu\nVERSION_ID="24.04"\nPRETTY_NAME="Ubuntu 24.04"\n' > "$T/os-release"
echo "Linux version 6.8.0-generic" > "$T/version"
for s in xdg-open gio gnome-terminal zenity notify-send; do
  printf '#!/bin/sh\nprintf "%%s %%s\\n" "%s" "$*" >> "%s/called"\nexit 0\n' "$s" "$T" > "$STUB/$s"
  chmod +x "$STUB/$s"
done
called() { cat "$T/called" 2>/dev/null; }
shown() { cat "$T/shown" 2>/dev/null; }
reset() { rm -f "$T/called" "$T/shown"; }

# A GNOME desktop on Linux, with nothing of this machine's own environment;
# the switch only when given, as SCREEN=<file>.
desk() {
  env -i CLAUDE_HTML_NO_SCREEN="${SCREEN:-}" HOME="$H" PATH="$STUB:$PATH" TZ=UTC CLAUDE_HTML_UNAME=Linux \
    CLAUDE_HTML_OS_RELEASE="$T/os-release" CLAUDE_HTML_PROC_VERSION="$T/version" CLAUDE_HTML_NO_REGISTER=1 \
    CLAUDE_HTML_UPDATE_CHECK=off CLAUDE_HTML_REDACT_FILE="$T/no-such.redact" XDG_CURRENT_DESKTOP=GNOME DISPLAY=:0 "$@"
}

# ── the index, after a build ─────────────────────────────────────────
reset
SCREEN="$T/shown" desk bash "$HERE/claude-html" >/dev/null 2>&1
check "a build with the switch: the index is noted, not opened" "$(shown)" "open 'xdg-open' '$OUT/index.html'"
check "  and the opener is never started" "$(called)" ""
reset
SCREEN="" desk bash "$HERE/claude-html" >/dev/null 2>&1
check "without it, the opener would have been (a stand-in here)" "$(called)" "xdg-open $OUT/index.html"

# ── a project, through open.js under node ────────────────────────────
A=11111111-0000-0000-0000-00000000000a
printf '{"%s":{"cwd":"%s","project":"a-project","kind":"transcript"}}\n' "$A" "$PROJ" > "$OUT/.manifest.json"
reset
check "--open with the switch: says where, as ever" \
  "$(SCREEN="$T/shown" desk bash "$HERE/claude-html" --open "$A" 2>&1)" "folder: $PROJ"
check "  noted by open.js, not opened" "$(shown) | $(called)" "open xdg-open $PROJ | "
reset
SCREEN="" desk bash "$HERE/claude-html" --open "$A" >/dev/null 2>&1
check "  without it, opened (a stand-in here)" "$(called)" "xdg-open $PROJ"

# ── a terminal, a window, a banner ───────────────────────────────────
inlib() { desk bash -c '. "$0/lib/platform.sh"; ch_detect; CH_HERE="$0"; '"$1" "$HERE"; }
reset
SCREEN="$T/shown" inlib 'ch_term_run sh /some/launcher.sh' >/dev/null 2>&1
check "a terminal: noted, not opened" "$(shown) | $(called)" "open 'gnome-terminal' '--' 'sh' '/some/launcher.sh' | "
reset
check "a window asking: none shown, so the caller asks in words" \
  "$(SCREEN="$T/shown" inlib 'ch_confirm T S "$(printf "A:\tb")" Apply' 2>&1)" cancel
check "  noted, the window's command on one line" "$(shown | cut -c1-25) $(shown | wc -l | tr -d ' ') | $(called)" "window 'zenity' '--questi 1 | "
reset
check "  the guard's: nothing printed, as when no window can be shown" \
  "$(SCREEN="$T/shown" inlib 'ch_choose prompt P "GitHub token (1)"' 2>&1)|$(shown | cut -c1-15)|$(called)" "|window 'zenity'|"
reset
SCREEN="$T/shown" desk bash -c '. "$0/lib/limits.sh"; CH_LIM_NOTIFY=1; ch_lim_banner "API budget at 95 %"; sleep 2' "$HERE" >/dev/null 2>&1
check "a banner: noted, not shown" "$(shown) | $(called)" "banner API budget at 95 % | "
reset
SCREEN="" desk bash -c '. "$0/lib/limits.sh"; CH_LIM_NOTIFY=1; ch_lim_banner "API budget at 95 %"' "$HERE" >/dev/null 2>&1
# It goes in the background: waited for, up to ten seconds.
for _ in $(seq 1 50); do [ -s "$T/called" ] && break; sleep 0.2; done
check "  without it, shown (a stand-in here)" "$(called)" "notify-send -a claude-html claude-html API budget at 95 %"

# ── the Settings page, opened again after Apply ──────────────────────
# The link handler, beside a stand-in command that answers as an applied
# --settings-apply does: the page it names is opened again, by ch_open_file.
HD="$T/handler"; mkdir -p "$HD/linux" "$HD/lib"
cp "$HERE/linux/handler.sh" "$HD/linux/"; cp "$HERE/lib/platform.sh" "$HD/lib/"
printf '#!/bin/sh
[ "$1" = --settings-apply ] && printf "Applied.\\n%%s\\n" "%s/settings.html"
exit 0
' "$OUT" > "$HD/claude-html"
chmod +x "$HD/claude-html"
reset
SCREEN="$T/shown" desk sh "$HD/linux/handler.sh" "claude-html://settings/v1/none/GUARD=off" >/dev/null 2>&1
check "Settings, applied: the page's reopening is noted, not opened" "$(shown) | $(called)" "open 'xdg-open' '$OUT/settings.html' | "
reset
SCREEN="" desk sh "$HD/linux/handler.sh" "claude-html://settings/v1/none/GUARD=off" >/dev/null 2>&1
check "  without it, opened (a stand-in here)" "$(called)" "xdg-open $OUT/settings.html"

# ── the Mac's opener ─────────────────────────────────────────────────
# /usr/bin/open by its full path, which no stand-in can take the place of:
# given a file that is not there, so even a broken switch opens nothing.
if [ "$(uname -s)" = Darwin ]; then
  reset
  CLAUDE_HTML_NO_SCREEN="$T/shown" bash -c '. "$0/lib/platform.sh"; CH_OPENER=open; ch_open_file "$1"' "$HERE" "$T/not-there.html"
  check "macOS: /usr/bin/open is noted, not run" "$(shown)" "open '/usr/bin/open' '$T/not-there.html'"
fi

# ── helper apps left registered: this run's only ────────────────────
# run-all.sh counts the apps registered under its own temp folder (every
# suite's TMPDIR) and this clone's; another run's, at the same time, are
# not its failure. Tried on dumps written here, as lsregister -dump has them.
RUN="$T/run"; OTHER="$T/other-run"; CL="$T/a clone"; mkdir -p "$RUN/tmp/chhelper.1" "$OTHER/chhelper.2" "$CL" "$T/lh/.local/bin"
dump() { for p in "$@"; do printf 'bundle id:                  1\npath:                       %s (0x1a2b)\nname:  Claude HTML\n' "$p"; done > "$T/dump"; }
leaks() { HOME="$T/lh" bash "$HERE/tests/app-leaks.sh" "$RUN" "$CL" "$T/dump"; }
dump "$OTHER/chhelper.2/Claude HTML.app"
check "an app another run registered, in its temp folder: not this run's" "$(leaks)" 0
dump "$OTHER/chhelper.2/Claude HTML.app" "$RUN/tmp/chhelper.1/Claude HTML.app"
check "one this run's suites registered: counted" "$(leaks)" 1
dump "$RUN/tmp/chhelper.1/Claude HTML.app/Contents/x.app" "$RUN/tmp/chhelper.1/Other.app"
check "  only a helper app, by its name" "$(leaks)" 0
dump "$CL/Claude HTML.app"
check "this clone's own: counted" "$(leaks)" 1
ln -s "$CL/claude-html" "$T/lh/.local/bin/claude-html"
check "  unless it is the installed copy" "$(leaks)" 0

# ── what the suites run themselves ───────────────────────────────────
# osascript is an engine as well, so no stand-in can sit in its place: the
# suites' own calls of it that draw are held to this. Every real window of
# dialog.js is --offscreen (its countdown words show nothing), and no suite
# runs an opener, a dialog or a banner of the system's directly.
cd "$HERE/tests" || exit 1
check "every real dialog.js window a suite draws is --offscreen" \
  "$(grep -nE '^[^#]*osascript -l JavaScript "\$HERE/mac/dialog\.js"' -- *.sh | grep -v -- '--offscreen' | grep -vE 'dialog\.js" (--limit [0-9]+ )?countdown' | grep -c .)" 0
check "no suite runs /usr/bin/open, display dialog, display notification or terminal-notifier itself" \
  "$(grep -nE '^[^#]*(^|[;&|(`]|\$\(|^[[:space:]]*)(/usr/bin/open |display (dialog|notification)|terminal-notifier )' -- *.sh | grep -vE "^(screen|run-all)\.test\.sh:|^run-all\.sh:|:[[:space:]]*\"|check \"|'osascript'" | grep -c .)" 0

# env -i throws the switch away with the rest of the environment, and a
# build under it on a Mac then opens the index for real: every env -i in a
# suite names CLAUDE_HTML_NO_SCREEN, passed on or, for stand-ins of its
# own, set empty.
check "every env -i in a suite says what becomes of CLAUDE_HTML_NO_SCREEN" \
  "$(grep -nE '^[^#]*env -i ' -- *.sh | grep -v -e 'env -i CLAUDE_HTML_NO_SCREEN=' -e '^screen\.test\.sh:.*check ' | grep -c .)" 0

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
