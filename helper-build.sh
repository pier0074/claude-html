#!/bin/bash
# Build the delete helper: a small app that receives claude-html:// links.
#
#   helper-build.sh "<path>/Claude HTML.app"              build it
#   helper-build.sh "<path>/Claude HTML.app" --register   and tell macOS about it
#   helper-build.sh "<path>/Claude HTML.app" --if-stale   only if the source is newer
#
# Everything here is Apple's own: osacompile makes the app from
# helper.applescript, PlistBuddy declares the link it handles, codesign signs
# it locally, and lsregister makes LaunchServices route the links to it.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$1"; shift
REGISTER=0; IFSTALE=0
for a in "$@"; do
  case "$a" in --register) REGISTER=1 ;; --if-stale) IFSTALE=1 ;; esac
done

# The app carries a copy of the script inside it, so editing the source does
# nothing until it is built again — which is exactly how the delete links kept
# working while a new kind of link did nothing at all.
if [ "$IFSTALE" = 1 ] && [ -f "$APP/Contents/Resources/Scripts/main.scpt" ] &&
   [ ! "$HERE/helper.applescript" -nt "$APP/Contents/Resources/Scripts/main.scpt" ]; then
  exit 0
fi

PB=/usr/libexec/PlistBuddy
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

rm -rf "$APP"
osacompile -o "$APP" "$HERE/helper.applescript"

PL="$APP/Contents/Info.plist"
$PB -c "Set :CFBundleIdentifier local.claude-html.helper" "$PL" 2>/dev/null ||
  $PB -c "Add :CFBundleIdentifier string local.claude-html.helper" "$PL"
$PB -c "Delete :CFBundleURLTypes" "$PL" 2>/dev/null || true
$PB -c "Add :CFBundleURLTypes array" \
    -c "Add :CFBundleURLTypes:0 dict" \
    -c "Add :CFBundleURLTypes:0:CFBundleURLName string claude-html" \
    -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes array" \
    -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string claude-html" "$PL"

# Editing Info.plist breaks the signature osacompile gave the app, and an app
# with a broken signature is refused on Apple silicon. Sign it again, ad hoc:
# this Mac made it, so no developer identity is involved.
codesign --force --sign - "$APP" >/dev/null 2>&1

if [ "$REGISTER" = 1 ] && [ -x "$LSREG" ]; then
  "$LSREG" -f "$APP"
fi
exit 0
