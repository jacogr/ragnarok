# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exact checksummed revision frames support bounded append-only physical node journals.
## Framing is local integrity; selected roots still require independent caller trust.
import ./[node_records, record_codec, node_repository]
import ../codec/bounded
import ../crypto/primitives

type
  FrameError* {.pure.} = enum ## Only complete frames expose transport metadata or bytes.
    Uninitialized, None, InvalidFormat, LimitExceeded, ChecksumMismatch, InvalidRecords,
      BackendFailure, InvalidRevision
  JournalFrame* = object ## Detached untrusted transport payload; repository admission remains separate.
    generation*: RepositoryGeneration
    batch*: TrieExport
    context*: seq[byte] # Full-state schema binds bounded application context under the same frame checksum.
  JournalReplay* = object ## A completely admitted frame selects an immutable revision and detached context only.
    view*: RepositoryView
    context*: seq[byte]
  FrameResult*[T] = object ## Guarded private alternatives retain the selected nested codec cause.
    case status: FrameError
    of None: completed: T
    of InvalidRecords: recordReason: RecordError
    else: discard
func error*[T](outcome: FrameResult[T]): FrameError =
  ## Read the selected outer reason alone.
  outcome.status
func value*[T](outcome: FrameResult[T]): T {.inline, requires: outcome.status == FrameError.None.} =
  ## Extract only a complete checked frame or byte buffer.
  outcome.completed
func recordError*[T](outcome: FrameResult[T]): RecordError {.requires: outcome.status ==
    FrameError.InvalidRecords.} =
  ## Access only the selected inner physical-record refusal.
  outcome.recordReason
func number(input: openArray[byte], offset: int): uint64 =
  ## Internal callers prove the complete eight-byte little-endian field.
  result = 0
  for i in 0..<8: result = result or (uint64(input[offset+i]) shl (8*i))
proc putNumber(output: var seq[byte], offset: int, value: uint64) =
  ## Exact extent preflight precedes fixed numeric field writes.
  for i in 0..<8: output[offset+i] = byte((value shr (8*i)) and 255)
proc journalFrameExtent*(input: openArray[byte], limit: ByteLimit): FrameResult[int] =
  ## Return the first complete frame extent without parsing later frames or trusting its content.
  if input.len < 48: return FrameResult[int](status: FrameError.InvalidFormat)
  let maximum = min(uint64(limit), uint64(high(int)))
  if maximum < 48: return FrameResult[int](status: FrameError.LimitExceeded)
  let size = number(input, 0)
  if size > maximum-48: return FrameResult[int](status: FrameError.LimitExceeded)
  let extent = size+48
  if extent > uint64(input.len): return FrameResult[int](status: FrameError.InvalidFormat)
  FrameResult[int](status: FrameError.None, completed: int(extent))
proc encodeFrame(generation: RepositoryGeneration, batch: TrieExport,
    context: openArray[byte], contextual: bool, contextLimit: ByteLimit,
    limits: RecordLimits, limit: ByteLimit): FrameResult[seq[byte]] =
  ## Bound the inner codec before hashing/allocation, then checksum length, generation and body.
  if uint64(generation) == 0: return FrameResult[seq[byte]](status: FrameError.InvalidFormat)
  let maximum = min(uint64(limit), uint64(high(int)))
  let overhead = if contextual: 56'u64 else: 48'u64
  if uint64(context.len) > uint64(contextLimit) or maximum < overhead or
      uint64(context.len) > maximum-overhead:
    return FrameResult[seq[byte]](status: FrameError.LimitExceeded)
  let prefix = int(overhead-32)+context.len
  var bounded = limits
  bounded.encoded = ByteLimit(min(uint64(limits.encoded), maximum-overhead-uint64(context.len)))
  let body = encodeTrieExport(batch, bounded)
  if body.error == RecordError.LimitExceeded: return FrameResult[seq[byte]](
      status: FrameError.LimitExceeded)
  if body.error != RecordError.None:
    return FrameResult[seq[byte]](status: FrameError.InvalidRecords, recordReason: body.error)
  let bytes = body.value
  var output = newSeq[byte](bytes.len+prefix+32) # The narrowed inner ceiling proved the addition and allocation.
  putNumber(output, 0, uint64(bytes.len+prefix-16))
  putNumber(output, 8, uint64(generation))
  if contextual:
    putNumber(output, 16, uint64(context.len))
    for i, octet in context: output[24+i] = octet # Context bytes share the exact generation/root integrity boundary.
  for i, octet in bytes: output[prefix+i] = octet
  let hashed = blake2b256(output.toOpenArray(0, output.len-33))
  if hashed.error != CryptoError.None: return FrameResult[seq[byte]](
      status: FrameError.BackendFailure)
  let checksum = array[32, byte](hashed.value)
  for i in 0..<32: output[output.len-32+i] = checksum[i]
  FrameResult[seq[byte]](status: FrameError.None, completed: output)
proc inspectFrame(input: openArray[byte], contextual: bool, contextLimit: ByteLimit,
    encoded: ByteLimit, limit: ByteLimit): FrameResult[int] =
  ## Verify exact outer consumption, bounded context/body and checksum before exposing the body offset.
  let extent = journalFrameExtent(input, limit)
  if extent.error != FrameError.None: return FrameResult[int](status: extent.error)
  if extent.value != input.len or number(input, 0) == 0 or number(input, 8) == 0:
    return FrameResult[int](status: FrameError.InvalidFormat)
  var prefix = 16
  if contextual:
    if input.len < 56: return FrameResult[int](status: FrameError.InvalidFormat)
    let length = number(input, 16)
    if length > uint64(contextLimit): return FrameResult[int](
        status: FrameError.LimitExceeded)
    if length > uint64(input.len-56): return FrameResult[int](
        status: FrameError.InvalidFormat)
    prefix = 24+int(length) # Subtraction proved conversion, offset addition and complete context extent.
  if uint64(input.len-prefix-32) > uint64(encoded):
    return FrameResult[int](status: FrameError.LimitExceeded) # Bound inner bytes before hashing the checksum prefix.
  let hashed = blake2b256(input.toOpenArray(0, input.len-33))
  if hashed.error != CryptoError.None: return FrameResult[int](
      status: FrameError.BackendFailure)
  let checksum = array[32, byte](hashed.value)
  for i in 0..<32:
    if input[input.len-32+i] != checksum[i]: return FrameResult[int](
        status: FrameError.ChecksumMismatch)
  FrameResult[int](status: FrameError.None, completed: prefix)
proc decodeFrame(input: openArray[byte], contextual: bool, contextLimit: ByteLimit,
    limits: RecordLimits, limit: ByteLimit): FrameResult[JournalFrame] =
  ## Detached frame decoding retains independent record validation for mutable transport callers.
  let inspected = inspectFrame(input, contextual, contextLimit, limits.encoded, limit)
  if inspected.error != FrameError.None: return FrameResult[JournalFrame](status: inspected.error)
  let prefix = inspected.value
  let decoded = decodeTrieExport(input.toOpenArray(prefix, input.len-33), limits)
  if decoded.error == RecordError.LimitExceeded: return FrameResult[JournalFrame](
      status: FrameError.LimitExceeded)
  if decoded.error != RecordError.None:
    return FrameResult[JournalFrame](status: FrameError.InvalidRecords, recordReason: decoded.error)
  var context: seq[byte] = @[]
  if contextual:
    context = newSeq[byte](prefix-24)
    for i in 0..<context.len: context[i] = input[24+i] # Never return a mutable borrow into caller bytes.
  FrameResult[JournalFrame](status: FrameError.None,
    completed: JournalFrame(generation: RepositoryGeneration(number(input, 8)),
        batch: decoded.value, context: context))

proc encodeJournalFrame*(generation: RepositoryGeneration, batch: TrieExport,
    limits: RecordLimits, limit: ByteLimit): FrameResult[seq[byte]] =
  ## Preserve the existing node-only physical schema byte for byte.
  encodeFrame(generation, batch, [], false, ByteLimit(0), limits, limit)
proc decodeJournalFrame*(input: openArray[byte], limits: RecordLimits,
    limit: ByteLimit): FrameResult[JournalFrame] =
  ## Node-only framing never guesses or falls back to contextual frames.
  decodeFrame(input, false, ByteLimit(0), limits, limit)
proc encodeContextJournalFrame*(generation: RepositoryGeneration, batch: TrieExport,
    context: openArray[byte], contextLimit: ByteLimit,
    limits: RecordLimits, limit: ByteLimit): FrameResult[seq[byte]] =
  ## Bind bounded application context and changed nodes to one generation and synchronization boundary.
  encodeFrame(generation, batch, context, true, contextLimit, limits, limit)
proc decodeContextJournalFrame*(input: openArray[byte], contextLimit: ByteLimit,
    limits: RecordLimits, limit: ByteLimit): FrameResult[JournalFrame] =
  ## Explicit contextual schema checks context extents before hashing or allocating any transport bytes.
  decodeFrame(input, true, contextLimit, limits, limit)

proc replayFrame(repository: var NodeRepository, expected: RepositoryView,
    input: openArray[byte], contextual: bool, contextLimit: ByteLimit,
    limit: ByteLimit): FrameResult[JournalReplay] =
  ## Privately fuse checked framing with atomic serialized admission; no mutable decoded transport escapes.
  if not expected.initialized:
    return FrameResult[JournalReplay](status: FrameError.InvalidRevision)
  let inspected = inspectFrame(input, contextual, contextLimit,
    expected.repositoryLimits.codec.encoded, limit)
  if inspected.error != FrameError.None: return FrameResult[JournalReplay](status: inspected.error)
  if uint64(expected.generation) == high(uint64) or
      number(input, 8) != uint64(expected.generation)+1:
    return FrameResult[JournalReplay](status: FrameError.InvalidRevision)
  let prefix = inspected.value
  var context: seq[byte] = @[]
  if contextual:
    context = newSeq[byte](prefix-24)
    for index in 0..<context.len:
      context[index] = input[24+index] # Allocate detached context before the single successful publication point.
  let admitted = repository.publishEncoded(expected, input.toOpenArray(prefix, input.len-33))
  if admitted.error == RepositoryError.InvalidRecords:
    # Preserve existing frame codec diagnostic distinctions for untrusted serialized records.
    if admitted.recordError == RecordError.LimitExceeded:
      return FrameResult[JournalReplay](status: FrameError.LimitExceeded)
    return FrameResult[JournalReplay](status: FrameError.InvalidRecords,
      recordReason: admitted.recordError)
  if admitted.error != RepositoryError.None:
    return FrameResult[JournalReplay](status: FrameError.InvalidRevision)
  FrameResult[JournalReplay](status: FrameError.None,
    completed: JournalReplay(view: admitted.value, context: context))

proc replayJournalFrame*(repository: var NodeRepository, expected: RepositoryView,
    input: openArray[byte], limit: ByteLimit): FrameResult[JournalReplay] =
  ## Admit exactly one contiguous node-only frame under the live repository policy; failed replay is atomic.
  replayFrame(repository, expected, input, false, ByteLimit(0), limit)
proc replayContextJournalFrame*(repository: var NodeRepository, expected: RepositoryView,
    input: openArray[byte], contextLimit: ByteLimit, limit: ByteLimit): FrameResult[JournalReplay] =
  ## Explicit contextual replay owns returned context independently; it provides no chain/checkpoint authority.
  replayFrame(repository, expected, input, true, contextLimit, limit)
