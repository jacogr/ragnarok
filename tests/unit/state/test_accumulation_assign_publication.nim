# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "accumulation_assign_publication_arc_release"}

## Real parallel assign outcomes merge only original-owner queue/role rows under terminal selection, quotas and complete-map rollback.

import std/[assertions, syncio]
import ../../../src/state/[accumulation_batch, accumulation_effects, accumulation_context,
  accumulation_dispatch, accumulation_outcome, store]
import ../../../src/codec/[bounded, composite, header, state_accounts, state_authorization,
  state_layout, state_trie]
import ../../../src/chain/parameters
import ../../../src/pvm/machine
import ../../support/[accumulation_batch_context, pvm_accumulation_context,
  pvm_accumulation_program, accumulation_provision_integration, arc_evidence]

type Ending = enum ## Authored guest control flow selects normal, discarded, frozen or restored assignments.
  Halt, Panic, CheckpointPanic, Restore
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
proc hashAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
proc parameters(): Parameters =
  ## Assign validates the tiny core domain and eighty-entry queue before reading the real guest memory.
  var wire = encodeParameters(pvmParameters())
  for index in 0..<24: wire[index] = 0 # Tiny credited balances need no deposit funding.
  wire[24] = 2
  wire[25] = 0
  wire[82] = 80
  wire[83] = 0
  decodeParameters(wire).value
proc envelope(core: uint64, original: uint32, marker: byte, ending: Ending): seq[byte] =
  ## Place independently varied queue bytes in slot two; the rest of the mapped page is zero padded.
  var payload = newSeq[byte](96)
  for index in 64..<96: payload[index] = marker+byte(index-64)
  let next = if ending == Restore: uint64(original) else: 77+core
  var instructions = @[registerImmediate(7, core), registerImmediate(8, 196608),
    registerImmediate(9, next), @[10'u8, 16]]
  if ending == CheckpointPanic: instructions.add(@[10'u8,
      18]) # Freeze assignment provenance, queue and roles together.
  if ending == Restore:
    instructions.add(registerImmediate(7, core))
    instructions.add(registerImmediate(8, 196704))
    instructions.add(registerImmediate(9, uint64(original)))
    instructions.add(@[10'u8, 16]) # Restore original global bytes without erasing successful-assignment provenance.
  if ending in {Panic, CheckpointPanic}: instructions.add(@[
      0'u8]) # Genuine guest trap selects the exceptional implication.
  instructions.add(@[50'u8, 0])
  guestEnvelope(instructions, writable = payload)
proc policy(): AccumulationBatchLimits =
  ## Exactly two complete queue rows and the twenty-one-byte privilege record authorize four total writes including credits.
  result = batchPolicy()
  result.assignCores = ElementLimit(2)
  result.assignBytes = ByteLimit(5141)
proc expected(fixture: BatchFixture, first, second: Ending): seq[StateEntry] =
  ## Literal chapter offsets plus independent credited metadata build a whole-map oracle without running the merger.
  result = @[]
  for record in fixture.entries:
    var row = record
    for index, ending in [first, second]:
      let service = ServiceIndex(if index == 0: 42 else: 99)
      if array[31, byte](record.key) == array[31, byte](chapterServiceKey(StateChapter(255), service)):
        let decoded = decodeServiceMetadata(record.value, ByteLimit(89)).value.metadata
        var account = decoded
        account.balance = AccountBalance(if index == 0: 17 else: 31)
        row = serviceMetadataEntry(service, account, ByteLimit(89)).value
      if ending in {Halt, CheckpointPanic}:
        if array[31, byte](record.key) == array[31, byte](chapterKey(StateChapter(2))):
          for offset in 0..<32: row.value[index*2560+64+offset] = byte((if index ==
              0: 1 else: 41)+offset)
        if array[31, byte](record.key) == array[31, byte](chapterKey(StateChapter(12))):
          for offset in 0..<4: row.value[4+index*4+offset] = byte((uint32(77+index) shr (
              offset*8)) and 255)
    result.add(row)
proc check(first, second: Ending, reverse = false) =
  ## Every selected row is source-bound and independent of borrowed execution order or later caller changes.
  let fixture = batchFixture(firstEnvelope = envelope(0, 42, 1, first),
    secondEnvelope = envelope(1, 99, 41, second), assigners = @[ServiceIndex(42), ServiceIndex(99)])
  let prior = fixture.state.snapshot.value
  let a = batchExecution(fixture, 0, parameters = parameters(), copyLimit = MemoryByteLimit(2560))
  let b = batchExecution(fixture, 1, parameters = parameters(), copyLimit = MemoryByteLimit(2560))
  assert a.error == AccumulationDispatchError.None and b.error == AccumulationDispatchError.None, "both real assign dispatches complete"
  let ca = normalizeAccumulationOutcome(a).value.outcomeContext.value
  let cb = normalizeAccumulationOutcome(b).value.outcomeContext.value
  assert ca.effectInfo.value.hasAssignments == (first != Panic), "first selected assignment provenance"
  assert cb.effectInfo.value.hasAssignments == (second != Panic), "second selected assignment provenance"
  let runs = if reverse: @[b, a] else: @[a, b]
  let active = first != Panic or second != Panic
  failHash(3)
  let prepared = prepareCompleteAccumulationBatch(fixture.inputs, prior, runs, [], HeaderSlot(128),
      policy()).value
  assert prepared.batchInfo.value.assignmentWrites == (if active: 2 else: 0), "selected global write count"
  if active:
    assert prepareCompleteAccumulationBatch(fixture.inputs, prior, runs, [], HeaderSlot(128),
        batchPolicy()).error == AccumulationBatchError.LimitExceeded
    var short = policy()
    short.assignCores = ElementLimit(1)
    assert prepareCompleteAccumulationBatch(fixture.inputs, prior, runs, [], HeaderSlot(128),
        short).error == AccumulationBatchError.LimitExceeded
    short = policy()
    short.assignBytes = ByteLimit(5140)
    assert prepareCompleteAccumulationBatch(fixture.inputs, prior, runs, [], HeaderSlot(128),
        short).error == AccumulationBatchError.LimitExceeded
  assert hashCalls() == 0, "preparation hashes no data" # Work refusal and private write preparation perform no hashes.
  failHash(0)
  var wide = policy()
  wide.assignCores = ElementLimit(high(uint64))
  wide.assignBytes = ByteLimit(high(uint64))
  assert prepareCompleteAccumulationBatch(fixture.inputs, prior, runs, [], HeaderSlot(128),
      wide).error == AccumulationBatchError.None
  let entries = expected(fixture, first, second)
  let wanted = stateTrieRoot(entries, integrationStoreLimits().trie).value
  for successful in [0, 2]:
    var caller = fixture.state
    hashAfter(cint(successful))
    let refused = applyAccumulationBatch(caller, prepared)
    assert refused.error == AccumulationBatchError.StoreFailure and refused.storeError ==
        StateStoreError.BackendFailure
    failHash(0)
    assert sameStateSnapshot(caller.snapshot.value, prior)
  var caller = fixture.state
  let published = applyAccumulationBatch(caller, prepared).value
  assert array[32, byte](published.commitment.root) == array[32, byte](wanted.root), "literal complete-map root"
  for record in entries: assert published.lookup(record.key).value.bytes == record.value, "literal complete-map entry"
  assert sameStateSnapshot(fixture.state.snapshot.value, prior)
  var observed = ca.effectInfo.value
  observed.hasAssignments = false
  assert ca.effectInfo.value.hasAssignments == (first != Panic), "first selected assignment provenance"
  failHash(3)
  assert applyAccumulationBatch(caller, prepared).error == AccumulationBatchError.StaleState
  assert hashCalls() == 0
  failHash(0)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    let local = prepareCompleteAccumulationBatch(fixture.inputs, prior, runs, [], HeaderSlot(128),
        policy()).value
    var private = fixture.state
    assert array[32, byte](applyAccumulationBatch(private, local).value.commitment.root) == array[
        32, byte](wanted.root)
  assert before == getOccupiedMem(), "assignment plan/publication ARC release" # Plans, selected handles, core row scratch and unpublished complete maps all release.
proc checkSubset() =
  ## An explicit executed subset retains an absent original assigner's row and grants credits only to the executed service.
  let fixture = batchFixture(firstEnvelope = envelope(0, 42, 1, Halt),
    secondEnvelope = envelope(1, 99, 41, Halt), assigners = @[ServiceIndex(42), ServiceIndex(99)])
  let b = batchExecution(fixture, 1, parameters = parameters(), copyLimit = MemoryByteLimit(2560))
  let plan = prepareAccumulationBatch(fixture.inputs, fixture.state.snapshot.value, [b], HeaderSlot(
      128), policy()).value
  assert not plan.batchInfo.value.completeInputs and plan.batchInfo.value.assignmentWrites == 2
  var entries = expected(fixture, Panic, Halt)
  let key = chapterServiceKey(StateChapter(255), ServiceIndex(42))
  for index in 0..<entries.len:
    if array[31, byte](entries[index].key) == array[31, byte](key):
      entries[index].value = fixture.state.snapshot.value.lookup(
          key).value.bytes # No skipped/absent service receives a subset credit.
  let wanted = stateTrieRoot(entries, integrationStoreLimits().trie).value
  var caller = fixture.state
  let published = applyAccumulationBatch(caller, plan).value
  assert array[32, byte](published.commitment.root) == array[32, byte](wanted.root), "subset retains absent original assigner and metadata"
proc checkStoreLimit() =
  ## Host assign fits the inherited store, but the complete two-credit/two-global batch must still honor its four-write requirement.
  let fixture = batchFixture(writes = 3, firstEnvelope = envelope(0, 42, 1, Halt),
    secondEnvelope = envelope(1, 99, 41, Halt), assigners = @[ServiceIndex(42), ServiceIndex(99)])
  let a = batchExecution(fixture, 0, parameters = parameters(), copyLimit = MemoryByteLimit(2560))
  let b = batchExecution(fixture, 1, parameters = parameters(), copyLimit = MemoryByteLimit(2560))
  let prior = fixture.state.snapshot.value
  let plan = prepareCompleteAccumulationBatch(fixture.inputs, prior, [a, b], [], HeaderSlot(128),
      policy()).value
  var state = fixture.state
  let refused = applyAccumulationBatch(state, plan)
  assert refused.error == AccumulationBatchError.StoreFailure and refused.storeError ==
      StateStoreError.LimitExceeded
  assert sameStateSnapshot(state.snapshot.value, prior)
proc checkUnsupported() =
  ## A real manager bless followed by a successful assign cannot erase broader unsupported ancestry.
  var payload = newSeq[byte](96)
  payload[0] = 42
  payload[4] = 99
  let program = guestEnvelope([registerImmediate(7, 77), registerImmediate(8, 196608),
    registerImmediate(9, 0), registerImmediate(10, 0), registerImmediate(11, 0),
    registerImmediate(12, 0), @[10'u8, 15], registerImmediate(7, 0),
    registerImmediate(8, 196608), registerImmediate(9, 42), @[10'u8, 16], @[50'u8, 0]],
        writable = payload)
  let fixture = batchFixture(firstEnvelope = program, secondEnvelope = guestEnvelope([@[50'u8, 0]]),
    assigners = @[ServiceIndex(42), ServiceIndex(99)], manager = 42)
  let a = batchExecution(fixture, 0, parameters = parameters(), copyLimit = MemoryByteLimit(2560))
  let b = batchExecution(fixture, 1, parameters = parameters(), copyLimit = MemoryByteLimit(2560))
  assert a.error == AccumulationDispatchError.None
  let selected = normalizeAccumulationOutcome(a).value.outcomeContext.value
  assert selected.effectInfo.value.hasAssignments, "assign after bless succeeds"
  assert selected.effectAccountScope.value == AccumulationAccountScope.Unsupported, "manager ancestry remains unsupported"
  assert prepareCompleteAccumulationBatch(fixture.inputs, fixture.state.snapshot.value, [a, b], [],
      HeaderSlot(128), policy()).error == AccumulationBatchError.UnsupportedAccountEffects
proc main() =
  ## Exercise both original core owners, distinct terminal branches and restored-equal provenance.
  check(Halt, Halt)
  check(Halt, Halt, reverse = true)
  check(Panic, Halt)
  check(CheckpointPanic, Panic)
  check(Panic, Panic)
  check(Restore, Halt)
  checkSubset()
  checkStoreLimit()
  checkUnsupported()
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    let source = batchFixture()
    assert source.entries.len > 0 # Repeated frozen backing owners also release independently of the heavier merge checks.
  let after = getOccupiedMem()
  assert before == after, "fixture ARC release"
  recordArcRelease("accumulation_assign_publication", 1000, before, after)
  echo "Accumulation assign publication passed"
  echo "ARC_RELEASE cycles=1000 unchanged"
main()
