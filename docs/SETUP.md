# Setting up claude-html

Every setting and every way to set the tool up, in one place. How it all
works is in [DETAILS.md](DETAILS.md).

- [How a setting is decided](#how-a-setting-is-decided)
- [Where things go](#where-things-go)
- [Engine](#engine)
- [Dashboard weeks](#dashboard-weeks)
- [Prices](#prices)
- [claude.ai exports](#claudeai-exports)
- [Secrets](#secrets)
- [Guard](#guard)
- [Limits and budget](#limits-and-budget)
- [Hooks](#hooks)
- [Transcript cleanup](#transcript-cleanup)
- [Commands](#commands)
- [Updating](#updating)
- [The cache](#the-cache)
- [Linux](#linux)
- [For the test suite](#for-the-test-suite)

## How a setting is decided

The command, the hooks and the installer all decide the same way:

1. a variable set in the environment wins,
2. then the line in `~/.claude/claude-html.conf`,
3. then the default.

A hook sees the environment Claude Code was started with. The conf is a
shell file that `install.sh` writes once and then only adds to; edit it
freely.

```bash
# ~/.claude/claude-html.conf
CLAUDE_HTML_ROOT="$HOME/Sites"
CLAUDE_HTML_OUT="$HOME/Sites/claude-html"
```

| Variable | What it is | Default |
| -------- | ---------- | ------- |
| `CLAUDE_HTML_CONF` | the conf file itself (environment only) | `~/.claude/claude-html.conf` |

## Where things go

**Where you clone it is the configuration.** The pages are written in the
clone, and its parent is the projects root: every session started in it or
below is archived.

| Variable | Flag | What it is | Default |
| -------- | ---- | ---------- | ------- |
| `CLAUDE_HTML_OUT` | `./install.sh --out DIR` | where the pages are written | the clone |
| `CLAUDE_HTML_ROOT` | `./install.sh --root DIR` | which projects get archived: every session started in it or below | the folder the clone is in |

A leading `~` works in both. `--out` and `--root` change their own conf line
and nothing else, so a later bare `./install.sh` does not undo them.

| Layout | How |
| ------ | --- |
| clone in `~/Sites/claude-html`, pages there, everything under `~/Sites` archived | `git clone … ~/Sites/claude-html && cd ~/Sites/claude-html && ./install.sh` |
| clone anywhere, pages elsewhere | `./install.sh --out ~/Documents/claude-pages` |
| clone anywhere, another projects tree | `./install.sh --root ~/code` |
| one-off build into another folder | `CLAUDE_HTML_OUT=/tmp/pages claude-html` |

**One projects root only.** There is no list of roots. To cover two trees,
point `CLAUDE_HTML_ROOT` at a folder that holds both. Archives are written
beside each project, in `<project>/.claude/.claude-conversations/`.

## Engine

| Variable | What it is | Default |
| -------- | ---------- | ------- |
| `CLAUDE_HTML_ENGINE` | `node` or `osascript`: which one reads the transcripts and builds the pages | node when a working one is found, else `osascript` |
| `CH_NODE_PROBE_LIMIT` | seconds each node found is given to answer before it is passed over (environment only) | 5 |

```bash
CLAUDE_HTML_ENGINE=osascript   # in the conf, or the environment
```

- A node counts only if it runs and is 14.14 or later. It is looked for on
  `PATH`, then in `/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin`,
  `~/.local/bin` and the versions fnm, nvm, Volta, asdf and mise installed —
  never their shims. Each is tried from `/` with five seconds to answer
  (`CH_NODE_PROBE_LIMIT`).
- A value that is neither, or names one this machine lacks, is set aside:
  the save goes ahead with the other, and `--doctor` shows a note.
- Deleting, opening and resuming stay on `osascript` on a Mac either way.

`claude-html --doctor` shows the engine and why it was picked, the system,
desktop, terminal, trash, dialog and link handler, the pages and projects
folders, whether what it wrote is readable by you alone, any archive folder
git would commit, and the [redaction](#secrets).

## Dashboard weeks

| Variable | What it is | Default |
| -------- | ---------- | ------- |
| `CLAUDE_HTML_WEEK_RESET` | when your plan's weekly allowance resets, so the dashboard's weeks match the ones you are billed for: a day and an hour, local or UTC | calendar weeks, from Monday 00:00 |

```bash
CLAUDE_HTML_WEEK_RESET="tue 07:00 UTC"   # a fixed moment: what Anthropic uses
CLAUDE_HTML_WEEK_RESET="tue 09:00"       # local time; also "thu 17", "Friday 8:30"
```

Anthropic's reset is a fixed moment in UTC, so in local time it moves by an
hour when the clocks change (Tue 09:00 in Zurich in summer, 08:00 in
winter). Write it in UTC to keep the weeks right all year: take the reset
time Claude Code shows ("resets Nov 24 at 8am") and convert it to UTC once.

The installer offers this line commented out. One it cannot read falls back
to Mondays.

## Prices

The calculated cost — shown beside what Claude Code recorded, and in its place
where it recorded nothing, marked `calc` — comes from `prices.tsv` in the
clone: Anthropic's API list prices, in USD per million tokens, one line per
model and per price period. [DETAILS.md](DETAILS.md#what-you-get) says how a
cost is worked out from it.

```
model             from        to          input  output  cache_read  cache_write_5m  cache_write_1h  source                                               checked
claude-sonnet-5-5 2026-09-28  2026-10-06  2      10      0.20        2.50            4               https://platform.claude.com/docs/en/release-notes/…  2026-11-21
claude-sonnet-5-5 2026-10-07              2      10      0.10        2.50            4               https://platform.claude.com/docs/en/about-claude/…   2026-11-21
```

Columns are separated by one tab; `#` starts a comment. A reply is priced by
the line whose `from`..`to` holds its day (UTC, both days included); an empty
`to` is today's price.

- **A price changes:** set `to` on the model's current line to the day
  before the change, and add a line with the new prices from the day of the
  change, an empty `to`, the page that says so in `source` and today's date
  in `checked`.
- **A new model:** add a line with the id Claude Code records (the
  `message.model` of its replies; `claude-html` shows it on the dashboard as
  not priced until then) and `from` its launch day. A dated id
  (`claude-haiku-4-5-20251001`) is priced by the line without the date, so
  one line covers every snapshot. A reply in fast mode is priced by the
  model's `/fast` line, a Haiku 5.5 prompt over 100,000 tokens by
  `claude-haiku-5-5/over-100k`.
- **A line you only re-checked:** update its `checked` date. The dashboard
  shows the newest one in the heading of its price history.

Copy prices from Anthropic's pages only, never from memory: the pricing page
(<https://platform.claude.com/docs/en/about-claude/pricing>) for today's, the
release notes (<https://platform.claude.com/docs/en/release-notes/overview>)
for when a model came out or a price changed. A line that cannot be read is
skipped and named on the dashboard. The next build prices everything again;
no `--force` needed.

| Setting | What it is | Default |
| ------- | ---------- | ------- |
| `CLAUDE_HTML_PRICES` | a price file of your own, in the same format, instead of the clone's | `prices.tsv` in the clone |

Like `CLAUDE_HTML_EXPORT` it is read from the environment only, so in the
conf it needs `export`. Your own file is not updated with the tool: copy the
clone's new lines into it after an update.

On the dashboard, **cost at · the price of the time / today's prices** prices
every hour at the line in force then, or at today's line to show what the
same work would cost now; the browser remembers the choice. On a
subscription both are list-price equivalents, not a bill.

## claude.ai exports

| Setting | What it is | Default |
| ------- | ---------- | ------- |
| `CLAUDE_HTML_EXPORT` | one `conversations.json` to read, instead of looking | `conversations.json` in `~/Downloads`, the projects root, or one folder inside either |
| `~/.claude/claude-html.hidden` | claude.ai chats hidden from the index, one id per line; delete a line to bring a chat back | none hidden |

`CLAUDE_HTML_EXPORT` is read from the environment only, so in the conf it
needs `export`:

```bash
export CLAUDE_HTML_EXPORT="$HOME/exports/conversations.json"
```

The index's bin writes the hidden list for you.

## Secrets

Tokens, keys and passwords are written as `***` in everything claude-html
writes: archives, pages, sub-agent pages, search, index, launchers and
`.cache/`. **Claude Code's own transcript in `~/.claude/projects` is never
touched** — resuming needs it — so it keeps the secret for as long as Claude
Code keeps the transcript (3650 days if the installer set
[`cleanupPeriodDays`](#transcript-cleanup)).

| Setting | What it is | Default |
| ------- | ---------- | ------- |
| `CLAUDE_HTML_REDACT` | `off` (or `0`, `no`, `false`) turns masking off | on |
| `CLAUDE_HTML_REDACT_FILE` | your own list of things to mask | `~/.claude/claude-html.redact` |

```bash
CLAUDE_HTML_REDACT=off    # in the conf, or the environment
```

**Your own list**, one entry per line:

```text
# a comment
Example-Not-A-Real-Secret-0000
/acme_[0-9a-f]{32}/i
```

- a plain line is masked wherever it appears, exactly as written;
- `/regex/flags` is a regex; flags may be `i`, `m`, `s`, `u`;
- a line it cannot use — an invalid regex, one that matches nothing at all,
  one that would match inside `***` — is ignored and reported by line
  number in `--doctor`; it never fails a save;
- what the list says is never printed anywhere.

A regex line is slower than a plain one under `osascript`, which reads every
character of every text with it; a regex that starts with plain text is
looked for with that text first.

**Built-in rules**, by the names `--redact-check` counts them under:

| Rule | Catches |
| ---- | ------- |
| `anthropic`, `openai` | `sk-ant-…`, `sk-…`, `sk-proj-…` |
| `github`, `gitlab` | `ghp_ gho_ ghu_ ghs_ ghr_ github_pat_`, `glpat-` |
| `aws-key-id`, `aws-secret` | `AKIA…`/`ASIA…` key ids; `aws_secret_access_key` values |
| `google-api-key` | `AIza…` |
| `slack-token`, `slack-webhook` | `xoxb-…` and kin, `xapp-…`; `hooks.slack.com/services/…` |
| `stripe` | `sk_live_ rk_live_ sk_test_ rk_test_ whsec_` |
| `npm`, `pypi`, `huggingface`, `sendgrid`, `telegram` | `npm_…`, `pypi-AgEI…`, `hf_…`, `SG.….…`, bot tokens |
| `twilio` | `SK` + 32 hex, only in a text that says "twilio" |
| `discord-webhook`, `discord-token` | webhook URLs; bot tokens, only in a text that says "discord" |
| `jwt` | `eyJ….eyJ….…` |
| `private-key` | `-----BEGIN … PRIVATE KEY-----` blocks, with real or `\n` line breaks |
| `auth-header`, `bearer` | `Authorization: Bearer/Basic/token …`; a bare `Bearer` token |
| `url-password` | `scheme://user:password@host` (user and host stay) |
| `user-password` | `curl -u user:password`, `--user` |
| `mysql-password`, `sshpass` | `mysql -pV` (and mariadb, mysqldump, mysqladmin, mysqlimport, in the same command: not after a `|`, `;` or `&&`), `sshpass -p V` |
| `flag` | `--password value`, `--pass value`, `--api-key=value` (not `--password-stdin`) |
| `assignment` | `NAME=value`, `NAME: value`, `"name": "value"`, `Password=…;` where the name ends in password, pass, secret, token, api key, access key, private key, client secret, auth, credentials, `mdp` or `motdepasse` — the name stays |
| `env-name` | a name in capitals with such a word anywhere: `SECRET_KEY_BASE=`, `TOKEN_GITHUB:` — not one ending in a word that makes it a setting (URL, PATH, NAME, ID, COUNT, LIMIT, MAX, BYTES, TTL, TIMEOUT, HEADER, FIELD, REGEX, ALGO, POLICY and the like); one ending in HASH only when the value looks like a hash |
| `mot-de-passe` | `mot de passe : value` |
| `cookie` | a `Cookie:` value holding a session id |
| `key-value` | in a tool's input or any parsed object, a string under a key that says secret: `token`, `password`, `apiKey`, `x-api-key`, `Authorization`, `Cookie`; a number under one is kept |
| `cut-token` | what a cut left of a token in an old archive |

**How sure.** Where the form says so plainly — a name in capitals
(`DB_PASSWORD=hunter`), a quoted value (`"token": "123456"`), a `--password`
flag, a key in a tool's input, a URL, `curl -u`, `sshpass -p`, `mysql -p` —
any value is masked but a stand-in (`changeme`, `string`, `your_token_here`,
`<password>`, `""`, fetch's `credentials: 'include'`, or a field's own name
such as `'newPassword'`). A bare value after a name in running text must
have a digit or a symbol in it, so `password: wrong` and `token = getToken()`
stay; so must one after `NAME= ` with a space, which in a shell is an empty
variable for the command that follows (`DB_PASSWORD= echo x`).

**Limits.** It recognises formats, it does not guess: a secret of no known
shape pasted on its own, with no name before it, is not caught unless your
list names it, and a number under a secret key is kept. In lower case only
a name's last word counts, so `token_count: 12k` stays.
A bare value that reads as code is kept too: a call (`bin2hex(…)`), a type
(`?string`, `Uint8Array`), an encoding (`Base64`), a lower-case identifier
(`utf8mb3_general_ci`), or the next HTML attribute (`name="password" :errors=…`).

**Two commands**, for archives already written:

```bash
claude-html --redact-check      # per session and archive: counts by rule; changes nothing
claude-html --redact-archives   # rewrite every archive holding something to mask
```

A save rewrites the archive of a session whose transcript is still there;
an archive whose transcript has gone is masked on its page but only changed
by `--redact-archives`. `--doctor` and the build say how many are left.

## Guard

Masking keeps a secret out of what claude-html writes; the guard keeps it
from reaching Claude at all. Before a prompt is sent, and before Claude
runs a Bash command, it looks for the [rules it is sure of](#secrets) —
every known token prefix, key blocks, JWTs, `Authorization` headers,
passwords in URLs, after `-u`, `sshpass -p`, `mysql -p`, names in capitals,
`--password` flags — and your own list. Not the forms that take reading
(`password:` in prose, cookies).

On a match it stops and asks. With someone at the screen, in a window,
which for a command also shows its first line, masked:

![The guard's dialog: where, what was found, four choices](guard-dialog.png)

| Answer | Prompt | Command |
| ------ | ------ | ------- |
| **Cancel** (picked already; Return, Escape) | nothing is sent | not run; Claude is told to read it from `~/.my.cnf`, an env var or a credential helper |
| **Allow once** | sent this time; still masked in saved pages; asked again next time | goes on to Claude Code's own permission check, as if the guard were not there |
| **Safe** | sent, never asked about again, and shown in saved pages | the same |
| **Stop** | sent, and the guard turned off | the same |

It waits ten minutes. Then it closes, as Cancel, and the terminal says so.

With nobody to ask — over ssh, no desktop, `CLAUDE_HTML_GUARD_DIALOG=off`,
or the dialog failed — the prompt is stopped and the answer is typed as the
very next prompt, in the same session, within ten minutes:

```text
⚠ claude-html: your prompt has been interrupted — sensitive information detected (GitHub token (1)).
  Nothing was sent. Retype it without it, or answer:

  cancel  do not send
  allow   it is sensitive, send it this time only
  safe    it is not sensitive, send it and never ask again
  stop    turn this check off (claude-html --guard on turns it back on)
```

After `allow`, press ↑ and Enter: the prompt passes once. A command with
nobody to ask goes to Claude Code's own permission dialog (deny = not run,
allow = run once); with permissions bypassed it is refused instead.

| Setting | What it is | Default |
| ------- | ---------- | ------- |
| `CLAUDE_HTML_GUARD` | `on` (prompts and commands), `prompt` (prompts only), `off` | `on` |
| `CLAUDE_HTML_GUARD_DIALOG` | `off` always asks in words, as the next prompt | `on` |

```bash
claude-html --guard status   # the mode, the hooks, the safe values by rule and date
claude-html --guard prompt   # on, off, prompt: one line in the conf
```

**What Safe keeps**: a line `safe:<salt>:<hash>   # github, 2026-11-19` in
your own list — a salted SHA-256 of the value, never the value. To forget
one, delete its line. A plain line or `/regex/` of your own list still masks
what it matches, safe or not.

**What it cannot do**: see what a tool prints (it checks what goes in, not
what comes out); know a secret of no known shape; stop a secret Claude
already has from an earlier turn or a file it read. The prompt you typed
can still be in Claude Code's own prompt history and transcript, as its
documentation says of every blocked prompt.

**If Claude Code gives up on the hook**, it sends the prompt or runs the
command. Its hooks' default time for a prompt is 30 seconds, so the
installer sets 660 for the guard's two: past the dialog's ten minutes.

On Linux the dialog is zenity's, kdialog's, yad's or xmessage's, so its
look is the desktop's; their own Cancel button is the Cancel choice.

## Limits and budget

Your plan's usage, your own stop rules, and a budget for API use. Claude
Code already warns at its plan levels ("You've used 80% of your weekly
limit · resets …") and `/usage` shows the figures, so claude-html repeats
none of that. It adds what Claude Code does not have: a **status line**, a
**plan line** on the index and the Token usage page, **stop rules**, and a
**budget** for an API key.

**Where the figures come from.** Claude Code runs a status-line command
after each reply and hands it JSON: for Pro, Max and Ultra subscribers,
from a session's first reply on, `rate_limits.five_hour` and
`rate_limits.seven_day`, each a `used_percentage` and a `resets_at`; for
everyone, `cost.total_cost_usd`, the session's cost at list price.
claude-html's status line shows them and records the latest in
`~/.claude/.claude-html.limits`, which the pages, the rules and their
announcements read. With an API key there are no percentages: the week's
spend is counted at each save, session by session — the cost Claude Code
recorded for a session, or, for one with none, its tokens at the
[price table](#prices)'s prices, never both — plus the running session's
own cost while no save has counted it.

```text
plan · 5 h ██████░░░░ 62 % ↻16:30 · week ████████▌░ 81 % ↻Tue 08:00 · stop at 80 % from Fri 20:00
budget · week $38.20 of $50 ███████▌░░ 76 % ↻Tue 08:00 · this session $1.12
```

Normal below 80 %, amber from 80, red from 95. With neither figure there is
a short line, never an error.

**One status-line slot.** Claude Code has a single `statusLine`. The
installer puts claude-html's there when it is empty. When you have one of
your own, claude-html's **wraps** it: your command is kept whole inside
claude-html's (`bash '<clone>/statusline.sh' --wrap '<your command>'`,
your `padding` and other fields as they were), it is run first with the
same JSON, its output shown first, then claude-html's part. A command of
yours that fails or takes more than three seconds costs its own part only.
`./install.sh --uninstall` gives yours back exactly; a re-run changes
nothing.

**Stop rules.** A rule says: from this weekday and time until the weekly
reset, a new prompt is stopped once the week is past this percentage.

```bash
CLAUDE_HTML_LIMIT_RULES="fri 20:00 80% · sat 00:00 90%"   # or joined by commas
```

The stop is gentle: only a **new prompt** waits, in the guard's own window,
Cancel picked already:

![The stop window: the week, the rule, four choices](limits-stop.png)

| Answer | What happens |
| ------ | ------------ |
| **Cancel** (picked already; Return, Escape) | nothing is sent |
| **Allow once** | this prompt is sent; the next one asks again |
| **Allow until the reset** | no more asking until the week's `resets_at` |
| **Stop** | sent, and that rule taken out of the conf (`claude-html --limits add …` brings it back) |

As the guard's: ten minutes, then Cancel; with nobody at the screen the
answer is the next prompt, one word, `cancel`, `allow`, `until` or `stop`.
Figures more than six hours old, or none yet, never stop anything: the
window and `claude-html --limits` say "no recent usage values". A rule
acts on new prompts only: a task already running, and its sub-agents,
carry on. It works with the guard off, through the same hook.

**The week.** Claude Code's own `seven_day.resets_at` when it has given
one (exact); else `CLAUDE_HTML_WEEK_RESET` ([Dashboard weeks](#dashboard-weeks));
else calendar weeks. A rule's time is local, on the clock, so across a
change of the clocks it is still 20:00.

**Announcements.** One line in Claude Code after a reply, through the Stop
hook's `systemMessage`, once each: when a rule starts within twelve hours
and the week is already within five points of it, and when it starts.

```text
⚠ claude-html · your stop rule starts Fri 20:00 at 80 % · week now 81 %
```

**Budget, for API use.** A dollar amount per day, week or month, warned
about at 80 and 95 % (one line each, once per period) and stopped at 100 %
in the same window. It does not apply while Claude Code has reported plan
figures in the last eight days: a subscriber's list-price cost is not what
they pay.

**Desktop banner**, off by default: the same announcements and warnings,
on macOS through `osascript` (the first may ask for permission, and shows
"Script Editor" as its source), on Linux through `notify-send` where the
desktop has it; none over ssh, without a display, or under WSL.

| Setting | What it is | Default |
| ------- | ---------- | ------- |
| `CLAUDE_HTML_LIMITS` | `off`: no stop, no announcement, no budget warning, no banner (the status line and the pages still show the figures) | `on` |
| `CLAUDE_HTML_LIMIT_RULES` | stop rules, `"<day> <HH:MM> <percent>%"` joined by ` · `, commas or semicolons; 8 at most | none |
| `CLAUDE_HTML_BUDGET` | `"<dollars> day\|week\|month"`, or `off` | none |
| `CLAUDE_HTML_BUDGET_WARN` | the budget's two warning levels | `"80 95"` |
| `CLAUDE_HTML_LIMIT_NOTIFY` | `on`: the desktop banner | `off` |

```bash
claude-html --limits                         # what is set, the latest figures, their source and age
claude-html --limits add "fri 20:00 80%"     # a rule; remove <n> takes one out
claude-html --limits budget week 50          # or day, month; budget off; budget warn 80 95
claude-html --limits notify on               # the banner
claude-html --limits off                     # all of it, the rules kept in the conf
```

**From the page.** The Token usage page has a foldable **Limits & budget**
section with the same settings. The page never writes a file: **copy
command** gives the change as `claude-html --limits` lines, and **apply**
(where the helper app or the Linux link handler is) opens a
`claude-html://limits/…` link, which asks in a window of its own, listing
every value it will write, Cancel the default. Only Apply writes the conf
and rebuilds the pages. The link holds the values in a fixed form and
nothing else, at most 160 characters; the helper, `handler.sh` and the
command each refuse anything else. Without a window to ask in (no desktop),
nothing is written and the command says what to run instead.

**Not covered**: claude-html cannot see the figures while Claude Code is
closed (every display says "as of"); Anthropic decides the `rate_limits`
and `cost` fields, which older Claude Code versions do not send and which
may change; a rule uses the week as last seen, so a prompt sent before the
next refresh can pass a level by a few percent; other sessions running at
the same time count toward the API budget once they end; nothing here
stops work already running.

## Hooks

`./install.sh` adds these hooks to `~/.claude/settings.json`:

| Hook | When | What it does |
| ---- | ---- | ------------ |
| `Stop` | after every reply | saves in the background, so the reply is never held up; gives way to a save already running; once per release, says a newer one is out; announces a [stop rule or a budget level](#limits-and-budget) |
| `SessionEnd` | when a session ends | saves, detached so quitting is instant, and waits its turn |
| `PreCompact` (`auto`, `manual`) | before a compaction | saves, detached so the compaction is not held up; the transcript keeps what it summarises |
| `UserPromptSubmit` | before a prompt is sent | the [guard](#guard), and the [stop rules and budget](#limits-and-budget) |
| `PreToolUse` (`Bash`) | before a command runs | the [guard](#guard) |

And `statusLine`, claude-html's [status line](#limits-and-budget), or
claude-html's around yours.

They are added beside the hooks you have; yours are read, never rewritten.
`./install.sh --no-guard` leaves the guard's two out and turns it off; a
later bare `./install.sh` (which is what an update runs) leaves them out
while the conf says `CLAUDE_HTML_GUARD=off`.
An install from before the guard gets them on the next `./install.sh`.
`./install.sh --uninstall` removes only these.

## Transcript cleanup

Claude Code deletes transcripts after `cleanupPeriodDays` in
`~/.claude/settings.json`, 30 days by default. The installer sets it to
3650 **only if you have not set it**; one you chose is kept, and the
installer says so if it is under a year. Uninstalling leaves it as it is.

## Commands

| Command | What it does |
| ------- | ------------ |
| `claude-html` | build what changed, open the index |
| `claude-html --force` | rebuild every session from scratch |
| `claude-html <session id>` | rebuild that session (a prefix will do) |
| `claude-html --doctor` | what this machine is, which tool does each job, the redaction |
| `claude-html --redact-check` | what would be masked, per session and archive; changes nothing |
| `claude-html --redact-archives` | rewrite the archives that still hold something to mask |
| `claude-html --guard on\|prompt\|off\|status` | turn the [guard](#guard) on, on for prompts only, off; or say how it stands |
| `claude-html --limits` | the [stop rules, budget and banner](#limits-and-budget), and the latest figures with their source and age (`status` too) |
| `claude-html --limits add "fri 20:00 80%"` / `remove <n>` / `rules "…"\|none` | a stop rule more, one fewer, or all of them at once |
| `claude-html --limits budget day\|week\|month <dollars>` / `budget off` / `budget warn <a> <b>` | the API budget and its two warnings |
| `claude-html --limits notify on\|off` / `on\|off` | the desktop banner; all of the limits |
| `claude-html --limits-apply <payload>` | what the page's **apply** link reaches: asks in a window, then writes and rebuilds |
| `claude-html --delete <full id>` | the index's bin: move a conversation to the Trash, after asking |
| `claude-html --delete-plan <full id>` | say what `--delete` would move, and move nothing |
| `claude-html --delete <full id> --yes` | the same without asking (`-y`) |
| `claude-html --open <full id>` | open that session's project: its server, page or folder |
| `claude-html --open-plan <full id>` | say what it would open, and open nothing |
| `claude-html --resume-session <full id>` | reopen the conversation in a terminal |
| `claude-html --resume-plan <full id>` | say which launcher and terminal, and run nothing |
| `claude-html --update-terminal` | the index's **run**: a terminal that asks, then runs `--update` on a yes, and stays open; at most one a minute |
| `claude-html --update-terminal-plan` | say which terminal and command, and run nothing |
| `claude-html --version` | which release this is (`-V`); also in `--doctor` |
| `claude-html --update` | go to the newest release ([Updating](#updating)); `--upgrade` too |
| `claude-html --update X.Y.Z` | go to that release (`vX.Y.Z` too); going back asks first, `--yes` (`-y`) does not |
| `claude-html --update list` | every release there is, newest first; changes nothing |
| `claude-html --update status` | what is installed, what is newest, and the daily check; changes nothing (`--check` too) |
| `claude-html --update on\|off` | the daily check for a new release, and its notice |
| `claude-html --help` | the short list (`-h`) |
| `./install.sh` | install with the defaults; safe to run again |
| `./install.sh --out DIR` / `--root DIR` | install with the pages or the projects root elsewhere |
| `./install.sh --no-guard` | install without the [guard](#guard) |
| `./install.sh --uninstall` | remove the command, the helper and the hooks |
| `./install.sh --help` | every option, with the defaults filled in |

## Updating

A clone of the release repository updates itself:

```bash
claude-html --update            # the newest release
claude-html --update 3.0.0      # that release (v3.0.0 too)
claude-html --update list       # every release, newest first, the installed one marked
claude-html --update status     # installed, newest, and when the daily check last ran
```

`--upgrade` is the same command. An update fetches the releases, shows the
changelog in between, moves the clone (to `main` for the newest, to the
tag for a given release), runs that release's `./install.sh` and builds:
pages made by another viewer, other masking rules or another dashboard
format are rebuilt by the build's own checks, and the count is said. Its
`After updating:` lines are repeated, and new hooks apply to Claude Code
sessions started afterwards. If the move, the install or the build fails,
the clone goes back where it was and its own install runs again.

It refuses, changing nothing, while a file of the release is changed or
staged here (commit, stash or undo it first), or while a save holds the
lock past a minute. The pages, `.cache/`, archives and anything else
untracked do not stop it and are left as they are. Only moves that refuse
to overwrite a change are used: never a reset or a clean.

**Going back** to an older release asks first: it may not read what a
newer one wrote, and before 3.0.0 cannot read the archives written since
(archive format 4). Releases before 3.1.0 have no `--update`; from one of
them, coming back is `git checkout main && git pull && ./install.sh`, and
the same updates a clone made before 3.1.0.

**A development checkout** — a clone whose HEAD is not a release, one that
does not come from the release repository, a copy that is not a clone —
is never fetched for nor moved: it is told to update with git.
`--update list` lists nothing there, and `status` says what it is without
fetching.

**The daily check.** At most once a day, from the part of a save nobody
waits on, the tool asks the release repository for its list of tags
(`git ls-remote`, five seconds at most, never a password prompt) and keeps
the answer in `~/.claude/.claude-html.update`. Nothing about you or your
conversations is sent; the pages themselves make no request. A newer
release is then a line on the index — copy the command, or run, which
opens a terminal on it — and after `claude-html` in the terminal, and is shown once in Claude Code after a reply — a Stop hook's
`systemMessage`, which Claude Code shows to you and does not give to
Claude. `--doctor` shows what it last saw.

| Setting | What it is | Default |
| ------- | ---------- | ------- |
| `CLAUDE_HTML_UPDATE_CHECK` | `off` (or `0`, `no`, `false`) stops the daily check and its notice; `claude-html --update` by hand still works | `on` |

```bash
claude-html --update off    # one line in the conf; on turns it back on
```

## The cache

`OUT/.cache/` holds what the last save made of each transcript, so the next
one reads only what was appended. It holds text, masked as the pages are.
**Deleting it is always safe**: the next save reads everything once.

## Linux

The same JavaScript runs under node, which Linux needs (14.14 or later).
The terminal a resume or an update opens, the trash, the confirmation
dialog and the `claude-html://` link handler (`delete`, `open`, `resume`
with a session id, `update` alone, and `limits` with its values) are picked per machine from what is
installed (when the command ends, the window stays, as an ordinary shell
in that folder); `$TERMINAL` wins over all terminals. See
[On Linux](DETAILS.md#on-linux) for the table.

## For the test suite

Knobs the tests set; nothing needs them day to day.

| Variable | What it does |
| -------- | ------------ |
| `CLAUDE_HTML_FORCE_NODE` | pretend there is no `osascript`, so node does everything |
| `CLAUDE_HTML_NO_REGISTER` | register nothing, and build no helper app in place: macOS registers any app it sees appear (set by the test runner itself) |
| `CLAUDE_HTML_UNAME` | what `uname -s` would say |
| `CLAUDE_HTML_OS_RELEASE` | the os-release file to read |
| `CLAUDE_HTML_PROC_VERSION` | the kernel version string, for WSL detection |
| `CLAUDE_HTML_NODE_DIRS` | the folders to look for node in, instead of the usual ones |
| `CLAUDE_HTML_TRASH` | a folder `--delete` moves into instead of the Trash |
| `CLAUDE_HTML_TRANSCRIPT` | the transcript a detached save was handed (set by the hook itself) |
| `CLAUDE_HTML_DETACHED` | marks the detached copy of a session-end save (set by the hook itself) |
| `CLAUDE_HTML_GUARD_TEST_LIMIT` | seconds the guard's dialog (and the stop and confirmation windows) waits, instead of ten minutes |
| `CLAUDE_HTML_TEST_NOW` | the time, in epoch seconds, that the limits take for now |
| `CLAUDE_HTML_STATUSLINE_TEST_LIMIT` | seconds the status line waits for the one it wraps, instead of three |
| `CLAUDE_HTML_UPDATE_REMOTE` | the release repository, a URL or a path, instead of GitHub's |
| `CLAUDE_HTML_UPDATE_LOCK_WAIT` | seconds an update waits for a save's lock, instead of 60 |
| `CLAUDE_HTML_LOCK_WAIT` | seconds a session-end save waits for the lock before saving without it, instead of 50 |
| `CLAUDE_HTML_TEST_JOBS` | how many suites `tests/run-all.sh` runs at once (default: half the CPUs, 2 to 6; `1` runs them one after another) |
| `CH_DRY` | print the command a terminal, opener or dialog would be given, and run nothing (what `--doctor` and the `-plan` commands show) |
