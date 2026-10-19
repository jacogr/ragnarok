# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "accumulation_complete_batch_arc_release"}

## Complete input coverage merges certified skipped credits and actual execution effects atomically.

import std/[assertions, syncio]
import ../../../src/state/[accumulation_batch, accumulation_inputs, accumulation_service,
  accumulation_queue, accumulation_operands,
  accumulation_skip, accumulation_dispatch, accumulation_outcome, accumulation_provisions, store]
import ../../../src/codec/[bounded, composite, header, state_accounts, state_service_values,
  state_layout, state_trie, state_workqueues, assurances]
import ../../../src/crypto/primitives
import ../../support/[accumulation_batch_context, accumulation_provision_integration,
  pvm_accumulation_provision, arc_evidence]

# Inject failures after genuine resolution and observe hash-free early coverage/provenance checks.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
proc hashAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}

# Choose an independently authored missing or malformed code preimage; oversized uses the original code.
type CodeCase = enum Missing, Malformed, Oversized

# Remove code blobs without disturbing metadata, storage, outstanding requests or opaque chapters.
proc skippedFixture(kind = Missing, both = false, incoming = true, writes = 64'u64): BatchFixture =
  result = batchFixture(incoming = incoming, writes = writes)
  var entries: seq[StateEntry] = @[]
  for entry in result.entries:
    var keep = true
    for service in [42'u32, 99'u32]:
      # Missing code retains the original account code hash and omits only its blob.
      if (service == 99 and kind == Missing) or (service == 42 and both):
        let key = chapterServiceKey(StateChapter(255), ServiceIndex(service))
        let metadata = decodeServiceMetadata(result.state.snapshot.value.lookup(key).value.bytes,
            ByteLimit(89)).value.metadata
        let blob = servicePreimageEntry(ServiceIndex(service),
          ServicePreimageHash(array[32, byte](metadata.codeHash)), [],
          ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(0))).value
        if array[31, byte](entry.key) == array[31, byte](blob.key): keep = false
    if keep: entries.add(entry)
  if kind == Malformed:
    # A noncanonical/incomplete compact metadata length cannot supply an executable code envelope.
    let raw = @[255'u8]
    let hash = array[32, byte](blake2b256(raw).value)
    let key = chapterServiceKey(StateChapter(255), ServiceIndex(99))
    for index in 0..<entries.len:
      if array[31, byte](entries[index].key) == array[31, byte](key):
        var metadata = decodeServiceMetadata(entries[index].value, ByteLimit(89)).value.metadata
        metadata.codeHash = CodeHash(hash)
        entries[index] = serviceMetadataEntry(ServiceIndex(99), metadata, ByteLimit(89)).value
    entries.add(servicePreimageEntry(ServiceIndex(99), ServicePreimageHash(hash), raw,
      ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(1))).value)
  result.entries = entries
  result.state = newStateStore(entries, integrationStoreLimits(writes = writes)).value

# Resolve and certify a real non-executing alternative with the same immutable source owners.
proc skipped(fixture: BatchFixture, index = 1'u64, slot = HeaderSlot(128),
    limit = 512'u64): SkippedAccumulation =
  let service = prepareAccumulationService(fixture.inputs, InvocationServiceIndex(index),
    fixture.state.snapshot.value, slot, AccumulationServiceConfig(codeLimit: ServiceCodeLimit(limit),
      preimageBytes: ByteLimit(1024))).value
  finishUninvokedAccumulation(service).value

# Independently construct the expected full map with literal credited balances and optional provision fulfillment.
proc expectedRows(fixture: BatchFixture, provisions: bool, credit = true): seq[StateEntry] =
  result = @[]
  for entry in fixture.entries: result.add(StateEntry(key: entry.key, value: entry.value))
  for ordinal, service in [42'u32, 99'u32]:
    let key = chapterServiceKey(StateChapter(255), ServiceIndex(service))
    for index in 0..<result.len:
      if credit and array[31, byte](result[index].key) == array[31, byte](key):
        var metadata = decodeServiceMetadata(result[index].value, ByteLimit(89)).value.metadata
        metadata.balance = AccountBalance(if ordinal == 0: 17 else: 31)
        result[index] = serviceMetadataEntry(ServiceIndex(service), metadata, ByteLimit(89)).value
    if provisions:
      let raw = (if ordinal == 0: @[73'u8] else: @[81'u8])
      let request = provisionRequest(service, raw)
      for index in 0..<result.len:
        if array[31, byte](result[index].key) == array[31, byte](request.key):
          result[index].value = @[1'u8, 128, 0, 0, 0]
      result.add(servicePreimageEntry(ServiceIndex(service),
        ServicePreimageHash(array[32, byte](blake2b256(raw).value)), raw,
        ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(1))).value)

# Compare complete-map commitments without causing additional hashes.
proc root(state: StateStore): array[32, byte] = array[32, byte](
    state.snapshot.value.commitment.root)

let policy = batchPolicy()
for kind in [Missing, Malformed, Oversized]:
  # Each certified skip reason preserves incoming credit; the actual execution can provide to the skipped service.
  let fixture = skippedFixture(kind)
  let skip = skipped(fixture, limit = (if kind == Oversized: 0'u64 else: 512'u64))
  let expectedStatus = (case kind
    of Missing: AccumulationCodeStatus.Missing
    of Malformed: AccumulationCodeStatus.Malformed
    of Oversized: AccumulationCodeStatus.Oversized)
  assert skip.skipInfo.value.code == expectedStatus
  let execution = batchExecution(fixture, 0)
  let plan = prepareCompleteAccumulationBatch(fixture.inputs, fixture.state.snapshot.value,
    [execution], [skip], HeaderSlot(128), policy).value
  let facts = plan.batchInfo.value
  assert facts.completeInputs and facts.executions == 1 and facts.skipped == 1
  assert facts.accountWrites == 2 and facts.terminal.provisions.contexts == 1
  assert uint32(plan.batchOutcomeAt(AccumulationProvisionSourceIndex(
      0)).value.outcomeInfo.value.service) == 42
  assert plan.batchOutcomeAt(AccumulationProvisionSourceIndex(1)).error ==
      AccumulationBatchError.InvalidIndex
  let expected = newStateStore(expectedRows(fixture, true), integrationStoreLimits()).value
  var state = fixture.state
  assert applyAccumulationBatch(state, plan).error == AccumulationBatchError.None
  assert root(state) == root(expected)
  assert applyAccumulationBatch(state, plan).error == AccumulationBatchError.StaleState

let fixture = skippedFixture(both = true)
let prior = fixture.state.snapshot.value
let a = skipped(fixture, 0)
let b = skipped(fixture)
let plan = prepareCompleteAccumulationBatch(fixture.inputs, prior, [], [a, b], HeaderSlot(128), policy).value
let expected = newStateStore(expectedRows(fixture, false), integrationStoreLimits()).value
var state = fixture.state
assert plan.batchInfo.value.completeInputs and plan.batchInfo.value.skipped == 2
assert plan.batchInfo.value.executions == 0 and plan.batchInfo.value.terminal.provisions.items == 0
assert applyAccumulationBatch(state, plan).error == AccumulationBatchError.None
assert root(state) == root(expected)
let permuted = prepareCompleteAccumulationBatch(fixture.inputs, prior, [], [b, a], HeaderSlot(128), policy).value
var reversedState = fixture.state
assert applyAccumulationBatch(reversedState, permuted).error == AccumulationBatchError.None
assert root(reversedState) == root(expected)
let wrongSlot = skipped(fixture, slot = HeaderSlot(129))
var foreignInput = fixture
foreignInput.inputs = batchInputSet()
let foreignSkip = skipped(foreignInput)
var foreignPrior = fixture
foreignPrior.state = newStateStore(fixture.entries, integrationStoreLimits()).value
let foreignStateSkip = skipped(foreignPrior)
let defaultSkip = default(SkippedAccumulation)
failHash(1)
assert prepareCompleteAccumulationBatch(fixture.inputs, prior, [], [], HeaderSlot(128),
    policy).error == AccumulationBatchError.IncompleteCoverage
assert prepareCompleteAccumulationBatch(fixture.inputs, prior, [], [a], HeaderSlot(128),
    policy).error == AccumulationBatchError.IncompleteCoverage
assert prepareCompleteAccumulationBatch(fixture.inputs, prior, [], [a, b, a], HeaderSlot(128),
    policy).error == AccumulationBatchError.IncompleteCoverage
assert prepareCompleteAccumulationBatch(fixture.inputs, prior, [], [a, a], HeaderSlot(128),
    policy).error == AccumulationBatchError.DuplicateService
assert prepareCompleteAccumulationBatch(fixture.inputs, prior, [], [a, defaultSkip], HeaderSlot(
    128), policy).error == AccumulationBatchError.InvalidSkip
assert prepareCompleteAccumulationBatch(fixture.inputs, prior, [], [a, wrongSlot], HeaderSlot(128),
    policy).error == AccumulationBatchError.InvalidSlot
for foreign in [foreignSkip, foreignStateSkip]:
  assert prepareCompleteAccumulationBatch(fixture.inputs, prior, [], [a, foreign], HeaderSlot(128),
      policy).error == AccumulationBatchError.SourceMismatch
assert prepareCompleteAccumulationBatch(fixture.inputs, prior, [], [a, b], HeaderSlot(128),
    batchPolicy(accounts = 1)).error == AccumulationBatchError.LimitExceeded
assert hashCalls() == 0
failHash(0)
# All-executed complete coverage reuses real outcomes; explicit subsets still report omissions.
let ready = batchFixture()
let first = batchExecution(ready, 0)
let second = batchExecution(ready, 1)
assert prepareCompleteAccumulationBatch(ready.inputs, ready.state.snapshot.value, [first], [],
    HeaderSlot(128), policy).error == AccumulationBatchError.IncompleteCoverage
let executed = prepareCompleteAccumulationBatch(ready.inputs, ready.state.snapshot.value,
  [second, first], [], HeaderSlot(128), policy).value
assert executed.batchInfo.value.completeInputs and executed.batchInfo.value.skipped == 0
let subset = prepareAccumulationBatch(ready.inputs, ready.state.snapshot.value, [first], HeaderSlot(
    128), policy).value
assert not subset.batchInfo.value.completeInputs
# A real service cannot appear in both arrays even when independently resolved with different size policies.
let oversizedReady = skipped(ready, 0, limit = 0)
assert prepareCompleteAccumulationBatch(ready.inputs, ready.state.snapshot.value,
  [first], [oversizedReady], HeaderSlot(128), policy).error ==
      AccumulationBatchError.DuplicateService
# Empty prepared inputs have genuine complete coverage without inventing an execution or skip.
let emptyQueue = planAccumulationQueues([], [0'u8], [0'u8], HeaderSlot(0),
  AccumulationQueueConfig(queues: WorkQueueConfig(cores: CoreCount(2), epochSlots: EpochSlots(1),
    maxBytes: ByteLimit(1000)))).value
let emptyOperands = prepareAccumulationOperands(emptyQueue, AccumulationReportPrefix(0),
  default(AccumulationOperandConfig)).value
let emptyInputs = prepareAccumulationInputs(emptyOperands, [], [], default(
    AccumulationInputConfig)).value
failHash(1)
let emptyPlan = prepareCompleteAccumulationBatch(emptyInputs, prior, [], [], HeaderSlot(128),
  batchPolicy(accounts = 0)).value
var emptyState = fixture.state
assert emptyPlan.batchInfo.value.completeInputs
assert applyAccumulationBatch(emptyState, emptyPlan).error == AccumulationBatchError.None
assert sameStateSnapshot(emptyState.snapshot.value, prior)
assert hashCalls() == 0
failHash(0)
let noCredit = skippedFixture(both = true, incoming = false)
let noCreditA = skipped(noCredit, 0)
let noCreditB = skipped(noCredit)
failHash(1)
let noWork = prepareCompleteAccumulationBatch(noCredit.inputs, noCredit.state.snapshot.value,
  [], [noCreditA, noCreditB], HeaderSlot(128), batchPolicy(accounts = 0)).value
var noWorkState = noCredit.state
assert applyAccumulationBatch(noWorkState, noWork).error == AccumulationBatchError.None
assert sameStateSnapshot(noWorkState.snapshot.value, noCredit.state.snapshot.value)
assert hashCalls() == 0
failHash(0)
# Store write limits refuse the combined skipped credits without publishing either account.
let limited = skippedFixture(both = true, writes = 1)
let limitedPlan = prepareCompleteAccumulationBatch(limited.inputs, limited.state.snapshot.value,
  [], [skipped(limited, 0), skipped(limited)], HeaderSlot(128), policy).value
var limitedState = limited.state
assert applyAccumulationBatch(limitedState, limitedPlan).storeError == StateStoreError.LimitExceeded
assert sameStateSnapshot(limitedState.snapshot.value, limited.state.snapshot.value)
# Mixed credits and terminal provisions retain atomicity if either private hash phase refuses.
let mixed = skippedFixture()
let mixedPlan = prepareCompleteAccumulationBatch(mixed.inputs, mixed.state.snapshot.value,
  [batchExecution(mixed, 0)], [skipped(mixed)], HeaderSlot(128), policy).value
var credited = mixed.state
let credits = prepareCompleteAccumulationBatch(fixture.inputs, prior, [], [a, b], HeaderSlot(128), policy).value
var observed = fixture.state
failHash(0)
discard applyAccumulationBatch(observed, credits).value
let accountHashes = hashCalls()
assert accountHashes > 0
for allowance in [0.cint, accountHashes]:
  var candidate = fixture.state
  hashAfter(allowance)
  let result = applyAccumulationBatch(candidate, credits)
  if allowance == 0:
    assert result.storeError == StateStoreError.BackendFailure
    assert sameStateSnapshot(candidate.snapshot.value, prior)
  else:
    assert result.error == AccumulationBatchError.None # An all-skip plan has no later provision hashes.
  failHash(0)
# Count the mixed fixture's literal credit phase to target refusal after all credits are computed.
var writes: seq[StateWrite] = @[]
for entry in expectedRows(mixed, false):
  for service in [42'u32, 99'u32]:
    if array[31, byte](entry.key) == array[31, byte](chapterServiceKey(StateChapter(255),
        ServiceIndex(service))):
      writes.add(StateWrite(key: entry.key, kind: StateWriteKind.Put, value: entry.value))
failHash(0)
discard credited.apply(writes).value
let mixedHashes = hashCalls()
failHash(0)
var candidate = mixed.state
hashAfter(mixedHashes)
assert applyAccumulationBatch(candidate, mixedPlan).provisionError ==
    AccumulationProvisionError.BackendFailure
assert sameStateSnapshot(candidate.snapshot.value, mixed.state.snapshot.value)
failHash(0)
var retained: PreparedAccumulationBatch
var detached: StateStore
block:
  let local = skippedFixture(both = true)
  var sources = @[skipped(local, 0), skipped(local)]
  retained = prepareCompleteAccumulationBatch(local.inputs, local.state.snapshot.value,
    [], sources, HeaderSlot(128), policy).value
  detached = local.state
  sources.setLen(0) # Releasing all source certificates does not invalidate copied metadata or retained provenance.
assert applyAccumulationBatch(detached, retained).error == AccumulationBatchError.None
assert root(detached) == root(expected)
let before = getOccupiedMem()
for iteration in 0..<1000:
  # Repeated all-skip plans release private candidates and copied owners after failure and success.
  let prepared = prepareCompleteAccumulationBatch(fixture.inputs, prior, [], [b, a], HeaderSlot(
      128), policy).value
  var local = fixture.state
  failHash(1)
  assert applyAccumulationBatch(local, prepared).storeError == StateStoreError.BackendFailure
  assert sameStateSnapshot(local.snapshot.value, prior)
  failHash(0)
  assert applyAccumulationBatch(local, prepared).error == AccumulationBatchError.None
  assert root(local) == root(expected)
let after = getOccupiedMem()
assert before == after
recordArcRelease("accumulation_complete_batch", 1000, before, after)
echo "Complete accumulation batch state passed"
echo "ARC_RELEASE cycles=1000 unchanged"
