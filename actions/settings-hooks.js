// Add or remove this tool's hooks in ~/.claude/settings.json.
//
// Run by install.sh through osascript on macOS and node elsewhere, so that
// installing needs nothing beyond what the machine already has. Everything here is deliberately conservative:
// the file belongs to the user, may contain settings this tool knows nothing
// about, and must survive being read and written by it.
//
//   osascript -l JavaScript settings-hooks.js <settings.json> <scripts dir> add
//   osascript -l JavaScript settings-hooks.js <settings.json> <scripts dir> remove
//   … add no-guard     the saves only: the guard's two hooks left out, and
//                      taken out if an earlier install put them in
//   … add keep-guard   the saves only: the guard's hooks left as they are,
//                      for an install whose conf has the guard off
//
// remove takes out this clone's hooks and nothing else. add takes out the
// hooks of any other copy of claude-html - an earlier clone somewhere else -
// and puts this clone's in their place, so the hooks are always one set.
//
// The status line is one slot, statusLine. add puts claude-html's there
// when it is empty; when it holds a command of the user's own, claude-html's
// wraps it — `bash '<clone>/statusline.sh' --wrap '<their command>'`, their
// command kept whole inside ours, every other field of theirs as it was —
// and statusline.sh runs theirs first. remove gives theirs back exactly,
// or empties the slot it filled.

function run(argv) {
  var settingsPath = argv[0], here = argv[1], mode = argv[2], noGuard = argv[3] === "no-guard";
  var keepGuard = argv[3] === "keep-guard";

  var JXA = typeof $ !== "undefined";
  var fm = JXA ? $.NSFileManager.defaultManager : null, nfs = JXA ? null : require("fs");

  function env(name) {
    if (!JXA) return process.env[name] || "";
    var v = $.NSProcessInfo.processInfo.environment.objectForKey(name);
    try { return v && v.js ? v.js : ""; } catch (e) { return ""; }
  }
  function exists(path) {
    if (JXA) return !!fm.fileExistsAtPath(path);
    try { nfs.statSync(path); return true; } catch (e) { return false; }
  }
  // A path as the file system has it, links followed, for comparing two
  // spellings of one folder; as given when it is not there.
  function real(path) {
    path = String(path || "").replace(/\/+$/, "") || "/";
    if (!exists(path)) return path;
    if (JXA) return $(path).stringByResolvingSymlinksInPath.js;
    try { return nfs.realpathSync(path); } catch (e) { return path; }
  }

  // The text; null when there is no file; false when there is one that
  // cannot be read, or holds a byte that is not UTF-8. Read as missing, such
  // a file was written again as our hooks alone; read with the byte
  // replaced, it came back changed.
  function readFile(path) {
    if (!JXA) {
      var buf;
      try { buf = nfs.readFileSync(path); } catch (e) { return e && e.code === "ENOENT" ? null : false; }
      var t = buf.toString("utf8");
      return Buffer.from(t, "utf8").equals(buf) ? t : false;
    }
    // A missing file yields an ObjC nil that is truthy in JS and whose .js is
    // undefined, so check it exists first and guard the unwrap. A link that
    // points nowhere is not there either.
    if (!fm.fileExistsAtPath(path)) return null;
    try {
      var s = $.NSString.stringWithContentsOfFileEncodingError(path, 4, null);
      var text = s ? $.CFMakeCollectable(s).js : null;
      return (typeof text === "string") ? text : false;
    } catch (e) {
      return false;
    }
  }

  // Written beside the file and moved over it. A settings.json kept as a
  // symlink - into a dotfiles repository, say - is written where it points,
  // so the link stays a link.
  function writeFile(path, text) {
    var target = path;
    if (JXA) {
      var dest = $(path).stringByResolvingSymlinksInPath.js;
      if (dest) target = dest;
      var dir = $.NSString.alloc.initWithUTF8String(target).stringByDeletingLastPathComponent;
      fm.createDirectoryAtPathWithIntermediateDirectoriesAttributesError(dir, true, $(), null);
      return $.NSString.alloc.initWithUTF8String(text)
        .writeToFileAtomicallyEncodingError(target, true, 4, null);
    }
    var npath = require("path");
    try { target = nfs.realpathSync(path); } catch (e) { target = path; }
    try {
      nfs.mkdirSync(npath.dirname(target), { recursive: true });
      var tmp = target + ".tmp" + process.pid;
      nfs.writeFileSync(tmp, text, "utf8");
      nfs.renameSync(tmp, target);
      return true;
    } catch (e) { return false; }
  }

  var data = {};
  var raw = readFile(settingsPath);
  // There but not to be read: nothing is written, the file stays as it is.
  if (raw === false) return "unreadable";
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

  // ── which hooks are claude-html's ──
  // Recognised by the whole command, never by a script's name alone: a hook
  // of the user's own called prompt-guard.sh, or a guard.sh of theirs, is
  // theirs. A command is claude-html's when it has the shape the installer
  // writes - bash, a path ending in one of its scripts, and that script's
  // own argument - and its folder is a copy of claude-html (it holds files
  // only claude-html has: in its folders, or at its top for a copy from
  // before them), or, in the quoted form only this installer
  // writes, a copy that has since gone. This clone's are the ones in this
  // folder; any other is left from an install somewhere else.
  // save-session-link.sh is gone, but an early install may still have its
  // hook in settings.json: it is recognised so that it can go.
  var ARGS = { "save-conversation.sh": ["", "--background"], "guard.sh": ["prompt", "bash"],
               "save-session-link.sh": [""] };
  var HOMEDIR = env("HOME");
  function parse(cmd) {
    // Unquoted, the path may hold a space: an install from before the
    // quoting wrote it so, and it is still this one's to repair or remove.
    var m = /^\s*bash\s+(?:'((?:[^']|'\\'')*)'|([^\s'"][^'"]*?))(?:\s+(--background|prompt|bash))?\s*$/
      .exec(String(cmd || ""));
    if (!m) return null;
    var p = m[1] !== undefined ? m[1].replace(/'\\''/g, "'") : m[2], arg = m[3] || "";
    if (p.indexOf("~/") === 0 && HOMEDIR) p = HOMEDIR + p.slice(1);
    var slash = p.lastIndexOf("/"), script = p.slice(slash + 1);
    if (slash < 1 || !Object.prototype.hasOwnProperty.call(ARGS, script) ||
        ARGS[script].indexOf(arg) < 0) return null;
    return { dir: p.slice(0, slash), script: script, arg: arg, quoted: m[1] !== undefined };
  }
  function looksOurs(dir) {
    return exists(dir + "/build/convert.js") || exists(dir + "/actions/guard.js") ||
           exists(dir + "/convert.js") || exists(dir + "/guard.js") ||
           (exists(dir + "/save-conversation.sh") && exists(dir + "/save-session-link.sh"));
  }
  var HERE_REAL = real(here);
  var infoMemo = {};
  function info(cmd) {
    cmd = String(cmd || "");
    if (Object.prototype.hasOwnProperty.call(infoMemo, cmd)) return infoMemo[cmd];
    var p = parse(cmd);
    if (p) {
      if (real(p.dir) === HERE_REAL) p.mine = true;
      else if (looksOurs(p.dir) || (p.quoted && !exists(p.dir + "/" + p.script))) p.mine = false;
      else p = null;
    }
    infoMemo[cmd] = p;
    return p;
  }
  function isOurs(cmd) { return !!info(cmd); }
  function isMine(cmd, script, arg) {
    var p = info(cmd);
    return !!p && p.mine && (script === undefined || p.script === script) &&
           (arg === undefined || p.arg === arg);
  }
  // Takes out the hooks a test picks, and any group left empty by it: a
  // group that still holds somebody else's hook is kept.
  function drop(test) {
    var n = 0;
    Object.keys(hooks).forEach(function (event) {
      var kept = [];
      groups(event).forEach(function (g) {
        var before = (g.hooks || []).length;
        g.hooks = (g.hooks || []).filter(function (h) { return !test(h.command || ""); });
        n += before - g.hooks.length;
        if (g.hooks.length) kept.push(g);
      });
      if (kept.length) hooks[event] = kept; else delete hooks[event];
    });
    return n;
  }

  // ── the status line ──
  // Ours is recognised by its whole command, as a hook is: bash, a path
  // ending in statusline.sh in a copy of claude-html (or, quoted as only
  // this installer writes it, one since gone), and nothing after it but
  // --wrap and one quoted command.
  var Q = "'((?:[^']|'\\\\'')*)'";
  var SLRE = new RegExp("^\\s*bash\\s+" + Q + "(?:\\s+--wrap\\s+" + Q + ")?\\s*$");
  function unq(t) { return t.replace(/'\\''/g, "'"); }
  function statusLineOf(sl) {
    if (!sl || typeof sl !== "object" || typeof sl.command !== "string") return null;
    var m = SLRE.exec(sl.command);
    if (!m) return null;
    var p = unq(m[1]), slash = p.lastIndexOf("/");
    if (slash < 1 || p.slice(slash + 1) !== "statusline.sh") return null;
    var dir = p.slice(0, slash);
    var mine = real(dir) === HERE_REAL;
    if (!mine && !looksOurs(dir) && exists(dir + "/statusline.sh")) return null;
    return { dir: dir, mine: mine, wrap: m[2] === undefined ? null : unq(m[2]) };
  }

  // What is installed, for the Settings page: this clone's hooks, the status
  // line, cleanupPeriodDays. Nothing is written.
  if (mode === "status") {
    var sl = statusLineOf(data.statusLine), has = function (event, script, arg, matcher) {
      return already(event, script, arg, matcher);
    };
    return JSON.stringify({
      Stop: has("Stop", "save-conversation.sh", "--background"),
      SessionEnd: has("SessionEnd", "save-conversation.sh", ""),
      PreCompact: has("PreCompact", "save-conversation.sh", "", "auto") && has("PreCompact", "save-conversation.sh", "", "manual"),
      guardPrompt: has("UserPromptSubmit", "guard.sh", "prompt"),
      guardBash: has("PreToolUse", "guard.sh", "bash", "Bash"),
      statusLine: sl && sl.mine ? (sl.wrap !== null ? "wrapped" : "ours") : sl ? "other copy" :
        (data.statusLine && data.statusLine.command ? "yours" : "none"),
      cleanupPeriodDays: typeof data.cleanupPeriodDays === "number" ? data.cleanupPeriodDays : null
    });
  }

  if (mode === "remove") {
    var removed = drop(function (c) { return isMine(c); });
    if (Object.keys(hooks).length) data.hooks = hooks; else delete data.hooks;
    var slNote = "", slOurs = statusLineOf(data.statusLine);
    if (slOurs && slOurs.mine) {
      if (slOurs.wrap !== null) { data.statusLine.command = slOurs.wrap; slNote = "; status line restored to yours"; }
      else { delete data.statusLine; slNote = "; status line removed"; }
    }
    if (!writeFile(settingsPath, JSON.stringify(data, null, 2) + "\n")) return "unwritable";
    return "removed " + removed + slNote;
  }

  // Claude Code hands the command to a shell, so a clone path with a space in
  // it would split into words and the hook would never run.
  function quote(p) { return "'" + String(p).replace(/'/g, "'\\''") + "'"; }
  var save = "bash " + quote(here + "/save-conversation.sh");

  // Hooks written before the path was quoted are repaired in place, but only
  // where the missing quotes break them: elsewhere they run as they are, and
  // the file is the user's.
  var legacy = "bash " + here + "/save-conversation.sh";
  var repaired = 0;
  if (/[^A-Za-z0-9_.\/+,:@%=-]/.test(here)) {
    Object.keys(hooks).forEach(function (event) {
      groups(event).forEach(function (g) {
        (g.hooks || []).forEach(function (h) {
          if (h.command === legacy) { h.command = save; repaired++; }
          else if (h.command === legacy + " --background") {
            h.command = save + " --background"; repaired++;
          }
        });
      });
    });
  }

  var added = [];
  // Another copy's hooks, from an install somewhere else: taken out as a
  // set, and this clone's put in below. Whether that copy had the guard
  // decides it for keep-guard, which leaves the guard as it was.
  var hadGuard = false, others = {};
  Object.keys(hooks).forEach(function (event) {
    groups(event).forEach(function (g) {
      (g.hooks || []).forEach(function (h) {
        var p = info(h.command);
        if (p && p.script === "guard.sh") hadGuard = true;
        if (p && !p.mine) others[p.dir] = true;
      });
    });
  });
  var replaced = drop(function (c) { var p = info(c); return !!p && !p.mine; });
  if (replaced) added.push("replaced " + replaced + " hook(s) of " + Object.keys(others).join(", "));

  function already(event, script, arg, matcher) {
    return groups(event).some(function (g) {
      if (matcher !== undefined && g.matcher !== matcher) return false;
      return (g.hooks || []).some(function (h) { return isMine(h.command, script, arg); });
    });
  }

  // Appended alongside whatever is already configured. Existing groups are
  // read, never rewritten, so another tool's hooks keep working unchanged.
  if (!already("SessionEnd", "save-conversation.sh", "")) {
    hooks.SessionEnd = groups("SessionEnd").concat([
      { hooks: [{ type: "command", command: save, timeout: 60 }] }]);
    added.push("SessionEnd");
  }
  // After every reply. It returns at once and saves in the background.
  if (!already("Stop", "save-conversation.sh", "--background")) {
    hooks.Stop = groups("Stop").concat([
      { hooks: [{ type: "command", command: save + " --background", timeout: 10 }] }]);
    added.push("Stop");
  }
  ["auto", "manual"].forEach(function (matcher) {
    if (!already("PreCompact", "save-conversation.sh", "", matcher)) {
      hooks.PreCompact = groups("PreCompact").concat([
        { matcher: matcher, hooks: [{ type: "command", command: save, timeout: 60 }] }]);
      added.push("PreCompact/" + matcher);
    }
  });

  // The guard: before a prompt is sent, and before a Bash command runs. Its
  // dialog waits CLAUDE_HTML_GUARD_WAIT, a minute unless the conf says
  // otherwise, and at most an hour; a hook Claude Code gives up on lets the
  // prompt or the command through — its own default for a prompt hook is 30
  // seconds — so its timeout is the hour and a minute: any wait the conf
  // can hold works the moment it is saved, with nothing reinstalled. One of
  // an earlier install, with another timeout (660, for the ten minutes it
  // once waited), is set to this one where it stands.
  var guard = "bash " + quote(here + "/guard.sh"), GUARD_TIMEOUT = 3660;
  function guardTimeouts(event, arg, matcher) {
    var n = 0;
    groups(event).forEach(function (g) {
      if (matcher !== undefined && g.matcher !== matcher) return;
      (g.hooks || []).forEach(function (h) {
        if (isMine(h.command, "guard.sh", arg) && h.timeout !== GUARD_TIMEOUT) { h.timeout = GUARD_TIMEOUT; n++; }
      });
    });
    return n;
  }
  if (noGuard) {
    ["UserPromptSubmit", "PreToolUse"].forEach(function (event) {
      var keptGroups = [];
      groups(event).forEach(function (g) {
        var before = (g.hooks || []).length;
        g.hooks = (g.hooks || []).filter(function (h) { return !isMine(h.command, "guard.sh"); });
        if (g.hooks.length < before) added.push("removed guard/" + event);
        if (g.hooks.length) keptGroups.push(g);
      });
      if (keptGroups.length) hooks[event] = keptGroups; else delete hooks[event];
    });
  } else if (!keepGuard || hadGuard) {
    if (!already("UserPromptSubmit", "guard.sh", "prompt")) {
      hooks.UserPromptSubmit = groups("UserPromptSubmit").concat([
        { hooks: [{ type: "command", command: guard + " prompt", timeout: GUARD_TIMEOUT }] }]);
      added.push("UserPromptSubmit");
    } else if (guardTimeouts("UserPromptSubmit", "prompt")) {
      added.push("UserPromptSubmit timeout " + GUARD_TIMEOUT);
    }
    if (!already("PreToolUse", "guard.sh", "bash", "Bash")) {
      hooks.PreToolUse = groups("PreToolUse").concat([
        { matcher: "Bash", hooks: [{ type: "command", command: guard + " bash", timeout: GUARD_TIMEOUT }] }]);
      added.push("PreToolUse/Bash");
    } else if (guardTimeouts("PreToolUse", "bash", "Bash")) {
      added.push("PreToolUse/Bash timeout " + GUARD_TIMEOUT);
    }
  }

  // The status line: ours in an empty slot, around theirs in a taken one,
  // moved here from another copy of claude-html with what it wraps.
  var slCmd = "bash " + quote(here + "/statusline.sh"), slState = "kept";
  var slNow = statusLineOf(data.statusLine);
  if (data.statusLine === undefined || data.statusLine === null) {
    data.statusLine = { type: "command", command: slCmd };
    slState = "added"; added.push("statusLine");
  } else if (slNow && !slNow.mine) {
    data.statusLine.command = slCmd + (slNow.wrap !== null ? " --wrap " + quote(slNow.wrap) : "");
    slState = slNow.wrap !== null ? "wrapped" : "added"; added.push("statusLine (from " + slNow.dir + ")");
  } else if (!slNow && data.statusLine && typeof data.statusLine === "object" &&
             typeof data.statusLine.command === "string" && data.statusLine.command.trim()) {
    data.statusLine.command = slCmd + " --wrap " + quote(data.statusLine.command);
    slState = "wrapped"; added.push("statusLine (around yours)");
  } else if (slNow) {
    slState = slNow.wrap !== null ? "wrapped" : "ours";
  } else {
    slState = "left";
  }

  // Raw transcripts hold more than the archives do and are deleted after 30
  // days. Only decide this for someone who has not decided it themselves.
  var kept = data.cleanupPeriodDays;
  if (kept === undefined || kept === null) {
    data.cleanupPeriodDays = 3650;
    added.push("cleanupPeriodDays=3650");
  }
  if (repaired) added.push("quoted " + repaired + " older hook(s)");

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
    statusLine: slState,
    keptTheirCleanup: !(kept === undefined || kept === null)
  });
}

// osascript calls run() by itself; node has to be asked.
if (typeof $ === "undefined" && typeof require !== "undefined" &&
    typeof module !== "undefined" && require.main === module) {
  process.stdout.write(run(process.argv.slice(2)) + "\n");
}
