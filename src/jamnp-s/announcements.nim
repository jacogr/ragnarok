# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded JAMNP-S UP0 messages. Authenticated sources still advertise untrusted hash/slot
## claims: decoding grants neither canonical adoption nor finalized/full/light state authority.

import ../codec/[assurances, bounded, header, natural]
import ../crypto/primitives

type
  AnnouncedHeaderHash* = distinct array[32, byte] ## Remote sealed-header claim, never a state root or validated block certificate.
  AnnouncedBlock* = object ## A copied peer claim, distinct from a validated BlockSnapshot.
    hash*: AnnouncedHeaderHash
    slot*: HeaderSlot
  AnnouncementLimits* = object ## Explicit local resource policy, independent of peer claims.
    leaves*: ElementLimit
    bytes*: ByteLimit
    header*: HeaderConfig
  AnnouncementHandshake* = object ## Finality is the peer's claim; leaves may represent competing forks.
    finalized*: AnnouncedBlock
    leaves*: seq[AnnouncedBlock]
  BlockAnnouncement* = object ## Structurally decoded header and its exact hash confer no consensus validity.
    head*: AnnouncedBlock
    finalized*: AnnouncedBlock
    header*: OwnedHeader
  AnnouncementError* {.pure.} = enum ## Defaults and failures publish no message or partial extent.
    Uninitialized, None, InvalidPolicy, Truncated, InvalidCount, LimitExceeded, Trailing,
    DuplicateLeaf, InvalidSlot, InvalidHeader, HashFailure, InvalidStream, Busy
  AnnouncementResult*[T] = object ## Successful payload access requires selecting the private status.
    case status: AnnouncementError
    of None: completed: T
    else: discard                 # A rejected prefix cannot masquerade as a successful handshake.

func error*[T](outcome: AnnouncementResult[T]): AnnouncementError =
  ## Observe status without granting a successful payload.
  outcome.status
func value*[T](outcome: AnnouncementResult[T]): T {.inline,
    requires: outcome.status == AnnouncementError.None.} =
  ## Return only the complete checked message, never a partially decoded prefix.
  outcome.completed
proc valid*(limits: AnnouncementLimits): bool =
  ## Hard caps bound allocation and callback work even if local configuration is malformed.
  uint64(limits.leaves) > 0 and uint64(limits.leaves) <= 64 and
    uint64(limits.bytes) >= 37 and uint64(limits.bytes) <= 1048576 and
    uint64(limits.header.maxBytes) > 0 and uint64(limits.header.maxBytes) <= 1048540 and
    uint64(limits.header.epochSlots) > 0 and assurances.validConfig(AssuranceConfig(
      cores: limits.header.cores, validators: limits.header.authorValidators))
func `==`*(a, b: AnnouncedHeaderHash): bool =
  ## Equality compares all claimed identity bytes without granting canonical authority.
  array[32, byte](a) == array[32, byte](b)
func `==`*(a, b: AnnouncedBlock): bool =
  ## Target identity requires both exact sealed-header hash and JAM slot.
  a.hash == b.hash and uint32(a.slot) == uint32(b.slot)
proc readBlock(input: openArray[byte], offset: int): AnnouncedBlock =
  ## Callers prove a complete 36-byte record before borrowing any fixed field.
  result = default(AnnouncedBlock)
  var hash = default(array[32, byte])
  for index in 0..<32: hash[index] = input[offset + index]
  result.hash = AnnouncedHeaderHash(hash)
  var slot = 0'u32
  for index in 0..<4: slot = slot or (uint32(input[offset + 32 + index]) shl (8 * index))
  result.slot = HeaderSlot(slot)
proc writeBlock(output: var seq[byte], value: AnnouncedBlock) =
  ## Encode a local copied claim only after the complete message size was admitted.
  for octet in array[32, byte](value.hash): output.add(octet)
  for index in 0..<4: output.add(byte((uint32(value.slot) shr (8 * index)) and 255))
proc decodeHandshake*(input: openArray[byte], limits: AnnouncementLimits):
    AnnouncementResult[AnnouncementHandshake] =
  ## Decode an exact UP0 handshake body; message E4 framing is handled by the stream reader.
  if not limits.valid: return AnnouncementResult[AnnouncementHandshake](
      status: AnnouncementError.InvalidPolicy)
  if uint64(input.len) > uint64(limits.bytes):
    return AnnouncementResult[AnnouncementHandshake](status: AnnouncementError.LimitExceeded)
  if input.len < 37: return AnnouncementResult[AnnouncementHandshake](
      status: AnnouncementError.Truncated)
  let count = natural.decode(input.toOpenArray(36, input.len - 1))
  if not count.ok: return AnnouncementResult[AnnouncementHandshake](
      status: AnnouncementError.InvalidCount)
  let amount = uint64(count.value)
  if amount > uint64(limits.leaves):
    return AnnouncementResult[AnnouncementHandshake](status: AnnouncementError.LimitExceeded)
  let start = 36 + int(count.consumed)
  let available = input.len - start
  if amount > uint64(available div 36):
    return AnnouncementResult[AnnouncementHandshake](status: AnnouncementError.Truncated)
  if amount * 36 != uint64(available):
    return AnnouncementResult[AnnouncementHandshake](status: AnnouncementError.Trailing)
  let finalized = readBlock(input, 0)
  var leaves: seq[AnnouncedBlock] = @[]
  for index in 0..<int(amount):
    # The admitted count and exact remaining extent prove every fixed-record borrow.
    let leaf = readBlock(input, start + index * 36)
    if uint32(leaf.slot) < uint32(finalized.slot):
      return AnnouncementResult[AnnouncementHandshake](status: AnnouncementError.InvalidSlot)
    for previous in leaves:
      if previous.hash == leaf.hash:
        return AnnouncementResult[AnnouncementHandshake](status: AnnouncementError.DuplicateLeaf)
    leaves.add(leaf)
  AnnouncementResult[AnnouncementHandshake](status: AnnouncementError.None,
    completed: AnnouncementHandshake(finalized: finalized, leaves: leaves))
proc encodeHandshake*(message: AnnouncementHandshake, limits: AnnouncementLimits):
    AnnouncementResult[seq[byte]] =
  ## Encode the canonical GP compact leaf count, validating the same bounds as the decoder.
  if not limits.valid: return AnnouncementResult[seq[byte]](status: AnnouncementError.InvalidPolicy)
  if uint64(message.leaves.len) > uint64(limits.leaves):
    return AnnouncementResult[seq[byte]](status: AnnouncementError.LimitExceeded)
  let count = natural.encode(JamNatural(uint64(message.leaves.len)))
  let size = 36 + int(count.len) + message.leaves.len * 36
  if uint64(size) > uint64(limits.bytes):
    return AnnouncementResult[seq[byte]](status: AnnouncementError.LimitExceeded)
  var output: seq[byte] = @[]
  output.writeBlock(message.finalized)
  for index in 0..<count.len: output.add(count.bytes[index])
  for leaf in message.leaves: output.writeBlock(leaf)
  let checked = decodeHandshake(output, limits)
  if checked.error != AnnouncementError.None:
    return AnnouncementResult[seq[byte]](status: checked.error)
  AnnouncementResult[seq[byte]](status: AnnouncementError.None, completed: output)
proc decodeAnnouncement*(input: openArray[byte], limits: AnnouncementLimits):
    AnnouncementResult[BlockAnnouncement] =
  ## Decode one complete header plus Final; do not adopt the block or trust the finality claim.
  if not limits.valid: return AnnouncementResult[BlockAnnouncement](
      status: AnnouncementError.InvalidPolicy)
  if uint64(input.len) > uint64(limits.bytes):
    return AnnouncementResult[BlockAnnouncement](status: AnnouncementError.LimitExceeded)
  if input.len <= 36: return AnnouncementResult[BlockAnnouncement](
      status: AnnouncementError.Truncated)
  let extent = input.len - 36
  let decoded = decodeHeader(input.toOpenArray(0, extent - 1), limits.header)
  if decoded.error != HeaderError.None:
    return AnnouncementResult[BlockAnnouncement](status: AnnouncementError.InvalidHeader)
  if decoded.value.consumed != extent:
    return AnnouncementResult[BlockAnnouncement](status: AnnouncementError.Trailing)
  let info = decoded.value.owner.headerInfo
  if info.error != HeaderError.None:
    return AnnouncementResult[BlockAnnouncement](status: AnnouncementError.InvalidHeader)
  let finalized = readBlock(input, extent)
  if uint32(info.value.unsigned.slot) < uint32(finalized.slot):
    return AnnouncementResult[BlockAnnouncement](status: AnnouncementError.InvalidSlot)
  var hash = default(array[32, byte])
  if blake2b256(input.toOpenArray(0, extent - 1), hash) != CryptoError.None:
    return AnnouncementResult[BlockAnnouncement](status: AnnouncementError.HashFailure)
  AnnouncementResult[BlockAnnouncement](status: AnnouncementError.None,
    completed: BlockAnnouncement(head: AnnouncedBlock(hash: AnnouncedHeaderHash(hash),
        slot: info.value.unsigned.slot),
      finalized: finalized, header: decoded.value.owner))

proc encodeAnnouncement*(owner: OwnedHeader, finalized: AnnouncedBlock,
    limits: AnnouncementLimits): AnnouncementResult[seq[byte]] =
  ## Serialize only an owned structural header; caller retains responsibility for actual validity.
  if not limits.valid: return AnnouncementResult[seq[byte]](status: AnnouncementError.InvalidPolicy)
  let info = owner.headerInfo
  if info.error != HeaderError.None:
    return AnnouncementResult[seq[byte]](status: AnnouncementError.InvalidHeader)
  let size = info.value.consumed
  if size < 0 or uint64(size) > uint64(limits.bytes) - 36:
    return AnnouncementResult[seq[byte]](status: AnnouncementError.LimitExceeded)
  var output = newSeq[byte](size)
  let encoded = owner.encodeOwnedHeader(output)
  if encoded.error != HeaderError.None:
    return AnnouncementResult[seq[byte]](status: AnnouncementError.InvalidHeader)
  output.writeBlock(finalized)
  let checked = decodeAnnouncement(output, limits)
  if checked.error != AnnouncementError.None:
    return AnnouncementResult[seq[byte]](status: checked.error)
  AnnouncementResult[seq[byte]](status: AnnouncementError.None, completed: output)

type AnnouncementReader* = object ## One bounded persistent-stream message; no native callback pointer escapes.
  framing: array[4, byte]
  prefix, expected: int
  body: seq[byte]
  maximum: int
  failure: AnnouncementError
  configured, complete: bool

proc configure*(reader: var AnnouncementReader, maximum: ByteLimit): AnnouncementError =
  ## Start a fresh stream incarnation; a pending/ready message cannot be silently discarded.
  if reader.configured: return AnnouncementError.Busy
  if uint64(maximum) < 37 or uint64(maximum) > 1048576: return AnnouncementError.InvalidPolicy
  reader = AnnouncementReader(maximum: int(uint64(maximum)), configured: true,
    failure: AnnouncementError.None)
  AnnouncementError.None
func error*(reader: AnnouncementReader): AnnouncementError =
  ## A default reader is uninitialized, not an empty successful stream.
  if reader.configured: reader.failure else: AnnouncementError.Uninitialized
func ready*(reader: AnnouncementReader): bool =
  ## Complete framing is required before a handshake or announcement decoder can inspect its body.
  reader.configured and reader.failure == AnnouncementError.None and reader.complete
func remaining*(reader: AnnouncementReader): int =
  ## Native reads must stop at this exact frame boundary, leaving coalesced messages in QUIC storage.
  if not reader.configured or reader.failure != AnnouncementError.None or reader.complete: return 0
  if reader.prefix < 4: 4 - reader.prefix else: reader.expected - reader.body.len
proc feed*(reader: var AnnouncementReader, input: openArray[byte]): AnnouncementError =
  ## Copy at most one proven remaining extent; invalid lengths latch failure until stream retirement.
  if reader.error != AnnouncementError.None: return reader.error
  if reader.complete: return AnnouncementError.Busy
  if input.len > reader.remaining:
    reader.failure = AnnouncementError.Trailing
    return reader.failure
  if reader.prefix < 4:
    for value in input:
      reader.framing[reader.prefix] = value
      inc reader.prefix
    if reader.prefix == 4:
      # The full E4 is assembled in uint64 before any host-size cast or body allocation.
      var size = 0'u64
      for index in 0..<4: size = size or (uint64(reader.framing[index]) shl (8 * index))
      if size == 0 or size > uint64(reader.maximum):
        reader.failure = AnnouncementError.LimitExceeded
        return reader.failure
      reader.expected = int(size)
  else:
    for value in input: reader.body.add(value)
    reader.complete = reader.body.len == reader.expected
  reader.failure
proc message*(reader: AnnouncementReader): AnnouncementResult[seq[byte]] =
  ## Return an owned copy of one bounded message only after its complete extent is available.
  if reader.error != AnnouncementError.None:
    return AnnouncementResult[seq[byte]](status: reader.error)
  if not reader.ready: return AnnouncementResult[seq[byte]](status: AnnouncementError.Truncated)
  AnnouncementResult[seq[byte]](status: AnnouncementError.None, completed: reader.body)
proc consume*(reader: var AnnouncementReader): AnnouncementError =
  ## Acknowledge an exact complete body while retaining the admitted per-stream resource ceiling.
  if not reader.ready: return AnnouncementError.Busy
  reader.prefix = 0
  reader.expected = 0
  reader.body = @[]
  reader.complete = false
  AnnouncementError.None
