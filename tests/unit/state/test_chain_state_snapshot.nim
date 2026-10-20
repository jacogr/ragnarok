# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "chain_state_snapshot"}

## Verify applied-state chain capture preserves exact ownership, bounds and inherited store policies.

import std/[assertions, envvars, syncio]
import ../../../src/chain/[genesis, parameters]
import ../../../src/codec/[bounded, report_owned, state_layout, state_trie, header]
import ../../../src/state/[store, accumulation_state, accumulation_finalization,
  accumulation_times, accumulation_statistics, accumulation_validators, accumulation_activity,
  accumulation_completion, report_admission, block_transition, block_admission]
import ../../support/[accumulation_activity_context, accumulation_completion_context, arc_evidence]

# Resettable backend counters distinguish sealed-header hashing from unnecessary state Merklization.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}

proc settings(): Parameters =
  ## Use a complete fetch tuple with the signed fixture's two cores and twelve-slot epoch.
  let decoded = decodeParametersHex("ffffffffffffffff020000000000000003000000000000000200050000000c0000000700000000000000080000000000000009000000000000000a000000000000000b000c000d000e000f000000100011001200130014001500160000001700000018000000190000001a0000001b0000001c0000000a000000")
  assert decoded.ok
  decoded.value

proc entries(state: StateStoreSnapshot): seq[StateEntry] =
  ## A test-only raw-entry oracle compares the legacy adapter with exact-owner capture.
  result = @[]
  for index in 0..<state.commitment.entries:
    let key = state.keyAt(StateEntryIndex(index)).value
    result.add(StateEntry(key: key, value: state.lookup(key).value.bytes))

proc capture(wire: seq[byte], state: StateStoreSnapshot): BlockSnapshot =
  ## Capture one valid owner while proving that only the sealed header reaches the native hash primitive.
  failHash(0)
  let captured = captureBlockSnapshot(wire, state, settings())
  assert captured.error == GenesisError.None
  assert hashCalls() == 1, "retained state must not be Merklized again"
  assert sameStateSnapshot(captured.value.stateSnapshot, state)
  captured.value

proc witness(base: OwnedReport, incoming = false, provided = false, disputed = false,
    ticket = false, rotated = false): BlockSnapshot =
  ## Run genuine signed execution and state application before giving its exact posterior to chain capture.
  let authored = activityFixture(base, guarantees = (if incoming: 2 else: 0),
    available = incoming, blobs = provided, provided = provided, withDispute = disputed,
    withTicket = ticket, shiftPending = rotated, slot = (if rotated: 12'u32 else: 2'u32))
  let source = authored.source.accumulationValidatorsSource.value.accumulationTimesStatistics.value.statisticsSource.value
  var target = forkStateStore(source.finalAccumulationParent.value).value
  let applied = applyAccumulationState(target, source, completionLimits().composition)
  assert applied.error == AccumulationStateError.None
  let admitted = source.finalAccumulationAdmission.value.reportBlockStage.value.value.admitted
  var wire = newSeq[byte](100000)
  let encoded = encodeOwnedHeader(admitted.admittedHeader, wire)
  assert encoded.error == HeaderError.None
  wire.setLen(encoded.value)
  result = capture(wire, applied.value)
  let raw = entries(applied.value)
  let legacy = captureBlockSnapshot(wire, raw, settings()).value
  assert not sameStateSnapshot(legacy.stateSnapshot, applied.value), "raw entries create a distinct store"
  assert array[32, byte](legacy.stateRoot) == array[32, byte](result.stateRoot)
  assert array[32, byte](legacy.blockHash) == array[32, byte](result.blockHash)
  assert legacy.slot == result.slot and uint64(legacy.activeValidators) == uint64(
      result.activeValidators)
  assert uint64(legacy.ticketAttempts) == uint64(result.ticketAttempts) and
      uint64(legacy.basicPieceLength) == uint64(result.basicPieceLength)
  assert legacy.serviceCount == result.serviceCount and legacy.keyCount == result.keyCount
  var readOnly = forkStateStore(legacy.stateSnapshot).value
  assert readOnly.apply([StateWrite(key: chapterKey(StateChapter(250)), kind: StateWriteKind.Put,
    value: @[42'u8])]).error == StateStoreError.LimitExceeded, "legacy capture keeps its read-only policy"
  for index in 0..<raw.len:
    # Every sorted key and value agrees with legacy capture, including opaque service/storage entries.
    assert array[31, byte](result.keyAt(StateKeyIndex(index))) == array[31, byte](raw[index].key)
    assert legacy.lookup(raw[index].key).value.bytes == result.lookup(raw[index].key).value.bytes
  for index in 0..<result.serviceCount:
    assert uint32(legacy.serviceAt(ServiceListIndex(index))) == uint32(result.serviceAt(
        ServiceListIndex(index)))
  var branch = forkStateStore(result.stateSnapshot).value
  let oldTime = result.lookup(chapterKey(StateChapter(11))).value
  assert branch.apply([StateWrite(key: chapterKey(StateChapter(250)), kind: StateWriteKind.Put,
    value: @[42'u8])]).error == StateStoreError.None, "capture preserves execution store's writable policy"
  assert sameStateSnapshot(result.stateSnapshot, target.snapshot.value)
  assert oldTime.bytes == result.lookup(chapterKey(StateChapter(11))).value.bytes
  failHash(1)
  assert captureBlockSnapshot(wire, applied.value, settings()).error == GenesisError.Invalid
  assert hashCalls() == 1
  failHash(0)
  wire[0] = wire[0] xor 1
  assert array[32, byte](result.blockHash) == array[32, byte](legacy.blockHash), "header input is detached"

proc refusals(owner: BlockSnapshot) =
  ## Required chapter framing, fixed capture ceilings and defaults are checked before header hashing.
  var wire = newSeq[byte](100000)
  let encoded = encodeOwnedHeader(owner.header, wire)
  assert encoded.error == HeaderError.None
  wire.setLen(encoded.value)
  let state = owner.stateSnapshot
  failHash(1)
  assert captureBlockSnapshot(wire, default(StateStoreSnapshot), settings()).error ==
      GenesisError.Invalid
  assert captureBlockSnapshot([], state, settings()).error == GenesisError.Invalid
  assert captureBlockSnapshot(wire, state, default(Parameters)).error == GenesisError.Invalid
  assert hashCalls() == 0
  failHash(0)
  for chapter in [8'u8, 11'u8]:
    # Missing, empty and trailing bytes cannot manufacture the roster/time required for capture.
    for kind in 0..<3:
      let key = chapterKey(StateChapter(chapter))
      var changed = forkStateStore(state).value
      var replacement = state.lookup(key).value.bytes
      if kind == 1: replacement = @[] # Empty is structurally different from absent.
      elif kind == 2: replacement.add(0) # Exact consumption rejects a valid prefix plus suffix.
      let changedState = changed.apply([StateWrite(key: key,
        kind: (if kind == 0: StateWriteKind.Delete else: StateWriteKind.Put), value:
        (if kind == 0: @[] else: replacement))]).value
      failHash(1)
      assert captureBlockSnapshot(wire, changedState, settings()).error == GenesisError.Invalid
      assert hashCalls() == 0
      failHash(0)
  let empty = newStateStore([], default(StateStoreLimits)).value.snapshot.value
  assert empty.keyAt(StateEntryIndex(0)).error == StateStoreError.InvalidRange
  assert state.keyAt(StateEntryIndex(-1)).error == StateStoreError.InvalidRange
  assert state.keyAt(StateEntryIndex(state.commitment.entries)).error ==
      StateStoreError.InvalidRange
  assert state.keyAt(StateEntryIndex(high(int))).error == StateStoreError.InvalidRange
  assert default(StateStoreSnapshot).keyAt(StateEntryIndex(0)).error ==
      StateStoreError.Uninitialized
  var raw = entries(state)
  raw.add(StateEntry(key: chapterKey(StateChapter(249)), value: newSeq[byte](4 * 1024 * 1024)))
  let broad = StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(20000),
    perValue: ByteLimit(5 * 1024 * 1024), totalValueBytes: ByteLimit(8 * 1024 * 1024),
    nodes: TrieNodeLimit(2000000)))
  let oversized = newStateStore(raw, broad).value.snapshot.value
  failHash(1)
  assert captureBlockSnapshot(wire, oversized, settings()).error == GenesisError.Invalid
  assert hashCalls() == 0, "a broad source policy cannot override the capture byte ceiling"
  failHash(0)
  raw = entries(state)
  let missing = 16385 - raw.len
  for index in 0..<missing:
    # Distinct opaque keys cross the entry ceiling without consuming the aggregate-value allowance.
    var key = default(array[31, byte])
    key[0] = 248
    key[1] = byte(index and 255)
    key[2] = byte(index shr 8)
    raw.add(StateEntry(key: StateKey(key)))
  let overpopulated = newStateStore(raw, broad).value.snapshot.value
  assert overpopulated.commitment.entries == 16385
  failHash(1)
  assert captureBlockSnapshot(wire, overpopulated, settings()).error == GenesisError.Invalid
  assert hashCalls() == 0
  failHash(0)
  var wrongTime = forkStateStore(state).value
  let mismatched = wrongTime.apply([StateWrite(key: chapterKey(StateChapter(11)),
    kind: StateWriteKind.Put, value: @[3'u8, 0, 0, 0])]).value
  failHash(1)
  assert captureBlockSnapshot(wire, mismatched, settings()).error == GenesisError.Invalid
  var extended = wire
  extended.add(0)
  assert captureBlockSnapshot(extended, state, settings()).error == GenesisError.Invalid
  wire.setLen(wire.len - 1)
  assert captureBlockSnapshot(wire, state, settings()).error == GenesisError.Invalid
  assert hashCalls() == 0
  failHash(0)

proc enumeration() =
  ## A small independent literal map proves sorted ordinals, present-empty keys and snapshot-relative coordinates.
  let keys = [chapterKey(StateChapter(7)), chapterKey(StateChapter(1)), chapterKey(StateChapter(4))]
  var source = newStateStore([StateEntry(key: keys[0], value: @[7'u8]),
    StateEntry(key: keys[1]), StateEntry(key: keys[2], value: @[4'u8])],
    StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(3), perValue: ByteLimit(1),
      totalValueBytes: ByteLimit(2), nodes: TrieNodeLimit(1000)), writes: ElementLimit(1),
      writeValueBytes: ByteLimit(1))).value
  let old = source.snapshot.value
  let expected = [1'u8, 4, 7]
  for index, chapter in expected:
    # Lexical order is independent of insertion order, and the empty value still has a key ordinal.
    assert array[31, byte](old.keyAt(StateEntryIndex(index)).value) ==
      array[31, byte](chapterKey(StateChapter(chapter)))
  assert source.apply([StateWrite(key: keys[1], kind: StateWriteKind.Delete)]).error ==
      StateStoreError.None
  assert array[31, byte](source.snapshot.value.keyAt(StateEntryIndex(0)).value) == array[31, byte](keys[2])
  assert array[31, byte](old.keyAt(StateEntryIndex(0)).value) == array[31, byte](keys[1])

proc cycle(owner: BlockSnapshot, wire: seq[byte]) =
  ## One capture and one failed capture release their temporary key/service/header owners at scope exit.
  let retained = capture(wire, owner.stateSnapshot)
  assert retained.keyCount == owner.keyCount
  assert captureBlockSnapshot([], owner.stateSnapshot, settings()).error == GenesisError.Invalid

proc main() {.raises.} =
  ## Signed scenarios prove detached output lifetime; repeated cheap capture checks ARC release separately.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index in 0..<wire.len: wire[index] = byte(raw[index])
  let base = decodeOwnedReport(wire, 2).value
  let owner = witness(base, incoming = true, provided = true)
  discard witness(base)
  discard witness(base, disputed = true)
  discard witness(base, ticket = true)
  discard witness(base, rotated = true)
  assert owner.slot == 2 and owner.lookup(chapterKey(StateChapter(11))).value.bytes == @[2'u8, 0, 0, 0]
  refusals(owner)
  enumeration()
  wire = newSeq[byte](100000)
  let encoded = encodeOwnedHeader(owner.header, wire)
  assert encoded.error == HeaderError.None
  wire.setLen(encoded.value)
  cycle(owner, wire)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(owner, wire) # No retained snapshots or private index containers accumulate.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("chain_state_snapshot", 1000, before, after)
  echo "Applied-state chain snapshot capture passed"
  echo "ARC_RELEASE cycles=1000 unchanged"

try:
  main() # Fixture I/O errors must fail the native suite.
except:
  quit(2)
