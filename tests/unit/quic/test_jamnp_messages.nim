# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exercise independently specified E4 bytes, all selectors, fragmentation, concatenated messages,
## stream-wide budgets and FIN. Framing acceptance alone never establishes protocol authentication.

import std/[assertions, syncio]
import "../../../src/jamnp-s/messages"
import ../../../src/codec/bounded

# Small admission budgets make every limit and header boundary observable.
const Limits = MessageLimits(messageBytes: ByteLimit(256), streamBytes: ByteLimit(1024),
    messages: ElementLimit(3))

proc selectors() =
  ## Every octet is either a pinned stream kind or a rejected reserved/unknown value.
  for selector in 0..255:
    let parsed = decodeKind(byte(selector))
    let known = selector == 0 or selector in 128..129 or selector in 131..148
    assert (parsed.error == MessageError.None) == known
    if known: assert byte(parsed.value) == byte(selector)

proc fragments() =
  ## Independently written E4 messages include an empty payload and an embedded zero octet.
  let wire = @[3'u8, 0, 0, 0, 7, 0, 9, 0, 0, 0, 0, 1, 0, 0, 0, 255]
  for width in 1..wire.len:
    var reader = default(MessageReader)
    assert reader.configure(Limits) == MessageError.None
    var cursor = 0
    var seen = 0
    # Fragment at each chunk width; unconsumed input remains at the caller's cursor.
    while cursor < wire.len:
      let offered = min(width, wire.len-cursor)
      let fed = reader.feed(wire.toOpenArray(cursor, cursor+offered-1))
      assert fed.error == MessageError.None
      assert fed.value > 0 and fed.value <= offered
      cursor += fed.value
      if reader.ready:
        # Bytes after the first message remain unconsumed even when offered in the same chunk.
        let duplicate = reader.feed([41'u8])
        assert duplicate.error == MessageError.None and duplicate.value == 0
        let taken = reader.takeMessage()
        assert taken.error == MessageError.None
        case seen
        of 0: assert taken.value == @[7'u8, 0, 9]
        of 1: assert taken.value.len == 0
        of 2: assert taken.value == @[255'u8]
        else: assert false # No extra message can be synthesized by a fragment boundary.
        inc seen
    assert seen == 3
    assert reader.finish() == MessageError.None
    assert reader.feed([]).error == MessageError.Closed
    assert reader.takeMessage().error == MessageError.Closed

proc truncation() =
  ## Every strict nonempty prefix of a single message fails FIN; an empty stream is a clean boundary.
  let wire = @[3'u8, 0, 0, 0, 7, 0, 9]
  for length in 0..<wire.len:
    var reader = default(MessageReader)
    assert reader.configure(Limits) == MessageError.None
    assert reader.feed(wire.toOpenArray(0, length-1)).error == MessageError.None
    assert not reader.ready
    assert reader.takeMessage().error == MessageError.NotReady
    if length == 0:
      assert reader.finish() == MessageError.None
    else:
      assert reader.finish() == MessageError.Truncated
      assert reader.takeMessage().error == MessageError.Truncated
  var reader = default(MessageReader)
  assert reader.configure(Limits) == MessageError.None
  assert reader.feed(wire).value == wire.len
  assert reader.finish() == MessageError.NotReady
  assert reader.takeMessage().value == @[7'u8, 0, 9]
  assert reader.finish() == MessageError.None

proc budgets() =
  ## Reject untrusted E4 and aggregate limits before a payload allocation or completed message escapes.
  var reader = default(MessageReader)
  assert reader.error == MessageError.Uninitialized
  assert reader.feed([]).error == MessageError.Uninitialized
  assert reader.configure(Limits) == MessageError.None
  assert reader.feed([255'u8, 255, 255, 255]).error == MessageError.LimitExceeded
  assert not reader.ready
  assert reader.takeMessage().error == MessageError.LimitExceeded
  # Reconfiguration is explicit trusted host work, never an automatic malformed-input recovery.
  assert reader.configure(MessageLimits(messageBytes: ByteLimit(0), streamBytes: ByteLimit(12),
      messages: ElementLimit(2))) == MessageError.None
  for message in 0..<2:
    assert reader.feed([0'u8, 0, 0, 0]).value == 4
    assert reader.takeMessage().value.len == 0
  assert reader.feed([0'u8, 0, 0, 0]).error == MessageError.LimitExceeded
  assert reader.configure(MessageLimits(messageBytes: ByteLimit(8), streamBytes: ByteLimit(7),
      messages: ElementLimit(10))) == MessageError.None
  assert reader.feed([4'u8, 0, 0, 0]).error == MessageError.LimitExceeded
  assert reader.configure(MessageLimits(messageBytes: ByteLimit(0x100000000'u64),
      streamBytes: ByteLimit(32), messages: ElementLimit(1))) == MessageError.InvalidPolicy
  assert reader.configure(MessageLimits(messageBytes: ByteLimit(1), streamBytes: ByteLimit(3),
      messages: ElementLimit(1))) == MessageError.InvalidPolicy
  assert reader.configure(MessageLimits(messageBytes: ByteLimit(1), streamBytes: ByteLimit(8),
      messages: ElementLimit(0))) == MessageError.InvalidPolicy

proc encoding() =
  ## Expected length octets are independent of the decoder and include a multi-byte E4 length.
  assert encodeMessage([], ByteLimit(0)).value == @[0'u8, 0, 0, 0]
  assert encodeMessage([7'u8, 0, 9], ByteLimit(3)).value == @[3'u8, 0, 0, 0, 7, 0, 9]
  assert encodeMessage([7'u8], ByteLimit(0)).error == MessageError.LimitExceeded
  var payload = newSeq[byte](256)
  for i in 0..<payload.len: payload[i] = byte(i)
  let encoded = encodeMessage(payload, ByteLimit(256))
  assert encoded.error == MessageError.None
  let wire = encoded.value
  assert wire.len == 260
  assert wire[0] == 0 and wire[1] == 1 and wire[2] == 0 and wire[3] == 0
  for i in 0..<payload.len: assert wire[4+i] == byte(i)

selectors()
fragments()
truncation()
budgets()
encoding()
let empty = default(MessageResult[int])
assert empty.error == MessageError.Uninitialized
echo "JAMNP-S: selectors, incremental E4 messages, budgets and FIN passed"
