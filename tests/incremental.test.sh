#!/bin/bash
# A save reads only what was appended since the last one, and must write
# exactly what a build from nothing writes. The property itself is checked
# in incremental.test.js; this runs it under the engine lib.sh picked:
# osascript on a Mac, with node checked against it, and node elsewhere or
# with CLAUDE_HTML_FORCE_NODE=1, where it can afford many more split points.
#
#   bash tests/incremental.test.sh          add --all for every split point
set -u

. "$(dirname "$0")/lib.sh"

ENGINE=node; [ "$HAVE_OSASCRIPT" = true ] && ENGINE=osascript
node "$(dirname "$0")/incremental.test.js" --engine "$ENGINE" "$@"
