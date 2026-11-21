# Changelog

One entry per release, newest first. Numbers are MAJOR.MINOR.PATCH: a patch
fixes, a minor adds without breaking, a major needs something from you
(usually `./install.sh` again). To update: `claude-html --update`; before
3.1.0, `git checkout main && git pull && ./install.sh`.

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
