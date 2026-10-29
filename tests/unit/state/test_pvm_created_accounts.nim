# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_created_accounts_arc_release"}

## Genuine new-service executions publish selected children/debits and refuse colliding or broader account effects.

import std/[assertions, syncio]
import ../../../src/chain/parameters
import ../../../src/state/accumulation/[batch as accumulation_batch,
    dispatch as accumulation_dispatch, effects as accumulation_effects,
    context as accumulation_context, outcome as accumulation_outcome,
    invocation as accumulation_invocation, provisions as accumulation_provisions]
import ../../../src/state/store
import ../../../src/codec/[bounded, composite, header]
import ../../../src/codec/state/[accounts as state_accounts, service_values as state_service_values,
    requests as state_requests, layout as state_layout, trie as state_trie,
    safrole as state_safrole]
import ../../../src/pvm/[machine, step]
import ../../../src/crypto/primitives
import ../../support/[accumulation_batch_context, accumulation_provision_integration,
  pvm_accumulation_program, pvm_accumulation_context, arc_evidence, accumulation_batch_hash_failures]

# Fail real backend work only after the guest and prepared batch exist.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}

# One unit flat deposit gives a literal nonzero debit/child balance while retaining the fixed fixture profile.
proc profile(): Parameters =
  var bytes = encodeParameters(pvmParameters())
  for index in 0..<24:
    bytes[index] = 0 # Item and byte deposits remain zero, independent of the child request length.
  bytes[16] = 1
  for index in 0..<4:
    bytes[74+index] = byte((14400'u32 shr (8*index)) and
        255) # Retain the validated standard lookup age; current eject uses supervisor/empty-account eligibility.
  decodeParameters(bytes).value

let hash = ServicePreimageHash(array[32, byte](blake2b256([81'u8]).value))
# Offer a genuine one-byte preimage hash plus the actual raw byte for later provision to the child.
proc guestInput(): seq[byte] =
  result = newSeq[byte](61)
  for index, octet in array[32, byte](hash):
    result[index] = octet # Code availability is deliberately not required by creation.
  result[32] = 1 # E4 code length.
  result[36] = 7 # E8 minimum accumulation gas.
  result[44] = 9 # E8 minimum transfer gas.
  result[60] = 81 # Provision bytes follow the complete current request.
let input = guestInput()

# Preserve every authored opcode boundary through the shared fixed envelope builder.
proc append(code: var seq[seq[byte]], instructions: seq[seq[byte]]) =
  for instruction in instructions:
    code.add(instruction) # No upstream assembler or replacement execution verdict.

# One real creation reads the packed current request; a repeated call reuses preserved arguments.
proc envelope(checkpoint = false, panic = false, repeat = false, provide = false,
    storage = false, upgrade = false, beforeStorage = false, eject = false): seq[byte] =
  var code: seq[seq[byte]] = @[]
  let write = @[@[51'u8, 7, 255], registerImmediate(8, 65536), registerImmediate(9, 1),
    registerImmediate(10, 196668), registerImmediate(11, 1), @[10'u8, 5]]
  if beforeStorage:
    append(code, write) # An earlier unsupported storage lineage cannot regain eligibility through new.
  append(code, @[@[51'u8, 7, 255], registerImmediate(8, high(uint64)),
    @[51'u8, 9, 0], registerImmediate(10, 196608), @[10'u8, 20]])
  if checkpoint:
    code.add(@[10'u8, 19]) # Retain the first child, creator debit and allocation cursor together.
  if repeat:
    append(code, @[@[51'u8, 7, 255], @[10'u8,
        20]]) # All other creation arguments survive the preceding call.
  if provide:
    append(code, @[registerImmediate(8, 196668), registerImmediate(9, 1), @[10'u8,
        28]]) # r7 is the actual returned child ID.
  if storage:
    append(code, write) # Self-key proof must preserve existing child provenance.
  if upgrade:
    append(code, @[@[51'u8, 7, 255], registerImmediate(8, 196608), registerImmediate(9, 17),
      registerImmediate(10, 19), @[10'u8, 21]]) # Metadata-only upgrade must not erase the child proof.
  if eject:
    append(code, @[registerImmediate(7, 77), registerImmediate(8, 196608), @[10'u8,
        23]]) # A real eligible deletion remains outside publication scope.
  code.add(if panic: @[0'u8] else: @[50'u8, 0])
  guestEnvelope(code, input)

# Fixed entropy counters freeze an offline birthday collision; they are ordinary explicit bootstrap inputs.
proc entropy(counter: uint32): StateEntropyWord =
  var bytes = default(array[32, byte])
  for index in 0..<4:
    bytes[index] = byte((counter shr (8*index)) and 255)
  StateEntropyWord(bytes)

# Keep creation capacity, self-key tracing and automatic-allocation probing separate.
proc execute(fixture: BatchFixture, index = 0'u64, children = 2'u64, keys = 1'u64,
    word = default(StateEntropyWord), slot = HeaderSlot(128)): AccumulationDispatchResult =
  batchExecution(fixture, index, slot, copyLimit = MemoryByteLimit(60), parameters = profile(),
      createdAccounts = ElementLimit(children),
    accountWriteKeys = ElementLimit(keys), serviceProbes = ServiceProbeLimit(1), entropy = word)

# Complete coverage still uses only the exact shared inputs/prior; a slot is checked independently by terminal normalization.
proc prepare(fixture: BatchFixture, first, second: AccumulationDispatchResult,
    children = 4'u64, slot = HeaderSlot(128)): AccumulationBatchResult[PreparedAccumulationBatch] =
  let prior = fixture.state.snapshot.value
  let executions = [first, second]
  prepareCompleteAccumulationBatch(fixture.inputs, prior, executions, [], slot,
    batchPolicy(selfWrites = 2, selfValueBytes = 2, createdAccounts = children))

# Derive the first ID from the existing independent bootstrap allocator, not from the newly added creation-proof accessor.
proc childId(service: uint32, slot = HeaderSlot(128)): ServiceIndex =
  initialAccumulationService(ServiceIndex(service), default(StateEntropyWord), slot).value

# Construct complete expected creator metadata with literal incoming amounts and per-child flat debits.
proc rows(fixture: BatchFixture, first = 1'u64, second = 1'u64, storage = false,
    upgrade = false, incoming = true): seq[StateEntry] =
  result = @[]
  for entry in fixture.entries:
    var copied = StateEntry(key: entry.key, value: entry.value)
    for ordinal, service in [42'u32, 99'u32]:
      if array[31, byte](entry.key) == array[31, byte](chapterServiceKey(StateChapter(255),
          ServiceIndex(service))):
        var account = decodeServiceMetadata(entry.value, ByteLimit(
            ServiceMetadataBytes)).value.metadata
        account.balance = AccountBalance(if ordinal == 0: (
            if incoming: 17-first else: 10-first) else: (if incoming: 31-second else: 20-second))
        if ordinal == 0 and storage:
          account.storageItems = AccountStorageItems(1)
          account.storageBytes = AccountStorageBytes(
              36) # One-byte key/value adds the independently specified footprint.
        if ordinal == 0 and upgrade:
          account.codeHash = CodeHash(array[32, byte](hash))
          account.minimumAccumulationGas = Gas(17)
          account.minimumTransferGas = Gas(19)
        copied = serviceMetadataEntry(ServiceIndex(service), account, ByteLimit(
            ServiceMetadataBytes)).value
    result.add(copied) # Retain code, unrelated accounts, storage and opaque chapters exactly.
  if storage:
    result.add(serviceStorageEntry(ServiceIndex(42), @[73'u8], @[81'u8],
      ServiceEntryLimits(keyBytes: ByteLimit(1), valueBytes: ByteLimit(1))).value)

# Each child has one unit balance, two footprint items, the current time and the literal invoking parent.
proc addChild(expected: var seq[StateEntry], service: ServiceIndex, parent: uint32,
    slot = HeaderSlot(128), provided = false) =
  expected.add(serviceMetadataEntry(service, ServiceMetadata(codeHash: CodeHash(array[32, byte](hash)),
    balance: AccountBalance(1), storageItems: AccountStorageItems(2),
        storageBytes: AccountStorageBytes(82),
    minimumAccumulationGas: Gas(7), minimumTransferGas: Gas(9), supervisor: ServiceIndex(parent),
        created: AccountSlot(uint32(slot)),
    parent: ServiceIndex(parent)), ByteLimit(ServiceMetadataBytes)).value)
  expected.add(serviceRequestEntry(service, hash, RequestLength(1),
    (if provided: availableHistory(RequestSlot(uint32(slot))) else: requestedHistory()),
    RequestEntryConfig(keyBytes: ByteLimit(32), history: RequestHistoryConfig(items: ElementLimit(
        3), maxBytes: ByteLimit(13)))).value)
  if provided:
    expected.add(servicePreimageEntry(service, hash, @[81'u8],
      ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(
          1))).value) # Only fnprovide publishes this raw blob.

# Roots cover complete independently authored maps rather than only the changed service projections.
proc sameRoot(state: StateStore, expected: seq[StateEntry]) =
  let wanted = newStateStore(expected, integrationStoreLimits()).value
  assert array[32, byte](state.snapshot.value.commitment.root) == array[32, byte](
      wanted.snapshot.value.commitment.root),
    "full root preserves exact debits, child records and all unrelated prior entries"

for checkpoint in [false, true]:
  for panic in [false, true]:
    let fixture = batchFixture(firstEnvelope = envelope(checkpoint, panic, repeat = true),
        secondEnvelope = envelope())
    let first = execute(fixture)
    let second = execute(fixture, 1)
    let count = if panic: (if checkpoint: 1 else: 0) else: 2
    let selected = normalizeAccumulationOutcome(first).value.outcomeContext.value
    assert selected.effectCreatedAccountCount.value == count, "terminal checkpoint selects creation facts and debits together"
    assert selected.effectCreatedAccountFactCount.value == count, "enabled creation proof follows terminal checkpoint"
    if count > 0:
      let fact = selected.effectCreatedAccountFactAt(AccumulationCreatedAccountIndex(0)).value
      assert uint32(fact.service) == uint32(childId(42)), "independent facts retain actual child identity"
    var expected = rows(fixture, uint64(count), 1)
    if count != 0:
      addChild(expected, childId(42), 42)
    if count == 2:
      let next = nextAccumulationService(fixture.state.snapshot.value, childId(42),
          ServiceProbeLimit(1)).value
      addChild(expected, next, 42) # The second call uses the actual advancing cursor, never overwrites the first child.
    addChild(expected, childId(99), 99)
    let plan = prepare(fixture, first, second).value
    assert plan.batchInfo.value.createdAccounts == count+1 and plan.batchInfo.value.selfWrites == 0,
      "created children remain separate from invoking metadata and self-key budgets"
    var state = fixture.state
    discard applyAccumulationBatch(state, plan).value
    sameRoot(state, expected)
    var reversed = fixture.state
    discard applyAccumulationBatch(reversed, prepare(fixture, second, first).value).value
    sameRoot(reversed, expected)
    assert selected.effectCreatedAccountAt(AccumulationCreatedAccountIndex(high(uint64))).error ==
        AccumulationEffectError.InvalidIndex,
      "full-width invalid creation index cannot narrow to a real child"

for storage in [false, true]:
  let fixture = batchFixture(firstEnvelope = envelope(storage = storage, upgrade = not storage),
      secondEnvelope = envelope())
  let plan = prepare(fixture, execute(fixture), execute(fixture, 1)).value
  var expected = rows(fixture, storage = storage, upgrade = not storage)
  addChild(expected, childId(42), 42)
  addChild(expected, childId(99), 99)
  var state = fixture.state
  discard applyAccumulationBatch(state, plan).value
  sameRoot(state, expected)

block creation_without_incoming:
  let fixture = batchFixture(incoming = false, firstEnvelope = envelope(),
      secondEnvelope = envelope())
  var expected = rows(fixture, incoming = false)
  addChild(expected, childId(42), 42)
  addChild(expected, childId(99), 99)
  var state = fixture.state
  discard applyAccumulationBatch(state, prepare(fixture, execute(fixture), execute(fixture,
      1)).value).value
  sameRoot(state, expected) # Creator debits must publish even when initial service credit did not fork the map.

# Ejection really deletes an old eligible account locally, but only a pre-deletion checkpoint permits publication.
for checkpoint in [false, true]:
  var identity = default(array[32, byte])
  identity[0] = 42 # Opaque code hash; the current supervisor fields authorize ejection.
  let target = serviceMetadataEntry(ServiceIndex(77), ServiceMetadata(codeHash: CodeHash(identity),
    supervisor: ServiceIndex(42), balance: AccountBalance(5)), ByteLimit(
        ServiceMetadataBytes)).value
  let fixture = batchFixture(firstEnvelope = envelope(checkpoint, checkpoint, eject = true),
    secondEnvelope = guestEnvelope([@[50'u8, 0]]), extra = @[target])
  let first = execute(fixture, slot = HeaderSlot(50000))
  let second = execute(fixture, 1, slot = HeaderSlot(50000))
  let regular = first.effects.effectContext(AccumulationDimension.Regular).value
  assert regular.effectAccounts.value.lookup(target.key).error == StateStoreError.MissingKey,
    "actual eligible eject removed the prior target before terminal selection"
  assert regular.effectCreatedAccountCount.error == AccumulationEffectError.InvalidState,
    "broader deletion exposes no partial creation certificate"
  assert regular.effectCreatedAccountFactCount.value == 1,
    "new before a broader deletion also retains independent enabled membership"
  let planned = prepare(fixture, first, second, slot = HeaderSlot(50000))
  if checkpoint:
    var expected = rows(fixture, 1, 0)
    addChild(expected, childId(42, HeaderSlot(50000)), 42, HeaderSlot(50000))
    var state = fixture.state
    discard applyAccumulationBatch(state, planned.value).value
    sameRoot(state, expected) # Rolled-back deletion neither removes the target nor credits its balance to the creator.
  else:
    assert planned.error == AccumulationBatchError.UnsupportedAccountEffects,
      "selected existing-account deletion remains explicitly gated"

block collision:
  let fixture = batchFixture(firstEnvelope = envelope(), secondEnvelope = envelope())
  let first = execute(fixture, word = entropy(14592))
  let second = execute(fixture, 1, word = entropy(94245))
  assert uint64(machineInfo(first.value.machine).value.registers[7]) == 1197275345 and
    uint64(machineInfo(second.value.machine).value.registers[7]) == 1197275345,
    "frozen real hash collision makes two genuine guests choose the same child ID"
  assert prepare(fixture, first, second).error == AccumulationBatchError.UnsupportedAccountEffects and
    prepare(fixture, second, first).error == AccumulationBatchError.UnsupportedAccountEffects,
    "conflicting child records never choose a winner or publish either debit"

block limits_and_default:
  let fixture = batchFixture(firstEnvelope = envelope(repeat = true), secondEnvelope = envelope())
  let first = execute(fixture)
  let second = execute(fixture, 1)
  assert execute(fixture, children = 1).error == AccumulationDispatchError.LimitExceeded,
    "second child exceeds the per-execution proof ceiling before its candidate map is published"
  let foreign = batchFixture(firstEnvelope = envelope(repeat = true), secondEnvelope = envelope())
  assert prepare(fixture, execute(foreign), second).error == AccumulationBatchError.SourceMismatch,
    "matching created child contents cannot replace the retained common input/prior owners"
  assert prepare(fixture, first, second, children = 0).error ==
      AccumulationBatchError.LimitExceeded,
    "zero aggregate child budget never authorizes copied child payloads"
  assert prepare(fixture, first, second, children = 2).error ==
      AccumulationBatchError.LimitExceeded,
    "aggregate child publication count is independent from each guest's ceiling"
  assert prepare(fixture, first, second, children = 3).error == AccumulationBatchError.None, "exact child count boundary"
  let disabled = execute(fixture, children = 0)
  assert disabled.error == AccumulationDispatchError.None and prepare(fixture, disabled,
      second).error == AccumulationBatchError.UnsupportedAccountEffects,
    "zero child proof capacity retains successful local creation and the original publication gate"
  let disabledContext = normalizeAccumulationOutcome(disabled).value.outcomeContext.value
  assert disabledContext.effectCreatedAccountFactCount.error ==
      AccumulationEffectError.CreatedAccountsDisabled,
    "disabled creation history never certifies an empty set"
  assert disabledContext.effectCreatedAccountFactAt(AccumulationCreatedAccountIndex(0)).error ==
    AccumulationEffectError.CreatedAccountsDisabled, "disabled extraction keeps its typed refusal"
  let boundedBroader = batchFixture(firstEnvelope = envelope(beforeStorage = true, repeat = true),
    secondEnvelope = envelope())
  assert execute(boundedBroader, children = 1, keys = 0).error ==
      AccumulationDispatchError.LimitExceeded,
    "unsupported legacy ancestry cannot bypass enabled creation capacity"
  let broader = batchFixture(firstEnvelope = envelope(beforeStorage = true),
      secondEnvelope = envelope())
  let unsupported = execute(broader, keys = 0)
  assert unsupported.error == AccumulationDispatchError.None and prepare(broader, unsupported,
      execute(broader, 1)).error == AccumulationBatchError.UnsupportedAccountEffects,
    "new cannot relabel an earlier unsupported mutation as safe creation"
  let broaderContext = normalizeAccumulationOutcome(unsupported).value.outcomeContext.value
  assert broaderContext.effectAccountScope.value == AccumulationAccountScope.Unsupported
  assert broaderContext.effectCreatedAccountCount.error == AccumulationEffectError.InvalidState,
    "legacy scope-gated creation access remains refused"
  assert broaderContext.effectCreatedAccountFactCount.value == 1,
    "a successful new after an unsupported write retains enabled independent proof"
  var fact = broaderContext.effectCreatedAccountFactAt(AccumulationCreatedAccountIndex(0)).value
  assert uint32(fact.service) == uint32(childId(42)), "actual selected child survives unrelated lineage gate"
  fact.service = ServiceIndex(0)
  let retained = broaderContext.effectCreatedAccountFactAt(AccumulationCreatedAccountIndex(0)).value
  assert uint32(retained.service) == uint32(childId(42)), "copied facts cannot mutate retained identity"
  assert broaderContext.effectCreatedAccountFactAt(AccumulationCreatedAccountIndex(high(
      uint64))).error ==
    AccumulationEffectError.InvalidIndex, "full-width proof index refuses before narrowing"
  assert default(AccumulationEffectContext).effectCreatedAccountFactCount.error ==
    AccumulationEffectError.Uninitialized, "default independent proof is not enabled empty"
  assert default(AccumulationEffectContext).effectCreatedAccountFactAt(
      AccumulationCreatedAccountIndex(0)).error ==
    AccumulationEffectError.Uninitialized, "default independent fact has no payload"
  assert default(AccumulationEffectContext).effectCreatedAccountCount.error ==
      AccumulationEffectError.Uninitialized,
    "default effects do not certify an empty creation set"
  assert default(AccumulationEffectContext).effectCreatedAccountAt(AccumulationCreatedAccountIndex(
      0)).error == AccumulationEffectError.Uninitialized,
    "default creation facts expose no payload"

# Child request publication precedes provision fulfillment; final code preimages are still a separate terminal phase.
let fixture = batchFixture(firstEnvelope = envelope(provide = true), secondEnvelope = envelope())
let first = execute(fixture)
let second = execute(fixture, 1)
let plan = prepare(fixture, first, second).value
block provision_and_atomicity:
  var expected = rows(fixture)
  addChild(expected, childId(42), 42, provided = true)
  addChild(expected, childId(99), 99)
  var state = fixture.state
  discard applyAccumulationBatch(state, plan).value
  sameRoot(state, expected)
  let current = state.snapshot.value
  failHash(1)
  assert applyAccumulationBatch(state, plan).error == AccumulationBatchError.StaleState and
      hashCalls() == 0,
    "stale child publication cannot replay creator debits"
  failHash(0)
  assert sameStateSnapshot(current, state.snapshot.value), "stale refusal preserves exact published owner"
  var target = fixture.state
  let prior = target.snapshot.value
  failHash(1)
  assert applyAccumulationBatch(target, plan).storeError == StateStoreError.BackendFailure,
    "failed account-root computation publishes no children or debits"
  failHash(0)
  assert sameStateSnapshot(prior, target.snapshot.value), "account phase remains atomic"

block late_provision_failure:
  # Refuse every real incremental hash, including provision work after completed child/debit writes.
  assertBatchHashRollback(fixture.state, plan)

block detached_proof:
  var owned = default(PreparedAccumulationBatch)
  var state = default(StateStore)
  block sources:
    let local = batchFixture(firstEnvelope = envelope(), secondEnvelope = envelope())
    let first = execute(local)
    let context = normalizeAccumulationOutcome(first).value.outcomeContext.value
    var copied = context.effectCreatedAccountAt(AccumulationCreatedAccountIndex(0)).value
    copied.service = ServiceIndex(0)
    copied.requestKey = chapterKey(StateChapter(250))
    assert uint32(context.effectCreatedAccountAt(AccumulationCreatedAccountIndex(
        0)).value.service) == uint32(childId(42)),
      "copied facts cannot rewrite the retained creation proof"
    owned = prepare(local, first, execute(local, 1)).value
    state = local.state # Caller contexts, executions and fixture are released before the plan is applied.
  discard applyAccumulationBatch(state, owned).value
  assert state.snapshot.value.lookup(chapterServiceKey(StateChapter(255), childId(42))).error ==
      StateStoreError.None,
    "plan retains selected child values after all caller execution owners disappear"

# Complete funding modes publish self debit/child pools, while foreign debits cannot opt into creation provenance.
block creation_funding_publication:
  for foreign in [false, true]:
    for mode in 0'u64..3:
      let instructions = @[registerImmediate(7, (if foreign: 77'u64 else: high(uint64))),
          registerImmediate(8, high(uint64)), registerImmediate(9, mode), registerImmediate(10,
              196608),
          @[10'u8, 20], @[50'u8, 0]]
      let sourceEntry = serviceMetadataEntry(ServiceIndex(77), ServiceMetadata(
          balance: AccountBalance(10), supervisorBalance: AccountBalance(4),
              supervisor: ServiceIndex(42), supervisorCreated: AccountSlot(0),
          created: AccountSlot(7)), ByteLimit(ServiceMetadataBytes)).value
      var fixture = batchFixture(incoming = false, firstEnvelope = guestEnvelope(instructions,
          input), secondEnvelope = guestEnvelope([@[50'u8, 0]]), extra = @[sourceEntry])
      let ownKey = chapterServiceKey(StateChapter(255), ServiceIndex(42))
      let original = fixture.state.snapshot.value.lookup(ownKey).value.bytes
      var own = decodeServiceMetadata(original, ByteLimit(ServiceMetadataBytes)).value.metadata
      own.supervisorBalance = AccountBalance(4)
      let ownEntry = serviceMetadataEntry(ServiceIndex(42), own, ByteLimit(
          ServiceMetadataBytes)).value
      discard fixture.state.apply([StateWrite(key: ownKey, kind: StateWriteKind.Put,
          value: ownEntry.value)]).value
      let prior = fixture.state.snapshot.value
      let first = batchExecution(fixture, 0, parameters = profile(), createdAccounts = ElementLimit(
          1), copyLimit = MemoryByteLimit(60), serviceProbes = ServiceProbeLimit(1))
      let second = batchExecution(fixture, 1, parameters = profile())
      assert first.error == AccumulationDispatchError.None, "funded creation completes within explicit allocation limits"
      let selected = first.effects.effectContext(AccumulationDimension.Regular).value
      let child = ServiceIndex(uint32(uint64(machineInfo(first.value.machine).value.registers[7])))
      let childKey = chapterServiceKey(StateChapter(255), child)
      let childBytes = selected.effectAccounts.value.lookup(childKey).value.bytes
      let childRecord = decodeServiceMetadata(childBytes, ByteLimit(
          ServiceMetadataBytes)).value.metadata
      assert uint64(childRecord.balance) == (if mode < 2: 1'u64 else: 0'u64) and
          uint64(childRecord.supervisorBalance) == (if mode < 2: 0'u64 else: 1'u64),
          "flat one-unit threshold seeds exactly the selected child pool"
      let executions = [first, second]
      let plan = prepareCompleteAccumulationBatch(fixture.inputs, prior, executions, [], HeaderSlot(
          128), batchPolicy(createdAccounts = 1))
      if foreign:
        assert selected.effectAccountScope.value == AccumulationAccountScope.Unsupported and
            plan.error == AccumulationBatchError.UnsupportedAccountEffects,
            "foreign payer cannot be certified by bounded child creation facts"
        assert fixture.state.snapshot.value.lookup(chapterServiceKey(StateChapter(255),
            child)).error == StateStoreError.MissingKey,
            "refused foreign publication leaves child absent in the complete prior"
      else:
        assert plan.error == AccumulationBatchError.None, "self funding modes retain complete creation publication"
        discard applyAccumulationBatch(fixture.state, plan.value).value
        let published = fixture.state.snapshot.value
        let paid = decodeServiceMetadata(published.lookup(ownKey).value.bytes, ByteLimit(
            ServiceMetadataBytes)).value.metadata
        assert uint64(paid.balance) == (if mode in [0'u64, 2]: 9'u64 else: 10'u64) and
            uint64(paid.supervisorBalance) == (if mode in [1'u64, 3]: 3'u64 else: 4'u64),
            "published source debit selects exactly one pool"
        assert published.lookup(chapterServiceKey(StateChapter(255), child)).value.bytes ==
            selected.effectAccounts.value.lookup(chapterServiceKey(StateChapter(255),
                child)).value.bytes,
            "published child retains both pools and invoker provenance exactly"

let before = getOccupiedMem()
for iteration in 0..<1000:
  let owned = prepare(fixture, execute(fixture), second).value
  var state = fixture.state
  discard applyAccumulationBatch(state, owned).value
  assert state.snapshot.value.lookup(chapterServiceKey(StateChapter(255), childId(42))).error ==
      StateStoreError.None,
    "fresh guest, creation proof, debit and provision owners release after publication"
let after = getOccupiedMem()
assert before == after, "created-account publication releases every intermediate ARC graph"
recordArcRelease("pvm_created_accounts", 1000, before, after)
echo "PVM created accounts passed"
echo "ARC_RELEASE cycles=1000 unchanged"
