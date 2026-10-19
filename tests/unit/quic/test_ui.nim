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
let index = embeddedIndex("index.html")
assert index >= 0
for verb in ["GET", "HEAD"]:
  var embedded = Connection(input: verb & " / HTTP/1.1\r\nHost: localhost\r\n\r\n")
  embedded.process(-1)
  assert "200 OK" in embedded.output and not embedded.fileOpened
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
var absent = Connection(input: "GET /not-in-bundle HTTP/1.1\r\nHost: localhost\r\n\r\n")
absent.process(-1)
assert "404 Not Found" in absent.output and not absent.embedded

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
  writeFile("ui-static-test/index.html", "hello")
  writeFile("ui-static-test/assets/app.js", "const ready = true;")
  writeFile("ui-static-test-secret", "outside")
except:
  assert false, "Cannot write static test fixtures"
assert posix.symlink("../ui-static-test-secret", "ui-static-test/escape") == 0
assert posix.symlink("assets", "ui-static-test/linked") == 0
var directory = "ui-static-test"
let root = posix.open(directory.toCString(), O_RDONLY or Directory)
assert root >= 0
for path in ["missing", "escape", "linked/app.js"]:
  assert openFile(root, path) < 0

# GET owns a bounded file stream; HEAD sends the same metadata without keeping its descriptor.
var get = Connection(input: "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n")
get.process(root)
assert get.output.startsWith("HTTP/1.1 200 OK\r\n") and "Content-Length: 5\r\n" in get.output
assert get.fileOpened and get.remaining == 5
get.close()
for verb in ["GET", "HEAD"]:
  var head = Connection(input: verb & " /assets/app.js HTTP/1.1\r\nHost: localhost\r\nContent-Length: 0\r\n\r\n")
  head.process(root)
  assert "200 OK" in head.output and "text/javascript" in head.output
  assert head.fileOpened == (verb == "GET")
  head.close()
for target in ["/escape", "/linked/app.js", "/assets", "/missing"]:
  var missing = Connection(input: "GET " & target & " HTTP/1.1\r\nHost: localhost\r\n\r\n")
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
var post = Connection(input: "POST / HTTP/1.1\r\nHost: localhost\r\nContent-Length: 0\r\n\r\n")
post.process(root)
assert "405 Method Not Allowed" in post.output and "Allow: GET, HEAD" in post.output
assert posix.close(root) == 0
# Remove owned fixtures after descriptors retire, preserving repeatable native runs.
assert posix.unlink("ui-static-test/escape") == 0
assert posix.unlink("ui-static-test/linked") == 0
assert posix.unlink("ui-static-test/assets/app.js") == 0
assert posix.unlink("ui-static-test/index.html") == 0
assert posix.unlink("ui-static-test-secret") == 0
assert posix.rmdir("ui-static-test/assets") == 0
assert posix.rmdir("ui-static-test") == 0
echo "UI tests passed"
