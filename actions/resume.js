// Which launcher resumes a conversation — looked up, never taken on trust.
//
//   osascript -l JavaScript resume.js '{"id":"…","out":"…","ext":".command"}'
//   node resume.js '{"id":"…","out":"…","ext":".sh"}'
//
// The id has to be a session id, in the index's manifest, and a conversation
// Claude Code can resume (a claude.ai chat has no folder to resume it in). The
// launcher is the one convert.js wrote for it into resume/, found by its name,
// so the path is always one this tool built.
//
// Prints two lines, tab-separated so bash can read them:
//   LAUNCHER <path>     the file to open
//   COMMAND  <command>  what to type instead, where nothing can open it

function run(argv) {
  "use strict";

  var opt = JSON.parse(argv[0] || "{}");

  // ── the platform ────────────────────────────────────────────────────
  var read, list;
  if (typeof $ !== "undefined") {
    var fm = $.NSFileManager.defaultManager;
    read = function (path) {
      if (!fm.fileExistsAtPath(path)) return null;
      try {
        var s = $.NSString.stringWithContentsOfFileEncodingError(path, 4, null);
        var text = s ? $.CFMakeCollectable(s).js : null;
        return typeof text === "string" ? text : null;
      } catch (e) { return null; }
    };
    list = function (dir) {
      if (!fm.fileExistsAtPath(dir)) return [];
      var items = fm.contentsOfDirectoryAtPathError(dir, null);
      if (!items) return [];
      return $.CFMakeCollectable(items).js.map(function (x) { return x.js; }).sort();
    };
  } else {
    var nfs = require("fs");
    read = function (path) {
      try { return nfs.readFileSync(path, "utf8"); } catch (e) { return null; }
    };
    list = function (dir) {
      try { return nfs.readdirSync(dir).sort(); } catch (e) { return []; }
    };
  }

  var OUT = String(opt.out || "");
  var ID = String(opt.id || "");
  var EXT = opt.ext === ".command" ? ".command" : ".sh";
  var SESSION_ID = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;
  if (!SESSION_ID.test(ID)) throw new Error("not a session id: " + ID);
  if (!OUT) throw new Error("no pages folder given");

  var manifest = {};
  try { manifest = JSON.parse(read(OUT + "/.manifest.json") || "{}"); } catch (e) {}
  var entry = Object.prototype.hasOwnProperty.call(manifest, ID) ? manifest[ID] : null;
  if (!entry) throw new Error("that conversation is not in the index");
  if (entry.kind === "web" || !entry.cwd) {
    throw new Error("a claude.ai chat has no folder here to resume it in");
  }

  var name = null;
  list(OUT + "/resume").forEach(function (f) {
    if (f.slice(-(ID.length + 1 + EXT.length)) === "-" + ID + EXT) name = f;
  });
  if (!name) throw new Error("its launcher is missing - run claude-html to build it again");

  function quote(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'"; }
  var launcher = OUT + "/resume/" + name;
  // A folder with a line break in it cannot be shown on one line; running its
  // launcher does the same thing.
  var command = /[\r\n\t]/.test(entry.cwd)
    ? "sh " + quote(launcher)
    : "cd -- " + quote(entry.cwd) + " && claude --resume " + ID;
  return "LAUNCHER\t" + launcher + "\nCOMMAND\t" + command;
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
