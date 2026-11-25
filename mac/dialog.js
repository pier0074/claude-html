// The guard's question, on macOS: a window of its own, four choices as
// radio buttons with the first, Cancel, picked already, and one button,
// OK. Return is OK, Escape is Cancel. A countdown beside OK says how long
// it waits; at 0:00 it closes by itself, which counts as no answer.
//
//   osascript -l JavaScript dialog.js [options] prompt|bash <project> <found> [<command>]
//
// <command> is the first line of the command, already masked, shown so
// the answer is about something seen. <found> names the kinds of secret,
// never one. Prints cancel, allow, safe, stop, or timeout.
//
// The same window stops a prompt by a limit rule or the API budget, its
// rows and last two choices given (limits.sh writes them):
//
//   … dialog.js [options] limits <head> <key1> <value1> <key2> <value2> <choice3> <choice4>
//
// and prints cancel, allow, until, stop or timeout. And it asks before the
// limits are changed from the Token usage page, Cancel the default:
//
//   … dialog.js [options] confirm <title> <subtitle> <rows: key<TAB>value per line>
//
// which prints apply, cancel or timeout.
//
// Options, before the kind:
//   --ok <label>           the confirmation's button that says yes ("Apply";
//                          "Open", "Forget" where that is what it does)
//   --limit <seconds>      how long it waits (60; the hook gives the owner's
//                          CLAUDE_HTML_GUARD_WAIT); the countdown counts it down
//   --box <key> <file>     a disclosure arrow on the row <key> ("Found:"): the
//   --pre <key> <file>     file's text in a box under it, wrapped (--box) or
//                          as lines that scroll sideways (--pre)
// What a box shows may be a secret, the owner's own, shown on his own screen
// only when he opens it. So it never comes on this command line, which any
// local process can read: it comes in a file of the caller's, private to
// its owner, which is read here first thing and deleted at once. Between
// \u0001 and \u0002 is what was found, shown in bold red; the copy button
// copies the text without them.
//
// For the tests only:
//   --snap <png>           a picture of the window, then it closes, as cancel:
//   --snap-after <secs>    at once, or that long into a real wait
//   --open <key>           that row's box open from the start
//   --selftest <file>      selects the title, types ⌘C, opens the first box,
//                          clicks its copy button (into a pasteboard of its own),
//                          closes it again, and writes what came of each to
//                          <file>; the clipboard is given back as it was
//   --offscreen            drawn, timed and pictured as ever, but clear, with
//                          no Dock icon and nothing brought forward: the
//                          window exists, nobody sees it; --selftest works on it
//   countdown <seconds>|start [confirm]   prints the countdown's words, nothing
//                          shown; start is where it starts, the --limit
//
// Its own window, brought forward as its own: nothing is sent to another
// application, and no permission is asked for.
if (typeof ObjC !== "undefined") ObjC.import("Cocoa");

// The countdown's words: "Cancel in 9:59", or for the confirmation
// "closes in 9:59 — nothing changed". Whole seconds, never below 0:00.
function countdown(secs, kind) {
  secs = Math.max(0, Math.floor(Number(secs) || 0));
  var h = Math.floor(secs / 3600), m = Math.floor(secs % 3600 / 60), s = secs % 60;
  var t = (h ? h + ":" + (m < 10 ? "0" : "") : "") + m + ":" + (s < 10 ? "0" : "") + s;
  return kind === "confirm" ? "closes in " + t + " — nothing changed" : "Cancel in " + t;
}

// A box's text as it is copied: without the marks around what was found.
function plain(text) { return String(text).replace(/[\u0001\u0002]/g, ""); }

function options(argv) {
  var o = { limit: 60, boxes: {}, order: [], snap: "", snapAfter: 0, open: {}, selftest: "", offscreen: false, ok: "Apply" }, i = 0;
  while (i < argv.length && /^--/.test(argv[i])) {
    var a = argv[i];
    if (a === "--ok") { o.ok = /^[A-Za-z][A-Za-z ]{0,11}$/.test(argv[i + 1] || "") ? argv[i + 1] : "Apply"; i += 2; }
    else if (a === "--limit") { o.limit = Math.floor(Number(argv[i + 1])) || 60; i += 2; }
    else if (a === "--box" || a === "--pre") {
      if (!o.boxes[argv[i + 1]]) o.order.push(argv[i + 1]);
      o.boxes[argv[i + 1]] = { file: argv[i + 2] || "", pre: a === "--pre" }; i += 3;
    }
    else if (a === "--snap") { o.snap = argv[i + 1] || ""; i += 2; }
    else if (a === "--snap-after") { o.snapAfter = Number(argv[i + 1]) || 0; i += 2; }
    else if (a === "--open") { o.open[argv[i + 1]] = true; i += 2; }
    else if (a === "--selftest") { o.selftest = argv[i + 1] || ""; i += 2; }
    else if (a === "--offscreen") { o.offscreen = true; i += 1; }
    else break;
  }
  if (o.limit < 1) o.limit = 60;
  o.rest = argv.slice(i);
  return o;
}

// A private file's text, and the file gone, whatever it held.
function take(path) {
  if (!path) return null;
  var s = $.NSString.stringWithContentsOfFileEncodingError(path, 4, null);
  $.NSFileManager.defaultManager.removeItemAtPathError(path, null);
  return s && !s.isNil() ? s.js : null;
}

function run(argv) {
  var o = options(argv);
  // The private files first, before anything is drawn: none is left on disk
  // while the window is up.
  var boxes = {};
  o.order.forEach(function (k) {
    var t = take(o.boxes[k].file);
    if (t) boxes[k] = { text: t, pre: o.boxes[k].pre };
  });
  var a = o.rest;
  if (a[0] === "countdown") return countdown(a[1] === "start" ? o.limit : a[1], a[2]);
  var S;
  if (a[0] === "confirm") {
    S = { title: a[1] || "", sub: a[2] || "", subBold: false, confirm: true,
          rows: String(a[3] || "").split("\n").filter(Boolean).map(function (l) {
            var i = l.indexOf("\t"); return i < 0 ? ["", l] : [l.slice(0, i), l.slice(i + 1)];
          }) };
  } else if (a[0] === "limits") {
    S = { title: "Your prompt has been interrupted", sub: a[1] || "", subBold: true,
          rows: [[a[2] || "", a[3] || ""], [a[4] || "", a[5] || ""]],
          choices: ["Cancel — do not send", "Allow once — send this prompt only", a[6] || "", a[7] || ""],
          answers: ["cancel", "allow", "until", "stop"] };
  } else {
    var bash = a[0] === "bash", project = a[1] || "", verb = bash ? "run" : "send";
    S = { title: bash ? "Claude's command has been interrupted" : "Your prompt has been interrupted",
          sub: "Sensitive information detected", subBold: true,
          rows: [["Where:", (bash ? "a command from Claude" : "your prompt in Claude Code") +
                            (project ? "  ·  project " + project : "")], ["Found:", a[2] || ""]],
          choices: ["Cancel — do not " + verb,
                    "Allow once — it is sensitive, " + verb + " it this time only",
                    "Safe — it is not sensitive, " + verb + " it and never ask again",
                    "Stop — turn this check off"],
          answers: ["cancel", "allow", "safe", "stop"] };
    if (a[3]) S.rows.push(["Command:", a[3]]);
  }
  return show(S, o, boxes);
}

// A minimal main menu, its Edit menu holding Copy and Select All: without
// one, an application started by osascript has nowhere to send ⌘C, and a
// selected text is not copied.
function editMenu(app) {
  var bar = $.NSMenu.alloc.init, appItem = $.NSMenuItem.alloc.init;
  bar.addItem(appItem); appItem.setSubmenu($.NSMenu.alloc.initWithTitle("claude-html"));
  var editItem = $.NSMenuItem.alloc.init, edit = $.NSMenu.alloc.initWithTitle("Edit");
  edit.addItemWithTitleActionKeyEquivalent("Copy", "copy:", "c");
  edit.addItemWithTitleActionKeyEquivalent("Select All", "selectAll:", "a");
  editItem.setSubmenu(edit); bar.addItem(editItem);
  app.setMainMenu(bar);
}

// What each box holds, said in its top strip.
var CAPTION = {
  "Found:": "What was found, with what is around it \u2014 shown here only",
  "Command:": "The whole command, as Claude wrote it",
  "Rule:": "Your stop rules, from the conf",
  "Budget:": "Your budget, from the conf",
  "File:": "The lines Apply writes to the file"
};

function show(S, o, boxes) {
  var app = $.NSApplication.sharedApplication;
  app.setActivationPolicy(o.offscreen ? $.NSApplicationActivationPolicyAccessory : $.NSApplicationActivationPolicyRegular);
  editMenu(app);
  var W = 500, P = 24, TRI = 18, MAXBOX = 200, STRIP = 22, INSET = 4, CW = 58;
  var body = $.NSFont.systemFontOfSize(13), bold = $.NSFont.boldSystemFontOfSize(15);
  var mono = $.NSFont.userFixedPitchFontOfSize(11);
  var monoBold = $.NSFontManager.sharedFontManager.convertFontToHaveTrait(mono, $.NSBoldFontMask);
  // Titled, without a close button: an answer is one of the choices.
  var win = $.NSWindow.alloc.initWithContentRectStyleMaskBackingDefer($.NSMakeRect(0, 0, W, 300),
    $.NSWindowStyleMaskTitled, $.NSBackingStoreBuffered, false);
  win.setTitle("claude-html");
  var v = win.contentView;
  v.setWantsLayer(true);
  // Every text can be selected and copied: titles, keys, values, the countdown.
  function field(text, font, color) {
    var t = $.NSTextField.alloc.initWithFrame($.NSMakeRect(0, 0, 10, 10));
    t.setStringValue($(String(text))); t.setFont(font); t.setBezeled(false); t.setDrawsBackground(false);
    t.setEditable(false); t.setSelectable(true);
    t.cell.setLineBreakMode($.NSLineBreakByTruncatingTail);
    if (color) t.setTextColor(color);
    v.addSubview(t);
    return t;
  }
  // A button's action, as a block: what a click does, without an ObjC class
  // of our own (registering one hangs osascript on recent macOS).
  var keep = [];
  function onClick(b, fn) {
    var op = $.NSBlockOperation.blockOperationWithBlock(function () { try { fn(); } catch (e) {} });
    keep.push(op); b.setTarget(op); b.setAction("main");
  }

  var icon = $.NSImageView.alloc.initWithFrame($.NSMakeRect(0, 0, 40, 40));
  icon.setImage($.NSImage.imageNamed("NSCaution"));
  v.addSubview(icon);
  var t1 = field(S.title, bold), t2 = S.subBold ? field(S.sub, bold) : field(S.sub, body, $.NSColor.secondaryLabelColor);

  var anyBox = S.rows.some(function (r) { return boxes[r[0]]; });
  var KX = P + (anyBox ? TRI : 0), K = 52;
  S.rows.forEach(function (r) {
    var w = $(r[0]).sizeWithAttributes($({ NSFont: body })).width + 8;
    if (w > K) K = Math.ceil(w);
  });
  var BW = W - P - KX;
  var PB = $.NSPasteboard.generalPasteboard;
  var rows = S.rows.map(function (r) {
    var row = { key: r[0] ? field(r[0], body, $.NSColor.secondaryLabelColor) : null,
                val: field(r[1], r[0] === "Command:" ? $.NSFont.userFixedPitchFontOfSize(12) : body),
                box: null, open: false };
    var b = boxes[r[0]];
    if (!b) return row;
    // The arrow: closed, ▸, until it is clicked.
    var tri = $.NSButton.alloc.initWithFrame($.NSMakeRect(0, 0, 16, 16));
    tri.setButtonType($.NSButtonTypePushOnPushOff); tri.setBezelStyle($.NSBezelStyleDisclosure);
    tri.setTitle(""); tri.setState($.NSControlStateValueOff);
    v.addSubview(tri);
    // The box: a strip with what it holds and a copy button at its top
    // right, the text under it, monospaced and selectable, scrolling past
    // its height.
    var sv = $.NSScrollView.alloc.initWithFrame($.NSMakeRect(1, 1, BW - 2, MAXBOX));
    sv.setBorderType($.NSNoBorder); sv.setDrawsBackground(false);
    sv.setHasVerticalScroller(true); sv.setAutohidesScrollers(true);
    // Measured as narrow as it can be shown: with a scroller that takes
    // room of its own, when the system shows them always.
    var cs = sv.contentSize, sw = 0;
    if ($.NSScroller.preferredScrollerStyle === $.NSScrollerStyleLegacy) {
      sw = $.NSScroller.scrollerWidthForControlSizeScrollerStyle($.NSControlSizeRegular, $.NSScrollerStyleLegacy);
    }
    var tv = $.NSTextView.alloc.initWithFrame($.NSMakeRect(0, 0, cs.width - sw, cs.height));
    tv.setEditable(false); tv.setSelectable(true); tv.setRichText(true); tv.setDrawsBackground(false);
    tv.setTextContainerInset($.NSMakeSize(INSET, 2));
    tv.setVerticallyResizable(true); tv.setMinSize($.NSMakeSize(0, 0)); tv.setMaxSize($.NSMakeSize(1e7, 1e7));
    var lm = tv.layoutManager, tc = tv.textContainer;
    // A command keeps its lines, and scrolls sideways: a line broken in
    // two would read as two commands. The rest wraps.
    if (b.pre) {
      sv.setHasHorizontalScroller(true);
      tv.setHorizontallyResizable(true);
      tc.setWidthTracksTextView(false); tc.setContainerSize($.NSMakeSize(1e7, 1e7));
    } else {
      tv.setHorizontallyResizable(false); tv.setAutoresizingMask($.NSViewWidthSizable);
      tc.setWidthTracksTextView(true);
    }
    // The text as it is copied, then the marked parts made bold red, by
    // their place in it (both count in UTF-16, as JavaScript does).
    var ts = tv.textStorage, marks = [], pos = 0, on = -1;
    String(b.text).split(/([\u0001\u0002])/).forEach(function (part) {
      if (part === "\u0001") { on = pos; return; }
      if (part === "\u0002") { if (on >= 0 && pos > on) marks.push([on, pos - on]); on = -1; return; }
      pos += part.length;
    });
    ts.replaceCharactersInRangeWithString($.NSMakeRange(0, ts.length), $(plain(b.text)));
    ts.addAttributeValueRange($.NSFontAttributeName, mono, $.NSMakeRange(0, ts.length));
    ts.addAttributeValueRange($.NSForegroundColorAttributeName, $.NSColor.labelColor, $.NSMakeRange(0, ts.length));
    marks.forEach(function (m) {
      ts.addAttributeValueRange($.NSFontAttributeName, monoBold, $.NSMakeRange(m[0], m[1]));
      ts.addAttributeValueRange($.NSForegroundColorAttributeName, $.NSColor.systemRedColor, $.NSMakeRange(m[0], m[1]));
    });
    sv.setDocumentView(tv);
    lm.ensureLayoutForTextContainer(tc);
    var used = lm.usedRectForTextContainer(tc);
    var sh = Math.max(20, Math.min(MAXBOX - STRIP, Math.ceil(used.size.height) + 4 + 4 + (b.pre ? 4 + sw : 0)));
    var bh = STRIP + sh + 1;
    var box = $.NSBox.alloc.initWithFrame($.NSMakeRect(0, 0, BW, bh));
    box.setBoxType($.NSBoxCustom); box.setTitlePosition($.NSNoTitle);
    box.setBorderColor($.NSColor.separatorColor); box.setBorderWidth(1); box.setCornerRadius(5);
    box.setFillColor($.NSColor.textBackgroundColor); box.setContentViewMargins($.NSMakeSize(0, 0));
    v.addSubview(box);
    var bv = box.contentView;
    sv.setFrame($.NSMakeRect(1, 1, BW - 2, sh));
    bv.addSubview(sv);
    var cap = $.NSTextField.alloc.initWithFrame($.NSMakeRect(INSET + 4, bh - STRIP + 3, BW - CW - 30, 15));
    cap.setStringValue($(CAPTION[r[0]] || "")); cap.setFont($.NSFont.systemFontOfSize(11));
    cap.setTextColor($.NSColor.secondaryLabelColor); cap.setBezeled(false); cap.setDrawsBackground(false);
    cap.setEditable(false); cap.setSelectable(true);
    bv.addSubview(cap);
    // The copy button: the whole text, as it came, to the clipboard, and
    // "copied" for a moment.
    var copy = $.NSButton.alloc.initWithFrame($.NSMakeRect(BW - CW - 6, bh - STRIP + 1, CW, 19));
    copy.setTitle("copy"); copy.setBezelStyle($.NSBezelStyleRoundRect);
    copy.setControlSize($.NSControlSizeSmall); copy.setFont($.NSFont.systemFontOfSize(11));
    bv.addSubview(copy);
    row.box = { view: box, tv: tv, copy: copy, tri: tri, h: bh, text: plain(b.text), copiedAt: 0 };
    row.open = !!o.open[r[0]];
    if (row.open) tri.setState($.NSControlStateValueOn);
    onClick(tri, function () { row.open = tri.state === $.NSControlStateValueOn; layout(); });
    onClick(copy, function () {
      PB.clearContents; PB.setStringForType($(row.box.text), $.NSPasteboardTypeString);
      copy.setTitle("copied"); row.box.copiedAt = elapsed() || 0.01;
    });
    return row;
  });

  var matrix = null, MH = 0;
  if (!S.confirm) {
    var cell = $.NSButtonCell.alloc.init;
    cell.setButtonType($.NSButtonTypeRadio); cell.setTitle("x"); cell.setFont(body);
    // One radio group: picking one unpicks the others.
    matrix = $.NSMatrix.alloc.initWithFrameModePrototypeNumberOfRowsNumberOfColumns(
      $.NSMakeRect(0, 0, W - 2 * P, 100), $.NSRadioModeMatrix, cell, S.choices.length, 1);
    matrix.setCellSize($.NSMakeSize(W - 2 * P, 21)); matrix.setIntercellSpacing($.NSMakeSize(0, 5));
    for (var i = 0; i < S.choices.length; i++) matrix.cellAtRowColumn(i, 0).setTitle(S.choices[i]);
    matrix.selectCellAtRowColumn(0, 0);
    v.addSubview(matrix);
    MH = S.choices.length * 21 + (S.choices.length - 1) * 5;
  }

  // The buttons and the countdown keep their place at the bottom.
  function button(title, x, key, action) {
    var b = $.NSButton.alloc.initWithFrame($.NSMakeRect(x, 16, 90, 32));
    b.setTitle(title); b.setBezelStyle($.NSBezelStyleRounded);
    if (key) b.setKeyEquivalent(key);
    b.setTarget(app); b.setAction(action);
    v.addSubview(b);
    return b;
  }
  if (S.confirm) {
    // Cancel answers Return as well as Escape: nothing is done unless
    // Apply (or Open, or Forget) itself is pressed.
    button(o.ok, W - P - 84, "", "stopModal");
    button("Cancel", W - P - 84 - 98, "\r", "abortModal");
  } else {
    // OK answers with the choice; Escape, a key with no button of its own
    // to show, answers Cancel whatever is picked.
    button("OK", W - P - 84, "\r", "stopModal");
  }
  var esc = $.NSButton.alloc.initWithFrame($.NSMakeRect(-200, -200, 10, 10));
  esc.setKeyEquivalent("\u001b"); esc.setTarget(app); esc.setAction("abortModal");
  v.addSubview(esc);
  var kind = S.confirm ? "confirm" : "", left = o.limit;
  var clock = field(countdown(left, kind), $.NSFont.monospacedDigitSystemFontOfSizeWeight(12, 0), $.NSColor.secondaryLabelColor);
  clock.setFrame($.NSMakeRect(P, 24, S.confirm ? W - 2 * P - 190 : W - 2 * P - 100, 17));

  // Everything above the buttons, from the top down; the window grows to
  // fit an open box and shrinks back when it is closed, its top edge kept.
  var H = 0;
  function layout() {
    var top = 94, f = [[icon, P, 20, 40, 40], [t1, P + 52, 24, W - 2 * P - 52, 22], [t2, P + 52, 46, W - 2 * P - 52, 22]];
    rows.forEach(function (r) {
      if (r.key) f.push([r.key, KX, top, K, 18]);
      f.push([r.val, KX + K + 2, top, W - P - KX - K - 2, 18]);
      if (r.box) f.push([r.box.tri, P - 3, top + 1, 16, 16]);
      top += 18;
      if (r.box) {
        r.box.view.setHidden(!r.open);
        if (r.open) { top += 6; f.push([r.box.view, KX, top, BW, r.box.h]); top += r.box.h + 2; }
      }
      top += 4;
    });
    if (matrix) { top += 16; f.push([matrix, P + 4, top, W - 2 * P, MH]); H = top + MH + 62; }
    else H = top + 74;
    var c = win.contentRectForFrameRect(win.frame), edge = c.origin.y + c.size.height;
    var fr = win.frameRectForContentRect($.NSMakeRect(c.origin.x, edge - H, W, H));
    if (!win.screen.isNil()) fr = win.constrainFrameRectToScreen(fr, win.screen);
    win.setFrameDisplay(fr, true);
    f.forEach(function (x) { x[0].setFrame($.NSMakeRect(x[1], H - x[2] - x[4], x[3], x[4])); });
    v.setNeedsDisplay(true);
  }
  layout();
  win.center;
  if (o.offscreen) {
    // Ordered in, so it is laid out, drawn and timed as ever, but clear,
    // past the mouse, and nothing brought forward: nobody sees it, and
    // whatever the person at the screen is typing into keeps the keys.
    win.setAlphaValue(0);
    win.setIgnoresMouseEvents(true);
    win.orderFrontRegardless;
  } else {
    win.setLevel($.NSFloatingWindowLevel);
    app.activateIgnoringOtherApps(true);
    win.makeKeyAndOrderFront(null);
  }
  // For the tests: a picture of what it shows, and nothing waited for.
  if (o.snap && !o.snapAfter) { snapshot(win, o.snap); return "cancel"; }

  // The countdown, from a timer in the run loop: once a second it says
  // what is left, and at 0:00 the window closes, as no answer.
  var start = $.NSDate.date, steps = o.selftest ? selftest() : null;
  function elapsed() { return -start.timeIntervalSinceNow; }
  var timer = $.NSTimer.timerWithTimeIntervalRepeatsBlock(0.25, true, function () {
    try {
      var e = elapsed(), l = Math.max(0, o.limit - Math.floor(e));
      if (l !== left) { left = l; clock.setStringValue($(countdown(l, kind))); }
      rows.forEach(function (r) {
        if (r.box && r.box.copiedAt && e - r.box.copiedAt > 1.5) { r.box.copiedAt = 0; r.box.copy.setTitle("copy"); }
      });
      if (o.snapAfter && e >= o.snapAfter) { snapshot(win, o.snap); app.stopModalWithCode(2); return; }
      if (steps && e >= 0.75) { steps(); return; }
      if (l <= 0) app.stopModalWithCode(1);
    } catch (x) {}
  });
  $.NSRunLoop.currentRunLoop.addTimerForMode(timer, $.NSRunLoopCommonModes);
  var how = Number(app.runModalForWindow(win));
  timer.invalidate;
  win.orderOut(null);
  if (how === 1) return "timeout";
  if (how !== Number($.NSModalResponseStop)) return "cancel";
  if (S.confirm) return "apply";
  return S.answers[matrix.selectedRow] || "cancel";

  // The test's steps, one per tick, each on the window as it is.
  function selftest() {
    var out = [], n = 0, saved = savePasteboard(PB), first = rows.filter(function (r) { return r.box; })[0], h0 = 0;
    return function () {
      n++;
      if (n === 1) {
        // The title, selected as a mouse would, then ⌘C as the keyboard
        // sends it: through the application, its menu, the responder chain.
        t1.selectText(null);
        PB.clearContents; PB.setStringForType($("(nothing copied)"), $.NSPasteboardTypeString);
        app.sendEvent($.NSEvent.keyEventWithTypeLocationModifierFlagsTimestampWindowNumberContextCharactersCharactersIgnoringModifiersIsARepeatKeyCode(
          $.NSEventTypeKeyDown, $.NSMakePoint(0, 0), $.NSEventModifierFlagCommand, 0, win.windowNumber, null, "c", "c", false, 8));
      } else if (n === 2) {
        var s = PB.stringForType($.NSPasteboardTypeString);
        out.push("cmd-c=" + (s.isNil() ? "" : s.js));
        restorePasteboard(PB, saved);
        if (!first) { out.push("box=none"); n = 5; return; }
        // The copy button copies into a pasteboard of the test's own: what
        // a box holds may be a secret, and the clipboard is not the test's.
        PB = $.NSPasteboard.pasteboardWithUniqueName;
        h0 = win.frame.size.height;
        first.box.tri.performClick(null);
      } else if (n === 3) {
        out.push("open=" + (first.open ? 1 : 0) + " grew=" + (win.frame.size.height > h0 ? 1 : 0));
        first.box.copy.performClick(null);
      } else if (n === 4) {
        var c = PB.stringForType($.NSPasteboardTypeString);
        out.push("copy=" + (!c.isNil() && c.js === first.box.text ? "same" : "differs") + " title=" + first.box.copy.title.js);
        PB.releaseGlobally;
        first.box.tri.performClick(null);
      } else if (n === 5) {
        out.push("closed=" + (first.open ? 0 : 1) + " back=" + (win.frame.size.height === h0 ? 1 : 0));
      } else {
        $(out.join("\n") + "\n").writeToFileAtomicallyEncodingError(o.selftest, true, 4, null);
        app.stopModalWithCode(2);
      }
    };
  }
}

// What the clipboard holds, every item and every type, to give it back.
function savePasteboard(pb) {
  var out = [], items = pb.pasteboardItems;
  if (!items || items.isNil()) return out;
  for (var i = 0; i < items.count; i++) {
    var it = items.objectAtIndex(i), ts = it.types, d = [];
    for (var j = 0; j < ts.count; j++) {
      var t = ts.objectAtIndex(j), data = it.dataForType(t);
      if (data && !data.isNil()) d.push([t, data]);
    }
    out.push(d);
  }
  return out;
}
function restorePasteboard(pb, saved) {
  pb.clearContents;
  if (!saved.length) return;
  var arr = $.NSMutableArray.array;
  saved.forEach(function (d) {
    var it = $.NSPasteboardItem.alloc.init;
    d.forEach(function (p) { it.setDataForType(p[1], p[0]); });
    arr.addObject(it);
  });
  pb.writeObjects(arr);
}

function snapshot(win, snap) {
  if (!snap) return;
  // Drawn once, as the screen would show it, before it is pictured.
  $.NSRunLoop.currentRunLoop.runUntilDate($.NSDate.dateWithTimeIntervalSinceNow(0.5));
  win.display;
  // A clear window pictures as clear: its views draw themselves instead,
  // the title bar's frame and all.
  if (win.alphaValue < 1) {
    var fv = win.contentView.superview, rep = fv.bitmapImageRepForCachingDisplayInRect(fv.bounds);
    fv.cacheDisplayInRectToBitmapImageRep(fv.bounds, rep);
    rep.representationUsingTypeProperties($.NSBitmapImageFileTypePNG, $()).writeToFileAtomically(snap, true);
    win.orderOut(null);
    return;
  }
  // Its own window, as the window server shows it: a process may always
  // picture its own windows.
  ObjC.import("CoreGraphics");
  var cg = $.CGWindowListCreateImage($.CGRectNull, $.kCGWindowListOptionIncludingWindow,
                                     win.windowNumber, $.kCGWindowImageBoundsIgnoreFraming);
  if (cg) {
    $.NSBitmapImageRep.alloc.initWithCGImage(cg)
      .representationUsingTypeProperties($.NSBitmapImageFileTypePNG, $()).writeToFileAtomically(snap, true);
  }
  win.orderOut(null);
}

if (typeof module !== "undefined" && module.exports) module.exports = { countdown: countdown, options: options };
