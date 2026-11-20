// Helpers for tests/guard.test.sh: the notes a hook is handed, made from
// the fake secrets, and the check that guard.sh's quick look never lets
// through what the rules would catch.
//
//   node tests/guard.test.js fixture <dir>      notes, probes and the rule list
//   node tests/guard.test.js anchors            every text a rule starts at is in guard.sh's list
"use strict";
var fs = require("fs"), path = require("path");
var F = require("./fake-secrets");
var HERE = path.resolve(__dirname, "..");
var args = process.argv.slice(2);

// The rules the guard uses, as guard.js names them.
var SURE = /var SURE = \{\};\s*\(([\s\S]*?)\)\.split/.exec(fs.readFileSync(path.join(HERE, "guard.js"), "utf8"))[1]
  .replace(/["+\s]+/g, " ").trim().split(" ");

if (args[0] === "anchors") {
  var src = fs.readFileSync(path.join(HERE, "redact.js"), "utf8");
  var sh = fs.readFileSync(path.join(HERE, "guard.sh"), "utf8");
  var list = /^ANCHORS='([^']*)'/m.exec(sh)[1].split("|");
  var found = [], re = /\["((?:[^"\\]|\\.)*)", (true|false), /g, m;
  var body = src.slice(src.indexOf("var ANCHORS = ["), src.indexOf("function named("));
  while ((m = re.exec(body)) !== null) found.push(JSON.parse('"' + m[1] + '"'));
  // The cut mark is redact.js's own, never typed.
  found = found.filter(function (a) { return a.indexOf("…") < 0; });
  var CUT = body.indexOf("[CUT, false") > -1;
  var missing = found.filter(function (a) { return list.indexOf(a.toLowerCase()) < 0; });
  console.log(JSON.stringify({ anchors: found.length, missing: missing, cut: CUT }));
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
    w_cancel: note({ prompt: "cancel" }), w_allow: note({ prompt: " Allow " }), w_safe: note({ prompt: "safe" }),
    w_stop: note({ prompt: "STOP" }), w_stop2: note({ session_id: "sess-2", prompt: "stop" }),
    bash_mysql: JSON.stringify({ session_id: "sess-1", hook_event_name: "PreToolUse", tool_name: "Bash",
      permission_mode: "default", tool_input: { command: my.text } }),
    bash_url: JSON.stringify({ session_id: "sess-1", hook_event_name: "PreToolUse", tool_name: "Bash",
      permission_mode: "default", tool_input: { command: "curl " + url.text.replace(/^[^ ]* /, "") } }),
    bash_bypass: JSON.stringify({ session_id: "sess-1", hook_event_name: "PreToolUse", tool_name: "Bash",
      permission_mode: "bypassPermissions", tool_input: { command: my.text } }),
    bash_clean: JSON.stringify({ session_id: "sess-1", hook_event_name: "PreToolUse", tool_name: "Bash",
      permission_mode: "default", tool_input: { command: "mkdir -p build && ls -la" } }),
    write_tool: JSON.stringify({ session_id: "sess-1", hook_event_name: "PreToolUse", tool_name: "Write",
      tool_input: { file_path: "/tmp/x", content: gh.text } })
  };
  Object.keys(notes).forEach(function (k) { fs.writeFileSync(path.join(T, "note." + k), notes[k]); });
  fs.writeFileSync(path.join(T, "sure.txt"), SURE.join("\n") + "\n");
  process.exit(0);
}
