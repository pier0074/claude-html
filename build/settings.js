// Every user setting, as lib/settings.tsv describes it, and the one check of
// a value in JavaScript: what the Settings page uses to mark a field and to
// build its claude-html://settings link, and what the tests run under node
// and osascript to hold it to the shell's (lib/settings.sh, which checks
// with the setting's own shell code before anything is written).
//
//   var S = claudeHtmlSettings(<the tsv's text>, CH.parseReset);
//   S.list, S.groups, S.byKey[key]
//   S.check(key, value)      {ok, value, unset, why}
//   S.linkFor(fp, changes)   the claude-html://settings link, or null if too long
//   S.commandFor(changes)    the same as claude-html --config lines
//
// A change is {key, op: "set"|"unset"|"forget", value}. The grammar of the
// link is lib/settings.sh's; parseReset is the dashboard's own reader of
// CLAUDE_HTML_WEEK_RESET (viewer.js), handed in rather than copied.
function claudeHtmlSettings(tsv, parseReset) {
  "use strict";
  var groups = [], list = [], byKey = {};
  String(tsv || "").split("\n").forEach(function (line) {
    if (!line || line.charAt(0) === "#") return;
    var f = line.split("\t").map(function (c) { return c === "-" ? "" : c; });
    if (f[0].charAt(0) === "@") { groups.push({ id: f[0].slice(1), title: f[1] || "" }); return; }
    if (!/^(CLAUDE_HTML_|CH_)[A-Z0-9_]+$/.test(f[0]) || f.length < 9) return;
    var flags = {};
    f[7].split(",").forEach(function (x) {
      if (!x) return;
      var i = x.indexOf(":");
      if (i < 0) flags[x] = true; else flags[x.slice(0, i)] = x.slice(i + 1);
    });
    var s = { key: f[0], name: f[0].replace(/^CLAUDE_HTML_/, ""), group: f[1], label: f[2], kind: f[3],
              values: f[4] ? f[4].split("|") : [], def: f[5], anchor: f[6], flags: flags, help: f[8] };
    s.editable = !flags.ro && !flags.env && !flags.panel && !flags.hidden;
    list.push(s); byKey[s.key] = s;
  });

  // CLAUDE_HTML_GUARD_WAIT, read as ch_wait_secs reads it: 45, 45s, 2m or
  // 1m30s, from 30 seconds to 60 minutes. 1 for what is not a wait, 2 for
  // one out of range.
  function waitSecs(text) {
    var t = String(text).replace(/^\s+|\s+$/g, ""), wm = "0", wx = "0", i;
    if (!t || /[^0-9mMsS]/.test(t)) return { bad: 1 };
    if (/^[0-9].*[mM][0-9].*[sS]$/.test(t)) { i = t.search(/[mM]/); wm = t.slice(0, i); wx = t.slice(i + 1, -1); }
    else if (/^[0-9].*[mM]$/.test(t)) wm = t.slice(0, -1);
    else if (/^[0-9].*[sS]$/.test(t)) wx = t.slice(0, -1);
    else wx = t;
    var parts = [wm, wx];
    for (i = 0; i < 2; i++) {
      if (!/^[0-9]+$/.test(parts[i])) return { bad: 1 };
      if (parts[i].length > 5) return { bad: 2 };
    }
    if (/[mM].*[sS]/.test(t) && +wx >= 60) return { bad: 1 };
    var v = +wm * 60 + +wx;
    return v >= 30 && v <= 3600 ? { secs: v } : { bad: 2 };
  }

  // A path as a setting takes one: from / or ~/, no . or .. in it, no
  // control character and none of " ` $ \, 512 characters at most.
  function pathWhy(v) {
    if (!/^(\/|~\/)/.test(v)) return "a path is written from / or ~/";
    if (/[\u0000-\u001f\u007f"`$\\]/.test(v)) return "a path may not hold a control character, \", `, $ or \\";
    if (/(^|\/)\.\.?(\/|$)/.test(v)) return "a path may not go through . or ..";
    if (v.length > 512) return "a path of 512 characters at most";
    return "";
  }

  var WAIT_WORDS = "from 30 seconds to 60 minutes, written 45, 45s, 2m or 1m30s";
  function check(key, value) {
    var s = byKey[key];
    if (!s) return { ok: false, why: "no such setting" };
    var v = String(value === undefined || value === null ? "" : value).replace(/^\s+|\s+$/g, "");
    if (s.flags.ro) return { ok: false, why: "set by ./install.sh " + (key === "CLAUDE_HTML_OUT" ? "--out" : "--root") + " DIR" };
    if (s.flags.env) return { ok: false, why: "read from the environment only, never from the conf" };
    if (!v) return { ok: false, why: "empty: claude-html --config unset " + s.name + " puts the default back" };
    if (s.kind === "enum") {
      var lv = v.toLowerCase();
      if (s.values.indexOf(lv) < 0) return { ok: false, why: "one of " + s.values.join(", ") };
      return lv === s.def ? { ok: true, unset: true, value: "" } : { ok: true, value: lv };
    }
    if (s.kind === "duration") {
      var w = waitSecs(v);
      if (w.bad) return { ok: false, why: (w.bad === 2 ? "out of range: " : "not a wait: ") + WAIT_WORDS };
      return { ok: true, value: v, secs: w.secs };
    }
    if (s.kind === "week") {
      var r = parseReset ? parseReset(v) : null;
      if (!r || !r.ok) return { ok: false, why: "not a day and an hour: tue 07:00 UTC, thu 17, Friday 8:30" };
      return { ok: true, value: r.spec };
    }
    if (s.kind === "path") {
      var why = pathWhy(v);
      return why ? { ok: false, why: why } : { ok: true, value: v };
    }
    return { ok: false, why: "set in the Limits & budget panel" };
  }

  // The link: a value percent-encoded, every character but A-Z a-z 0-9 . _ ~ -.
  function enc(v) {
    return encodeURIComponent(v).replace(/[!'()*]/g, function (c) {
      return "%" + c.charCodeAt(0).toString(16).toUpperCase();
    });
  }
  var MAX = 2048;
  function linkFor(fp, changes) {
    var items = changes.map(function (c) {
      if (c.op === "forget") return "forget-safe";
      var n = byKey[c.key] ? byKey[c.key].name : c.key;
      return c.op === "unset" ? n : n + "=" + enc(c.value);
    });
    var payload = "v1/" + (/^[0-9a-f]{16}$/.test(fp || "") ? fp : "none") + "/" + items.join("/");
    if (!items.length || items.length > 24 || payload.length > MAX) return null;
    return "claude-html://settings/" + payload;
  }
  function shq(s) { return /^[A-Za-z0-9._~\/:@%+=,-]+$/.test(s) ? s : "'" + s.replace(/'/g, "'\\''") + "'"; }
  function commandFor(changes) {
    var sets = [], unsets = [], forget = false;
    changes.forEach(function (c) {
      var n = byKey[c.key] ? byKey[c.key].name : c.key;
      if (c.op === "forget") forget = true;
      else if (c.op === "unset") unsets.push(n);
      else sets.push(shq(n + "=" + c.value));
    });
    var out = [];
    if (sets.length) out.push("claude-html --config set " + sets.join(" "));
    if (unsets.length) out.push("claude-html --config unset " + unsets.join(" "));
    if (forget) out.push("claude-html --config forget-safe");
    return out.join("\n");
  }

  return { list: list, groups: groups, byKey: byKey, check: check, waitSecs: waitSecs,
           linkFor: linkFor, commandFor: commandFor, MAX: MAX };
}

if (typeof module !== "undefined" && module.exports) module.exports = claudeHtmlSettings;
