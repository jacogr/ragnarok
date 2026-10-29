# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Static HTTP path, MIME, framing and descriptor ownership checks without a live peer.
## Provides a Hastur executable with explicit output; temporary files live in its build workdir.

import std/[assertions, syncio]
include ../../../src/ui/server

# Disabled startup must not inspect the directory or own a socket.
var disabled = default(UiServer)
assert disabled.start(0, "missing-static-directory")
disabled.tick()
disabled.close()
disabled.close()
assert not disabled.start(8888, "missing-static-directory")
assert not disabled.opened and not disabled.rootOpened

# Embedded GET/HEAD use compiled bytes without opening any file or directory.
let index = embeddedIndex("index.html.gz")
assert index >= 0
for verb in ["GET", "HEAD"]:
  var embedded = Connection(input: verb & " / HTTP/1.1\r\nHost: localhost\r\nAccept-Encoding: gzip\r\n\r\n")
  embedded.process(-1)
  assert "200 OK" in embedded.output and not embedded.fileOpened
  assert "Content-Encoding: gzip\r\n" in embedded.output
  assert "Vary: Accept-Encoding\r\n" in embedded.output
  assert "Content-Length: " & $EmbeddedData[index].len & "\r\n" in embedded.output
  assert embedded.embedded == (verb == "GET")
  if verb == "GET": # Read successive bounded chunks and compare exact bundled bytes.
    embedded.output = ""
    var body = ""
    while embedded.remaining > 0:
      embedded.readEmbedded()
      assert embedded.output.len <= ChunkBytes
      body.add(embedded.output)
      embedded.output = ""
    assert body == EmbeddedData[index]
  embedded.close()
var absent = Connection(input: "GET /not-in-bundle HTTP/1.1\r\nHost: localhost\r\nAccept-Encoding: gzip\r\n\r\n")
absent.process(-1)
assert "404 Not Found" in absent.output and not absent.embedded

# Gzip-only serving rejects missing/empty/excluded codings and respects explicit wildcard overrides.
for value in ["", "br", "identity", "gzip;q=0", "gzip;q=0.000", "*;q=0", "*;q=1, gzip;q=0",
    "gzip;q=1.001", "gzip;q=-1", "gzip;q=0.0001", "gzip;q=oops", "gzip;level=1",
    "gzip;q=1;q=0", "gzip;q=1, gzip;q=0"]:
  assert not acceptsGzip(value)
  var rejected = Connection(input: "GET / HTTP/1.1\r\nHost: localhost\r\nAccept-Encoding: " &
      value & "\r\n\r\n")
  rejected.process(-1)
  assert "406 Not Acceptable" in rejected.output and not rejected.embedded
  assert "Vary: Accept-Encoding" in rejected.output
var unspecified = Connection(input: "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n")
unspecified.process(-1)
assert "406 Not Acceptable" in unspecified.output
for value in ["gzip", "GZip; Q=1.000", "gzip;q=0.001", "br, gzip", "*", "*;q=0, gzip;q=1",
    "identity;q=1, gzip;q=0.1", "x-gzip"]:
  assert acceptsGzip(value)

# Decode once and reject all traversal representations before touching the filesystem.
for target in ["", "relative", "//etc/passwd", "/../secret", "/%2e%2e/secret",
    "/a/%2E%2E/secret", "/a/./b", "/a//b", "/%00", "/%0a", "/%7f", "/%5csecret",
    "/bad%", "/bad%0", "/bad%gg", "/fragment#x"]:
  assert staticPath(target) == ""
assert staticPath("/") == "index.html"
assert staticPath("/assets/") == "assets/index.html"
assert staticPath("/assets/a%20b.js?v=1") == "assets/a b.js"
assert contentType("APP.JS") == "text/javascript; charset=utf-8"
assert contentType("app.wasm") == "application/wasm"
assert contentType("unknown") == "application/octet-stream"

# Filesystem checks operate on an explicit directory descriptor and reject symlink escapes.
assert posix.mkdir("ui-static-test", Mode(0o700)) == 0
assert posix.mkdir("ui-static-test/assets", Mode(0o700)) == 0
try: # Fixture write failures must fail this suite rather than escape the Nimony boundary.
  writeFile("ui-static-test/index.html.gz", "\x1f\x8b\x08\x00\x00\x00\x00\x00\x02\xff\xcb\x48\xcd\xc9\xc9\x07\x00\x86\xa6\x10\x36\x05\x00\x00\x00")
  writeFile("ui-static-test/assets/app.js.gz", "\x1f\x8b\x08\x00\x00\x00\x00\x00\x02\xff\x4b\xce\xcf\x2b\x2e\x51\x28\x4a\x4d\x4c\xa9\x54\xb0\x55\x28\x29\x2a\x4d\xb5\x06\x00\x9a\xcd\xf3\xf8\x13\x00\x00\x00")
  writeFile("ui-static-test-secret", "outside")
except:
  assert false, "Cannot write static test fixtures"
assert posix.symlink("../ui-static-test-secret", "ui-static-test/escape.gz") == 0
assert posix.symlink("assets", "ui-static-test/linked") == 0
var directory = "ui-static-test"
let root = posix.open(directory.toCString(), O_RDONLY or Directory)
assert root >= 0
for path in ["missing.gz", "escape.gz", "linked/app.js.gz"]:
  assert openFile(root, path) < 0

# GET owns a bounded file stream; HEAD sends the same metadata without keeping its descriptor.
var get = Connection(input: "GET / HTTP/1.1\r\nHost: localhost\r\nAccept-Encoding: gzip\r\n\r\n")
get.process(root)
assert get.output.startsWith("HTTP/1.1 200 OK\r\n") and "Content-Length: 25\r\n" in get.output
assert get.fileOpened and get.remaining == 25
get.close()
for verb in ["GET", "HEAD"]:
  var head = Connection(input: verb & " /assets/app.js HTTP/1.1\r\nHost: localhost\r\nAccept-Encoding: gzip\r\nContent-Length: 0\r\n\r\n")
  head.process(root)
  assert "200 OK" in head.output and "text/javascript" in head.output
  assert head.fileOpened == (verb == "GET")
  head.close()
for target in ["/escape", "/linked/app.js", "/assets", "/missing"]:
  var missing = Connection(input: "GET " & target & " HTTP/1.1\r\nHost: localhost\r\nAccept-Encoding: gzip\r\n\r\n")
  missing.process(root)
  assert "404 Not Found" in missing.output and not missing.fileOpened
for request in ["GET / HTTP/1.1\r\n\r\n", "GET / HTTP/1.1\r\nHost: a\r\nHost: b\r\n\r\n",
    "GET / HTTP/1.1\r\nHost: a\r\nContent-Length: 1\r\n\r\nx",
    "GET / HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\n\r\n",
    "GET / HTTP/1.1\r\nHost: a\x00\r\n\r\n",
    "GET / HTTP/1.1\r\nHost: a\r\r\n\r\n",
    "GET /../secret HTTP/1.1\r\nHost: a\r\n\r\n"]:
  var bad = Connection(input: request)
  bad.process(root)
  assert "400 Bad Request" in bad.output and not bad.fileOpened
var post = Connection(input: "POST / HTTP/1.1\r\nHost: localhost\r\nAccept-Encoding: gzip\r\nContent-Length: 0\r\n\r\n")
post.process(root)
assert "405 Method Not Allowed" in post.output and "Allow: GET, HEAD" in post.output
assert posix.close(root) == 0
# Remove owned fixtures after descriptors retire, preserving repeatable native runs.
assert posix.unlink("ui-static-test/escape.gz") == 0
assert posix.unlink("ui-static-test/linked") == 0
assert posix.unlink("ui-static-test/assets/app.js.gz") == 0
assert posix.unlink("ui-static-test/index.html.gz") == 0
assert posix.unlink("ui-static-test-secret") == 0
assert posix.rmdir("ui-static-test/assets") == 0
assert posix.rmdir("ui-static-test") == 0
echo "UI tests passed"

# Moving the listener also transfers every accepted connection cleanup obligation.
block moved_owner:
  var destination = default(UiServer)
  block:
    var source = default(UiServer)
    source.fd = posix.open("/dev/null", O_RDONLY)
    source.connections[0].fd = posix.open("/dev/null", O_RDONLY)
    assert source.fd >= 0 and source.connections[0].fd >= 0
    source.opened = true
    source.connections[0].opened = true
    source.connections[0].input = "owned request bytes"
    destination = move(source)
    assert not source.opened and not source.connections[0].opened
    source.close()
    # Reusing the source must neither retire the destination nor inherit its request storage.
    assert source.connections[0].input.len == 0
    source.fd = posix.open("/dev/null", O_RDONLY)
    assert source.fd >= 0
    source.opened = true
    source.close()
  # Source destruction has run; both transferred descriptor identities still belong to destination.
  assert fcntl(destination.fd, F_GETFL) >= 0
  assert fcntl(destination.connections[0].fd, F_GETFL) >= 0
  assert destination.connections[0].input == "owned request bytes"
  destination.close()

# The development root and a streaming file also transfer independently of socket ownership.
block moved_files:
  var destination = default(UiServer)
  block:
    var source = default(UiServer)
    source.root = posix.open("/dev/null", O_RDONLY)
    source.connections[0].file = posix.open("/dev/null", O_RDONLY)
    assert source.root >= 0 and source.connections[0].file >= 0
    source.rootOpened = true
    source.connections[0].fileOpened = true
    destination = move(source)
    assert not source.rootOpened and not source.connections[0].fileOpened
    source.close()
  assert fcntl(destination.root, F_GETFL) >= 0
  assert fcntl(destination.connections[0].file, F_GETFL) >= 0
  destination.close()
