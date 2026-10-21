// Delete one conversation and everything that belongs to it — or, for a
// claude.ai chat, hide it from the index, since its real copy lives on
// claude.ai and the next export would only bring a deleted one back.
//
//   osascript -l JavaScript delete.js '{"id":"…","mode":"plan"|"apply",
//                                       "root":"…","out":"…"}'
//
// Nothing is destroyed outright. Files go to the Trash, where Finder's Put
// Back restores them, and the prompts taken out of the up-arrow history go
// there as well, as a file of their own. A conversation still open in Claude
// Code is refused: it would only write its transcript straight back.
//
// The plan is printed as tab-separated lines, so both bash and the AppleScript
// helper can read it without a JSON parser:
//   TITLE <title>   ACTION trash|hide|refuse   REASON <why>
//   ITEM <path> <what>   HISTORY <prompts in up-arrow history>

function run(argv) {
  "use strict";

  var opt = JSON.parse(argv[0] || "{}");
  var fm = $.NSFileManager.defaultManager;

  function env(name) {
    var v = $.NSProcessInfo.processInfo.environment.objectForKey(name);
    try { return v && v.js ? v.js : null; } catch (e) { return null; }
  }

  var HOME = env("HOME") || $.NSHomeDirectory().js;
  var ROOT = opt.root || HOME + "/Sites";
  var OUT = opt.out || ROOT + "/claude-html";
  var HIDDEN = opt.hidden || HOME + "/.claude/claude-html.hidden";
  var ID = String(opt.id || "");
  var SESSION_ID = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;
  if (!SESSION_ID.test(ID)) throw new Error("not a session id: " + ID);

  // ── files ───────────────────────────────────────────────────────────
  function exists(p) { return fm.fileExistsAtPath(p); }

  function list(dir) {
    if (!exists(dir)) return [];
    var items = fm.contentsOfDirectoryAtPathError(dir, null);
    if (!items) return [];
    return $.CFMakeCollectable(items).js.map(function (x) { return x.js; }).sort();
  }

  function read(path) {
    if (!exists(path)) return null;
    try {
      var s = $.NSString.stringWithContentsOfFileEncodingError(path, 4, null);
      var text = s ? $.CFMakeCollectable(s).js : null;
      return typeof text === "string" ? text : null;
    } catch (e) { return null; }
  }

  function write(path, text) {
    return $.NSString.alloc.initWithUTF8String(text)
      .writeToFileAtomicallyEncodingError(path, true, 4, null);
  }

  function size(path) {
    var at = fm.attributesOfItemAtPathError(path, null);
    return at ? $.CFMakeCollectable(at).js.NSFileSize.js : -1;
  }

  function tilde(p) { return p.indexOf(HOME) === 0 ? "~" + p.slice(HOME.length) : p; }
  function clean(s) { return String(s == null ? "" : s).replace(/[\t\r\n]+/g, " ").trim(); }
  function basename(p) { return p.replace(/\/+$/, "").split("/").pop(); }
  function quote(p) { return "'" + String(p).replace(/'/g, "'\\''") + "'"; }

  // ── what belongs to it ──────────────────────────────────────────────
  var manifest = {};
  try { manifest = JSON.parse(read(OUT + "/.manifest.json") || "{}"); } catch (e) {}
  var entry = manifest[ID] || null;

  var items = [];
  function add(p, what) { if (exists(p)) items.push({ path: p, what: what }); }

  // Claude Code's own records of it.
  list(HOME + "/.claude/projects").forEach(function (d) {
    add(HOME + "/.claude/projects/" + d + "/" + ID + ".jsonl", "transcript");
    add(HOME + "/.claude/projects/" + d + "/" + ID, "sub-agent transcripts");
  });
  add(HOME + "/.claude/file-history/" + ID, "snapshots of files it edited");
  add(HOME + "/.claude/session-env/" + ID, "session environment");
  list(HOME + "/.claude/todos").forEach(function (f) {
    if (f.indexOf(ID) === 0) add(HOME + "/.claude/todos/" + f, "todo list");
  });
  // Every archive of it, including stray copies in other projects.
  list(ROOT).forEach(function (d) {
    add(ROOT + "/" + d + "/.claude/.claude-conversations/" + ID + ".json", "archive");
  });
  var claude = items.length > 0;

  // What this tool generated from it.
  add(OUT + "/sessions/" + ID + ".html", "page");
  add(OUT + "/sessions/" + ID, "sub-agent pages");
  add(OUT + "/search/" + ID + ".js", "search file");
  add(OUT + "/search/" + ID + ".json", "search file");
  list(OUT + "/resume").forEach(function (f) {
    if (f.slice(-(ID.length + ".command".length)) === ID + ".command") {
      add(OUT + "/resume/" + f, "resume launcher");
    }
  });
  add(OUT + "/.archive-errors/" + ID + ".json", "archive error note");

  var web = !claude && !!entry && entry.kind === "web";

  // Its prompts in the up-arrow history, which every session shares.
  var HISTORY = HOME + "/.claude/history.jsonl";
  function split(text) {
    var keep = [], gone = [];
    text.split("\n").forEach(function (line) {
      if (!line) return;
      var o = null;
      try { o = JSON.parse(line); } catch (e) {}
      if (o && o.sessionId === ID) gone.push(line); else keep.push(line);
    });
    return { keep: keep, gone: gone };
  }
  var historyCount = claude ? split(read(HISTORY) || "").gone.length : 0;

  // ── is it still open? ───────────────────────────────────────────────
  var shell = Application.currentApplication();
  shell.includeStandardAdditions = true;
  function alive(pid) {
    if (!/^\d+$/.test(String(pid))) return false;
    try { shell.doShellScript("/bin/kill -0 " + pid); return true; } catch (e) { return false; }
  }
  var running = null;
  list(HOME + "/.claude/sessions").forEach(function (f) {
    if (!/\.json$/.test(f)) return;
    var o = null;
    try { o = JSON.parse(read(HOME + "/.claude/sessions/" + f)); } catch (e) {}
    if (o && o.sessionId === ID && alive(o.pid)) running = o;
  });

  var title = clean(entry && (entry.title || entry.project)) || ID;
  var action = running ? "refuse" : claude ? "trash" : web ? "hide" : "refuse";
  var reason = running
    ? "This conversation is still open in Claude Code. Close it first - " +
      "otherwise it would write its transcript straight back."
    : action === "refuse" ? "Nothing on this Mac belongs to that conversation." : "";

  if (opt.mode !== "apply") {
    var plan = ["TITLE\t" + title, "ACTION\t" + action];
    if (reason) plan.push("REASON\t" + reason);
    items.forEach(function (i) { plan.push("ITEM\t" + tilde(i.path) + "\t" + i.what); });
    plan.push("HISTORY\t" + historyCount);
    return plan.join("\n");
  }

  // ── apply ───────────────────────────────────────────────────────────
  if (action === "refuse") throw new Error(reason);

  if (action === "hide") {
    var cur = read(HIDDEN) || "";
    if (cur.split("\n").indexOf(ID) < 0) {
      write(HIDDEN, cur + (cur && cur.slice(-1) !== "\n" ? "\n" : "") + ID + "\n");
    }
    return "DONE\t0\t0\t1";
  }

  // The Trash, or a plain directory standing in for it — the tests use one,
  // so running them never fills the real Trash.
  var moved = 0, failed = [], n = 0;
  function toTrash(p) {
    var ok;
    if (opt.trash) {
      fm.createDirectoryAtPathWithIntermediateDirectoriesAttributesError(opt.trash, true, $(), null);
      ok = fm.moveItemAtPathToPathError(p, opt.trash + "/" + (++n) + "-" + basename(p), null);
    } else {
      ok = fm.trashItemAtURLResultingItemURLError($.NSURL.fileURLWithPath(p), null, null);
    }
    if (ok) moved++; else failed.push(tilde(p));
  }

  items.forEach(function (i) { toTrash(i.path); });

  // The history is a file Claude Code appends to while it runs, so it is
  // rewritten only if it did not grow while this read it — otherwise a prompt
  // typed in another session at that moment would be lost. The removed lines
  // go to the Trash as a file, so they can be recovered like everything else.
  function removeHistory() {
    for (var attempt = 0; attempt < 5; attempt++) {
      var before = size(HISTORY);
      var text = read(HISTORY);
      if (text === null) return 0;
      var parts = split(text);
      if (!parts.gone.length) return 0;
      var saved = HOME + "/.claude/claude-html removed history " + ID.slice(0, 8) + ".jsonl";
      var tmp = HISTORY + ".claude-html-" + Date.now();
      write(saved, parts.gone.join("\n") + "\n");
      write(tmp, parts.keep.length ? parts.keep.join("\n") + "\n" : "");
      var at = fm.attributesOfItemAtPathError(HISTORY, null);
      var perm = at ? $.CFMakeCollectable(at).js.NSFilePosixPermissions : null;
      if (perm) fm.setAttributesOfItemAtPathError({ NSFilePosixPermissions: perm.js || perm }, tmp, null);
      if (size(HISTORY) !== before) {             // written to meanwhile: start over
        fm.removeItemAtPathError(tmp, null);
        fm.removeItemAtPathError(saved, null);
        continue;
      }
      // A rename within one folder is atomic: anyone reading the history sees
      // the old file or the new one, never half of either. (replaceItemAtURL
      // would do the same, but a JavaScript null for its backup name arrives
      // as NSNull, and it crashes asking that for its length.)
      try {
        shell.doShellScript("/bin/mv -f " + quote(tmp) + " " + quote(HISTORY));
      } catch (e) {
        fm.removeItemAtPathError(tmp, null);
        fm.removeItemAtPathError(saved, null);
        throw new Error("could not rewrite history.jsonl; it was left as it was");
      }
      toTrash(saved);
      return parts.gone.length;
    }
    throw new Error("history.jsonl kept changing while it was being edited; it was left as it was");
  }
  // The files have already moved by now, so a history that cannot be edited
  // must not turn the whole thing into an error: it is reported on its own,
  // and the caller still rebuilds the index to match what did happen.
  var removed = 0;
  if (claude) {
    try { removed = removeHistory(); }
    catch (e) { failed.push("the up-arrow history: " + String(e.message || e)); }
  }

  var out = ["DONE\t" + moved + "\t" + removed + "\t0"];
  failed.forEach(function (p) { out.push("FAILED\t" + p); });
  return out.join("\n");
}
