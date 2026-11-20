// The redactor on its own: every rule catches its fake secret, what merely
// looks like one is left alone, a second pass changes nothing, the owner's
// own list works and refuses what it cannot use, and the two ways of
// finding where a secret could start — node's and osascript's — agree, as
// do the two engines themselves.
//
//   node tests/redact.test.js [--engine node|osascript]
//   node tests/redact.test.js fixture <dir>    the sandbox redact.test.sh saves
//
// Nothing here prints a secret: a failure names the rule and the case.
"use strict";
var fs = require("fs"), path = require("path"), os = require("os"), cp = require("child_process");
var F = require("./fake-secrets");

var HERE = path.resolve(__dirname, "..");
var SRC = fs.readFileSync(path.join(HERE, "redact.js"), "utf8");
var make = new Function(SRC + "\nreturn claudeHtmlRedactor;")();
var args = process.argv.slice(2);

if (args[0] === "fixture") { fixture(args[1]); process.exit(0); }
if (args[0] === "hook-fixture") { hookFixture(args[1]); process.exit(0); }

var ENGINE = args.indexOf("--engine") > -1 ? args[args.indexOf("--engine") + 1] : "node";
var pass = 0, fail = 0;
function check(name, ok, detail) {
  if (ok) { pass++; return; }
  fail++;
  console.log("  FAIL  " + name + (detail ? "\n        " + detail : ""));
}
function leaks(text) {
  return F.probes().filter(function (p) { return text.indexOf(p) > -1; }).length;
}

// ── every rule, both ways of looking ──
[true, false].forEach(function (compiled) {
  var how = compiled ? "one expression" : "indexOf";
  F.cases.forEach(function (c, i) {
    var r = make("", true, compiled), out = r.text(c.text);
    check(how + ": " + c.rule + " (case " + i + ") is masked", out.indexOf(c.secret) < 0 && leaks(out) === 0);
    check(how + ": " + c.rule + " (case " + i + ") is counted under its name", r.counts[c.rule] > 0,
          "counted as " + Object.keys(r.counts).join(", "));
    check(how + ": " + c.rule + " (case " + i + ") is masked with exactly ***", out.indexOf("***") > -1 &&
          !/\*{4}/.test(out));
    check(how + ": " + c.rule + " (case " + i + ") twice is once", r.text(out) === out);
  });
  F.clean.forEach(function (t, i) {
    var out = make("", true, compiled).text(t);
    check(how + ": left alone (clean " + i + ")", out === t, out === t ? "" : "became " + out.slice(0, 80));
  });
});

// The name stays, only the value goes; the user and host of a URL stay.
(function () {
  var r = make("", true, true), pw = F.rnd(14);
  check("an assignment keeps its name", r.text("export DB_PASSWORD=" + pw) === "export DB_PASSWORD=***");
  check("a quoted one keeps its quotes", r.text('"password": "' + pw + '"') === '"password": "***"');
  check("a URL keeps its user and host", r.text("redis://app:" + pw + "@cache:6379/0") === "redis://app:***@cache:6379/0");
  check("a header keeps its scheme", r.text("Authorization: Bearer " + pw + F.rnd(12)) === "Authorization: Bearer ***");
})();

// ── where a cut falls ──
// A secret the cap would halve: redacted before the cut, so no part of it
// is left; and in a text already cut, as an old archive holds, what is left
// before the mark is masked too.
(function () {
  var r = make("", true, true), tok = "gh" + "p_" + F.rnd(36);
  var cutOld = r.text("see " + tok.slice(0, 12) + "\n…[truncated]");
  check("what a cut left of a token is masked", cutOld === "see ***\n…[truncated]", cutOld);
  var pem = "-----BEGIN " + "PRIVATE KEY-----\n" + F.rnd(64) + "\n" + F.rnd(20) + "\n…[truncated]";
  check("what a cut left of a key block is masked", r.text(pem) === "***\n…[truncated]");
  var pw = F.rnd(4);
  check("what a cut left of a password is masked, however short",
        r.text("password=" + pw + "\n…[truncated]") === "password=***\n…[truncated]");
})();

// ── the owner's own list ──
(function () {
  var lit = "Zebra" + "-Quokka-" + "7731", word = "Mango" + "4821";
  var list = ["# my own secrets", lit, "/Mango\\d{4}/", "/[unclosed/", "/x*/", "/\\*/", "**", "", "/abc/y"].join("\n");
  var r = make(list, true, true);
  check("the own list counts what it can use", r.own === 2, "own " + r.own);
  check("and lists the lines it cannot, by number", r.ignored.join(",") === "4,5,6,7,9", r.ignored.join(","));
  var out = r.text("a " + lit + " and " + word + " and xxx and ** stars");
  check("a plain line is masked where it appears", out.indexOf(lit) < 0 && out.indexOf(word) < 0);
  check("  and nothing else is touched", out === "a *** and *** and xxx and ** stars", out);
  check("  and counted as the own list", r.counts["own list"] === 1 && r.counts["own line 3"] === 1,
        JSON.stringify(r.counts));
  check("  twice is once", r.text(out) === out);
  check("an empty list is no list", make("\n\n# nothing\n", true, true).own === 0);
  var t = make(list, true, false).text("a " + lit + " and " + word);
  check("indexOf agrees", t === make(list, true, true).text("a " + lit + " and " + word));
})();

// ── off ──
(function () {
  var r = make("anything", false, true);
  check("off leaves every case as it was", F.cases.every(function (c) { return r.text(c.text) === c.text; }));
})();

// ── the two ways agree, on texts made of all of it, shuffled ──
var corpus = (function () {
  var seed = 7, out = [];
  function rand(n) { seed = (seed * 48271) % 2147483647; return seed % n; }
  var bits = F.cases.map(function (c) { return c.text; }).concat(F.clean,
    ["password", "=", " ", "\n", ":", "--", "-u ", "token", "://", "@", "sk-", "eyJ", "…[truncated", "İ", "\u212A", "🙂", "\"", "'"]);
  for (var i = 0; i < 400; i++) {
    var s = "";
    for (var k = rand(12); k >= 0; k--) s += bits[rand(bits.length)];
    out.push(s);
  }
  return out;
})();
(function () {
  var a = make("", true, true), b = make("", true, false), bad = 0, again = 0;
  corpus.forEach(function (s) {
    var x = a.text(s);
    if (x !== b.text(s)) bad++;
    if (a.text(x) !== x) again++;
  });
  check("one expression and indexOf redact " + corpus.length + " shuffled texts alike", bad === 0, bad + " differ");
  check("  and a second pass changes none of them", again === 0, again + " changed");
  check("  with the same counts", JSON.stringify(a.counts) === JSON.stringify(b.counts));
})();

// ── a parsed record, at any depth ──
(function () {
  var r = make("", true, true), tok = "gh" + "p_" + F.rnd(36);
  var input = { command: "echo " + tok, headers: { list: [1, null, { deep: "x " + tok }] }, password: tok };
  var keys = JSON.stringify(Object.keys(input));
  r.value(input);
  check("a tool input is masked at every depth", JSON.stringify(input).indexOf(tok) < 0);
  check("  its keys and other values are kept", JSON.stringify(Object.keys(input)) === keys &&
        input.headers.list[0] === 1 && input.headers.list[1] === null);
})();

// ── a value whose key says secret, with no known prefix ──
// Masked whether the object is walked a value at a time, as the pages
// and archives do, or turned to text first and read as one.
(function () {
  [true, false].forEach(function (compiled) {
    var how = compiled ? "one expression" : "indexOf", v = F.rnd(16);
    function obj() {
      return { command: "ls", env: { nested: { api_key: v } }, token: v, password: v,
               headers: { Authorization: "Bearer " + v, "x-api-key": v, Cookie: "session=" + v },
               apiKey: v, clientSecret: v, accessToken: v, authToken: v, DB_PASS: v, list: { password: [v] },
               keep: { tokens: "12k", primary_key: "id2", count: { token: 5 }, password: "${PW}", token: "string",
                       token_count: "4096", password_hash: "bcrypt", tokenizer: "gpt2-large" } };
    }
    var r = make("", true, compiled), o = obj(), kept = JSON.stringify(obj().keep);
    r.value(o);
    var t = JSON.stringify(o);
    check(how + ": a secret under a key that says so is masked, at any depth", t.indexOf(v) < 0, t.slice(0, 160));
    check(how + ":   counted as key-value", r.counts["key-value"] >= 12, JSON.stringify(r.counts));
    check(how + ":   and keys that do not say so, or stand-ins, are kept", JSON.stringify(o.keep) === kept,
          JSON.stringify(o.keep));
    // Strong: any value but a stand-in, letters or digits alone too.
    var r2 = make("", true, compiled), lo = { password: "plumquokka", token: "908172", keep: { password: "password", token: "string", label: "Mot de passe" } };
    r2.value(lo);
    check(how + ": under a secret key, letters or digits alone are masked too",
          lo.password === "***" && lo.token === "***", JSON.stringify(lo));
    check(how + ":   but not a stand-in or a label", JSON.stringify(lo.keep) === '{"password":"password","token":"string","label":"Mot de passe"}');
    var flat = make("", true, compiled).text(JSON.stringify(obj()));
    check(how + ": the same object as text is masked too", flat.indexOf(v) < 0);
  });
})();

// ── osascript runs the same file to the same result ──
if (ENGINE === "osascript") (function () {
  var T = fs.mkdtempSync(path.join(fs.realpathSync(process.env.TMPDIR || os.tmpdir()), "chredact."));
  try {
    var own = "Zebra" + "-Quokka-" + "7731\n/Mango\\d{4}/";
    var inputs = corpus.concat(F.cases.map(function (c) { return c.text; }), F.clean);
    fs.writeFileSync(path.join(T, "in.json"), JSON.stringify({ own: own, texts: inputs }));
    fs.writeFileSync(path.join(T, "runner.js"),
      "function run(argv) {\n" +
      "  function read(p) { return $.NSString.stringWithContentsOfFileEncodingError(p, 4, null).js; }\n" +
      "  var make = new Function(read(argv[0]) + '\\nreturn claudeHtmlRedactor;')();\n" +
      "  var x = JSON.parse(read(argv[1])), out = [];\n" +
      "  [true, false].forEach(function (c) { var r = make(x.own, true, c);\n" +
      "    out.push(x.texts.map(function (t) { return r.text(t); }), r.counts); });\n" +
      "  $(JSON.stringify(out)).writeToFileAtomicallyEncodingError(argv[2], true, 4, null);\n" +
      "  return 'done';\n}\n");
    var res = cp.spawnSync("osascript", ["-l", "JavaScript", path.join(T, "runner.js"),
      path.join(HERE, "redact.js"), path.join(T, "in.json"), path.join(T, "out.json")], { encoding: "utf8" });
    var got = fs.existsSync(path.join(T, "out.json")) ? fs.readFileSync(path.join(T, "out.json"), "utf8") : "";
    var want = [];
    [true, false].forEach(function (c) {
      var r = make(own, true, c);
      want.push(inputs.map(function (t) { return r.text(t); }), r.counts);
    });
    check("osascript redacts every text exactly as node does, both ways of looking",
          got === JSON.stringify(want), got ? "differs" : "no output: " + String(res.stderr).slice(0, 200));
  } finally { fs.rmSync(T, { recursive: true, force: true }); }
})();

console.log("  " + ENGINE + ": " + pass + " passed, " + fail + " failed");
process.exitCode = fail ? 1 : 0;

// ── the sandbox for redact.test.sh ──────────────────────────────────────
// Every fake secret, everywhere a conversation can hold one, and the list
// of what must never be found again in what claude-html writes.
function fixture(T) {
  var APP = T + "/root/app", PROJ = T + "/home/.claude/projects/" + APP.replace(/\//g, "-");
  var S1 = "5ec1e7a1-0000-4000-8000-000000000001";   // everything, with a sub-agent
  var S2 = "5ec1e7a1-0000-4000-8000-000000000002";   // no title: the first prompt is one
  var S3 = "5ec1e7a1-0000-4000-8000-000000000003";   // an old archive beside its transcript
  var Q = "5ec1e7a1-0000-4000-8000-000000000004";    // an old archive, its transcript gone
  var W = "5ec1e7a1-0000-4000-8000-000000000005";    // a claude.ai export
  var all = F.cases.map(function (c) { return c.text; }).join("\n");
  // The own list's strings, in the first session only, for later.
  var lit = "Zebra" + "-Quokka-" + "7731", word = "Mango" + "4821";
  // Kept only in the old archives, never in a transcript: if an old
  // archive is extended rather than made again, these survive.
  var stale = "gh" + "p_" + F.rnd(36), stale2 = "gh" + "o_" + F.rnd(36);
  // A token far longer than what is read past a cut, starting a little
  // before it: what the cut keeps of it must go too.
  var longJwt = "ey" + "J" + F.rnd(30) + ".ey" + "J" + F.rnd(3000) + "." + F.rnd(43);
  function before(at, text) { return new Array(at - 100).join("x") + " " + text + " tail"; }
  var probes = F.probes().concat([stale, stale2, stale.slice(4, 14), stale2.slice(4, 14), longJwt.slice(3, 13)]);
  fs.mkdirSync(PROJ + "/" + S1 + "/subagents", { recursive: true });
  fs.mkdirSync(APP + "/.claude/.claude-conversations", { recursive: true });
  fs.mkdirSync(T + "/root/pages", { recursive: true });
  fs.mkdirSync(T + "/bin", { recursive: true });
  var n = 0;
  function ts() { return new Date(Date.UTC(2026, 10, 1, 9) + (n++) * 60000).toISOString(); }
  function line(o) { return JSON.stringify(o) + "\n"; }
  function user(sid, content) {
    return line({ type: "user", cwd: APP, sessionId: sid, uuid: "u" + n, timestamp: ts(), message: { role: "user", content: content } });
  }
  function reply(sid, content, extra) {
    return line(Object.assign({ type: "assistant", cwd: APP, sessionId: sid, uuid: "a" + n, timestamp: ts(),
      message: { id: "msg_" + sid.slice(-1) + n, role: "assistant", model: "claude-opus-5", content: content,
                 usage: { input_tokens: 3, output_tokens: 4, cache_read_input_tokens: 5, cache_creation_input_tokens: 6 } } }, extra || {}));
  }
  // A secret where each cap cuts: the archive keeps 4000 characters of a
  // result, the page 6000; the archive 6000 of thinking and 4000 of an edit.
  function straddle(at, c) {
    var before = c.text.indexOf(c.secret);
    return new Array(at - 4 - before).join("x") + " " + c.text + " " + new Array(400).join("y");
  }
  function rule(name) { return F.cases.filter(function (c) { return c.rule === name; })[0]; }
  var tool = F.cases[2], tok2 = F.cases[0];
  var t1 = "";
  t1 += line({ type: "summary", aiTitle: "Fix the login, using " + F.cases[2].secret, sessionId: S1 });
  t1 += user(S1, "Here is everything:\n" + all + "\nand " + lit + " and " + word);
  t1 += reply(S1, [{ type: "thinking", thinking: straddle(6000, tok2) + "\n" + all },
                   { type: "text", text: "Replying with " + all },
                   { type: "tool_use", id: "toolu_1", name: "Bash", input: { command: all, description: "run " + tool.text } },
                   { type: "tool_use", id: "toolu_2", name: "mcp__thing", input: { config: { headers: { list: [all, { deep: all }] } } } },
                   { type: "tool_use", id: "toolu_3", name: "Edit", input: { file_path: "/x/a.env", old_string: "a", new_string: straddle(4000, tool) } },
                   { type: "tool_use", id: "toolu_4", name: "Task", input: { description: "check " + tool.text, prompt: all } }]);
  t1 += user(S1, [{ type: "tool_result", tool_use_id: "toolu_1", content: [{ type: "text", text: all }] }]);
  t1 += user(S1, [{ type: "tool_result", tool_use_id: "toolu_2", content: straddle(4000, tool) }]);
  t1 += user(S1, [{ type: "tool_result", tool_use_id: "toolu_3", content: straddle(6000, tok2) }]);
  t1 += user(S1, [{ type: "tool_result", tool_use_id: "toolu_4", content: before(6000, longJwt) }]);
  t1 += user(S1, [{ type: "tool_result", tool_use_id: "toolu_4", content: before(4000, longJwt) }]);
  t1 += user(S1, [{ type: "image", source: { type: "base64", media_type: "image/png", data: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ" } }]);
  fs.writeFileSync(PROJ + "/" + S1 + ".jsonl", t1);
  fs.writeFileSync(PROJ + "/" + S1 + "/subagents/agent-s1.jsonl",
    user(S1, "You are a sub-agent. " + all) + reply(S1, [{ type: "text", text: "Found " + all }]));
  fs.writeFileSync(PROJ + "/" + S1 + "/subagents/agent-s1.meta.json",
    JSON.stringify({ agentType: "general-purpose", description: "look at " + tool.text, toolUseId: "toolu_4" }));

  fs.writeFileSync(PROJ + "/" + S2 + ".jsonl",
    user(S2, F.cases[3].text + " is what I pasted") + reply(S2, [{ type: "text", text: "ok" }]));

  var t3 = user(S3, "an old one: " + F.cases[5].text) + reply(S3, [{ type: "text", text: "noted" }]);
  fs.writeFileSync(PROJ + "/" + S3 + ".jsonl", t3);
  function oldArchive(sid, bytes, text) {
    return JSON.stringify({ sourceBytes: bytes, format: 3, sessionId: sid, project: APP,
      startedAt: "2026-10-01T09:00:00.000Z", endedAt: "2026-10-01T09:01:00.000Z", messageCount: 2, promptCount: 1,
      messages: [{ role: "user", timestamp: "2026-10-01T09:00:00.000Z", text: text },
                 { role: "assistant", timestamp: "2026-10-01T09:01:00.000Z", text: "ok",
                   tools: [{ name: "Bash", input: { command: "echo " + stale2 } }] }],
      usage: {}, replies: [], agentFrom: 0, agentBytes: {} });
  }
  // Same size as its transcript, so the old skip check would have kept it.
  fs.writeFileSync(APP + "/.claude/.claude-conversations/" + S3 + ".json",
    oldArchive(S3, Buffer.byteLength(t3), "an old one: " + F.cases[5].text + " " + stale));
  fs.writeFileSync(APP + "/.claude/.claude-conversations/" + Q + ".json",
    oldArchive(Q, 999, "archived long ago: " + F.cases[6].text + " " + stale));

  fs.writeFileSync(T + "/conversations.json", JSON.stringify([{ uuid: W, name: "Chat about " + F.cases[0].secret,
    created_at: "2026-05-01T10:00:00Z", updated_at: "2026-05-01T11:00:00Z", chat_messages: [
      { sender: "human", created_at: "2026-05-01T10:00:00Z", content: [{ type: "text", text: all }] },
      { sender: "assistant", created_at: "2026-05-01T10:00:05Z", content: [
        { type: "thinking", thinking: all }, { type: "text", text: all },
        { type: "tool_use", id: "t1", name: "web_fetch", input: { url: rule("url-password").text } },
        { type: "tool_result", tool_use_id: "t1", content: [{ type: "text", text: straddle(6000, tok2) }] }] }] }]));

  fs.writeFileSync(T + "/probes.txt", probes.join("\n") + "\n");
  fs.writeFileSync(T + "/own.txt", [lit, word].join("\n") + "\n");
  // Lines 3-6 cannot be used: an invalid regex, one matching nothing at
  // all, one matching inside the mask, a sticky flag.
  fs.writeFileSync(T + "/list.redact", ["# mine", lit, "/[unclosed/", "/x*/", "/\\*/", "/abc/y", "/Mango\\d{4}/"].join("\n") + "\n");
  fs.writeFileSync(T + "/ids", [S1, S2, S3, Q, W].join("\n") + "\n");
}

// ── the sandbox for the hook-then-force check ───────────────────────────
// Secrets with no known prefix, one in each place a transcript holds text,
// as a session that ran the hook after a reply would leave them.
function hookFixture(T) {
  var APP = T + "/root/app", PROJ = T + "/home/.claude/projects/" + APP.replace(/\//g, "-");
  var ID = "5ec1e7a1-0000-4000-8000-0000000000a1";
  var V = []; for (var i = 0; i < 9; i++) V.push(F.rnd(16));
  fs.mkdirSync(PROJ, { recursive: true });
  fs.mkdirSync(APP, { recursive: true });
  fs.mkdirSync(T + "/root/pages", { recursive: true });
  var n = 0;
  function ts() { return new Date(Date.UTC(2026, 10, 2, 9) + (n++) * 60000).toISOString(); }
  function line(o) { return JSON.stringify(o) + "\n"; }
  function rec(type, content) {
    var m = { role: type, content: content };
    if (type === "assistant") { m.id = "msg_h" + n; m.model = "claude-opus-5"; }
    return line({ type: type, cwd: APP, sessionId: ID, uuid: "h" + n, timestamp: ts(), message: m });
  }
  // A result of 9000 characters with the secret across the page's cut.
  var out = new Array(5991).join("o") + " token=" + V[5] + " " + new Array(3000).join("p");
  var t = line({ type: "summary", aiTitle: "deploy with SECRET_KEY_BASE=" + V[6], sessionId: ID });
  t += rec("user", "the db password: " + V[0] + " for the staging box");
  t += rec("assistant", [{ type: "thinking", thinking: "they gave DB_PASS=" + V[1] + " earlier" },
    { type: "text", text: "noted, mot de passe : " + V[2] },
    { type: "tool_use", id: "toolu_h1", name: "Bash", input: { command: "curl -u admin:" + V[3] + " https://api.example.com",
      env: { nested: { api_key: V[4] } } } },
    { type: "tool_use", id: "toolu_h2", name: "Bash", input: { command: "mysql -u root -p" + V[7] + " app" } },
    { type: "tool_use", id: "toolu_h3", name: "mcp__thing", input: { headers: { Authorization: V[8] } } }]);
  t += rec("user", [{ type: "tool_result", tool_use_id: "toolu_h1", content: out }]);
  fs.writeFileSync(PROJ + "/" + ID + ".jsonl", t);
  fs.writeFileSync(T + "/probes.txt", V.concat(V.map(function (x) { return x.slice(0, 8); })).join("\n") + "\n");
  fs.writeFileSync(T + "/id", ID + "\n");
}
