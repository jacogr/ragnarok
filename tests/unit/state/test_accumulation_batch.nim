# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "accumulation_batch_arc_release"}

## Common-source executed subsets merge credited metadata before selected provisions with atomic publication.
## Authored complete-map roots, source substitution, stale plans and both private-phase refusals retain strict contracts.

import std/[assertions, syncio]
import ../../../src/state/[accumulation_batch, accumulation_inputs, accumulation_service,
  accumulation_dispatch, accumulation_outcome, accumulation_provisions,
  accumulation_terminal_provisions, accumulation_effects, store]
import ../../../src/codec/[bounded, composite, header, state_accounts, state_service_values,
  state_layout, state_trie]
import ../../../src/crypto/primitives
import ../../support/[accumulation_batch_context, accumulation_provision_integration,
  pvm_accumulation_provision, arc_evidence]

# Inject backend refusal only after genuine source and execution owners exist.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
# Permit a complete account-root phase before refusing the next provision-root hash.
proc hashAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
# Count actual backend work to prove early provenance/stale gates precede hashing.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}

# Inspect the existing complete-map commitment without hashing or reconstructing partial accounts.
proc root(state: StateStore): array[32, byte] = array[32, byte](
    state.snapshot.value.commitment.root)

# Replace only named metadata/history values; code/storage/opaque chapters remain in the full expected map.
proc expectedRows(fixture: BatchFixture, first = true, second = true,
    providedSecond = true): seq[StateEntry] =
  result = @[]
  for entry in fixture.entries: result.add(StateEntry(key: entry.key, value: entry.value))
  for ordinal, service in [42'u32, 99'u32]:
    let credited = (if ordinal == 0: first else: second)
    let accountKey = chapterServiceKey(StateChapter(255), ServiceIndex(service))
    for index in 0..<result.len:
      if credited and array[31, byte](result[index].key) == array[31, byte](accountKey):
        var metadata = decodeServiceMetadata(result[index].value, ByteLimit(
            ServiceMetadataBytes)).value.metadata
        metadata.balance = AccountBalance(if ordinal ==
            0: 17 else: 31) # Literal original + distinct incoming transfers.
        result[index] = serviceMetadataEntry(ServiceIndex(service), metadata, ByteLimit(
            ServiceMetadataBytes)).value
    if ordinal == 0 or providedSecond:
      let bytes = (if ordinal == 0: @[73'u8] else: @[81'u8])
      let request = provisionRequest(service, bytes)
      for index in 0..<result.len:
        if array[31, byte](result[index].key) == array[31, byte](request.key):
          result[index].value = @[1'u8, 128, 0, 0, 0] # Literal singleton timestamp at invocation slot 128.
      result.add(servicePreimageEntry(ServiceIndex(service),
        ServicePreimageHash(array[32, byte](blake2b256(bytes).value)), bytes,
        ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(1))).value)

let fixture = batchFixture()
let prior = fixture.state.snapshot.value
let invalidExecution = default(AccumulationDispatchResult)
let first = batchExecution(fixture, 0)
let second = batchExecution(fixture, 1)
assert first.error == AccumulationDispatchError.None and second.error ==
    AccumulationDispatchError.None
let policy = batchPolicy()
let plan = prepareAccumulationBatch(fixture.inputs, prior, [first, second], HeaderSlot(128), policy).value
let expected = newStateStore(expectedRows(fixture), integrationStoreLimits()).value
let facts = plan.batchInfo.value
assert facts.executions == 2 and facts.accountWrites == 2
assert facts.terminal.provisions.inputItems == 4 and facts.terminal.provisions.items == 2
assert uint32(facts.terminal.slot) == 128
assert uint32(plan.batchOutcomeAt(AccumulationProvisionSourceIndex(
    0)).value.outcomeInfo.value.service) == 42
assert uint32(plan.batchOutcomeAt(AccumulationProvisionSourceIndex(
    1)).value.outcomeInfo.value.service) == 99
assert plan.batchOutcomeAt(AccumulationProvisionSourceIndex(high(uint64))).error ==
    AccumulationBatchError.InvalidIndex
let defaultPlan = default(PreparedAccumulationBatch)
assert defaultPlan.batchInfo.error == AccumulationBatchError.Uninitialized
assert defaultPlan.batchOutcomeAt(AccumulationProvisionSourceIndex(0)).error ==
    AccumulationBatchError.Uninitialized
let defaultResult = default(AccumulationBatchResult[PreparedAccumulationBatch])
assert defaultResult.error == AccumulationBatchError.Uninitialized
assert not sameStateSnapshot(default(StateStoreSnapshot), default(StateStoreSnapshot))
assert sameStateSnapshot(prior, fixture.state.snapshot.value)
assert not sameStateSnapshot(prior, default(StateStoreSnapshot))
assert sameAccumulationInputs(fixture.inputs, fixture.inputs)
assert not sameAccumulationInputs(fixture.inputs, default(PreparedAccumulationInputs))
assert not sameAccumulationInputs(default(PreparedAccumulationInputs), default(PreparedAccumulationInputs))
assert not serviceSourceMatches(default(PreparedAccumulationService), fixture.inputs, prior)
var applied = fixture.state
assert applyAccumulationBatch(applied, plan).error == AccumulationBatchError.None
assert root(applied) == root(expected)
assert root(fixture.state) != root(applied) # Shared immutable prior and original caller handles remain unchanged.
let published = applied.snapshot.value
let reversed = prepareAccumulationBatch(fixture.inputs, prior, [second, first], HeaderSlot(128), policy).value
var permuted = fixture.state
assert applyAccumulationBatch(permuted, reversed).error == AccumulationBatchError.None
assert root(permuted) == root(expected)
assert uint32(reversed.batchOutcomeAt(AccumulationProvisionSourceIndex(
    0)).value.outcomeInfo.value.service) == 99
let subset = prepareAccumulationBatch(fixture.inputs, prior, [first], HeaderSlot(128), policy).value
let subsetExpected = newStateStore(expectedRows(fixture, second = false), integrationStoreLimits()).value
var subsetState = fixture.state
assert applyAccumulationBatch(subsetState, subset).error == AccumulationBatchError.None
assert root(subsetState) == root(subsetExpected) # Noninvoked service receives provisions but no incoming credit from this subset.
let panicFixture = batchFixture(BatchEnding.Panic, BatchEnding.Panic)
let panicPlan = prepareAccumulationBatch(panicFixture.inputs, panicFixture.state.snapshot.value,
  [batchExecution(panicFixture, 0), batchExecution(panicFixture, 1)], HeaderSlot(128), policy).value
let panicExpected = newStateStore(expectedRows(panicFixture, providedSecond = false),
    integrationStoreLimits()).value
var panicState = panicFixture.state
assert applyAccumulationBatch(panicState, panicPlan).error == AccumulationBatchError.None
assert root(panicState) == root(panicExpected) # Incoming credit predates checkpoint rollback; only the later provision is discarded.
let noCreditFixture = batchFixture(incoming = false)
let noCredit = prepareAccumulationBatch(noCreditFixture.inputs,
  noCreditFixture.state.snapshot.value,
  [batchExecution(noCreditFixture, 0), batchExecution(noCreditFixture, 1)], HeaderSlot(128),
      batchPolicy(accounts = 0)).value
assert noCredit.batchInfo.value.accountWrites == 0
let noCreditExpected = newStateStore(expectedRows(noCreditFixture, first = false, second = false),
    integrationStoreLimits()).value
var noCreditState = noCreditFixture.state
assert applyAccumulationBatch(noCreditState, noCredit).error == AccumulationBatchError.None
assert root(noCreditState) == root(noCreditExpected)
var foreignInputs = fixture
foreignInputs.inputs = batchInputSet()
let foreignInputExecution = batchExecution(foreignInputs, 1)
var foreignPrior = fixture
foreignPrior.state = newStateStore(fixture.entries, integrationStoreLimits()).value
let foreignPriorExecution = batchExecution(foreignPrior, 1)
assert root(foreignPrior.state) == root(fixture.state)
assert not sameStateSnapshot(foreignPrior.state.snapshot.value, prior)
assert not sameAccumulationInputs(foreignInputs.inputs, fixture.inputs)
let wrongSlot = batchExecution(fixture, 1, HeaderSlot(129))
let hashFixture = batchFixture(second = BatchEnding.HashReturn)
let hashExecutions = @[batchExecution(hashFixture, 0), batchExecution(hashFixture, 1)]
failHash(1)
assert prepareAccumulationBatch(default(PreparedAccumulationInputs), prior, [], HeaderSlot(128),
    policy).error == AccumulationBatchError.InvalidInputs
assert prepareAccumulationBatch(fixture.inputs, default(StateStoreSnapshot), [], HeaderSlot(128),
    policy).error == AccumulationBatchError.InvalidState
for foreign in [foreignInputExecution, foreignPriorExecution]:
  assert prepareAccumulationBatch(fixture.inputs, prior, [first, foreign], HeaderSlot(128),
      policy).error == AccumulationBatchError.SourceMismatch
assert prepareAccumulationBatch(fixture.inputs, prior, [first, first], HeaderSlot(128),
    policy).error == AccumulationBatchError.DuplicateService
assert prepareAccumulationBatch(fixture.inputs, prior, [first, invalidExecution], HeaderSlot(128),
    policy).error == AccumulationBatchError.InvalidExecution
assert prepareAccumulationBatch(fixture.inputs, prior, [first, second], HeaderSlot(128),
    batchPolicy(accounts = 1)).error == AccumulationBatchError.LimitExceeded
let invalidSlot = prepareAccumulationBatch(fixture.inputs, prior, [first, wrongSlot], HeaderSlot(
    128), policy)
assert invalidSlot.terminalError == AccumulationTerminalProvisionError.InvalidSlot
assert hashCalls() == 0
let backend = prepareAccumulationBatch(fixture.inputs, prior, [first, second], HeaderSlot(128), policy)
assert backend.provisionError == AccumulationProvisionError.BackendFailure
failHash(0)
# Adopted regular hash-return provisions flow through the exact common-source batch proof.
let hashExpected = newStateStore(expectedRows(hashFixture), integrationStoreLimits()).value
for reverse in [false, true]:
  let ordered = if reverse: @[hashExecutions[1], hashExecutions[0]] else: hashExecutions
  let selected = prepareCompleteAccumulationBatch(hashFixture.inputs,
    hashFixture.state.snapshot.value,
    ordered, [], HeaderSlot(128), policy).value
  let index = if reverse: 0'u64 else: 1'u64
  let info = selected.batchOutcomeAt(AccumulationProvisionSourceIndex(
      index)).value.outcomeInfo.value
  assert info.hasYield and info.provisions == 2, "batch keeps the hash-return service's regular provision set"
  var state = hashFixture.state
  discard applyAccumulationBatch(state, selected).value
  assert root(state) == root(hashExpected), "both execution orders publish the same literal credits and fulfilled requests"
# Calibrate the hash-return account phase independently before faulting each private publication phase.
let hashPlan = prepareCompleteAccumulationBatch(hashFixture.inputs,
  hashFixture.state.snapshot.value,
  hashExecutions, [], HeaderSlot(128), policy).value
var hashCredited = hashFixture.state
var hashCreditWrites: seq[StateWrite] = @[]
for entry in expectedRows(hashFixture):
  for service in [42'u32, 99'u32]:
    if array[31, byte](entry.key) == array[31, byte](chapterServiceKey(StateChapter(255),
        ServiceIndex(service))):
      hashCreditWrites.add(StateWrite(key: entry.key, kind: StateWriteKind.Put, value: entry.value))
failHash(0)
discard hashCredited.apply(hashCreditWrites).value
let hashAccountHashes = hashCalls()
assert hashAccountHashes > 0
for allowance in [0.cint, hashAccountHashes]:
  var state = hashFixture.state
  let before = state.snapshot.value
  hashAfter(allowance)
  let refused = applyAccumulationBatch(state, hashPlan)
  if allowance == 0:
    assert refused.storeError == StateStoreError.BackendFailure, "early hash-return account phase failure is atomic"
  else:
    assert refused.provisionError == AccumulationProvisionError.BackendFailure, "late hash-return provision phase failure discards credited candidate"
  failHash(0)
  assert sameStateSnapshot(state.snapshot.value, before), "no credit, hash-return provision or candidate root escapes either refusal"
let empty = prepareAccumulationBatch(fixture.inputs, prior, [], HeaderSlot(7), batchPolicy(
    accounts = 0)).value
var emptyState = fixture.state
failHash(1)
assert applyAccumulationBatch(emptyState, empty).error == AccumulationBatchError.None
assert sameStateSnapshot(emptyState.snapshot.value, prior)
assert applyAccumulationBatch(applied, plan).error == AccumulationBatchError.StaleState
assert sameStateSnapshot(applied.snapshot.value, published)
assert applyAccumulationBatch(foreignPrior.state, plan).error == AccumulationBatchError.StaleState
assert hashCalls() == 0 # No work is repeated for empty or stale publication attempts.
failHash(0)
var changedState = fixture.state
discard changedState.apply([StateWrite(key: chapterKey(StateChapter(250)), kind: StateWriteKind.Put,
    value: @[9'u8])]).value
let changedSnapshot = changedState.snapshot.value
assert applyAccumulationBatch(changedState, plan).error == AccumulationBatchError.StaleState
assert sameStateSnapshot(changedState.snapshot.value, changedSnapshot)
var invalidState: StateStore
assert applyAccumulationBatch(invalidState, plan).error == AccumulationBatchError.InvalidState
assert applyAccumulationBatch(applied, defaultPlan).error == AccumulationBatchError.Uninitialized
# Inherited limits can refuse either phase; even a fully merged private credit map must be discarded.
for writeLimit in [1'u64, 2]:
  let limitedFixture = batchFixture(writes = writeLimit)
  let limitedPlan = prepareAccumulationBatch(limitedFixture.inputs,
    limitedFixture.state.snapshot.value,
    [batchExecution(limitedFixture, 0), batchExecution(limitedFixture, 1)], HeaderSlot(128), policy).value
  var state = limitedFixture.state
  let before = state.snapshot.value
  let result = applyAccumulationBatch(state, limitedPlan)
  if writeLimit == 1:
    assert result.storeError == StateStoreError.LimitExceeded
  else:
    assert result.provisionError == AccumulationProvisionError.LimitExceeded
  assert sameStateSnapshot(state.snapshot.value, before)
# Measure only the independent literal account phase to place a fault after it, before provision publication.
var credited = fixture.state
var creditWrites: seq[StateWrite] = @[]
for entry in expectedRows(fixture):
  for service in [42'u32, 99'u32]:
    if array[31, byte](entry.key) == array[31, byte](chapterServiceKey(StateChapter(255),
        ServiceIndex(service))):
      creditWrites.add(StateWrite(key: entry.key, kind: StateWriteKind.Put, value: entry.value))
failHash(0)
discard credited.apply(creditWrites).value
let accountHashes = hashCalls()
assert accountHashes > 0
failHash(0)
for allowance in [0.cint, accountHashes]:
  var state = fixture.state
  let before = state.snapshot.value
  hashAfter(allowance)
  let refused = applyAccumulationBatch(state, plan)
  if allowance == 0:
    assert refused.storeError == StateStoreError.BackendFailure
  else:
    assert refused.provisionError == AccumulationProvisionError.BackendFailure
  assert sameStateSnapshot(state.snapshot.value, before)
  failHash(0)
var retained: PreparedAccumulationBatch
var detachedState: StateStore
var detachedExpected = default(StateStore)
block:
  let source = batchFixture(second = BatchEnding.HashReturn)
  var executions = @[batchExecution(source, 0), batchExecution(source, 1)]
  retained = prepareAccumulationBatch(source.inputs, source.state.snapshot.value, executions,
      HeaderSlot(128), policy).value
  detachedState = source.state
  detachedExpected = newStateStore(expectedRows(source), integrationStoreLimits()).value
  executions[0] = default(AccumulationDispatchResult)
  executions.setLen(0) # All original local input/execution handles can be released independently.
var copied = retained.batchInfo.value
copied.accountWrites = 0
copied.terminal.slot = HeaderSlot(7)
assert retained.batchInfo.value.accountWrites == 2
assert uint32(retained.batchInfo.value.terminal.slot) == 128
assert applyAccumulationBatch(detachedState, retained).error == AccumulationBatchError.None
assert root(detachedState) == root(detachedExpected)
let detachedOutcome = retained.batchOutcomeAt(AccumulationProvisionSourceIndex(1)).value
let detachedProvision = detachedOutcome.outcomeContext.value.effectProvisionAt(
    AccumulationProvisionIndex(1)).value
assert detachedProvision.copyProvisionBytes.value == @[81'u8],
  "detached hash-return outcome retains regular provision bytes after all caller execution owners leave scope"
when declared(effectAccounts):
  # Exercise the actual sibling PVM write API when present, never a forged effects/machine certificate.
  for ending in [BatchEnding.StorageHalt, BatchEnding.StorageCheckpointPanic]:
    let written = batchFixture(first = ending)
    let a = batchExecution(written, 0)
    let b = batchExecution(written, 1)
    assert a.error == AccumulationDispatchError.None and b.error == AccumulationDispatchError.None
    let refused = prepareAccumulationBatch(written.inputs, written.state.snapshot.value,
      [a, b], HeaderSlot(128), policy)
    assert refused.error == AccumulationBatchError.UnsupportedAccountEffects
  let rolled = batchFixture(first = BatchEnding.StoragePanic)
  let rolledPlan = prepareAccumulationBatch(rolled.inputs, rolled.state.snapshot.value,
    [batchExecution(rolled, 0), batchExecution(rolled, 1)], HeaderSlot(128), policy).value
  var rolledState = rolled.state
  let rolledExpected = newStateStore(expectedRows(rolled), integrationStoreLimits()).value
  assert applyAccumulationBatch(rolledState, rolledPlan).error == AccumulationBatchError.None
  assert root(rolledState) == root(rolledExpected) # An uncheckpointed regular write is correctly discarded by terminal selection.
let before = getOccupiedMem()
for iteration in 0..<1000:
  # Repeated preparation, late private-phase refusal, success and stale retry release all candidate owners.
  let prepared = prepareAccumulationBatch(fixture.inputs, prior, [first, second], HeaderSlot(128), policy).value
  var state = fixture.state
  hashAfter(accountHashes)
  assert applyAccumulationBatch(state, prepared).provisionError ==
      AccumulationProvisionError.BackendFailure
  assert sameStateSnapshot(state.snapshot.value, prior)
  failHash(0)
  assert applyAccumulationBatch(state, prepared).error == AccumulationBatchError.None
  assert root(state) == root(expected)
  failHash(1)
  assert applyAccumulationBatch(state, prepared).error == AccumulationBatchError.StaleState
  assert hashCalls() == 0
  failHash(0)
  let selected = prepareCompleteAccumulationBatch(hashFixture.inputs,
    hashFixture.state.snapshot.value,
    hashExecutions, [], HeaderSlot(128), policy).value
  var hashState = hashFixture.state
  discard applyAccumulationBatch(hashState, selected).value
  assert root(hashState) == root(hashExpected), "fresh hash-return batch/yield/provision owners release every cycle"
let after = getOccupiedMem()
assert before == after
recordArcRelease("accumulation_batch", 1000, before, after)
echo "Accumulation batch state passed"
echo "ARC_RELEASE cycles=1000 unchanged"
