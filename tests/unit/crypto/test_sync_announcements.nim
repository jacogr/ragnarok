# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent UP0 body/framing witnesses preserve peer claims without granting chain trust.
import std/[assertions, syncio]
import ../../../src/quic/announcements
import ../../../src/codec/[bounded, header]

proc `&`(a, b: seq[byte]): seq[byte] =
  ## Test-only literal concatenation keeps wire expectations independent of production encoding.
  result = @[]
  for value in a: result.add(value)
  for value in b: result.add(value)

proc limits(): AnnouncementLimits =
  ## Small explicit ceilings exercise refusal before allocation and ordinary full-header parsing.
  var config = fullHeaderConfig(ByteLimit(4096))
  config.epochSlots = EpochSlots(12)
  AnnouncementLimits(leaves: ElementLimit(4), bytes: ByteLimit(8192), header: config)
proc claim(marker: byte, slot: uint32): AnnouncedBlock =
  ## Independent fixed identity and E4 slot pair; a claimed slot is never a block count.
  result = default(AnnouncedBlock)
  var hash = default(array[32, byte])
  hash[0] = marker
  result.hash = AnnouncedHeaderHash(hash)
  result.slot = HeaderSlot(slot)
proc wireRecord(value: AnnouncedBlock): seq[byte] =
  ## Literal protocol order avoids using the production handshake encoder as its own oracle.
  result = newSeq[byte](36)
  for index in 0..<32: result[index] = array[32, byte](value.hash)[index]
  for index in 0..<4: result[32 + index] = byte((uint32(value.slot) shr (index * 8)) and 255)
proc frame(body: seq[byte]): seq[byte] =
  ## E4 message length is separate from the GP compact leaf count inside a handshake.
  result = newSeq[byte](body.len + 4)
  for index in 0..<4: result[index] = byte((uint64(body.len) shr (index * 8)) and 255)
  for index, value in body: result[index + 4] = value

let policy = limits()
let final = claim(1, 10)
let first = claim(2, 10000)
let fork = claim(3, 10000)
var body = wireRecord(final)
body.add(2)
for value in wireRecord(first): body.add(value)
for value in wireRecord(fork): body.add(value)
let parsed = decodeHandshake(body, policy)
assert parsed.error == AnnouncementError.None
assert parsed.value.finalized == final and parsed.value.leaves == @[first, fork]
assert encodeHandshake(parsed.value, policy).value == body
assert uint32(parsed.value.leaves[0].slot) == 10000 # Two leaves do not imply a height/lag of two.
let empty = AnnouncementHandshake(finalized: final, leaves: @[])
assert encodeHandshake(empty, policy).value == wireRecord(final) & @[0'u8]
for length in 0..<body.len:
  # Every strict prefix must fail instead of publishing a decoded partial handshake.
  assert decodeHandshake(body.toOpenArray(0, length - 1), policy).error != AnnouncementError.None
var trailing = body
trailing.add(0)
assert decodeHandshake(trailing, policy).error == AnnouncementError.Trailing
var invalid = wireRecord(final) & @[128'u8, 0]
assert decodeHandshake(invalid, policy).error == AnnouncementError.InvalidCount
invalid = wireRecord(final) & @[255'u8, 255, 255, 255, 255, 255, 255, 255, 255]
assert decodeHandshake(invalid, policy).error == AnnouncementError.LimitExceeded
invalid = wireRecord(final) & @[2'u8] & wireRecord(first) & wireRecord(first)
assert decodeHandshake(invalid, policy).error == AnnouncementError.DuplicateLeaf
invalid = wireRecord(final) & @[1'u8] & wireRecord(claim(4, 9))
assert decodeHandshake(invalid, policy).error == AnnouncementError.InvalidSlot
assert decodeHandshake(body, default(AnnouncementLimits)).error == AnnouncementError.InvalidPolicy
var smaller = policy
smaller.bytes = ByteLimit(uint64(body.len - 1))
assert decodeHandshake(body, smaller).error == AnnouncementError.LimitExceeded
smaller = policy
smaller.leaves = ElementLimit(1)
assert decodeHandshake(body, smaller).error == AnnouncementError.LimitExceeded

var maximum = policy
maximum.leaves = ElementLimit(64)
var many: seq[AnnouncedBlock] = @[]
for index in 0..<64: many.add(claim(byte(index + 2), uint32(10 + index)))
let encodedMaximum = encodeHandshake(AnnouncementHandshake(finalized: final, leaves: many), maximum)
assert encodedMaximum.error == AnnouncementError.None and decodeHandshake(encodedMaximum.value,
    maximum).value.leaves == many
maximum.leaves = ElementLimit(65)
assert decodeHandshake(body, maximum).error == AnnouncementError.InvalidPolicy
maximum = policy
maximum.header.epochSlots = EpochSlots(0)
assert decodeHandshake(body, maximum).error == AnnouncementError.InvalidPolicy

# A canonical minimal header has two absent markers, author zero, no offenders, and a 96-byte seal.
var headerBytes = newSeq[byte](297)
headerBytes[96] = 7
var announcement = headerBytes & wireRecord(claim(5, 0))
let announced = decodeAnnouncement(announcement, policy)
assert announced.error == AnnouncementError.None and uint32(announced.value.head.slot) == 7
assert announced.value.finalized == claim(5, 0)
# Fixed expected Blake2b-256 computed independently with Python hashlib from the literal header.
assert array[32, byte](announced.value.head.hash) == [207'u8, 185, 216, 37, 144, 166, 200, 214, 223,
    102, 72, 51, 238, 144, 74, 46, 83, 236, 155, 151, 175, 194, 250, 187, 30, 217, 20, 77, 158, 77,
        223, 76]
for length in 0..<announcement.len:
  assert decodeAnnouncement(announcement.toOpenArray(0, length - 1), policy).error !=
      AnnouncementError.None
announcement.add(0)
assert decodeAnnouncement(announcement, policy).error != AnnouncementError.None
announcement = headerBytes & wireRecord(claim(5, 8))
assert decodeAnnouncement(announcement, policy).error == AnnouncementError.InvalidSlot
headerBytes[100] = 2 # The optional epoch marker tag has no permissive third representation.
assert decodeAnnouncement(headerBytes & wireRecord(claim(5, 0)), policy).error ==
    AnnouncementError.InvalidHeader

# Every fragmentation width must stop at exact frame boundaries, preserving the next message.
let framed = frame(body)
for width in 1..framed.len:
  var reader = default(AnnouncementReader)
  assert reader.error == AnnouncementError.Uninitialized
  assert reader.configure(policy.bytes) == AnnouncementError.None
  var cursor = 0
  while cursor < framed.len:
    let count = min(width, reader.remaining)
    assert count > 0 and count <= framed.len - cursor
    assert reader.feed(framed.toOpenArray(cursor, cursor + count - 1)) == AnnouncementError.None
    cursor += count
  assert reader.ready and reader.message.value == body
  assert reader.feed([]) == AnnouncementError.Busy
  assert reader.configure(policy.bytes) == AnnouncementError.Busy
  assert reader.consume() == AnnouncementError.None and reader.remaining == 4
  assert not reader.ready
  # Reuse the same persistent reader for another exact body without requiring stream FIN.
  assert reader.feed(framed.toOpenArray(0, 3)) == AnnouncementError.None
  assert reader.feed(body) == AnnouncementError.None and reader.ready
var reader = default(AnnouncementReader)
assert reader.configure(policy.bytes) == AnnouncementError.None
assert reader.feed([255'u8, 255, 255, 255]) == AnnouncementError.LimitExceeded
assert reader.error == AnnouncementError.LimitExceeded and reader.remaining == 0
assert reader.message.error == AnnouncementError.LimitExceeded
reader = default(AnnouncementReader)
assert reader.configure(policy.bytes) == AnnouncementError.None
assert reader.feed([0'u8, 0, 0, 0]) == AnnouncementError.LimitExceeded
reader = default(AnnouncementReader)
assert reader.configure(policy.bytes) == AnnouncementError.None
assert reader.feed([1'u8, 0, 0, 0, 0]) == AnnouncementError.Trailing

echo "PASS UP0: bounded handshake, announcements, exact hashes, framing and fragmentation"
