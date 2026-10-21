# Self-rendering pages: removing Python from claude-html

2026-09-10

## The problem

`claude-html` needs Python to build its pages. On macOS `/usr/bin/python3` is
`com.apple.dt.xcode_select.tool-shim` — a stub that offers to install the
developer tools on first use. So a new user cannot open their sessions until
they have downloaded several hundred megabytes of Xcode tooling.

The hooks are already free of this: `save-conversation.sh` archives each session
using `/usr/bin/osascript`, which is genuinely part of macOS. `install.sh` is
too. Only the renderer, `build-conversation-html.py`, still needs Python.

## Why JXA, and not one of the alternatives

`codesign` distinguishes Apple's own tools from Xcode stubs:

| | |
| --- | --- |
| Durable | `osascript`, `zsh`, `bash`, `sqlite3`, `plutil`, `awk`, `sed`, `curl` |
| Deprecated | `perl` 5.34, `ruby` — bundled runtimes Apple has said will be removed |
| Xcode stubs | `python3`, `git` |

JavaScript for Automation, run through `osascript`, is the only durable native
language capable of this work. Perl and Ruby would trade one dependency for one
with an expiry date.

Note in passing: `git` is a stub too, so a user without developer tools cannot
clone the repository at all. The README should offer the GitHub zip download as
an alternative. That is independent of this design.

## The shape of the change

Today the renderer does two separable things:

| | lines |
| --- | ---: |
| data work — parse, repair archive roles, pair tools with output, build the search index | 291 |
| presentation — render functions producing HTML | 207 |
| CSS and JS held inside Python string templates | ~467 |
| plumbing — config, manifest, pruning, `main` | 187 |

Porting all of it to JXA would be a like-for-like rewrite, and would require
implementing a Myers diff by hand, because `difflib.unified_diff` has no
JavaScript equivalent and 303 diffs are rendered across the current pages.

Instead, **the page renders itself**. A session page becomes:

- the conversation, as JSON, in a `<script type="application/json">`
- the viewer — CSS and JS — inlined from a static file that is authored
  normally and never generated
- an empty `<main>` that the viewer fills on load

The converter's only job is to produce the JSON and paste it into a template.
Every rendering decision — diffs, tool labels, escaping, the Conversation
toggle, prompt navigation — happens in the browser, where 200 lines of it
already run.

This means:

- the ~467 lines of CSS/JS stop being generated and become a real `.css` and
  `.js` file, no longer escaped inside Python string templates
- the 207 presentation lines move into the viewer, merging with the JS already
  there rather than duplicating it
- no diff algorithm is needed in the converter; the viewer computes diffs
- only the 291 lines of data work need porting to JXA, and that work is JSON
  manipulation, which is what JavaScript is good at

### Measured, not assumed

A prototype of the largest session (3,510 messages) was built and measured in
headless Chrome, three runs:

| | pre-rendered HTML | self-rendering |
| --- | --- | --- |
| file size | 4.8 MB | 4.8 MB |
| full page load | 5,196 ms | **2,774 ms** |
| JS render step | — | 109–132 ms |

Self-rendering is roughly twice as fast: parsing JSON and assigning one
`innerHTML` beats the HTML parser walking 4.8 MB of markup. Anchors matched
exactly at 3,508 on both sides, confirming the data pipeline is equivalent.

Safari, the browser guaranteed to exist and running JavaScriptCore rather than
V8, renders the same page in **137 ms** — statistically the same. The engine
difference does not matter for this workload.

## Architecture

```
~/.claude/projects/<dir>/<id>.jsonl   transcripts
<project>/.claude/.claude-conversations/*.json   archives
~/Downloads/conversations.json        claude.ai exports
        │
        ▼
   convert.js            JXA, run by osascript
   ├── reads a source, applies role repair and tool pairing
   ├── writes <id>.html   = page-template.html + embedded JSON
   ├── writes search/<id>.json
   └── writes .manifest.json
        │
        ▼
   index.html            = index-template.html + embedded manifest
   search-index.js       concatenated fragments, loaded on first keystroke
```

### Components and their boundaries

**`convert.js`** (JXA). Reads one source file, returns the message array the
viewer expects. Contains all the data work: role repair for old archives, tool
pairing, harness filtering, sidechain flagging, export parsing. Knows nothing
about HTML beyond substituting two placeholders in a template.

*Interface:* `convert(sourcePath, kind) -> {meta, messages}`. Depends on: the
file system, and the transcript formats.

**`viewer.js`** (plain browser JavaScript). Takes the message array and produces
the DOM. Contains all presentation: prose formatting, tool rendering, the diff
algorithm, anchors, the Conversation/Everything toggle, prompt navigation,
search-result rendering on the index.

*Interface:* pure functions from message objects to HTML strings, plus one
`render(messages, root)` entry point. Depends on: nothing. No file system, no
globals beyond the DOM node it is handed.

**`viewer.css`**. The styling that is currently a Python string. Authored as
CSS, with the theme tokens it already has.

**`page-template.html` / `index-template.html`**. Static skeletons with two
placeholders each: where the inlined viewer goes, and where the data goes.

**`build.sh`**. Thin: work out which sessions changed, call `convert.js` for
each, assemble `search-index.js` and `index.html`, prune. Replaces `main()`.

The boundary that matters: **`viewer.js` never touches a file and `convert.js`
never emits markup.** That is what makes the viewer testable in Node and the
converter testable with fixtures.

## Data contract

The JSON embedded in a page is the message array the Python renderer already
builds internally — this is not a new format, it is the existing one written
down:

```json
{
  "meta": {"id": "...", "project": "...", "cwd": "...", "kind": "transcript|archive|archive (inferred)|web",
           "title": "...", "mtime": 0},
  "messages": [
    {"role": "user",       "timestamp": "...", "side": false, "text": "..."},
    {"role": "assistant",  "timestamp": "...", "side": false, "text": "...",
     "thinking": "...", "tools": [{"name": "Edit", "input": {...}}]},
    {"role": "tool_result","timestamp": "...", "side": false, "text": "..."},
    {"role": "system",     "timestamp": "...", "text": "..."}
  ]
}
```

A message's index in the array is its anchor (`id="m7"`) and the number the
search index stores. That coupling already exists and must be preserved.

## Diffs

`render_diff` currently uses `difflib.unified_diff`. The viewer needs an
equivalent, and this is the part most likely to go wrong quietly: a diff
algorithm produces plausible output for any input, so a bad alignment does not
crash, it just attributes changes to the wrong lines.

**An earlier draft of this spec had the acceptance criterion wrong.** It said
the new diff must "agree line for line" with `difflib`. That is not a sound
test. `difflib` is `SequenceMatcher` — Ratcliff/Obershelp with an autojunk
heuristic — not Myers. Two different, equally correct diffs of the same pair can
align differently. Demonstrated on `one two three four` → `one three two four`,
`difflib` moves `three` up while a Myers implementation may just as correctly
move `two` down. Holding a correct implementation to that criterion would
produce failures that are not bugs, and invite "fixing" it until it is wrong.

The criterion is instead a property of the diff itself:

> **Applying the diff to `old_string` must reproduce `new_string` exactly.**

This is engine-independent, exhaustively checkable, and true of any correct
diff regardless of alignment. The corpus is every `Edit` ever made across the
sessions on disk — **303 real edits** — and the property has already been
verified to hold on all 303 for the current implementation, so it is known to
be a criterion the tool can meet rather than an aspiration.

Alignment quality is then a separate, weaker check: the number of changed lines
the new implementation produces must not exceed `difflib`'s by more than a small
margin on the same corpus. A diff can be correct but noisy; this catches that
without demanding identity.

**Fallback if quality proves poor.** The `Edit` tool gives us `old_string` and
`new_string` directly, so a diff is a presentation choice, not a necessity. If
a hand-written diff cannot be made both correct and tidy, the viewer renders
before-and-after blocks instead: less elegant, zero algorithmic risk, and still
answers "what changed". This is the escape hatch that keeps the diff off the
critical path of the whole migration.

## Testing

Three layers, and the first two run without Python:

1. **Viewer unit tests, in Node.** `viewer.js` is pure functions, so the current
   Python test suite ports directly: escaping, prose, tool labels, diffs,
   prompt numbering, archive role repair as it applies to rendering. Node is a
   developer dependency, never a user one.
2. **Converter tests, through `osascript`.** Fixture JSONL files in, expected
   JSON out. Covers the hyphenated-path bug, `isMeta` filtering, sidechain
   flagging, tool pairing, old-archive role repair.
3. **A differ, for the migration only.** For each of the 69 real sessions,
   render with Python and with the new pipeline, normalise whitespace, and
   compare the resulting DOM structure — element counts, anchors, prompt text,
   tool names, diff bodies. The port is not finished until this reports no
   differences it cannot explain.

The 51 existing Python tests stay green until the differ is clean, then are
ported and retired with the Python renderer.

## Migration

Deliberately incremental, with both renderers alive until the end.

1. Extract the 303-edit corpus and stand up the reconstruction test.
2. Write `viewer.js` + `viewer.css` and the templates. Feed them JSON produced
   by the *Python* code, so only presentation is under test.
3. Run the differ. Fix until clean.
4. Write `convert.js` in JXA. Feed the *existing* viewer. Run the differ again,
   now end to end.
5. Rewrite `build.sh`, `claude-html` and the `install.sh` build step to call it.
6. Delete `build-conversation-html.py` and port its tests.

Each step leaves a working tool. Steps 2–3 and 4 are the two substantial ones.

## What this does not change

Self-contained pages: a session page remains one file that opens on its own,
with no index and no data file beside it. This was checked — today's pages
reference nothing external except a navigation link to `index.html`. That
property survives, and is the reason for embedding the JSON rather than loading
it from a sibling file, which `file://` would block anyway.

Also unchanged: the archives and their location, the resume launchers, the
`.command` files, the config, the hooks, pruning rules, and the index and search
behaviour as the user experiences them.

## Failures are always visible

No failure path may be silent. Four exist, and each gets a way of being seen.

**A session that will not convert.** Today it is skipped with `continue` and
simply never appears — the only sign is a missing row nobody counts. Instead
every failure is recorded in `.build-errors.json` as session id, source path,
error and time, and the index renders a banner at the top listing them. A
session you cannot see is reported rather than absent.

**A build that partly failed.** `build.sh` exits non-zero and prints each
failure. The index still builds from what succeeded, so a single bad transcript
cannot cost you the other sixty-eight — but the banner says so.

**A hook that failed.** Hook output goes into the transcript where it is easy to
miss, so the archiving hook writes its own failures to the same
`.build-errors.json`. A session that failed to archive at exit is then reported
the next time you open the index, which is when you would care.

**A page that is stale.** Each page records the mtime of the source it was built
from. If the source is newer, the page says so in its header and the index marks
the row, rather than quietly showing an old conversation.

With this in place, rendering from the `SessionEnd` hook is no longer the
objection it was — a failure there surfaces on the index like any other. Whether
to do it is still deferred, but it stops being unsafe.

## Risks

**The diff.** Highest risk, mitigated by the reconstruction property, the
303-edit corpus, and the before/after fallback if quality disappoints.

**JXA is 4× slower at parsing** — 869 ms versus 210 ms on the largest
transcript. A full rebuild goes from about 2 s to perhaps 8 s. Acceptable
because builds are incremental and the hook renders each session as it ends, so
full rebuilds are rare. If it becomes annoying, the hook can render at session
end and the command becomes a repair tool.

**JXA's ObjC bridge is unforgiving.** A missing file returns a nil that is
truthy in JavaScript with an `undefined` `.js` — a bug already hit once in
`settings-hooks.js`. Every file read in `convert.js` goes through one guarded
helper, as it does now.

**Engine difference.** Tests run in Node (V8); production runs in
JavaScriptCore. For ES5-era code the risk is small, but the differ in step 3
runs the real pipeline, which closes it.

**Viewing with JavaScript disabled** shows an empty page. Acceptable: search,
the Conversation toggle and prompt navigation already require JavaScript.

## Open questions

1. Should the `SessionEnd` hook render the page directly, making `claude-html`
   optional? Safe now that failures surface on the index, but deferred: it adds
   work to session exit for no benefit the command does not already give.
2. `search-index.js` is 3.6 MB and rebuilt from fragments on every run. It could
   be assembled incrementally. Out of scope here.
