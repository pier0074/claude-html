# claude-html, in detail

How it all works. Every setting and command is in [SETUP.md](SETUP.md).

## What you get

**An index of every session**, newest first: date, project, Claude's title
for it, and how many prompts you typed. A row or its title opens the
conversation, which links back. Under the title: links to claude.ai and your
usage, and when the index was built, so a stopped hook shows. **Group by
project** lists projects by last use, with session and prompt counts. Narrow
windows drop the least useful columns and wrap titles; a phone scrolls the
table in its own box.

**Search across every conversation**: prompts, replies and thinking, as
highlighted snippets linking to the exact message. Each conversation shows
its five newest matches and how many more it has. All words must be in one
message; `"quoted text"` is a phrase; **match case** appears as you type.
Conversations whose search file is missing are counted as not searched.

**Readable session pages.** The header is the path to the page
(`claude-html / weather-app / 7c21a9b4-…`); a sub-agent page adds its
parent. Scrolled in, it folds to one line (path, find, prompt arrows)
without moving the page; ▾ or the top opens it. Tool calls are labelled,
every `Edit` is a real diff, and commands, diffs and writes show at once;
what a call returned stays folded. Thinking is kept, folded: a click opens
either, the page remembers it, and find opens whatever hides its match. Markdown tables are drawn as tables. **Printing** is light,
without buttons, folded as on screen.

**Two ways to read a long session.** **Conversation / Everything**:
Conversation hides tool calls, output and thinking, often nine tenths of the
page. Prompts are numbered; the arrows or `j`/`k` step through them. The find
bar (`/`; Enter, Shift-Enter; `«` `»` for first and last) counts matches,
offers match case, and skips what Conversation hides. Both use one control,
`« ‹ n / m › »`.

**Sub-agents stay with their conversation**: each has its own page, linked
from the call that spawned it and linking back; the index counts them
rather than listing them.

**What it cost.** Each session totals its replies' tokens: a column on the
index, and under the title the total, output, input, cached, replies and
output per reply. `usage.html` charts them per week, month or all time (by
day up to 130 days of history, by week beyond), by model or project, the
latest period against the one before. Empty periods are empty columns; a bar
links to its table row. Output is always named apart, since cache reads are
nearly all the volume and the cheapest part.

**Click a name to filter**: a model or project, in a table or the legend,
narrows the whole dashboard; click again or the chip's × to undo. Model and
project combine; the filter survives switching views and is remembered.

**The tables.** The first lists every period and ends with a total (with a
project chosen, all its sessions and sub-agents); the period button picks
the cards and the second table. With one name left by the filter, each
period is one row. A total's cost is what Claude Code recorded, `≥` if
partly recorded; `calc` rows are not in it, and the line below gives the
calculated total. A reply in several transcripts (resumed or forked
sessions copy messages) counts once on the dashboard but in each session's
total, so the index can add up to more.

**Recorded cost.** Recent Claude Code writes `cost-state` records: the
session's running total per model at API list prices. Where present, the
index has a Cost column, the title line says `≈ $498.94`, and the dashboard
shows a cost card, Cost columns and the cost in each bar's tooltip, stating
how many sessions it covers. Its limits:

- Older sessions and sub-agents (which spend on their parent's) have none;
  the calculated cost stands in, marked `calc`, or `—` with no price, never
  `$0.00`.
- A record is a running total written at exit, with no time: each counts
  what it added, filed under the previous record's hour, so work can land
  when it was closed. Hence the chart stays on tokens.
- A falling total or new start time is a new counter; a record copied into a
  resumed or forked transcript is skipped, so nothing counts twice.
- Replies before the first record or after the last (still open, unclean
  exit) are in none: the session says `≥`, not `≈`.
- On a subscription this is what the use would cost, not a bill.

**Calculated cost**, beside the recorded one and never added to it: tokens
times the price of the time, from `build/prices.tsv` (a line per model and
price period, from Anthropic's pricing page, with source and check date;
[SETUP.md](SETUP.md#prices) says how to add one). Shown as `$12.40 calc`
where nothing was recorded; the cost card shows both.

- **The price of the time**: the line whose `from`–`to` holds the reply's
  UTC day. *cost at · today's prices* uses the current line instead.
- **Five prices**: input, output, cache reads, and 5-minute and 1-hour cache
  writes (1.25× and 2× input), from each reply's `cache_creation`. Writes of
  unknown kind (old archives, old transcripts) count as 5-minute, shown as
  "split unknown".
- **Prices of their own**: fast mode is `<model>/fast`; a Claude Haiku 5.5
  request with over 100,000 prompt tokens is `haiku-5-5/over-100k`. Standard
  list prices only: no batch, US-only or cloud prices.
- **Unknown models are not priced**: an id matches its line, or a dated id
  (`claude-haiku-4-5-20251001`) the line without the date; anything else is
  left out, its sessions say `≥`, and the dashboard lists it.
- **Price history**: per model, the current and earlier prices, the change,
  your tokens and sessions in each period, the sources and last check.
- **A stale file gives quietly wrong numbers**, which is why the check
  dates are shown.

**Long conversations open quickly.** Past 400 rows, only rows near the
screen are built; the rest are placeholders of their height, built and
removed as you scroll. A 16 MB session (fifteen thousand messages) is ready
in about half a second instead of two, with about 900 DOM nodes instead of
94,000. Find, prompt arrows and `#m…` links reach every message, printing
builds everything, and ⌘F (Ctrl+F) goes to the page's find; pressed again,
to the browser's.

**A way back in.** **resume** reopens the conversation in a terminal in its
folder; **copy** copies the `cd … && claude --resume …` line; `resume/` has
a launcher per conversation (`.command` on macOS, `.desktop` and `.sh` on
Linux).

**Open the project.** A project name opens, decided at the click, its
running server, else its `index.html`, else its folder.

**Delete a conversation.** The bin moves it, after a dialog listing what
goes, to the Trash with all that belongs to it: transcript, edit snapshots,
archives (nested ones too), page, and its prompts in your up-arrow history.
Put Back restores it. An open conversation is refused; a claude.ai chat is
hidden, not deleted.

**Your claude.ai chats too.** A `conversations.json` export in
`~/Downloads`, the projects root, or one folder inside either is shown and
searched with the rest; `CLAUDE_HTML_EXPORT` names another, then the only
one read ([SETUP.md](SETUP.md#claudeai-exports)).

**Nothing to run.** Each session and its pages are saved in the background
after every reply and at its end, so a page is at most one reply behind.
Transcripts go after 30 days; archives stay.

## Install

Clone it where you want the pages, then run it:

```bash
git clone <this-repo> /path/where/you/want/the/pages
cd /path/where/you/want/the/pages
./install.sh
```

It asks nothing. The clone becomes the pages folder and its parent the
projects root, whose sessions are archived. Or choose:

```bash
./install.sh --out ~/somewhere/else --root ~/code
```

Running it again is safe: `~/.claude/claude-html.conf` keeps every line,
comments included, and gains only missing settings; `--out` and `--root`
change only their own line, so a later bare `./install.sh` keeps them.

### Uninstall

```bash
cd ~/claude-html && ./install.sh --uninstall
```

It removes the `claude-html` command (one leading to this clone), the helper
app or Linux link handler, its own hooks, and its state in `~/.claude`
(update logs, the guard's pending answers, update launchers). It keeps the
pages, archives, conf and `cleanupPeriodDays`. Nothing is saved after.

To erase every trace as well:

- delete the clone folder (the tool, its pages and `.cache/`)
- delete `~/.claude/claude-html.conf`, `~/.claude/claude-html.archives`,
  `~/.claude/claude-html.own-archives`, and if present
  `~/.claude/claude-html.hidden` (hidden claude.ai chats) and
  `~/.claude/claude-html.redact` (your own list of secrets and safe values)
- the archives are in each project, at any depth, in
  `.claude/.claude-conversations/`;
  `find ~/Sites -type d -path '*/.claude/.claude-conversations'` lists them
  (use your projects root); deleting them loses the conversations for good
- `cleanupPeriodDays` in `~/.claude/settings.json` stays at 3650 if the
  installer set it

### What it changes

| Path | Change |
| ---- | ------ |
| `~/.claude/claude-html.conf` | the two directories, and the week reset offered commented out; written once, then only added to |
| `~/.claude/settings.json` | hooks that save after every reply (`Stop`) and at the end (`SessionEnd`, `PreCompact`); the guard's; `statusLine`, claude-html's or claude-html's around yours; `cleanupPeriodDays` set to 3650 **only if you have not set it** |
| `~/.local/bin/claude-html` | a symlink, so you can type `claude-html` |
| `Claude HTML.app` | macOS: built at the top of the clone, beside `claude-html`; receives the index's delete, open and resume links |
| `~/.local/share/applications/claude-html-handler.desktop` | Linux, where there is a desktop: claims `claude-html://` links for `linux/handler.sh`, registered with `xdg-mime` |

**Your hooks are kept.** Its hooks are appended beside yours, which are never
rewritten; uninstalling removes only its own, and the installer says how many
of yours it left alone.

**A `cleanupPeriodDays` you set is kept.** It is raised only if you never
chose one, because transcripts hold more than archives (sub-agents, tool
output past the 6,000 characters a page shows, input past 20,000).

Archives go to `<project>/.claude/.claude-conversations/` in whichever
folder under the projects root the session ran, however deep. The pages
folder also holds `.cache/` (see [How it works](#how-it-works)), which can be
deleted at any time.

**Nothing else in the pages folder is touched.** Only files named for a
session that no longer exists (a page, launcher or search fragment) are
removed, and `index.html` is replaced; your own files there are safe.

### Requirements

**On macOS: nothing** but the system's tools (`bash`, `osascript`, `open`,
`curl`, `lsof`, `ps`…, and `osacompile`, `PlistBuddy`, `codesign`,
`lsregister` for the helper app); Intel and Apple silicon. `git` only to
update itself, never Apple's stand-in that offers the developer tools; a zip
download works but cannot update.

**node, when it is already there** (14.14 or later), builds three to four
times faster. It is found on `PATH` or where it is usually installed
(`/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin`, Volta, asdf, mise,
fnm, nvm), as hooks get a thin `PATH`; a version manager's shim is never
run, and each node is tried from `/` with five seconds to answer. Never
installed or required. Deleting, opening and resuming stay on `osascript`.
`--doctor` says which engine builds; `CLAUDE_HTML_ENGINE` chooses.

**On Linux: node** 14.14 or later, from the distribution (Claude Code's
installer brings none); without it nothing is built and `install.sh`,
`--doctor` and the save's error say so. Everything works as on a Mac
(`tests/backend.test.sh` proves identical output), with the machine's own
terminal, opener, trash and dialog ([On Linux](#on-linux)). Windows only
through WSL.

## Commands

Every `claude-html` and `./install.sh` command and flag is listed in
[SETUP.md](SETUP.md#commands). The test suites:

```bash
bash tests/run-all.sh           # every suite below, one verdict — what CI runs
bash tests/run-all.sh --parts-check  # the long suites whole and in their parts: the same checks, each once
node tests/viewer.test.js       # the renderer's tests, long-page windowing included
node tests/diff.test.js         # the diff, against every edit ever made here
node tests/index.test.js        # the index: search, its failures, and what Linux is shown
node tests/pages.test.js        # every page's head, print and words; the dashboard's chart, empty periods included
node tests/docs.test.js         # every setting the code reads is in SETUP.md, and every link resolves
node tests/settingspage.test.js # the Settings page: safe values by id, the own list, the status line, the limits panel
bash tests/backend.test.sh      # osascript and node build byte-identical pages; nested projects
bash tests/archive.test.sh      # a page made from the archive alone is the page made from the transcript
bash tests/engine.test.sh       # node does the data work when it is here and works; osascript when not
bash tests/incremental.test.sh  # a save that reads only what was appended writes what a build from nothing does
bash tests/races.test.sh        # the ways a message could be lost, and two saves or a stale lock
bash tests/build.test.sh        # a failed build never costs a page, nor does a lost manifest
bash tests/hooks.test.sh        # a save finds its transcript; a cut-short archive never wins
bash tests/agents.test.sh       # sub-agents land inside their parent, never rows of their own
bash tests/usage.test.sh        # the dashboard counts every reply once, and every cost, from transcript or archive
bash tests/prices.test.sh       # the price file, the line in force at a boundary, the 5-minute/1-hour split, calculated beside recorded
bash tests/redact.test.sh       # no secret reaches an archive, a page or a cache; the transcript is never touched
bash tests/guard.test.sh        # a prompt or command holding a secret is stopped, and each answer does what it says
bash tests/install.test.sh      # a second install keeps your conf; env, conf, default; only its own hooks
bash tests/update.test.sh       # --update, going back, the daily check, the automatic update, and copies that are not clones
bash tests/safety.test.sh       # an outside file cannot write elsewhere or break a page
bash tests/delete.test.sh       # deleting removes everything it should, and nothing else (macOS)
bash tests/open.test.sh         # a project name opens the right thing, and nothing else (macOS)
bash tests/helper.test.sh       # the helper app is built, and rebuilt when its source changes (macOS)
bash tests/linux.test.sh        # every Linux desktop, simulated: detection, terminals, trash, links
bash tests/doctor.test.sh       # --doctor's one layout: sections, padded labels, wrapping at a terminal
bash tests/gate.test.sh         # run-all.sh stopped part way stops its suites and their children, and cleans up
bash tests/release.test.sh      # the release's secret check and CI clean-up, offline (skips without dev/)
```

delete, open and helper need macOS and say so when skipped; linux runs
everywhere, against desktops it fakes. On a Mac the suites build with
`osascript` even where node is installed; `CLAUDE_HTML_FORCE_NODE=1` runs
everything through node.

Unchanged sessions are skipped, so a rebuild takes a fraction of a second;
`claude-html --force` rebuilds everything, reading every transcript whole.

### Configuration

Moved to [SETUP.md](SETUP.md), with every variable, its default and an example.

## How it works

**Where everything is.**

| Where | What |
| ----- | ---- |
| `claude-html`, `install.sh` | the command and the installer |
| `save-conversation.sh`, `guard.sh`, `statusline.sh` | what `settings.json` runs: the save, the guard and the status line, called by their full path, so they stay at the top |
| `lib/` | the shell the others source: the conf (`conf.sh`), what the machine has (`platform.sh`), the lock, the plan limits, the settings (`settings.sh`, and `settings.tsv`, which describes every one of them), the update (`update.sh`) and the release numbers (`version.sh`) |
| `build/` | the pages: `convert.js` builds them, with `parse.js`, `lines.js` (a transcript read a piece at a time, as the archiver reads it), `redact.js`, `prices.js` and its `prices.tsv`, `limits.js`, and `settings.js`, the one check of a setting's value in JavaScript |
| `actions/` | what the command and the installer run besides: the guard's judge, open, resume, delete, and the edit of `settings.json` |
| `mac/` | the helper app's source and build, and the windows (`dialog.js`) |
| `linux/` | the link handler |
| `viewer/` | what the pages carry: their HTML, CSS and JavaScript |
| `tests/` | the suites (`bash tests/run-all.sh`), their data in `tests/fixtures/` |
| `docs/` | this file and [SETUP.md](SETUP.md); the pictures in `docs/img/` |

The JavaScript is the same files under `osascript` and `node`, writing the
same bytes; `lib/platform.sh` gives the data work to node when a working one
is installed. A hook, after every reply and at a session's end, writes an
archive beside the project and rebuilds what changed: normally a third of a
second.

**A save reads only what was added.** Transcripts reach hundreds of
megabytes, with a gigabyte of sub-agents, and reading them whole took most
of a minute. So the archiver and the build keep in `.cache/` how far they
read (whole lines) and what the next lines need: encoded messages and
search rows, replies counted (one can straddle the cut), the cost counter,
the first prompt. A sub-agent is read again only when its size, time,
`.meta.json` or what its page shows of the parent changes. On a 166 MB
session with 322 sub-agents a save went from 57 s to under 3 (`osascript`)
and 17 s to under 2 (node).

The result is byte for byte what a save from nothing writes;
`tests/incremental.test.js` cuts transcripts at hundreds of points to prove
it. The cache is used only while it provably fits: its key holds the
program's source and usage format, each file's md5 must match, and the
transcript must be as long, with the same bytes at three sampled points,
checked when read and again before the cache is written. Otherwise the save
reads from the start; `--force` always does. Saves take turns through a lock
(`claude-html` too); a build without it skips the cache. **Deleting
`.cache/` is always safe**; a deleted conversation's goes at the next build.

A session is unchanged only at exactly its last size (a timestamp misses a
reply in the same second as the save). Each save knows its transcript from
Claude Code's note to the hook; run by hand it searches the project's
sessions, slower and foolable. Search is one file per session.

The save after a reply is detached. One save runs at a time: a reply's save
steps aside for a running one, which carries its changes; the session-end
save waits its turn. A failed archive puts a banner on the index until it
succeeds.

A page is the conversation as JSON with the renderer inlined: one
self-contained file, the tool doing only the data work (reading transcripts,
repairing mislabelled archives, pairing tool calls with output).

Where a transcript and an archive both exist, the transcript wins. The
archive comes from the same code (`parse.js`), so without the transcript
the page shows the same messages, cuts, title, prompts and search. It keeps
prompts, replies, tool calls with arguments and output, thinking, tokens per
hour and model (cache writes split by kind) and recorded cost, so the
dashboard keeps its numbers. An older archive is rewritten by the next save
while its transcript exists; without one it keeps the last build's tokens
and is shown without the harness's additions (`<system-reminder>`, slash
command tags).

Archives are looked for in the projects root, one folder below, every folder
a session worked in, and every folder in `~/.claude/claude-html.archives`,
kept outside the pages folder so a nested project survives losing the pages:
the hook adds folders it archives into, the build adds found ones and drops
gone ones. Only with no list, or `--force`, does the build walk the root
(three deep, around `node_modules`). `~/.claude/claude-html.own-archives`
holds only folders the hook archived into: with Claude Code's transcripts,
the only ones open and resume links trust.

| Source | Path | Life |
| ------ | ---- | ---- |
| transcript | `~/.claude/projects/<dir>/<id>.jsonl` | until `cleanupPeriodDays` |
| archive | `<project>/.claude/.claude-conversations/*.json` | permanent |

A sub-agent's transcript (`~/.claude/projects/<dir>/<id>/subagents/`) is
part of its parent; its page goes to `sessions/<parent id>/`.

**Some pages say `archive (inferred)`**: early archivers filed tool output as
your words (49 prompts read as 1,125), so roles are inferred from turn
order. **Search does not cover tool output**, nearly half the text and rarely
the match you want.

### Opening a project

`claude-html://open/<session id>` opens without asking. It carries an id,
not a path, so any website's link can reach only a folder in your index,
inside your projects root, and only opens it; starting a server stays yours.
The app holds a copy of its script and is rebuilt whenever
`helper.applescript` is newer. Each open is logged in `.last-open`. A
session run at the projects root opens that folder.

### Resuming

`claude-html://resume/<session id>` takes nothing else from the link:
`claude-html --resume-session` checks it is a full id in the manifest that
can be resumed (not a claude.ai chat), then opens its launcher from
`resume/` (Terminal on macOS, the terminal below on Linux), logged in
`.last-resume`. No dialog: the worst a stranger's link can do is open a
terminal on your conversation. Afterwards the window stays as a shell in
that folder (your `$SHELL`, else `/bin/zsh` on macOS, `bash` or `sh` on
Linux), or at home if the folder is gone. Launchers single-quote the folder,
and the `.desktop` passes it to `bash -c` as an argument, so no folder name,
however odd, runs anything. Older launchers are rewritten by the next build.

### Updating from the index

A new release shows on the index with **copy** (`claude-html --update`) and
**run**, a `claude-html://update` link accepted only exactly so. It opens a
terminal on this clone's `claude-html --update` (through
`~/.claude/.claude-html-update.command` on macOS,
`~/.claude/.claude-html-update.sh` on Linux), which asks "Update claude-html
X -> Y? [y/N]" and does nothing without a yes; a second window within a
minute is refused. The window stays as a shell afterwards. The update
refuses a changed file or a development checkout.

### On Linux

`platform.sh` detects, each time, the distribution (`/etc/os-release`), the
desktop (`XDG_CURRENT_DESKTOP` and older variables), Wayland, X11 or none,
and WSL (`/proc/version`), and gives each job to the best tool installed,
the desktop's own first. Nothing is installed; `--doctor` prints it all.

| | terminal (how it is told to run the launcher) | trash | asks with |
| --- | --- | --- | --- |
| GNOME (Ubuntu, Fedora…) | `ptyxis --new-window --`, `kgx --` or `gnome-terminal --`, newest first | `gio trash` | `zenity` |
| KDE Plasma | `konsole -e` | `kioclient` / `kioclient5 move … trash:/` | `kdialog` |
| XFCE | `xfce4-terminal -x` | `gio trash` | `zenity` if present, else a terminal window |
| MATE, Cinnamon, LXQt, LXDE, Budgie | `mate-terminal -x`, `gnome-terminal --`, `qterminal -e`, `lxterminal -e`, `tilix -e` | whichever is there | whichever is there |
| a bare window manager | `$TERMINAL`, `x-terminal-emulator -e`, then kitty, alacritty, foot, wezterm, `xterm -e` | `trash-put`, else the freedesktop.org Trash spec by hand | `xmessage`, else a terminal window |
| no display (a server, ssh) | none — resume prints the command to type | as above | none — a delete link is refused |
| WSL | `wt.exe wsl.exe -d <distro> --` | as above | — links cannot reach WSL from a Windows browser |

`$TERMINAL`, when set, wins. The Trash spec fallback moves the file into
`~/.local/share/Trash/files` with a `.trashinfo` every desktop restores
from; a file on another filesystem is refused.

`linux/handler.sh` receives the links; `install.sh` registers it with
`xdg-mime` (never from a temp folder, nor with `CLAUDE_HTML_NO_REGISTER`),
`--uninstall` removes it. It accepts exactly
`claude-html://delete|open|resume/<session id>`, `claude-html://update`, or
a fixed-form `limits` or `settings` link, and passes on only the id or form.
An id is acted on only for a transcript Claude Code has or an archive in a
folder claude-html's hook archived into; an archive planted where the build
reads (a cloned repo's) is listed, never opened or resumed. Controls appear
only where the handler is installed (always on macOS).

**How far this is proven.** `tests/linux.test.sh` fakes each environment
(`os-release`, variables, recording stand-ins) and checks detection, each
terminal's exact command, the trash, that a hand-made trash entry restores,
that hostile links are refused and that launchers are valid. It runs on
macOS and Ubuntu CI, but not on a physical Linux desktop.

### The Settings page

`settings.html` is built with the index from `lib/settings.tsv` (each
setting's kind, default and section in
[SETUP.md](SETUP.md#the-settings-page)) and, at build time, each value and
its source, the conf's fingerprint, the engine and system; of your own list,
only its line count. It writes nothing: **apply** is a
`claude-html://settings/…` link, checked by the helper or `handler.sh`, then
by `claude-html --settings-apply` as `--config set` checks, with a window to
confirm, Cancel the default. Each value has one check per language
(`build/settings.js`, and shell code such as `ch_wait_secs`), held to the
same answers by the tests. The page defaults (`CLAUDE_HTML_VIEW_*`) go to
`defaults.js`, loaded by every page, so changing one rebuilds nothing.

### Deleting, and undoing it

A page from disk cannot delete files, so the bin is a `claude-html://` link
for `Claude HTML.app` (macOS) or `handler.sh` (Linux), which lists what
would go and acts only on **Move to Trash** in its own dialog. Linux without
a dialog tool asks in a terminal; with no display, nothing is deleted.

The index reloads when you return from the dialog (only from elsewhere, so
it never loops), checking until the conversation is gone, and gives up
after a minute, as a cancel looks from the page.

To undo, Put Back from the Trash (on Linux, Restore); the removed prompt
history is there too, as `claude-html removed history <id>.jsonl`. A hidden
claude.ai chat is a line in `~/.claude/claude-html.hidden`: delete it to
bring the chat back.

## Secrets

A token or password pasted in, or printed by a tool, becomes `***` in
everything claude-html writes (archives with sub-agents, thinking and tool
input and output, pages, search, index, launchers, `.cache/`), masked as
read and before any cut, so no half secret is left. Settings, your own list
and the rules are in [SETUP.md](SETUP.md#secrets).

**What is caught**: formats that say what they are. Token prefixes
(Anthropic, OpenAI, GitHub, GitLab, AWS, Google, Slack, Stripe, npm, PyPI,
Hugging Face, SendGrid, Twilio, Telegram, Discord), JWTs, private keys,
`Authorization` headers, cookies, values named secret, password, token or
key (capital `.env` names with the word anywhere, `SECRET_KEY_BASE`; `mot de
passe`/`mdp`), such keys in a tool's input at any depth, and passwords in
URLs or given to `curl -u`, `mysql -p` and `sshpass -p`
on a command line. Nothing is guessed from randomness: hashes, ids, SHAs
and pictures are untouched.

**What is not**: a bare secret of no known shape, unless your own list names
it; a named value without a digit or symbol; a number.

**Claude Code's transcript is left exactly as it is**, as resuming needs it,
for as long as Claude Code keeps it. Rotate a secret you pasted: masking is
not revoking.

**Changing the rules or your list** remakes every page and cache at the next
build, and every archive with a transcript at the next save (each records
the md5 of the rules and list). A page that cannot be remade does not keep
the old masking: an error note replaces it, its sub-agents' pages and caches
go, its text leaves the search, and the index lists the error until a build
succeeds. An archive without a transcript is masked on its page but changed
only by `claude-html --redact-archives`, which rewrites those holding
something to mask, atomically. `claude-html --redact-check` changes nothing
and counts per session and archive what each rule finds, never what;
`--doctor` and the build say how many archives are left.

### The guard

Masking acts after the fact; the guard acts before: a prompt or Bash
command holding a secret is stopped before Claude sees it, and you choose.

```text
  you type a prompt              Claude wants to run a command
          │                                   │
          ▼                                   ▼
   [guard: UserPromptSubmit]          [guard: PreToolUse · Bash]
    secret? ask, or stop               secret? ask, or refuse
          │ sent                              │ run
          ▼                                   ▼
  Claude Code writes its own transcript and prompt history
  (~/.claude/projects, history.jsonl — in clear, never touched by us)
          │
          ▼
  save hook (after every reply, at session end)
          │
          ▼
  masking (redact.js) ──▶ archives, pages, search, index, caches (masked)
```

It uses the rules sure of themselves and your own list, and fails open: its
own fault lets things through. Answers, dialog, settings and the words used
when no one can see a dialog are in [SETUP.md](SETUP.md#guard). A blocked
prompt may still be in Claude Code's history and transcript, as for any
prompt a hook blocks.

**What the window is given.** On a Mac, `dialog.js` under `osascript`. Its
arguments hold only the kinds found, the project and the masked first line,
since any process can read arguments. What **Found ▸** and **Command ▸** show
goes through files in a `mktemp -d` folder (700, files 600) that the window
reads and deletes before drawing; the folder goes when the hook exits (a
killed hook's is swept after 30 minutes). On Linux the dialog tool's text
window shows the file behind **Details**. None of it reaches a log, state or
page. The window closes itself at 0:00, or the hook closes it five seconds
later. ⌘C works through a minimal Edit menu.

### Plan limits and the stop rules

How the figures travel:

```text
  Claude Code, after each reply (and at a rate-limit reset, or on refreshInterval)
          │  JSON: rate_limits.five_hour / seven_day (used_percentage, resets_at),
          │        cost.total_cost_usd, session_id
          ▼
  statusline.sh ──▶ the line under the input box (yours first, when wrapped)
          │  only when something changed, or every five minutes
          ▼
  ~/.claude/.claude-html.limits   the latest figures and when they were seen
          │
          ├──▶ guard.sh (UserPromptSubmit): a rule in force and reached ──▶ the stop window
          ├──▶ save-conversation.sh --background (Stop): announce a rule once ──▶ systemMessage
          └──▶ the build (limits.sh ──▶ convert.js): the plan line, Limits & budget
                       │  the budget period's cost (limits.js weekSpend: recorded,
                       │  else the price table's, per session)
                       ▼
               ~/.claude/.claude-html.spend ──▶ the status line, the stop, the warnings
```

All bash and builtins: the status line usually starts one `date`; the
prompt hook with no rule or budget starts nothing. A rule's start is worked
out once a week. Announcements and "Allow until the reset" are kept in
`~/.claude/.claude-html.limits-marks` until they expire. The page writes
nothing: **apply** is a `claude-html://limits/…` link, checked by the helper
or `handler.sh`, then by the command, which asks, Cancel the default.

**Limits to know.** Figures update only while Claude Code runs, so displays
say "as of". Anthropic decides the `rate_limits` and `cost` fields; older
versions lack them. A stop acts on new prompts only, not running tasks or
their sub-agents, and uses the last figures, so a prompt can pass a level by
a few percent. See [SETUP.md](SETUP.md#limits-and-budget).

## Privacy

Everything about your conversations stays on your machine: the pages make
no requests (no fonts, analytics or CDN), and the tool's one request is the
[daily check](SETUP.md#updating) for release tags on GitHub.

The pages hold your conversations in full, less the [secrets](#secrets)
they recognise, so generated files are gitignored and each archive folder
has its own `.gitignore` (`--doctor` names any git would still commit).
Everything claude-html writes is readable by you alone, as Claude Code's
transcripts are, and older releases' looser files are fixed at the next
save. Serving this folder over HTTP needs auth.

## License

MIT. Not affiliated with or endorsed by Anthropic; Claude is their
trademark. This independent tool reads the files Claude Code leaves on your
machine.
