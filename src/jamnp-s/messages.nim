# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## JAMNP-S stream selectors and incremental E4 messages with explicit per-message and stream
## budgets. Parsing does not authenticate a message or grant application/state authority.
##
## A reader exclusively owns its partial payload. feed consumes only the reported input prefix;
## callers retain any suffix and drain takeMessage before feeding again. FIN is accepted only at
## a message boundary after the final completed message has been taken.

import ../codec/bounded

type
  StreamKind* {.pure.} = enum ## Only selectors defined by the pinned protocol are constructible through decodeKind.
    BlockAnnouncement = 0, BlockRequest = 128, StateRequest = 129,
    TicketProxy = 131, TicketDistribution = 132, PackageSubmission = 133,
    PackageSharing = 134, ReportDistribution = 135, ReportRequest = 136,
    ShardDistribution = 137, AuditShardRequest = 138, SegmentShards = 139,
    SegmentShardsWithProof = 140, AssuranceDistribution = 141,
    PreimageAnnouncement = 142, PreimageRequest = 143, AuditAnnouncement = 144,
    JudgmentPublication = 145, BundleSubmission = 146, BundleRequest = 147,
    SegmentRequest = 148
  MessageError* {.pure.} = enum ## Failed/default results contain neither payload nor consumed input count.
    Uninitialized, None, InvalidKind, InvalidPolicy, LimitExceeded, Truncated, NotReady, Closed
  MessageResult*[T] = object ## Private tags prevent forging success or accessing partial results.
    case status: MessageError
    of None: completed: T
    else: discard            # Rejections carry only their reason.
  MessageLimits* = object ## Independent admission ceilings include E4 overhead in the total stream budget.
    messageBytes*, streamBytes*: ByteLimit
    messages*: ElementLimit
  MessageReader* = object ## One mutable parser owns its payload until takeMessage transfers it to the caller.
    limits: MessageLimits
    status: MessageError
    header: array[4, byte]
    headerUsed, payloadUsed: int
    payload: seq[byte]
    chargedBytes, startedMessages: uint64
    complete: bool

# Mutable parser storage must never be shared by a copied enclosing stream owner.
proc `=copy`*(destination: var MessageReader, source: MessageReader) {.error: "MessageReader owns partial input".}
# Duplication has the same lifetime restriction as assignment.
proc `=dup`*(source: MessageReader): MessageReader {.error.}

func error*[T](outcome: MessageResult[T]): MessageError =
  ## Inspect an operation without exposing its private payload.
  outcome.status
func value*[T](outcome: MessageResult[T]): T {.inline, requires: outcome.status ==
    MessageError.None.} =
  ## Access only a successful result's complete value.
  outcome.completed
func error*(reader: MessageReader): MessageError =
  ## Read parser lifecycle without granting access to a partial frame.
  reader.status
func ready*(reader: MessageReader): bool =
  ## Only an active parser with all declared payload bytes has a message to transfer.
  reader.status == MessageError.None and reader.complete

proc decodeKind*(selector: byte): MessageResult[StreamKind] =
  ## Reject reserved gaps and unknown selectors before converting to a sparse enum.
  case selector
  of 0: return MessageResult[StreamKind](status: MessageError.None,
      completed: StreamKind.BlockAnnouncement)
  of 128, 129, 131..148:
    return MessageResult[StreamKind](status: MessageError.None, completed: StreamKind(selector))
  else:
    return MessageResult[StreamKind](status: MessageError.InvalidKind) # No unknown protocol fallback.

proc configure*(reader: var MessageReader, limits: MessageLimits): MessageError =
  ## Reset a private parser from trusted ceilings before receiving any untrusted input.
  # Every message has an E4 header, including empty messages. Keep host conversions checked.
  if uint64(limits.messageBytes) > 0xffffffff'u64 or
      uint64(limits.messageBytes) > uint64(high(int)) or
      uint64(limits.streamBytes) < 4 or uint64(limits.messages) == 0:
    reader = MessageReader(status: MessageError.InvalidPolicy)
    return MessageError.InvalidPolicy
  reader = MessageReader(status: MessageError.None, limits: limits)
  MessageError.None

proc reject(reader: var MessageReader, reason: MessageError): MessageResult[int] =
  ## Poison malformed streams and release their partial payload; no progress escapes on failure.
  reader.status = reason
  reader.payload = @[]
  reader.complete = false
  MessageResult[int](status: reason)

proc feed*(reader: var MessageReader, input: openArray[byte]): MessageResult[int] =
  ## Consume at most one message; the caller must retain and re-feed any unconsumed suffix.
  if reader.status != MessageError.None:
    return MessageResult[int](status: reader.status) # Default, rejected and closed readers cannot receive bytes.
  if reader.complete: return MessageResult[int](status: MessageError.None, completed: 0)
  var consumed = 0
  # A fragmented header requires at most four copied bytes per invocation.
  while reader.headerUsed < 4 and consumed < input.len:
    reader.header[reader.headerUsed] = input[consumed]
    inc reader.headerUsed
    inc consumed
  if reader.headerUsed < 4:
    return MessageResult[int](status: MessageError.None, completed: consumed)
  # Allocate only once, after proving both per-message and whole-stream resource bounds.
  if reader.payloadUsed == 0 and reader.payload.len == 0:
    var claimed = 0'u64
    for i in 0..<4: claimed = claimed or (uint64(reader.header[i]) shl (8*i))
    if claimed > uint64(reader.limits.messageBytes) or claimed > uint64(high(int)):
      return reject(reader, MessageError.LimitExceeded)
    if reader.startedMessages >= uint64(reader.limits.messages):
      return reject(reader, MessageError.LimitExceeded)
    let remaining = uint64(reader.limits.streamBytes) - reader.chargedBytes
    if remaining < 4 or claimed > remaining - 4:
      return reject(reader, MessageError.LimitExceeded)
    reader.chargedBytes += claimed + 4
    inc reader.startedMessages
    reader.payload = newSeq[byte](int(claimed))
  let available = min(input.len - consumed, reader.payload.len - reader.payloadUsed)
  # Source and destination extents are bounded independently before any byte is copied.
  for i in 0..<available: reader.payload[reader.payloadUsed+i] = input[consumed+i]
  reader.payloadUsed += available
  consumed += available
  reader.complete = reader.payloadUsed == reader.payload.len
  MessageResult[int](status: MessageError.None, completed: consumed)

proc takeMessage*(reader: var MessageReader): MessageResult[seq[byte]] =
  ## Transfer a complete payload, retaining only stream-wide resource accounting in the parser.
  if reader.status != MessageError.None:
    return MessageResult[seq[byte]](status: reader.status) # A rejected prefix cannot yield buffered bytes.
  if not reader.complete: return MessageResult[seq[byte]](status: MessageError.NotReady)
  let payload = move(reader.payload)
  reader.headerUsed = 0
  reader.payloadUsed = 0
  reader.complete = false
  MessageResult[seq[byte]](status: MessageError.None, completed: payload)

proc finish*(reader: var MessageReader): MessageError =
  ## Validate received FIN after the caller drains all complete messages.
  if reader.status != MessageError.None: return reader.status
  if reader.complete: return MessageError.NotReady # The host must process the final message before accepting FIN.
  if reader.headerUsed != 0:
    discard reject(reader, MessageError.Truncated)
    return MessageError.Truncated
  reader.status = MessageError.Closed
  MessageError.None

proc encodeMessage*(payload: openArray[byte], maximum: ByteLimit): MessageResult[seq[byte]] =
  ## Encode one E4 message; the stream kind is sent separately once when the stream opens.
  if uint64(payload.len) > uint64(maximum) or uint64(payload.len) > 0xffffffff'u64 or
      payload.len > high(int)-4:
    return MessageResult[seq[byte]](status: MessageError.LimitExceeded)
  var wire = newSeq[byte](payload.len+4)
  # The four-byte length is little endian on every host architecture.
  for i in 0..<4: wire[i] = byte((uint64(payload.len) shr (8*i)) and 255)
  for i in 0..<payload.len: wire[4+i] = payload[i]
  MessageResult[seq[byte]](status: MessageError.None, completed: wire)
