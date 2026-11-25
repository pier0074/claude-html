// What the JavaScript suites share, as lib.sh is for the shell ones.
//
//   var L = require("./lib.js");
//
//   L.test(name, fn)           an assert-style test; a throw is its failure
//   L.report()                 the tests' failures and count; exits 1 on one
//   L.check(name, ok, detail)  a counted check, said only when it fails
//   L.checkEq(name, got, want) the same, comparing two values
//   L.done(prefix)             the checks' count, as run-all.sh reads it
//   L.tests() / L.counts()     the figures, for a suite that says them its own way
//   L.section(part, name)      whether a section of a long suite runs, as lib.sh's
"use strict";

var ran = 0, failed = [], pass = 0, fail = 0;

// A long suite in parts, as lib.sh says: its header says how many
// ("// parts: 4"), each section which part it is in,
//   if (section(2, "the archiver")) { … }
// and CLAUDE_HTML_TEST_PART=i/n runs only part i's, saying each one's name.
var fs = require("fs");
var PART = process.env.CLAUDE_HTML_TEST_PART || "", partI = 0, current = null;
if (PART) {
  var main = require.main && require.main.filename;
  var m = main && /^\/\/ parts: ([0-9]+)$/m.exec(fs.readFileSync(main, "utf8"));
  var mm = /^([1-9][0-9]*)\/([0-9]+)$/.exec(PART);
  if (!m || !mm || mm[2] !== m[1] || +mm[1] > +m[1]) {
    console.log("  FAIL  CLAUDE_HTML_TEST_PART=" + PART + ", but " + main + " has " + (m ? m[1] : "no") + " parts");
    process.exit(1);
  }
  partI = +mm[1];
}
exports.section = function (part, name) {
  if (!partI) { current = name; return true; }
  if (part === partI) { current = name; console.log("  section  " + name); return true; }
  current = null; return false;
};
// Every check goes through here: listed, and in a part, outside every
// section, a failure. Whether it may count as it came out.
function placed(name) {
  if (process.env.CLAUDE_HTML_TEST_CHECKS) fs.appendFileSync(process.env.CLAUDE_HTML_TEST_CHECKS, name + "\n");
  if (partI && current === null) {
    console.log("  FAIL  " + name + " (a check outside every section, in a part)");
    return false;
  }
  return true;
}

exports.test = function (name, fn) {
  ran++;
  if (!placed(name)) { failed.push([name, "outside every section"]); return; }
  try { fn(); } catch (e) { failed.push([name, e.message]); }
};
exports.tests = function () { return { ran: ran, failed: failed }; };
exports.report = function () {
  if (failed.length) {
    failed.forEach(function (f) { console.log("FAIL " + f[0] + "\n     " + f[1]); });
    console.log(failed.length + " of " + ran + " failed");
    process.exit(1);
  }
  console.log(ran + " passed");
};

exports.check = function (name, ok, detail) {
  if (!placed(name)) { fail++; return; }
  if (ok) { pass++; return; }
  fail++;
  console.log("  FAIL  " + name + (detail ? "\n        " + detail : ""));
};
exports.checkEq = function (name, got, want) {
  if (!placed(name)) { fail++; return; }
  if (got === want) { pass++; return; }
  fail++;
  console.log("  FAIL  " + name + "\n        expected: " + want + "\n        got:      " + got);
};
exports.counts = function () { return { pass: pass, fail: fail }; };
exports.done = function (prefix) {
  console.log("  " + (prefix || "") + pass + " passed, " + fail + " failed");
  process.exitCode = fail ? 1 : 0;
};
