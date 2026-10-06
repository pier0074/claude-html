// Add or remove this tool's hooks in ~/.claude/settings.json.
//
// Run by install.sh through osascript on macOS and node elsewhere, so that
// installing needs nothing beyond what the machine already has. Everything here is deliberately conservative:
// the file belongs to the user, may contain settings this tool knows nothing
// about, and must survive being read and written by it.
//
//   osascript -l JavaScript settings-hooks.js <settings.json> <scripts dir> add
//   osascript -l JavaScript settings-hooks.js <settings.json> <scripts dir> remove

function run(argv) {
  var settingsPath = argv[0], here = argv[1], mode = argv[2];
  // save-session-link.sh is gone, but an early install may still have its
  // hook in settings.json; recognising the name lets remove clean it up.
  var OURS = ["save-conversation.sh", "save-session-link.sh"];

  var JXA = typeof $ !== "undefined";

  function readFile(path) {
    if (!JXA) {
      try { return require("fs").readFileSync(path, "utf8"); } catch (e) { return null; }
    }
    // A missing file yields an ObjC nil that is truthy in JS and whose .js is
    // undefined, so check it exists first and guard the unwrap.
    if (!$.NSFileManager.defaultManager.fileExistsAtPath(path)) return null;
    try {
      var s = $.NSString.stringWithContentsOfFileEncodingError(path, 4, null);
      var text = s ? $.CFMakeCollectable(s).js : null;
      return (typeof text === "string") ? text : null;
    } catch (e) {
      return null;
    }
  }

  function writeFile(path, text) {
    if (!JXA) {
      var nfs = require("fs"), npath = require("path");
      try {
        nfs.mkdirSync(npath.dirname(path), { recursive: true });
        var tmp = path + ".tmp" + process.pid;
        nfs.writeFileSync(tmp, text, "utf8");
        nfs.renameSync(tmp, path);
        return true;
      } catch (e) { return false; }
    }
    var dir = $.NSString.alloc.initWithUTF8String(path).stringByDeletingLastPathComponent;
    $.NSFileManager.defaultManager
      .createDirectoryAtPathWithIntermediateDirectoriesAttributesError(dir, true, $(), null);
    return $.NSString.alloc.initWithUTF8String(text)
      .writeToFileAtomicallyEncodingError(path, true, 4, null);
  }

  var data = {};
  var raw = readFile(settingsPath);
  if (raw !== null && raw.trim() !== "") {
    try {
      data = JSON.parse(raw);
    } catch (e) {
      // Someone else's file that this tool cannot parse is left exactly as it
      // is. Refusing to write is the only safe move.
      return "unparseable";
    }
    if (typeof data !== "object" || data === null || Array.isArray(data)) return "unparseable";
  }

  var hooks = data.hooks || {};
  function groups(event) { return hooks[event] || []; }
  function isOurs(cmd) {
    cmd = cmd || "";
    return OURS.some(function (o) { return cmd.indexOf(o) > -1; });
  }

  if (mode === "remove") {
    var removed = 0;
    Object.keys(hooks).forEach(function (event) {
      var kept = [];
      groups(event).forEach(function (g) {
        var before = (g.hooks || []).length;
        // A group may hold somebody else's hook alongside ours; keep the group
        // when anything of theirs survives.
        g.hooks = (g.hooks || []).filter(function (h) { return !isOurs(h.command); });
        removed += before - g.hooks.length;
        if (g.hooks.length) kept.push(g);
      });
      if (kept.length) hooks[event] = kept; else delete hooks[event];
    });
    if (Object.keys(hooks).length) data.hooks = hooks; else delete data.hooks;
    if (!writeFile(settingsPath, JSON.stringify(data, null, 2) + "\n")) return "unwritable";
    return "removed " + removed;
  }

  var save = "bash " + here + "/save-conversation.sh";
  function already(event, script, matcher) {
    return groups(event).some(function (g) {
      if (matcher !== undefined && g.matcher !== matcher) return false;
      return (g.hooks || []).some(function (h) {
        return (h.command || "").indexOf(script) > -1;
      });
    });
  }

  // Appended alongside whatever is already configured. Existing groups are
  // read, never rewritten, so another tool's hooks keep working unchanged.
  var added = [];
  if (!already("SessionEnd", "save-conversation.sh")) {
    hooks.SessionEnd = groups("SessionEnd").concat([
      { hooks: [{ type: "command", command: save, timeout: 60 }] }]);
    added.push("SessionEnd");
  }
  // After every reply. It returns at once and saves in the background.
  if (!already("Stop", "save-conversation.sh")) {
    hooks.Stop = groups("Stop").concat([
      { hooks: [{ type: "command", command: save + " --background", timeout: 10 }] }]);
    added.push("Stop");
  }
  ["auto", "manual"].forEach(function (matcher) {
    if (!already("PreCompact", "save-conversation.sh", matcher)) {
      hooks.PreCompact = groups("PreCompact").concat([
        { matcher: matcher, hooks: [{ type: "command", command: save, timeout: 60 }] }]);
      added.push("PreCompact/" + matcher);
    }
  });

  // Raw transcripts hold more than the archives do and are deleted after 30
  // days. Only decide this for someone who has not decided it themselves.
  var kept = data.cleanupPeriodDays;
  if (kept === undefined || kept === null) {
    data.cleanupPeriodDays = 3650;
    added.push("cleanupPeriodDays=3650");
  }

  data.hooks = hooks;
  if (!writeFile(settingsPath, JSON.stringify(data, null, 2) + "\n")) return "unwritable";

  var theirs = 0;
  Object.keys(hooks).forEach(function (event) {
    groups(event).forEach(function (g) {
      (g.hooks || []).forEach(function (h) { if (!isOurs(h.command)) theirs++; });
    });
  });

  // install.sh prints these; keeping the formatting there keeps this file
  // about settings rather than about presentation.
  return JSON.stringify({
    added: added,
    theirs: theirs,
    cleanupPeriodDays: data.cleanupPeriodDays,
    keptTheirCleanup: !(kept === undefined || kept === null)
  });
}

// osascript calls run() by itself; node has to be asked.
if (typeof $ === "undefined" && typeof require !== "undefined" &&
    typeof module !== "undefined" && require.main === module) {
  process.stdout.write(run(process.argv.slice(2)) + "\n");
}
