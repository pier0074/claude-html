// The guard: stops a secret before it reaches Claude. Run by guard.sh from
// two Claude Code hooks, with the hook's JSON note on stdin:
//
//   UserPromptSubmit   a prompt holding a secret is blocked, and the user
//                      is told which kind and how many — never the value
//   PreToolUse (Bash)  a command holding one is put to the user in Claude
//                      Code's own permission dialog
//
//   osascript -l JavaScript guard.js prompt|bash <clone> <state> <list> <conf> [dialog <private folder>]
//   … answer-prompt|answer-bash <clone> <state> <list> <conf> cancel|allow|safe|stop|timeout|"" <wait>
//   node guard.js …
//
// With "dialog", someone is at the screen to answer: a match is put in
// the pending state and {"choose": "<kinds>", …} returned (with, for a
// command, its first line masked; what the window's boxes show is written
// to files in the private folder, see details()), guard.sh asks in a dialog, and the
// answer comes back as answer-…, with the same note. Allow, safe and stop
// return no decision: what happens next is what would have happened
// without the guard.
//
// Only the rules that are sure of themselves, from redact.js, and the
// owner's own list. After a block, the very next prompt of the same session,
// within ten minutes of it (or of the window closing), may be one word,
// which is answered here and never reaches Claude: cancel, allow, safe or
// stop.
//
// It fails open: whatever goes wrong, it prints nothing, and the prompt or
// the command goes ahead as if it were not here. The state it keeps holds
// rule names and salted fingerprints, never a value and never a prompt.

function run(argv) {
  "use strict";
  try { return guard(argv) || ""; } catch (e) { return ""; }
}

function guard(argv) {
  "use strict";
  var KIND = argv[0], HERE = argv[1], STATE = argv[2], LIST = argv[3], CONF = argv[4], ARG = argv[5] || "";
  var JXA = typeof $ !== "undefined";
  var fm = JXA ? $.NSFileManager.defaultManager : null, nfs = JXA ? null : require("fs");

  // ── the platform ──
  function read(p) {
    if (!p) return null;
    if (JXA) {
      if (!fm.fileExistsAtPath(p)) return null;
      var s = $.NSString.stringWithContentsOfFileEncodingError(p, 4, null);
      var t = s ? $.CFMakeCollectable(s).js : null;
      return typeof t === "string" ? t : null;
    }
    try { return nfs.readFileSync(p, "utf8"); } catch (e) { return null; }
  }
  // Written in place, so a file kept as a symlink stays one, readable by
  // its owner only.
  function write(p, text) {
    if (JXA) {
      var ok = $.NSString.alloc.initWithUTF8String(text).writeToFileAtomicallyEncodingError(p, false, 4, null);
      fm.setAttributesOfItemAtPathError({ NSFilePosixPermissions: 384 }, p, null);
      return !!ok;
    }
    try { nfs.writeFileSync(p, text, { encoding: "utf8", mode: 384 }); nfs.chmodSync(p, 384); return true; }
    catch (e) { return false; }
  }
  function remove(p) {
    if (JXA) { fm.removeItemAtPathError(p, null); return; }
    try { nfs.unlinkSync(p); } catch (e) {}
  }
  function stdin() {
    if (JXA) {
      var d = $.NSFileHandle.fileHandleWithStandardInput.readDataToEndOfFile;
      var s = $.NSString.alloc.initWithDataEncoding(d, 4);
      return s && !s.isNil() ? s.js : "";
    }
    try { return nfs.readFileSync(0, "utf8"); } catch (e) { return ""; }
  }

  var note = JSON.parse(stdin() || "null");
  if (!note || typeof note !== "object") return "";
  var src = read(HERE + "/build/redact.js");
  if (src === null) return "";
  var lib = new Function(src + "\nreturn [claudeHtmlRedactor, fingerprint];")();

  // The rules the guard uses: a token's own prefix, a key block, a
  // header, a password in a URL or after its flag, a name in capitals.
  // Not the forms that take some reading: password: in prose, cookies.
  var SURE = {};
  ("anthropic openai github gitlab aws-key-id google-api-key slack-token slack-webhook discord-webhook " +
   "discord-token stripe npm pypi huggingface sendgrid twilio telegram private-key jwt auth-header bearer " +
   "url-password user-password sshpass mysql-password aws-secret env-name flag").split(" ")
    .forEach(function (r) { SURE[r] = true; });
  var LABEL = {
    anthropic: "Anthropic key", openai: "OpenAI key", github: "GitHub token", gitlab: "GitLab token",
    "aws-key-id": "AWS key id", "aws-secret": "AWS secret key", "google-api-key": "Google API key",
    "slack-token": "Slack token", "slack-webhook": "Slack webhook", "discord-webhook": "Discord webhook",
    "discord-token": "Discord token", stripe: "Stripe key", npm: "npm token", pypi: "PyPI token",
    huggingface: "Hugging Face token", sendgrid: "SendGrid key", twilio: "Twilio key",
    telegram: "Telegram bot token", "private-key": "private key", jwt: "JWT",
    "auth-header": "Authorization header", bearer: "bearer token", "url-password": "password in a URL",
    "user-password": "password after -u", sshpass: "sshpass password", "mysql-password": "MySQL password",
    "env-name": "secret variable", flag: "secret flag", "own list": "your own list"
  };
  var red = lib[0](read(LIST) || "", true, !JXA, SURE), fp = lib[1];

  // What is pending lasts ten minutes for an answer in words. The window's
  // answer comes once it has closed, <wait> seconds (argv[6], up to an
  // hour) after the pending began: it must still find it, or the prompt
  // would go through for want of it.
  var sid = String(note.session_id || ""), now = Date.now(), LIMIT = 10 * 60 * 1000;
  if (/^answer-/.test(KIND)) LIMIT = Math.max(LIMIT, ((Number(argv[6]) || 0) + 60) * 1000);
  var st = null;
  try { st = JSON.parse(read(STATE) || "null"); } catch (e) { st = null; }
  // A state from another session, or too old, is no state.
  if (!st || typeof st !== "object" || st.session !== sid) st = {};
  if (st.pending && !(now - st.pending.time < LIMIT)) st.pending = null;
  if (st.pass && !(now - st.pass.time < LIMIT)) st.pass = null;
  function save() {
    if (!st.pending && !st.pass) { remove(STATE); return; }
    st.session = sid;
    write(STATE, JSON.stringify(st));
  }
  function salt() {
    var h = "";
    for (var i = 0; i < 16; i++) h += Math.floor(Math.random() * 16).toString(16);
    return h;
  }
  function block(reason) {
    return JSON.stringify({ decision: "block", reason: reason, suppressOriginalPrompt: true });
  }
  // What the text holds, less what a one-time allow lets through.
  function matches(text) {
    var got = red.find(text), out = [], used = false;
    got.forEach(function (m) {
      var passed = st.pass && st.pass.entries.some(function (p) { return fp(p.salt, m.value) === p.hash; });
      if (passed) used = true; else out.push(m);
    });
    // A pass is good for one prompt or command that holds what it allowed.
    if (used) st.pass = null;
    return out;
  }
  function summary(found) {
    var n = {}, order = [];
    found.forEach(function (m) {
      var l = LABEL[m.rule] || m.rule;
      if (!n[l]) { n[l] = 0; order.push(l); }
      n[l]++;
    });
    return order.map(function (l) { return l + " (" + n[l] + ")"; }).join(", ");
  }
  function pend(found) {
    st.pending = { time: now, entries: found.map(function (m) {
      var s = salt();
      return { rule: m.rule, salt: s, hash: fp(s, m.value) };
    }) };
  }
  function today() { return new Date(now).toISOString().slice(0, 10); }
  function recordSafe(p) {
    var list = read(LIST) || "";
    if (list && list.slice(-1) !== "\n") list += "\n";
    p.entries.forEach(function (e) {
      list += "safe:" + e.salt + ":" + e.hash + "   # " + e.rule + ", " + today() + "\n";
    });
    return write(LIST, list);
  }
  // The conf's one line, changed where it stands or added.
  function turnOff() {
    var conf = read(CONF) || "", line = 'CLAUDE_HTML_GUARD="off"', re = /^[ \t]*(export[ \t]+)?CLAUDE_HTML_GUARD=.*$/m;
    conf = re.test(conf) ? conf.replace(re, line) : conf + (conf && conf.slice(-1) !== "\n" ? "\n" : "") + line + "\n";
    return write(CONF, conf);
  }
  var TEXT = "\u26a0 claude-html: your prompt has been interrupted \u2014 sensitive information detected (%).\n" +
      "  Nothing was sent. Retype it without it, or answer:\n\n" +
      "  cancel  do not send\n" +
      "  allow   it is sensitive, send it this time only\n" +
      "  safe    it is not sensitive, send it and never ask again\n" +
      "  stop    turn this check off (claude-html --guard on turns it back on)";
  // The dialog's limit, in words: 60 is "1 minute". The seconds come from
  // guard.sh, which read the setting (platform.sh's ch_guard_wait).
  function span(secs) {
    secs = Number(secs) || 60;
    return secs % 60 ? secs + " second" + (secs === 1 ? "" : "s")
                     : secs / 60 + " minute" + (secs === 60 ? "" : "s");
  }
  var NEXT = "To never be asked about this value again, answer `safe` as your next prompt; `stop` turns the check off.";
  function refuse(kinds) {
    return JSON.stringify({
      hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: "deny",
        permissionDecisionReason: "claude-html: this command carries a secret (" + kinds + ") and was not run. " +
          "Do not put the secret in the command: read it from ~/.my.cnf, an environment variable or a " +
          "credential helper instead." },
      systemMessage: "\u26d4 claude-html stopped a command that carries a secret (" + kinds + "). " + NEXT
    });
  }
  function kindsOf(p) { return summary(p.entries); }
  // What the command is, for the dialog: its first line, masked by every
  // rule and the own list (not only the sure ones), without anything that
  // would not sit on one line of a window, and short.
  function firstLine(cmd) {
    var all = lib[0](read(LIST) || "", true, !JXA);
    var l = String(cmd || "").replace(/^\s+/, "").split(/\r?\n/)[0];
    l = all.text(l).replace(/[\u0000-\u001f\u007f]+/g, " ");
    var more = /\n\s*\S/.test(String(cmd || "").replace(/^\s+/, ""));
    if (l.length > 100) {
      var cut = 99;
      if ((l.charCodeAt(cut - 1) & 0xFC00) === 0xD800) cut--;
      l = l.slice(0, cut); more = true;
    }
    return l + (more ? " …" : "");
  }
  // What the dialog's boxes show, for the owner's eyes on his own screen
  // only: each match with up to 40 characters on each side, the match
  // itself between \u0001 and \u0002, one a line; and for a command, the
  // command whole. Written to files in the folder guard.sh made private to
  // its owner for this one window (argv[6]), never on a command line: the
  // window reads them and deletes them, and guard.sh takes the folder away
  // when the hook ends. details.txt is the same for a Linux window, the
  // marks as « and ».
  function places(text, found) {
    var out = [];
    found.forEach(function (m) {
      var v = String(m.value || ""), from = 0, i = -1;
      if (!v) return;
      // The same value twice is two places; one inside another's is not.
      for (;;) {
        i = text.indexOf(v, from);
        if (i < 0 || !out.some(function (p) { return i < p.b && i + v.length > p.a; })) break;
        from = i + 1;
      }
      out.push({ rule: m.rule, a: i, b: i < 0 ? -1 : i + v.length, value: v });
    });
    return out;
  }
  function flat(s) { return s.replace(/\r?\n/g, " \u23ce ").replace(/[\u0000-\u001f\u007f]/g, " "); }
  function cut(text, i, back) {   // a place to cut at, never inside a pair of surrogates
    var c = text.charCodeAt(i);
    return i > 0 && i < text.length && c >= 0xDC00 && c <= 0xDFFF ? i + (back ? -1 : 1) : i;
  }
  function context(text, p) {
    var label = (LABEL[p.rule] || p.rule) + ":  ";
    if (p.a < 0) return label + "\u0001" + flat(p.value) + "\u0002";
    var a = cut(text, Math.max(0, p.a - 40), true), b = cut(text, Math.min(text.length, p.b + 40), false);
    return label + (a > 0 ? "\u2026" : "") + flat(text.slice(a, p.a)) + "\u0001" + flat(text.slice(p.a, p.b)) + "\u0002" +
      flat(text.slice(p.b, b)) + (b < text.length ? "\u2026" : "");
  }
  function details(text, found, isCommand) {
    var dir = argv[6] || "";
    if (!dir || !/^\//.test(dir)) return;
    var ps = places(text, found);
    var lines = ps.map(function (p) { return context(text, p); }).join("\n");
    write(dir + "/found", lines);
    var linux = "What was found (shown on this screen only, kept nowhere):\n\n" + lines;
    if (isCommand) {
      // The command as Claude wrote it, each place of a match marked.
      var marked = "", at = 0;
      ps.filter(function (p) { return p.a >= 0; }).sort(function (x, y) { return x.a - y.a; }).forEach(function (p) {
        if (p.a < at) return;
        marked += text.slice(at, p.a) + "\u0001" + text.slice(p.a, p.b) + "\u0002"; at = p.b;
      });
      marked += text.slice(at);
      write(dir + "/command", marked);
      linux += "\n\n\nThe whole command, as Claude wrote it:\n\n" + text;
    }
    write(dir + "/details.txt", linux.replace(/\u0001/g, "\u00ab").replace(/\u0002/g, "\u00bb") + "\n");
  }
  // The project, as the index names it: the last folder of where it runs.
  function project() {
    return String(note.cwd || "").replace(/\/+$/, "").split("/").pop().replace(/["\\\u0000-\u001f]/g, "");
  }
  // Claude Code's own permission dialog asks; where it would not show one,
  // or its documentation does not say it would, the command is refused
  // rather than let through.
  function askOrRefuse(kinds) {
    var mode = String(note.permission_mode || "");
    if (mode === "bypassPermissions" || mode === "dontAsk") return refuse(kinds);
    return JSON.stringify({
      hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: "ask",
        permissionDecisionReason: "Claude's command has been interrupted \u2014 sensitive information detected (" +
          kinds + "). Deny to stop it; allow to run it this time only.\n" + NEXT }
    });
  }

  // The answer from the dialog, to what was found just before.
  if (KIND === "answer-prompt" || KIND === "answer-bash") {
    var pa = st.pending;
    if (!pa) return "";
    st.pending = null;
    var bash = KIND === "answer-bash";
    if (ARG === "allow" || ARG === "safe" || ARG === "stop") {
      if (ARG === "safe") recordSafe(pa);
      if (ARG === "stop") turnOff();
      save();
      // No decision at all, for a command as for a prompt: the guard only
      // ever takes something away. "allow" here would also skip Claude
      // Code's own permission check for the whole command, which this
      // dialog never showed; with nothing said, that check runs as usual.
      return "";
    }
    if (ARG === "cancel") { save(); return bash ? refuse(kindsOf(pa)) : block("Dropped. Nothing was sent."); }
    // Nobody answered in time: Cancel, and the words still work after it.
    if (ARG === "timeout") {
      // The ten minutes for words start now, when the window has closed.
      pa.time = now;
      st.pending = pa;
      save();
      var late = "sensitive information was detected (" + kindsOf(pa) + ") and nobody answered within " + span(argv[6]) + ".";
      if (!bash) {
        return block("\u23f8 claude-html: " + late + "\n  Nothing was sent. Retype the prompt without it, or answer:  allow \u00b7 safe \u00b7 stop");
      }
      return JSON.stringify({
        hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: "deny",
          permissionDecisionReason: "claude-html: in this command " + late + " It was not run. " +
            "Stop here and do not retry it: wait for the user." },
        systemMessage: "\u23f8 claude-html: " + late + " The command was not run. " + NEXT
      });
    }
    // No answer at all: as if there were no dialog, the answer still open.
    pa.time = now;
    st.pending = pa;
    save();
    return bash ? askOrRefuse(kindsOf(pa)) : block(TEXT.replace("%", kindsOf(pa)));
  }

  if (KIND === "prompt") {
    var prompt = typeof note.prompt === "string" ? note.prompt : "";
    var word = prompt.replace(/^\s+|\s+$/g, "").toLowerCase();
    if (st.pending && (word === "cancel" || word === "allow" || word === "safe" || word === "stop")) {
      var p = st.pending;
      st.pending = null;
      if (word === "cancel") { save(); return block("Dropped. Nothing was sent."); }
      if (word === "allow") {
        st.pass = { time: now, entries: p.entries };
        save();
        return block("Allowed once. Press ↑ and Enter to send it again.");
      }
      if (word === "safe") {
        if (!recordSafe(p)) { save(); return block("Could not write " + LIST + "; nothing was recorded."); }
        save();
        return block("Recorded as not sensitive. Press \u2191 and Enter to send it again. " +
                     "Saved pages will show it after the next save.");
      }
      turnOff();
      save();
      return block("The secret check is off. claude-html --guard on turns it back on.");
    }
    // Anything else is a prompt like any other, and what was pending goes.
    st.pending = null;
    var found = matches(prompt);
    if (!found.length) { save(); return ""; }
    // Pending before anything is asked: if Claude Code gives up on this
    // hook while the dialog waits, what was found is still on record.
    pend(found);
    save();
    if (ARG === "dialog") { details(prompt, found, false); return JSON.stringify({ choose: summary(found), project: project() }); }
    return block(TEXT.replace("%", summary(found)));
  }

  if (KIND === "bash") {
    if (note.tool_name !== "Bash" || !note.tool_input || typeof note.tool_input.command !== "string") return "";
    var hits = matches(note.tool_input.command);
    if (!hits.length) { save(); return ""; }
    pend(hits);
    save();
    var kinds = summary(hits);
    if (ARG === "dialog") {
      details(note.tool_input.command, hits, true);
      return JSON.stringify({ choose: kinds, project: project(), command: firstLine(note.tool_input.command) });
    }
    return askOrRefuse(kinds);
  }
  return "";
}

// osascript calls run() by itself; node has to be asked.
if (typeof $ === "undefined" && typeof require !== "undefined" &&
    typeof module !== "undefined" && require.main === module) {
  var out = run(process.argv.slice(2));
  if (out) process.stdout.write(out + "\n");
}
