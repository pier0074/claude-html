// Helpers for tests/guard.test.sh: the notes a hook is handed, made from
// the fake secrets, and the check that guard.sh's quick look never lets
// through what the rules would catch.
//
//   node tests/guard.test.js fixture <dir>      notes, probes and the rule list
//   node tests/guard.test.js anchors            every text a rule starts at is in guard.sh's list
"use strict";
var fs = require("fs"), path = require("path");
var F = require("./fixtures/fake-secrets");
var HERE = path.resolve(__dirname, "..");
var args = process.argv.slice(2);

// The rules the guard uses, as guard.js names them.
var SURE = /var SURE = \{\};\s*\(([\s\S]*?)\)\.split/.exec(fs.readFileSync(path.join(HERE, "actions/guard.js"), "utf8"))[1]
  .replace(/["+\s]+/g, " ").trim().split(" ");

// guard.sh's quick look, the expression given in a file, tried as the hook
// tries it (grep, any case, on the note as JSON) on every fake secret of
// every rule, in many surroundings, and on prose that holds none:
//   node tests/guard.test.js quick <expression file>
// prints { tried, found, missed: [rule…], slow: [prose…] }: missed, a text
// the rules find a secret in that the quick look would let through; slow,
// prose that holds none and is still sent on to the rules.
if (args[0] === "quick") {
  var expr = fs.readFileSync(args[1], "utf8").replace(/\n$/, "");
  var src = fs.readFileSync(path.join(HERE, "build/redact.js"), "utf8");
  var lib = new Function(src + "\nreturn [claudeHtmlRedactor];")();
  var all = lib[0]("", true, true);
  // The fields guard.sh takes out before it looks, taken out alike.
  var STRIP = /"(transcript_path|cwd|session_id|permission_mode|hook_event_name|tool_use_id|tool_name|agent_id|agent_type)"\s*:\s*"[^"]*"/g;
  function notes(text) {
    return [{ session_id: "sess-1", hook_event_name: "UserPromptSubmit", prompt: text },
            { session_id: "sess-1", hook_event_name: "PreToolUse", tool_name: "Bash",
              tool_input: { command: text, description: "a command" } }]
      .map(function (o) { return JSON.stringify(o).replace(STRIP, ""); });
  }
  // Each secret as written, and with its spaces made line breaks, tabs,
  // runs of spaces, a no-break space, a form feed, and its quotes escaped.
  var texts = [];
  F.cases.forEach(function (c) {
    var t = c.text;
    [t, t.replace(/ /g, "\n"), t.replace(/ /g, "\t"), t.replace(/ /g, "   "), t.replace(/ /g, "\u00a0"),
     t.replace(/ /g, "\f"), t.replace(/ /g, "\u2003"), t.replace(/"/g, '\\"'), "x\n" + t + "\ny",
     JSON.stringify({ text: t })].forEach(function (v) { texts.push({ rule: c.rule, text: v }); });
  });
  // And every line of the docs, the scripts and the suites: real prose and
  // real commands, a few of which the rules do find something in.
  F.clean.forEach(function (t) { texts.push({ rule: "clean", text: t }); });
  ["README.md", "docs/DETAILS.md", "docs/SETUP.md", "CHANGELOG.md", "claude-html", "save-conversation.sh",
   "install.sh", "lib/platform.sh", "tests/guard.test.sh", "tests/linux.test.sh", "tests/redact.test.sh"].forEach(function (f) {
    fs.readFileSync(path.join(HERE, f), "utf8").split("\n").forEach(function (l) { texts.push({ rule: f, text: l }); });
  });
  var PROSE = ["please fix the failing test in src/app.js", "that is right, go through the media folder",
    "mkdir -p build && ls -la", "the keyboard shortcut for this is broken", "pass the tests again",
    "the token count went up after the change", "git push -u origin main", "read the authentication docs",
    "a passing build, and the monkey wrench emoji", "see https://github.com/owner/repo/issues/12",
    "docker run -p 8080:80 nginx", "ssh -p 2222 host", "highlight the key points", "the cookie banner is ugly",
    "rename secretary to assistant", "the API key rotation is documented in docs/keys.md",
    "use the right gh command to open the PR", "Asia and Africa"];
  var lines = [], who = [];
  texts.forEach(function (t, i) {
    if (!all.find(t.text).length) return;
    notes(t.text).forEach(function (n) { lines.push(n); who.push(i); });
  });
  var prose0 = lines.length;
  PROSE.forEach(function (p) { notes(p).forEach(function (n) { lines.push(n); }); });
  var r = require("child_process").spawnSync("grep", ["-niE", "-e", expr], {
    input: Buffer.from(lines.join("\n") + "\n", "utf8"), encoding: "utf8", env: Object.assign({}, process.env, { LC_ALL: "C" })
  });
  var hit = {};
  String(r.stdout || "").split("\n").forEach(function (l) { var m = /^(\d+):/.exec(l); if (m) hit[m[1] - 1] = true; });
  var missed = [], slow = [];
  for (var k = 0; k < prose0; k++) if (!hit[k] && missed.indexOf(texts[who[k]].rule) < 0) missed.push(texts[who[k]].rule);
  for (k = prose0; k < lines.length; k++) if (hit[k]) slow.push(PROSE[(k - prose0) >> 1]);
  console.log(JSON.stringify({ tried: lines.length, found: prose0, missed: missed,
                               slow: slow.filter(function (v, i, a) { return a.indexOf(v) === i; }), grep: r.status }));
  process.exit(0);
}

// What the window's boxes must show for a note, worked out here on its own
// from what the rules find: each match with 40 characters on each side,
// line breaks as ⏎, the match between \u0001 and \u0002; the command whole,
// its matches marked; details.txt, the two for a Linux window, marked « ».
//   node tests/guard.test.js expect <note file> prompt|bash <out dir>
if (args[0] === "expect") {
  var note = JSON.parse(fs.readFileSync(args[1], "utf8")), bash = args[2] === "bash", out = args[3];
  var text = bash ? note.tool_input.command : note.prompt;
  var src = fs.readFileSync(path.join(HERE, "build/redact.js"), "utf8");
  var lib = new Function(src + "\nreturn [claudeHtmlRedactor];")();
  var sure = {}; SURE.forEach(function (r) { sure[r] = true; });
  var LABEL = JSON.parse(/var LABEL = (\{[\s\S]*?\});/.exec(fs.readFileSync(path.join(HERE, "actions/guard.js"), "utf8"))[1]
    .replace(/([{,]\s*)([a-z]+):/g, '$1"$2":').replace(/"(?:[^"\\]|\\.)*"/g, function (q) { return q; }));
  var taken = [], lines = [];
  lib[0]("", true, true, sure).find(text).forEach(function (m) {
    var i = text.indexOf(m.value);
    while (taken.some(function (t) { return i < t[1] && i + m.value.length > t[0]; })) i = text.indexOf(m.value, i + 1);
    taken.push([i, i + m.value.length]);
    var a = Math.max(0, i - 40), b = Math.min(text.length, i + m.value.length + 40);
    var fl = function (x) { return x.split("\r\n").join("\n").split("\n").join(" \u23ce "); };
    lines.push(LABEL[m.rule] + ":  " + (a > 0 ? "\u2026" : "") + fl(text.slice(a, i)) + "\u0001" + m.value + "\u0002" +
      fl(text.slice(i + m.value.length, b)) + (b < text.length ? "\u2026" : ""));
  });
  fs.writeFileSync(path.join(out, "found"), lines.join("\n"));
  var txt = "What was found (shown on this screen only, kept nowhere):\n\n" + lines.join("\n");
  if (bash) {
    taken.sort(function (x, y) { return x[0] - y[0]; });
    var marked = "", at = 0;
    taken.forEach(function (t) { marked += text.slice(at, t[0]) + "\u0001" + text.slice(t[0], t[1]) + "\u0002"; at = t[1]; });
    fs.writeFileSync(path.join(out, "command"), marked + text.slice(at));
    txt += "\n\n\nThe whole command, as Claude wrote it:\n\n" + text;
  }
  fs.writeFileSync(path.join(out, "details.txt"), txt.split("\u0001").join("\u00ab").split("\u0002").join("\u00bb") + "\n");
  process.exit(0);
}

if (args[0] === "fixture") {
  var T = args[1];
  // One note per fake secret of a rule the guard uses: as a prompt, and as
  // a Bash command.
  var sure = F.cases.filter(function (c) { return SURE.indexOf(c.rule) > -1; });
  var lines = sure.map(function (c, i) {
    return JSON.stringify({ i: i, rule: c.rule,
      prompt: { session_id: "sess-1", hook_event_name: "UserPromptSubmit", cwd: "/tmp/x",
                transcript_path: "/tmp/-Users-Pat/a.jsonl", permission_mode: "default", prompt: "look: " + c.text },
      bash: { session_id: "sess-1", hook_event_name: "PreToolUse", tool_name: "Bash", permission_mode: "default",
              tool_input: { command: "echo " + c.text, description: "a command" } } });
  });
  fs.writeFileSync(path.join(T, "cases.jsonl"), lines.join("\n") + "\n");
  fs.writeFileSync(path.join(T, "probes.txt"), F.probes().join("\n") + "\n");
  // A secret of each of two kinds, and the weak form, which passes.
  var gh = F.cases.filter(function (c) { return c.rule === "github"; })[0];
  var url = F.cases.filter(function (c) { return c.rule === "url-password"; })[0];
  var my = F.cases.filter(function (c) { return c.rule === "mysql-password"; })[0];
  function note(o) { return JSON.stringify(Object.assign({ session_id: "sess-1", hook_event_name: "UserPromptSubmit" }, o)); }
  var notes = {
    clean: note({ prompt: "please fix the failing test in src/app.js" }),
    weak: note({ prompt: "the db password: wrong, and reset your token" }),
    secret: note({ prompt: "deploy with " + gh.text + " and " + url.text }),
    secret2: note({ session_id: "sess-2", prompt: "deploy with " + gh.text + " and " + url.text }),
    other: note({ prompt: "and " + F.cases[0].text }),
    clean2: note({ session_id: "sess-2", prompt: "please fix the failing test in src/app.js" }),
    // A sub-agent's report, as Claude Code hands it over: passes; text
    // typed before or after one does not.
    notify: note({ prompt: "<task-notification>\n<task-id>a1</task-id>\n<result>run it with " + gh.text +
      "</result>\n</task-notification>\n<task-notification>\n<task-id>a2</task-id>\n</task-notification>\n" }),
    notify_after: note({ prompt: "<task-notification>\n<result>ok</result>\n</task-notification>\nand " + gh.text }),
    notify_before: note({ prompt: gh.text + "\n<task-notification>\n<result>ok</result>\n</task-notification>" }),
    w_cancel: note({ prompt: "cancel" }), w_allow: note({ prompt: " Allow " }), w_safe: note({ prompt: "safe" }),
    w_stop: note({ prompt: "STOP" }), w_stop2: note({ session_id: "sess-2", prompt: "stop" }),
    bash_mysql: JSON.stringify({ session_id: "sess-1", hook_event_name: "PreToolUse", tool_name: "Bash",
      permission_mode: "default", tool_input: { command: my.text } }),
    bash_multi: JSON.stringify({ session_id: "sess-1", hook_event_name: "PreToolUse", tool_name: "Bash",
      permission_mode: "default", tool_input: { command: "echo \"a\\b\" " + my.text + "\nsecond line" } }),
    bash_url: JSON.stringify({ session_id: "sess-1", hook_event_name: "PreToolUse", tool_name: "Bash",
      permission_mode: "default", tool_input: { command: "curl " + url.text.replace(/^[^ ]* /, "") } }),
    bash_bypass: JSON.stringify({ session_id: "sess-1", hook_event_name: "PreToolUse", tool_name: "Bash",
      permission_mode: "bypassPermissions", tool_input: { command: my.text } }),
    bash_clean: JSON.stringify({ session_id: "sess-1", hook_event_name: "PreToolUse", tool_name: "Bash",
      permission_mode: "default", tool_input: { command: "mkdir -p build && ls -la" } }),
    write_tool: JSON.stringify({ session_id: "sess-1", hook_event_name: "PreToolUse", tool_name: "Write",
      tool_input: { file_path: "/tmp/x", content: gh.text } })
  };
  // A long command, as Claude writes one: a heredoc of thirty lines, a key
  // in the middle, lines longer than any window.
  var key = F.cases.filter(function (c) { return c.rule === "env-name"; })[2].secret;
  var doc = ["cat > deploy.sh <<'EOF'", "#!/bin/bash", "set -euo pipefail",
    "# Deploy the weather service: build it, push the image, restart the units, then check that it answers."];
  for (var n = 1; doc.length < 14; n++) doc.push("echo \"step " + n + " of 26: preparing the release directory /srv/weather/releases/2026-11-24/build-" + n + "\"");
  doc.push("export " + ["API", "_KEY"].join("") + "=" + key);
  for (n = 1; doc.length < 28; n++) doc.push("curl -fsS -H \"X-Request: deploy-" + n + "\" https://weather.internal/api/v2/health/check?verbose=1&n=" + n);
  doc.push("EOF", "chmod +x deploy.sh && ./deploy.sh");
  notes.bash_heredoc = JSON.stringify({ session_id: "sess-1", hook_event_name: "PreToolUse", tool_name: "Bash",
    permission_mode: "default", cwd: "/tmp/Weather", tool_input: { command: doc.join("\n") } });
  Object.keys(notes).forEach(function (k) { fs.writeFileSync(path.join(T, "note." + k), notes[k]); });
  fs.writeFileSync(path.join(T, "sure.txt"), SURE.join("\n") + "\n");
  process.exit(0);
}
