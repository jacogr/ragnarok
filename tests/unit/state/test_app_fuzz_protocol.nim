# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Fuzzer-v1 owner, exact boundary, UTF-8, compact-state and transport refusals retain no partial values.
import std/assertions
import std/syncio
import ../../support/app_fuzz_protocol_context
import ../../../src/state/fuzz_protocol as state_fuzz_protocol
import ../../../src/state/store as state_store
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/codec/natural as codec_natural
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/header as codec_header
proc main() =
  ## Independently authored byte cases cover every discriminant without pretending to execute a JAM campaign.
  let limits = fuzzProtocolTestLimits()
  let missing = default(FuzzMessage)
  let absent = default(FuzzResult[FuzzMessage])
  assert absent.error == FuzzError.Uninitialized
  assert missing.fuzzInfo.error == FuzzError.InvalidOwner
  assert missing.fuzzState.error == FuzzError.InvalidOwner
  assert missing.copyFuzzMessage(limits.bytes).error == FuzzError.InvalidOwner
  assert missing.encodeFuzzFrame(limits.bytes).error == FuzzError.InvalidOwner
  let peer = FuzzPeer(protocol: 1, features: 3, jam: FuzzVersion(major: 0, minor: 8, patch: 0),
      app: FuzzVersion(major: 1, minor: 2, patch: 3), name: "Ragnarok")
  let made = newFuzzPeer(peer, limits)
  assert made.error == FuzzError.None
  let message = made.value
  let expected = @[0'u8, 1, 3, 0, 0, 0, 0, 8, 0, 1, 2, 3, 8, 82, 97, 103, 110, 97, 114, 111, 107]
  assert message.copyFuzzMessage(limits.bytes).value == expected
  assert message.fuzzInfo.value.kind == FuzzKind.PeerInfo
  assert message.fuzzPeer.value.features == 3
  assert message.fuzzHeader.error == FuzzError.WrongKind
  assert message.fuzzRequestedHeader.error == FuzzError.WrongKind
  var exact = limits
  exact.bytes = ByteLimit(expected.len)
  assert newFuzzPeer(peer, exact).error == FuzzError.None
  exact.bytes = ByteLimit(expected.len-1)
  assert newFuzzPeer(peer, exact).error == FuzzError.LimitExceeded
  var detached = message.fuzzPeer.value
  detached.name[0] = 'X'
  assert message.fuzzPeer.value.name == "Ragnarok"
  for length in 0..<expected.len:
    let truncated = if length == 0: decodeFuzzMessage([], limits) else: decodeFuzzMessage(
        expected.toOpenArray(0, length-1), limits)
    assert truncated.error != FuzzError.None # Every incomplete message fails before ownership.
  var input = expected
  let captured = decodeFuzzMessage(input, limits).value
  for index in 0..<input.len: input[index] = 0 # Input mutation cannot alter retained identity or wire.
  var output = captured.copyFuzzMessage(limits.bytes).value
  output[0] = 255
  assert captured.copyFuzzMessage(limits.bytes).value == expected
  var extra = expected
  extra.add(0)
  assert decodeFuzzMessage(extra, limits).error == FuzzError.TrailingBytes
  assert decodeFuzzMessage(@[6'u8], limits).error == FuzzError.InvalidTag
  assert decodeFuzzMessage(@[255'u8, 1, 255], limits).error == FuzzError.InvalidText
  assert decodeFuzzMessage(@[255'u8, 128, 0], limits).error == FuzzError.NonCanonical
  assert decodeFuzzMessage(@[1'u8], limits).error == FuzzError.HeaderFailure
  assert decodeFuzzMessage(@[3'u8], limits).error == FuzzError.BlockFailure
  var root = newSeq[byte](33)
  root[0] = 2
  assert decodeFuzzMessage(root, limits).value.fuzzRoot.error == FuzzError.None
  root[0] = 4
  assert decodeFuzzMessage(root, limits).value.fuzzRequestedHeader.error == FuzzError.None
  assert decodeFuzzMessage(root, limits).value.fuzzRoot.error == FuzzError.WrongKind
  let text = newFuzzError("no", limits).value
  assert text.copyFuzzMessage(limits.bytes).value == @[255'u8, 2, 110, 111]
  assert text.fuzzText.value == "no"
  let empty = decodeFuzzMessage(@[5'u8, 0], limits)
  assert empty.error == FuzzError.None
  assert empty.value.fuzzState.value.commitment.entries == 0
  assert newFuzzState(empty.value.fuzzState.value, limits).value.copyFuzzMessage(
      limits.bytes).value == @[5'u8, 0]
  assert newFuzzRoot(empty.value.fuzzState.value.commitment.root, limits).error == FuzzError.None
  var duplicate = @[5'u8, 2]
  for index in 0..<64: duplicate.add(0) # Two complete identical empty-valued keys are not a map.
  assert decodeFuzzMessage(duplicate, limits).error == FuzzError.DuplicateKey
  var initialize = newSeq[byte](300)
  initialize[0] = 1
  let initialized = decodeFuzzMessage(initialize, limits)
  assert initialized.error == FuzzError.None
  assert initialized.value.fuzzHeader.error == FuzzError.None
  assert initialized.value.fuzzState.value.commitment.entries == 0
  assert initialized.value.fuzzAncestors.value.len == 0
  var one = initialize
  one[one.high] = 1
  for index in 0..<36: one.add(byte(index))
  let ancestry = decodeFuzzMessage(one, limits).value
  assert ancestry.fuzzAncestors.value.len == 1
  assert uint32(ancestry.fuzzAncestors.value[0].slot) == 0x03020100'u32
  var detachedAncestors = ancestry.fuzzAncestors.value
  detachedAncestors[0].slot = HeaderSlot(99)
  assert uint32(ancestry.fuzzAncestors.value[0].slot) == 0x03020100'u32
  var absentAncestry = initialize
  absentAncestry[absentAncestry.high] = 1
  assert decodeFuzzMessage(absentAncestry, limits).error == FuzzError.Truncated
  initialize[initialize.high] = 25
  assert decodeFuzzMessage(initialize, limits).error == FuzzError.LimitExceeded
  var body = newSeq[byte](305)
  body[0] = 3
  assert decodeFuzzMessage(body, limits).value.fuzzBlock.error == FuzzError.None
  var two = limits
  two.bytes = ByteLimit(2)
  assert newFuzzState(empty.value.fuzzState.value, two).error == FuzzError.None
  two.bytes = ByteLimit(1)
  assert newFuzzState(empty.value.fuzzState.value, two).error == FuzzError.LimitExceeded
  var four = limits
  four.bytes = ByteLimit(4)
  assert newFuzzError("no", four).error == FuzzError.None
  four.bytes = ByteLimit(3)
  assert newFuzzError("no", four).error == FuzzError.LimitExceeded
  let framed = message.encodeFuzzFrame(limits.bytes).value
  assert framed[0] == byte(expected.len) and framed[1] == 0
  for index in 0..<expected.len: assert framed[index+4] == expected[
      index] # Payload framing preserves every original message byte.
  assert fuzzFrameLength(framed.toOpenArray(0, 3), limits.bytes).value == expected.len
  assert fuzzFrameLength(@[0'u8, 0, 0, 0], limits.bytes).error == FuzzError.Truncated
  assert fuzzFrameLength(@[255'u8, 255, 255, 255], limits.bytes).error == FuzzError.LimitExceeded
  echo "PASS JAM fuzzer wire: immutable owners, complete frames and bounded typed refusals"
main()
