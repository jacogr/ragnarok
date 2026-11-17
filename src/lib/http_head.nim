# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Request-owned Balsa HTTP/1 parsing for UI, MCP, management and RPC upgrades.
## A Head owns the foreign parser and its copied headers without sharing a vocabulary.
## Scans resume over an unchanged accumulated unread buffer, stop before body bytes,
## and retain their first failure. Views never escape: accessors copy strings into Nim.
## Library defaults determine syntax and the head limit; only ambiguous body framing
## is disabled through Balsa's public validation policy. Services own all access,
## selector-uniqueness and body-authorization decisions. Reader/Writer owns I/O.
## The library-derived limit includes leading blank lines in our retained wire head:
## Balsa skips these in its own accounting, but Reader keeps them until completion.

type
  NativeHead {.importc: "rq_http_head", header: "http_parser.h", incompleteStruct.} = object
  Head* = object
    ## Exclusive parser owner; default construction allocates nothing until the first scan.
    raw: nil ptr NativeHead

const
  HeadPending* = 0   ## More input is required, or a stream mailbox has not published a head.
  HeadInvalid* = -1  ## Balsa rejected syntax/framing, or parser allocation failed.
  HeadTooLarge* = -2 ## The pinned Balsa default head limit was exceeded.

proc newHead(): nil ptr NativeHead {.importc: "rq_http_head_new", header: "http_parser.h".}
  ## Allocate one independent foreign parser, returning nil on native allocation refusal.

proc freeHead(head: nil ptr NativeHead) {.importc: "rq_http_head_free", header: "http_parser.h".}
  ## Retire the parser and every copied header; nil is harmless.

proc maxHeadBytes*(): csize_t {.importc: "rq_http_max_head_bytes", header: "http_parser.h".}
  ## Query Balsa's default rather than duplicating its limit in application code.

proc scan(head: nil ptr NativeHead, input: pointer, length: csize_t): cint {.
  importc: "rq_http_head_scan", header: "http_parser.h".}
  ## Consume only newly appended bytes and return a sticky status or complete head extent.

proc value(head: nil ptr NativeHead, part: cint, name: pointer, size: csize_t,
  length: ptr csize_t): nil ptr UncheckedArray[char] {.
  importc: "rq_http_head_value", header: "http_parser.h".}
  ## Borrow a parsed first-line component or field only until the owner closes.

proc count(head: nil ptr NativeHead, name: pointer, size: csize_t): csize_t {.
  importc: "rq_http_head_count", header: "http_parser.h".}
  ## Count original field lines case-insensitively, without merging duplicate selectors.

proc nativeContentLength(raw: nil ptr NativeHead): uint64 {.
  importc: "rq_http_head_content_length", header: "http_parser.h".}
  ## Read Balsa's checked unsigned body extent without copying header storage.

proc `=copy`*(destination: var Head, source: Head) {.error.}
  ## The foreign parser cannot have duplicate destruction authority.

proc `=dup`*(source: Head): Head {.error.}
  ## Implicit duplication of native ownership is forbidden.

proc `=destroy`*(head: Head) =
  ## Each parser releases all C++ header storage on every return and error path.
  freeHead(head.raw)

proc `=wasMoved`*(head: var Head) {.nodestroy.} =
  ## Move only cleanup authority; no parser borrow survives a move.
  head.raw = nil

proc close*(head: var Head) =
  ## Release a completed scanner before its task waits for application body authorization.
  freeHead(head.raw)
  head.raw = nil

proc findHeadEnd*(head: var Head, input: openArray[char]): int =
  ## Feed the current unread buffer; append-only input must remain unchanged through completion.
  ## Refuse an incomplete wire head at maxHeadBytes before the caller fills again.
  ## A complete head within that limit may have arbitrarily larger buffered suffix bytes.
  if head.raw == nil:
    head.raw = newHead()
    if head.raw == nil: return HeadInvalid
  let bytes = if input.len == 0: cast[pointer](nil) else: cast[pointer](unsafeAddr input[0])
  int(scan(head.raw, bytes, csize_t(input.len)))

proc parse*(head: var Head, input: string): bool =
  ## Require exactly one complete head; suffix bytes are invalid for this one-shot entry point.
  head.findHeadEnd(toOpenArray(input, 0, input.len-1)) == input.len and input.len > 0

proc copyValue(head: Head, part: cint, name = ""): string =
  ## Copy a short foreign view before exposing it to callers; failed parsers expose no fields.
  var length = csize_t(0)
  let key = if name.len == 0: cast[pointer](nil) else: cast[pointer](name.readRawData)
  let bytes = value(head.raw, part, key, csize_t(name.len), addr length)
  if bytes == nil or length > maxHeadBytes(): return ""
  result = newString(int(length))
  for index in 0..<result.len:
    # The C API view is owned by head and remains valid throughout this copy.
    result[index] = bytes[index]

proc methodOf*(head: Head): string =
  ## Return the parsed request method as an owned value.
  head.copyValue(0)

proc target*(head: Head): string =
  ## Return the parsed request target without application routing or path normalization.
  head.copyValue(1)

proc version*(head: Head): string =
  ## Return the request-line version interpreted by Balsa.
  head.copyValue(2)

proc header*(head: Head, name: string): string =
  ## Return the library's field lookup; callers enforce uniqueness for interpreted selectors.
  head.copyValue(3, name)

proc headerCount*(head: Head, name: string): int =
  ## Count original case-insensitive field occurrences, including empty values.
  if name.len == 0: return 0
  int(count(head.raw, cast[pointer](name.readRawData), csize_t(name.len)))

proc hasHeader*(head: Head, name: string): bool =
  ## Presence is distinct from an empty value or missing Content-Length.
  head.headerCount(name) > 0

proc contentLength*(head: Head): uint64 =
  ## Return the checked unsigned interpretation; absence is observed through hasHeader.
  nativeContentLength(head.raw)
