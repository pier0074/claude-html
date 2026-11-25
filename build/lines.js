// Reading a transcript a piece of whole lines at a time. One file, read by
// both of the programs that read transcripts, as parse.js is:
//
//   convert.js         loads it with new Function, as it loads parse.js
//   the archiver       has it appended, as parse.js is, by the save
//
//   var L = claudeHtmlLines(JXA ? null : require("fs"), chunk, lineMax);
//   L.readFrom(path, offset[, max[, bare]])  →  { text, bytes, cut } | null
//   L.readLines(path, offset, take)          →  { off, tail, long } | null
//
// Read whole, a transcript of more than 512 MiB was more than a JavaScript
// string can hold: the read failed, and the session was neither built nor
// archived. chunk is how much is read at a time (64 MiB when not given),
// lineMax the longest line read (256 MiB): a line longer still could never
// be parsed, and is passed over and counted.
//
// nfs is node's fs module; without it, osascript's Foundation is used.

function claudeHtmlLines(nfs, chunk, lineMax) {
  "use strict";
  var READ_CHUNK = Math.max(4096, Number(chunk) || 64 << 20);
  var LINE_MAX = Math.max(READ_CHUNK, Number(lineMax) || 256 << 20);

  // A transcript from a byte offset to its end: what was appended since the
  // last read. Also where the last whole line ends, in bytes, which is
  // where the next read will start. The whole lines are decoded apart
  // from what follows them: a last line still being written can end in
  // the middle of a character, which is no reason to refuse the rest (node
  // does not); that unfinished line is no record yet either way. Whole
  // lines that are not UTF-8 are refused, as a whole read refuses them.
  // At most max bytes, when given; bare: no text, and where the first
  // line ends rather than the last.
  var readFrom;
  if (!nfs) {
    var NL = $("\n").dataUsingEncoding(4);
    readFrom = function (path, offset, max, bare) {
      var h = $.NSFileHandle.fileHandleForReadingAtPath(path);
      if (!h || h.isNil()) return null;
      try {
        h.seekToFileOffset(offset);
        var data = max === undefined ? h.readDataToEndOfFile : h.readDataOfLength(max);
        var n = Number(data.length);
        var loc = Number(data.rangeOfDataOptionsRange(NL, 1, $.NSMakeRange(0, n)).location);
        var at = loc < n ? loc + 1 : 0;
        if (bare) {
          loc = Number(data.rangeOfDataOptionsRange(NL, 0, $.NSMakeRange(0, n)).location);
          return { text: null, bytes: n, cut: loc < n ? loc + 1 : 0 };
        }
        var dec = function (from, len) {
          var s = $.NSString.alloc.initWithDataEncoding(data.subdataWithRange($.NSMakeRange(from, len)), 4);
          var t = !s || s.isNil() ? null : s.js;
          return typeof t === "string" ? t : null;
        };
        var head = dec(0, at);
        if (head === null) return null;
        var tail = dec(at, n - at);
        return { text: head + (tail || ""), bytes: n, cut: at };
      } catch (e) { return null; } finally { h.closeFile; }
    };
  } else {
    readFrom = function (path, offset, max, bare) {
      var fd;
      try { fd = nfs.openSync(path, "r"); } catch (e) { return null; }
      try {
        var parts = [], total = 0;
        while (max === undefined || total < max) {
          var buf = Buffer.allocUnsafe(max === undefined ? 8 << 20 : Math.min(8 << 20, max - total));
          var got = nfs.readSync(fd, buf, 0, buf.length, offset + total);
          if (!got) break;
          parts.push(got < buf.length ? buf.subarray(0, got) : buf);
          total += got;
        }
        var all = parts.length === 1 ? parts[0] : Buffer.concat(parts, total);
        // Found in the bytes, not the text: a character cut off by a write
        // in progress decodes to more bytes than it was.
        if (bare) return { text: null, bytes: total, cut: all.indexOf(10) + 1 };
        return { text: all.toString("utf8"), bytes: total, cut: all.lastIndexOf(10) + 1 };
      } catch (e) { return null; } finally { try { nfs.closeSync(fd); } catch (e) {} }
    };
  }

  // A transcript from a byte offset to its end, a piece of whole lines at a
  // time, handed to take(text). A piece is at most READ_CHUNK bytes, or as
  // long as one line longer than that, up to LINE_MAX; a line longer still
  // is passed over. Returns where the whole lines end, the unfinished last
  // line's text, and how many lines were passed over; null when unreadable.
  function readLines(path, off, take) {
    var size = READ_CHUNK, long = 0;
    for (;;) {
      var got = readFrom(path, off, size);
      if (got === null) return null;
      var more = got.bytes >= size;
      if (more && !got.cut) {
        // One line fills the piece. Where it ends is looked for in the
        // bytes, without the text: read again as far as that, or passed
        // over when it is longer than LINE_MAX.
        var end = lineEnd(path, off + got.bytes, off + LINE_MAX);
        if (end === null) return null;
        if (end.at) { size = end.at - off; continue; }
        if (end.eof) { size = end.eof - off + 1; continue; }
        long++;
        end = lineEnd(path, off + LINE_MAX, Infinity);
        if (end === null) return null;
        // Still unfinished: the next read carries on from inside it, and
        // does not count it again.
        if (!end.at) return { off: end.eof, tail: "", long: long };
        off = end.at; size = READ_CHUNK; continue;
      }
      var nl = got.text.lastIndexOf("\n");
      if (nl >= 0) take(got.text.slice(0, nl + 1));
      off += got.cut;
      if (more) { size = READ_CHUNK; continue; }
      return { off: off, tail: got.text.slice(nl + 1), long: long };
    }
  }
  // Just past the first line break from byte from on, if one comes before
  // byte limit: { at }; or { eof }, where the file ends, when none does.
  function lineEnd(path, from, limit) {
    for (;;) {
      var want = Math.min(READ_CHUNK, limit - from);
      if (want <= 0) return { at: 0, eof: 0 };
      var got = readFrom(path, from, want, true);
      if (got === null) return null;
      if (got.cut) return { at: from + got.cut, eof: 0 };
      from += got.bytes;
      if (got.bytes < want) return { at: 0, eof: from };
    }
  }

  return { readFrom: readFrom, readLines: readLines, chunk: READ_CHUNK };
}
