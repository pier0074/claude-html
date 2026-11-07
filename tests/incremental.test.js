// A build that carries on from the last one must write exactly what a build
// from nothing writes. Not for a few chosen cases: for a transcript cut at
// many points — between lines, inside a line, inside a character, inside a
// reply written as several records, between a tool call and its result —
// built cut, then built whole, and compared byte for byte, every file, with
// a build of the whole from scratch. Then the ways a cache can stop fitting:
// deleted, corrupted, from another version, from a transcript since
// replaced, from a save that stopped halfway.
//
//   node tests/incremental.test.js [--engine node|osascript] [--quick | --all]
//
// node runs in this process, so it can afford every split; osascript is a
// process per build, so it takes a spread of them, the hard ones included.
"use strict";
var fs = require("fs"), path = require("path"), os = require("os");
var cp = require("child_process");

var HERE = path.resolve(__dirname, "..");
var args = process.argv.slice(2);
var ENGINE = args.indexOf("--engine") > -1 ? args[args.indexOf("--engine") + 1] : "node";
var QUICK = args.indexOf("--quick") > -1;
var pass = 0, fail = 0;
function check(name, ok, detail) {
  if (ok) { pass++; return; }
  fail++;
  console.log("  FAIL  " + name + (detail ? "\n        " + detail : ""));
}

var T = fs.mkdtempSync(path.join(fs.realpathSync(process.env.TMPDIR || os.tmpdir()), "chincr."));
process.on("exit", function () { try { fs.rmSync(T, { recursive: true, force: true }); } catch (e) {} });

// ── the engines ──────────────────────────────────────────────────────
// The converter is loaded once and run in this process for node; osascript
// gets a process per build, as a save gives it.
// fsOver, when given, stands in for some of fs: a way to change the
// transcript at a chosen moment in the middle of a run.
function loadRun(file, fsOver) {
  var src = fs.readFileSync(file, "utf8");
  var req = fsOver ? function (m) { return m === "fs" ? Object.assign({}, fs, fsOver) : require(m); } : require;
  // eslint-disable-next-line no-new-func
  return new Function("require", "Buffer", "process", src + "\nreturn run;")(req, Buffer, process);
}
var convertRun = loadRun(path.join(HERE, "convert.js"));
function convert(o, engine) {
  var opt = JSON.stringify(o);
  if ((engine || ENGINE) === "osascript") {
    var r = cp.spawnSync("osascript", ["-l", "JavaScript", path.join(HERE, "convert.js"), opt],
                         { encoding: "utf8", maxBuffer: 1 << 28 });
    return r.stdout;
  }
  return convertRun([opt]);
}

// ── the fixture ─────────────────────────────────────────────────────
var ROOT = path.join(T, "root"), APP = path.join(ROOT, "app"), HOME = path.join(T, "home");
var PROJ = path.join(HOME, ".claude", "projects", APP.replace(/\//g, "-"));
var P = "11111111-2222-3333-4444-555555555555";       // the session that grows
var S2 = "11111111-2222-3333-4444-666666666666";      // a fork of it, holding copies
var Q = "22222222-3333-4444-5555-666666666666";       // archive only
var W = "cccccccc-0000-0000-0000-000000000003";       // claude.ai export
var X = path.join(T, "conversations.json");
fs.mkdirSync(path.join(PROJ, P, "subagents"), { recursive: true });
fs.mkdirSync(path.join(APP, ".claude", ".claude-conversations"), { recursive: true });
fs.mkdirSync(path.join(HOME, ".claude"), { recursive: true });
fs.writeFileSync(path.join(HOME, ".claude", "claude-html.archives"), APP + "\n");

function at(min) {          // a timestamp, min minutes into the session
  return new Date(Date.UTC(2026, 9, 6, 9, 0, 0) + min * 60000).toISOString();
}
function line(o) { return JSON.stringify(o) + "\n"; }
function user(min, content, extra) {
  return line(Object.assign({ type: "user", cwd: APP, sessionId: P, uuid: "u-" + min,
                              timestamp: at(min), message: { role: "user", content: content } }, extra || {}));
}
function reply(min, id, content, usage, extra) {
  var m = { role: "assistant", content: content, model: "claude-opus-5" };
  if (id) m.id = id;
  if (usage) m.usage = usage;
  return line(Object.assign({ type: "assistant", cwd: APP, sessionId: P, uuid: "a-" + min + "-" + id,
                              timestamp: at(min), message: m }, extra || {}));
}
function tokens(i, o) {
  return { input_tokens: i, output_tokens: o, cache_read_input_tokens: 100 + o, cache_creation_input_tokens: 7 };
}
function costState(start, usd, extra) {
  var mu = {};
  Object.keys(usd).forEach(function (m) { mu[m] = { costUSD: usd[m] }; });
  return line(Object.assign({ type: "cost-state", sessionId: P, startTime: start, modelUsage: mu }, extra || {}));
}

var parts = [];
parts.push(line({ type: "permission-mode", permissionMode: "default", sessionId: P }));
parts.push(user(0, "<command-name>/clear</command-name><command-args></command-args>"));
parts.push(user(1, "<system-reminder>injected</system-reminder>", { isMeta: true }));
parts.push(user(1, "Audit this — déjà vu 🙂 with <script>alert(1)</script> and a line separator"));
parts.push(line({ type: "summary", aiTitle: "A fixture with every hard case", sessionId: P }));
// One reply, three records under one id: the last one's usage is the one.
parts.push(reply(2, "msg_MULTI", [{ type: "thinking", thinking: "thinking it over" }], tokens(5, 10)));
parts.push(reply(2, "msg_MULTI", [{ type: "text", text: "Let me look." }], tokens(5, 20)));
parts.push(reply(2, "msg_MULTI", [{ type: "tool_use", id: "toolu_LATE", name: "Bash",
                                     input: { command: "ls -la", description: "list" } }], tokens(5, 30)));
// A reply in between, before the late tool's result arrives.
parts.push(reply(3, "msg_BETWEEN", [{ type: "tool_use", id: "toolu_TASK", name: "Task",
                                       input: { description: "check the backend", prompt: "go" } }], tokens(2, 3)));
parts.push(costState(1791277200000, { "claude-opus-5": 0.30000000000000004, "claude-haiku-4-5": 0.0009545 }));
parts.push(user(4, [{ type: "tool_result", tool_use_id: "toolu_LATE",
                      content: [{ type: "text", text: "a.txt\nb.txt" }, { type: "image" }] }]));
parts.push("null\n");
parts.push("\n");
parts.push("{this is not json}\n");
// A result long enough to be capped, with an emoji right where it is cut.
var long = new Array(5999).join("x") + "🙂🙂" + new Array(400).join("é");
parts.push(user(5, [{ type: "tool_result", tool_use_id: "toolu_TASK", content: long }]));
parts.push(user(5, [{ type: "image", source: {} }, { type: "text", text: "and this picture" }]));
// Usage with no message id: one with a uuid, and one with neither, which the
// accumulator numbers itself.
parts.push(reply(6, null, [{ type: "text", text: "no id here" }], tokens(1, 1)));
parts.push(JSON.stringify({ type: "assistant", cwd: APP, sessionId: P, timestamp: at(6),
  message: { role: "assistant", model: "claude-sonnet-4", content: [{ type: "text", text: "nor here" }],
             usage: tokens(1, 2) } }) + "\n");
// A copy carried over from another session, which this one's cost ignores.
parts.push(reply(7, "msg_CARRIED", [{ type: "text", text: "carried" }], tokens(3, 4), { sessionId: "someone-else" }));
parts.push(line({ type: "assistant", cwd: APP, isSidechain: true, timestamp: at(7),
                  message: { role: "assistant", content: [{ type: "text", text: "a side remark" }] } }));
parts.push(costState(1791277200000, { "claude-opus-5": 1.1000000000000003, "claude-haiku-4-5": 0.0009545 }));
// Enough exchanges to take the transcript past the 400 lines its title is
// looked for in, each with a tool whose result comes a few lines later.
for (var i = 0; i < 140; i++) {
  var min = 10 + i;
  parts.push(user(min, "question " + i + (i % 7 === 0 ? " 中文 ✓" : "")));
  parts.push(reply(min, "msg_R" + i, [{ type: "text", text: "answer " + i },
    { type: "tool_use", id: "toolu_" + i, name: "Read", input: { file_path: "/x/" + i } }], tokens(i, i + 1)));
  if (i > 0) {
    parts.push(user(min, [{ type: "tool_result", tool_use_id: "toolu_" + (i - 1), content: "out " + (i - 1) }]));
  }
  if (i === 60) parts.push(costState(1791290000000, { "claude-opus-5": 0.2 }));             // a restart
  if (i === 61) parts.push(costState(1791290000000, { "claude-opus-5": 0.15 }));            // went down
  if (i === 90) parts.push(costState(1791290000000, { "claude-opus-5": 0.9 }, { hasUnknownModelCost: true }));
  if (i === 91) parts.push(costState(1791290000000, { "claude-opus-5": 5 }, { sessionId: "another" }));
  if (i === 100) parts.push(line({ type: "summary", aiTitle: "a later title, past where titles count" }));
}
// The last reply is written in two records, and the second is still being
// written: a line cut off, as a save can catch it.
parts.push(reply(200, "msg_LAST", [{ type: "text", text: "nearly" }], tokens(9, 9)));
var whole = parts.join("") + JSON.stringify({ type: "assistant", sessionId: P, timestamp: at(200),
  message: { id: "msg_LAST", role: "assistant", content: [{ type: "text", text: "nearly done" }],
             usage: tokens(9, 99) } }).slice(0, 80);
var WHOLE = Buffer.from(whole, "utf8");
var MAIN = path.join(PROJ, P + ".jsonl");

// Sub-agents: one that shares a reply with its parent, one with nothing to
// show, one counted without ids.
var SUB = path.join(PROJ, P, "subagents");
function agentLine(min, o) {
  return line(Object.assign({ cwd: APP, isSidechain: true, sessionId: P, timestamp: at(min) }, o));
}
var AGENTS = {
  "agent-a1": agentLine(3, { type: "user", message: { role: "user", content: "You are checking the backend" } }) +
    agentLine(3, { type: "assistant", message: { id: "msg_R5", role: "assistant", model: "claude-opus-5",
      content: [{ type: "text", text: "FOUND SOMETHING" }], usage: tokens(50, 50) } }) +
    agentLine(4, { type: "assistant", message: { id: "msg_A1", role: "assistant", model: "claude-haiku-4-5",
      content: [{ type: "text", text: "done" }], usage: tokens(1, 1) } }),
  "agent-a2": line({ type: "permission-mode", sessionId: P }),
  "agent-a3": agentLine(5, { type: "user", message: { role: "user", content: "count me" } }) +
    agentLine(5, { type: "assistant", message: { role: "assistant", model: "claude-haiku-4-5",
      content: [{ type: "text", text: "counted" }], usage: tokens(2, 2) } })
};
Object.keys(AGENTS).forEach(function (a) {
  fs.writeFileSync(path.join(SUB, a + ".jsonl"), AGENTS[a]);
  fs.writeFileSync(path.join(SUB, a + ".meta.json"),
    JSON.stringify({ agentType: "general-purpose", description: "agent " + a, toolUseId: "toolu_TASK" }));
  fs.utimesSync(path.join(SUB, a + ".jsonl"), 1790000000, 1790000000);
  fs.utimesSync(path.join(SUB, a + ".meta.json"), 1790000000, 1790000000);
});

// A fork: a copy of the parent's early replies under its own session id, so
// which replies the two share depends on how far the parent has got.
var fork = parts.slice(0, 40).join("").split(P).join(S2) +
  line({ type: "user", cwd: APP, sessionId: S2, timestamp: at(300), message: { role: "user", content: "the fork's own" } });
fs.writeFileSync(path.join(PROJ, S2 + ".jsonl"), fork);
fs.utimesSync(path.join(PROJ, S2 + ".jsonl"), 1790000500, 1790000500);

fs.writeFileSync(path.join(APP, ".claude", ".claude-conversations", Q + ".json"),
  JSON.stringify({ sessionId: Q, project: APP, messages: [{ role: "user", text: "an archived question" },
    { role: "assistant", text: "an archived answer" }] }));
fs.writeFileSync(X, JSON.stringify([{ uuid: W, name: "A web chat", created_at: "2026-05-01T10:00:00Z",
  updated_at: "2026-05-01T11:00:00Z", chat_messages: [
    { sender: "human", created_at: "2026-05-01T10:00:00Z", content: [{ type: "text", text: "a web question" }] },
    { sender: "assistant", created_at: "2026-05-01T10:00:05Z", content: [{ type: "text", text: "an answer" }] }] }]));

// ── building and comparing ───────────────────────────────────────────
var n = 0;
function out() { return path.join(T, "out-" + (n++)); }
function build(o, extra, engine) {
  var r = convert(Object.assign({ root: ROOT, out: o, here: HERE, home: HOME, exportPath: X,
                                  projects: path.join(HOME, ".claude", "projects") }, extra || {}), engine);
  return r;
}
// The main transcript as it stands for a build: bytes, and a time of its own.
function setMain(buf, when) {
  fs.writeFileSync(MAIN, buf);
  fs.utimesSync(MAIN, when, when);
}
function files(dir) {
  var outp = {};
  (function walk(rel) {
    fs.readdirSync(path.join(dir, rel)).forEach(function (f) {
      var r = rel ? rel + "/" + f : f, full = path.join(dir, r);
      if (fs.statSync(full).isDirectory()) return walk(r);
      var b = fs.readFileSync(full);
      // When the index was built is the one thing two builds rightly differ in.
      if (r === "index.html") b = Buffer.from(b.toString("utf8").replace(/"built":\d+,/, '"built":0,'));
      outp[r] = b;
    });
  })("");
  return outp;
}
// a is the build under test, b the one from scratch. Every page, search
// file, launcher, the manifest, the index and the dashboard must be the same
// bytes. The cache is disposable: a session nobody rebuilt may have none
// after it was deleted, but any cache there is must be what scratch made.
function same(a, b) {
  var fa = files(a), fb = files(b), diffs = [];
  Object.keys(fa).concat(Object.keys(fb)).forEach(function (k) {
    if (diffs.indexOf(k) > -1) return;
    if (!fa[k] && k.indexOf(".cache/") === 0) return;
    if (!fa[k] || !fb[k] || !fa[k].equals(fb[k])) diffs.push(k);
  });
  return diffs;
}
function expectSame(name, a, b) {
  var d = same(a, b);
  check(name, d.length === 0, "differs: " + d.slice(0, 6).join(", ") + (d.length > 6 ? " …" : ""));
}

var T_CUT = 1790001000, T_WHOLE = 1790002000;
setMain(WHOLE, T_WHOLE);
var SCRATCH = out();
var r0 = build(SCRATCH);
check("the fixture builds", /"sessions":4/.test(r0) && /"errors":\[\]/.test(r0), r0);
check("  with its sub-agent pages", fs.existsSync(path.join(SCRATCH, "sessions", P, "agent-a1.html")) &&
      fs.existsSync(path.join(SCRATCH, "sessions", P, "agent-a3.html")));
check("  and a cache for each transcript", fs.existsSync(path.join(SCRATCH, ".cache", P + ".build")) &&
      fs.existsSync(path.join(SCRATCH, ".cache", S2 + ".build.md5")));
var manifest = JSON.parse(fs.readFileSync(path.join(SCRATCH, ".manifest.json"), "utf8"));
check("  the fork and its source both keep the replies they share",
      !!manifest[P].shared && !!manifest[S2].shared &&
      Object.keys(manifest[P].shared).join() === Object.keys(manifest[S2].shared).join());

// Every split point worth having: each line's end, before and after its
// line break, and points inside lines — inside a multi-byte character too.
var splits = [];
for (var b = 0; b < WHOLE.length; b++) {
  if (WHOLE[b] === 10) { splits.push(b); splits.push(b + 1); }
}
var lineEnds = splits.slice();
var inner = [];
for (var c = 37; c < WHOLE.length; c += 997) inner.push(c);
var uni = whole.indexOf("déjà");
inner.push(Buffer.byteLength(whole.slice(0, uni + 2), "utf8") + 1);       // inside the é
var multi = Buffer.byteLength(whole.slice(0, whole.indexOf("msg_MULTI") + 4), "utf8");
inner.push(multi);                                                         // inside a record of a split reply
splits = splits.concat(inner).filter(function (x) { return x > 0 && x < WHOLE.length; });
splits = splits.filter(function (x, i) { return splits.indexOf(x) === i; }).sort(function (a, b) { return a - b; });

// The ones that matter most, for the engine that cannot afford them all:
// before and between the records of the split reply, before the late tool
// result, either side of the cost restart, past line 400, and inside lines.
function lineEndAfter(sub) {
  var k = Buffer.byteLength(whole.slice(0, whole.indexOf(sub)), "utf8");
  for (var j = 0; j < lineEnds.length; j++) if (lineEnds[j] > k) return lineEnds[j];
  return k;
}
var hard = [lineEndAfter('"msg_MULTI"'), lineEndAfter('"text":"Let me look."'),
            lineEndAfter('"tool_use_id":"toolu_LATE"') - 1, lineEndAfter('"costUSD":0.2}'),
            lineEndAfter('"costUSD":0.15}'), lineEndAfter("question 139"), lineEndAfter("the fork") ]
  .concat(inner.slice(-2), [inner[3], lineEnds[lineEnds.length - 1], WHOLE.length - 30]);
// --all takes every one, which is a minute's work under node.
var ALL = args.indexOf("--all") > -1;
var chosen = QUICK ? hard.concat(splits.filter(function (x, i) { return i % 97 === 0; }))
  : ENGINE === "osascript" && !ALL ? hard.concat(splits.filter(function (x, i) { return i % 40 === 0; }))
  : ALL ? splits : hard.concat(splits.filter(function (x, i) { return i % 4 === 0; }));
chosen = chosen.filter(function (x, i) { return x > 0 && x < WHOLE.length && chosen.indexOf(x) === i; });

var bad = [];
chosen.forEach(function (k) {
  var o = out();
  setMain(WHOLE.subarray(0, k), T_CUT);
  build(o);
  setMain(WHOLE, T_WHOLE);
  build(o);
  var d = same(o, SCRATCH);
  if (d.length) bad.push(k + " (" + d.slice(0, 3).join(", ") + ")");
  fs.rmSync(o, { recursive: true, force: true });
});
check("cut at any of " + chosen.length + " points, then whole: the same bytes as built whole",
      bad.length === 0, "split points that differ: " + bad.slice(0, 8).join("; "));

// ── when the cache stops fitting ──────────────────────────────────────
var MID = lineEnds[Math.floor(lineEnds.length / 2)];
function cutThenWhole(between) {
  var o = out();
  setMain(WHOLE.subarray(0, MID), T_CUT);
  build(o);
  if (between) between(o);
  setMain(WHOLE, T_WHOLE);
  build(o);
  return o;
}
var cacheOf = function (o) { return path.join(o, ".cache", P + ".build"); };
function md5(p) { return require("crypto").createHash("md5").update(fs.readFileSync(p)).digest("hex"); }
function reseal(o) { fs.writeFileSync(cacheOf(o) + ".md5", md5(cacheOf(o)) + "\n"); }

expectSame("with the cache deleted between builds", cutThenWhole(function (o) {
  fs.rmSync(path.join(o, ".cache"), { recursive: true, force: true });
}), SCRATCH);
expectSame("with a byte of the cache changed", cutThenWhole(function (o) {
  var buf = fs.readFileSync(cacheOf(o)); buf[buf.length - 50] ^= 1; fs.writeFileSync(cacheOf(o), buf);
}), SCRATCH);
expectSame("with the cache cut short", cutThenWhole(function (o) {
  var buf = fs.readFileSync(cacheOf(o)); fs.writeFileSync(cacheOf(o), buf.subarray(0, buf.length >> 1));
}), SCRATCH);
expectSame("with its md5 missing", cutThenWhole(function (o) { fs.rmSync(cacheOf(o) + ".md5"); }), SCRATCH);
expectSame("with nonsense in it and a matching md5", cutThenWhole(function (o) {
  fs.writeFileSync(cacheOf(o), "{not json\n"); reseal(o);
}), SCRATCH);
// A cache from another version, here made to hold the wrong text: if it were
// used, the page would say so.
expectSame("with a cache from another version, however sound it looks", cutThenWhole(function (o) {
  var t = fs.readFileSync(cacheOf(o), "utf8");
  t = t.replace(/^\{"key":"[^"]*"/, '{"key":"0:3:old"').split("answer 3").join("ANSWER 3");
  fs.writeFileSync(cacheOf(o), t); reseal(o);
}), SCRATCH);
// Made to hold the wrong text as well, so that using it would show.
expectSame("with a cache from another transcript at that path", cutThenWhole(function (o) {
  var t = fs.readFileSync(cacheOf(o), "utf8");
  fs.writeFileSync(cacheOf(o), t.replace('"path":"', '"path":"/elsewhere').split("answer 3").join("ANSWER 3"));
  reseal(o);
}), SCRATCH);
expectSame("with stray files left in the cache", cutThenWhole(function (o) {
  fs.writeFileSync(path.join(o, ".cache", P + ".build.tmp123"), "half");
  fs.writeFileSync(path.join(o, ".cache", "99999999-0000-0000-0000-000000000000.build"), "gone");
}), SCRATCH);

// The transcript replaced: by a shorter one, by another conversation at
// least as long, and edited just before where the cache stopped. The
// fingerprint is three samples, cheap by design: an edit confined to bytes
// between them is not one it can see, and transcripts are only appended to.
(function () {
  var o = out();
  setMain(WHOLE, T_WHOLE); build(o);
  setMain(WHOLE.subarray(0, MID), T_CUT); build(o);
  var s2 = out(); build(s2);
  expectSame("with the transcript replaced by a shorter one", o, s2);
  function replaced(name, buf) {
    var o2 = out();
    setMain(WHOLE.subarray(0, MID), T_CUT); build(o2);
    setMain(buf, T_WHOLE); build(o2);
    var s3 = out(); build(s3);
    expectSame(name, o2, s3);
  }
  replaced("with the transcript replaced by another conversation as long",
           Buffer.from(whole.split("answer").join("ANSWER").split("question").join("QUESTION"), "utf8"));
  // A byte the cut build has already read: in the last whole line before
  // the cut, which is inside the last sample.
  var edited = Buffer.from(WHOLE), AT = WHOLE.lastIndexOf("question", WHOLE.lastIndexOf(10, MID - 1));
  edited[AT] = edited[AT] === 65 ? 66 : 65;
  replaced("with the transcript edited just before where the cache stopped", edited);
  setMain(WHOLE, T_WHOLE);
})();

// The transcript cut short, or replaced by a longer one, while a build was
// writing its pages: what it read is no longer the file, so it must not be
// kept as if it were. The next build must write what one from scratch does.
(function () {
  function during(name, to) {
    var o = out(), page = path.join(o, "sessions", P + ".html"), fired = false;
    var hooked = loadRun(path.join(HERE, "convert.js"), { renameSync: function (a, b) {
      fs.renameSync(a, b);
      if (!fired && b === page) { fired = true; setMain(to, T_CUT); }
    } });
    setMain(WHOLE, T_WHOLE);
    hooked([JSON.stringify({ root: ROOT, out: o, here: HERE, home: HOME, exportPath: X,
                             projects: path.join(HOME, ".claude", "projects") })]);
    build(o);
    var s2 = out(); build(s2);
    check(name + " (it happened)", fired);
    expectSame(name, o, s2);
  }
  during("with the transcript cut short while the pages were written", WHOLE.subarray(0, MID));
  during("with it replaced by a longer, different one then",
         Buffer.from(whole.split("answer").join("ANSWER").split("question").join("QUESTION") + "\n", "utf8"));
  setMain(WHOLE, T_WHOLE);
})();

// Sub-agents and parent, each growing while the other does not.
(function () {
  var a1 = path.join(SUB, "agent-a1.jsonl"), o = out();
  setMain(WHOLE, T_WHOLE); build(o);
  fs.appendFileSync(a1, agentLine(9, { type: "assistant", message: { id: "msg_A1b", role: "assistant",
    model: "claude-opus-5", content: [{ type: "text", text: "more from a1" }], usage: tokens(4, 4) } }));
  fs.utimesSync(a1, 1790000100, 1790000100);
  build(o);
  var s2 = out(); build(s2);
  expectSame("a sub-agent grows while its parent does not", o, s2);
  setMain(WHOLE.subarray(0, MID), T_CUT); build(o);
  setMain(WHOLE, T_WHOLE); build(o);
  expectSame("  then the parent grows while the sub-agent does not", o, s2);
  fs.writeFileSync(path.join(SUB, "agent-a1.meta.json"), JSON.stringify({ agentType: "Explore", description: "renamed" }));
  fs.utimesSync(path.join(SUB, "agent-a1.meta.json"), 1790000200, 1790000200);
  fs.writeFileSync(path.join(SUB, "agent-a4.jsonl"), AGENTS["agent-a3"].replace("count me", "a new one"));
  fs.utimesSync(path.join(SUB, "agent-a4.jsonl"), 1790000300, 1790000300);
  build(o);
  var s3 = out(); build(s3);
  expectSame("  a new sub-agent, and one whose description changed", o, s3);
  fs.rmSync(path.join(SUB, "agent-a4.jsonl"));
  build(o);
  var s4 = out(); build(s4);
  expectSame("  and one whose transcript went", o, s4);
  fs.writeFileSync(a1, AGENTS["agent-a1"]); fs.utimesSync(a1, 1790000000, 1790000000);
  fs.writeFileSync(path.join(SUB, "agent-a1.meta.json"),
    JSON.stringify({ agentType: "general-purpose", description: "agent agent-a1", toolUseId: "toolu_TASK" }));
  fs.utimesSync(path.join(SUB, "agent-a1.meta.json"), 1790000000, 1790000000);
})();

// A save that stopped halfway: a cache newer than the pages and manifest,
// and one older than them.
(function () {
  var early = out(), late = out();
  setMain(WHOLE.subarray(0, MID), T_CUT); build(early);
  fs.cpSync(early, late, { recursive: true });
  setMain(WHOLE, T_WHOLE); build(late);
  var mixed = out();
  fs.cpSync(early, mixed, { recursive: true });
  fs.rmSync(path.join(mixed, ".cache"), { recursive: true, force: true });
  fs.cpSync(path.join(late, ".cache"), path.join(mixed, ".cache"), { recursive: true });
  build(mixed);
  expectSame("a cache ahead of its pages", mixed, SCRATCH);
  var mixed2 = out();
  fs.cpSync(late, mixed2, { recursive: true });
  fs.rmSync(path.join(mixed2, ".cache"), { recursive: true, force: true });
  fs.cpSync(path.join(early, ".cache"), path.join(mixed2, ".cache"), { recursive: true });
  fs.rmSync(path.join(mixed2, ".manifest.json"));
  build(mixed2);
  expectSame("a cache behind its pages, with the manifest lost", mixed2, SCRATCH);
})();

// A forced rebuild, and one without the cache, write what a build from
// nothing writes; the second leaves the cache as it was.
(function () {
  var o = out();
  setMain(WHOLE.subarray(0, MID), T_CUT); build(o);
  setMain(WHOLE, T_WHOLE); build(o, { force: true });
  expectSame("a forced rebuild over a cache", o, SCRATCH);
  var o2 = out();
  setMain(WHOLE.subarray(0, MID), T_CUT); build(o2);
  var before = fs.readFileSync(cacheOf(o2));
  // What a deleted conversation left behind: it holds that conversation's
  // text, so it goes even when the build does without the cache.
  var GONE = "99999999-0000-0000-0000-000000000001";
  [".build", ".build.md5", ".archive", ".archive.md5"].forEach(function (x) {
    fs.writeFileSync(path.join(o2, ".cache", GONE + x), "a deleted conversation");
  });
  setMain(WHOLE, T_WHOLE); build(o2, { cache: false });
  var d = same(o2, SCRATCH).filter(function (f) { return f.indexOf(".cache/") !== 0; });
  check("a build without the cache writes the same pages", d.length === 0, d.join(", "));
  check("  and leaves the cache alone", before.equals(fs.readFileSync(cacheOf(o2))));
  check("  but not that of a conversation that is gone", fs.readdirSync(path.join(o2, ".cache"))
    .filter(function (f) { return f.indexOf(GONE) === 0; }).length === 0);
})();

// The engine can change between saves — a hook may find node where another
// did not — so each must write what the other writes, and carry on from a
// cache the other kept.
if (ENGINE === "osascript") (function () {
  var o = out();
  setMain(WHOLE, T_WHOLE); build(o, {}, "node");
  expectSame("node writes what osascript writes, the cache included", o, SCRATCH);
  [["osascript", "node"], ["node", "osascript"]].forEach(function (pair) {
    var o2 = out();
    setMain(WHOLE.subarray(0, MID), T_CUT); build(o2, {}, pair[0]);
    setMain(WHOLE, T_WHOLE); build(o2, {}, pair[1]);
    expectSame("cut under " + pair[0] + ", whole under " + pair[1], o2, SCRATCH);
  });
})();

// Nothing changed: nothing rewritten, the cache included.
(function () {
  var o = out();
  setMain(WHOLE, T_WHOLE); build(o);
  var t1 = fs.statSync(cacheOf(o)).mtimeMs, r = build(o);
  check("a build where nothing changed builds nothing", /"built":0,/.test(r), r);
  check("  and leaves the cache as it was", fs.statSync(cacheOf(o)).mtimeMs === t1);
})();

// ── the archiver ────────────────────────────────────────────────────
// The same, for the archive a save writes into the project: archived cut,
// then archived whole on top of it, as a save does it — the same archive
// path, the output moved over the last one — against archived whole from
// nothing. The archive and the state it keeps must both be the same bytes.
var sh = fs.readFileSync(path.join(HERE, "save-conversation.sh"), "utf8");
var ARCHIVER = path.join(T, "archive.js");
fs.writeFileSync(ARCHIVER, sh.slice(sh.indexOf("<<'ARCHIVEREOF'\n") + 16, sh.indexOf("\nARCHIVEREOF\n") + 1));
var archiveRun = loadRun(ARCHIVER);
var AR = path.join(T, "arch"), ARCH = path.join(AR, P + ".json"), STATE = path.join(AR, ".cache", P + ".archive");
fs.mkdirSync(AR, { recursive: true });
function archive(engine, runner) {
  var a = [MAIN, P, APP, String(fs.statSync(MAIN).size), ARCH, STATE];
  var r = runner ? runner(a)
    : (engine || ENGINE) === "osascript"
    ? cp.spawnSync("osascript", ["-l", "JavaScript", ARCHIVER].concat(a), { encoding: "utf8", maxBuffer: 1 << 28 }).stdout
    : archiveRun(a);
  r = String(r || "").replace(/\n$/, "");
  // As the save does: only a complete archive replaces the last one.
  if (r.slice(-1) === "}") fs.writeFileSync(ARCH, r);
  return r;
}
function fresh() { fs.rmSync(AR, { recursive: true, force: true }); fs.mkdirSync(AR, { recursive: true }); }
function snapshot() {
  return { a: fs.existsSync(ARCH) ? fs.readFileSync(ARCH) : null,
           s: fs.existsSync(STATE) ? fs.readFileSync(STATE) : null };
}
setMain(WHOLE, T_WHOLE); fresh(); archive();
var ASCRATCH = snapshot();
check("the archiver archives the fixture", !!ASCRATCH.a && !!ASCRATCH.s &&
      JSON.parse(ASCRATCH.a).messageCount > 400 && JSON.parse(ASCRATCH.a).costPart === true);
function sameArchive(name, extra) {
  var now = snapshot();
  var ok = now.a && now.a.equals(ASCRATCH.a) && now.s && now.s.equals(ASCRATCH.s);
  check(name, ok, (extra || "") + (now.a && now.a.equals(ASCRATCH.a) ? " (the state differs)" : " (the archive differs)"));
  return ok;
}
var aChosen = ENGINE === "osascript" && !ALL ? chosen.filter(function (x, i) { return i % 2 === 0; }) : chosen;
var abad = [];
aChosen.forEach(function (k) {
  fresh();
  setMain(WHOLE.subarray(0, k), T_CUT); archive();
  setMain(WHOLE, T_WHOLE); archive();
  var now = snapshot();
  if (!now.a || !now.a.equals(ASCRATCH.a) || !now.s || !now.s.equals(ASCRATCH.s)) abad.push(k);
});
check("archived cut at any of " + aChosen.length + " points, then whole: the same archive and state",
      abad.length === 0, "split points that differ: " + abad.slice(0, 8).join(", "));

function archThen(name, between, engines) {
  fresh();
  setMain(WHOLE.subarray(0, MID), T_CUT); archive(engines && engines[0]);
  if (between) between();
  setMain(WHOLE, T_WHOLE); archive(engines && engines[1]);
  sameArchive(name);
}
function resealState() {
  fs.writeFileSync(STATE + ".md5", md5(STATE) + "\n");
}
archThen("with the archiver's state deleted", function () { fs.rmSync(STATE); });
archThen("with a byte of it changed", function () {
  var b2 = fs.readFileSync(STATE); b2[b2.length >> 1] ^= 1; fs.writeFileSync(STATE, b2);
});
archThen("with nonsense in it and a matching md5", function () { fs.writeFileSync(STATE, "[1,2"); resealState(); });
archThen("with a state from another version, however sound it looks", function () {
  var t = fs.readFileSync(STATE, "utf8").replace(/^\{"key":"[^"]*"/, '{"key":"0:old"').replace(/"msgs":\d+/, '"msgs":3');
  fs.writeFileSync(STATE, t); resealState();
});
archThen("with the archive it would extend gone", function () { fs.rmSync(ARCH); });
// Its messages made to differ as well, as a real older one's do, so that
// extending it anyway would show.
archThen("with the archive it would extend from an older format", function () {
  var o = JSON.parse(fs.readFileSync(ARCH, "utf8")); o.format = 2;
  o.messages = o.messages.map(function (m) { var c = Object.assign({}, m); delete c.usage; delete c.thinking; c.stale = 1; return c; });
  fs.writeFileSync(ARCH, JSON.stringify(o));
});
archThen("with the archive it would extend shorter than it said", function () {
  var o = JSON.parse(fs.readFileSync(ARCH, "utf8")); o.messages = o.messages.slice(0, 5); fs.writeFileSync(ARCH, JSON.stringify(o));
});
(function () {
  fresh();
  setMain(WHOLE, T_WHOLE); archive();
  setMain(WHOLE.subarray(0, MID), T_CUT); archive();
  var shorter = snapshot();
  fresh(); archive();
  var s2 = snapshot();
  check("with the transcript replaced by a shorter one", shorter.a.equals(s2.a) && shorter.s.equals(s2.s));
  setMain(WHOLE, T_WHOLE);
})();
// The transcript cut short, or replaced by a longer one, after the archiver
// read it and before it kept its state: the next save must start over.
(function () {
  function during(name, to) {
    var fired = false;
    var hooked = loadRun(ARCHIVER, { readdirSync: function (d) {
      if (!fired && d === SUB) { fired = true; setMain(to, T_CUT); }
      return fs.readdirSync(d);
    } });
    fresh();
    setMain(WHOLE, T_WHOLE); archive(null, hooked);
    archive();
    var got = snapshot();
    fresh(); archive();
    var s2 = snapshot();
    check(name, fired && got.a.equals(s2.a) && got.s.equals(s2.s), fired ? "" : "(it never happened)");
  }
  during("with the transcript cut short during the save", WHOLE.subarray(0, MID));
  during("with it replaced by a longer, different one then",
         Buffer.from(whole.split("answer").join("ANSWER").split("question").join("QUESTION") + "\n", "utf8"));
  setMain(WHOLE, T_WHOLE);
})();
(function () {
  var a1 = path.join(SUB, "agent-a1.jsonl");
  fresh();
  setMain(WHOLE.subarray(0, MID), T_CUT); archive();
  fs.appendFileSync(a1, agentLine(9, { type: "assistant", message: { id: "msg_A1b", role: "assistant",
    model: "claude-opus-5", content: [{ type: "text", text: "more" }], usage: tokens(4, 4) } }));
  setMain(WHOLE, T_WHOLE); archive();
  var grown = snapshot();
  fresh(); archive();
  var s3 = snapshot();
  check("with a sub-agent grown as well", grown.a.equals(s3.a) && grown.s.equals(s3.s));
  fs.writeFileSync(a1, AGENTS["agent-a1"]); fs.utimesSync(a1, 1790000000, 1790000000);
})();
if (ENGINE === "osascript") {
  archThen("cut under osascript, whole under node", null, ["osascript", "node"]);
  archThen("cut under node, whole under osascript", null, ["node", "osascript"]);
}

console.log("  " + ENGINE + ": " + chosen.length + " split points; " + pass + " passed, " + fail + " failed");
process.exitCode = fail ? 1 : 0;
