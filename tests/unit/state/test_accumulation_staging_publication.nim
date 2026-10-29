# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "accumulation_staging_publication_arc_release"}

## Real designate/bless executions prove original-delegator roster selection, bounded work and atomic whole-map publication.

import std/[assertions, syncio]
import ../../../src/state/accumulation/[batch as accumulation_batch,
    context as accumulation_context, effects as accumulation_effects,
    dispatch as accumulation_dispatch, outcome as accumulation_outcome]
import ../../../src/state/store
import ../../../src/codec/[bounded, composite, header]
import ../../../src/codec/state/[accounts as state_accounts, layout as state_layout,
    safrole as state_safrole, trie as state_trie]
import ../../../src/chain/parameters
import ../../../src/pvm/machine
import ../../support/[accumulation_batch_context, pvm_accumulation_context,
  pvm_accumulation_program, accumulation_provision_integration, arc_evidence]

type Ending = enum ## Genuine terminal branches select regular, checkpoint or initial staging snapshots.
  Halt, Panic, CheckpointPanic, Restore, HashReturn
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
proc hashAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
proc parameters(): Parameters =
  ## Match the three-core host profile without charging unrelated fixture deposits.
  var wire = encodeParameters(pvmParameters())
  for index in 0..<24: wire[index] = 0 # Tiny balances isolate staging effects from storage funding.
  wire[24] = 3
  wire[25] = 0
  decodeParameters(wire).value
proc payload(count: int, seed: int): seq[byte] =
  ## Independently vary every opaque record field and ordinal while keeping all arithmetic small.
  result = newSeq[byte](count*336)
  for index in 0..<result.len:
    result[index] = byte((index*7+seed) mod 256) # All four opaque fields and duplicate records retain their wire order.
proc designateProgram(count, original: int, ending: Ending): seq[byte] =
  ## The real host reads complete mapped memory; zero-padded memory after the payload can restore the original roster.
  var instructions = @[registerImmediate(7, 196608), registerImmediate(8, uint64(count)), @[10'u8, 18]]
  if ending == CheckpointPanic:
    instructions.add(@[10'u8, 19]) # Freeze roster and provenance in the exceptional implication.
  if ending == Restore:
    instructions.add(registerImmediate(7, uint64(196608+336*count)))
    instructions.add(registerImmediate(8, uint64(original)))
    instructions.add(@[10'u8, 18]) # Both real successful calls remain observable even when final C(7) equals the original bytes.
  if ending in {Panic, CheckpointPanic}:
    instructions.add(@[0'u8]) # A genuine guest trap selects the exceptional snapshot.
  if ending == HashReturn:
    instructions.add(registerImmediate(7, 196608))
    instructions.add(registerImmediate(8, 32)) # Hash-return normalization retains the regular staging mutation.
  instructions.add(@[50'u8, 0])
  guestEnvelope(instructions, writable = payload(count, 41))
proc managerProgram(): seq[byte] =
  ## The original manager grants itself delegation and designates a competing roster in its independent execution.
  var bytes = newSeq[byte](12)
  for octet in payload(9, 7): bytes.add(octet) # Three zero assigners precede a different nine-validator roster.
  guestEnvelope([registerImmediate(7, 42), registerImmediate(8, 196608),
    registerImmediate(9, 42), registerImmediate(10, 0), registerImmediate(11, 0),
    registerImmediate(12, 0), @[10'u8, 16], registerImmediate(7, 196620),
    registerImmediate(8, 9), @[10'u8, 18], @[50'u8, 0]], writable = bytes)
proc policy(count, original: int): AccumulationBatchLimits =
  ## Exact aggregate original/output C(7) bytes are independent of the manager/queue publication policy.
  result = batchPolicy()
  result.stagingValidators = ElementLimit(max(count, original))
  result.stagingBytes = ByteLimit(2+336*(count+original))
  result.assignCores = ElementLimit(3)
  result.assignBytes = ByteLimit(7705)
  result.managerBytes = ByteLimit(50)
proc fixture(count, original: int, ending: Ending, handoff: bool, writes = 64'u64): BatchFixture =
  ## Both independent guests share the genuine immutable three-core source and original delegator 99.
  batchFixture(firstEnvelope = (if handoff: managerProgram() else: guestEnvelope([@[50'u8, 0]])),
    secondEnvelope = designateProgram(count, original, ending), manager = 42,
    delegator = 99, cores = 3, stagingCount = original, writes = writes)
proc run(source: BatchFixture, index: uint64, original: int): AccumulationDispatchResult =
  ## Every terminal observation comes from the real engine with explicit core/population and byte policies.
  batchExecution(source, index, parameters = parameters(), copyLimit = MemoryByteLimit(3024),
    cores = 3, stagingCount = original, codeBytes = 4096, preimageBytes = 4096)
proc expected(source: BatchFixture, count, original: int, ending: Ending,
    handoff: bool, subset = 0): seq[StateEntry] =
  ## Literal C(7), C(12) role offsets and independent incoming credits define a full-map oracle.
  let retained = ending in {Panic, Restore} or subset == 1
  let selected = if retained: original else: count
  var roster = @[byte(selected)]
  for octet in (if retained: newSeq[byte](336*selected) else: payload(selected, 41)):
    roster.add(octet) # All small valid populations use one compact count byte.
  result = @[]
  for entry in source.entries:
    var row = entry
    if array[31, byte](entry.key) == array[31, byte](chapterKey(StateChapter(7))):
      row.value = roster # The manager's competing seed-seven roster is never the selected source.
    if handoff and subset != 2 and array[31, byte](entry.key) == array[31, byte](chapterKey(
        StateChapter(12))):
      row.value[16] = 42 # E4 manager + three E4 assigners precede delegator; every other original byte is unchanged.
    for index in 0..<2:
      let service = ServiceIndex(if index == 0: 42 else: 99)
      if (subset == 0 or subset == index+1) and array[31, byte](entry.key) == array[31, byte](
          chapterServiceKey(StateChapter(255), service)):
        var account = decodeServiceMetadata(entry.value, ByteLimit(
            ServiceMetadataBytes)).value.metadata
        account.balance = AccountBalance(if index == 0: 17 else: 31)
        row = serviceMetadataEntry(service, account, ByteLimit(
            ServiceMetadataBytes)).value # A subset receives only its actual invoking service credit.
    result.add(row)
proc check(count, original: int, ending: Ending, handoff = false, reverse = false) =
  ## Exact budgets publish complete-map roots; refusals, hash failures and stale callers preserve all prior owners.
  let source = fixture(count, original, ending, handoff)
  let prior = source.state.snapshot.value
  let a = run(source, 0, original)
  let b = run(source, 1, original)
  assert a.error == AccumulationDispatchError.None and b.error == AccumulationDispatchError.None
  let selected = normalizeAccumulationOutcome(b).value.outcomeContext.value
  assert selected.effectInfo.value.hasStaging == (ending != Panic)
  var copied = selected.effectInfo.value
  copied.hasStaging = false
  assert selected.effectInfo.value.hasStaging == (ending != Panic), "copied provenance cannot change its owner"
  let active = ending != Panic or handoff
  let finalCount = if ending in {Panic, Restore}: original else: count
  let limits = policy(finalCount, original)
  let runs = if reverse: @[b, a] else: @[a, b]
  failHash(3)
  let plan = prepareCompleteAccumulationBatch(source.inputs, prior, runs, [], HeaderSlot(128), limits).value
  assert plan.batchInfo.value.stagingWrites == (if active: 1 else: 0)
  assert plan.batchInfo.value.assignmentWrites == (if handoff: 2 else: 0)
  if active:
    for kind in 0..<3:
      var short = limits
      if kind == 0: short.stagingBytes = ByteLimit(0) # Default-zero preserves the publication gate.
      if kind == 1: short.stagingBytes = ByteLimit(uint64(limits.stagingBytes)-1) # Aggregate wire bound.
      if kind == 2: short.stagingValidators = ElementLimit(max(finalCount,
          original)-1) # Source and selected domains both consume policy.
      assert prepareCompleteAccumulationBatch(source.inputs, prior, runs, [], HeaderSlot(128),
          short).error == AccumulationBatchError.LimitExceeded
  assert hashCalls() == 0, "preparation and quota refusal hash nothing"
  failHash(0)
  var wide = limits
  wide.stagingValidators = ElementLimit(high(uint64))
  wide.stagingBytes = ByteLimit(high(uint64))
  assert prepareCompleteAccumulationBatch(source.inputs, prior, runs, [], HeaderSlot(128),
      wide).error == AccumulationBatchError.None
  let entries = expected(source, count, original, ending, handoff)
  let wanted = stateTrieRoot(entries, integrationStoreLimits().trie).value
  for successful in [0, 2]:
    var caller = source.state
    hashAfter(cint(successful))
    let refused = applyAccumulationBatch(caller, plan)
    assert refused.error == AccumulationBatchError.StoreFailure and refused.storeError ==
        StateStoreError.BackendFailure
    failHash(0)
    assert sameStateSnapshot(caller.snapshot.value, prior), "failed hashing publishes no account or chapter writes"
  var caller = source.state
  let published = applyAccumulationBatch(caller, plan).value
  assert array[32, byte](published.commitment.root) == array[32, byte](wanted.root)
  for entry in entries:
    assert published.lookup(entry.key).value.bytes == entry.value, "literal complete-map entry"
  assert sameStateSnapshot(source.state.snapshot.value, prior), "source aliases retain their prior version"
  if finalCount != original:
    var next = source
    next.state = forkStateStore(published).value # Capture the real published successor without replacing its original input owner.
    let resumed = run(next, 0, original)
    assert resumed.error == AccumulationDispatchError.None, "successor staging count does not replace the active profile"
    let captured = resumed.effects.effectsSource.value.initialContext(
        AccumulationDimension.Regular).value
    assert captured.contextStaging.value.validatorCount.value ==
        finalCount # Both growth and shrinkage survive genuine next-invocation capture.

  failHash(3)
  assert applyAccumulationBatch(caller, plan).error == AccumulationBatchError.StaleState
  assert hashCalls() == 0
  failHash(0)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    let local = prepareCompleteAccumulationBatch(source.inputs, prior, runs, [], HeaderSlot(128), limits).value
    var private = source.state
    assert array[32, byte](applyAccumulationBatch(private, local).value.commitment.root) == array[
        32, byte](wanted.root)
  assert before == getOccupiedMem(), "staging plan/publication ARC release"
proc checkSubsets() =
  ## Absent original delegators retain C(7); absent managers cannot donate their independently executed handoff.
  let source = fixture(9, 6, Halt, true)
  for subset in 1..2:
    let run = run(source, uint64(subset-1), 6)
    let count = if subset == 1: 6 else: 9
    let plan = prepareAccumulationBatch(source.inputs, source.state.snapshot.value, [run],
        HeaderSlot(128), policy(count, 6)).value
    var caller = source.state
    let published = applyAccumulationBatch(caller, plan).value
    for entry in expected(source, 9, 6, Halt, true, subset):
      assert published.lookup(entry.key).value.bytes == entry.value, "absent authority retains its own component"
proc checkStoreLimit() =
  ## Individual one-key host writes fit, while the five-write account/global batch honors inherited limits.
  let source = fixture(9, 6, Halt, true, writes = 4)
  let runs = @[run(source, 0, 6), run(source, 1, 6)]
  let plan = prepareCompleteAccumulationBatch(source.inputs, source.state.snapshot.value, runs, [],
      HeaderSlot(128), policy(9, 6)).value
  var caller = source.state
  let refused = applyAccumulationBatch(caller, plan)
  assert refused.error == AccumulationBatchError.StoreFailure and refused.storeError ==
      StateStoreError.LimitExceeded
  assert sameStateSnapshot(caller.snapshot.value, source.state.snapshot.value)
proc checkUnsupported() =
  ## An untracked storage write followed by designate cannot erase unsupported account ancestry.
  let code = guestEnvelope([@[51'u8, 7, 255], registerImmediate(8, 196608), registerImmediate(9, 1),
    registerImmediate(10, 196609), registerImmediate(11, 1), @[10'u8, 5],
    registerImmediate(7, 196608), registerImmediate(8, 9), @[10'u8, 18], @[50'u8, 0]],
    writable = payload(9, 41))
  let source = batchFixture(firstEnvelope = code, secondEnvelope = guestEnvelope([@[50'u8, 0]]),
    cores = 3, delegator = 42)
  let a = run(source, 0, 6)
  let b = run(source, 1, 6)
  assert a.error == AccumulationDispatchError.None
  let selected = normalizeAccumulationOutcome(a).value.outcomeContext.value
  assert selected.effectInfo.value.hasStaging
  assert selected.effectAccountScope.value == AccumulationAccountScope.Unsupported
  assert prepareCompleteAccumulationBatch(source.inputs, source.state.snapshot.value, [a, b], [],
      HeaderSlot(128), policy(9, 6)).error == AccumulationBatchError.UnsupportedAccountEffects
proc main() =
  ## Exercise growth/shrinkage, original-delegator authority, terminal branches and restored-equal occurrence.
  check(9, 6, Halt)
  check(6, 9, Halt)
  check(9, 6, Halt, handoff = true)
  check(9, 6, Halt, handoff = true, reverse = true)
  check(9, 6, Panic)
  check(9, 6, Panic, handoff = true)
  check(9, 6, CheckpointPanic)
  check(9, 6, Restore)
  check(9, 6, HashReturn)
  checkSubsets()
  checkStoreLimit()
  checkUnsupported()
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    let source = batchFixture()
    assert source.entries.len > 0 # Repeated backing-owner capture releases independently of per-case merge loops.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("accumulation_staging_publication", 1000, before, after)
  echo "Accumulation staging publication passed"
  echo "ARC_RELEASE cycles=1000 unchanged"
main()
