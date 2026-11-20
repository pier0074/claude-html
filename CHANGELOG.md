# Changelog

One entry per release, newest first. Numbers are MAJOR.MINOR.PATCH: a patch
fixes, a minor adds without breaking, a major needs something from you
(usually `./install.sh` again). To update: `claude-html --update`; before
3.1.0, `git pull && ./install.sh`.

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
