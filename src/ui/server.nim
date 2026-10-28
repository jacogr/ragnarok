# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded static HTTP server with a separate loopback listener, driven by the peer dispatcher.
## UiServer owns eight connections and optional development root/file descriptors; release assets
## are immutable gzip data embedded by the build. Requests must accept gzip; no runtime compression
## or uncompressed fallback is provided. Only GET
## and HEAD are supported; paths cannot traverse parents or follow symlinks. No directory listing.

import std/[nativesocket, oserrors, strutils, monotimes]
import std/posix/posix

# Make generates immutable path/data arrays from the staged UI; no runtime asset files are read.
include ../../build/ui_assets

const
  MaxConnections = 8
  MaxHeader = 4096
  ChunkBytes = 16384

type
  Connection = object ## Each slot owns its socket, optional file and bounded write buffer.
    opened, fileOpened, embedded: bool
    fd, file: cint
    input, output: string
    offset, assetIndex, position: int
    remaining, deadline: int64
  UiServer* = object ## Non-copyable listener and root owner; disabled instances own no descriptors.
    opened, rootOpened: bool
    fd, root: cint
    connections: array[MaxConnections, Connection]

# Synchronous POSIX calls borrow only bounded storage; accepted sockets are always nonblocking.
proc socket(domain, kind, protocol: cint): cint {.importc: "socket", header: "<sys/socket.h>".}
proc bindSocket(fd: cint, address: pointer, size: SockLen): cint {.importc: "bind",
    header: "<sys/socket.h>".}
proc listenSocket(fd, backlog: cint): cint {.importc: "listen", header: "<sys/socket.h>".}
proc acceptSocket(fd: cint, address, size: nil pointer): cint {.importc: "accept",
    header: "<sys/socket.h>".}
proc receive(fd: cint, data: pointer, size: csize_t, flags: cint): int {.importc: "recv",
    header: "<sys/socket.h>".}
proc sendBytes(fd: cint, data: pointer, size: csize_t, flags: cint): int {.importc: "send",
    header: "<sys/socket.h>".}
proc setOption(fd, level, option: cint, value: pointer,
    size: SockLen): cint {.importc: "setsockopt", header: "<sys/socket.h>".}
proc parseAddress(family: cint, text: cstring, output: pointer): cint {.importc: "inet_pton",
    header: "<arpa/inet.h>".}
proc networkPort(port: uint16): uint16 {.importc: "htons", header: "<netinet/in.h>".}
proc openRelative(fd: cint, path: cstring, flags: cint): cint {.importc: "openat",
    header: "<fcntl.h>".}
let
  GetFd {.importc: "F_GETFD", header: "<fcntl.h>".}: cint
  SetFd {.importc: "F_SETFD", header: "<fcntl.h>".}: cint
  CloseExec {.importc: "FD_CLOEXEC", header: "<fcntl.h>".}: cint
  Directory {.importc: "O_DIRECTORY", header: "<fcntl.h>".}: cint
  NoFollow {.importc: "O_NOFOLLOW", header: "<fcntl.h>".}: cint
  OpenCloseExec {.importc: "O_CLOEXEC", header: "<fcntl.h>".}: cint
  SocketLevel {.importc: "SOL_SOCKET", header: "<sys/socket.h>".}: cint
when defined(macosx):
  let NoSigpipe {.importc: "SO_NOSIGPIPE", header: "<sys/socket.h>".}: cint # Prevent process-wide SIGPIPE.
else:
  let NoSignal {.importc: "MSG_NOSIGNAL", header: "<sys/socket.h>".}: cint # Protect each Linux send.

# Copying a composite owner would duplicate root, socket and streaming-file ownership.
proc `=copy`*(destination: var UiServer, source: UiServer) {.error: "UI Server owns descriptors".}
proc `=wasMoved`*(server: var UiServer) {.nodestroy, inline.} =
  ## Disarm transferred fields through their own move hooks; never destroy the destination resources.
  `=wasMoved`(server.opened)
  `=wasMoved`(server.rootOpened)
  `=wasMoved`(server.fd)
  `=wasMoved`(server.root)
  `=wasMoved`(server.connections)

proc `=destroy`*(server: UiServer) =
  ## Retire partial startup, live requests and ARC strings even when explicit close is skipped.
  if server.opened: discard posix.close(server.fd)
  if server.rootOpened: discard posix.close(server.root)
  for slot in server.connections: # File and socket lifetimes belong exclusively to this owner.
    if slot.opened: discard posix.close(slot.fd)
    if slot.fileOpened: discard posix.close(slot.file)
  `=destroy`(server.connections)

# Slot reuse clears all file/socket ownership and response state.
proc close(slot: var Connection) =
  if slot.opened: discard posix.close(slot.fd)
  if slot.fileOpened: discard posix.close(slot.file)
  slot = default(Connection)

proc close*(server: var UiServer) =
  ## Explicit shutdown is idempotent; default instances never close stdin.
  for slot in mitems(server.connections): slot.close() # Retire requests before the directory root.
  if server.opened: discard posix.close(server.fd)
  if server.rootOpened: discard posix.close(server.root)
  server.opened = false
  server.rootOpened = false

# Configure socket ownership flags before accepting or writing any bytes.
proc nonblocking(fd: cint): bool =
  let flags = fcntl(fd, F_GETFL, 0)
  let descriptorFlags = fcntl(fd, GetFd, 0)
  if flags < 0 or descriptorFlags < 0 or fcntl(fd, F_SETFL, flags or O_NONBLOCK) < 0 or
      fcntl(fd, SetFd, descriptorFlags or CloseExec) < 0: return false
  when defined(macosx): # Darwin suppresses SIGPIPE per socket rather than per send.
    var enabled = 1.cint
    if setOption(fd, SocketLevel, NoSigpipe, addr enabled, SockLen(sizeof(enabled))) !=
        0: return false
  true

proc start*(server: var UiServer, port: uint16, directory = ""): bool =
  ## Port zero disables IO. Empty directory serves embedded assets; a development root pins disk files.
  if server.opened or server.rootOpened: return false
  if port == 0: return true
  server.root = -1 # Embedded mode owns no directory descriptor and never depends on the working directory.
  if directory.len > 0: # Development mode uses only this root; missing files never fall back to embedded assets.
    var path = directory
    server.root = posix.open(path.toCString(), O_RDONLY or Directory or OpenCloseExec)
    if server.root < 0: return false
    server.rootOpened = true
  server.fd = socket(cint(ord(nativesocket.AF_INET)), cint(ord(nativesocket.SOCK_STREAM)), 0)
  if server.fd < 0:
    server.close() # Root ownership must also retire on socket creation failure.
    return false
  server.opened = true
  var address = default(Sockaddr_in)
  address.sin_family = TSa_Family(ord(nativesocket.AF_INET))
  address.sin_port = networkPort(port)
  when defined(macosx): # BSD requires an explicit sockaddr length.
    address.sin_len = uint8(sizeof(Sockaddr_in))
  var loopback = "127.0.0.1"
  if not nonblocking(server.fd) or parseAddress(cint(ord(nativesocket.AF_INET)),
      loopback.toCString(), addr address.sin_addr) != 1 or
      bindSocket(server.fd, addr address, SockLen(sizeof(address))) != 0 or
      listenSocket(server.fd, cint(MaxConnections)) != 0:
    server.close() # Requested startup failures cannot silently disable the UI.
    return false
  true

# Decode one bounded request target; reject traversal, controls, backslashes and malformed escapes.
proc staticPath(target: string): string =
  result = ""
  if target.len == 0 or target[0] != '/': return
  var decoded = ""
  var i = 0
  while i < target.len and target[i] != '?': # Query strings select the same static resource.
    var c = target[i]
    if c == '%':
      if target.len - i < 3: return ""
      var value = 0
      for digit in target[i + 1..i + 2]: # Decode exactly two hexadecimal digits without raising.
        value *= 16
        if digit in {'0'..'9'}: value += ord(digit) - ord('0')
        elif digit in {'a'..'f'}: value += ord(digit) - ord('a') + 10
        elif digit in {'A'..'F'}: value += ord(digit) - ord('A') + 10
        else: return ""
      c = char(value)
      i += 2
    if ord(c) < 32 or ord(c) == 127 or c in {'\\', '#'}: return ""
    decoded.add(c)
    inc i
  if decoded.endsWith("/"): decoded.add("index.html") # Directory requests use an explicit index only.
  for part in decoded[1..^1].split('/'):
    if part.len == 0 or part in [".", ".."]: return "" # Reject before opening any component.
  decoded[1..^1]

# Walk descriptor-relative components with O_NOFOLLOW to prevent symlink and rename escapes.
proc openFile(root: cint, path: string): cint =
  var parent = root
  var owned = false
  defer:
    if owned: discard posix.close(parent) # Caller receives only the final file descriptor.
  let parts = path.split('/')
  for i in 0..<parts.len:
    var part = parts[i]
    let flags = O_RDONLY or NoFollow or OpenCloseExec or O_NONBLOCK or
        (if i < parts.len - 1: Directory else: 0.cint)
    let next = openRelative(parent, part.toCString(), flags)
    if next < 0: return -1
    if i == parts.len - 1: return next # Only the validated final component escapes the walk.
    if owned: discard posix.close(parent)
    parent = next
    owned = true
  -1

# Use browser-compatible MIME types for common static assets; unknown files remain binary.
proc contentType(path: string): string =
  let lower = path.toLowerAscii()
  if lower.endsWith(".html"): "text/html; charset=utf-8"
  elif lower.endsWith(".css"): "text/css; charset=utf-8"
  elif lower.endsWith(".js") or lower.endsWith(".mjs"): "text/javascript; charset=utf-8"
  elif lower.endsWith(".json") or lower.endsWith(".map"): "application/json"
  elif lower.endsWith(".svg"): "image/svg+xml"
  elif lower.endsWith(".png"): "image/png"
  elif lower.endsWith(".jpg") or lower.endsWith(".jpeg"): "image/jpeg"
  elif lower.endsWith(".ico"): "image/x-icon"
  elif lower.endsWith(".wasm"): "application/wasm"
  elif lower.endsWith(".woff2"): "font/woff2"
  elif lower.endsWith(".txt"): "text/plain; charset=utf-8"
  else: "application/octet-stream"

# HTTP quality values use integer thousandths, avoiding floats and unchecked numeric parsing.
proc quality(value: string): int =
  if value == "0": return 0
  if value == "1": return 1000
  if value.len < 2 or value.len > 5 or value[0] notin {'0', '1'} or value[1] != '.': return -1
  var resultValue = 0
  var scale = 100
  for i in 2..<value.len: # At most three decimal digits fit the HTTP qvalue grammar.
    if value[i] notin {'0'..'9'} or (value[0] == '1' and value[i] != '0'): return -1
    resultValue += (ord(value[i]) - ord('0')) * scale
    scale = scale div 10
  if value[0] == '1': 1000 else: resultValue

# Explicit gzip exclusion wins over wildcard acceptance; missing/empty headers do not opt in.
proc acceptsGzip(value: string): bool =
  var explicit = -1
  var wildcard = -1
  for item in value.split(','): # The request header budget also bounds this list and its allocations.
    let parts = item.split(';')
    let coding = parts[0].strip().toLowerAscii()
    if coding in ["gzip", "x-gzip", "*"]:
      var weight = 1000
      if parts.len > 1: # Malformed or extra parameters cannot grant compression acceptance.
        weight = 0
        if parts.len == 2:
          let parameter = parts[1].split('=')
          if parameter.len == 2 and parameter[0].strip().toLowerAscii() == "q":
            weight = max(quality(parameter[1].strip()), 0)
      if coding == "*": # Conflicting repeated entries are conservatively combined as exclusions.
        wildcard = if wildcard < 0: weight else: min(wildcard, weight)
      else:
        explicit = if explicit < 0: weight else: min(explicit, weight)
  if explicit >= 0: explicit > 0 else: wildcard > 0

# Every response closes the connection; bounded headers never reflect request data.
proc response(status, kind: string, length: int64, encoded = false): string =
  "HTTP/1.1 " & status & "\r\nContent-Type: " & kind & "\r\nContent-Length: " & $length &
    "\r\nVary: Accept-Encoding\r\n" & (if encoded: "Content-Encoding: gzip\r\n" else: "") &
    "Connection: close\r\nX-Content-Type-Options: nosniff\r\n\r\n"

# Lookup returns an internal manifest index or absence; generated paths are immutable build inputs.
proc embeddedIndex(path: string): int =
  for i in 0..<EmbeddedPaths.len: # Manifest order is deterministic and contains no duplicate paths.
    if EmbeddedPaths[i] == path: return i
  -1

# Copy at most one chunk from immutable program data, avoiding a whole-asset copy per request.
proc readEmbedded(slot: var Connection) =
  let count = int(min(slot.remaining, int64(ChunkBytes)))
  for i in 0..<count: # The manifest length and saved offset bound every access.
    slot.output.add(EmbeddedData[slot.assetIndex][slot.position + i])
  slot.position += count
  slot.remaining -= int64(count)

# Parse only complete, bounded HTTP/1.1 GET/HEAD headers with no body or ambiguous framing.
proc process(slot: var Connection, root: cint) =
  let ending = slot.input.find("\r\n\r\n")
  if ending < 0:
    if slot.input.len >= MaxHeader: slot.close() # Partial headers cannot retain a slot indefinitely.
    return
  slot.output = response("400 Bad Request", "text/plain", 0)
  if ending + 4 > MaxHeader: return
  let lines = slot.input[0..<ending].split("\r\n")
  let request = lines[0].split(' ')
  if request.len != 3 or request[2] != "HTTP/1.1": return
  var seen: seq[string] = @[]
  var host = false
  var encoding = ""
  for i in 1..<lines.len: # Duplicate, folded and control-bearing fields are rejected consistently.
    let colon = lines[i].find(':')
    if colon < 1: return
    let name = lines[i][0..<colon].toLowerAscii()
    for c in name:
      if c notin {'a'..'z', '0'..'9', '!', '#', '$', '%', '&', '\'', '*', '+', '-', '.', '^', '_',
          '`', '|', '~'}: return
    if name in seen: return
    seen.add(name)
    let value = lines[i][colon + 1..^1].strip()
    for c in lines[i][colon + 1..^1]: # Check raw values before trimming optional whitespace.
      if (ord(c) < 32 and c != '\t') or ord(c) == 127: return
    if name == "transfer-encoding" or (name == "content-length" and value != "0"):
      return # Permit the standard empty-body header without accepting request bodies.
    if name == "host": host = value.len > 0
    if name == "accept-encoding": encoding = value
  if not host: return
  if request[0] notin ["GET", "HEAD"]:
    slot.output = "HTTP/1.1 405 Method Not Allowed\r\nAllow: GET, HEAD\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
    return
  let path = staticPath(request[1])
  if path.len == 0: return
  if not acceptsGzip(encoding): # This server offers gzip only, without an identity fallback.
    slot.output = response("406 Not Acceptable", "text/plain", 0)
    return
  if root < 0: # Release serving reads embedded constants directly; no extraction or filesystem fallback.
    let index = embeddedIndex(path & ".gz")
    if index < 0:
      slot.output = response("404 Not Found", "text/plain", 0)
      return
    let length = EmbeddedData[index].len
    slot.output = response("200 OK", contentType(path), int64(length), true)
    if request[0] == "GET" and length > 0: # HEAD and empty assets need only their metadata response.
      slot.embedded = true
      slot.assetIndex = index
      slot.position = 0
      slot.remaining = int64(length)
    slot.input = ""
    return
  let file = openFile(root, path & ".gz")
  if file < 0:
    slot.output = response("404 Not Found", "text/plain", 0)
    return
  var stat = default(Stat)
  if fstat(file, stat) != 0 or not S_ISREG(stat.st_mode) or stat.st_size < 0:
    discard posix.close(file) # FIFOs, sockets, devices and directories never become response streams.
    slot.output = response("404 Not Found", "text/plain", 0)
    return
  slot.output = response("200 OK", contentType(path), int64(stat.st_size), true)
  if request[0] == "HEAD" or stat.st_size == 0:
    discard posix.close(file) # HEAD preserves metadata while sending no file bytes.
  else:
    slot.file = file
    slot.fileOpened = true
    slot.remaining = int64(stat.st_size) # Growth is ignored; truncation terminates the incomplete response.
  slot.input = ""

proc tick*(server: var UiServer) =
  ## One admission, bounded header read, one file chunk and one socket write per slot per turn.
  if not server.opened: return
  let now = getMonoTime().ticks div 1_000_000
  let accepted = acceptSocket(server.fd, nil, nil)
  if accepted >= 0: # Capacity pressure rejects only the newly accepted socket.
    var free = -1
    for i in 0..<MaxConnections:
      if not server.connections[i].opened:
        free = i
        break
    if free < 0 or not nonblocking(accepted): discard posix.close(accepted)
    else:
      server.connections[free] = Connection(opened: true, fd: accepted, deadline: now + 5000)
  for slot in mitems(server.connections): # Fixed capacity and buffers bound each dispatcher's work.
    if slot.opened and now >= slot.deadline: slot.close()
    if slot.opened and slot.output.len == 0 and not slot.fileOpened and not slot.embedded:
      var bytes = default(array[MaxHeader, char])
      let count = receive(slot.fd, addr bytes[0], csize_t(MaxHeader - slot.input.len), 0)
      if count > 0:
        for i in 0..<count: slot.input.add(bytes[i]) # Copy only initialized bytes.
        slot.process(server.root)
      elif count == 0: slot.close()
      elif osLastError() notin [OSErrorCode(EAGAIN), OSErrorCode(EWOULDBLOCK), OSErrorCode(
          EINTR)]: slot.close()
    if slot.opened and slot.output.len == 0 and slot.embedded:
      slot.readEmbedded() # Static data uses the same bounded write buffer and partial-send handling.
    if slot.opened and slot.output.len == 0 and slot.fileOpened:
      var bytes = default(array[ChunkBytes, char])
      let count = posix.read(slot.file, addr bytes[0], int(min(slot.remaining, int64(ChunkBytes))))
      if count > 0:
        for i in 0..<count: slot.output.add(bytes[i]) # Buffer at most one fixed-size chunk.
        slot.remaining -= count
      elif count == 0 or osLastError() != OSErrorCode(EINTR): slot.close()
    if slot.opened and slot.output.len > 0:
      var flags = 0.cint
      when not defined(macosx): flags = NoSignal # Avoid a process-wide signal policy.
      let bytes = slot.output.toCString()
      let sent = sendBytes(slot.fd, cast[pointer](cast[uint](bytes) + uint(slot.offset)),
          csize_t(slot.output.len - slot.offset), flags)
      if sent > 0:
        slot.offset += sent
        if slot.offset == slot.output.len:
          slot.output = ""; slot.offset = 0
          if (not slot.fileOpened and not slot.embedded) or slot.remaining == 0: slot.close() # Last response byte retires both owners.
      elif sent == 0 or osLastError() notin [OSErrorCode(EAGAIN), OSErrorCode(EWOULDBLOCK),
          OSErrorCode(EINTR)]: slot.close()
