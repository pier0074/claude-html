// Delete one conversation and everything that belongs to it — or, for a
// claude.ai chat, hide it from the index, since its real copy lives on
// claude.ai and the next export would only bring a deleted one back.
//
//   osascript -l JavaScript delete.js '{"id":"…","mode":"plan"|"apply",
//                                       "root":"…","out":"…"}'
//   node delete.js '{…, "trashMethod":"gio"|"kioclient"|"kioclient5"|"trash-put"|"spec"}'
//
// On macOS the Finder's Trash takes things; elsewhere whichever tool
// platform.sh found for it, or failing all of them the freedesktop.org Trash
// spec, done here by hand.
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
  var P = platform();
  var env = P.env;

  var HOME = env("HOME") || P.home();
  var ROOT = opt.root || HOME + "/Sites";
  var OUT = opt.out || ROOT + "/claude-html";
  var HIDDEN = opt.hidden || HOME + "/.claude/claude-html.hidden";
  var ID = String(opt.id || "");
  var SESSION_ID = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;
  if (!SESSION_ID.test(ID)) throw new Error("not a session id: " + ID);

  // ── files ───────────────────────────────────────────────────────────
  var exists = P.exists, list = P.list, read = P.read, write = P.write, size = P.size;

  function tilde(p) { return p.indexOf(HOME) === 0 ? "~" + p.slice(HOME.length) : p; }
  function clean(s) { return String(s == null ? "" : s).replace(/[\t\r\n]+/g, " ").trim(); }
  function basename(p) { return p.replace(/\/+$/, "").split("/").pop(); }

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
  // Every archive of it, including stray copies in other projects: wherever
  // the build looks for them, which for a nested project is the folder the
  // session worked in and the list of every folder that has held archives.
  var archiveDirs = [ROOT].concat(list(ROOT).map(function (d) { return ROOT + "/" + d; }));
  if (entry && entry.cwd) archiveDirs.push(entry.cwd);
  (read(HOME + "/.claude/claude-html.archives") || "").split("\n").forEach(function (l) {
    l = l.replace(/\/+$/, "");
    if (l.charAt(0) === "/") archiveDirs.push(l);
  });
  var seenDirs = {};
  archiveDirs.forEach(function (d) {
    d = String(d).replace(/\/+$/, "");
    if (seenDirs[d]) return;
    seenDirs[d] = true;
    add(d + "/.claude/.claude-conversations/" + ID + ".json", "archive");
  });
  var claude = items.length > 0;

  // What this tool generated from it.
  add(OUT + "/sessions/" + ID + ".html", "page");
  add(OUT + "/sessions/" + ID, "sub-agent pages");
  add(OUT + "/search/" + ID + ".js", "search file");
  add(OUT + "/search/" + ID + ".json", "search file");
  list(OUT + "/resume").forEach(function (f) {
    var m = /-([^-]+-[^-]+-[^-]+-[^-]+-[^-]+)\.(command|sh|desktop)$/.exec(f);
    if (m && m[1] === ID) add(OUT + "/resume/" + f, "resume launcher");
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
  function alive(pid) { return /^\d+$/.test(String(pid)) && P.alive(+pid); }
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
      P.mkdirs(opt.trash);
      ok = P.move(p, opt.trash + "/" + (++n) + "-" + basename(p));
    } else {
      ok = P.trash(p, String(opt.trashMethod || ""));
    }
    if (ok === true) moved++;
    else failed.push(tilde(p) + (typeof ok === "string" ? " (" + ok + ")" : ""));
  }

  // Refused before anything moves: a method this does not know is a mistake
  // upstream, and half a conversation in the trash is worse than none.
  if (!opt.trash && !P.canTrash(String(opt.trashMethod || ""))) {
    throw new Error("no way to move things to the trash here (" +
                    (opt.trashMethod || "none given") + ")");
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
      P.copyMode(HISTORY, tmp);
      if (size(HISTORY) !== before) {             // written to meanwhile: start over
        P.remove(tmp);
        P.remove(saved);
        continue;
      }
      // A rename within one folder is atomic: anyone reading the history sees
      // the old file or the new one, never half of either. (replaceItemAtURL
      // would do the same, but a JavaScript null for its backup name arrives
      // as NSNull, and it crashes asking that for its length.)
      if (!P.replace(tmp, HISTORY)) {
        P.remove(tmp);
        P.remove(saved);
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

// ── the platform ──────────────────────────────────────────────────────
// Everything either engine is asked for. osascript on macOS reaches the
// Finder's Trash through NSFileManager; node, elsewhere, uses the trash tool
// it was told about, or the freedesktop.org spec by hand.
function platform() {
  "use strict";
  if (typeof $ !== "undefined") {
    var fm = $.NSFileManager.defaultManager;
    var shell = Application.currentApplication();
    shell.includeStandardAdditions = true;
    var quote = function (p) { return "'" + String(p).replace(/'/g, "'\\''") + "'"; };
    var exists = function (p) { return fm.fileExistsAtPath(p); };
    return {
      env: function (name) {
        var v = $.NSProcessInfo.processInfo.environment.objectForKey(name);
        try { return v && v.js ? v.js : null; } catch (e) { return null; }
      },
      home: function () { return $.NSHomeDirectory().js; },
      exists: exists,
      list: function (dir) {
        if (!exists(dir)) return [];
        var items = fm.contentsOfDirectoryAtPathError(dir, null);
        if (!items) return [];
        return $.CFMakeCollectable(items).js.map(function (x) { return x.js; }).sort();
      },
      read: function (path) {
        if (!exists(path)) return null;
        try {
          var s = $.NSString.stringWithContentsOfFileEncodingError(path, 4, null);
          var text = s ? $.CFMakeCollectable(s).js : null;
          return typeof text === "string" ? text : null;
        } catch (e) { return null; }
      },
      write: function (path, text) {
        return $.NSString.alloc.initWithUTF8String(text)
          .writeToFileAtomicallyEncodingError(path, true, 4, null);
      },
      size: function (path) {
        var at = fm.attributesOfItemAtPathError(path, null);
        return at ? $.CFMakeCollectable(at).js.NSFileSize.js : -1;
      },
      copyMode: function (from, to) {
        var at = fm.attributesOfItemAtPathError(from, null);
        var perm = at ? $.CFMakeCollectable(at).js.NSFilePosixPermissions : null;
        if (perm) fm.setAttributesOfItemAtPathError({ NSFilePosixPermissions: perm.js || perm }, to, null);
      },
      remove: function (p) { fm.removeItemAtPathError(p, null); },
      // A rename within one folder is atomic: anyone reading the history sees
      // the old file or the new one, never half of either. (replaceItemAtURL
      // would do the same, but a JavaScript null for its backup name arrives
      // as NSNull, and it crashes asking that for its length.)
      replace: function (from, to) {
        try { shell.doShellScript("/bin/mv -f " + quote(from) + " " + quote(to)); return true; }
        catch (e) { return false; }
      },
      alive: function (pid) {
        try { shell.doShellScript("/bin/kill -0 " + pid); return true; } catch (e) { return false; }
      },
      mkdirs: function (dir) {
        fm.createDirectoryAtPathWithIntermediateDirectoriesAttributesError(dir, true, $(), null);
      },
      move: function (from, to) { return !!fm.moveItemAtPathToPathError(from, to, null); },
      canTrash: function () { return true; },
      trash: function (p) {
        return !!fm.trashItemAtURLResultingItemURLError($.NSURL.fileURLWithPath(p), null, null);
      }
    };
  }

  var nfs = require("fs"), npath = require("path"), cp = require("child_process");
  var stat = function (p) { try { return nfs.lstatSync(p); } catch (e) { return null; } };
  var env = function (name) { return process.env[name] || null; };
  var move = function (from, to) {
    try { nfs.renameSync(from, to); return true; } catch (e) { return false; }
  };
  // A tool, run with its arguments as they are: no shell sees the path.
  var tool = function (cmd, args) {
    try { cp.execFileSync(cmd, args, { stdio: "ignore", timeout: 60000 }); return true; }
    catch (e) { return false; }
  };

  // The freedesktop.org Trash spec, home trash only: the file goes into
  // Trash/files under a name not yet taken, and Trash/info gets a note of
  // where it came from and when, which is what every desktop's restore reads.
  // A file on another filesystem would need that filesystem's own trash
  // folder; rather than copy it across and delete the original, it is refused.
  function specTrash(p) {
    var home = (env("XDG_DATA_HOME") || require("os").homedir() + "/.local/share") + "/Trash";
    var files = home + "/files", info = home + "/info";
    try {
      nfs.mkdirSync(files, { recursive: true, mode: 448 });
      nfs.mkdirSync(info, { recursive: true, mode: 448 });
    } catch (e) { return "cannot make " + home; }
    var st = stat(p), tst = stat(files);
    if (!st) return "it is gone already";
    if (!tst || st.dev !== tst.dev) return "it is on another filesystem than " + home;
    var abs = npath.resolve(p);
    var base = npath.basename(abs), ext = "";
    var dot = base.lastIndexOf(".");
    if (dot > 0 && !st.isDirectory()) { ext = base.slice(dot); base = base.slice(0, dot); }
    var d = new Date();
    function two(n) { return (n < 10 ? "0" : "") + n; }
    var when = d.getFullYear() + "-" + two(d.getMonth() + 1) + "-" + two(d.getDate()) + "T" +
      two(d.getHours()) + ":" + two(d.getMinutes()) + ":" + two(d.getSeconds());
    // The info file is created first and exclusively: it is what reserves the
    // name, so two deletes at once can never pick the same one.
    var body = "[Trash Info]\nPath=" + encodeURIComponent(abs).replace(/%2F/g, "/") +
      "\nDeletionDate=" + when + "\n";
    for (var i = 1; i < 10000; i++) {
      var name = i === 1 ? base + ext : base + "." + i + ext;
      if (stat(files + "/" + name)) continue;
      try { nfs.writeFileSync(info + "/" + name + ".trashinfo", body, { flag: "wx", mode: 384 }); }
      catch (e) { if (e.code === "EEXIST") continue; return "cannot write to " + info; }
      if (move(abs, files + "/" + name)) return true;
      try { nfs.unlinkSync(info + "/" + name + ".trashinfo"); } catch (e) {}
      return "could not move it into " + files;
    }
    return "too many things of that name in the trash";
  }

  var METHODS = {
    gio: function (p) { return tool("gio", ["trash", "--", p]); },
    kioclient: function (p) { return tool("kioclient", ["--noninteractive", "move", p, "trash:/"]); },
    kioclient5: function (p) { return tool("kioclient5", ["--noninteractive", "move", p, "trash:/"]); },
    "trash-put": function (p) { return tool("trash-put", ["--", p]); },
    spec: specTrash
  };

  return {
    env: env,
    home: function () { return require("os").homedir(); },
    exists: function (p) { return !!stat(p); },
    list: function (dir) { try { return nfs.readdirSync(dir).sort(); } catch (e) { return []; } },
    read: function (p) { try { return nfs.readFileSync(p, "utf8"); } catch (e) { return null; } },
    write: function (p, text) {
      var tmp = p + ".tmp" + process.pid;
      try { nfs.writeFileSync(tmp, text, "utf8"); nfs.renameSync(tmp, p); return true; }
      catch (e) { try { nfs.unlinkSync(tmp); } catch (e2) {} return false; }
    },
    size: function (p) { var st = stat(p); return st ? st.size : -1; },
    copyMode: function (from, to) {
      var st = stat(from);
      if (st) { try { nfs.chmodSync(to, st.mode & 4095); } catch (e) {} }
    },
    remove: function (p) { try { nfs.rmSync(p, { recursive: true, force: true }); } catch (e) {} },
    replace: move,
    alive: function (pid) {
      try { process.kill(pid, 0); return true; }
      catch (e) { return e.code === "EPERM"; }
    },
    mkdirs: function (dir) { try { nfs.mkdirSync(dir, { recursive: true }); } catch (e) {} },
    move: move,
    canTrash: function (m) { return Object.prototype.hasOwnProperty.call(METHODS, m); },
    trash: function (p, m) {
      if (!Object.prototype.hasOwnProperty.call(METHODS, m)) return "no trash method";
      // A tool that said yes but left the file where it was did not trash it.
      var r = METHODS[m](p);
      return r === true && stat(p) ? "still there afterwards" : r;
    }
  };
}

// osascript calls run() by itself; node has to be asked.
if (typeof $ === "undefined" && typeof require !== "undefined" &&
    typeof module !== "undefined" && require.main === module) {
  try {
    process.stdout.write(run(process.argv.slice(2)) + "\n");
  } catch (e) {
    process.stderr.write(String(e.message || e) + "\n");
    process.exit(1);
  }
}
