# claude-html, in detail

The front page says what it is; this says how it all works. Every setting
and command is in [SETUP.md](SETUP.md).

## What you get

**An index of every session** — date, project, the title Claude gave the
conversation, and how many prompts you actually typed. Click a row anywhere to
read it, or its title, which is a link a keyboard can reach too; the
conversation links back to the index from its own header. Links to
claude.ai and to your usage sit under the title. Sessions are listed newest
first, and where a project has more than one a **group by project** switch
appears: projects in the order you last worked in them, each with its session
and prompt count, and its name still opens the project. Under the title the
index says when it was last built and how long ago, so a hook that has
stopped firing shows. On a narrow window the least useful columns step aside
rather than push the table off the screen, the time goes before the date
does, and a title takes two lines rather than be cut to a word; on a phone
the table scrolls sideways in its own box.

**Search across every conversation at once.** Your prompts, Claude's replies and
its thinking. Results show a snippet with your terms highlighted and link to the
exact message, which the page scrolls to and highlights. Each conversation
shows its five newest matches, newest first, and says how many more it holds,
with a link to the next of them. Several words must all
appear in the same message; `"quoted text"` matches as a phrase. A **match
case** option appears as you type. If a session's search file is missing, the
results say how many conversations went unsearched rather than leave them out
quietly.

**Readable session pages.** The header reads as the path to the page —
`claude-html / weather-app / 7c21a9b4-…` — where the first crumb is the way
home and the project opens the project, the same as on the index; a sub-agent
page carries one more crumb, the conversation it came from. Both pages are the
same width, so the text sits in the same column wherever you are. Once you
scroll into the conversation the header folds to one line — the path, find and
the prompt arrows — so on a narrow window it no longer takes a third of the
screen; it opens again at the top of the page, or with ▾. Nothing on the page
moves when it does. Tool calls are labelled rather than dumped as JSON,
and every `Edit` becomes a real diff. Commands, diffs and file writes are shown
without a click; what a call returned stays folded. Thinking is kept, folded:
a click opens either, the page remembers it while you read, and find opens
whatever hides the match it lands on. A Markdown table in a reply is drawn as
a table.

**Printing** gives the light palette whatever the screen shows, the whole
header once at the top, and none of the buttons; on the index, none of the
search or the resume column either. What is folded on screen prints folded.

**Two ways to read a long session.** A **Conversation / Everything** switch in
the header: Conversation hides every tool call, its output and Claude's
thinking, leaving the dialogue — often a tenth of the page. Prompts are
numbered and navigable with the arrows in the header or the `j` and `k` keys,
and the counter tells you which question you are currently under. A find bar
searches inside the conversation — press `/` to jump to it, Enter and
Shift-Enter to step between matches, and `«` `»` to go straight to the first
or last of them, which matters when a common word matches six hundred times.
It counts what it found, offers match case, and in Conversation mode skips the
tool output that mode hides. Both navigators are the same control, `« ‹ n / m
› »`: one steps through questions, the other through matches.

**Sub-agents stay with their conversation.** When Claude spawns one, its
transcript is a separate file — often far bigger than the conversation that
asked for it. Each gets its own page, linked from inside the very call that
spawned it, so you read it where it happened instead of hunting for it; the
index says how many a session has rather than listing them as conversations of
their own. A sub-agent page says whose it is and links back.

**What it cost.** Every assistant reply records the tokens it used, so each
session carries its own total — a column on the index, and a line under the
title of the conversation itself: total, output, input, cached, replies, and
output per reply. `usage.html` gathers all of them: a stacked bar per week,
per month, or over all time — by day while your history spans no more than
130 days, by week after that — broken down by model or by project, the
latest period compared with the one just before it, even when that one was
empty. A period with nothing in it is an empty column, so a quiet month
looks like one; a bar is a button that takes you to its row in the table. Cache reads are nearly all of the volume and the cheapest part of it,
which is why output is always named separately.

**Click a name to filter.** A model or a project — in either table or in the
chart's legend — narrows the whole dashboard to it: cards, chart and both
tables. Click it again, or the × on the chip that says what is filtered, to
see everything. A model and a project can be combined; the filter survives
switching period or breakdown, and the browser remembers it.

A reply that appears in more than one transcript — a resumed or forked
session copies the earlier messages — is counted once on the dashboard. Each
session's own total still counts everything in it, so the sessions on the
index can add up to more than the dashboard says.

**What it cost in dollars, where Claude Code says.** Recent versions of Claude
Code write a `cost-state` record into the transcript: the session's running
total per model, in dollars, worked out by Claude Code itself at API list
prices. Where a session has them, the index has a Cost column, the line under
its title says `≈ $498.94`, and the dashboard has a cost card (compared with the
period before, like the others), a Cost column in both tables, and the cost in
each bar's tooltip — following the period, the breakdown and the filter
exactly as the tokens do. Its limits, which the dashboard states with the
count of sessions it covers:

- Most sessions have no recorded cost at all: older ones were never given the
  record, and sub-agents spend on their parent's. Where nothing was recorded
  the calculated cost below stands in, marked `calc`; with no price line for
  any of its models a session still shows `—`, never `$0.00`.
- The record is a running total written when a session exits, with no time of
  its own. Each one becomes what it added since the one before, filed under
  the hour of the last record before it — so a day's work can land on the
  hour it was closed, and a week on the week after. That is why the chart
  stays on tokens.
- A total that falls, or a new start time, is a new counter, counted from
  zero. A record carried into a resumed or forked transcript belongs to the
  other session and is skipped there, so no cost is counted twice.
- Replies from before the first counter began, or since the last one was
  written (a session still open, or one closed without a clean exit), are in
  no record. Such a session's cost is a floor and says `≥` instead of `≈`.
- On a subscription these are what the same use would cost at list prices:
  an equivalent, not a bill.

**What it cost, calculated from a dated price file.** Beside what Claude Code
recorded — never added to it — every session also gets a calculated cost: its
tokens times the price of the time, from `build/prices.tsv` in the repository (one
line per model and price period, copied from Anthropic's pricing page, with
the page and the day it was checked; [SETUP.md](SETUP.md#prices) says how to
add a line). The index and the line under a session's title show it where
nothing was recorded, as `$12.40 calc` (`≈ $12.40 calc` under the title); the
dashboard's cost card shows both, `$412` recorded by Claude Code and `$498`
calculated, and its tables show the recorded cost plain and the calculated one,
marked `calc`, where none was recorded.

- **The price of the time.** A reply is priced by the line whose `from`–`to`
  holds its day, in UTC, both days included. The dashboard's third toggle,
  *cost at · the price of the time / today's prices*, prices every hour at the
  current line instead, to show what the same work would cost now; the browser
  remembers the choice.
- **Five prices.** Input, output, cache reads, and cache writes in two kinds:
  5-minute and 1-hour writes cost differently (1.25× and 2× the input price),
  so the two are stored apart, per hour and model, from each reply's
  `cache_creation` record. A write whose kind no record says — an archive
  written before 3.3.0 whose transcript is gone, or a transcript older than
  that record — is priced as a 5-minute write, and the dashboard says how many
  tokens that is ("split unknown").
- **Prices of their own.** A reply in fast mode (`usage.speed` is `fast`) is
  filed under its model with `/fast` (`opus-5-5/fast`), and a Claude Haiku 5.5
  request whose prompt — input, cache reads and cache writes — is over 100,000
  tokens under `haiku-5-5/over-100k`, because the pricing page prices both
  higher, per request. They show as models of their own on the dashboard.
  Nothing else is applied: no batch discount, no US-only 1.1×, no cloud
  platform prices — standard list prices only.
- **Unknown models are not priced.** A model id matches its own line, or, for
  a dated id such as `claude-haiku-4-5-20251001`, the line without the date.
  Anything else is "not priced": left out of the calculated cost, never
  guessed. A session with tokens of such a model says `≥`, and the dashboard
  lists those models and how many tokens they had.
- **Price history.** The dashboard's last section lists, per model you used,
  the current price and the periods before it, what changed (old → new, ± %),
  and how many of your tokens and sessions fell in each period, with the day
  the file was last checked and its sources.
- **A stale file gives quietly wrong numbers.** The file changes only when
  someone adds a line; that is why each line says when it was checked, and the
  dashboard shows the newest of those dates.

**Long conversations open quickly.** A session of fifteen thousand messages is
a hundred thousand DOM nodes, and putting all of them on the page is what made
it lag. So a conversation of more than 400 rows is built only near your
screen: every other row is an empty block of about its own height, built as
you scroll towards it and taken down again once it is far away. On a 16 MB
session the page now stops working in about half a second where it took about
two, and holds about 900 DOM nodes instead of 94,000. Find, the prompt arrows
and `#m…` links work from the conversation itself, so they reach every
message; printing builds the whole page first. The browser's own find cannot
see past what is built, so on these pages ⌘F (Ctrl+F elsewhere) goes to the
page's find instead; pressed again in that field, it opens the browser's.

**A way back in.** Every row of the index, and every page, has a **resume**
button: click it and the conversation reopens in a terminal, in the right
folder. **copy** beside it puts the `cd … && claude --resume …` command on the
clipboard instead. And `resume/` holds a launcher per conversation to
double-click — a `.command` on macOS, a `.desktop` file and a `.sh` on Linux.

**Open the project.** Each project name on the index is a link to the project
itself, and what that means is worked out when you click: the server it is
running, if one is, otherwise its `index.html`, otherwise its folder in Finder.
Nothing is guessed in advance — a port does not exist until its server starts,
and a vite project never names one.

**Delete a conversation.** Each row of the index has a bin. It moves the
conversation and everything that belongs to it to the Trash — Claude Code's
transcript and edit snapshots, the archives, the page, and its prompts in your
up-arrow history — so Finder's Put Back restores it. It looks for archives
wherever the build does, so a nested project's archive goes too. You see exactly what will
go, and confirm, in a dialog first. A conversation still open in Claude
Code is refused. A claude.ai chat is hidden rather than deleted, since its real
copy lives on claude.ai.

**Your claude.ai chats too.** Drop a `conversations.json` export in
`~/Downloads`, in the projects root, or one folder inside either, and those
conversations are rendered and searched alongside the Claude Code ones. If
yours lives anywhere else, `CLAUDE_HTML_EXPORT` names it — and then that file
is the only one read (see [SETUP.md](SETUP.md#claudeai-exports)).

**Nothing to run.** Each session is saved after every reply and again when it
ends, and the pages rebuild with it — open a conversation's page while you are
still in it and it is at most one reply behind. The save after a reply runs in
the background, so you never wait on it. Claude Code deletes raw transcripts
after 30 days; the archives are permanent.

## Install

Clone it into the folder where you want the pages, then run it. Any folder,
anywhere:

```bash
git clone <this-repo> /path/where/you/want/the/pages
cd /path/where/you/want/the/pages
./install.sh
```

It asks nothing. The folder you cloned into becomes the pages directory —
`index.html` and the rest land right there — and its parent becomes the
projects root, the tree whose sessions get archived. You choose both by
choosing where to clone.

Point them elsewhere if that is not what you want:

```bash
./install.sh --out ~/somewhere/else --root ~/code
```

Running it again is safe. `~/.claude/claude-html.conf` is yours once it is
written: a later run keeps every line of it, edits and comments included, and
adds only a setting that is missing. `--out` and `--root` change their own line
and nothing else, so a bare `./install.sh` later does not undo them.
`./install.sh --uninstall` removes the command, the helper app and the hooks,
leaving your pages, archives and conf alone.

### Uninstall

```bash
cd ~/claude-html && ./install.sh --uninstall
```

That removes the `claude-html` command (only one that leads to this clone),
the helper app (on Linux, the link handler), the hooks it added — only its
own; the rest of your `settings.json` is untouched — and the state it kept
for itself in `~/.claude` (the update check's and the automatic update's log, the guard's pending answers,
the update launchers), and keeps what is yours: the pages, the
archives, `~/.claude/claude-html.conf` and your `cleanupPeriodDays`. Nothing
saves from then on; what was saved stays readable.

To erase every trace as well:

- delete the clone folder — the tool, its pages and its `.cache/` go with it
- delete `~/.claude/claude-html.conf`, `~/.claude/claude-html.archives` and
  `~/.claude/claude-html.own-archives` (and `~/.claude/claude-html.hidden`, if you hid claude.ai chats, and
  `~/.claude/claude-html.redact`, your own list of secrets and safe values)
- the archives live in each project, at any depth, in `.claude/.claude-conversations/`;
  `find ~/Sites -type d -path '*/.claude/.claude-conversations'` lists them
  (use your own projects root), and deleting them loses the conversations for good
- `cleanupPeriodDays` in `~/.claude/settings.json` stays at 3650 if the
  installer set it; put it back to taste

### What it changes

| Path | Change |
| ---- | ------ |
| `~/.claude/claude-html.conf` | the two directories, and the week reset offered commented out; written once, then only added to |
| `~/.claude/settings.json` | hooks that save after every reply (`Stop`) and at the end (`SessionEnd`, `PreCompact`); the guard's; `statusLine`, claude-html's or claude-html's around yours; `cleanupPeriodDays` set to 3650 **only if you have not set it** |
| `~/.local/bin/claude-html` | a symlink, so you can type `claude-html` |
| `Claude HTML.app` | macOS: built at the top of the clone, beside `claude-html`; receives the index's delete, open and resume links |
| `~/.local/share/applications/claude-html-handler.desktop` | Linux, where there is a desktop: claims `claude-html://` links for `linux/handler.sh`, registered with `xdg-mime` |

**Hooks you already have are kept.** New ones are appended beside whatever is
there; existing entries are read, never rewritten. Another tool's `SessionEnd`
hook keeps working exactly as before, and uninstalling removes only the ones
this adds. The installer reports how many of yours it left alone.

**A `cleanupPeriodDays` you already set is kept** — the installer says what
yours is and moves on. It raises the limit only for people who never chose one,
because raw transcripts carry more than the archives do — sub-agent
conversations, a tool's output past the 6,000 characters a page shows, and
its input past 20,000 — and are deleted after 30 days by default.

Session archives are written to `<project>/.claude/.claude-conversations/`,
beside the code they belong to, in whichever folder under the projects root the
session ran, however deep.

The pages folder also holds `.cache/`, what the last save made of each
transcript, so the next one reads only what was added; see
[How it works](#how-it-works). It can be deleted at any time.

**Nothing else in the pages folder is touched.** Files are only ever removed if
they are named for a session that no longer exists — a page, a launcher or a
search fragment carrying a session id. Your own files in that folder are left
alone, so pointing `--out` at a directory you already keep things in is safe.
The one exception is `index.html`, which is the index and gets replaced.

### Requirements

**On macOS: nothing.** What it runs is the system's own: `bash`, `osascript`
(which runs the JavaScript), `open`, `curl`, `lsof`, `ps`, and the standard
tools every Mac has (`find`, `sed`, `awk`, `grep`, `stat`, `mv`…), and — to
build the helper app — `osacompile`, `PlistBuddy`, `codesign`, `lsregister`.
`git` only to update itself, and never Apple's stand-in for it when the
developer tools are not installed. No Python, no Node, no Homebrew, nothing
to `pip install`. Intel and Apple silicon alike.

**node, when it is already there.** If a Mac has a working node (14.14 or
later) — and many running Claude Code do — the transcripts are read and the
pages built with it, because it runs the same files three to four times faster
than `osascript`. It is looked for on `PATH` and in the folders it is usually
installed in (`/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin`, and the
versions Volta, asdf, mise, fnm and nvm installed), since a hook can run with a
thinner `PATH` than your terminal. A version manager's shim is never run: it
picks a version by the folder it runs in, and Volta and mise download one that
is missing. Each node is tried from `/`, not from your project, and given five
seconds to answer. It is never installed and never required: without it, `osascript` does the
same work. Deleting, opening and resuming stay on `osascript` either way, as
they need the Finder and the helper app. `claude-html --doctor` says which
engine builds the pages and why, and `CLAUDE_HTML_ENGINE` chooses.

**On Linux: node**, which runs the same JavaScript files byte for byte. A
machine running Claude Code need not have it: Claude Code's native installer
brings its own runtime and no `node` command, so install node 14.14 or later
from the distribution. Without a working one nothing is built, and
`install.sh`, `claude-html --doctor` and the error a save records say why. The pages, the index, the
search, the dashboard, the archives and the save-after-every-reply hooks all
work exactly as on a Mac; `tests/backend.test.sh` proves the two engines
produce identical output. Everything else — the terminal a resume opens, what
opens a project, the trash, the confirmation dialog — is done with tools the
machine already has, chosen per machine; see [On Linux](#on-linux). Windows
is not supported, except through WSL.

If you want to work on the project rather than use it, the tests run under
Node on either platform: `bash tests/run-all.sh`.

Note that on macOS `git` comes with Apple's developer tools rather than the
system. claude-html uses git only to update itself (`claude-html --update`
and the daily check for a new release); without the developer tools it
never runs Apple's stand-in for git, which would offer to install them. A
copy downloaded as a zip works the same, but cannot update itself: it is
re-installed from a clone instead.

## Commands

Every `claude-html` and `./install.sh` command and flag is listed in
[SETUP.md](SETUP.md#commands). The test suites:

```bash
bash tests/run-all.sh           # every suite below, one verdict — what CI runs
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
```

delete, open and helper need macOS and say so when skipped elsewhere; linux
runs everywhere, against desktops it fakes. On a Mac the suites build with
`osascript` even where node is installed, so that engine stays tested; set
`CLAUDE_HTML_FORCE_NODE=1` to run everything through node instead.

Sessions whose source has not changed are skipped, so a rebuild after a day's
work takes a fraction of a second. `claude-html --force` rebuilds every session
from the start, reading every transcript whole.

### Configuration

Moved to [SETUP.md](SETUP.md), with every variable, its default and an example.

## How it works

**Where everything is.** The clone is laid out by what each file does:

| Where | What |
| ----- | ---- |
| `claude-html`, `install.sh` | the command and the installer |
| `save-conversation.sh`, `guard.sh`, `statusline.sh` | what `settings.json` runs: the save, the guard and the status line, called by their full path, so they stay at the top |
| `lib/` | the shell the others source: the conf (`conf.sh`), what the machine has (`platform.sh`), the lock, the plan limits, the settings (`settings.sh`, and `settings.tsv`, which describes every one of them), the update (`update.sh`) and the release numbers (`version.sh`) |
| `build/` | the pages: `convert.js` builds them, with `parse.js`, `redact.js`, `prices.js` and its `prices.tsv`, `limits.js`, and `settings.js`, the one check of a setting's value in JavaScript |
| `actions/` | what the command and the installer run besides: the guard's judge, open, resume, delete, and the edit of `settings.json` |
| `mac/` | the helper app's source and build, and the windows (`dialog.js`) |
| `linux/` | the link handler |
| `viewer/` | what the pages carry: their HTML, CSS and JavaScript |
| `tests/` | the suites (`bash tests/run-all.sh`), their data in `tests/fixtures/` |
| `docs/` | this file and [SETUP.md](SETUP.md); the pictures in `docs/img/` |

The JavaScript is the same files under `osascript` and `node`, and they
produce the same bytes under either. The data work — archiving and building
pages — goes to node when a working one is installed, being the faster, and
to `osascript` when it is not; `lib/platform.sh` decides, once, for the hook, the
command and the installer alike. A hook runs after every reply and when a session ends. It writes a permanent
archive beside the project, then rebuilds whatever changed — normally a third
of a second, because sessions whose pages are current are never read again.

**A save reads only what was added.** A transcript only ever grows, and a
long session's reaches hundreds of megabytes, with a gigabyte of sub-agents
beside it; reading all of it after every reply made a save take most of a
minute. So the archiver and the build each keep, in the pages folder's
`.cache/`, how far they read — whole lines only — and what those lines leave
for the ones after: the messages and search rows already encoded, the replies
counted so far (a reply is several records under one id, and can fall either
side of where the last save stopped), the cost counter's last snapshot, the
first prompt. The next save reads on from that offset. Each sub-agent is kept
under a key made of its transcript's size and time, its `.meta.json` and what
its page shows of the parent, and is read again only when one of them changes.
On a 166 MB session with 322 sub-agents, a save after one more reply went
from 57 seconds to under 3 with `osascript`, and from 17 to under 2 with node.

The result is the same bytes a save from nothing would write — pages, search,
manifest, dashboard and archive — and `tests/incremental.test.js` checks
exactly that, cutting a transcript at hundreds of points and comparing every
file. The cache is used only while it provably fits: its key holds the
program's own source and the usage format, so any update starts afresh; an
md5 beside each file must match; the transcript must be at least as long as
where it stopped, with the same bytes at its start, its middle and just before
that point. Anything else, and the save reads from the beginning, as it always
did. Those samples are taken the moment the bytes are read, and checked again
before the cache is written: a transcript cut short or replaced while a save
was reading it leaves no cache behind. That check is three samples, cheap by design: transcripts are only ever
appended to, and an edit confined to the bytes between the samples would not
be seen — `claude-html --force` rebuilds from scratch. Saves take turns
through a lock, and `claude-html` waits for its turn too; a build that cannot
have it, and the installer's one build, do without the cache. **Deleting `.cache/` is always safe**: the next
save reads everything once and writes it again. A conversation that is
deleted takes its cache with it at the next build, since the cache holds its text.

A session counts as unchanged only when its transcript is exactly the size it
was last time. Transcripts only ever grow, so size catches any new message — a
timestamp does not, when a reply lands in the same second as the save that
just read the file, and that reply would never reach its page or its archive.

Each save knows exactly which transcript is its own, because Claude Code names
it in a note to the hook. Run by hand there is no note, so the save searches
this project's sessions instead — slower, and it can be fooled by a transcript
that merely mentions the folder's path. Search is one small file per session,
so a save rewrites only the session that changed.

The save after a reply is detached, so the hook returns at once. Only one save
runs at a time: if another is still going, a reply's save steps aside, since
the next one will carry its changes — but the save at session end waits for
its turn, because it is the one that must not be lost. If archiving a session
fails, the index says so in a banner until it succeeds.

A session page is the conversation as JSON, with the renderer inlined beside
it: the page draws itself when you open it. That keeps each page a single file
that works on its own, and means the tool only has to do the data work —
reading transcripts, repairing archives that mislabelled their roles, matching
tool calls to their output.

Sessions come from two places. Where both exist the transcript wins, since it
carries more. The archive is read from the transcript by the same code the
page is (`parse.js`), so once the transcript is gone the page made from the
archive shows what it showed before: the same messages, cut where the page
cuts them, the same title, prompts and search. An archive keeps your prompts, the replies, each tool call with
its arguments, what it returned, the thinking, the tokens each reply used,
by hour and model (cache writes split into 5-minute and 1-hour), and the cost
where Claude Code recorded one — so once the
transcript is gone the page, its search and the dashboard keep their numbers.
An archive written by an older version is
rewritten in the new form by the next save of its session while its
transcript is still there; one whose transcript has already gone keeps the
token counts the last build had, and is shown without what the harness put
into a prompt (`<system-reminder>`, the tags of a slash command).

Archives are looked for in the projects root, one folder below it, in every
folder a session is known to have worked in, and in every folder listed in
`~/.claude/claude-html.archives`. That list is kept outside the pages folder,
so losing the pages or the manifest does not lose a nested project whose
transcripts have expired: the hook adds a folder when it archives there, the
build adds any it finds and drops one that has gone. Only when the list is
missing, or a rebuild is forced, does the build walk the root for archives,
three folders deep and around `node_modules` and the like — seconds, so never
on an ordinary save. The hook also keeps `~/.claude/claude-html.own-archives`,
the folders it archived into itself and nothing the build only found: the
index's open and resume links trust those, and Claude Code's own transcripts.

| Source | Path | Life |
| ------ | ---- | ---- |
| transcript | `~/.claude/projects/<dir>/<id>.jsonl` | until `cleanupPeriodDays` |
| archive | `<project>/.claude/.claude-conversations/*.json` | permanent |

A sub-agent's transcript sits beside its parent's, in
`~/.claude/projects/<dir>/<id>/subagents/`, and is read as part of it: it is
never a session in its own right, in the index or in the archives. Its page is
written to `sessions/<parent id>/`, which is also why pages one folder deeper
carry a longer link home.

Two things are worth knowing, because they show up on the pages:

**Some pages say `archive (inferred)`.** Early versions of the archiver filed
tool output as something the user said, which made a 49-prompt session read as
1,125. Those roles are worked out again from turn order, and the label says so
rather than implying they were recorded.

**Search does not cover tool output.** It is nearly half the text, and a match
inside a command dump is rarely the one you wanted.

### Opening a project

The link is `claude-html://open/<session id>`, handled by the same helper, and
it opens without asking — that is the point of it. It carries a session id
rather than a path, so a link from any website can only ever reach a folder
already in your index, inside your projects root, and it only ever opens:
it never runs anything. Starting a dev server is still yours to do.

The app holds a copy of its script inside it, so the app is rebuilt whenever
`helper.applescript` is newer than it — by `claude-html`, and by the hook after
a reply. Otherwise editing the source would change nothing and the links would
quietly do nothing. Each open is recorded in `.last-open` beside the index,
since it happens inside another app where a failure would be invisible.

A session run at the projects root itself opens that folder. It deliberately
does not adopt whichever project happens to be serving underneath it.

### Resuming

The button is a `claude-html://resume/<session id>` link. It runs nothing
taken from the link: `claude-html --resume-session` checks the id is a full
session id, that the manifest lists it, and that it can be resumed (a
claude.ai chat cannot), then opens the launcher `convert.js` wrote for it in
`resume/` — on macOS with `open`, which hands a `.command` to Terminal, on
Linux in the terminal described below. There is no dialog: the worst a
stranger's link can do is open a terminal on a conversation of yours. What it
did is noted in `.last-resume`, beside `.last-open`. When the command ends,
the window stays, as an ordinary shell in that folder: your `$SHELL` (else
`/bin/zsh` on macOS, `bash` then `sh` on Linux), a login shell on macOS as
Terminal's are and an interactive one on Linux as a terminal's are; if the
folder has gone, it says so and the shell opens at home. A launcher written
by an earlier version is written again by the next build, once.

The launchers quote the folder in single quotes, and the `.desktop` file
passes it to `bash -c` as an argument rather than inside the script, so a
folder named with spaces, quotes, `$`, backticks or even a line break is
reached exactly and nothing in its name ever runs.

### Updating from the index

When a newer release is out, the index says so in one line with two
buttons: **copy** puts `claude-html --update` on the clipboard, **run** is a
`claude-html://update` link. That link names nothing — it is exactly that
string or it is refused — and opens a terminal on this clone's own
`claude-html --update`: on macOS Terminal, through a launcher in
`~/.claude/.claude-html-update.command`, on Linux the terminal described
below, through `~/.claude/.claude-html-update.sh`. The window first asks "Update claude-html X -> Y? [y/N]" and does nothing
without a yes, since any web page can open the link; a second window within
a minute is refused. Either way, when the update ends the window stays, as
an ordinary shell, with what it said above the prompt. The update itself
refuses what it should (a changed file, a development checkout).

### On Linux

`platform.sh` works out, each time, what the machine is and what it has:
the distribution and version from `/etc/os-release` (`ID`, `ID_LIKE`,
`VERSION_ID`), the desktop from `XDG_CURRENT_DESKTOP` and its older
cousins, Wayland, X11 or no display at all, and WSL from `/proc/version`.
Then each job goes to the best tool already installed — the desktop's own
first. Nothing is installed. `claude-html --doctor` prints all of it.

| | terminal (how it is told to run the launcher) | trash | asks with |
| --- | --- | --- | --- |
| GNOME (Ubuntu, Fedora…) | `ptyxis --new-window --`, `kgx --` or `gnome-terminal --`, newest first | `gio trash` | `zenity` |
| KDE Plasma | `konsole -e` | `kioclient` / `kioclient5 move … trash:/` | `kdialog` |
| XFCE | `xfce4-terminal -x` | `gio trash` | `zenity` if present, else a terminal window |
| MATE, Cinnamon, LXQt, LXDE, Budgie | `mate-terminal -x`, `gnome-terminal --`, `qterminal -e`, `lxterminal -e`, `tilix -e` | whichever is there | whichever is there |
| a bare window manager | `$TERMINAL`, `x-terminal-emulator -e`, then kitty, alacritty, foot, wezterm, `xterm -e` | `trash-put`, else the freedesktop.org Trash spec by hand | `xmessage`, else a terminal window |
| no display (a server, ssh) | none — resume prints the command to type | as above | none — a delete link is refused |
| WSL | `wt.exe wsl.exe -d <distro> --` | as above | — links cannot reach WSL from a Windows browser |

`$TERMINAL`, when set, wins over all of these. The Trash spec fallback moves
the file into `~/.local/share/Trash/files` under a free name and writes the
`.trashinfo` (percent-encoded `Path=`, `DeletionDate=`) that every desktop's
restore reads; a file on another filesystem is refused rather than copied.

Links reach the machine through `linux/handler.sh`, which `install.sh` registers
with `xdg-mime` as the handler for `x-scheme-handler/claude-html` (never from
a temporary folder, and not when `CLAUDE_HTML_NO_REGISTER` is set);
`--uninstall` takes it out again. The handler accepts exactly
`claude-html://delete|open|resume/<session id>`, or `claude-html://update`
exactly, or a `limits` or `settings` link in its fixed form, and nothing
else, and passes only the id or the form on. An id is acted on only for a
conversation Claude Code itself has the transcript of, or an archive in a
folder claude-html's own hook archived into: an archive anyone put in a
folder the build reads, a cloned repo's, is listed but never opened or
resumed, since any web page can open these links. The index offers the
bin, the project links, resume and an update's run only
where that handler is installed — on macOS always — so no page shows a control
that does nothing.

**How far this is proven.** `tests/linux.test.sh` builds each environment
above from a fake `os-release`, the session's variables and stand-in programs
that record how they were called, and checks what is detected, the exact
command each terminal is given, which trash is used, that the hand-written
trash entry restores, that hostile links are refused, and that the launchers
are valid desktop files that land in an awkward folder. It runs on macOS and
on Ubuntu in CI. It has not been clicked through on a physical Linux desktop,
so a desktop that behaves differently from its documentation would only show
up there.

### The Settings page

`settings.html` is built with the index, from `lib/settings.tsv` — every
setting, its kind, default and section in [SETUP.md](SETUP.md#the-settings-page) —
and what the shell knows as of the build: each value and where it comes
from, the conf's fingerprint, the engine, the system. Of your own list of
secrets it carries how many lines, never one of them. It writes nothing:
**apply** is a `claude-html://settings/…` link, which the helper (macOS) or
`handler.sh` (Linux) checks for its characters and length before
`claude-html --settings-apply` reads it whole, checks every value as
`--config set` does, and asks in the limits' window, Cancel the default.
A value is checked once per language: `build/settings.js` for the page,
the setting's own shell code (`ch_wait_secs`, the limits' parsers) for the
command, and the tests hold the two to the same answers.

The page defaults (`CLAUDE_HTML_VIEW_*`) are written to `defaults.js`
beside the index, which every page loads in its head before it draws, so
changing one rebuilds no conversation's page.

### Deleting, and undoing it

A page opened from disk is not allowed to delete files, so the bin is a
`claude-html://` link, which macOS hands to `Claude HTML.app` and Linux to
`handler.sh`. Either lists what would go and does nothing until you click
**Move to Trash** in its own dialog: any website can ask it to open, but only
that click makes it act. On Linux without a dialog tool the question is asked
in a terminal window instead, and with no display at all a link deletes
nothing.

The index reloads itself when you come back from that dialog, so the
conversation disappears from the list without you doing anything. It only
counts a return from somewhere else — otherwise a page reload would look like
one and it would refresh itself in circles — and it keeps checking until the
conversation is gone, because the browser's own "open this app?" prompt can
hand focus back before the helper has started. It gives up after a few tries or
a minute, which is what cancelling looks like from the page's side.

To undo, use Put Back on the files in the Trash (on Linux, Restore in the
file manager's trash); the prompts removed from your
up-arrow history are there too, as a file named
`claude-html removed history <id>.jsonl`. A hidden claude.ai chat is listed in
`~/.claude/claude-html.hidden` — delete its line to bring it back.

## Secrets

A token or a password pasted into a conversation, or printed by a tool, is
written as `***` in everything claude-html writes: the archives (sub-agents,
thinking, tool inputs and outputs included), the pages, the search, the
index, the launchers and `.cache/`. Each text is masked as it is read from
the transcript, before it is cut to length, so half a secret is never left
at a cut. The settings, your own list and the rules by name are in
[SETUP.md](SETUP.md#secrets).

**What is caught**: formats that say what they are — known token prefixes
(Anthropic, OpenAI, GitHub, GitLab, AWS, Google, Slack, Stripe, npm, PyPI,
Hugging Face, SendGrid, Twilio, Telegram, Discord), JWTs, private key
blocks, `Authorization` headers and cookies, passwords in URLs, in
`curl -u`, `mysql -p` and `sshpass -p`, values whose name says secret,
password, token or key — `.env` names in capitals with the word anywhere
(`SECRET_KEY_BASE`), and `mot de passe`/`mdp` — and, in a tool's input,
a value under such a key (`{"api_key": …}`) at any depth. Hashes, ids, commit
SHAs and pictures are never touched: nothing is guessed from how random a
string looks.

**What is not**: a secret of no known shape, pasted on its own with no name
before it, is kept as it is unless your own list names it. A value after a
secret-sounding name or key is masked only if it has a digit or a symbol in
it, and a number under such a key is kept.

**Claude Code's transcript is left exactly as it is**, in
`~/.claude/projects`, because resuming a conversation needs it. It keeps
the secret for as long as Claude Code keeps the transcript — and the
installer set `cleanupPeriodDays` to 3650, unless you had set it. Rotate a
secret you pasted; masking the copies is not revoking it.

**Changing the rules or your list** makes every page and cache again on the
next build, and every archive whose transcript is still there on the next
save: each records the md5 of the rules and of the list it was made with,
and anything made with others is made again. An archive whose transcript
has gone is masked on its page, but the archive itself is changed only by
`claude-html --redact-archives`, which rewrites each one holding something
to mask, whole and atomically, and leaves the rest alone.
`claude-html --redact-check` reads everything, changes nothing, and says
per session and archive how many it found under each rule — never what.
`--doctor` and the build say how many archives are left.

### The guard

Masking acts on what claude-html writes, after the fact; the guard acts
before: a prompt or a Bash command that holds a secret is stopped before it
reaches Claude, and you choose what happens to it. Where it sits:

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

It uses only the rules that are sure of themselves, and your own list, and
fails open: a fault of its own lets the prompt or command through
quietly. The answers, the dialog, the words that stand in for it when
nobody can see a dialog, and the settings are in
[SETUP.md](SETUP.md#guard). A blocked prompt may still be in Claude Code's
prompt history and its transcript: its documentation says so of every
prompt a hook blocks.

**What the window is given.** On a Mac the window is `dialog.js`, run by
`osascript`. Its arguments carry the kinds found, the project and the
command's first line, masked — nothing secret, since any local process can
read another's arguments. What its **Found ▸** and **Command ▸** boxes show
(each match in its context, the whole command) is written by `guard.js` to
files in a folder `guard.sh` makes with `mktemp -d` (mode 700, files 600);
the window reads each and deletes it before it draws anything, and the
folder is removed when the hook exits, however it exits (one left by a hook
killed outright is swept after 30 minutes). On Linux the same file is
opened by the dialog tool's own text window behind **Details**. Nothing of
it reaches a log, the state or a page. The window counts down with a timer
in its own run loop and closes itself at 0:00; the hook closes it from
outside five seconds later should it not have. ⌘C works because the window
installs a minimal main menu (Edit: Copy, Select All), without which an
application started by `osascript` has nowhere to send it.

### Plan limits and the stop rules

How the figures travel, from Claude Code to the pages and the stop:

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

Everything on the way is bash and its builtins: the status line starts one
`date` in the common case, and the prompt hook with no rule and no budget
starts nothing. When a rule starts in a week is worked out once per week
and kept in the state file. What was announced, and an "Allow until the
reset", are in `~/.claude/.claude-html.limits-marks`, each ending at the
time it means nothing any more. The page writes nothing: its **apply** is a
`claude-html://limits/…` link, which the helper (macOS) or `handler.sh`
(Linux) checks against a fixed form before the command checks it again
and asks in a window, Cancel the default.

**Limits to know.** The figures update only while Claude Code runs; with no
session open they stand still, and every display says "as of". Anthropic
decides the `rate_limits` and `cost` fields: older Claude Code versions do
not send them, and they can change or go. A stop acts on new prompts only:
a task already running, and the sub-agents it started, carry on. A rule
uses the week as last seen, so a prompt sent before the next refresh can
pass a level by a few percent. The settings and the windows are in
[SETUP.md](SETUP.md#limits-and-budget).

## Privacy

Everything about your conversations stays on your machine. The pages make
no network requests — no fonts, no analytics, no CDN. The one request the
tool makes is the [daily check](SETUP.md#updating) for a new release: the
list of release tags, from GitHub, and nothing sent but the request itself.

They do contain your conversations in full, including anything you pasted in,
except the [secrets](#secrets) they recognise.
The generated files are gitignored for that reason, and each archive folder
holds a `.gitignore` of its own, so a project's repository never takes a
conversation into a commit (`--doctor` names any archive folder git would
still commit). Everything claude-html writes — pages, search, cache,
archives — is readable by you alone, as Claude Code keeps its own
transcripts; what an earlier release left readable by others is made so at
the next save or build. If you serve this directory over HTTP,
put it behind auth.

## License

MIT. Not affiliated with or endorsed by Anthropic; Claude is their trademark,
and this is an independent tool that reads the files Claude Code leaves on
your own machine.
