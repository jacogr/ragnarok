# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Structurally decoded header markers bind retained parent and staged state without writes or
## hashing.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

import std/assertions
import std/envvars
import std/parseutils
import std/strutils
import std/syncio
import ../../../src/state/safrole_markers as state_safrole_markers
import ../../../src/state/marker_state as state_marker_state
import ../../../src/state/store as state_store
import ../../../src/codec/state_safrole as codec_state_safrole
import ../../../src/codec/state_consensus as codec_state_consensus
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/codec/header as codec_header
import ../../../src/codec/bounded as codec_bounded
import ../../support/codec_validator_rotation_fixture

## Test-library hashes can be refused after map construction to prove validation performs no backend work.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
## Observe all primitive attempts, including refused calls.
proc hashes(): cint {.importc: "ro_blake_calls", cdecl.}

## Parse a whole trusted unsigned decimal fixture field before narrowing.
proc number(text: string): uint64 =
  var value = 0'u64
  assert parseBiggestUInt(text, value) == text.len
  value

## Decode exact trusted hexadecimal transport without calling a production parser.
proc unhex(text: string): seq[byte] =
  assert text.len mod 2 == 0
  result = newSeq[byte](text.len div 2)
  for i in 0..<result.len:
    var value = 0'u8
    assert parseHex(text[2*i..2*i+1], value) == 2 # Every supplied octet is complete.
    result[i] = value

## Append one explicit suffix byte without changing the original trusted fixture buffer.
proc suffixed(raw: seq[byte]): seq[byte] =
  result = newSeq[byte](raw.len+1)
  for i in 0..<raw.len: result[i] = raw[i] # Preserve every original byte before the extra trailing value.
  result[raw.len] = 0

## Finite chain policy bounds every parent/posterior chapter and active roster independently.
proc policy(epoch = 12, tail = 10): SafroleMarkerConfig =
  SafroleMarkerConfig(state: SafroleStateConfig(validators: rotationRosterConfig(),
    epochSlots: EpochSlots(uint64(epoch)), maxAccumulator: ElementLimit(uint64(epoch)),
    maxBytes: ByteLimit(1000000)), tailStart: EpochSlots(uint64(tail)), maxMarkerBytes: ByteLimit(1000000))

## Finite sample map limits bound complete construction independently of marker validation policy.
proc limits(): StateStoreLimits =
  StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(4), perValue: ByteLimit(400000),
    totalValueBytes: ByteLimit(500000), nodes: TrieNodeLimit(1000)),
    writes: ElementLimit(1), writeValueBytes: ByteLimit(400000))

## Build a structural header using supplied upstream marker bytes, never native expected-marker construction.
proc candidate(epoch, winners: seq[byte], target: StateTime,
    config: SafroleMarkerConfig): OwnedUnsignedHeader =
  let policy = HeaderConfig(cores: config.state.validators.cores,
    authorValidators: ValidatorCount(uint64(config.state.validators.cores)*3),
    epochSlots: config.state.epochSlots, maxBytes: ByteLimit(100000))
  let epochOwner = decodeEpochMarker(epoch, policy).value.owner
  let winnerOwner = decodeWinnersMarker(winners, policy).value.owner
  let epochInfo = epochMarkerInfo(epochOwner).value
  let winnerInfo = winnersMarkerInfo(winnerOwner).value
  var source = default(UnsignedHeader)
  source.slot = HeaderSlot(uint32(target))
  source.epoch = absentEpoch()
  source.winners = absentWinners()
  if epochInfo.present:
    var keys = newSeq[EpochValidator](epochInfo.validators)
    for i in 0..<keys.len: keys[i] = epochValidatorAt(epochOwner,
        i).value # Preserve published key order and both roles.
    source.epoch = presentEpoch(epochInfo.entropy, epochInfo.ticketsEntropy, keys)
  if winnerInfo.present:
    var tickets = newSeq[WinningTicket](winnerInfo.tickets)
    for i in 0..<tickets.len: tickets[i] = winningTicketAt(winnerOwner,
        i).value # Supplied attempt bytes remain observable.
    source.winners = presentWinners(tickets)
  var wire = newSeq[byte](100000)
  let encoded = encodeUnsignedHeader(source, policy, wire)
  assert encoded.error == HeaderError.None
  wire.setLen(encoded.value)
  let captured = decodeUnsignedHeader(wire, policy)
  assert captured.error == HeaderError.None and captured.value.consumed == wire.len
  captured.value.owner

## Compare the entire retained map and commitment after validation, not just the marker chapters.
proc unchanged(owner: StateStoreSnapshot, source: seq[StateEntry], root: StateRoot) =
  assert array[32, byte](owner.commitment.root) == array[32, byte](root)
  for entry in source:
    assert owner.lookup(entry.key).value.bytes == entry.value # No hidden C(4), entropy, time or unrelated write.

## Exercise missing/truncated/suffixed required chapters on both sides without relying on marker equality.
proc damage(before, after: seq[StateEntry], header: OwnedUnsignedHeader,
    config: SafroleMarkerConfig) =
  for parentSide in 0..<2:
    let original = if parentSide == 1: before else: after
    let required = if parentSide == 1: 3 else: 2
    for index in 0..<required:
      let position = if parentSide == 0 and index == 1: 2 else: index
      for kind in 0..<3:
        var broken = newSeq[StateEntry](0)
        for i, entry in original:
          if i != position or kind != 0:
            var copied = StateEntry(key: entry.key, value: entry.value)
            if i == position:
              if kind == 1:
                copied.value.setLen(copied.value.len-1) # Truncated state cannot provide a default field.
              else:
                copied.value.add 0 # Exact chapters reject valid prefixes with an extra octet.
            broken.add copied
        failHash(0)
        let parent = newStateStore((if parentSide == 1: broken else: before), limits()).value.snapshot.value
        let staged = newStateStore((if parentSide == 0: broken else: after), limits()).value.snapshot.value
        let parentRoot = parent.commitment.root
        let stagedRoot = staged.commitment.root
        failHash(1)
        let outcome = validateSafroleHeaderMarkers(parent, staged, header, config)
        assert outcome == (if kind == 0: SafroleMarkerError.MissingState else: SafroleMarkerError.InvalidState)
        assert hashes() == 0
        unchanged(parent, (if parentSide == 1: broken else: before), parentRoot)
        unchanged(staged, (if parentSide == 0: broken else: after), stagedRoot)
  failHash(0)

## Every accepted vector output is validated through a complete immutable unsigned-header owner.
proc published(text: string) =
  let lines = text.splitLines()
  assert lines.len == 34
  for i in 0..<33:
    let f = lines[i].splitWhitespace()
    assert f.len == 19
    var config = policy(int(number(f[2])), int(number(f[3])))
    config.state.validators = rotationRosterConfig(int(number(f[1])))
    let previous = StateTime(uint32(number(f[4])))
    let target = StateTime(uint32(number(f[5])))
    let before = @[
      StateEntry(key: chapterKey(StateChapter(4)), value: unhex(f[7])),
      StateEntry(key: chapterKey(StateChapter(6)), value: unhex(f[12])), timeEntry(previous),
      StateEntry(key: chapterKey(StateChapter(1)), value: @[98'u8, 76])]
    let after = @[
      StateEntry(key: chapterKey(StateChapter(4)), value: unhex(f[10])),
      StateEntry(key: chapterKey(StateChapter(6)), value: unhex(f[14])), timeEntry(target),
      StateEntry(key: chapterKey(StateChapter(1)), value: @[77'u8, 66])]
    failHash(0)
    var parentStore = newStateStore(before, limits()).value
    var working = newStateStore(after, limits()).value
    let parent = parentStore.snapshot.value
    let staged = working.snapshot.value
    let oldRoot = parent.commitment.root
    let stagedRoot = staged.commitment.root
    let epoch = unhex(f[17])
    let winners = unhex(f[18])
    let header = candidate(epoch, winners, target, config)
    failHash(1)
    assert validateSafroleHeaderMarkers(parent, staged, header, config) == SafroleMarkerError.None
    assert hashes() == 0 # Even epoch crossings and deadline markers need no hash or native backend.
    unchanged(parent, before, oldRoot)
    unchanged(staged, after, stagedRoot)
    assert validateSafroleHeaderMarkers(default(StateStoreSnapshot), staged, header, config) ==
        SafroleMarkerError.Uninitialized
    assert validateSafroleHeaderMarkers(parent, default(StateStoreSnapshot), header, config) ==
        SafroleMarkerError.Uninitialized
    assert validateSafroleHeaderMarkers(parent, staged, default(OwnedUnsignedHeader), config) ==
        SafroleMarkerError.InvalidHeader
    let otherSlot = candidate(epoch, winners, StateTime(uint32(target)+1), config)
    assert validateSafroleHeaderMarkers(parent, staged, otherSlot, config) ==
        SafroleMarkerError.InvalidState
    if epoch.len > 1:
      var changed = epoch
      changed[1] = changed[1] xor 1 # A structurally valid header with wrong parent entropy must fail context validation.
      let wrongEpoch = candidate(changed, winners, target, config)
      assert validateSafroleHeaderMarkers(parent, staged, wrongEpoch, config) ==
          SafroleMarkerError.InvalidEpochMarker
    if winners.len > 1:
      var changed = winners
      changed[33] = changed[33] xor 1 # Wrong attempt cannot pass merely because the identifier matches.
      let wrongWinner = candidate(epoch, changed, target, config)
      assert validateSafroleHeaderMarkers(parent, staged, wrongWinner, config) ==
          SafroleMarkerError.InvalidWinnersMarker
    var small = config
    small.state.maxBytes = ByteLimit(uint64(before[0].value.len-1))
    assert validateSafroleHeaderMarkers(parent, staged, header, small) ==
        SafroleMarkerError.LimitExceeded
    assert hashes() == 0
    failHash(0)
    if i == 0: damage(before, after, header, config) # Focus every required input shape independently.
    parentStore = default(StateStore)
    working = default(StateStore)
    assert validateSafroleHeaderMarkers(parent, staged, header, config) ==
        SafroleMarkerError.None # Retained snapshots/header outlive all store handles.
    unchanged(parent, before, oldRoot)
    unchanged(staged, after, stagedRoot)

try:
  published(readFile(getEnv("RAGNAROK_SAFROLE_MARKERS"))) # Mandatory hash-checked transport preserves the full published workload.
except:
  quit(2) # Never silently skip context projections or substitute a prefix-only header.
echo "PASS marker state: thirty-three decoded headers, read-only context binding and retained history"
