// The guard's question, on macOS: a window of its own, four choices as
// radio buttons with the first, Cancel, picked already, and one button,
// OK. Return is OK, Escape is Cancel. The time limit is the caller's: it
// closes this from outside, which counts as no answer.
//
//   osascript -l JavaScript dialog.js prompt|bash <project> <found> [<command>] [<png>]
//
// <command> is the first line of the command, already masked, shown so
// the answer is about something seen. With <png>, for the tests only: a
// picture of the window is written there and it closes at once, waiting
// for nothing.
//
// Prints cancel, allow, safe or stop. Its own window, brought forward as
// its own: nothing is sent to another application, and no permission is
// asked for. <found> names the kinds of secret, never one.
//
// The same window stops a prompt by a limit rule or the API budget, its
// rows and last two choices given (limits.sh writes them):
//
//   … dialog.js limits <head> <key1> <value1> <key2> <value2> <choice3> <choice4> [<png>]
//
// and prints cancel, allow, until or stop. And it asks before the
// limits are changed from the Token usage page, Cancel the default:
//
//   … dialog.js confirm <title> <subtitle> <rows: key<TAB>value per line> [<png>]
//
// which prints apply or cancel.
ObjC.import("Cocoa");

function run(argv) {
  if (argv[0] === "confirm") return confirmWindow(argv);
  var lim = argv[0] === "limits";
  if (lim) argv = ["prompt", "", "", "", argv[8] || ""].concat([argv]);
  var bash = argv[0] === "bash", project = argv[1] || "", found = argv[2] || "", command = argv[3] || "";
  var L = lim ? argv[5] : null;
  var app = $.NSApplication.sharedApplication;
  app.setActivationPolicy($.NSApplicationActivationPolicyRegular);

  var W = 500, H = command ? 340 : 316, P = 24;
  // Titled, without a close button: an answer is one of the four.
  var win = $.NSWindow.alloc.initWithContentRectStyleMaskBackingDefer($.NSMakeRect(0, 0, W, H),
    $.NSWindowStyleMaskTitled, $.NSBackingStoreBuffered, false);
  win.setTitle("claude-html");
  var v = win.contentView;
  function label(text, font, x, y, w, h, color) {
    var t = $.NSTextField.alloc.initWithFrame($.NSMakeRect(x, y, w, h));
    t.setStringValue(text); t.setFont(font); t.setBezeled(false); t.setDrawsBackground(false);
    t.setEditable(false); t.setSelectable(false);
    if (color) t.setTextColor(color);
    v.addSubview(t);
    return t;
  }
  var body = $.NSFont.systemFontOfSize(13), bold = $.NSFont.boldSystemFontOfSize(15);
  var icon = $.NSImageView.alloc.initWithFrame($.NSMakeRect(P, H - 68, 40, 40));
  icon.setImage($.NSImage.imageNamed("NSCaution"));
  v.addSubview(icon);
  label(bash ? "Claude's command has been interrupted" : "Your prompt has been interrupted",
        bold, P + 52, H - 46, W - 2 * P - 52, 22);
  label(L ? L[1] : "Sensitive information detected", bold, P + 52, H - 68, W - 2 * P - 52, 22);
  // The key column: the guard's width, wider only for a longer key.
  var K = 52;
  if (L) [L[2], L[4]].forEach(function (k) {
    var w = $(k).sizeWithAttributes($({ NSFont: body })).width + 6;
    if (w > K) K = Math.ceil(w);
  });
  label(L ? L[2] : "Where:", body, P, H - 112, K, 18, $.NSColor.secondaryLabelColor);
  label(L ? L[3] : (bash ? "a command from Claude" : "your prompt in Claude Code") +
        (project ? "  ·  project " + project : ""), body, P + K + 2, H - 112, W - 2 * P - K - 2, 18);
  label(L ? L[4] : "Found:", body, P, H - 134, K, 18, $.NSColor.secondaryLabelColor);
  label(L ? L[5] : found, body, P + K + 2, H - 134, W - 2 * P - K - 2, 18);
  if (command) {
    label("Command:", body, P, H - 156, 70, 18, $.NSColor.secondaryLabelColor);
    var c = label(command, $.NSFont.userFixedPitchFontOfSize(12), P + 72, H - 156, W - 2 * P - 72, 18);
    c.cell.setLineBreakMode($.NSLineBreakByTruncatingTail);
    c.setToolTip(command);
  }

  var verb = bash ? "run" : "send";
  var choices = L ? ["Cancel — do not send", "Allow once — send this prompt only", L[6], L[7]]
    : ["Cancel — do not " + verb,
       "Allow once — it is sensitive, " + verb + " it this time only",
       "Safe — it is not sensitive, " + verb + " it and never ask again",
       "Stop — turn this check off"];
  var cell = $.NSButtonCell.alloc.init;
  cell.setButtonType($.NSButtonTypeRadio); cell.setTitle("x"); cell.setFont(body);
  // One radio group: picking one unpicks the others.
  var m = $.NSMatrix.alloc.initWithFrameModePrototypeNumberOfRowsNumberOfColumns(
    $.NSMakeRect(P + 4, 62, W - 2 * P, 100), $.NSRadioModeMatrix, cell, choices.length, 1);
  m.setCellSize($.NSMakeSize(W - 2 * P, 21)); m.setIntercellSpacing($.NSMakeSize(0, 5));
  for (var i = 0; i < choices.length; i++) m.cellAtRowColumn(i, 0).setTitle(choices[i]);
  m.selectCellAtRowColumn(0, 0);
  v.addSubview(m);

  // OK answers with the choice; Escape, a key with no button of its own
  // to show, answers Cancel whatever is picked.
  var ok = $.NSButton.alloc.initWithFrame($.NSMakeRect(W - P - 84, 16, 90, 32));
  ok.setTitle("OK"); ok.setBezelStyle($.NSBezelStyleRounded); ok.setKeyEquivalent("\r");
  ok.setTarget(app); ok.setAction("stopModal");
  v.addSubview(ok);
  var esc = $.NSButton.alloc.initWithFrame($.NSMakeRect(-200, -200, 10, 10));
  esc.setKeyEquivalent("\u001b"); esc.setTarget(app); esc.setAction("abortModal");
  v.addSubview(esc);

  win.center;
  win.setLevel($.NSFloatingWindowLevel);
  app.activateIgnoringOtherApps(true);
  win.makeKeyAndOrderFront(null);
  // For the tests: a picture of what it shows, from its own window, and
  // nothing waited for.
  if (snapshot(app, win, argv[4] || "")) return "cancel";
  var how = app.runModalForWindow(win);
  win.orderOut(null);
  if (how !== $.NSModalResponseStop) return "cancel";
  return (L ? ["cancel", "allow", "until", "stop"] : ["cancel", "allow", "safe", "stop"])[m.selectedRow] || "cancel";
}

function snapshot(app, win, snap) {
  if (!snap) return false;
  // Drawn once, as the screen would show it, before it is pictured.
  $.NSRunLoop.currentRunLoop.runUntilDate($.NSDate.dateWithTimeIntervalSinceNow(0.5));
  win.display;
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
  return true;
}

// The question before the limits are changed from a page: what will be
// written, key by key, and two buttons, Cancel the default. Return and
// Escape both cancel; only a click on Apply applies.
function confirmWindow(argv) {
  var title = argv[1] || "", sub = argv[2] || "", rows = String(argv[3] || "").split("\n").filter(Boolean)
    .map(function (l) { var i = l.indexOf("\t"); return i < 0 ? ["", l] : [l.slice(0, i), l.slice(i + 1)]; });
  var app = $.NSApplication.sharedApplication;
  app.setActivationPolicy($.NSApplicationActivationPolicyRegular);
  var body = $.NSFont.systemFontOfSize(13), bold = $.NSFont.boldSystemFontOfSize(15);
  var K = 52;
  rows.forEach(function (r) {
    var w = $(r[0]).sizeWithAttributes($({ NSFont: body })).width + 10;
    if (w > K) K = Math.ceil(w);
  });
  var W = 500, P = 24, H = 112 + rows.length * 22 + 56;
  var win = $.NSWindow.alloc.initWithContentRectStyleMaskBackingDefer($.NSMakeRect(0, 0, W, H),
    $.NSWindowStyleMaskTitled, $.NSBackingStoreBuffered, false);
  win.setTitle("claude-html");
  var v = win.contentView;
  function label(text, font, x, y, w, h, color) {
    var t = $.NSTextField.alloc.initWithFrame($.NSMakeRect(x, y, w, h));
    t.setStringValue(text); t.setFont(font); t.setBezeled(false); t.setDrawsBackground(false);
    t.setEditable(false); t.setSelectable(false);
    t.cell.setLineBreakMode($.NSLineBreakByTruncatingTail);
    if (color) t.setTextColor(color);
    v.addSubview(t);
  }
  var icon = $.NSImageView.alloc.initWithFrame($.NSMakeRect(P, H - 68, 40, 40));
  icon.setImage($.NSImage.imageNamed("NSCaution"));
  v.addSubview(icon);
  label(title, bold, P + 52, H - 46, W - 2 * P - 52, 22);
  label(sub, body, P + 52, H - 68, W - 2 * P - 52, 22, $.NSColor.secondaryLabelColor);
  rows.forEach(function (r, i) {
    var y = H - 112 - i * 22;
    if (r[0]) label(r[0], body, P, y, K, 18, $.NSColor.secondaryLabelColor);
    label(r[1], body, P + K + 2, y, W - 2 * P - K - 2, 18);
  });
  // Cancel answers Return as well as Escape: nothing is written unless
  // Apply itself is pressed.
  var apply = $.NSButton.alloc.initWithFrame($.NSMakeRect(W - P - 84, 16, 90, 32));
  apply.setTitle("Apply"); apply.setBezelStyle($.NSBezelStyleRounded);
  apply.setTarget(app); apply.setAction("stopModal");
  v.addSubview(apply);
  var cancel = $.NSButton.alloc.initWithFrame($.NSMakeRect(W - P - 84 - 98, 16, 90, 32));
  cancel.setTitle("Cancel"); cancel.setBezelStyle($.NSBezelStyleRounded); cancel.setKeyEquivalent("\r");
  cancel.setTarget(app); cancel.setAction("abortModal");
  v.addSubview(cancel);
  var esc = $.NSButton.alloc.initWithFrame($.NSMakeRect(-200, -200, 10, 10));
  esc.setKeyEquivalent("\u001b"); esc.setTarget(app); esc.setAction("abortModal");
  v.addSubview(esc);
  win.center;
  win.setLevel($.NSFloatingWindowLevel);
  app.activateIgnoringOtherApps(true);
  win.makeKeyAndOrderFront(null);
  if (snapshot(app, win, argv[4] || "")) return "cancel";
  var how = app.runModalForWindow(win);
  win.orderOut(null);
  return how === $.NSModalResponseStop ? "apply" : "cancel";
}
