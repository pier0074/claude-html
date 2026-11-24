// The documentation keeps up with the code: every CLAUDE_HTML_ variable
// the scripts read is in docs/SETUP.md, SETUP.md names none they do not,
// and every relative link in the three documents (a picture in HTML too)
// reaches a file and, where it names one, a heading that exists.
//
//   node tests/docs.test.js
"use strict";
var fs = require("fs"), path = require("path");
var HERE = path.resolve(__dirname, "..");
var pass = 0, fail = 0;
function check(name, ok, detail) {
  if (ok) { pass++; return; }
  fail++;
  console.log("  FAIL  " + name + (detail ? "\n        " + detail : ""));
}

// ── variables ──
var code = ["claude-html", "helper.applescript", "tests/run-all.sh"]
  .concat(fs.readdirSync(HERE).filter(function (f) { return /\.(sh|js)$/.test(f); }))
  .concat(fs.readdirSync(path.join(HERE, "viewer")).filter(function (f) { return /\.js$/.test(f); })
    .map(function (f) { return "viewer/" + f; }));
function names(text) {
  var out = {};
  (text.match(/CLAUDE_HTML_[A-Z0-9]+(?:_[A-Z0-9]+)*/g) || []).forEach(function (n) { out[n] = true; });
  return out;
}
var inCode = {};
code.forEach(function (f) {
  var p = path.join(HERE, f);
  if (fs.existsSync(p)) Object.keys(names(fs.readFileSync(p, "utf8"))).forEach(function (n) { inCode[n] = f; });
});
var setup = fs.readFileSync(path.join(HERE, "docs", "SETUP.md"), "utf8"), inDoc = names(setup);
var missing = Object.keys(inCode).filter(function (n) { return !inDoc[n]; });
var extra = Object.keys(inDoc).filter(function (n) { return !inCode[n]; });
check("every variable the code reads is in SETUP.md (" + Object.keys(inCode).length + ")", !missing.length,
      "missing: " + missing.map(function (n) { return n + " (" + inCode[n] + ")"; }).join(", "));
check("SETUP.md names no variable the code does not read", !extra.length, "unknown: " + extra.join(", "));

// ── the command's flags ──
// Every flag claude-html and install.sh take is in SETUP.md's table of
// commands, and the table names none they do not take.
function flags(file) {
  var out = {}, re = /(--[a-z][-a-z]*)(?=[|)])/g, m, t = fs.readFileSync(path.join(HERE, file), "utf8");
  while ((m = re.exec(t)) !== null) out[m[1]] = true;
  return out;
}
var taken = Object.assign(flags("claude-html"), flags("install.sh"));
var cmds = setup.slice(setup.indexOf("## Commands"), setup.indexOf("\n## ", setup.indexOf("## Commands") + 5));
var tabled = {};
(cmds.match(/--[a-z][-a-z]*/g) || []).forEach(function (f) { tabled[f] = true; });
var untabled = Object.keys(taken).filter(function (f) { return !tabled[f]; });
var unknown = Object.keys(tabled).filter(function (f) { return !taken[f]; });
check("every flag of claude-html and install.sh is in SETUP.md's commands (" + Object.keys(taken).length + ")",
      !untabled.length, "missing: " + untabled.join(", "));
check("SETUP.md's commands name no flag they do not take", !unknown.length, "unknown: " + unknown.join(", "));

// ── links ──
// A heading's anchor as GitHub makes it: lower case, punctuation gone,
// spaces as hyphens, and -1, -2 … after a repeat.
function anchors(text) {
  var out = {}, seen = {};
  stripCode(text).split("\n").forEach(function (l) {
    var m = /^#{1,6}\s+(.*?)\s*#*\s*$/.exec(l);
    if (!m) return;
    var a = m[1].toLowerCase().replace(/[^\w\- ]+/g, "").replace(/ /g, "-");
    var k = seen[a] === undefined ? a : a + "-" + seen[a];
    seen[a] = (seen[a] || 0) + 1;
    out[k] = true;
  });
  return out;
}
function stripCode(text) {
  return text.replace(/```[\s\S]*?```/g, "").replace(/`[^`\n]*`/g, "");
}
var docs = ["README.md", "CHANGELOG.md", "docs/SETUP.md", "docs/DETAILS.md"], bad = [], total = 0;
docs.forEach(function (d) {
  var text = fs.readFileSync(path.join(HERE, d), "utf8"), re = /!?\[[^\]]*\]\(([^)\s]+)\)/g, m;
  var body = stripCode(text), targets = [];
  while ((m = re.exec(body)) !== null) targets.push(m[1]);
  // A picture written in HTML, to give it a width or a dark variant: its
  // src, and each file of a srcset.
  var tag = /<(?:img|source)\b[^>]*>/gi, attr = /\b(src|srcset)\s*=\s*"([^"]*)"/gi, a;
  while ((m = tag.exec(body)) !== null) {
    while ((a = attr.exec(m[0])) !== null) {
      if (a[1].toLowerCase() === "src") targets.push(a[2]);
      else a[2].split(",").forEach(function (c) { if (c.trim()) targets.push(c.trim().split(/\s+/)[0]); });
    }
  }
  targets.forEach(function (target) {
    if (/^(https?:|mailto:)/.test(target)) return;
    total++;
    var hash = target.indexOf("#"), file = hash > -1 ? target.slice(0, hash) : target;
    var anchor = hash > -1 ? target.slice(hash + 1) : "";
    var p = file ? path.resolve(path.dirname(path.join(HERE, d)), file) : path.join(HERE, d);
    if (!fs.existsSync(p)) { bad.push(d + " → " + target + " (no such file)"); return; }
    if (anchor && !anchors(fs.readFileSync(p, "utf8"))[anchor]) bad.push(d + " → " + target + " (no such heading)");
  });
});
check("every relative link in README, SETUP and DETAILS resolves (" + total + ")", !bad.length, bad.join("\n        "));
check("SETUP.md is linked from the README and DETAILS",
      /\(docs\/SETUP\.md\)/.test(fs.readFileSync(path.join(HERE, "README.md"), "utf8")) &&
      /\(SETUP\.md\)/.test(fs.readFileSync(path.join(HERE, "docs", "DETAILS.md"), "utf8")));

// ── the release number ──
// One number, in VERSION: the changelog's newest entry is that release,
// the command says it, and the README's pinned clone names it.
var version = fs.readFileSync(path.join(HERE, "VERSION"), "utf8").trim();
var log = fs.readFileSync(path.join(HERE, "CHANGELOG.md"), "utf8");
var newest = (/^## (\d+\.\d+\.\d+)/m.exec(log) || [])[1];
check("VERSION is a three-part number", /^\d+\.\d+\.\d+$/.test(version), version);
check("the changelog's newest entry is VERSION", newest === version, newest + " vs " + version);
var said = require("child_process").spawnSync("bash", [path.join(HERE, "claude-html"), "--version"],
  { encoding: "utf8", env: Object.assign({}, process.env, { HOME: "/nonexistent-home" }) });
check("claude-html --version says it, reading nothing else",
      said.status === 0 && said.stdout.trim() === "claude-html " + version, said.stdout + said.stderr);
check("the README's pinned clone names it",
      fs.readFileSync(path.join(HERE, "README.md"), "utf8").indexOf("--branch v" + version) > -1);

console.log("  " + pass + " passed, " + fail + " failed");
process.exitCode = fail ? 1 : 0;
