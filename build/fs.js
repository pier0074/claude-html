// The file helpers of the scripts that run under node as well as under
// osascript: under node they are these, one copy. Under osascript each
// script keeps its own, through NSFileManager, and never loads this file.
//
//   var F = require(<the clone> + "/build/fs.js")(require("fs"));
//
// The fs module is handed in rather than required here, so a test that
// stands in for part of it reaches these helpers too. Nothing here throws:
// a path that cannot be read is null, an empty list, or not there.

function claudeHtmlNodeFs(nfs) {
  "use strict";
  function stat(p) { try { return nfs.statSync(p); } catch (e) { return null; } }
  // The link itself, not what it points to: a dangling link is still there.
  function lstat(p) { try { return nfs.lstatSync(p); } catch (e) { return null; } }
  return {
    stat: stat,
    lstat: lstat,
    exists: function (p) { return !!stat(p); },
    isDir: function (p) { var st = stat(p); return !!st && st.isDirectory(); },
    isFile: function (p) { var st = stat(p); return !!st && st.isFile(); },
    read: function (p) { try { return nfs.readFileSync(p, "utf8"); } catch (e) { return null; } },
    // The owner's own files, read whole or not at all: the text; null when
    // there is none; false when there is one that cannot be read, or holds
    // a byte that is not UTF-8 (which a plain read would replace).
    readWhole: function (p) {
      var buf;
      try { buf = nfs.readFileSync(p); } catch (e) { return e && e.code === "ENOENT" ? null : false; }
      var text = buf.toString("utf8");
      return Buffer.from(text, "utf8").equals(buf) ? text : false;
    },
    list: function (dir) { try { return nfs.readdirSync(dir).sort(); } catch (e) { return []; } },
    // A path as the file system has it, links followed; as given when it is not there.
    real: function (p) { try { return nfs.realpathSync(p); } catch (e) { return p; } }
  };
}

if (typeof module !== "undefined") module.exports = claudeHtmlNodeFs;
