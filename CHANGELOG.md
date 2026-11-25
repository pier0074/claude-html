# Changelog

One entry per release, newest first. Numbers are MAJOR.MINOR.PATCH: a patch
fixes, a minor adds without breaking, a major needs something from you
(usually `./install.sh` again). To update: `claude-html --update`; before
3.1.0, `git checkout main && git pull && ./install.sh`.

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
