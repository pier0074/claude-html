#!/bin/bash
# Linux desktop integration, proven without a Linux desktop.
#
# Each environment is faked whole: an os-release file, the variables a session
# sets, and a folder of stand-in programs placed in front of a PATH that holds
# nothing else but the basic tools. The stand-ins write down how they were
# called, so what is checked is the exact command each desktop would be given.
# None of this has been clicked through on a real Linux desktop; it shows the
# logic is right for each one, which is what can be shown from here.
#
# Runs the same on macOS and Linux; nothing here registers anything with the
# real machine (the handler goes into a fake home, xdg-mime is a stand-in).
#
#   bash tests/linux.test.sh
set -u

. "$(dirname "$0")/lib.sh"

HERE="$(cd "$(dirname "$0")/.." && pwd)"
pass=0; fail=0
check() {
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); printf '  ok    %s\n' "$1"
  else fail=$((fail + 1)); printf '  FAIL  %s\n        expected: %s\n        got:      %s\n' "$1" "$3" "$2"; fi
}
T="$(cd "$(tmpdir chlinux)" && pwd)"
trap 'rm -rf "$T"' EXIT

# ── the basic tools, and nothing else ───────────────────────────────
SYS="$T/sys"; mkdir -p "$SYS"
for t in sh bash env cat sed awk grep tr head tail cut wc dirname basename readlink \
         mkdir rm mv cp ln chmod touch date uname node ls sort id stat sleep mktemp od find ps; do
  p="$(command -v "$t" 2>/dev/null)"
  case "$p" in /*) ln -s "$p" "$SYS/$t" ;; esac
done

# A stand-in records its name and every argument, one call per line.
stub() {   # dir name [body]
  {
    echo '#!/bin/sh'
    echo '{ printf "%s" "$(basename "$0")"; for a in "$@"; do printf " [%s]" "$a"; done; echo; } >> "$STUB_LOG"'
    printf '%s\n' "${3:-exit 0}"
  } > "$1/$2"
  chmod +x "$1/$2"
}
# Trash tools that really move the file, so a delete through them completes.
TRASH_BODY='for a in "$@"; do last="$a"; done
case "$(basename "$0")" in kioclient*) for a in "$@"; do [ "$a" = trash:/ ] || [ "$a" = move ] || case "$a" in -*) ;; *) f="$a" ;; esac; done; last="$f" ;; esac
mkdir -p "$STUB_TRASH" && mv "$last" "$STUB_TRASH/"'
DIALOG_BODY='exit "${STUB_ANSWER:-1}"'

# ── a project whose path has everything awkward in it ────────────────
H="$T/home"; ROOT="$T/root"; OUT="$ROOT/pages"
PLAIN="$ROOT/plain"
NL='
'
WEIRD="$ROOT/it's a \"proj\" \$HOME \$(touch pwned) \`id\` 100% \\n${NL}line"
mkdir -p "$PLAIN" "$WEIRD" "$OUT" "$H/.claude"
A=aaaaaaaa-1111-4111-8111-000000000001      # in the plain project
B=bbbbbbbb-2222-4222-8222-000000000002      # in the awkward one
jsq() { node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$1"; }
transcript() {   # id cwd prompt
  local d="$H/.claude/projects/-p-$1"
  mkdir -p "$d"
  printf '{"type":"user","sessionId":"%s","cwd":%s,"timestamp":"2026-11-01T10:00:00Z","message":{"role":"user","content":%s}}\n' \
    "$1" "$(jsq "$2")" "$(jsq "$3")" > "$d/$1.jsonl"
}
transcript "$A" "$PLAIN" "fix the build"
transcript "$B" "$WEIRD" "a title with \"quotes\", \$(touch pwned), \`id\` and <b>markup</b>"
printf 'CLAUDE_HTML_ROOT="%s"\nCLAUDE_HTML_OUT="%s"\n' "$ROOT" "$OUT" > "$H/.claude/claude-html.conf"
build() {   # os, then more opts
  HOME="$H" node "$HERE/build/convert.js" \
    "{\"root\":$(jsq "$ROOT"),\"out\":$(jsq "$OUT"),\"here\":$(jsq "$HERE"),\"os\":\"$1\"${2:-}}" >/dev/null
}

# ── environments ────────────────────────────────────────────────────
# Each gets a bin folder, an os-release, and the session's variables.
mkenv() {   # name id version id_like pretty
  local e="$T/env/$1"
  mkdir -p "$e/bin"
  { echo "PRETTY_NAME=\"$5\""; echo "ID=$2"; echo "VERSION_ID=\"$3\""
    [ -n "$4" ] && echo "ID_LIKE=\"$4\""
    # A line that would do something if the file were run rather than read.
    echo 'BUG_REPORT_URL="$(touch '"$T"'/os-release-was-run)"'; } > "$e/os-release"
  echo "Linux version 6.8.0-generic (buildd@ubuntu) #1 SMP" > "$e/version"
  : > "$e/vars"
}
var() { printf '%s\n' "$2" >> "$T/env/$1/vars"; }

# What counts as a temporary folder inside these environments: only this,
# so the clone is not one wherever it sits (CI and worktrees put it under
# /tmp, which ch_is_temp would otherwise refuse to register).
TEMPS="$T/temporary"

# Run something inside an environment: nothing of this machine's own
# environment gets in, only what the fake one says. Its own stand-ins are
# the screen, so CLAUDE_HTML_NO_SCREEN is off: they record what is shown.
inenv() {   # name cmd…
  local e="$T/env/$1"; shift
  local vars=() line
  while IFS= read -r line; do [ -n "$line" ] && vars+=("$line"); done < "$e/vars"
  env -i CLAUDE_HTML_NO_SCREEN= HOME="$H" PATH="$e/bin:$SYS" STUB_LOG="$e/log" STUB_TRASH="$e/trashed" \
    CLAUDE_HTML_UNAME=Linux CLAUDE_HTML_OS_RELEASE="$e/os-release" \
    CLAUDE_HTML_PROC_VERSION="$e/version" CLAUDE_HTML_NO_REGISTER=1 \
    CLAUDE_HTML_TEMP_DIRS="$TEMPS" ${vars[@]+"${vars[@]}"} "$@"
}
doctor() { inenv "$1" bash "$HERE/claude-html" --doctor 2>&1; }
field() { awk -v k="$1" '$1 == k { $1 = ""; sub(/^ +/, ""); print; exit }'; }
first() { awk -v k="$1" '$1 == k { print $2; exit }'; }
log() { cat "$T/env/$1/log" 2>/dev/null; }
clearlog() { : > "$T/env/$1/log"; }

mkenv ubuntu ubuntu 24.04 debian "Ubuntu 24.04.1 LTS"
var ubuntu XDG_CURRENT_DESKTOP=ubuntu:GNOME; var ubuntu XDG_SESSION_TYPE=wayland
var ubuntu WAYLAND_DISPLAY=wayland-0; var ubuntu DISPLAY=:0
for s in gnome-terminal xdg-open xdg-mime update-desktop-database; do stub "$T/env/ubuntu/bin" "$s"; done
stub "$T/env/ubuntu/bin" gio "$TRASH_BODY"
stub "$T/env/ubuntu/bin" zenity "$DIALOG_BODY"

mkenv fedora fedora 41 "" "Fedora Linux 41 (Workstation Edition)"
var fedora XDG_CURRENT_DESKTOP=GNOME; var fedora XDG_SESSION_TYPE=wayland; var fedora WAYLAND_DISPLAY=wayland-0
for s in ptyxis kgx xdg-open; do stub "$T/env/fedora/bin" "$s"; done
stub "$T/env/fedora/bin" gio "$TRASH_BODY"; stub "$T/env/fedora/bin" zenity "$DIALOG_BODY"

mkenv fedora40 fedora 40 "" "Fedora Linux 40 (Workstation Edition)"
var fedora40 XDG_CURRENT_DESKTOP=GNOME; var fedora40 WAYLAND_DISPLAY=wayland-0
stub "$T/env/fedora40/bin" kgx; stub "$T/env/fedora40/bin" gio "$TRASH_BODY"

mkenv kde opensuse-tumbleweed 20261101 "opensuse suse" "openSUSE Tumbleweed"
var kde XDG_CURRENT_DESKTOP=KDE; var kde XDG_SESSION_TYPE=x11; var kde DISPLAY=:0
for s in konsole xdg-open; do stub "$T/env/kde/bin" "$s"; done
# gio is often installed on Plasma too; the desktop's own tools still win.
stub "$T/env/kde/bin" kioclient5 "$TRASH_BODY"; stub "$T/env/kde/bin" gio "$TRASH_BODY"
stub "$T/env/kde/bin" kdialog "$DIALOG_BODY"; stub "$T/env/kde/bin" zenity "$DIALOG_BODY"

mkenv xfce debian 12 "" "Debian GNU/Linux 12 (bookworm)"
var xfce XDG_CURRENT_DESKTOP=XFCE; var xfce DISPLAY=:0
for s in xfce4-terminal xdg-open; do stub "$T/env/xfce/bin" "$s"; done
stub "$T/env/xfce/bin" gio "$TRASH_BODY"

mkenv bare arch "" "" "Arch Linux"
var bare DISPLAY=:0
stub "$T/env/bare/bin" xterm; stub "$T/env/bare/bin" xmessage "$DIALOG_BODY"

mkenv headless debian 12 "" "Debian GNU/Linux 12 (bookworm)"
var headless XDG_SESSION_TYPE=tty

mkenv wsl ubuntu 22.04 debian "Ubuntu 22.04.4 LTS"
echo "Linux version 5.15.153.1-microsoft-standard-WSL2 (root@1c602f52c2e4)" > "$T/env/wsl/version"
var wsl WSL_DISTRO_NAME=Ubuntu
stub "$T/env/wsl/bin" wt.exe; stub "$T/env/wsl/bin" wslview

# ── 1. what --doctor sees ───────────────────────────────────────────
echo "doctor"
D="$(doctor ubuntu)"
check "ubuntu: system" "$(printf '%s\n' "$D" | field system)" \
  "linux · ubuntu 24.04 (like debian) · Ubuntu 24.04.1 LTS"
check "ubuntu: desktop" "$(printf '%s\n' "$D" | first desktop)" gnome
check "ubuntu: session" "$(printf '%s\n' "$D" | first session)" wayland
check "ubuntu: terminal" "$(printf '%s\n' "$D" | first terminal)" gnome-terminal
check "ubuntu: opener" "$(printf '%s\n' "$D" | first opener)" xdg-open
check "ubuntu: trash" "$(printf '%s\n' "$D" | first trash)" gio
check "ubuntu: dialog" "$(printf '%s\n' "$D" | first dialog)" zenity
check "ubuntu: links can be registered" "$(printf '%s\n' "$D" | field links)" \
  "not registered yet - ./install.sh registers it"
check "ubuntu: nothing missing" "$(printf '%s\n' "$D" | field missing)" nothing
check "os-release is read, never run" "$([ -e "$T/os-release-was-run" ] && echo ran || echo read)" read

D="$(doctor fedora)"
check "fedora 41: newest GNOME terminal first" "$(printf '%s\n' "$D" | first terminal)" ptyxis
check "  and its version" "$(printf '%s\n' "$D" | field system)" \
  "linux · fedora 41 · Fedora Linux 41 (Workstation Edition)"
check "fedora 40: GNOME Console" "$(doctor fedora40 | first terminal)" kgx
check "  with no dialog tool, a delete asks in the terminal" "$(doctor fedora40 | first dialog)" terminal
check "  and links need xdg-mime" "$(doctor fedora40 | field links)" \
  "unavailable: no xdg-mime to register a handler with"

D="$(doctor kde)"
check "kde: desktop" "$(printf '%s\n' "$D" | first desktop)" kde
check "kde: konsole" "$(printf '%s\n' "$D" | first terminal)" konsole
check "kde: its own trash tool, though gio is there" "$(printf '%s\n' "$D" | first trash)" kioclient5
check "kde: its own dialog, though zenity is there" "$(printf '%s\n' "$D" | first dialog)" kdialog
check "kde: session" "$(printf '%s\n' "$D" | first session)" x11

D="$(doctor xfce)"
check "xfce: terminal" "$(printf '%s\n' "$D" | first terminal)" xfce4-terminal
check "xfce: trash" "$(printf '%s\n' "$D" | first trash)" gio
check "xfce: no dialog tool, asks in a terminal" "$(printf '%s\n' "$D" | first dialog)" terminal

D="$(doctor bare)"
check "bare wm: no desktop" "$(printf '%s\n' "$D" | first desktop)" none
check "bare wm: xterm" "$(printf '%s\n' "$D" | first terminal)" xterm
check "bare wm: the Trash spec by hand" "$(printf '%s\n' "$D" | first trash)" spec
check "bare wm: xmessage asks" "$(printf '%s\n' "$D" | first dialog)" xmessage
check "bare wm: says what it lacks" "$(printf '%s\n' "$D" | field missing)" "opener · links"

D="$(doctor headless)"
check "headless: session" "$(printf '%s\n' "$D" | first session)" headless
check "headless: no terminal" "$(printf '%s\n' "$D" | first terminal)" none
check "headless: no dialog" "$(printf '%s\n' "$D" | first dialog)" none
check "headless: trash still works" "$(printf '%s\n' "$D" | first trash)" spec
check "headless: no links" "$(printf '%s\n' "$D" | field links)" "unavailable: no display"
check "headless: says what it lacks" "$(printf '%s\n' "$D" | field missing)" \
  "terminal · opener · dialog · links"

D="$(doctor wsl)"
check "wsl: detected" "$(printf '%s\n' "$D" | first wsl)" yes
check "wsl: Windows Terminal" "$(printf '%s\n' "$D" | first terminal)" wt.exe
check "wsl: wslview opens things" "$(printf '%s\n' "$D" | first opener)" wslview
check "wsl: links cannot reach it" "$(printf '%s\n' "$D" | field links)" \
  "unavailable: WSL without a Linux desktop - the browser runs on Windows and cannot reach this"

mkenv custom ubuntu 24.04 debian "Ubuntu"
var custom XDG_CURRENT_DESKTOP=GNOME; var custom WAYLAND_DISPLAY=w; var custom TERMINAL=kitty
stub "$T/env/custom/bin" kitty; stub "$T/env/custom/bin" gnome-terminal
check "\$TERMINAL wins over the desktop's own" "$(doctor custom | first terminal)" kitty

# The same layout as on a Mac, whatever the desktop has or lacks; the
# command a terminal is given as it would be typed; wrapped as a terminal
# 60 wide would be (doctor.test.sh has the rest of the layout).
for e in ubuntu fedora fedora40 kde xfce bare headless wsl custom; do
  check "$e: the doctor's layout" "$(doctor "$e" | doctor_layout)" ok
  check "  and at 60 columns" "$(inenv "$e" CLAUDE_HTML_DOCTOR_COLUMNS=60 bash "$HERE/claude-html" --doctor 2>&1 | doctor_layout header 60)" ok
done
check "ubuntu: the terminal and its command, readable" "$(doctor ubuntu | field terminal)" \
  "gnome-terminal · gnome-terminal -- sh <launcher>"
check "wsl: the same through Windows Terminal" "$(doctor wsl | field terminal)" \
  "wt.exe · wt.exe wsl.exe -d Ubuntu -- sh <launcher>"
check "headless: what it does instead, after the same dot" "$(doctor headless | field terminal) | $(doctor headless | field dialog)" \
  "none · resume prints the command to run instead | none · a delete link is refused rather than done unasked"
check "xfce: a delete asks in a terminal, said the same way" "$(doctor xfce | field dialog)" \
  "terminal · a delete link asks in a terminal window"
check "the trash tool and how it is called" "$(doctor kde | field trash)" \
  "kioclient5 · kioclient5 --noninteractive move <file> trash:/"

# ── 2. launchers ────────────────────────────────────────────────────
echo "launchers"
build linux
SA="$(ls "$OUT/resume" | grep -- "-$A.sh$")"; SB="$(ls "$OUT/resume" | grep -- "-$B.sh$")"
check "linux writes a .sh and a .desktop per conversation" \
  "$(ls "$OUT/resume" | sed 's/.*\.//' | sort | uniq -c | tr -s ' ' | sed 's/^ //' | tr '\n' ' ')" \
  "2 desktop 2 sh "
check "  and no .command" "$(ls "$OUT/resume" | grep -c '\.command$')" 0
check "  both executable" \
  "$([ -x "$OUT/resume/$SB" ] && [ -x "$OUT/resume/${SB%.sh}.desktop" ] && echo yes || echo no)" yes

# A desktop file read the way the spec says: groups, keys, values unescaped
# once, then Exec split by its own quoting rules. Prints the problem, or the
# argv as JSON.
cat > "$T/desktop.js" <<'JS'
var fs = require("fs"), text = fs.readFileSync(process.argv[2], "utf8"), want = process.argv[3] || "";
function die(m) { console.log("INVALID: " + m); process.exit(0); }
if (!/\n$/.test(text)) die("no final newline");
var lines = text.slice(0, -1).split("\n"), group = null, keys = {};
lines.forEach(function (l, i) {
  if (/^\s*(#|$)/.test(l)) return;
  var g = /^\[([^\[\]\x00-\x1f]+)\]$/.exec(l);
  if (g) { if (group === null && g[1] !== "Desktop Entry") die("first group is " + g[1]); group = g[1]; return; }
  if (group === null) die("line " + (i + 1) + " before any group");
  var kv = /^([A-Za-z0-9-]+(?:\[[^\]]+\])?)\s*=\s*(.*)$/.exec(l);
  if (!kv) die("line " + (i + 1) + " is not key=value: " + JSON.stringify(l));
  if (/[\x00-\x1f\x7f]/.test(kv[2])) die("control character in " + kv[1]);
  if (group === "Desktop Entry") { if (kv[1] in keys) die("duplicate " + kv[1]); keys[kv[1]] = kv[2]; }
});
function unescape(v) {
  return v.replace(/\\(.)/g, function (m, c) {
    return ({ s: " ", n: "\n", t: "\t", r: "\r", "\\": "\\" })[c] !== undefined
      ? ({ s: " ", n: "\n", t: "\t", r: "\r", "\\": "\\" })[c] : die("bad escape \\" + c);
  });
}
["Type", "Name", "Exec"].forEach(function (k) { if (!(k in keys)) die("missing " + k); });
if (keys.Type !== "Application") die("Type is " + keys.Type);
["Terminal", "NoDisplay"].forEach(function (k) {
  if (k in keys && !/^(true|false)$/.test(keys[k])) die(k + " is not a boolean");
});
if (keys.MimeType !== undefined && !/;$/.test(keys.MimeType)) die("MimeType list without final ;");
var exec = unescape(keys.Exec), argv = [], cur = null, i = 0;
while (i < exec.length) {
  var c = exec[i];
  if (c === " ") { if (cur !== null) { argv.push(cur); cur = null; } i++; continue; }
  if (c === '"') {
    cur = cur || ""; i++;
    while (i < exec.length && exec[i] !== '"') {
      if (exec[i] === "\\") {
        if ('"`$\\'.indexOf(exec[i + 1]) < 0) die("bad quoting escape in Exec: \\" + exec[i + 1]);
        cur += exec[i + 1]; i += 2;
      } else if (exec[i] === "`" || exec[i] === "$") die("unescaped " + exec[i] + " in a quoted Exec argument");
      else { cur += exec[i]; i++; }
    }
    if (i >= exec.length) die("unclosed quote in Exec");
    i++; continue;
  }
  if (/[\t\n'\\><~|&;$*?#()`"]/.test(c)) die("reserved character " + JSON.stringify(c) + " outside quotes in Exec");
  cur = (cur || "") + c; i++;
}
if (cur !== null) argv.push(cur);
// Field codes: %% is a literal %, %u/%U/%f/%F are the only ones allowed here.
argv = argv.map(function (a) {
  return a.replace(/%(.)/g, function (m, c) { return c === "%" ? "%" : "uUfF".indexOf(c) >= 0 ? m : die("bad field code " + m); });
});
var out = { argv: argv, path: keys.Path !== undefined ? unescape(keys.Path) : null,
            name: unescape(keys.Name), terminal: keys.Terminal || "" };
console.log(want ? JSON.stringify(out[want]) : JSON.stringify(out));
JS
desk() { node "$T/desktop.js" "$@"; }
DB="$OUT/resume/${SB%.sh}.desktop"
check "the .desktop file is valid" "$(desk "$DB" | cut -c1)" "{"
check "  it runs in a terminal" "$(desk "$DB" terminal)" '"true"'
check "  Exec is bash -c, with the folder as an argument and not in the script" \
  "$(desk "$DB" argv | node -e 'var a=JSON.parse(require("fs").readFileSync(0,"utf8"));
    console.log(JSON.stringify([a[0],a[1],a[3],a[4],a[5],a.length]))')" \
  "$(node -e 'console.log(JSON.stringify(["bash","-c","claude-html",process.argv[1],process.argv[2],6]))' "$WEIRD" "$B")"
check "  and the script ends in the shell, exec'd, nothing after it" \
  "$(desk "$DB" argv | node -e 'var a=JSON.parse(require("fs").readFileSync(0,"utf8")); console.log(/; exec "\$s" -i$/.test(a[2]))')" true
check "  no Path=, which a removed folder would make fail to open" "$(desk "$DB" path)" null
check "  Name comes from the title, on one line" "$(desk "$DB" name)" \
  "$(jsq 'Resume: a title with "quotes", $(touch pwned), `id` and <b>markup</b>')"
if command -v desktop-file-validate >/dev/null 2>&1; then
  check "  and desktop-file-validate agrees" "$(desktop-file-validate "$DB" 2>&1 | grep -c error)" 0
fi

# Run each launcher for real, with a claude that only says where it woke up
# and then exits as CLAUDE_EXIT says, and a $SHELL that says where it was
# started and how: the window must end as that shell, in that folder.
FAKE="$T/fakeclaude"; mkdir -p "$FAKE"
printf '#!/bin/sh\npwd -P > "%s/where"\nprintf "%%s\\n" "$*" > "%s/args"\nexit "${CLAUDE_EXIT:-0}"\n' "$T" "$T" > "$FAKE/claude"
chmod +x "$FAKE/claude"
STUBSH="$T/stubshell"
printf '#!/bin/sh\nprintf "%%s|%%s\\n" "$(pwd -P)" "$*" > "%s/shell"\n' "$T" > "$STUBSH"; chmod +x "$STUBSH"
REAL="$(cd "$WEIRD" && pwd -P)"
HREAL="$(cd "$H" && pwd -P)"
rundesk() { ( cd "$T" && HOME="$H" PATH="$FAKE:$SYS" node -e '
  var a = JSON.parse(process.argv[1]);
  require("child_process").spawnSync(a[0], a.slice(1), { stdio: "inherit" });' "$(desk "$DB" argv)" ); }
rm -f "$T/where" "$T/shell"
SHELL="$STUBSH" rundesk
check "the .desktop's command lands in the awkward folder" "$(cat "$T/where" 2>/dev/null)" "$REAL"
check "  and resumes that conversation" "$(cat "$T/args" 2>/dev/null)" "--resume $B"
check "  then the window is your shell, there, interactive" "$(cat "$T/shell" 2>/dev/null)" "$REAL|-i"
rm -f "$T/where" "$T/args" "$T/shell"
( cd "$T" && HOME="$H" SHELL="$STUBSH" PATH="$FAKE:$SYS" sh "$OUT/resume/$SB" )
check "the .sh lands there too" "$(cat "$T/where" 2>/dev/null)" "$REAL"
check "  and ends as your shell, there" "$(cat "$T/shell" 2>/dev/null)" "$REAL|-i"
rm -f "$T/shell"
( cd "$T" && HOME="$H" SHELL="$STUBSH" CLAUDE_EXIT=3 PATH="$FAKE:$SYS" sh "$OUT/resume/$SB" )
check "  also when claude exits 3" "$(cat "$T/shell" 2>/dev/null)" "$REAL|-i"
check "the .sh's last line is the exec of the shell" "$(tail -1 "$OUT/resume/$SB")" 'exec "$s" -i'
# No usable $SHELL: unset, or not a program. bash, else sh, reading the
# commands it is given, as a window's shell reads what is typed.
# (Unset, a shell started from it fills it in from the password file, so
# empty is the case that reaches the launcher.)
ONE="$(printf '%s' "$REAL" | tr '\n' '@')@"
for sv in "" /nonexistent/shell "$T"; do
  o="$(cd "$T" && printf 'echo "is:$0:$(pwd -P | tr "\\n" @)"\n' | env HOME="$H" SHELL="$sv" PATH="$FAKE:$SYS" sh "$OUT/resume/$SB" 2>/dev/null)"
  check "  \$SHELL '$sv': bash instead, in the folder" "$(printf '%s\n' "$o" | grep '^is:')" "is:/bin/bash:$ONE"
done
# The folder gone: said in one line, and the shell opens at home.
mv "$WEIRD" "$T/away"
rm -f "$T/where" "$T/shell"
o="$( cd "$T" && HOME="$H" SHELL="$STUBSH" PATH="$FAKE:$SYS" sh "$OUT/resume/$SB" 2>&1 )"
check "a removed folder: said in one line" "$(printf '%s\n' "$o" | grep -c 'is no longer there, so this is a shell in your home folder')" 1
check "  claude not started, the shell at home" "$([ -f "$T/where" ] && echo ran || echo no) $(cat "$T/shell" 2>/dev/null)" "no $HREAL|-i"
rm -f "$T/shell"; SHELL="$STUBSH" rundesk >/dev/null 2>&1
check "  the .desktop too" "$(cat "$T/shell" 2>/dev/null)" "$HREAL|-i"
mv "$T/away" "$WEIRD"
pwned() { for d in "$T" "$ROOT" "$WEIRD" "$PLAIN" "$HERE"; do [ -e "$d/pwned" ] && echo "$d/pwned"; done; }
check "no part of the path was run" "$(pwned)" ""

# The macOS flavour is built by the same code, and had the same hole: it
# quoted the folder in double quotes, where $(…) and backticks run.
build darwin
SC="$(ls "$OUT/resume" | grep -- "-$B.command$")"
check "a darwin build writes .command only" "$(ls "$OUT/resume" | grep -vc '\.command$')" 0
rm -f "$T/where" "$T/shell"
( cd "$T" && HOME="$H" SHELL="$STUBSH" PATH="$FAKE:$SYS" bash "$OUT/resume/$SC" )
check "  and it lands in the awkward folder" "$(cat "$T/where" 2>/dev/null)" "$REAL"
check "  then is your login shell there, as Terminal's are" "$(cat "$T/shell" 2>/dev/null)" "$REAL|-l"
rm -f "$T/shell"
( cd "$T" && HOME="$H" SHELL="$STUBSH" CLAUDE_EXIT=3 PATH="$FAKE:$SYS" bash "$OUT/resume/$SC" )
check "  also when claude exits 3" "$(cat "$T/shell" 2>/dev/null)" "$REAL|-l"
check "  its last line is the exec of the shell" "$(tail -1 "$OUT/resume/$SC")" 'exec "$s" -l'
if [ -x /bin/zsh ]; then
  o="$(cd "$T" && printf 'echo "is:$0:$(pwd -P | tr "\\n" @)"\n' | env SHELL= HOME="$H" ZDOTDIR="$H" PATH="$FAKE:$SYS" bash "$OUT/resume/$SC" 2>/dev/null)"
  check "  no \$SHELL: zsh instead" "$(printf '%s\n' "$o" | grep '^is:' | cut -d: -f1-2)" "is:/bin/zsh"
fi

# A launcher written by an older version is written again by the next
# build, once, and its page is left alone.
PAGE="$OUT/sessions/$B.html"; touch -t 202001010000 "$PAGE"; PT="$(mtime_of "$PAGE")"
printf '#!/bin/bash\ncd -- /old || exit 1\nexec claude --resume %s\n' "$B" > "$OUT/resume/$SC"
node -e 'var f=process.argv[1], m=JSON.parse(require("fs").readFileSync(f,"utf8"));
  Object.keys(m).forEach(function(k){ delete m[k].lv; }); require("fs").writeFileSync(f, JSON.stringify(m));' "$OUT/.manifest.json"
build darwin
check "old launchers are written again by the next build" "$(tail -1 "$OUT/resume/$SC")" 'exec "$s" -l'
check "  without rebuilding the page" "$(mtime_of "$PAGE")" "$PT"
printf 'stale\n' > "$OUT/resume/$SC"; build darwin
check "  and only once: a current one is not rewritten" "$(cat "$OUT/resume/$SC")" stale
rm -f "$OUT/resume/$SC"; build darwin
build linux
check "back on linux, the .command files are pruned" "$(ls "$OUT/resume" | grep -c '\.command$')" 0
check "  and the linux launchers are there again" "$(ls "$OUT/resume" | grep -c '\.sh$')" 2

# ── 3. the actions flag ─────────────────────────────────────────────
echo "actions"
idx() { node -e 'var h=require("fs").readFileSync(process.argv[1],"utf8");
  var d=JSON.parse(/id="index-data">([\s\S]*?)<\/script>/.exec(h)[1]); console.log(d.actions)' "$OUT/index.html"; }
pageopen() { node -e 'var h=require("fs").readFileSync(process.argv[1],"utf8");
  var d=JSON.parse(/id="session-data">([\s\S]*?)<\/script>/.exec(h)[1]); console.log(JSON.stringify(d.meta.open))' "$OUT/sessions/$A.html"; }
check "linux without a handler: no link actions" "$(idx)" false
check "  and the page offers no project link or resume" "$(pageopen)" '""'
mkdir -p "$H/.local/share/applications"; : > "$H/.local/share/applications/claude-html-handler.desktop"
build linux
check "with the handler installed, actions are offered" "$(idx)" true
check "  and every page is rebuilt to offer them" "$(pageopen)" "\"$A\""
rm -f "$H/.local/share/applications/claude-html-handler.desktop"
build linux

# ── 4. the terminal command, per desktop ─────────────────────────────
echo "resume"
LA="$OUT/resume/$SA"
plan() { inenv "$1" bash "$HERE/claude-html" --resume-plan "$2" 2>&1 | sed -n 's/^command: //p'; }
q() { printf "'%s'" "$1"; }
check "ubuntu: gnome-terminal --" "$(plan ubuntu "$A")" "'gnome-terminal' '--' 'sh' $(q "$LA")"
check "fedora 41: ptyxis --new-window --" "$(plan fedora "$A")" "'ptyxis' '--new-window' '--' 'sh' $(q "$LA")"
check "fedora 40: kgx --" "$(plan fedora40 "$A")" "'kgx' '--' 'sh' $(q "$LA")"
check "kde: konsole -e" "$(plan kde "$A")" "'konsole' '-e' 'sh' $(q "$LA")"
check "xfce: xfce4-terminal -x" "$(plan xfce "$A")" "'xfce4-terminal' '-x' 'sh' $(q "$LA")"
check "bare wm: xterm -e" "$(plan bare "$A")" "'xterm' '-e' 'sh' $(q "$LA")"
check "\$TERMINAL=kitty: kitty, no flag" "$(plan custom "$A")" "'kitty' 'sh' $(q "$LA")"
check "wsl: Windows Terminal, back into this distribution" "$(plan wsl "$A")" \
  "'wt.exe' 'wsl.exe' '-d' 'Ubuntu' '--' 'sh' $(q "$LA")"
check "headless: prints the command to type instead" \
  "$(inenv headless bash "$HERE/claude-html" --resume-session "$A" 2>&1)" \
  "run: cd -- '$PLAIN' && claude --resume $A"
check "  and for a folder with a line break, the launcher" \
  "$(inenv headless bash "$HERE/claude-html" --resume-session "$B" 2>&1)" \
  "run: sh '$OUT/resume/$SB'"

# The terminals that take one string split it themselves, POSIX-fashion.
mkenv lx ubuntu 24.04 debian Lubuntu
var lx XDG_CURRENT_DESKTOP=LXDE; var lx DISPLAY=:0; stub "$T/env/lx/bin" lxterminal
LINE="$(plan lx "$B")"
check "lxterminal: -e and a single quoted string" "$(printf '%s' "$LINE" | sed "s/^'lxterminal' '-e' .*/ok/")" ok
STR2="$(sh -c 'eval "set -- $1"; eval "set -- $3"; printf "%s" "$2"' sh "$LINE")"
check "  which splits back into exactly sh and the launcher" "$STR2" "$OUT/resume/$SB"

clearlog ubuntu
inenv ubuntu bash "$HERE/claude-html" --resume-session "$A" >/dev/null 2>&1
check "resume really calls the terminal" "$(log ubuntu)" "gnome-terminal [--] [sh] [$LA]"
check "  and notes what it did beside .last-open" "$(sed 's/^[0-9-]* [0-9:]*  //' "$OUT/.last-resume")" \
  "gnome-terminal  $LA"
check "resume refuses an id not in the index" \
  "$(inenv ubuntu bash "$HERE/claude-html" --resume-session 99999999-9999-4999-8999-999999999999 >/dev/null 2>&1; echo $?)" 1
check "resume refuses something that is not an id" \
  "$(inenv ubuntu bash "$HERE/claude-html" --resume-session "$A; touch $T/pwned" >/dev/null 2>&1; echo $?)" 2

# An archive planted in a cloned repo under the root, named with any id: the
# build lists it and writes it a launcher, but any website can open its
# resume and open links unasked, so neither does anything for it.
PL=dddddddd-6666-4666-8666-000000000066
CLONED="$ROOT/cloned-repo"; mkdir -p "$CLONED/.claude/.claude-conversations"
echo "<h1>theirs</h1>" > "$CLONED/index.html"
printf '{"format":6,"sessionId":"%s","title":"planted","messages":[{"role":"user","text":"hello","timestamp":"2026-11-01T10:00:00Z"}]}\n' "$PL" \
  > "$CLONED/.claude/.claude-conversations/$PL.json"
build linux
check "a planted archive is listed, with a launcher" \
  "$(grep -c "\"$PL\"" "$OUT/.manifest.json") $(ls "$OUT/resume" | grep -c -- "-$PL.sh$")" "1 1"
clearlog ubuntu
R="$(inenv ubuntu bash "$HERE/claude-html" --resume-session "$PL" 2>&1)"; RC=$?
check "  but resuming it opens nothing, and says why" "$R $RC|$(log ubuntu)" \
  "Claude Code has no transcript of that conversation, so it cannot be resumed 1|"
check "  nor does opening its project" \
  "$(inenv ubuntu bash "$HERE/claude-html" --open "$PL" >/dev/null 2>&1; echo $?)|$(log ubuntu)" "1|"
# Once claude-html's own hook has archived into a folder, its project opens.
printf '%s\n' "$CLONED" > "$H/.claude/claude-html.own-archives"
check "  a folder the hook archived into opens" \
  "$(inenv headless bash "$HERE/claude-html" --open "$PL" 2>&1)" "page: $CLONED/index.html"
rm -f "$H/.claude/claude-html.own-archives"
rm -rf "$CLONED"; build linux

# The index's run button for an update: this clone's command, --update, in
# the same terminal, kept open until Enter.
echo "update"
CLIP="$(cd -P "$HERE" && pwd)/claude-html"
UL="$H/.claude/.claude-html-update.sh"
uplan() { inenv "$1" bash "$HERE/claude-html" --update-terminal-plan 2>&1 | sed -n 's/^command: //p'; }
check "update, ubuntu: gnome-terminal --" "$(uplan ubuntu)" "'gnome-terminal' '--' 'sh' '$UL'"
check "update, fedora 41: ptyxis --new-window --" "$(uplan fedora)" "'ptyxis' '--new-window' '--' 'sh' '$UL'"
check "update, kde: konsole -e" "$(uplan kde)" "'konsole' '-e' 'sh' '$UL'"
check "update, xfce: xfce4-terminal -x" "$(uplan xfce)" "'xfce4-terminal' '-x' 'sh' '$UL'"
check "update, bare wm: xterm -e" "$(uplan bare)" "'xterm' '-e' 'sh' '$UL'"
check "update, \$TERMINAL=kitty: kitty, no flag" "$(uplan custom)" "'kitty' 'sh' '$UL'"
check "update, wsl: Windows Terminal, back into this distribution" "$(uplan wsl)" \
  "'wt.exe' 'wsl.exe' '-d' 'Ubuntu' '--' 'sh' '$UL'"
check "update, headless: prints the command to type instead" \
  "$(inenv headless bash "$HERE/claude-html" --update-terminal 2>&1)" "run: '$CLIP' --update"
clearlog ubuntu; rm -f "$UL"
inenv ubuntu bash "$HERE/claude-html" --update-terminal >/dev/null 2>&1
check "update really calls the terminal, on a launcher" "$(log ubuntu)" "gnome-terminal [--] [sh] [$UL]"
check "  which runs this clone's --update on a yes, then exec's the shell, last" \
  "$(grep -c "y|Y|yes|YES) '$CLIP' --update ;;" "$UL") | $(tail -1 "$UL")" "1 | exec \"\$s\" -i"
clearlog ubuntu
check "  a second window within a minute is refused" \
  "$(inenv ubuntu bash "$HERE/claude-html" --update-terminal >/dev/null 2>&1; echo $?) $(log ubuntu)" "1 "
# Run it, with a stand-in for this clone's command that fails.
UF="$T/upd"; mkdir -p "$UF"; printf '#!/bin/sh\necho "the update says $1"; exit 1\n' > "$UF/claude-html"; chmod +x "$UF/claude-html"
sed "s|'$CLIP' --update|'$UF/claude-html' --update|" "$UL" > "$T/ul.sh"
rm -f "$T/shell"
o="$(cd "$T" && echo yes | HOME="$H" SHELL="$STUBSH" PATH="$SYS" sh "$T/ul.sh")"
check "  its output stays above the shell, which it ends as, even after a failure" \
  "$(printf '%s' "$o" | head -1 | sed 's/.*\] //') | $(cat "$T/shell" 2>/dev/null)" "the update says --update | $(cd "$T" && pwd -P)|-i"

# ── 5. open ─────────────────────────────────────────────────────────
echo "open"
clearlog ubuntu
inenv ubuntu bash "$HERE/claude-html" --open "$A" >/dev/null 2>&1
check "ubuntu: xdg-open gets the folder" "$(log ubuntu)" "xdg-open [$PLAIN]"
# The index after a build, by the opener picked: on Debian /usr/bin/open is
# openvt, and a command named open says nothing about the machine.
stub "$T/env/ubuntu/bin" open
clearlog ubuntu
inenv ubuntu bash "$HERE/claude-html" >/dev/null 2>&1
check "the built index opens with the desktop's opener, not a command named open" "$(log ubuntu)" "xdg-open [$OUT/index.html]"
rm -f "$T/env/ubuntu/bin/open"
check "  and .last-open says so" "$(sed 's/^[0-9-]* [0-9:]*  //' "$OUT/.last-open")" "folder  $PLAIN"
check "headless: says where, opens nothing" "$(inenv headless bash "$HERE/claude-html" --open "$A" 2>&1)" \
  "folder: $PLAIN"

# ── 6. the link handler ─────────────────────────────────────────────
echo "handler"
# A copy of the handler beside a stand-in command, so what it would ask the
# command to do is written down instead of done.
HD="$T/handler"; mkdir -p "$HD/linux" "$HD/lib"
cp "$HERE/linux/handler.sh" "$HD/linux/"; cp "$HERE/lib/platform.sh" "$HD/lib/"
cat > "$HD/claude-html" <<'SH'
#!/bin/sh
{ printf 'cli'; for a in "$@"; do printf ' [%s]' "$a"; done; echo; } >> "$STUB_LOG"
case "$1" in
  --delete-plan) printf 'TITLE\t%s\nACTION\ttrash\nITEM\t~/x.jsonl\ttranscript\nHISTORY\t2\n' "$PLAN_TITLE" ;;
  --resume-session) [ -n "${NO_TERM:-}" ] && echo "run: cd -- '/x' && claude --resume $2" ;;
  --settings-apply) [ -z "${APPLY_OUT:-}" ] || printf '%s\n' "$APPLY_OUT"; exit "${APPLY_RC:-0}" ;;
esac
exit 0
SH
chmod +x "$HD/claude-html"
handle() { inenv "$1" PLAN_TITLE='a <b>title</b> "q" $(touch '"$T"'/pwned) `id`' sh "$HD/linux/handler.sh" "${@:2}"; }

for bad in "claude-html://delete/$A/extra" "claude-html://open/$A;rm -rf ~" \
           "claude-html://open/\$(touch $T/pwned)" "claude-html://resume/../../etc/passwd" \
           "claude-html://run/$A" "claude-html://open/$A?x=1" "claude-html://open/$A#f" \
           "claude-html://open/$A%0a" "claude-html://open/$A${NL}claude-html://delete/$A" \
           "claude-html://open/${A%?}" "claude-html://open/${A}0" "http://evil/open/$A" \
           "claude-html:open/$A" "CLAUDE-HTML://open/$A" "claude-html://open/$A " \
           "claude-html://open//$A" "claude-html://open/\`id\`" "claude-html://" "" \
           "claude-html://open/zzzzzzzz-1111-4111-8111-000000000001" "claude-html://Open/$A" \
           "claude-html://update/anything" "claude-html://update/" "claude-html://update?x" \
           "claude-html://update#x" "claude-html://update " "claude-html://Update" "claude-html://UPDATE" \
           "CLAUDE-HTML://update" "claude-html://%75pdate" "claude-html://update%2F" "claude-html://update/$A" \
           "claude-html://update${NL}claude-html://delete/$A" "claude-html:update"; do
  clearlog ubuntu
  code="$(handle ubuntu "$bad" >/dev/null 2>&1; echo $?)"
  check "refused: $(printf '%s' "$bad" | tr '\n' '|')" "$code:$(log ubuntu | grep -c '^cli')" "2:0"
done
clearlog ubuntu
check "refused: two arguments" "$(handle ubuntu "claude-html://open/$A" extra >/dev/null 2>&1; echo $?):$(log ubuntu | grep -c cli)" "2:0"
check "nothing anywhere was run from a link" "$(pwned)" ""

# A limits link from the Token usage page: its fixed grammar, and nothing
# else, no variant of it.
LG="v1/fri-2000-80.sat-0000-90/50-week/80-95/off"
for bad in "claude-html://limits/$LG/" "claude-html://limits/$LG?x=1" "claude-html://limits/$LG#f" \
           "claude-html://limits/$LG%0a" "claude-html://limits/$LG " "claude-html://limits/$LG;id" \
           "claude-html://limits/$LG${NL}claude-html://delete/$A" "claude-html://limits/" "claude-html://limits" \
           "claude-html://Limits/$LG" "CLAUDE-HTML://limits/$LG" "claude-html://limits//$LG" "claude-html:limits/$LG" \
           "claude-html://limits/V1/fri-2000-80/none/80-95/on" "claude-html://limits/v1/fri-2400-80/none/80-95/on" \
           "claude-html://limits/v1/fri-2000-80/none/80-95/on/\$(touch $T/pwned)" "claude-html://limits/v1/none/none/80-95/\`id\`" \
           "claude-html://limits/v1/none/0.5-week/80-95/on" "claude-html://limits/v1/none/none/80-100/on" \
           "claude-html://limits/v1/none/none/80-95/on/../../x" "claude-html://limits/$(printf 'v1/none/none/80-95/on%0200d' 0)"; do
  clearlog ubuntu
  code="$(handle ubuntu "$bad" >/dev/null 2>&1; echo $?)"
  check "refused: $(printf '%s' "$bad" | tr '\n' '|' | cut -c1-90)" "$code:$(log ubuntu | grep -c '^cli')" "2:0"
done
check "nothing anywhere was run from a limits link" "$(pwned)" ""
clearlog ubuntu; handle ubuntu "claude-html://limits/$LG" >/dev/null 2>&1
check "a limits link asks the command for exactly that" "$(log ubuntu)" "cli [--limits-apply] [$LG]"

# A settings link from the Settings page: v1/, its characters and its
# length, then the command reads it whole; Applied, the page opens again.
SG="v1/0123456789abcdef/GUARD_WAIT=2m/WEEK_RESET=tue%2007%3A00%20UTC/ENGINE/forget-safe"
for bad in "claude-html://settings/$SG?x=1" "claude-html://settings/$SG#f" "claude-html://settings/$SG;id" \
           "claude-html://settings/$SG " "claude-html://settings/$SG${NL}claude-html://delete/$A" "claude-html://settings/" \
           "claude-html://settings" "claude-html://Settings/$SG" "claude-html://settings//$SG" "claude-html://settings/V1/none/GUARD=off" \
           "claude-html://settings/v1/none/EXPORT=\$(touch $T/pwned)" "claude-html://settings/v1/none/GUARD=\`id\`" \
           "claude-html://settings/v1/none/EXPORT='/x'" "claude-html://settings/v1/none/EXPORT=\"/x\"" \
           "claude-html://settings/v1/none/PRICES=$(printf 'a%.0s' $(seq 1 2100))"; do
  clearlog ubuntu
  code="$(handle ubuntu "$bad" >/dev/null 2>&1; echo $?)"
  check "refused: $(printf '%s' "$bad" | tr '\n' '|' | cut -c1-90)" "$code:$(log ubuntu | grep -c '^cli')" "2:0"
done
check "nothing anywhere was run from a settings link" "$(pwned)" ""
hset() { inenv ubuntu APPLY_OUT="$1" APPLY_RC="$2" sh "$HD/linux/handler.sh" "claude-html://settings/$SG" >/dev/null 2>&1; }
clearlog ubuntu; handle ubuntu "claude-html://settings/$SG" >/dev/null 2>&1
check "a settings link asks the command for exactly that" "$(log ubuntu)" "cli [--settings-apply] [$SG]"
clearlog ubuntu; hset "$(printf 'Applied.\n%s' "$OUT/settings.html")" 0
check "  applied: the Settings page opened again" "$(log ubuntu | grep -v '^cli')" "xdg-open [$OUT/settings.html]"
clearlog ubuntu; hset "Nothing was changed." 0
check "  cancelled: nothing opened, nothing said" "$(log ubuntu | grep -v '^cli')" ""
clearlog ubuntu; hset "not a settings link, so nothing was changed:" 2
check "  refused by the command: the window says why" "$(log ubuntu | grep '^zenity' | grep -c 'The settings were not changed.')" 1
clearlog ubuntu; hset "a window asking about the settings is already open" 3
check "  a window already asking: nothing more" "$(log ubuntu | grep -vc '^cli')" 0

clearlog ubuntu; handle ubuntu "claude-html://update" >/dev/null 2>&1
check "an update link asks for exactly that, and names nothing" "$(log ubuntu)" "cli [--update-terminal]"
clearlog ubuntu; handle ubuntu "claude-html://resume/$A" >/dev/null 2>&1
check "a resume link asks for exactly that" "$(log ubuntu)" "cli [--resume-session] [$A]"
clearlog ubuntu; handle ubuntu "claude-html://open/$A/" >/dev/null 2>&1
check "an open link, trailing slash and all" "$(log ubuntu)" "cli [--open] [$A]"

clearlog ubuntu
inenv ubuntu STUB_ANSWER=1 PLAN_TITLE='a <b>title</b> "q" $(touch '"$T"'/pwned) `id`' sh "$HD/linux/handler.sh" "claude-html://delete/$A" >/dev/null 2>&1
check "delete, cancelled: looks it up, deletes nothing" "$(log ubuntu | grep -c '^cli \[--delete\]')" 0
check "  zenity asked, without markup, Cancel the default" \
  "$(log ubuntu | grep '^zenity' | grep -c '\[--question\] \[--no-markup\] \[--default-cancel\]')" 1
check "  and showed the title as plain text" \
  "$(log ubuntu | grep '^zenity' | grep -c 'a <b>title</b> "q" $(touch')" 1
clearlog ubuntu
inenv ubuntu STUB_ANSWER=0 PLAN_TITLE=t sh "$HD/linux/handler.sh" "claude-html://delete/$A" >/dev/null 2>&1
check "delete, confirmed: then and only then --yes" "$(log ubuntu | grep '^cli \[--delete\]')" "cli [--delete] [$A] [--yes]"

clearlog kde
inenv kde STUB_ANSWER=0 PLAN_TITLE='<b>bold</b>' sh "$HD/linux/handler.sh" "claude-html://delete/$A" >/dev/null 2>&1
check "kde: kdialog asks, and gets no markup to render" \
  "$(log kde | grep '^kdialog' | grep -c '\[--warningcontinuecancel\] \[Delete "‹b›bold‹/b›"')" 1
check "  then deletes" "$(log kde | grep -c '^cli \[--delete\]')" 1

clearlog bare
inenv bare STUB_ANSWER=1 PLAN_TITLE=t sh "$HD/linux/handler.sh" "claude-html://delete/$A" >/dev/null 2>&1
check "bare wm: xmessage asks, Cancel the default" \
  "$(log bare | grep '^xmessage' | grep -c '\[-buttons\] \[Cancel:1,Move to Trash:0\] \[-default\] \[Cancel\]')" 1
check "  and a cancel deletes nothing" "$(log bare | grep -c '^cli \[--delete\]')" 0

clearlog xfce
inenv xfce PLAN_TITLE=t sh "$HD/linux/handler.sh" "claude-html://delete/$A" >/dev/null 2>&1
check "xfce, no dialog tool: the question goes to a terminal window" \
  "$(log xfce | grep '^xfce4-terminal' | sed "s|$(cd -P "$HD" && pwd)|HD|")" \
  "xfce4-terminal [-x] [sh] [-c] [\"\$0\" --delete \"\$1\"; printf \"\\nPress Enter to close. \"; read -r _] [HD/claude-html] [$A]"
check "  and nothing is deleted unasked" "$(log xfce | grep -c '\[--yes\]')" 0

clearlog headless
check "headless: a delete link is refused" \
  "$(inenv headless PLAN_TITLE=t sh "$HD/linux/handler.sh" "claude-html://delete/$A" >/dev/null 2>&1; echo $?)" 1
check "  and nothing is deleted" "$(log headless | grep -c '^cli \[--delete\]')" 0

# The command behind it, on each desktop: it always asks first, in the
# desktop's own question, Cancel the default; no yes, nothing written.
echo "limits"
LCONF="$H/.claude/claude-html.conf"; cp "$LCONF" "$T/lconf.before"
lapply() { clearlog "$1"; inenv "$1" STUB_ANSWER="${2:-1}" bash "$HERE/claude-html" --limits-apply "$LG" 2>&1; }
check "ubuntu: zenity asks, a question, Cancel the default, Apply" \
  "$(lapply ubuntu 1 >/dev/null; log ubuntu | grep -c '^zenity \[--question\] \[--no-markup\] \[--default-cancel\] \[--title=claude-html\] \[--ok-label=Apply\] \[--cancel-label=Cancel\]')" 1
check "  Cancel: the conf as it was" "$(cmp -s "$LCONF" "$T/lconf.before" && echo same)" same
check "kde: kdialog asks" "$(lapply kde 1 >/dev/null; log kde | grep -c '^kdialog \[--title\] \[claude-html\] \[--continue-label\] \[Apply\] \[--warningcontinuecancel\]')" 1
check "bare wm: xmessage, Cancel the default" "$(lapply bare 1 >/dev/null; log bare | grep -c '\[-buttons\] \[Cancel:1,Apply:0\] \[-default\] \[Cancel\]')" 1
check "xfce, no dialog tool: refused, the commands said, nothing written" \
  "$(lapply xfce 0 | grep -c '^no way to ask you first here') $(cmp -s "$LCONF" "$T/lconf.before" && echo same)" "1 same"
check "headless: the same" "$(lapply headless 0 | grep -c '^no way to ask you first here')" 1
check "ubuntu, Apply: written" "$(lapply ubuntu 0 | tail -1) $(grep -c '^CLAUDE_HTML_LIMIT_RULES="fri 20:00 80% · sat 00:00 90%"$' "$LCONF")" "Applied. 1"
cp "$T/lconf.before" "$LCONF"
check "  the question lists the very lines it writes, and how long it waits" \
  "$(lapply ubuntu 1 >/dev/null; log ubuntu | grep -c -e '^Written to the file:$' -e '^CLAUDE_HTML_LIMIT_RULES="fri 20:00 80% · sat 00:00 90%"$' -e '^CLAUDE_HTML_LIMIT_NOTIFY="' -e '^Closes after 1 minute — nothing changed.\]')" 4
cp "$T/lconf.before" "$LCONF"; printf 'CLAUDE_HTML_GUARD_WAIT="1m30s"\n' >> "$LCONF"
check "  as long as the conf's CLAUDE_HTML_GUARD_WAIT says" \
  "$(lapply ubuntu 1 >/dev/null; log ubuntu | grep -c '^Closes after 90 seconds — nothing changed.\]')" 1
cp "$T/lconf.before" "$LCONF"; printf 'CLAUDE_HTML_GUARD_WAIT="2 hours"\n' >> "$LCONF"
check "  and a minute when it says what is not a wait" \
  "$(lapply ubuntu 1 >/dev/null; log ubuntu | grep -c '^Closes after 1 minute — nothing changed.\]')" 1
cp "$T/lconf.before" "$LCONF"
# The guard's question on each desktop, dry: what was found and the whole
# command are never in the question (an argument, which any local process
# can read), only in a private file its own text window reads.
GD="$T/guard-details"; mkdir -p "$GD"; : > "$GD/found"; : > "$GD/command"; : > "$GD/details.txt"
gdry() { inenv "$1" CH_DRY=1 bash -c '. "$0/lib/platform.sh"; ch_detect; CH_HERE="$0"; ch_choose bash Weather "MySQL password (1)" "mysql -u root -p*** db" "$1"' "$HERE" "$GD"; }
check "ubuntu: zenity, a Details button, then zenity's text window on the private file" \
  "$(gdry ubuntu | grep -c -e "^Closes after 1 minute — counts as Cancel.' '--ok-label=OK' '--extra-button=Details' " -e "^'zenity' '--text-info' '--title=claude-html' '--filename=$GD/details.txt' '--width=720' '--height=460'$")" 2
check "  the guard's question says the wait set: 45 seconds" \
  "$(inenv ubuntu CLAUDE_HTML_GUARD_WAIT=45 CH_DRY=1 bash -c '. "$0/lib/platform.sh"; ch_detect; ch_choose prompt P "GitHub token (1)"' "$HERE" | grep -c '^Closes after 45 seconds — counts as Cancel.')" 1
check "kde: kdialog, a fifth entry, then its text box" \
  "$(gdry kde | grep -c -e "'details' 'Details — show what was found and the whole command' 'off'$" -e "^'kdialog' '--title' 'claude-html' '--textbox' '$GD/details.txt' '720' '460'$")" 2
check "bare wm: xmessage, a Details button, then the file shown by xmessage" \
  "$(gdry bare | grep -c -e "'Cancel:1,Allow once:2,Safe:3,Stop:4,Details:5'" -e "^'xmessage' '-center' '-title' 'claude-html' '-buttons' 'Back:0' '-default' 'Back' '-file' '$GD/details.txt'$")" 2
check "  without details (none written), no Details at all" \
  "$(inenv ubuntu CH_DRY=1 bash -c '. "$0/lib/platform.sh"; ch_detect; ch_choose prompt P "GitHub token (1)"' "$HERE" | grep -c 'Details')" 0
# The banner, where the desktop has notify-send; none headless.
stub "$T/env/ubuntu/bin" notify-send
check "notify-send: the banner on a Linux desktop" \
  "$(clearlog ubuntu; inenv ubuntu bash -c '. "$0/lib/limits.sh"; CH_LIM_NOTIFY=1; ch_lim_banner "your stop rule starts Fri 20:00 at 80 %"; wait' "$HERE"; log ubuntu)" \
  "notify-send [-a] [claude-html] [claude-html] [your stop rule starts Fri 20:00 at 80 %]"
check "  none headless" "$(clearlog headless; inenv headless bash -c '. "$0/lib/limits.sh"; CH_LIM_NOTIFY=1; ch_lim_banner x; wait' "$HERE"; log headless)" ""

# ── 7. moving things to the trash ────────────────────────────────────
echo "trash"
mkconv() {   # id: a conversation with a transcript, a file-history folder and a page
  transcript "$1" "$PLAIN" "throwaway $1"
  mkdir -p "$H/.claude/file-history/$1"; echo snap > "$H/.claude/file-history/$1/edit-1"
  build linux
}
C1=cccccccc-3333-4333-8333-000000000003
mkconv "$C1"
check "the plan lists the linux launchers" \
  "$(inenv ubuntu bash "$HERE/claude-html" --delete-plan "$C1" | grep -c 'resume launcher')" 2
clearlog ubuntu
inenv ubuntu bash "$HERE/claude-html" --delete "$C1" --yes >/dev/null 2>&1
check "ubuntu: gio trash took the transcript" \
  "$(log ubuntu | grep -c "^gio \[trash\] \[--\] \[$H/.claude/projects/-p-$C1/$C1.jsonl\]")" 1
check "  and it is gone from where it was" "$([ -e "$H/.claude/projects/-p-$C1/$C1.jsonl" ] && echo there || echo gone)" gone

C2=cccccccc-3333-4333-8333-000000000004
mkconv "$C2"
inenv kde bash "$HERE/claude-html" --delete "$C2" --yes >/dev/null 2>&1
check "kde: kioclient5 moves to trash:/" \
  "$(log kde | grep -c "^kioclient5 \[--noninteractive\] \[move\] \[$H/.claude/projects/-p-$C2/$C2.jsonl\] \[trash:/\]")" 1

# The spec by hand: no tool at all on the bare window manager.
C3=cccccccc-3333-4333-8333-000000000005
mkconv "$C3"
TR="$H/.local/share/Trash"
mkdir -p "$TR/files"; echo "an older one" > "$TR/files/$C3.jsonl"   # a name already taken
ORIG="$H/.claude/projects/-p-$C3/$C3.jsonl"
cp "$ORIG" "$T/orig.jsonl"
inenv bare bash "$HERE/claude-html" --delete "$C3" --yes >/dev/null 2>&1
check "bare wm: the transcript left its folder" "$([ -e "$ORIG" ] && echo there || echo gone)" gone
check "  into Trash/files, beside the older one of that name" "$(ls "$TR/files" | grep -cE "^$C3(\.2)?\.jsonl$")" 2
INFO="$(grep -l "^Path=.*$C3/$C3.jsonl$" "$TR/info/"*.trashinfo 2>/dev/null | head -1)"
check "  with a .trashinfo for it" "$([ -n "$INFO" ] && echo yes || echo no)" yes
check "  named after the file it kept, not the taken name" "$(basename "$INFO")" "$C3.2.jsonl.trashinfo"
check "  starting [Trash Info]" "$(head -1 "$INFO")" "[Trash Info]"
check "  with DeletionDate as the spec writes it" \
  "$(grep -c '^DeletionDate=[0-9]\{4\}-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]$' "$INFO")" 1
# What a desktop's "restore" does: read Path, percent-decode it, move back.
restore() {
  local info="$1" name; name="$(basename "$info" .trashinfo)"
  local to; to="$(node -e 'var t=require("fs").readFileSync(process.argv[1],"utf8");
    process.stdout.write(decodeURIComponent(/^Path=(.*)$/m.exec(t)[1]))' "$info")"
  mv "$TR/files/$name" "$to" && rm -f "$info"
}
restore "$INFO"
check "restored, it is back where it was, the same file" "$(cmp -s "$ORIG" "$T/orig.jsonl" && echo same || echo different)" same

# A path that needs escaping: percent-encoded in, decoded out.
mkdir -p "$T/odd dir"; printf 'x' > "$T/odd dir/a b%c ü.txt"
# delete.js's own platform layer, called straight: HOME and XDG_DATA_HOME
# point into the fake home, so the real trash is never touched.
spec_trash() {
  HOME="$H" XDG_DATA_HOME="${2:-$H/.local/share}" node -e '
    var src = require("fs").readFileSync(process.argv[1], "utf8");
    var platform = new Function("require", "process", src + "\nreturn platform;")(require, process);
    process.stdout.write(String(platform().trash(process.argv[2], "spec")));' "$HERE/actions/delete.js" "$1" 2>&1
}
spec_trash "$T/odd dir/a b%c ü.txt" > "$T/r"
check "an awkward name goes in" "$(cat "$T/r")" true
INFO="$TR/info/a b%c ü.txt.trashinfo"
check "  its Path is percent-encoded" "$(sed -n 's/^Path=//p' "$INFO")" \
  "$(node -e 'console.log(encodeURIComponent(process.argv[1]).replace(/%2F/g,"/"))' "$T/odd dir/a b%c ü.txt")"
restore "$INFO"
check "  and comes back out to the same name" "$(cat "$T/odd dir/a b%c ü.txt" 2>/dev/null)" x

# Another filesystem: refused, not copied. /dev/shm is a separate tmpfs on
# Linux; macOS has nothing so handy, and the check is skipped there.
if [ -d /dev/shm ] && [ -w /dev/shm ] && [ "$(stat -c %d /dev/shm 2>/dev/null)" != "$(stat -c %d "$T" 2>/dev/null)" ]; then
  X="$(mktemp -d /dev/shm/chlinux.XXXXXX)"; echo x > "$X/f"
  R="$(spec_trash "$X/f" "$T/xd")"
  check "another filesystem is refused" "$(printf '%s' "$R" | grep -c 'another filesystem')" 1
  check "  and the file stays" "$(cat "$X/f")" x
  rm -f "$X/f"; rmdir "$X"
else
  printf '  skip  no second filesystem to try the refusal on\n'
fi

# Headless, a person at a terminal can still delete; with no terminal, nothing.
C4=cccccccc-3333-4333-8333-000000000006
mkconv "$C4"
inenv headless bash "$HERE/claude-html" --delete "$C4" </dev/null >/dev/null 2>&1
check "headless, unconfirmed: nothing moves" \
  "$([ -e "$H/.claude/projects/-p-$C4/$C4.jsonl" ] && echo there || echo gone)" there

# ── 8. registering the handler ───────────────────────────────────────
echo "register"
reg() { inenv ubuntu XDG_DATA_HOME="$T/xdg" XDG_CONFIG_HOME="$T/xdgc" sh -c '. "$1/lib/platform.sh"; ch_detect; '"$1" sh "$HERE"; }
clearlog ubuntu
check "CLAUDE_HTML_NO_REGISTER is honoured" "$(reg 'ch_register_handler "$1"')" \
  "not registered: CLAUDE_HTML_NO_REGISTER is set"
check "a handler in a temp folder is refused" \
  "$(inenv ubuntu sh -c '. "$1/lib/platform.sh"; ch_detect; unset CLAUDE_HTML_NO_REGISTER CLAUDE_HTML_TEMP_DIRS; ch_register_handler /tmp/x' sh "$HERE")" \
  "not registered: /tmp/x is a temporary folder"
check "  and so is one in a folder CLAUDE_HTML_TEMP_DIRS names" \
  "$(inenv ubuntu sh -c '. "$1/lib/platform.sh"; ch_detect; unset CLAUDE_HTML_NO_REGISTER; ch_register_handler "$2/x"' sh "$HERE" "$TEMPS")" \
  "not registered: $TEMPS/x is a temporary folder"
check "  which then replaces the built-in list" \
  "$(inenv ubuntu sh -c '. "$1/lib/platform.sh"; ch_is_temp /tmp/x && echo temp || echo kept' sh "$HERE")" kept
regok() { inenv ubuntu XDG_DATA_HOME="$T/xdg" XDG_CONFIG_HOME="$T/xdgc" sh -c '. "$1/lib/platform.sh"; ch_detect; unset CLAUDE_HTML_NO_REGISTER; '"$1" sh "$HERE"; }
# The clone itself is the one place that is not temporary; everything this
# writes still goes into the fake XDG folders, and xdg-mime is a stand-in.
check "registering writes the handler" "$(regok 'ch_register_handler "$1"')" \
  "registered $T/xdg/applications/claude-html-handler.desktop"
HF="$T/xdg/applications/claude-html-handler.desktop"
check "  a valid desktop file" "$(desk "$HF" | cut -c1)" "{"
check "  that runs this handler with the link" "$(desk "$HF" argv)" \
  "$(node -e 'console.log(JSON.stringify([process.argv[1] + "/linux/handler.sh", "%u"]))' "$HERE")"
check "  and claims the scheme" "$(grep -c '^MimeType=x-scheme-handler/claude-html;$' "$HF")" 1
check "  through xdg-mime" "$(log ubuntu | grep '^xdg-mime')" \
  "xdg-mime [default] [claude-html-handler.desktop] [x-scheme-handler/claude-html]"
check "  and refreshes the desktop database" "$(log ubuntu | grep -c "^update-desktop-database \[$T/xdg/applications\]")" 1
mkdir -p "$T/xdgc"
printf '[Default Applications]\ntext/html=firefox.desktop\nx-scheme-handler/claude-html=claude-html-handler.desktop\n' > "$T/xdgc/mimeapps.list"
check "unregistering removes it" "$(regok 'ch_unregister_handler')" "removed $HF"
check "  and only our line from mimeapps.list" "$(cat "$T/xdgc/mimeapps.list")" \
  "$(printf '[Default Applications]\ntext/html=firefox.desktop')"
P2="$T/a \"clone\" \$x \`y\` back\\slash 100%"
check "an awkward clone path survives Exec quoting" \
  "$(inenv ubuntu sh -c '. "$1/lib/platform.sh"; printf "[Desktop Entry]\nType=Application\nName=x\nExec=%s %%u\n" "$(ch_desktop_arg "$2/linux/handler.sh")"' sh "$HERE" "$P2" > "$T/p2.desktop"; desk "$T/p2.desktop" argv)" \
  "$(node -e 'console.log(JSON.stringify([process.argv[1] + "/linux/handler.sh", "%u"]))' "$P2")"

# install.sh on a fake Ubuntu: registers, and the pages then offer actions.
H2="$T/home2"; mkdir -p "$H2/.claude"
inenv ubuntu HOME="$H2" XDG_DATA_HOME="$H2/.local/share" XDG_CONFIG_HOME="$H2/.config" \
  sh -c 'unset CLAUDE_HTML_NO_REGISTER; exec bash "$1/install.sh" --root "$2" --out "$3"' sh "$HERE" "$ROOT" "$T/pages2" > "$T/install.out" 2>&1
check "install.sh on ubuntu registers the handler" "$(grep -c 'links:    registered' "$T/install.out")" 1
check "  and the index it builds offers actions" "$(OUT="$T/pages2" idx)" true
inenv ubuntu HOME="$H2" XDG_DATA_HOME="$H2/.local/share" bash "$HERE/install.sh" --uninstall > "$T/uninstall.out" 2>&1
check "uninstall removes it" "$([ -e "$H2/.local/share/applications/claude-html-handler.desktop" ] && echo there || echo gone)" gone
inenv headless HOME="$H2" sh -c 'unset CLAUDE_HTML_NO_REGISTER; exec bash "$1/install.sh" --root "$2" --out "$3"' sh "$HERE" "$ROOT" "$T/pages3" > "$T/install3.out" 2>&1
check "install.sh headless says why there are no links" "$(grep -c 'links:    not registered: unavailable: no display' "$T/install3.out")" 1

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
