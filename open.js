// Open a project from the index — whatever "the project" means right now.
//
//   osascript -l JavaScript open.js '{"id":"…","mode":"plan"|"apply",
//                                     "root":"…","out":"…"}'
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
  var fm = $.NSFileManager.defaultManager;
  var shell = Application.currentApplication();
  shell.includeStandardAdditions = true;

  function env(name) {
    var v = $.NSProcessInfo.processInfo.environment.objectForKey(name);
    try { return v && v.js ? v.js : null; } catch (e) { return null; }
  }
  function sh(cmd) { try { return shell.doShellScript(cmd); } catch (e) { return ""; } }
  function quote(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'"; }
  // do shell script hands back carriage returns, not newlines.
  function lines(text) { return String(text || "").split(/[\r\n]+/); }

  function read(path) {
    if (!fm.fileExistsAtPath(path)) return null;
    try {
      var s = $.NSString.stringWithContentsOfFileEncodingError(path, 4, null);
      var text = s ? $.CFMakeCollectable(s).js : null;
      return typeof text === "string" ? text : null;
    } catch (e) { return null; }
  }
  // lsof reports where a process really is, so both sides of the comparison
  // have to be the real path: /tmp and /var are symlinks on macOS, and a
  // project reached through one would never match its own server.
  function real(path) {
    var p = $.NSString.alloc.initWithUTF8String(path).stringByResolvingSymlinksInPath;
    try { return (p && p.js ? p.js : path).replace(/\/+$/, ""); } catch (e) { return path; }
  }

  function write(path, text) {
    return $.NSString.alloc.initWithUTF8String(text)
      .writeToFileAtomicallyEncodingError(path, true, 4, null);
  }

  function isDir(path) {
    var r = Ref();
    return fm.fileExistsAtPathIsDirectory(path, r) && r[0];
  }

  var HOME = env("HOME") || $.NSHomeDirectory().js;
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
    lines(sh("/usr/sbin/lsof -nP -iTCP -sTCP:LISTEN -Fpn 2>/dev/null")).forEach(function (l) {
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
    lines(sh("/usr/sbin/lsof -a -p " + pids.join(",") + " -d cwd -Fpn 2>/dev/null"))
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
      var type = sh("/usr/bin/curl -s -o /dev/null -w '%{content_type}' --max-time 1 " +
                    quote("http://localhost:" + ports[i] + "/"));
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
  } else if (fm.fileExistsAtPath(dir + "/index.html")) {
    what = "page"; where = dir + "/index.html";
  } else {
    what = "folder"; where = dir;
  }

  if (opt.mode === "apply") {
    sh("/usr/bin/open " + quote(where));
    // This runs inside the helper app, where nothing is visible if it goes
    // wrong, so it leaves a note behind saying what it did.
    write(OUT + "/.last-open", sh("/bin/date '+%Y-%m-%d %H:%M:%S'") +
          "  " + what + "  " + where + "\n");
  }
  return what + "\t" + where;
}
