# Changelog

One entry per release, newest first. Numbers are MAJOR.MINOR.PATCH: a patch
fixes, a minor adds without breaking, a major needs something from you
(usually `./install.sh` again). To update: `claude-html --update`; before
3.1.0, `git checkout main && git pull && ./install.sh`.

## 3.8.4 — 2026-11-25

- Privacy: after the rules or your own list change, a session whose page
  cannot be built again (its transcript unreadable, a full disk) no longer
  keeps the page masked the old way. A short page saying it could not be
  rebuilt, with the error, takes its place; its sub-agents' pages, its
  caches (the archiver's too) and its search text go, and the index lists
  the error. The next build that succeeds brings the page back. Under an
  unchanged list a failed build still keeps the page it had.
- Build errors are masked like the pages: an error can quote what it could
  not read.

## 3.8.2 — 2026-11-25

- Usage page: with one project chosen (or one model, broken down by
  model), each period is one row, named once in the table's heading,
  instead of the same name under every period's own line.
- Usage page: both tables end with a total row. The period table covers
  your whole history, whichever period button is on, and its heading now
  says "all time"; with a project chosen its total is that project's,
  as its conversations add it up. A total's recorded cost is marked `≥`
  when a session in it was recorded only in part, as that session's page
  does, and the line under the table says when rows marked calc are not in
  it, with the calculated total.
- Usage page: the month chart's labels read 2026-10, not 26-10.

## 3.8.1 — 2026-11-25

- Tests: `tests/run-all.sh` runs one at a time on a machine; a second run
  waits for the first (`CLAUDE_HTML_TEST_LOCK`). Several at once took each
  several times longer.
- Tests: a run that passes on a clean git tree records it, and a release
  does not run the gate again on that exact tree.

## 3.8.0 — 2026-11-25

- Linux: the link handler's windows (the delete question, and what it says
  after) go the way every other window does: closed after the windows' wait
  (`CLAUDE_HTML_GUARD_WAIT`), Cancel the default, and never shown while the
  tests run.
- Pages: the delete and hide buttons are named for screen readers; each of
  your prompts is a heading to jump between; the search fields show a clear
  outline when focused; sub-agent turns and older-format tool lines are no
  longer faded below a readable contrast.
- Inside: the helpers several scripts each had a copy of are in one place:
  `lib/common.sh` (the off and on words, reading the conf without running
  it, a command with a time limit, the links' grammars, a session id) and
  `build/fs.js` (the node side's file helpers). Code nothing reached is
  gone. The test suites share their checks (`tests/lib.sh`, `tests/lib.js`),
  and the guard, Linux and update suites take less time, checking the same.
## 3.7.3 — 2026-11-25

- The index's open and resume links act only on a conversation Claude Code
  itself has the transcript of, or on an archive in a folder claude-html's
  own hook archived into (`~/.claude/claude-html.own-archives`). An archive
  planted in a cloned repo was listed, and any web page could have its
  resume link open Terminal in that repo, or its open link the repo's page.
- The lock tells a live holder from a reused pid by a start time no time
  zone or clock change moves: a waiter in another time zone, or across a
  daylight-saving change, took a live lock as left over. Locks an older
  release wrote are judged as before.
- A transcript over 512 MiB is built a piece at a time; read whole, it was
  more than a string can hold and left the index without a word. A
  transcript that cannot be read at all, and was never built, is reported.
- The guard's quick look tells prose from what a rule would stop: "right",
  "media", "keyboard", `mkdir -p` and `git push -u` no longer start the
  engine; nor does a prompt when your own list holds plain values only.
- A session page's diff of an Edit that rewrites a whole file no longer
  freezes the page: the lines both sides share at the ends are left out of
  the work, which is bounded.
- A tool's output and thinking cut before the page says how much was cut
  again ("94000 more characters", not "36").
- Docs: Linux needs node 14.14 or later, which Claude Code's own installer
  does not bring.
- Tests: the Linux suite passes from a clone in a temporary folder
  (`CLAUDE_HTML_TEMP_DIRS`).

## 3.7.2 — 2026-11-25

- A session page escapes the model names in its token line. A planted
  archive could run a script there.
- A save replaces an archive only with a whole one: as many bytes as the
  archiver made, from as much transcript as it read. One cut short by a
  full disk, even just after a `}`, no longer replaces the good one.
- After a reply, a state file that cannot be written no longer stops the
  save.
- `./install.sh` leaves a settings.json it cannot read, or that holds a byte
  that is not UTF-8, exactly as it is, and says so.
- Forgetting safe values writes the own list whole or not at all. A failed
  write left it empty; now it is left as it was, and the command says so.
- The guard's answers `safe` and `stop` leave the own list or the conf as
  they are when they cannot read them as text, and say so. Both are written
  whole, then moved into place.
- A page or search file that could not be written is an error, and is
  written again by the next build. It was recorded as current, and kept the
  text of the old list.
- A build that does not keep a session's cache takes the cache away, its
  text and all. One under the old list stayed behind.

## 3.7.1 — 2026-11-25

- Settings page: the status line's preview wraps a long line inside its box
  instead of hiding it under a scrollbar, and says how many columns each form
  takes, and when the normal one is wider than the line may be.

## 3.7.0 — 2026-11-25

- Settings page: the guard's safe values one by one — the kind, the date
  and an id, never the value nor its fingerprint — each with **forget**;
  `claude-html --config safe` lists them and `--config forget-safe ID…`
  forgets those. Asked as "Forget this safe value?", Forget or Cancel.
- Your own list opens in your text editor from the Settings page (asked
  first: "Open your own list in the text editor?", Open or Cancel) or with
  `claude-html --config edit-list`; made with a few lines of help if missing.
- Status line: choose its items and their order (the 5-hour window, the
  week, this session's cost, today's cost across sessions, the context used,
  the agent, project · branch, the stop rule, the budget), its form
  (normal, condensed, or auto, which condenses to fit the terminal), its
  width, its bar, and its colours: `auto` (the terminal's own), `level`
  (green, amber, red; the default) or one of the terminal's colours. A live
  preview on the Settings page; the defaults draw the line as before.
- Limits & budget: the panel is the one place to change them, each of its
  rows with where its value comes from and its section of SETUP.md.
- Automatic updates (`CLAUDE_HTML_AUTO_UPDATE`, off by default): a newer
  release the daily check finds is installed by itself once a save is over,
  as `claude-html --update` installs it — never a major release, never a
  development checkout; put off while a save runs, rolled back on failure
  and tried again a day later; "updated to X.Y.Z" for a day on the index and
  the status line. Nothing is scheduled.
- Guard: when a command is stopped, Claude is told to write each sensitive
  value as `***` if it mentions the command, and is given the command
  already masked; a long one is cut to its start, each `***` with what is
  around it, and its end.

## 3.6.4 — 2026-11-25

- `--doctor` has one layout: a header with the version, titled sections a
  blank line apart, every line a padded label and its value, the parts of a
  value apart by " · "; long values wrap at the terminal's width under the
  value column, and piped output keeps one line per item. The guard's line
  has its label in `--doctor` and `--guard` alike.

## 3.6.3 — 2026-11-25

- The Settings page is as wide as the other pages, and on a wide screen each
  setting's field sits beside what it means, so it takes two or three lines
  rather than six.

## 3.6.2 — 2026-11-25

- Tests: a run of the suites no longer opens pages in your browser or brings
  windows to the front (`CLAUDE_HTML_NO_SCREEN`); it runs at lower priority
  (`CLAUDE_HTML_TEST_NICE`, default 10), and its helper-app leak check counts
  only its own temp folders.

## 3.6.1 — 2026-11-25

- Fixed: a prompt the guard stops is no longer repeated back by Claude Code as
  "Original prompt: …", which also kept it in the session's transcript; the
  limits stop leaves it out too. (Claude Code may still keep a prompt in its
  own files; a blocking hook cannot prevent that.)
- Fixed: a sub-agent's report, which Claude Code hands the session as a
  prompt, is no longer stopped by the guard or a limit rule: Claude wrote it,
  and once stopped it was lost. Anything typed with it is still checked.
- Fixed: `\$(cat file)` in a heredoc, and `$$(…)` in a Makefile, are commands
  like `$(cat file)`, not a secret.

## 3.6.0 — 2026-11-25

- **A Settings page** (`settings.html`), linked from the index and the Token
  usage page: every setting with where its value comes from (default, conf or
  environment), its default, one line of help and its `SETUP.md` section.
  Change it there and **apply** asks in a window, listing each change before →
  after, marking what lowers protection, and warning when the conf changed
  since the page was built. Where the pages go and the projects root are shown
  with the command that changes them; Claude Code's own settings are shown,
  never written; your own masking list is only ever counted.
- `claude-html --config` shows every setting; `--config set KEY=VALUE…` checks
  every value before writing any; `--config unset KEY…` restores the default;
  `--config forget-safe` forgets the guard's safe values and keeps your own
  entries. Each rebuilds the pages.
- Page defaults in the conf: `CLAUDE_HTML_VIEW_THEME`, `_GROUP`, `_SESSION`,
  `_PERIOD`, `_BREAKDOWN`, `_PRICES`. A browser starts with them until a click
  is remembered; "reset this browser" forgets what it remembered.
- `CLAUDE_HTML_PRICES` and `CLAUDE_HTML_EXPORT` work as plain conf lines,
  without `export`.
- Opening a session page no longer pins its view in the browser; only a click
  does.
- A week reset such as `fri 25:00` is now refused rather than wrapping round.

## 3.5.1 — 2026-11-24

- Fixed: the API budget no longer counts a forked session's copied replies
  twice when the original is still in use after the fork, nor drops them when
  an original without a recorded cost is resumed.
- Fixed: a project's heading on the index counts a reply copied by a resume
  or a fork once, as the Token usage page does.
- A session's page says how many of its replies, and tokens, another session
  (a resume or a fork) also holds; the index row says it on hover.
- Fixed: `claude-html --guard status` said " safe value(s)" with no number
  when there is no list file; it says 0.

## 3.5.0 — 2026-11-24

- **Tidier clone.** The files now live in folders: `lib/` (the shell
  libraries), `build/` (what builds the pages, and the price file),
  `actions/` (the guard, open, resume, delete, the settings writer), `mac/`
  and `linux/`. The command and the three scripts Claude Code calls
  (`save-conversation.sh`, `guard.sh`, `statusline.sh`) stay at the top, so
  your hooks keep working through the update, and back if you return to an
  older release. Nothing to do: `claude-html --update` moves you.
- `release.sh` is now `lib/version.sh`; the images are in `docs/img/`.
- The changelog shown before an update compares release numbers with the
  same code as the update itself.

## 3.4.0 — 2026-11-24

- **Windows you can read and copy.** Every text in the guard's window, the
  stop window and the limits confirmation can be selected and copied with ⌘C.
- **Found ▸ and Command ▸.** Arrows open a box under the row: each match with
  40 characters around it and the secret in red, shown only when you open it;
  the whole command, every line, exactly as Claude wrote it. Each box scrolls
  and has a copy button. The stop window's Rule ▸ shows your rules as the conf
  holds them; the confirmation's File ▸ shows the exact lines Apply writes.
- **A countdown** beside OK: "Cancel in 0:59" down to 0:00, then the window
  closes as Cancel ("closes in … — nothing changed" when confirming).
- **How long the windows wait is a setting:** `CLAUDE_HTML_GUARD_WAIT`
  (`45`, `45s`, `2m`, `1m30s`; 30 seconds to 60 minutes). The default is now
  1 minute instead of 10. `claude-html --guard wait` shows it, `--guard wait 2m`
  sets it, `--guard wait default` takes it out; a value that is not one is
  ignored and said so in `--guard status` and `--doctor`. The guard's hooks
  now have a 3660-second timeout so any wait works as soon as the conf is
  saved; `./install.sh` (which an update runs) raises an older install's in
  place.
- **Nothing secret on a command line.** What the boxes show reaches the window
  through private temp files, deleted as they are read.
- **Linux:** a Details button opens what was found and the whole command in
  the dialog tool's own text window; the question says how long it waits.
- **The plan line** wraps between its parts, never inside one.
- **README:** new screenshots, light or dark to match the reader, at a
  reading size.
- Fixed: a guard window that closed with nobody answering could let the
  prompt through instead of stopping it.

## 3.3.0 — 2026-11-21

- **Plan limits in Claude Code's status line.** Your 5-hour and weekly usage
  under the prompt, green, amber from 80 %, red from 95 %, with the reset
  times; the index and the Token usage page show the same line, "as of" when
  Claude Code last reported it. A status line you already have is kept:
  claude-html's wraps it, and `--uninstall` gives it back exactly.
- **Stop rules.** "From Fri 20:00, stop at 80 %" asks before a new prompt, in
  the guard's window: Cancel, Allow once, Allow until the reset, Stop. A task
  already running is never interrupted, and old figures never stop anything.
  Announced once in Claude Code before a rule starts and when it starts;
  Claude Code's own plan warnings are not repeated.
- **API budget** per day, week or month: warnings at 80 and 95 %, a stop at
  100 %.
- **Set it all** with `claude-html --limits`, or in the Token usage page's
  Limits & budget section, which copies the commands or applies them through
  a `claude-html://limits` link that always asks first. Optional desktop
  banner: `claude-html --limits notify on`.
- **A calculated cost beside the recorded one**, never mixed: every session's
  tokens at the list price of their day, from `prices.tsv`, a dated price
  file citing Anthropic's own pages. Shown marked `calc` where nothing was
  recorded (`—` before). The dashboard's cost card shows both; a third toggle
  prices "at the time" or "at today's prices"; a Price history lists each
  model's price periods, the change, and your tokens in each.
- Cache writes are kept as 5-minute and 1-hour writes, priced differently;
  fast mode and Haiku 5.5 prompts over 100,000 tokens have their own lines;
  a model without a line is said to be unpriced, never guessed.
  `CLAUDE_HTML_PRICES` points to a price file of your own.
- After updating: nothing to do. `./install.sh`, which the update runs, adds
  the status line; every page rebuilds once; each archive whose transcript is
  still there is rewritten in format 6 at its next save.

## 3.2.1 — 2026-11-21

- **The weekly reset can be given in UTC**: `CLAUDE_HTML_WEEK_RESET="tue 07:00 UTC"`.
  Anthropic's reset is a fixed moment, so written in local time it drifted
  an hour when the clocks changed and the dashboard's weeks started an hour
  late all winter. The dashboard says both: "Tuesday 07:00 UTC (Tuesday 08:00
  your time)". A local setting keeps working as before.

## 3.2.0 — 2026-11-20

- **What a call returned, and thinking, start folded**, as the docs always
  said; a click opens them, they stay open while you read, and find opens
  whatever hides its match. A Markdown table in a reply is drawn as a table.
- **Search lands on the match.** A result opens the conversation with the
  words you searched for already found and highlighted, even inside folded
  thinking. Each conversation shows its newest matches first and says how
  many more it has; "copy" or "resume" in the box no longer matches every row.
- **Index:** grouped by project, the table no longer squeezes titles to four
  letters on a narrower window. The title is the link to the conversation.
- **Dashboard:** a month or week with nothing in it is a gap on the chart,
  not hidden. An empty dashboard shows its one sentence.
- Every page prints in the light palette without its buttons, fits a phone,
  opens in the theme you chose without a flash, and has readable timestamps
  and labels. "1 prompt", not "1 prompts".

## 3.1.3 — 2026-11-20

- **The guard no longer waves a command through.** Allow, Safe or Stop on a
  command now leaves Claude Code's own permission check to run as usual,
  and the dialog shows the command's first line, masked.
- Your own hooks are yours: one named like ours (`prompt-guard.sh`, a
  `guard.sh` of your own) is no longer skipped, replaced or removed by the
  installer. Hooks left by a clone somewhere else are replaced as a set.
- **Archives are format 5**: read by the same code as the pages, so a
  session whose transcript has expired keeps the very page it had: title,
  prompts, pictures, tool output. An older archive is rewritten at its
  session's next save; one whose transcript is gone is shown without the
  harness's tags.
- What claude-html writes is readable by you alone, and archive folders
  keep themselves out of git; `--doctor` says how both stand.
- Saves no longer stop for good behind a lock left by a crash, nor spoil an
  archive when two run at once; the save before a compaction no longer
  holds it up.
- The index's update link asks before updating, at most once a minute.
- Folders with a quote or a backslash in their name, and a relative
  `--out` or `--root`, work; `copy` quotes the folder.
- On a Mac without Apple's developer tools, nothing offers to install them
  after every reply.
- After updating: ./install.sh, then claude-html --force

## 3.1.2 — 2026-11-20

- The test suites run side by side: `bash tests/run-all.sh` takes about a
  minute and a half instead of seven. `CLAUDE_HTML_TEST_JOBS=1` runs them one
  after another.
- No test reads the clock to decide a result any more, so a busy or a fast
  machine gives the same answer.
- A suite passes only on its own verdict line: one cut short by an error no
  longer counts as passed.
- The tests never register anything with the system. They no longer build the
  helper app inside the clone, which macOS registered by itself, leaving a
  second app claiming the links.

## 3.1.1 — 2026-11-20

- `--update` says so when it is waiting for a running save, and waits the
  full minute before giving up; it stopped half a second early.

## 3.1.0 — 2026-11-20

- **`claude-html --update`**: to the newest release, or to one by number
  (going back asks first); `--update list` and `--update status` look and
  change nothing. It reinstalls, rebuilds what needs it, and puts everything
  back if a step fails.
- **Once a day** a save asks GitHub for the list of releases, and a newer one
  is one line on the index, in the terminal, and once in Claude Code.
  `claude-html --update off` stops it. The pages still make no requests.
- **resume** and **run** leave a usable terminal: when the command ends,
  the window stays, as an ordinary shell in that folder.
- A bare `./install.sh` no longer puts back the guard's hooks after
  `--no-guard`.

## 3.0.1 — 2026-11-20

- `claude-html --version`, and the version in `--doctor`.
- This changelog; releases are numbered MAJOR.MINOR.PATCH from here on.
- The public branch is `main`, one commit per release.

## 3.0.0 — 2026-11-20

- **Secrets masked.** Tokens, keys and passwords become `***` in everything
  claude-html writes: pages, search, archives, cache. Claude Code's own
  transcript is left as it is. Your own list in `~/.claude/claude-html.redact`;
  `CLAUDE_HTML_REDACT=off` turns it off.
- **Guard.** A prompt or a command holding a secret is stopped before Claude
  sees it; a window asks: cancel, allow once, safe, or stop.
- `claude-html --redact-check`, `--redact-archives`, `--guard`.
- [docs/SETUP.md](docs/SETUP.md): every setting, command and hook in one place.
- After updating: `./install.sh` (adds the guard's hooks), then `claude-html --force`.

## 2.0.0 — 2026-11-07

- **Linux**, natively: launchers, link handler, Trash, dialogs, `--doctor`.
- **Faster saves.** node does the work when one is already installed (never
  installed for you); a save reads only what was appended.
- **Resume** button beside copy; quitting a session no longer waits for the save.
- **Cost**, where Claude Code records it, on the index, the session and the dashboard.
- Long conversations open in half a second; the header folds as you scroll.

## 1.0.0 — 2026-10-21

- The first release: every session as a static page, full-text search,
  diffs, sub-agents, archives that outlive Claude Code's cleanup, resume by
  copy and paste, and the token dashboard by week, month and model.
- macOS only. Superseded: install a later release.
