// The build's part of the plan limits and the API budget: what was spent
// in the budget's period, for the pages, the status line and the stop
// rule. Read by convert.js as redact.js is, the same bytes under
// osascript and node; nothing here reads a file or the clock.
//
// The usage data is project -> UTC hour ("2026-11-20T14") -> model ->
// [input, output, cache read, cache write, replies, of it 1-hour writes,
// of it writes of unknown duration, cost], the cost in micro-dollars and
// present only where Claude Code recorded one (prices.js's T.COST).

function claudeHtmlLimits() {
  "use strict";
  var COST = 7;

  // A cell's cost, in micro-dollars, or null for none: Claude Code's own,
  // recorded at list price when a session ends.
  function recorded(cell) {
    return cell && cell.length > COST && cell[COST] !== null && cell[COST] !== undefined ? cell[COST] : null;
  }

  function hourOf(key) {
    var t = Date.parse(key + ":00:00Z");
    return isNaN(t) ? null : t / 1000;
  }

  function inside(h, start, end) { var t = hourOf(h); return t !== null && t >= start && t < end; }
  function tokens(c) { return (c[0] || 0) + (c[1] || 0) + (c[2] || 0) + (c[3] || 0); }

  // What was spent from start (included) to end (excluded), epoch seconds.
  //
  // THE ONE PLACE the budget's dollars come from: the page, the status line,
  // the stop and its announcements all read this total.
  //
  // sessions is [[id, usage], …], each usage that session's own
  // {hour: {model: cell}} with the replies it shares with another session
  // already taken out (the dashboard's de-duplication), so nothing is
  // counted twice across a resume or a fork. PR is prices.js's helper, or
  // null without a price file.
  //
  // Decided per session, never per cell: Claude Code records a session's
  // cost as one running total in the hour it was written, while its tokens
  // sit in the hours they were used, with no cost beside them. Adding a
  // calculated cost for those hours to the recorded one would count the
  // same work twice. So a session with a recorded cost anywhere counts its
  // recorded cost, in the hours it was recorded; one without counts the
  // price table's cost of its tokens, hour by hour. A recorded cost that
  // lands after the period is the next period's, and that session's tokens
  // in this one count nothing here: its money is counted once, where it
  // was recorded.
  //
  // Returns { micro, unpriced, counted }: unpriced, the tokens in the
  // period no recorded cost or price covers; counted, the sessions with
  // something in the total (the status line and the stop add a running
  // session's own cost only when it is not among them).
  function weekSpend(sessions, start, end, PR) {
    var micro = 0, unpriced = 0, ids = [];
    (sessions || []).forEach(function (s) {
      var id = s[0], u = s[1] || {}, hasRec = false, rec = 0, recIn = false;
      Object.keys(u).forEach(function (h) {
        Object.keys(u[h] || {}).forEach(function (m) {
          var c = recorded(u[h][m]);
          if (c === null) return;
          hasRec = true;
          if (inside(h, start, end)) { rec += c; recIn = true; }
        });
      });
      if (hasRec) {
        if (recIn) { micro += rec; ids.push(id); }
        return;
      }
      if (PR) {
        var t = PR.total(u, { since: start * 1000, until: end * 1000 });
        micro += t.calc; unpriced += t.unpriced;
        if (t.priced) ids.push(id);
        return;
      }
      Object.keys(u).forEach(function (h) {
        if (!inside(h, start, end)) return;
        Object.keys(u[h] || {}).forEach(function (m) { unpriced += tokens(u[h][m]); });
      });
    });
    return { micro: Math.round(micro), unpriced: unpriced, counted: ids };
  }

  return { weekSpend: weekSpend, recorded: recorded };
}

if (typeof module !== "undefined" && module.exports) module.exports = claudeHtmlLimits;
