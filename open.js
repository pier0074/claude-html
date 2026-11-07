// Open a project from the index — whatever "the project" means right now.
//
//   osascript -l JavaScript open.js '{"id":"…","mode":"plan"|"apply",
//                                     "root":"…","out":"…"}'
//   node open.js '{…, "opener":"xdg-open"|"gio"|"wslview"}'
//
// In order:
//   a server of its own that is listening  ->  http://localhost:<port>
//   an index.html in its folder            ->  that page
//   otherwise                              ->  the folder itself
//
// Decided when you click, never when the index was built: a port does not
// exist until its server starts, and a vite project does not name one at all.
// The link carries a session id rather than a path, so a link from any website
// can only ever reach a folder that is already in the index and inside the
// projects root.
//
// Prints "<what>\t<where>"; with mode "apply" it opens it as well.

function run(argv) {
  "use strict";

  var opt = JSON.parse(argv[0] || "{}");
  var P = platform();
  var env = P.env, sh = P.sh, read = P.read, write = P.write, isDir = P.isDir, real = P.real;
  var exists = P.exists;
  // Command output can come back with carriage returns, not newlines.
  function lines(text) { return String(text || "").split(/[\r\n]+/); }

  var HOME = env("HOME") || P.home();
  var ROOT = (opt.root || HOME + "/Sites").replace(/\/+$/, "");
  var OUT = opt.out || ROOT + "/claude-html";
  var ID = String(opt.id || "");
  var SESSION_ID = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;
  if (!SESSION_ID.test(ID)) throw new Error("not a session id: " + ID);

  // ── which folder ────────────────────────────────────────────────────
  var manifest = {};
  try { manifest = JSON.parse(read(OUT + "/.manifest.json") || "{}"); } catch (e) {}
  var entry = manifest[ID];
  if (!entry) throw new Error("that conversation is not in the index");

  var dir = String(entry.cwd || "").replace(/\/+$/, "");
  if (!dir) throw new Error("a claude.ai chat has no folder on this Mac");
  if (dir !== ROOT && dir.indexOf(ROOT + "/") !== 0) {
    throw new Error("that folder is outside " + ROOT);
  }
  if (!isDir(dir)) throw new Error("that folder is gone: " + dir);

  // ── is something of its own already serving? ─────────────────────────
  // Two calls to lsof, not one per server: the listeners, then the working
  // directories of all their processes at once.
  function listeners() {
    var byPid = {}, pid = null;
    lines(sh(P.lsof, ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpn"])).forEach(function (l) {
      if (l.charAt(0) === "p") { pid = l.slice(1); byPid[pid] = byPid[pid] || []; }
      else if (l.charAt(0) === "n" && pid) {
        var m = /:(\d+)$/.exec(l.slice(1));
        if (m) byPid[pid].push(+m[1]);
      }
    });
    return byPid;
  }

  function workingDirs(pids) {
    var out = {}, pid = null;
    if (!pids.length) return out;
    lines(sh(P.lsof, ["-a", "-p", pids.join(","), "-d", "cwd", "-Fpn"]))
      .forEach(function (l) {
        if (l.charAt(0) === "p") pid = l.slice(1);
        else if (l.charAt(0) === "n" && pid) out[pid] = l.slice(1).replace(/\/+$/, "");
      });
    return out;
  }

  function servingPort() {
    // The projects root is not a project: everything is under it, so it would
    // claim the first server any of its projects happened to be running.
    if (real(dir) === real(ROOT)) return null;
    if (!P.lsof) return null;               // nothing here can tell
    var byPid = listeners();
    var pids = Object.keys(byPid);
    if (!pids.length) return null;
    var dirs = workingDirs(pids);
    var here = real(dir), ports = [];
    pids.forEach(function (p) {
      var c = dirs[p] ? real(dirs[p]) : "";
      if (c && (c === here || c.indexOf(here + "/") === 0)) ports = ports.concat(byPid[p]);
    });
    ports = ports.filter(function (v, i, a) { return a.indexOf(v) === i; })
                 .sort(function (a, b) { return a - b; });
    if (ports.length < 2) return ports[0] || null;
    // A project can run an API and a front end at once. The one that answers
    // with a page is the one a person means by "open the project".
    for (var i = 0; i < ports.length; i++) {
      var type = sh(P.curl, ["-s", "-o", "/dev/null", "-w", "%{content_type}",
                             "--max-time", "1", "http://localhost:" + ports[i] + "/"]);
      if (/html/i.test(type)) return ports[i];
    }
    return ports[0];
  }

  var port = servingPort();
  var what, where;
  if (port) {
    // localhost, not 127.0.0.1: a server bound only to IPv6 is reached either
    // way, and plenty are.
    what = "server"; where = "http://localhost:" + port;
  } else if (exists(dir + "/index.html")) {
    what = "page"; where = dir + "/index.html";
  } else {
    what = "folder"; where = dir;
  }

  if (opt.mode === "apply") {
    if (!P.open(where, String(opt.opener || ""))) throw new Error("could not open " + where);
    // This runs inside the helper app, where nothing is visible if it goes
    // wrong, so it leaves a note behind saying what it did.
    write(OUT + "/.last-open", sh("/bin/date", ["+%Y-%m-%d %H:%M:%S"]).replace(/\s+$/, "") +
          "  " + what + "  " + where + "\n");
  }
  return what + "\t" + where;
}

// ── the platform ──────────────────────────────────────────────────────
// What each engine is asked for. Commands always go as a program and a list
// of arguments: under osascript they are quoted here for its one shell
// string, under node no shell is involved at all.
function platform() {
  "use strict";
  if (typeof $ !== "undefined") {
    var fm = $.NSFileManager.defaultManager;
    var shell = Application.currentApplication();
    shell.includeStandardAdditions = true;
    var quote = function (s) { return "'" + String(s).replace(/'/g, "'\\''") + "'"; };
    var sh = function (cmd, args) {
      try { return shell.doShellScript([cmd].concat(args).map(quote).join(" ") + " 2>/dev/null"); }
      catch (e) { return ""; }
    };
    return {
      env: function (name) {
        var v = $.NSProcessInfo.processInfo.environment.objectForKey(name);
        try { return v && v.js ? v.js : null; } catch (e) { return null; }
      },
      home: function () { return $.NSHomeDirectory().js; },
      sh: sh,
      lsof: "/usr/sbin/lsof",
      curl: "/usr/bin/curl",
      exists: function (p) { return !!fm.fileExistsAtPath(p); },
      read: function (path) {
        if (!fm.fileExistsAtPath(path)) return null;
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
      isDir: function (path) {
        var r = Ref();
        return fm.fileExistsAtPathIsDirectory(path, r) && r[0];
      },
      // lsof reports where a process really is, so both sides of the
      // comparison have to be the real path: /tmp and /var are symlinks on
      // macOS, and a project reached through one would never match its server.
      real: function (path) {
        var p = $.NSString.alloc.initWithUTF8String(path).stringByResolvingSymlinksInPath;
        try { return (p && p.js ? p.js : path).replace(/\/+$/, ""); } catch (e) { return path; }
      },
      open: function (where) {
        try { shell.doShellScript("/usr/bin/open " + quote(where)); return true; }
        catch (e) { return false; }
      }
    };
  }

  var nfs = require("fs"), cp = require("child_process");
  var sh = function (cmd, args) {
    if (!cmd) return "";
    try {
      return cp.execFileSync(cmd, args, { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"],
                                          timeout: 10000 });
    } catch (e) { return e && typeof e.stdout === "string" ? e.stdout : ""; }
  };
  // Found on the PATH, or where Debian and Fedora keep it off the PATH; a
  // machine without it simply never finds a running server.
  var which = function (name, also) {
    var dirs = String(process.env.PATH || "").split(":").concat(also || []);
    for (var i = 0; i < dirs.length; i++) {
      if (!dirs[i]) continue;
      try { nfs.accessSync(dirs[i] + "/" + name, nfs.constants.X_OK); return dirs[i] + "/" + name; }
      catch (e) {}
    }
    return "";
  };
  var stat = function (p) { try { return nfs.statSync(p); } catch (e) { return null; } };
  var OPENERS = {
    "xdg-open": function (w) { return ["xdg-open", [w]]; },
    gio: function (w) { return ["gio", ["open", w]]; },
    wslview: function (w) { return ["wslview", [w]]; },
    open: function (w) { return ["/usr/bin/open", [w]]; }
  };
  return {
    env: function (name) { return process.env[name] || null; },
    home: function () { return require("os").homedir(); },
    sh: sh,
    lsof: which("lsof", ["/usr/sbin", "/sbin"]),
    curl: which("curl"),
    exists: function (p) { return !!stat(p); },
    read: function (p) { try { return nfs.readFileSync(p, "utf8"); } catch (e) { return null; } },
    write: function (p, text) {
      try { nfs.writeFileSync(p, text, "utf8"); return true; } catch (e) { return false; }
    },
    isDir: function (p) { var st = stat(p); return !!st && st.isDirectory(); },
    real: function (p) {
      try { return nfs.realpathSync(p).replace(/\/+$/, ""); } catch (e) { return p; }
    },
    open: function (where, opener) {
      if (!Object.prototype.hasOwnProperty.call(OPENERS, opener)) return false;
      var c = OPENERS[opener](where);
      try { cp.execFileSync(c[0], c[1], { stdio: "ignore", timeout: 30000 }); return true; }
      catch (e) { return false; }
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
