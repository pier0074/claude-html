// Build every session page, the index, and the search index.
//
// One file, two runtimes. On macOS it runs through /usr/bin/osascript, so a
// machine needs nothing but the system; anywhere else it runs under node,
// which a machine running Claude Code already has. Everything below the
// platform block is plain JavaScript, identical in both.
//
//   osascript -l JavaScript convert.js '{"root":"…","out":"…","force":false}'
//   node convert.js '{"root":"…","out":"…","force":false}'
//
// This file does the data work only — reading transcripts, repairing archives
// that mislabelled their roles, pairing tool calls with their output — and
// hands the result to the browser as JSON. Nothing here emits markup.

function run(argv) {
  "use strict";

  var opt = JSON.parse(argv[0] || "{}");

  // ── the platform ────────────────────────────────────────────────────
  // Everything either runtime is asked for, in one block: eleven functions.
  var JXA = typeof $ !== "undefined";
  var env, defaultHome, read, write, list, mtime, sig, isDir, exists, chmodx, remove;

  if (JXA) {
    var fm = $.NSFileManager.defaultManager;
    env = function (name) {
      var v = $.NSProcessInfo.processInfo.environment.objectForKey(name);
      try { return v && v.js ? v.js : null; } catch (e) { return null; }
    };
    defaultHome = function () { return $.NSHomeDirectory().js; };
    read = function (path) {
      // A missing file gives an ObjC nil that is truthy in JavaScript and
      // whose .js is undefined, so check first and guard the unwrap.
      if (!fm.fileExistsAtPath(path)) return null;
      try {
        var s = $.NSString.stringWithContentsOfFileEncodingError(path, 4, null);
        var text = s ? $.CFMakeCollectable(s).js : null;
        return typeof text === "string" ? text : null;
      } catch (e) { return null; }
    };
    write = function (path, text) {
      var dir = $.NSString.alloc.initWithUTF8String(path).stringByDeletingLastPathComponent;
      fm.createDirectoryAtPathWithIntermediateDirectoriesAttributesError(dir, true, $(), null);
      return $.NSString.alloc.initWithUTF8String(text)
        .writeToFileAtomicallyEncodingError(path, true, 4, null);
    };
    list = function (dir) {
      if (!fm.fileExistsAtPath(dir)) return [];
      var items = fm.contentsOfDirectoryAtPathError(dir, null);
      if (!items) return [];
      return $.CFMakeCollectable(items).js.map(function (x) { return x.js; }).sort();
    };
    mtime = function (path) {
      var at = fm.attributesOfItemAtPathError(path, null);
      if (!at) return 0;
      var d = $.CFMakeCollectable(at).js.NSFileModificationDate;
      return d ? Math.round(d.js.getTime() / 1000) : 0;
    };
    sig = function (path) {
      var at = fm.attributesOfItemAtPathError(path, null);
      if (!at) return "";
      var a = $.CFMakeCollectable(at).js;
      var d = a.NSFileModificationDate;
      return (a.NSFileSize ? a.NSFileSize.js : 0) + ":" + (d ? d.js.getTime() : 0);
    };
    isDir = function (path) {
      var ref = Ref();
      return fm.fileExistsAtPathIsDirectory(path, ref) && ref[0];
    };
    exists = function (path) { return !!fm.fileExistsAtPath(path); };
    chmodx = function (path) {
      fm.setAttributesOfItemAtPathError({ NSFilePosixPermissions: 0o755 }, path, null);
    };
    remove = function (path) { fm.removeItemAtPathError(path, null); };
  } else {
    var nfs = require("fs"), npath = require("path");
    var stat = function (p) { try { return nfs.statSync(p); } catch (e) { return null; } };
    env = function (name) { return process.env[name] || null; };
    defaultHome = function () { return require("os").homedir(); };
    read = function (path) {
      try { return nfs.readFileSync(path, "utf8"); } catch (e) { return null; }
    };
    write = function (path, text) {
      // Atomic for the same reason the JXA side is: a page being read while
      // half written is a broken page, and saves can overlap a build.
      try {
        nfs.mkdirSync(npath.dirname(path), { recursive: true });
        var tmp = path + ".tmp" + process.pid;
        nfs.writeFileSync(tmp, text, "utf8");
        nfs.renameSync(tmp, path);
        return true;
      } catch (e) { return false; }
    };
    list = function (dir) {
      try { return nfs.readdirSync(dir).sort(); } catch (e) { return []; }
    };
    mtime = function (path) {
      var st = stat(path);
      return st ? Math.round(st.mtimeMs / 1000) : 0;
    };
    sig = function (path) {
      // The same shape the JXA side produces: bytes, then milliseconds. Date
      // truncates to the millisecond there, so truncate here too, or the two
      // runtimes would call the same file two different files.
      var st = stat(path);
      return st ? st.size + ":" + Math.floor(st.mtimeMs) : "";
    };
    isDir = function (path) {
      var st = stat(path);
      return !!st && st.isDirectory();
    };
    exists = function (path) { return !!stat(path); };
    chmodx = function (path) {
      try { nfs.chmodSync(path, 0o755); } catch (e) {}
    };
    remove = function (path) {
      try { nfs.rmSync(path, { recursive: true, force: true }); } catch (e) {}
    };
  }

  // NSHomeDirectory reads the user record and ignores $HOME, so on its own it
  // would look in the real home even when the environment says otherwise —
  // wrong under a test harness, a redirected HOME, or another user's launchd.
  var HOME = opt.home || env("HOME") || defaultHome();
  var ROOT = opt.root || (HOME + "/Sites");
  var OUT = opt.out || (ROOT + "/claude-html");
  var PROJECTS = opt.projects || (HOME + "/.claude/projects");
  var HERE = opt.here || (HOME + "/.claude/scripts");
  var FORCE = !!opt.force;
  var ONLY = opt.only || "";

  // ── text ────────────────────────────────────────────────────────────
  function cap(s, n) {
    s = s == null ? "" : String(s);
    // Count code points, not UTF-16 units: Python does, and slicing by units
    // can cut an emoji in half and leave a lone surrogate behind.
    var chars = Array.from(s);
    if (chars.length <= n) return s;
    return chars.slice(0, n).join("") +
           "\n…[truncated, " + (chars.length - n) + " more characters]";
  }

  // Injected by the harness, not typed by anyone.
  var SYSTEM_BLOCK = /<system-reminder>[\s\S]*?<\/system-reminder>/g;
  var COMMAND_BLOCK = /<command-(name|message|args)>[\s\S]*?<\/command-\1>/g;

  function cleanUserText(text) {
    return String(text == null ? "" : text)
      .replace(SYSTEM_BLOCK, "").replace(COMMAND_BLOCK, "").trim();
  }

  var HARNESS = ["Launching skill:", "Base directory for this skill:",
    "Caveat: The messages below", "[Request interrupted",
    "This session is being continued from a previous",
    "API Error", "safeguards flagged this message"];

  function looksLikeHarness(text) {
    var head = String(text == null ? "" : text).replace(/^\s+/, "").slice(0, 200);
    return HARNESS.some(function (p) { return head.indexOf(p) > -1; });
  }

  function blocksToText(content) {
    if (typeof content === "string") return content;
    if (!Array.isArray(content)) return "";
    return content.map(function (b) {
      if (!b || typeof b !== "object") return "";
      if (b.type === "text") return b.text || "";
      if (b.type === "image") return "[image]";
      return "";
    }).filter(Boolean).join("\n");
  }

  // ── project naming ──────────────────────────────────────────────────
  function basename(p) {
    var parts = String(p).replace(/\/+$/, "").split("/");
    return parts[parts.length - 1] || String(p);
  }

  function projectFromCwd(cwd) {
    if (!cwd) return "?";
    var c = String(cwd).replace(/\/+$/, "");
    if (c === HOME.replace(/\/+$/, "")) return "~";
    if (c === ROOT.replace(/\/+$/, "")) return basename(ROOT);
    return basename(c);
  }

  // Claude encodes "/" as "-", which cannot be undone when the name itself
  // contains a hyphen. Only a fallback: the cwd inside the file is truth.
  function cwdFromDirname(name) {
    return "/" + String(name).replace(/^-+|-+$/g, "").replace(/-/g, "/");
  }

  // ── transcripts ─────────────────────────────────────────────────────
  function eachLine(text, fn) {
    var lines = text.split("\n");
    for (var i = 0; i < lines.length; i++) {
      if (!lines[i]) continue;
      var e;
      try { e = JSON.parse(lines[i]); } catch (err) { continue; }
      if (fn(e, i) === false) return;
    }
  }

  function peek(text) {
    var cwd = null, title = null;
    eachLine(text, function (e, i) {
      if (i > 400 || (cwd && title)) return false;
      cwd = cwd || e.cwd || null;
      title = title || e.aiTitle || null;
    });
    return { cwd: cwd, title: title };
  }

  function fromJsonl(text) {
    var msgs = [];
    eachLine(text, function (e) {
      var t = e.type, ts = e.timestamp, side = !!e.isSidechain;
      var content = (e.message || {}).content;
      if (t === "user") {
        if (e.isMeta) return;                 // harness context, not a turn
        if (typeof content === "string") {
          var text1 = cleanUserText(content);
          if (text1) msgs.push({ role: "user", timestamp: ts, side: side, text: text1 });
        } else if (Array.isArray(content)) {
          content.forEach(function (b) {
            if (!b || typeof b !== "object") return;
            if (b.type === "text") {
              var tx = cleanUserText(b.text);
              if (tx) msgs.push({ role: "user", timestamp: ts, side: side, text: tx });
            } else if (b.type === "image") {
              msgs.push({ role: "user", timestamp: ts, side: side, text: "[image]" });
            } else if (b.type === "tool_result") {
              msgs.push({ role: "tool_result", timestamp: ts, side: side,
                          text: cap(blocksToText(b.content), 6000) });
            }
          });
        }
      } else if (t === "assistant" && Array.isArray(content)) {
        var text2 = content.filter(function (b) { return b && b.type === "text"; })
                           .map(function (b) { return b.text || ""; }).join("\n");
        var think = content.filter(function (b) { return b && b.type === "thinking"; })
                           .map(function (b) { return b.thinking || ""; }).join("\n\n");
        var tools = content.filter(function (b) { return b && b.type === "tool_use"; })
                           .map(function (b) {
                             return { id: b.id, name: b.name, input: b.input || {} };
                           });
        if (text2 || tools.length || think) {
          msgs.push({ role: "assistant", timestamp: ts, side: side,
                      text: text2, thinking: think, tools: tools });
        }
      }
    });
    return msgs;
  }

  // ── archives ────────────────────────────────────────────────────────
  // Archives written before the writer separated the two filed tool output as
  // something the user said, which made a 49-prompt session read as 1,125.
  // The transcripts they came from are gone, so the roles are inferred from
  // turn order: a result can only follow the call that produced it.
  function repairArchiveRoles(msgs) {
    if (msgs.some(function (m) { return m.role === "tool_result"; })) {
      return { messages: msgs, inferred: false };
    }
    var out = [], changed = false, afterTools = false;
    msgs.forEach(function (m) {
      if (m.role === "user") {
        if (afterTools) { m = Object.assign({}, m, { role: "tool_result" }); changed = true; }
        else if (looksLikeHarness(m.text)) { m = Object.assign({}, m, { role: "system" }); changed = true; }
      }
      out.push(m);
      afterTools = m.role === "tool_result" ||
                   (m.role === "assistant" && !!(m.tools && m.tools.length));
    });
    return { messages: out, inferred: changed };
  }

  // ── claude.ai exports ───────────────────────────────────────────────
  function fromExportChat(c) {
    var msgs = [];
    (c.chat_messages || []).forEach(function (x) {
      var who = x.sender === "human" ? "user" : "assistant";
      var ts = x.created_at, blocks = x.content || [];
      var textParts = [], thinkParts = [], tools = [];
      blocks.forEach(function (b) {
        if (!b || typeof b !== "object") return;
        if (b.type === "text") textParts.push(b.text || "");
        else if (b.type === "thinking") thinkParts.push(b.thinking || "");
        else if (b.type === "tool_use") tools.push({ name: b.name, input: b.input || {} });
        else if (b.type === "tool_result") {
          var content = b.content;
          if (Array.isArray(content)) content = blocksToText(content);
          if (typeof content === "string" && content.trim()) {
            msgs.push({ role: "tool_result", timestamp: ts, side: false, text: cap(content, 6000) });
          }
        }
      });
      var text = textParts.filter(Boolean).join("\n") || x.text || "";
      (x.files || []).concat(x.attachments || []).forEach(function (a) {
        text = (text + "\n[attached: " + (a.file_name || a.file_kind || "file") + "]").trim();
      });
      if (who === "user") {
        if (text.trim()) msgs.push({ role: "user", timestamp: ts, side: false, text: text });
      } else if (text || tools.length || thinkParts.length) {
        msgs.push({ role: "assistant", timestamp: ts, side: false, text: text,
                    thinking: thinkParts.join("\n\n"), tools: tools });
      }
    });
    return msgs;
  }

  function findExports() {
    if (opt.exportPath) return exists(opt.exportPath) ? [opt.exportPath] : [];
    var found = [];
    [HOME + "/Downloads", ROOT].forEach(function (base) {
      var direct = base + "/conversations.json";
      if (exists(direct)) found.push(direct);
      list(base).forEach(function (name) {
        var p = base + "/" + name + "/conversations.json";
        if (exists(p)) found.push(p);
      });
    });
    return found;
  }

  // A chat whose export had not changed is listed from the manifest, without its
  // content, so a chat that must be rebuilt anyway is read back from the export.
  // Parsed once per run: rebuilding several chats must not re-read the file each.
  var exportCache = {};
  function chatFromExport(path, id) {
    if (!(path in exportCache)) {
      var text = read(path), chats = [];
      try { chats = text ? JSON.parse(text) : []; } catch (e) { chats = []; }
      exportCache[path] = {};
      (Array.isArray(chats) ? chats : []).forEach(function (c) {
        if (c && c.uuid) exportCache[path][c.uuid] = c;
      });
    }
    var c = exportCache[path][id];
    if (!c) throw new Error("no longer in " + path);
    return c;
  }

  // A session's sub-agents live beside it, in <session id>/subagents: each is a
  // transcript of its own, with a .meta.json naming the Task call that spawned
  // it. They belong to their conversation and are not conversations of their
  // own — eighty-nine megabytes of them for one session here, which is also why
  // each gets a page rather than being folded into the parent's.
  function subagents(dir, id) {
    var home = dir + "/" + id + "/subagents", out = [];
    if (!isDir(home)) return out;
    list(home).forEach(function (f) {
      if (!/^agent-.*\.jsonl$/.test(f)) return;
      var path = home + "/" + f;
      out.push({
        agentId: f.replace(/^agent-/, "").replace(/\.jsonl$/, ""),
        path: path,
        metaPath: path.replace(/\.jsonl$/, ".meta.json"),
        sig: sig(path)
      });
    });
    return out;
  }

  // ── discovery ───────────────────────────────────────────────────────
  // A slash command reaches the transcript wrapped in tags of Claude Code's
  // own — <command-name>/compact</command-name> and the rest. As a title that
  // is unreadable, and it is never what the session was about: take the
  // command's name, and prefer a real prompt further down if there is one.
  function clean(text) {
    var t = String(text || "").replace(/\u001b\[[0-9;]*[A-Za-z]/g, "");
    // What a local command printed is recorded as though you had typed it.
    // It is output, not a prompt, and never a title.
    if (/^\s*<local-command-stdout>/.test(t)) return "";
    var name = /<command-name>\s*([^<]*)<\/command-name>/.exec(t);
    if (name) {
      var args = /<command-args>\s*([^<]*)<\/command-args>/.exec(t);
      return (name[1].trim() + " " + (args ? args[1].trim() : "")).trim();
    }
    return t.replace(/<\/?command-[a-z]+>/g, " ").split(/\s+/).join(" ").trim();
  }

  function firstPrompt(msgs) {
    var fallback = "";
    for (var i = 0; i < msgs.length; i++) {
      var m = msgs[i];
      if (m.role !== "user" || m.side) continue;
      var t = clean(m.text);
      if (!t) continue;
      if (t.charAt(0) === "/") { fallback = fallback || t; continue; }
      return t.slice(0, 110);
    }
    return fallback.slice(0, 110);
  }

  function discover(known, force) {
    var found = {};

    // archives, oldest source
    list(ROOT).forEach(function (name) {
      var dir = ROOT + "/" + name + "/.claude/.claude-conversations";
      if (!isDir(dir)) return;
      list(dir).forEach(function (f) {
        if (!/\.json$/.test(f)) return;
        var id = f.replace(/\.json$/, "");
        found[id] = { id: id, project: name, cwd: ROOT + "/" + name, title: "",
                      path: dir + "/" + f, kind: "archive", mtime: mtime(dir + "/" + f),
                      sig: sig(dir + "/" + f) };
      });
    });

    // transcripts win, being richer
    list(PROJECTS).forEach(function (name) {
      var dir = PROJECTS + "/" + name;
      if (!isDir(dir)) return;
      list(dir).forEach(function (f) {
        if (!/\.jsonl$/.test(f)) return;
        var id = f.replace(/\.jsonl$/, ""), path = dir + "/" + f;
        var when = mtime(path), sg = sig(path);
        var kids = subagents(dir, id);
        if (kids.length) {
          sg += "|" + kids.map(function (k) { return k.sig; }).join(",");
        }
        var entry;
        var cached = known[id];
        if (!force && cached && cached.sig === sg && cached.kind !== "web") {
          // Its page is already current, so nothing in the file can have
          // changed. Reading a hundred megabytes to re-learn the project name
          // is the whole cost of a build where nothing happened.
          entry = { id: id, project: cached.project, cwd: cached.cwd,
                    title: cached.title || "", path: path, kind: "transcript",
                    mtime: when, sig: sg, agents: kids, cached: true };
        } else {
          var text = read(path);
          if (text === null) {
            // Unreadable, perhaps only for a moment. Keep it listed from what is
            // known, so the build reports it — dropping it here would have its
            // page pruned as if the session no longer existed.
            if (!cached) return;
            entry = { id: id, project: cached.project, cwd: cached.cwd,
                      title: cached.title || "", path: path, kind: "transcript",
                      mtime: when, sig: sg, agents: kids };
          } else {
            var p = peek(text);
            var cwd = p.cwd || cwdFromDirname(name);
            entry = { id: id, project: projectFromCwd(cwd), cwd: cwd,
                      title: p.title || "", path: path, kind: "transcript",
                      mtime: when, sig: sg, agents: kids };
          }
        }
        // The transcript stays under the directory the session was launched
        // in, and the cwd inside it says the same, so after a rename both
        // still name the old folder. The archive was written by a hook
        // running in the project as it is now, which makes it the authority
        // on where the work lives — while the transcript stays the better
        // source for the content, being uncapped.
        var prior = found[id];
        if (prior && prior.kind === "archive") {
          entry.project = prior.project;
          entry.cwd = prior.cwd;
        }
        found[id] = entry;
      });
    });

    // claude.ai conversations
    findExports().forEach(function (path) {
      var when = mtime(path), sg = sig(path);
      if (!force && exportsUnchanged(known, path, sg)) {
        Object.keys(known).forEach(function (id) {
          var e = known[id];
          if (e.kind === "web" && e.source === path) {
            found[id] = { id: id, project: e.project, cwd: "", title: e.title || "",
                          path: path, kind: "web", url: e.url, mtime: e.mtime,
                          sig: e.sig, source: path, sourceSig: sg, cached: true };
          }
        });
        return;
      }
      var text = read(path);
      if (text === null) return;
      var chats;
      try { chats = JSON.parse(text); } catch (e) { return; }
      if (!Array.isArray(chats)) return;
      chats.forEach(function (c) {
        if (!c || !c.uuid || !(c.chat_messages && c.chat_messages.length)) return;
        var chatWhen = c.updated_at || c.created_at;
        found[c.uuid] = {
          id: c.uuid, project: "claude.ai", cwd: "", title: c.name || "",
          path: path, kind: "web", chat: c,
          url: "https://claude.ai/chat/" + c.uuid,
          source: path, sourceSig: sg, sig: sg + ":" + (chatWhen || ""),
          mtime: chatWhen ? Math.round(new Date(chatWhen).getTime() / 1000) : when
        };
      });
    });

    return Object.keys(found)
      .filter(function (k) { return !HIDDEN[k] && k.indexOf("agent-") !== 0; })
      .map(function (k) { return found[k]; })
      .sort(function (a, b) { return b.mtime - a.mtime; });
  }

  // An export is one file holding many chats, so it is skipped as a whole:
  // if the file itself has not changed, none of its conversations have.
  function exportsUnchanged(known, path, sg) {
    var seen = false;
    for (var id in known) {
      if (known[id].kind === "web" && known[id].source === path) {
        seen = true;
        if (known[id].sourceSig !== sg) return false;
      }
    }
    return seen;
  }

  // ── search ──────────────────────────────────────────────────────────
  // The conversation, not the machinery: tool output is nearly half the text
  // and a match inside a command dump is rarely the one you wanted.
  function searchRows(msgs) {
    var rows = [];
    msgs.forEach(function (m, i) {
      if (m.role !== "user" && m.role !== "assistant") return;
      // Seconds, not the ISO string: a result shows when it was said and the
      // list is ordered by it, and this is a few bytes against several MB.
      var when = 0;
      if (m.timestamp) {
        var t = new Date(m.timestamp).getTime();
        if (!isNaN(t)) when = Math.round(t / 1000);
      }
      [["t", m.text], ["k", m.thinking]].forEach(function (pair) {
        var text = String(pair[1] == null ? "" : pair[1]).split(/\s+/).join(" ").trim();
        if (!text) return;
        rows.push([i, m.role === "assistant" ? pair[0] : "u", text, when]);
      });
    });
    return rows;
  }

  // One small script per session. A save then rewrites only the session that
  // changed; a single search file meant rewriting every conversation's text —
  // 3.7 MB — after every reply. U+2028/2029 are escaped: legal in JSON, not in
  // the string literals of older JavaScript engines.
  function searchScript(id, rows) {
    return "CH_SEARCH(" + JSON.stringify(id) + "," +
      JSON.stringify(rows).replace(/\u2028/g, "\\u2028").replace(/\u2029/g, "\\u2029") +
      ");\n";
  }

  // ── pages ───────────────────────────────────────────────────────────
  // Every placeholder is filled in one pass. Replacing them one after another
  // would let a conversation that quotes a placeholder — this project's own
  // sessions do — have a later replacement land inside its own data.
  var PLACEHOLDER = /\/\*\{\{(css|data|viewer|page|index)\}\}\*\//g;

  function fill(template, parts) {
    return template.replace(PLACEHOLDER, function (m, key) {
      return Object.prototype.hasOwnProperty.call(parts, key) ? parts[key] : m;
    });
  }

  function embed(value) {
    return JSON.stringify(value).split("</").join("<\\/");
  }

  var assets = {};
  function asset(name) {
    if (!(name in assets)) assets[name] = read(HERE + "/viewer/" + name) || "";
    return assets[name];
  }

  function sessionPage(meta, msgs, agents) {
    return fill(asset("page.html"), {
      css: asset("session.css"),
      data: embed({ meta: meta, messages: msgs, agents: agents || [] }),
      viewer: asset("viewer.js"),
      page: asset("page.js")
    });
  }

  function indexPage(entries, errors) {
    return fill(asset("index.html"), {
      css: asset("index.css"),
      data: embed({ sessions: entries, home: HOME, root: ROOT, errors: errors }),
      viewer: asset("viewer.js"),
      index: asset("index.js")
    });
  }

  // Each sub-agent gets a page of its own, beside its parent's, and the parent
  // is given only what it needs to link to it.
  function buildAgents(s, parentMeta) {
    var out = [];
    (s.agents || []).forEach(function (a) {
      var text = read(a.path);
      if (text === null) return;
      var msgs = fromJsonl(text);
      if (!msgs.length) return;
      var info = {};
      try { info = JSON.parse(read(a.metaPath) || "{}") || {}; } catch (e) { info = {}; }
      var rel = s.id + "/agent-" + a.agentId + ".html";
      write(OUT + "/sessions/" + rel, sessionPage({
        id: a.agentId, project: parentMeta.project, cwd: "", kind: "sub-agent",
        open: parentMeta.open || "",
        title: info.description || "a sub-agent", mtime: parentMeta.mtime,
        sig: a.sig, viewer: VIEWER, up: "../../index.html",
        agentType: info.agentType || "", model: info.model || "",
        parent: { id: s.id, title: parentMeta.title || "",
                  href: "../" + s.id + ".html" }
      }, msgs, []));
      out.push({
        id: a.agentId, href: rel, toolUseId: info.toolUseId || "",
        description: info.description || "", agentType: info.agentType || "",
        model: info.model || "", messages: msgs.length,
        prompts: msgs.filter(function (m) { return m.role === "user"; }).length
      });
    });
    return out;
  }

  // ── launchers ───────────────────────────────────────────────────────
  function resumable(meta) { return meta.kind !== "web" && !!meta.cwd; }

  function commandPath(meta) {
    var stem = String(meta.project || "").replace(/[^A-Za-z0-9_.-]/g, "_");
    return OUT + "/resume/" + stem + "-" + meta.id + ".command";
  }

  function writeCommand(meta) {
    var p = commandPath(meta);
    write(p, "#!/bin/bash\ncd " + JSON.stringify(meta.cwd) +
             " || exit 1\nexec claude --resume " + meta.id + "\n");
    chmodx(p);
    return p;
  }

  // ── pruning ─────────────────────────────────────────────────────────
  // Only files this program wrote are ever removed, and it knows them by name.
  // The pages directory may be one you already keep things in.
  var SESSION_ID = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

  function prune(keep) {
    var gone = 0;
    list(OUT + "/sessions").forEach(function (f) {
      if (!/\.html$/.test(f)) return;
      var id = f.replace(/\.html$/, "");
      if (SESSION_ID.test(id) && !(id in keep)) { remove(OUT + "/sessions/" + f); gone++; }
    });
    list(OUT + "/sessions").forEach(function (f) {
      // A folder of sub-agent pages belongs to the session it is named after.
      if (!SESSION_ID.test(f) || !isDir(OUT + "/sessions/" + f)) return;
      if (!(f in keep)) { remove(OUT + "/sessions/" + f); gone++; }
    });
    // Sub-agents were briefly listed as sessions of their own, which left a
    // page and a search file apiece.
    ["sessions", "search"].forEach(function (d) {
      list(OUT + "/" + d).forEach(function (f) {
        if (f.indexOf("agent-") === 0) { remove(OUT + "/" + d + "/" + f); gone++; }
      });
    });
    // Pages used to sit beside the index. Any left there are from that layout.
    list(OUT).forEach(function (f) {
      if (f === "index.html" || !/\.html$/.test(f)) return;
      var id = f.replace(/\.html$/, "");
      if (SESSION_ID.test(id)) { remove(OUT + "/" + f); gone++; }
    });
    list(OUT + "/resume").forEach(function (f) {
      if (!/\.command$/.test(f)) return;
      var stem = f.replace(/\.command$/, ""), id = stem.slice(-36);
      if (!SESSION_ID.test(id)) return;
      var entry = keep[id];
      if (!entry) { remove(OUT + "/resume/" + f); gone++; return; }
      // Renaming a project leaves a launcher pointing at a path that is gone.
      var wanted = commandPath({ id: id, project: entry.project });
      if (!resumable(entry) || OUT + "/resume/" + f !== wanted) {
        remove(OUT + "/resume/" + f); gone++;
      }
    });
    list(OUT + "/search").forEach(function (f) {
      var m = /^(.*)\.(js|json)$/.exec(f);
      if (!m || !SESSION_ID.test(m[1])) return;
      // .json is the old fragment format, only ever assembled into the single
      // search file; nothing reads it now.
      if (m[2] === "json" || !(m[1] in keep)) { remove(OUT + "/search/" + f); gone++; }
    });
    return gone;
  }

  // Conversations hidden from the index — claude.ai chats, which live on
  // claude.ai, so deleting the local copy would last only until the next
  // export. One id per line; delete a line to bring a chat back.
  var HIDDEN = {};
  (read(opt.hidden || HOME + "/.claude/claude-html.hidden") || "").split("\n")
    .forEach(function (l) { l = l.trim(); if (l) HIDDEN[l] = true; });

  // Pages carry the viewer inside them, so a page is only current if it was built
  // with the viewer as it is now. Without this, updating the tool would leave
  // every existing page on the old viewer until its conversation next changed.
  function hashText(t) {
    var h = 5381;
    for (var i = 0; i < t.length; i++) h = ((h << 5) + h + t.charCodeAt(i)) | 0;
    return (h >>> 0).toString(36);
  }
  var VIEWER = hashText(["page.html", "session.css", "viewer.js", "page.js"]
    .map(asset).join("\u0000"));

  // ── build ───────────────────────────────────────────────────────────
  var manifest = {};
  var raw = read(OUT + "/.manifest.json");
  if (raw) { try { manifest = JSON.parse(raw); } catch (e) { manifest = {}; } }

  var sessions = discover(manifest, FORCE);
  if (ONLY) {
    sessions = sessions.filter(function (s) { return s.id.indexOf(ONLY) === 0; });
    if (!sessions.length) return JSON.stringify({ error: "no session matching " + ONLY });
  }
  var everything = !ONLY;
  var force = FORCE || !!ONLY;   // naming a session is a request to rebuild it

  var fresh = everything ? {} : JSON.parse(JSON.stringify(manifest));
  var errors = [], built = 0, skipped = 0;

  sessions.forEach(function (s) {
    var page = OUT + "/sessions/" + s.id + ".html";
    var cached = manifest[s.id];
    if (!force && cached && exists(page) &&
        exists(OUT + "/search/" + s.id + ".js") &&
        cached.sig === s.sig && cached.viewer === VIEWER) {
      fresh[s.id] = cached;
      skipped++;
      return;
    }
    try {
      var msgs, kind = s.kind;
      if (s.kind === "transcript") {
        var text = read(s.path);
        if (text === null) throw new Error("cannot read " + s.path);
        msgs = fromJsonl(text);
      } else if (s.kind === "web") {
        msgs = fromExportChat(s.chat || chatFromExport(s.path, s.id));
      } else {
        var arch = read(s.path);
        if (arch === null) throw new Error("cannot read " + s.path);
        var parsed = JSON.parse(arch);
        var fixed = repairArchiveRoles(parsed.messages || []);
        msgs = fixed.messages;
        if (fixed.inferred) kind = "archive (inferred)";
      }
      if (!msgs.length) return;                       // nothing to show

      var meta = { id: s.id, project: s.project, cwd: s.cwd, kind: kind,
                   title: s.title || firstPrompt(msgs), mtime: s.mtime, sig: s.sig,
                   viewer: VIEWER,
                   // What the project crumb opens, when there is a folder to
                   // open: the same link the index's project name carries.
                   open: (s.cwd && kind !== "web") ? s.id : "",
                   up: "../index.html", home: HOME };
      if (s.url) meta.url = s.url;
      if (s.source) { meta.source = s.source; meta.sourceSig = s.sourceSig; }

      var agents = buildAgents(s, meta);
      write(page, sessionPage(meta, msgs, agents));
      write(OUT + "/search/" + s.id + ".js", searchScript(s.id, searchRows(msgs)));
      if (resumable(meta)) writeCommand(meta);
      else remove(commandPath(meta));

      meta.prompts = msgs.filter(function (m) {
        return m.role === "user" && !m.side;
      }).length;
      delete meta.home;
      meta.agents = agents.length;
      fresh[s.id] = meta;
      built++;
    } catch (e) {
      // A session that will not build is reported, never quietly missing — and
      // keeps its last good page and its place on the index. Without this it
      // would fall out of the list and be pruned, so one failed attempt would
      // cost a page that was fine a moment ago.
      errors.push({ id: s.id, source: s.path, error: String(e.message || e) });
      if (manifest[s.id]) fresh[s.id] = manifest[s.id];
    }
  });

  // The index and the search file describe every session, so they are written
  // from everything known, not only from what this run touched.
  var order = Object.keys(fresh)
    .filter(function (id) { return exists(OUT + "/sessions/" + id + ".html"); })
    .sort(function (a, b) { return (fresh[b].mtime || 0) - (fresh[a].mtime || 0); });

  var live = {};
  sessions.forEach(function (s) { live[s.id] = s.sig; });

  var entries = order.map(function (id) {
    var e = JSON.parse(JSON.stringify(fresh[id]));
    // A page built before its source changed is showing an old conversation.
    e.stale = live[id] !== undefined && live[id] !== e.sig;
    return e;
  });

  var removed = everything ? prune(fresh) : 0;

  // The single search file this replaced is no longer read by anything.
  remove(OUT + "/search-index.js");
  write(OUT + "/.manifest.json", JSON.stringify(fresh));
  // Archiving happens in the hook, before any of this. Its failures are left as
  // one file per session, so a later success clears exactly its own.
  var shown = errors.slice();
  list(OUT + "/.archive-errors").forEach(function (f) {
    if (!/\.json$/.test(f)) return;
    var t = read(OUT + "/.archive-errors/" + f);
    if (!t) return;
    try { var o = JSON.parse(t); if (o) shown.push(o); } catch (e) {}
  });
  write(OUT + "/index.html", indexPage(entries, shown));
  if (errors.length) write(OUT + "/.build-errors.json", JSON.stringify(errors));
  else remove(OUT + "/.build-errors.json");

  return JSON.stringify({
    sessions: order.length, built: built, skipped: skipped,
    removed: removed, errors: shown, out: OUT
  });
}

// osascript calls run() by itself; node has to be asked.
if (typeof $ === "undefined" && typeof require !== "undefined" &&
    typeof module !== "undefined" && require.main === module) {
  process.stdout.write(run(process.argv.slice(2)) + "\n");
}
