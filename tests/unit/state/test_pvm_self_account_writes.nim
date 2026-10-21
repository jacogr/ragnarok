# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_self_account_writes_arc_release"}

## Actual PVM self writes publish bounded terminal-selected data with exact common-source roots and rollback.

import std/[assertions, syncio]
import ../../../src/state/[accumulation_batch, accumulation_dispatch, accumulation_effects,
  accumulation_context, accumulation_outcome, accumulation_provisions, store]
import ../../../src/codec/[bounded, composite, header, state_accounts, state_service_values,
  state_requests, state_layout, state_trie]
import ../../../src/pvm/machine
import ../../../src/crypto/primitives
import ../../support/[accumulation_batch_context, accumulation_provision_integration,
  pvm_accumulation_program, arc_evidence]

# Observe actual backend work and place a refusal after complete account publication has been computed privately.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
proc hashAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}

let digest = ServicePreimageHash(array[32, byte](blake2b256([81'u8]).value))
# Immutable input supplies a real provision digest and independent one-byte values after the hash.
proc guestInput(): seq[byte] =
  result = newSeq[byte](34)
  for index, octet in array[32, byte](digest):
    result[index] = octet # The offered request hash belongs to literal raw blob 81.
  result[32] = 81
  result[33] = 82
let input = guestInput()

# Both services address the same raw key 73; canonical service key derivation must keep their writes disjoint.
proc write(value = 81'u32, delete = false): seq[seq[byte]] =
  @[@[51'u8, 7, 255], registerImmediate(8, 65536), registerImmediate(9, 1),
    registerImmediate(10, if value == 81: 196640'u64 else: 196641'u64),
    registerImmediate(11, if delete: 0'u64 else: 1'u64), @[10'u8, 5]]

# Append authored instruction sequences without duplicating framing, masks or the production engine.
proc append(instructions: var seq[seq[byte]], more: seq[seq[byte]]) =
  for instruction in more:
    instructions.add(instruction) # Each exact opcode boundary remains owned by the existing guest envelope builder.

# A checkpoint before replacement exposes terminal selection of complete account/key versions.
proc storageEnvelope(checkpoint = false, panic = false, replace = false,
    delete = false, upgrade = false): seq[byte] =
  var instructions = write()
  if checkpoint:
    instructions.add(@[10'u8, 19]) # Retain the first stored value and its key proof together.
  if replace or delete:
    append(instructions, write(82, delete)) # Reusing one raw key must consume one trace descriptor.
  if upgrade:
    append(instructions, @[@[51'u8, 7, 255], registerImmediate(8, 196608), registerImmediate(9, 7),
      registerImmediate(10, 9), @[10'u8, 21]]) # Later metadata upgrade must retain broader supported self-entry scope.
  instructions.add(if panic: @[0'u8] else: @[50'u8, 0])
  guestEnvelope(instructions, input)

# Explicit tracing policy is independent of actual guest memory-copy and batch publication budgets.
proc execute(fixture: BatchFixture, index = 0'u64, keys = 3'u64): AccumulationDispatchResult =
  batchExecution(fixture, index, accountWriteKeys = ElementLimit(keys))

# Keep the full prepared input/prior owners and finite metadata/self-data/provision policies inseparable.
proc prepare(fixture: BatchFixture, first, second: AccumulationDispatchResult,
    keys = 6'u64, bytes = 100'u64): AccumulationBatchResult[PreparedAccumulationBatch] =
  let prior = fixture.state.snapshot.value
  let executions = [first, second]
  prepareCompleteAccumulationBatch(fixture.inputs, prior, executions, [], HeaderSlot(128),
    batchPolicy(selfWrites = keys, selfValueBytes = bytes))

# Inspect canonical own metadata independently from batch observations or the traced descriptor list.
proc metadata(state: StateStoreSnapshot, service: uint32): ServiceMetadata =
  decodeServiceMetadata(state.lookup(chapterServiceKey(StateChapter(255),
    ServiceIndex(service))).value.bytes, ByteLimit(ServiceMetadataBytes)).value.metadata

# Construct a complete expected map from authored rows and literal own balances/storage counters.
proc creditedRows(fixture: BatchFixture, firstItems = 0'u32, secondItems = 0'u32,
    firstBytes = 0'u64, secondBytes = 0'u64, upgrade = false): seq[StateEntry] =
  result = @[]
  for entry in fixture.entries:
    var copied = StateEntry(key: entry.key, value: entry.value)
    for ordinal, service in [42'u32, 99'u32]:
      if array[31, byte](entry.key) == array[31, byte](chapterServiceKey(StateChapter(255),
          ServiceIndex(service))):
        var account = decodeServiceMetadata(entry.value, ByteLimit(
            ServiceMetadataBytes)).value.metadata
        account.balance = AccountBalance(if ordinal == 0: 17 else: 31)
        account.storageItems = AccountStorageItems(if ordinal == 0: firstItems else: secondItems)
        account.storageBytes = AccountStorageBytes(if ordinal == 0: firstBytes else: secondBytes)
        if ordinal == 0 and upgrade:
          account.codeHash = CodeHash(array[32, byte](digest))
          account.minimumAccumulationGas = Gas(7)
          account.minimumTransferGas = Gas(9) # Literal metadata fields are independent from selected current-account reads.
        copied = serviceMetadataEntry(ServiceIndex(service), account, ByteLimit(
            ServiceMetadataBytes)).value
    result.add(copied) # Preserve all code, existing storage, requests and opaque chapters.

# Compare the actual complete-map root, never a root reconstructed from partial service state.
proc sameRoot(state: StateStore, rows: seq[StateEntry]) =
  let wanted = newStateStore(rows, integrationStoreLimits()).value
  assert array[32, byte](state.snapshot.value.commitment.root) == array[32, byte](
      wanted.snapshot.value.commitment.root),
    "complete expected root includes all unrelated prior entries"

# Halt commits final values; panic picks the pre-replacement checkpoint or the initial context.
for checkpoint in [false, true]:
  for panic in [false, true]:
    let fixture = batchFixture(firstEnvelope = storageEnvelope(checkpoint, panic, replace = true),
      secondEnvelope = storageEnvelope())
    let first = execute(fixture)
    let second = execute(fixture, 1)
    let selected = normalizeAccumulationOutcome(first).value.outcomeContext.value
    let retained = not panic or checkpoint
    assert selected.effectAccountWriteCount.value == (if retained: 1 else: 0),
      "terminal selection retains the exact key-set version"
    assert first.effects.effectContext(AccumulationDimension.Regular).value.effectAccountWriteCount.value == 1,
      "repeated replacement consumes one unique trace key"
    var rows = creditedRows(fixture, (if retained: 1'u32 else: 0'u32), 1,
      (if retained: 36'u64 else: 0'u64), 36)
    if retained:
      rows.add(serviceStorageEntry(ServiceIndex(42), @[73'u8],
        (if panic: @[81'u8] else: @[82'u8]), ServiceEntryLimits(keyBytes: ByteLimit(1),
            valueBytes: ByteLimit(1))).value)
    rows.add(serviceStorageEntry(ServiceIndex(99), @[73'u8], @[81'u8],
      ServiceEntryLimits(keyBytes: ByteLimit(1), valueBytes: ByteLimit(1))).value)
    let plan = prepare(fixture, first, second).value
    var state = fixture.state
    discard applyAccumulationBatch(state, plan).value
    sameRoot(state, rows)
    let info = plan.batchInfo.value
    assert info.accountWrites == 2 and info.selfWrites == (if retained: 2 else: 1),
      "metadata count stays separate from selected nonmetadata key count"
    assert info.selfValueBytes == uint64(info.selfWrites), "only final raw storage values consume the copied-byte budget"
    assert selected.effectAccountWriteKeyAt(AccumulationAccountWriteIndex(high(uint64))).error ==
        AccumulationEffectError.InvalidIndex,
      "full-width invalid key ordinal refuses before narrowing"
    var reverse = fixture.state
    discard applyAccumulationBatch(reverse, prepare(fixture, second, first).value).value
    sameRoot(reverse, rows)
    assert uint64(metadata(fixture.state.snapshot.value, 42).balance) == 10, "retained prior stays immutable"

block replacement_and_deletion:
  let fixture = batchFixture(firstEnvelope = storageEnvelope(replace = true, delete = true,
      upgrade = true),
    secondEnvelope = guestEnvelope([@[50'u8, 0]]))
  let first = execute(fixture, keys = 1)
  let second = execute(fixture, 1)
  let selected = normalizeAccumulationOutcome(first).value.outcomeContext.value
  assert selected.effectAccountScope.value == AccumulationAccountScope.SelfEntries and
      selected.effectAccountWriteCount.value == 1,
    "upgrade retains the complete self-key proof after deletion"
  let plan = prepare(fixture, first, second, keys = 1, bytes = 0).value
  var state = fixture.state
  discard applyAccumulationBatch(state, plan).value
  sameRoot(state, creditedRows(fixture, upgrade = true))
  assert plan.batchInfo.value.selfWrites == 1 and plan.batchInfo.value.selfValueBytes == 0,
    "a touched deletion remains explicit even when final map bytes match initial storage"

# New request, optional forgetting and optional provide use the same actual self account owner.
proc requestEnvelope(forget = false, provide = false, checkpoint = false, panic = false): seq[byte] =
  var instructions = @[@[51'u8, 7, 255], registerImmediate(8, 196608), registerImmediate(9, 1), @[
      10'u8, 25]]
  if checkpoint:
    instructions.add(@[10'u8, 19]) # Retain the requested history before any later regular removal.
  if forget:
    append(instructions, @[@[51'u8, 7, 255], registerImmediate(8, 196608), registerImmediate(9, 1),
        @[10'u8, 26]])
  if provide:
    append(instructions, @[registerImmediate(7, 42), registerImmediate(8, 196640),
      registerImmediate(9, 1), @[10'u8, 28]]) # Request creation must compose with later terminal fulfillment.
  instructions.add(if panic: @[0'u8] else: @[50'u8, 0])
  guestEnvelope(instructions, input)

for forget in [false, true]:
  for checkpoint in [false, true]:
    let fixture = batchFixture(firstEnvelope = requestEnvelope(forget, checkpoint = checkpoint,
        panic = checkpoint),
      secondEnvelope = guestEnvelope([@[50'u8, 0]]))
    let first = execute(fixture)
    let kept = not forget or checkpoint
    let plan = prepare(fixture, first, execute(fixture, 1)).value
    var state = fixture.state
    discard applyAccumulationBatch(state, plan).value
    var rows = creditedRows(fixture, (if kept: 2'u32 else: 0'u32), 0,
      (if kept: 82'u64 else: 0'u64), 0)
    if kept:
      rows.add(serviceRequestEntry(ServiceIndex(42), digest, RequestLength(1), requestedHistory(),
        RequestEntryConfig(keyBytes: ByteLimit(32), history: RequestHistoryConfig(
            items: ElementLimit(3), maxBytes: ByteLimit(13)))).value)
    sameRoot(state, rows)

block delete_existing_prior_storage:
  let seeded = serviceStorageEntry(ServiceIndex(42), @[73'u8], @[91'u8],
    ServiceEntryLimits(keyBytes: ByteLimit(1), valueBytes: ByteLimit(1))).value
  var fixture = batchFixture(firstEnvelope = storageEnvelope(delete = true),
    secondEnvelope = guestEnvelope([@[50'u8, 0]]), extra = @[seeded])
  for index in 0..<fixture.entries.len:
    if array[31, byte](fixture.entries[index].key) == array[31, byte](chapterServiceKey(
        StateChapter(255), ServiceIndex(42))):
      var account = decodeServiceMetadata(fixture.entries[index].value, ByteLimit(
          ServiceMetadataBytes)).value.metadata
      account.storageItems = AccountStorageItems(1)
      account.storageBytes = AccountStorageBytes(36) # The independently seeded existing key has a real deletable footprint.
      fixture.entries[index] = serviceMetadataEntry(ServiceIndex(42), account, ByteLimit(
          ServiceMetadataBytes)).value
  fixture.state = newStateStore(fixture.entries, integrationStoreLimits()).value
  let plan = prepare(fixture, execute(fixture), execute(fixture, 1)).value
  var state = fixture.state
  discard applyAccumulationBatch(state, plan).value
  var rows: seq[StateEntry] = @[]
  for entry in creditedRows(fixture):
    if array[31, byte](entry.key) != array[31, byte](seeded.key):
      rows.add(entry) # The complete expected map removes exactly the originally present storage key.
  sameRoot(state, rows)
  assert fixture.state.snapshot.value.lookup(seeded.key).value.bytes == @[91'u8],
    "selected deletion cannot mutate the retained original value"

block restore_request_history:
  let config = RequestEntryConfig(keyBytes: ByteLimit(32), history: RequestHistoryConfig(
      items: ElementLimit(3), maxBytes: ByteLimit(13)))
  let seeded = serviceRequestEntry(ServiceIndex(42), digest, RequestLength(1),
    unavailableHistory(RequestSlot(5), RequestSlot(7)), config).value
  let fixture = batchFixture(firstEnvelope = requestEnvelope(), secondEnvelope = guestEnvelope([@[
      50'u8, 0]]), extra = @[seeded])
  let first = execute(fixture, keys = 1)
  let plan = prepare(fixture, first, execute(fixture, 1), keys = 1, bytes = 13).value
  var state = fixture.state
  discard applyAccumulationBatch(state, plan).value
  var rows = creditedRows(fixture)
  let restored = serviceRequestEntry(ServiceIndex(42), digest, RequestLength(1),
    reavailableHistory(RequestSlot(5), RequestSlot(7), RequestSlot(128)), config).value
  for index in 0..<rows.len:
    if array[31, byte](rows[index].key) == array[31, byte](seeded.key):
      rows[index] = restored # Restoration changes one history without a fresh metadata footprint.
  sameRoot(state, rows)
  assert plan.batchInfo.value.selfValueBytes == 13, "exact three-slot history copy consumes thirteen bytes"
  assert prepare(fixture, first, execute(fixture, 1), keys = 1, bytes = 12).error ==
      AccumulationBatchError.LimitExceeded,
    "short final history-copy budget is a local publication refusal"

block explicit_limits_and_disabled_trace:
  let fixture = batchFixture(firstEnvelope = storageEnvelope(), secondEnvelope = storageEnvelope())
  let first = execute(fixture, keys = 1)
  let second = execute(fixture, 1, keys = 1)
  assert prepare(fixture, first, second, keys = 1).error == AccumulationBatchError.LimitExceeded,
    "aggregate self-key budget is independent from per-service trace capacity"
  assert prepare(fixture, first, second, bytes = 1).error == AccumulationBatchError.LimitExceeded,
    "aggregate copied self-value bytes are independently bounded"
  assert prepare(fixture, first, second, keys = 2, bytes = 2).error == AccumulationBatchError.None,
    "exact key and byte boundaries accept both final one-byte values"
  let disabled = execute(fixture, keys = 0)
  assert disabled.error == AccumulationDispatchError.None and prepare(fixture, disabled,
      second).error == AccumulationBatchError.UnsupportedAccountEffects,
    "zero tracing retains the earlier successful local execution and conservative publication gate"
  assert disabled.effects.effectContext(AccumulationDimension.Regular).value.effectAccountWriteCount.error ==
      AccumulationEffectError.InvalidState,
    "unsupported lineage cannot expose a partially traced key list"
  let foreign = batchFixture(firstEnvelope = storageEnvelope(), secondEnvelope = storageEnvelope())
  assert prepare(fixture, execute(foreign), second).error == AccumulationBatchError.SourceMismatch,
    "matching code and trace contents cannot replace the exact shared input/prior owners"
  assert default(AccumulationEffectContext).effectAccountWriteCount.error ==
      AccumulationEffectError.Uninitialized,
    "default context has no successful empty trace"
  assert default(AccumulationEffectContext).effectAccountWriteKeyAt(AccumulationAccountWriteIndex(
      0)).error == AccumulationEffectError.Uninitialized,
    "default context has no key payload"
  let short = batchFixture(firstEnvelope = requestEnvelope(forget = true),
      secondEnvelope = guestEnvelope([@[50'u8, 0]]))
  assert execute(short, keys = 1).error == AccumulationDispatchError.LimitExceeded,
    "forget needs both request and preimage deletion keys in its trace, even when neither remains present"

# New requested history is merged before fnprovide, making the pending provision valid on the combined private candidate.
let fixture = batchFixture(firstEnvelope = requestEnvelope(provide = true),
  secondEnvelope = guestEnvelope([@[50'u8, 0]]))
let first = execute(fixture)
let second = execute(fixture, 1)
let plan = prepare(fixture, first, second).value
block provision_and_atomicity:
  var state = fixture.state
  discard applyAccumulationBatch(state, plan).value
  var rows = creditedRows(fixture, 2, 0, 82, 0)
  rows.add(serviceRequestEntry(ServiceIndex(42), digest, RequestLength(1), availableHistory(
      RequestSlot(128)),
    RequestEntryConfig(keyBytes: ByteLimit(32), history: RequestHistoryConfig(items: ElementLimit(
        3), maxBytes: ByteLimit(13)))).value)
  rows.add(servicePreimageEntry(ServiceIndex(42), digest, @[81'u8],
    ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(1))).value)
  sameRoot(state, rows)
  let published = state.snapshot.value
  failHash(1)
  assert applyAccumulationBatch(state, plan).error == AccumulationBatchError.StaleState and
      hashCalls() == 0,
    "stale self writes cannot overwrite intervening publication or duplicate credit"
  failHash(0)
  assert sameStateSnapshot(published, state.snapshot.value), "stale refusal retains exact published owner"
  var candidate = fixture.state
  let before = candidate.snapshot.value
  failHash(1)
  assert applyAccumulationBatch(candidate, plan).storeError == StateStoreError.BackendFailure,
    "account-phase backend failure remains atomic"
  failHash(0)
  assert sameStateSnapshot(before, candidate.snapshot.value), "failed root publishes no request, credit or provision"

block late_provision_failure:
  var writes: seq[StateWrite] = @[]
  for entry in creditedRows(fixture, 2, 0, 82, 0):
    for service in [42'u32, 99'u32]:
      if array[31, byte](entry.key) == array[31, byte](chapterServiceKey(StateChapter(255),
          ServiceIndex(service))):
        writes.add(StateWrite(key: entry.key, kind: StateWriteKind.Put,
            value: entry.value)) # Independently calibrate both credited metadata writes.
  let request = integrationRequest(42, @[81'u8])
  writes.add(StateWrite(key: request.key, kind: StateWriteKind.Put, value: request.value))
  var accountOnly = fixture.state
  failHash(0)
  discard accountOnly.apply(writes).value
  let hashes = hashCalls()
  assert hashes > 0, "real account root calibration"
  var state = fixture.state
  let prior = state.snapshot.value
  hashAfter(hashes)
  let failed = applyAccumulationBatch(state, plan)
  assert failed.error == AccumulationBatchError.TerminalFailure and failed.provisionError ==
      AccumulationProvisionError.BackendFailure,
    "late provision-root failure discards all completed private metadata and self-key writes"
  failHash(0)
  assert sameStateSnapshot(prior, state.snapshot.value), "late failure publishes no request or credit"

block detached_proof_owners:
  var owned = default(PreparedAccumulationBatch)
  var state = default(StateStore)
  block local_sources:
    let local = batchFixture(firstEnvelope = storageEnvelope(), secondEnvelope = storageEnvelope())
    let first = execute(local)
    let context = normalizeAccumulationOutcome(first).value.outcomeContext.value
    let key = context.effectAccountWriteKeyAt(AccumulationAccountWriteIndex(0)).value
    var copied = array[31, byte](key)
    copied[0] = copied[0] xor 255
    assert array[31, byte](context.effectAccountWriteKeyAt(AccumulationAccountWriteIndex(
        0)).value) == array[31, byte](key),
      "copied traced key cannot mutate the retained proof"
    owned = prepare(local, first, execute(local, 1)).value
    state = local.state # Caller execution, context and fixture owners leave scope before publication.
  discard applyAccumulationBatch(state, owned).value
  let key = serviceStorageKey(ServiceIndex(42), @[73'u8], ByteLimit(1)).value
  assert state.snapshot.value.lookup(key).value.bytes == @[81'u8], "plan retains selected self values after caller sources disappear"

let before = getOccupiedMem()
for iteration in 0..<1000:
  let owned = prepare(fixture, execute(fixture), second).value
  var state = fixture.state
  discard applyAccumulationBatch(state, owned).value
  assert uint32(metadata(state.snapshot.value, 42).storageItems) == 2, "fresh self-key proofs and account versions release after publication"
let after = getOccupiedMem()
assert before == after, "bounded self-write publication has stable ARC ownership"
recordArcRelease("pvm_self_account_writes", 1000, before, after)
echo "PVM self account writes passed"
echo "ARC_RELEASE cycles=1000 unchanged"
