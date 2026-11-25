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
"use strict";

var ran = 0, failed = [], pass = 0, fail = 0;

exports.test = function (name, fn) {
  ran++;
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
  if (ok) { pass++; return; }
  fail++;
  console.log("  FAIL  " + name + (detail ? "\n        " + detail : ""));
};
exports.checkEq = function (name, got, want) {
  if (got === want) { pass++; return; }
  fail++;
  console.log("  FAIL  " + name + "\n        expected: " + want + "\n        got:      " + got);
};
exports.counts = function () { return { pass: pass, fail: fail }; };
exports.done = function (prefix) {
  console.log("  " + (prefix || "") + pass + " passed, " + fail + " failed");
  process.exitCode = fail ? 1 : 0;
};
