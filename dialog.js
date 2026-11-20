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
ObjC.import("Cocoa");

function run(argv) {
  var bash = argv[0] === "bash", project = argv[1] || "", found = argv[2] || "", command = argv[3] || "";
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
  label("Sensitive information detected", bold, P + 52, H - 68, W - 2 * P - 52, 22);
  label("Where:", body, P, H - 112, 52, 18, $.NSColor.secondaryLabelColor);
  label((bash ? "a command from Claude" : "your prompt in Claude Code") +
        (project ? "  ·  project " + project : ""), body, P + 54, H - 112, W - 2 * P - 54, 18);
  label("Found:", body, P, H - 134, 52, 18, $.NSColor.secondaryLabelColor);
  label(found, body, P + 54, H - 134, W - 2 * P - 54, 18);
  if (command) {
    label("Command:", body, P, H - 156, 70, 18, $.NSColor.secondaryLabelColor);
    var c = label(command, $.NSFont.userFixedPitchFontOfSize(12), P + 72, H - 156, W - 2 * P - 72, 18);
    c.cell.setLineBreakMode($.NSLineBreakByTruncatingTail);
    c.setToolTip(command);
  }

  var verb = bash ? "run" : "send";
  var choices = ["Cancel — do not " + verb,
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
  var snap = argv[4] || "";
  if (snap) {
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
    return "cancel";
  }
  var how = app.runModalForWindow(win);
  win.orderOut(null);
  if (how !== $.NSModalResponseStop) return "cancel";
  return ["cancel", "allow", "safe", "stop"][m.selectedRow] || "cancel";
}
