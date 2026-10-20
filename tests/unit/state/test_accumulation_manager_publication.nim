# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "accumulation_manager_publication_arc_release"}

## Real parallel bless/assign guests prove manager precedence, original queue authority and atomic bounded full-map publication.

import std/[assertions, syncio]
import ../../../src/state/[accumulation_batch, accumulation_effects, accumulation_context,
  accumulation_dispatch, accumulation_outcome, store]
import ../../../src/codec/[bounded, composite, header, state_accounts, state_privileges,
  state_authorization, state_layout, state_trie]
import ../../../src/chain/parameters
import ../../../src/pvm/machine
import ../../support/[accumulation_batch_context, pvm_accumulation_context,
  pvm_accumulation_program, accumulation_provision_integration, arc_evidence]

type Ending = enum ## Authored terminal selection preserves or discards actual privilege provenance.
  Halt, Panic, CheckpointPanic, Restore, HashReturn
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
proc hashAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
proc put(bytes: var seq[byte], value: uint64, width: int) =
  ## Append literal little-endian protocol fields independently of the production C(12) codec.
  for offset in 0..<width:
    bytes.add(byte((value shr (8*offset)) and 255)) # Fixed four/eight-byte widths keep shifts below 64.
proc parameters(): Parameters =
  ## Real hosts validate the tiny chain profile and eighty-entry queues without unfunded fixture deposits.
  var wire = encodeParameters(pvmParameters())
  for index in 0..<24: wire[index] = 0 # Preserve tiny credited balances.
  wire[24] = 2
  wire[25] = 0
  wire[82] = 80
  wire[83] = 0
  decodeParameters(wire).value
proc managerProgram(changed: bool, ending: Ending, pairs: int): seq[byte] =
  ## The manager selects independent roles and a canonical dictionary, including full unsigned gas/service domains.
  var payload: seq[byte] = @[]
  payload.put(if changed: 88'u64 else: 99'u64, 4)
  payload.put(89, 4)
  if pairs > 0:
    payload.put(42, 4)
    payload.put(0, 8) # Zero remains a present allowance.
  if pairs > 1:
    payload.put(uint64(high(uint32)), 4)
    payload.put(high(uint64), 8) # No signed narrowing of allowances is permitted.
  # A second bless restores the entire original C(12), while retaining occurrence provenance.
  let restoreOffset = payload.len
  payload.put(99, 4)
  payload.put(99, 4)
  var instructions = @[registerImmediate(7, if ending == Restore: 42'u64 else: uint64(high(
      uint32))),
    registerImmediate(8, 196608), registerImmediate(9, uint64(high(uint32))-1),
    registerImmediate(10, 17), registerImmediate(11, 196616), registerImmediate(12, uint64(pairs)),
    @[10'u8, 15]]
  if ending == CheckpointPanic:
    instructions.add(@[10'u8, 18]) # Freeze the changed roles, dictionary and provenance in the exceptional context.
  if ending == Restore:
    instructions.add(registerImmediate(7, 42))
    instructions.add(registerImmediate(8, uint64(196608+restoreOffset)))
    instructions.add(registerImmediate(9, 0))
    instructions.add(registerImmediate(10, 0))
    instructions.add(registerImmediate(12, 0))
    instructions.add(@[10'u8, 15]) # Original manager retained authority to restore its roles.
  if ending in {Panic, CheckpointPanic}:
    instructions.add(@[0'u8]) # Actual terminal trap chooses the retained exceptional implication.
  if ending == HashReturn:
    instructions.add(registerImmediate(7, 196608))
    instructions.add(registerImmediate(8, 32)) # Normalized hash return must retain regular privilege changes.
  instructions.add(@[50'u8, 0])
  guestEnvelope(instructions, writable = payload)
proc assignProgram(): seq[byte] =
  ## Original assigner 99 changes only core zero; manager handoff must not replace its queue source.
  var payload = newSeq[byte](96)
  for index in 64..<96: payload[index] = byte(index) # Independently observable slot-two queue hash.
  guestEnvelope([registerImmediate(7, 0), registerImmediate(8, 196608),
    registerImmediate(9, 77), @[10'u8, 16], @[50'u8, 0]], writable = payload)
proc policy(pairs, original: int): AccumulationBatchLimits =
  ## Explicit exact wire/item ceilings cover original and selected manager C(12), including cardinality changes.
  result = batchPolicy()
  result.assignCores = ElementLimit(2)
  result.assignBytes = ByteLimit(5120+21+12*max(pairs, original))
  result.managerEntries = ElementLimit(max(pairs, original))
  result.managerBytes = ByteLimit(42+12*(pairs+original))
proc expected(fixture: BatchFixture, changed: bool, ending: Ending, pairs: int,
    subset = false): seq[StateEntry] =
  ## Literal whole-map bytes are an independent oracle for R and original-owner queue selection.
  let active = ending notin {Panic, Restore} and not subset
  var roles: seq[byte] = @[]
  roles.put(if active: uint64(high(uint32)) else: 42'u64, 4)
  roles.put(if active and changed: 88'u64 else: 77'u64, 4)
  roles.put(if active: 89'u64 else: 99'u64, 4)
  roles.put(if active: uint64(high(uint32))-1 else: 0'u64, 4)
  roles.put(if active: 17'u64 else: 0'u64, 4)
  roles.add(byte(if active: pairs else: 0))
  if active and pairs > 0:
    roles.put(42, 4)
    roles.put(0, 8)
  if active and pairs > 1:
    roles.put(uint64(high(uint32)), 4)
    roles.put(high(uint64), 8)
  result = @[]
  for entry in fixture.entries:
    var row = entry
    if array[31, byte](row.key) == array[31, byte](chapterKey(StateChapter(12))):
      row.value = roles # Use no codec or effect snapshot to construct posterior privilege bytes.
    if array[31, byte](row.key) == array[31, byte](chapterKey(StateChapter(2))):
      for offset in 64..<96: row.value[offset] = byte(offset) # Always use the original assigner's actual queue.
    for index in 0..<2:
      let service = ServiceIndex(if index == 0: 42 else: 99)
      if (index == 1 or not subset) and array[31, byte](row.key) == array[31, byte](
          chapterServiceKey(StateChapter(255), service)):
        var account = decodeServiceMetadata(entry.value, ByteLimit(89)).value.metadata
        account.balance = AccountBalance(if index == 0: 17 else: 31)
        row = serviceMetadataEntry(service, account, ByteLimit(
            89)).value # Independently known incoming credits remain atomic with global writes.
    result.add(row)
proc check(changed: bool, ending: Ending, pairs: int, reverse = false, original = 0) =
  ## Refusal never hashes or mutates callers; exact budgets publish literal complete-map roots and release every plan owner.
  let always = if original == 0: newSeq[AlwaysAccumulate]() else:
    @[AlwaysAccumulate(service: ServiceIndex(7), gas: PrivilegeGas(8))]
  let fixture = batchFixture(firstEnvelope = managerProgram(changed, ending, pairs),
    secondEnvelope = assignProgram(), manager = 42,
    assigners = @[ServiceIndex(99), ServiceIndex(99)], always = always, allowanceLimit = 6)
  let prior = fixture.state.snapshot.value
  let a = batchExecution(fixture, 0, parameters = parameters(), copyLimit = MemoryByteLimit(2560),
      allowanceLimit = 6)
  let b = batchExecution(fixture, 1, parameters = parameters(), copyLimit = MemoryByteLimit(2560),
      allowanceLimit = 6)
  assert a.error == AccumulationDispatchError.None and b.error == AccumulationDispatchError.None
  let context = normalizeAccumulationOutcome(a).value.outcomeContext.value
  assert context.effectInfo.value.hasPrivileges == (ending != Panic)
  var copied = context.effectInfo.value
  copied.hasPrivileges = false
  assert context.effectInfo.value.hasPrivileges == (ending != Panic), "copied provenance is read only"
  let activePairs = if ending in {Panic, Restore}: original else: pairs
  let runs = if reverse: @[b, a] else: @[a, b]
  let limits = policy(activePairs, original)
  failHash(3)
  let plan = prepareCompleteAccumulationBatch(fixture.inputs, prior, runs, [], HeaderSlot(128), limits).value
  assert plan.batchInfo.value.assignmentWrites == 2
  if ending != Panic:
    var short = limits
    short.managerBytes = ByteLimit(0)
    assert prepareCompleteAccumulationBatch(fixture.inputs, prior, runs, [], HeaderSlot(128),
        short).error == AccumulationBatchError.LimitExceeded
    short = limits
    short.managerBytes = ByteLimit(uint64(limits.managerBytes)-1)
    assert prepareCompleteAccumulationBatch(fixture.inputs, prior, runs, [], HeaderSlot(128),
        short).error == AccumulationBatchError.LimitExceeded
    if max(activePairs, original) > 0:
      short = limits
      short.managerEntries = ElementLimit(max(activePairs, original)-1)
      assert prepareCompleteAccumulationBatch(fixture.inputs, prior, runs, [], HeaderSlot(128),
          short).error == AccumulationBatchError.LimitExceeded
    short = limits
    short.assignBytes = ByteLimit(uint64(limits.assignBytes)-1)
    assert prepareCompleteAccumulationBatch(fixture.inputs, prior, runs, [], HeaderSlot(128),
        short).error == AccumulationBatchError.LimitExceeded
  assert hashCalls() == 0, "preparation and quota refusal hash nothing"
  failHash(0)
  var wide = limits
  wide.managerBytes = ByteLimit(high(uint64))
  wide.managerEntries = ElementLimit(high(uint64))
  assert prepareCompleteAccumulationBatch(fixture.inputs, prior, runs, [], HeaderSlot(128),
      wide).error == AccumulationBatchError.None
  let entries = expected(fixture, changed, ending, pairs)
  let wanted = stateTrieRoot(entries, integrationStoreLimits().trie).value
  for successful in [0, 2]:
    var caller = fixture.state
    hashAfter(cint(successful))
    let refused = applyAccumulationBatch(caller, plan)
    assert refused.error == AccumulationBatchError.StoreFailure and refused.storeError ==
        StateStoreError.BackendFailure
    failHash(0)
    assert sameStateSnapshot(caller.snapshot.value, prior), "failed hashing publishes nothing"
  var caller = fixture.state
  let published = applyAccumulationBatch(caller, plan).value
  assert array[32, byte](published.commitment.root) == array[32, byte](wanted.root), "literal full-map root"
  for entry in entries:
    assert published.lookup(entry.key).value.bytes == entry.value, "literal full-map entry"
  assert sameStateSnapshot(fixture.state.snapshot.value, prior), "source copy remains unchanged"
  failHash(3)
  assert applyAccumulationBatch(caller, plan).error == AccumulationBatchError.StaleState
  assert hashCalls() == 0
  failHash(0)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    let local = prepareCompleteAccumulationBatch(fixture.inputs, prior, runs, [], HeaderSlot(128), limits).value
    var private = fixture.state
    assert array[32, byte](applyAccumulationBatch(private, local).value.commitment.root) == array[
        32, byte](wanted.root)
  assert before == getOccupiedMem(), "manager publication plans release"
proc checkSubset() =
  ## An absent manager cannot donate its unexecuted role changes or allowance dictionary.
  let fixture = batchFixture(firstEnvelope = managerProgram(true, Halt, 2),
    secondEnvelope = assignProgram(), manager = 42, assigners = @[ServiceIndex(99), ServiceIndex(
        99)], allowanceLimit = 6)
  let b = batchExecution(fixture, 1, parameters = parameters(), copyLimit = MemoryByteLimit(2560),
      allowanceLimit = 6)
  let plan = prepareAccumulationBatch(fixture.inputs, fixture.state.snapshot.value, [b], HeaderSlot(
      128), policy(0, 0)).value
  var caller = fixture.state
  let published = applyAccumulationBatch(caller, plan).value
  for entry in expected(fixture, true, Halt, 2, subset = true):
    assert published.lookup(entry.key).value.bytes == entry.value, "absent manager retains original roles"
proc checkStoreLimit() =
  ## Hosts individually fit three writes, but the four-write combined candidate must retain inherited store limits.
  let fixture = batchFixture(writes = 3, firstEnvelope = managerProgram(true, Halt, 2),
    secondEnvelope = assignProgram(), manager = 42, assigners = @[ServiceIndex(99), ServiceIndex(
        99)], allowanceLimit = 6)
  let runs = @[batchExecution(fixture, 0, parameters = parameters(), copyLimit = MemoryByteLimit(
      2560), allowanceLimit = 6),
    batchExecution(fixture, 1, parameters = parameters(), copyLimit = MemoryByteLimit(2560),
        allowanceLimit = 6)]
  let plan = prepareCompleteAccumulationBatch(fixture.inputs, fixture.state.snapshot.value, runs, [
    ], HeaderSlot(128), policy(2, 0)).value
  var caller = fixture.state
  let refused = applyAccumulationBatch(caller, plan)
  assert refused.error == AccumulationBatchError.StoreFailure and refused.storeError ==
      StateStoreError.LimitExceeded
  assert sameStateSnapshot(caller.snapshot.value, fixture.state.snapshot.value)
proc checkManagerOnly() =
  ## A selected manager publishes C(12) even when no selected service assigned a queue.
  let fixture = batchFixture(firstEnvelope = managerProgram(true, Halt, 2),
    secondEnvelope = assignProgram(), manager = 42,
    assigners = @[ServiceIndex(99), ServiceIndex(99)], allowanceLimit = 6)
  let a = batchExecution(fixture, 0, parameters = parameters(),
    copyLimit = MemoryByteLimit(2560), allowanceLimit = 6)
  let prior = fixture.state.snapshot.value
  let plan = prepareAccumulationBatch(fixture.inputs, prior, [a], HeaderSlot(128), policy(2, 0)).value
  var entries = expected(fixture, true, Halt, 2)
  for index in 0..<entries.len:
    if array[31, byte](entries[index].key) == array[31, byte](chapterKey(StateChapter(2))) or
        array[31, byte](entries[index].key) == array[31, byte](chapterServiceKey(StateChapter(255),
            ServiceIndex(99))):
      entries[index].value = prior.lookup(entries[
          index].key).value.bytes # The absent assigner changes neither queues nor metadata.
  let wanted = stateTrieRoot(entries, integrationStoreLimits().trie).value
  var caller = fixture.state
  let published = applyAccumulationBatch(caller, plan).value
  assert array[32, byte](published.commitment.root) == array[32, byte](wanted.root)
proc checkStagingGate() =
  ## A real designate between two successful bless calls retains its independent staging publication budget.
  let program = guestEnvelope([registerImmediate(7, 42), registerImmediate(8, 196608),
    registerImmediate(9, 42), registerImmediate(10, 0), registerImmediate(11, 0),
    registerImmediate(12, 0), @[10'u8, 15], registerImmediate(7, 196608),
    registerImmediate(8, 6), @[10'u8, 17], registerImmediate(7, 42),
    registerImmediate(8, 196608), registerImmediate(9, 0), @[10'u8, 15], @[50'u8, 0]],
    writable = @[99'u8, 0, 0, 0, 99, 0, 0, 0])
  let fixture = batchFixture(firstEnvelope = program, secondEnvelope = assignProgram(),
    manager = 42, assigners = @[ServiceIndex(99), ServiceIndex(99)])
  let a = batchExecution(fixture, 0, parameters = parameters(), copyLimit = MemoryByteLimit(2560))
  let b = batchExecution(fixture, 1, parameters = parameters(), copyLimit = MemoryByteLimit(2560))
  assert a.error == AccumulationDispatchError.None
  let selected = normalizeAccumulationOutcome(a).value.outcomeContext.value
  assert selected.effectInfo.value.hasPrivileges
  assert selected.effectInfo.value.hasStaging
  assert selected.effectAccountScope.value == AccumulationAccountScope.Initial
  assert prepareCompleteAccumulationBatch(fixture.inputs, fixture.state.snapshot.value, [a, b], [],
    HeaderSlot(128), policy(0, 0)).error == AccumulationBatchError.LimitExceeded
proc main() =
  ## Exercise manager changes, R fallback, terminal rollback, restored-equal occurrence, growth/shrinkage and independent execution order.
  check(true, Halt, 2)
  check(false, Halt, 2)
  check(true, Halt, 2, reverse = true)
  check(true, Panic, 2)
  check(true, CheckpointPanic, 2)
  check(true, Restore, 2)
  check(true, HashReturn, 2)
  check(true, Halt, 0, original = 1)
  checkSubset()
  checkStoreLimit()
  checkManagerOnly()
  checkStagingGate()
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    let source = batchFixture()
    assert source.entries.len > 0 # Frozen backing owners release independently of the heavier per-case merge cycles.
  let after = getOccupiedMem()
  assert before == after, "fixture ARC release"
  recordArcRelease("accumulation_manager_publication", 1000, before, after)
  echo "Accumulation manager publication passed"
  echo "ARC_RELEASE cycles=1000 unchanged"
main()
