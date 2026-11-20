# Setting up claude-html

Every setting and every way to set the tool up, in one place. How it all
works is in [DETAILS.md](DETAILS.md).

- [How a setting is decided](#how-a-setting-is-decided)
- [Where things go](#where-things-go)
- [Engine](#engine)
- [Dashboard weeks](#dashboard-weeks)
- [claude.ai exports](#claudeai-exports)
- [Secrets](#secrets)
- [Guard](#guard)
- [Hooks](#hooks)
- [Transcript cleanup](#transcript-cleanup)
- [Commands](#commands)
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

```bash
CLAUDE_HTML_ENGINE=osascript   # in the conf, or the environment
```

- A node counts only if it runs and is 14.14 or later. It is looked for on
  `PATH`, then in `/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin`,
  `~/.local/bin` and the versions fnm, nvm, Volta, asdf and mise installed —
  never their shims. Each is tried from `/` with five seconds to answer.
- A value that is neither, or names one this machine lacks, is set aside:
  the save goes ahead with the other, and `--doctor` shows a note.
- Deleting, opening and resuming stay on `osascript` on a Mac either way.

`claude-html --doctor` shows the engine and why it was picked, the system,
desktop, terminal, trash, dialog and link handler, the pages and projects
folders, and the [redaction](#secrets).

## Dashboard weeks

| Variable | What it is | Default |
| -------- | ---------- | ------- |
| `CLAUDE_HTML_WEEK_RESET` | when your plan's weekly allowance resets, so the dashboard's weeks match the ones you are billed for: a day and a local hour | calendar weeks, from Monday 00:00 |

```bash
CLAUDE_HTML_WEEK_RESET="tue 09:00"    # also "thu 17", "Friday 8:30"
```

The installer offers this line commented out. One it cannot read falls back
to Mondays.

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

On a match it stops and asks. With someone at the screen, in a window:

![The guard's dialog: where, what was found, four choices](guard-dialog.png)

| Answer | Prompt | Command |
| ------ | ------ | ------- |
| **Cancel** (picked already; Return, Escape) | nothing is sent | not run; Claude is told to read it from `~/.my.cnf`, an env var or a credential helper |
| **Allow once** | sent this time; still masked in saved pages; asked again next time | run this time |
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

## Hooks

`./install.sh` adds these hooks to `~/.claude/settings.json`:

| Hook | When | What it does |
| ---- | ---- | ------------ |
| `Stop` | after every reply | saves in the background, so the reply is never held up; gives way to a save already running |
| `SessionEnd` | when a session ends | saves, detached so quitting is instant, and waits its turn |
| `PreCompact` (`auto`, `manual`) | before a compaction | saves before the context is cut |
| `UserPromptSubmit` | before a prompt is sent | the [guard](#guard) |
| `PreToolUse` (`Bash`) | before a command runs | the [guard](#guard) |

They are added beside the hooks you have; yours are read, never rewritten.
`./install.sh --no-guard` leaves the guard's two out and turns it off.
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
| `claude-html --delete <full id>` | the index's bin: move a conversation to the Trash, after asking |
| `claude-html --delete-plan <full id>` | say what `--delete` would move, and move nothing |
| `claude-html --delete <full id> --yes` | the same without asking (`-y`) |
| `claude-html --open <full id>` | open that session's project: its server, page or folder |
| `claude-html --open-plan <full id>` | say what it would open, and open nothing |
| `claude-html --resume-session <full id>` | reopen the conversation in a terminal |
| `claude-html --resume-plan <full id>` | say which launcher and terminal, and run nothing |
| `claude-html --help` | the short list (`-h`) |
| `./install.sh` | install with the defaults; safe to run again |
| `./install.sh --out DIR` / `--root DIR` | install with the pages or the projects root elsewhere |
| `./install.sh --no-guard` | install without the [guard](#guard) |
| `./install.sh --uninstall` | remove the command, the helper and the hooks |
| `./install.sh --help` | every option, with the defaults filled in |

## The cache

`OUT/.cache/` holds what the last save made of each transcript, so the next
one reads only what was appended. It holds text, masked as the pages are.
**Deleting it is always safe**: the next save reads everything once.

## Linux

The same JavaScript runs under node, which Linux needs (14.14 or later).
The terminal a resume opens, the trash, the confirmation dialog and the
`claude-html://` link handler are picked per machine from what is
installed; `$TERMINAL` wins over all terminals. See
[On Linux](DETAILS.md#on-linux) for the table.

## For the test suite

Knobs the tests set; nothing needs them day to day.

| Variable | What it does |
| -------- | ------------ |
| `CLAUDE_HTML_FORCE_NODE` | pretend there is no `osascript`, so node does everything |
| `CLAUDE_HTML_NO_REGISTER` | never register a link handler or helper app (the tests' temp folders) |
| `CLAUDE_HTML_UNAME` | what `uname -s` would say |
| `CLAUDE_HTML_OS_RELEASE` | the os-release file to read |
| `CLAUDE_HTML_PROC_VERSION` | the kernel version string, for WSL detection |
| `CLAUDE_HTML_NODE_DIRS` | the folders to look for node in, instead of the usual ones |
| `CLAUDE_HTML_TRASH` | a folder `--delete` moves into instead of the Trash |
| `CLAUDE_HTML_TRANSCRIPT` | the transcript a detached save was handed (set by the hook itself) |
| `CLAUDE_HTML_DETACHED` | marks the detached copy of a session-end save (set by the hook itself) |
| `CLAUDE_HTML_GUARD_TEST_LIMIT` | seconds the guard's dialog waits, instead of ten minutes |
