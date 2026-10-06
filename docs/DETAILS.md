# claude-html, in detail

The front page says what it is; this says how it all works.

## What you get

**An index of every session** — date, project, the title Claude gave the
conversation, and how many prompts you actually typed. Click a row anywhere to
read it; the conversation links back to the index from its own header. Links to
claude.ai and to your usage sit under the title. Sessions are listed newest
first, and where a project has more than one a **group by project** switch
appears: projects in the order you last worked in them, each with its session
and prompt count, and its name still opens the project.

**Search across every conversation at once.** Your prompts, Claude's replies and
its thinking. Results show a snippet with your terms highlighted and link to the
exact message, which the page scrolls to and highlights. Several words must all
appear in the same message; `"quoted text"` matches as a phrase. A **match
case** option appears as you type.

**Readable session pages.** The header reads as the path to the page —
`claude-html / weather-app / 7c21a9b4-…` — where the first crumb is the way
home and the project opens the project, the same as on the index; a sub-agent
page carries one more crumb, the conversation it came from. Both pages are the
same width, so the text sits in the same column wherever you are. Tool calls are labelled rather than dumped as JSON,
and every `Edit` becomes a real diff. Commands, diffs and file writes are shown
without a click; what a call returned stays folded. Thinking is kept, collapsed.

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

**A way back in.** Every page carries its `claude --resume` command, and
`resume/` holds a launcher per session — double-click it and the session reopens
in Terminal, in the right directory.

**Open the project.** Each project name on the index is a link to the project
itself, and what that means is worked out when you click: the server it is
running, if one is, otherwise its `index.html`, otherwise its folder in Finder.
Nothing is guessed in advance — a port does not exist until its server starts,
and a vite project never names one.

**Delete a conversation.** Each row of the index has a bin. It moves the
conversation and everything that belongs to it to the Trash — Claude Code's
transcript and edit snapshots, the archives, the page, and its prompts in your
up-arrow history — so Finder's Put Back restores it. You see exactly what will
go, and confirm, in a macOS dialog first. A conversation still open in Claude
Code is refused. A claude.ai chat is hidden rather than deleted, since its real
copy lives on claude.ai.

**Your claude.ai chats too.** Drop a `conversations.json` export in
`~/Downloads` or beside your projects and those conversations are rendered and
searched alongside the Claude Code ones. `CLAUDE_HTML_EXPORT` names one
explicitly.

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

Running it again is safe: it adds only what is missing, and never overwrites a
setting you chose. `./install.sh --uninstall` removes the command and the hooks,
leaving your pages and archives alone.

### What it changes

| Path | Change |
| ---- | ------ |
| `~/.claude/claude-html.conf` | the two directories |
| `~/.claude/settings.json` | hooks that save after every reply (`Stop`) and at the end (`SessionEnd`, `PreCompact`); `cleanupPeriodDays` set to 3650 **only if you have not set it** |
| `~/.local/bin/claude-html` | a symlink, so you can type `claude-html` |
| `Claude HTML.app` | built beside the scripts; receives the index's delete links |

**Hooks you already have are kept.** New ones are appended beside whatever is
there; existing entries are read, never rewritten. Another tool's `SessionEnd`
hook keeps working exactly as before, and uninstalling removes only the ones
this adds. The installer reports how many of yours it left alone.

**A `cleanupPeriodDays` you already set is kept** — the installer says what
yours is and moves on. It raises the limit only for people who never chose one,
because raw transcripts carry more than the archives do (thinking, sub-agent
turns) and are deleted after 30 days by default.

Session archives are written to `<project>/.claude/.claude-conversations/`,
beside the code they belong to.

**Nothing else in the pages folder is touched.** Files are only ever removed if
they are named for a session that no longer exists — a page, a launcher or a
search fragment carrying a session id. Your own files in that folder are left
alone, so pointing `--out` at a directory you already keep things in is safe.
The one exception is `index.html`, which is the index and gets replaced.

### Requirements

**On macOS: nothing.** Every binary it runs is Apple-signed system software,
twelve in all: `bash`, `osascript` (which runs the JavaScript), `open`,
`curl`, `lsof`, `date`, `mv`, `kill`, and — to build the helper app —
`osacompile`, `PlistBuddy`, `codesign`, `lsregister`. No Python, no Node, no
Homebrew, nothing to `pip install`. Intel and Apple silicon alike.

**On Linux: node**, which runs the same JavaScript files byte for byte — and a
machine running Claude Code has node already. The pages, the index, the
search, the archives and the save-after-every-reply hooks all work exactly as
on a Mac; `tests/backend.test.sh` proves the two engines produce identical
output. What stays macOS-only is the garnish around the pages: the Trash-aware
delete button, the click-to-open-project links and the double-click launchers,
all of which lean on macOS itself. Windows is not supported.

If you want to work on the project rather than use it, the tests run under
Node on either platform: `bash tests/run-all.sh`.

Note that on macOS `git` comes with Apple's developer tools rather than the
system. If `git clone` offers to install them and you would rather not,
download the repository as a zip instead — the tool does not use git.

## Commands

Sessions appear on their own as they end. These are for when you want to look
now, or rebuild after changing something:

```bash
claude-html                     # build what changed, open the index
claude-html --force             # rebuild every session
claude-html <session-id>        # rebuild one session
claude-html --delete <full id>  # the index's bin, from the terminal
claude-html --open <full id>    # open that session's project
claude-html --open-plan <id>    # say what it would open, and open nothing

./install.sh                    # install using the defaults
./install.sh --out DIR          # write the pages to DIR instead
./install.sh --root DIR         # archive sessions started under DIR instead
./install.sh --uninstall        # remove the command and the hooks
./install.sh --help             # every option, with the defaults filled in

bash tests/run-all.sh           # every suite below, one verdict — what CI runs
node tests/viewer.test.js       # the renderer's tests
node tests/diff.test.js         # the diff, against every edit ever made here
bash tests/races.test.sh        # the two ways a message could be lost, reproduced
bash tests/build.test.sh        # a failed build never costs a page
bash tests/hooks.test.sh        # a save finds its transcript from the hook's note
bash tests/delete.test.sh       # deleting removes everything it should, and nothing else
bash tests/open.test.sh         # a project name opens the right thing, and nothing else
bash tests/helper.test.sh       # the helper app is built, and rebuilt when its source changes
bash tests/agents.test.sh       # sub-agents land inside their parent, never rows of their own
bash tests/backend.test.sh      # osascript and node build byte-identical pages
```

Sessions whose source has not changed are skipped, so a rebuild after a day's
work takes a fraction of a second.

### Configuration

`install.sh` writes `~/.claude/claude-html.conf`. Edit it there, or set either
variable in the environment, which wins over the file:

| Variable | Meaning |
| -------- | ------- |
| `CLAUDE_HTML_OUT` | where the pages are written |
| `CLAUDE_HTML_ROOT` | which projects get archived |
| `CLAUDE_HTML_EXPORT` | a claude.ai `conversations.json` to include |

## How it works

The JavaScript runs through whichever engine the machine has — `osascript`
on macOS, `node` anywhere else — and the same files produce the same bytes
under either. A hook runs after every reply and when a session ends. It writes a permanent
archive beside the project, then rebuilds whatever changed — normally a third
of a second, because sessions whose pages are current are never read again.

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
carries more.

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

### Deleting, and undoing it

A page opened from disk is not allowed to delete files, so the bin is a
`claude-html://` link, which macOS hands to `Claude HTML.app`. The app lists what
would go and does nothing until you click **Move to Trash** in its own dialog:
any website can ask it to open, but only that click makes it act.

The index reloads itself when you come back from that dialog, so the
conversation disappears from the list without you doing anything. It only
counts a return from somewhere else — otherwise a page reload would look like
one and it would refresh itself in circles — and it keeps checking until the
conversation is gone, because the browser's own "open this app?" prompt can
hand focus back before the helper has started. It gives up after a few tries or
a minute, which is what cancelling looks like from the page's side.

To undo, use Put Back on the files in the Trash; the prompts removed from your
up-arrow history are there too, as a file named
`claude-html removed history <id>.jsonl`. A hidden claude.ai chat is listed in
`~/.claude/claude-html.hidden` — delete its line to bring it back.

## Privacy

Everything stays on your machine. The pages make no network requests — no
fonts, no analytics, no CDN.

They do contain your conversations in full, including anything you pasted in.
The generated files are gitignored for that reason, so cloning here and
committing later will not publish them. If you serve this directory over HTTP,
put it behind auth.

## License

MIT. Not affiliated with or endorsed by Anthropic; Claude is their trademark,
and this is an independent tool that reads the files Claude Code leaves on
your own machine.
