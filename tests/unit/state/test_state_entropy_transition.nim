# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Published Safrole entropy/time projections, fixed hash known answer and epoch/slot
## boundaries.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

import std/assertions
import std/envvars
import std/parseutils
import std/strutils
import std/syncio
import ../../support/state_entropy_transition_fixture
import ../../../src/state/entropy as state_entropy
import ../../../src/state/store as state_store
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/bounded as codec_bounded

## Parse exact trusted hex transport, independently of protocol framing and result guards.
proc unhex(text: string): seq[byte] =
  assert text.len mod 2 == 0
  result = newSeq[byte](text.len div 2)
  for i in 0..<result.len:
    var octet = 0'u8
    assert parseHex(text[2*i..2*i+1], octet) == 2 # A truncated/invalid fixture octet is a harness failure.
    result[i] = octet

## Preserve fixture unsigned extents before converting a slot to its explicit uint32 protocol width.
proc number(text: string): uint64 =
  var value = 0'u64
  assert parseBiggestUInt(text, value) == text.len
  value

## Parse a copied 32-byte identity; wider/shorter inputs cannot pass the fixture width contract.
proc fixed(text: string): array[32, byte] =
  let bytes = unhex(text)
  assert bytes.len == 32
  result = default(array[32, byte])
  for i in 0..<32: result[i] = bytes[i] # Synchronous copied values contain no transport pointers.

## Bound the independent full-map store and two simultaneous fixed chapter writes.
proc policy(): StateStoreLimits =
  StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(3), perValue: ByteLimit(128),
    totalValueBytes: ByteLimit(133), nodes: TrieNodeLimit(747)), writes: ElementLimit(2),
    writeValueBytes: ByteLimit(132))

## All twelve cases compare both fixed chapters; rejection preserves the complete old store head.
proc published(lines: seq[string]) =
  for i in 0..<12:
    let fields = lines[4*i].splitWhitespace() # Four transport lines per published projection.
    assert fields.len == 5
    let epoch = EpochSlots(number(fields[0]))
    let previous = number(fields[1])
    let target = number(fields[2])
    assert previous <= uint64(high(uint32)) and target <= uint64(high(uint32))
    let randomness = EntropyInput(fixed(fields[3]))
    let before = unhex(lines[4*i+1])
    let after = unhex(lines[4*i+2])
    let expectedTime = number(lines[4*i+3])
    let parsed = decodeStateEntropy(before)
    assert parsed.error == StateComponentError.None and parsed.value.consumed == before.len
    let advanced = advanceEntropyTime(parsed.value.value, StateTime(uint32(previous)),
        StateTime(uint32(target)), randomness, epoch)
    let entries = @[entropyEntry(parsed.value.value), timeEntry(StateTime(uint32(previous))),
        StateEntry(key: chapterKey(StateChapter(1)), value: @[99'u8])]
    let made = newStateStore(entries, policy())
    assert made.error == StateStoreError.None, "store initialization " & $made.error
    var state = made.value
    let old = state.snapshot.value
    let committed = advanceEntropyTimeState(state, StateTime(uint32(target)), randomness, epoch)
    if fields[4] == "1":
      # Successful projections bind exact published words and timeslot, not the rest of Safrole's posterior state.
      assert advanced.error == EntropyTransitionError.None, "advance failed"
      assert entropyEntry(advanced.value.entropy).value == after, "published entropy"
      assert uint64(uint32(advanced.value.time)) == expectedTime
      assert committed.error == EntropyTransitionError.None, "store transition " & $committed.error
      assert committed.value.lookup(entries[0].key).value.bytes == after
      assert committed.value.lookup(entries[1].key).value.bytes == timeEntry(StateTime(uint32(
          expectedTime))).value
    else:
      # The chosen negative vector is strict monotonicity failure; no new accumulator or slot may be published.
      assert fields[4] == "0" and advanced.error == EntropyTransitionError.InvalidSlot
      assert committed.error == EntropyTransitionError.InvalidSlot and after == before
      assert expectedTime == previous
      assert array[32, byte](state.snapshot.value.commitment.root) == array[32, byte](
          old.commitment.root)
    assert state.snapshot.value.lookup(entries[2].key).value.bytes == entries[2].value
    assert old.lookup(entries[0].key).value.bytes == before
    assert old.lookup(entries[1].key).value.bytes == entries[1].value

## Exact independent hash plus arithmetic boundaries distinguish old/new accumulator and one/many rotations.
proc boundaries(expected: array[32, byte]) =
  var prior = entropyWords()
  let original = prior
  var bytes = default(array[32, byte])
  for i in 0..<32: bytes[i] = byte(i+32) # Matches the independent hashlib known answer, not a native recomputation.
  let randomness = EntropyInput(bytes)
  for epoch in [1'u64, 12, 600, high(uint64)]:
    for target in [1'u32, 11, 12, 13, 600, high(uint32)]:
      # Every positive target hashes the same exact 64 bytes; epoch arithmetic only selects historical rotation.
      let advanced = advanceEntropyTime(prior, StateTime(0), StateTime(target), randomness,
          EpochSlots(epoch))
      assert advanced.error == EntropyTransitionError.None, "advance failed"
      assert array[32, byte](advanced.value.entropy[0]) == expected
      assert uint32(advanced.value.time) == target
      for word in 1..<4:
        let source = if uint64(target) div epoch >
            0: word-1 else: word # One rotation even across billions of epochs.
        assert array[32, byte](advanced.value.entropy[word]) == array[32, byte](prior[source])
  let last = advanceEntropyTime(prior, StateTime(high(uint32)-1), StateTime(high(uint32)),
      randomness, EpochSlots(12))
  assert last.error == EntropyTransitionError.None # The largest valid step needs no overflowing slot addition.
  for pair in [(0'u32, 0'u32), (1'u32, 0'u32), (1'u32, 1'u32), (high(uint32), 0'u32), (high(uint32),
      high(uint32))]:
    assert advanceEntropyTime(prior, StateTime(pair[0]), StateTime(pair[1]), randomness,
        EpochSlots(12)).error == EntropyTransitionError.InvalidSlot # Reject repeats, regressions and wraparound.
  assert advanceEntropyTime(prior, StateTime(0), StateTime(1), randomness,
      EpochSlots(0)).error == EntropyTransitionError.InvalidConfig
  let first = advanceEntropyTime(prior, StateTime(10), StateTime(11), randomness, EpochSlots(12)).value
  let next = advanceEntropyTime(first.entropy, first.time, StateTime(12), randomness, EpochSlots(12)).value
  assert array[32, byte](next.entropy[1]) == array[32, byte](first.entropy[
      0]) # Rotate the immediate parent's accumulator.
  prior[0] = StateEntropyWord(default(array[32, byte]))
  bytes[0] = 0
  assert array[32, byte](first.entropy[0]) == expected # Completed fixed copies outlive input mutation.
  assert array[32, byte](original[0]) != array[32, byte](prior[0])

try:
  let lines = readFile(getEnv("RAGNAROK_ENTROPY_STF")).splitLines() # Explicit fixture I/O is not protocol input.
  assert lines.len == 50
  published(lines)
  boundaries(fixed(lines[48]))
except:
  quit(2) # A missing/malformed fixture must fail rather than silently omit published coverage.
echo "PASS entropy/time transition: twelve published projections, fixed hash, epoch/slot boundaries and atomic chapters"
