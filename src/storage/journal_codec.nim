# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exact checksummed revision frames support bounded append-only physical node journals.
## Framing is local integrity; selected roots still require independent caller trust.
import ./[node_records, record_codec, node_repository]
import ../codec/bounded
import ../crypto/primitives

type
  FrameError* {.pure.} = enum ## Only complete frames expose transport metadata or bytes.
    Uninitialized, None, InvalidFormat, LimitExceeded, ChecksumMismatch, InvalidRecords, BackendFailure
  JournalFrame* = object ## Detached untrusted transport payload; repository admission remains separate.
    generation*: RepositoryGeneration
    batch*: TrieExport
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
proc encodeJournalFrame*(generation: RepositoryGeneration, batch: TrieExport,
    limits: RecordLimits, limit: ByteLimit): FrameResult[seq[byte]] =
  ## Bound the inner codec before hashing/allocation, then checksum length, generation and body.
  if uint64(generation) == 0: return FrameResult[seq[byte]](status: FrameError.InvalidFormat)
  let maximum = min(uint64(limit), uint64(high(int)))
  if maximum < 48: return FrameResult[seq[byte]](status: FrameError.LimitExceeded)
  var bounded = limits
  bounded.encoded = ByteLimit(min(uint64(limits.encoded), maximum-48))
  let body = encodeTrieExport(batch, bounded)
  if body.error == RecordError.LimitExceeded: return FrameResult[seq[byte]](
      status: FrameError.LimitExceeded)
  if body.error != RecordError.None:
    return FrameResult[seq[byte]](status: FrameError.InvalidRecords, recordReason: body.error)
  let bytes = body.value
  var output = newSeq[byte](bytes.len+48) # The narrowed inner ceiling proved the addition and allocation.
  putNumber(output, 0, uint64(bytes.len))
  putNumber(output, 8, uint64(generation))
  for i, octet in bytes: output[16+i] = octet
  let hashed = blake2b256(output.toOpenArray(0, output.len-33))
  if hashed.error != CryptoError.None: return FrameResult[seq[byte]](
      status: FrameError.BackendFailure)
  let checksum = array[32, byte](hashed.value)
  for i in 0..<32: output[output.len-32+i] = checksum[i]
  FrameResult[seq[byte]](status: FrameError.None, completed: output)
proc decodeJournalFrame*(input: openArray[byte], limits: RecordLimits,
    limit: ByteLimit): FrameResult[JournalFrame] =
  ## Require exact frame consumption and checksum before decoding any physical records.
  let extent = journalFrameExtent(input, limit)
  if extent.error != FrameError.None: return FrameResult[JournalFrame](status: extent.error)
  if extent.value != input.len or number(input, 0) == 0 or number(input, 8) == 0:
    return FrameResult[JournalFrame](status: FrameError.InvalidFormat)
  if number(input, 0) > uint64(limits.encoded):
    return FrameResult[JournalFrame](status: FrameError.LimitExceeded) # Bound inner bytes before hashing the checksum prefix.
  let hashed = blake2b256(input.toOpenArray(0, input.len-33))
  if hashed.error != CryptoError.None: return FrameResult[JournalFrame](
      status: FrameError.BackendFailure)
  let checksum = array[32, byte](hashed.value)
  for i in 0..<32:
    if input[input.len-32+i] != checksum[i]: return FrameResult[JournalFrame](
        status: FrameError.ChecksumMismatch)
  let decoded = decodeTrieExport(input.toOpenArray(16, input.len-33), limits)
  if decoded.error == RecordError.LimitExceeded: return FrameResult[JournalFrame](
      status: FrameError.LimitExceeded)
  if decoded.error != RecordError.None:
    return FrameResult[JournalFrame](status: FrameError.InvalidRecords, recordReason: decoded.error)
  FrameResult[JournalFrame](status: FrameError.None,
    completed: JournalFrame(generation: RepositoryGeneration(number(input, 8)),
        batch: decoded.value))
