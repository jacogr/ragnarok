# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_deleted_accounts_arc_release"}

## Real eligible ejections publish bounded selected removals/credits and gate conflicts with participating service work.

import std/[assertions, syncio]
import ../../../src/chain/parameters
import ../../../src/state/[accumulation_batch, accumulation_dispatch, accumulation_effects,
  accumulation_context, accumulation_outcome, accumulation_invocation, accumulation_service,
  accumulation_inputs, accumulation_skip, accumulation_provisions, store]
import ../../../src/codec/[bounded, composite, header, state_accounts, state_service_values,
  state_requests, state_layout, state_trie, state_safrole, state_privileges]
import ../../../src/pvm/machine
import ../../../src/crypto/primitives
import ../../support/[accumulation_batch_context, accumulation_provision_integration,
  pvm_accumulation_program, pvm_accumulation_context, arc_evidence, accumulation_batch_hash_failures]

# Observe/inject genuine backend refusals after actual executions and prepared publication plans exist.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}

let slot = HeaderSlot(50000)
let blob = @[5'u8, 7, 9]
let hash = ServicePreimageHash(array[32, byte](blake2b256(blob).value))
# Literal flat funding and 19,200-slot expiry make old targets eligible independently of current host observations.
proc profile(): Parameters =
  var bytes = encodeParameters(pvmParameters())
  for index in 0..<24:
    bytes[index] = 0 # Only the optional creation interaction consumes one unit of flat funding.
  bytes[16] = 1
  for index in 0..<4:
    bytes[74+index] = byte((14400'u32 shr (8*index)) and 255)
  decodeParameters(bytes).value

# The exact request hash occupies the first 32 guest bytes; a separate byte supports self-storage witnesses.
proc guestInput(): seq[byte] =
  result = newSeq[byte](65)
  for index, octet in array[32, byte](hash):
    result[index] = octet
  result[32] = 81
  for index, octet in array[32, byte](blake2b256([73'u8]).value):
    result[33+index] = octet # A separate one-byte code hash tests the existing provision-copy budget.
let input = guestInput()

# Empty junior accounts bind the invoker's actual creation slot; no request/preimage footprint remains.
proc targetEntries(service: uint32, balance: uint64): seq[StateEntry] =
  @[serviceMetadataEntry(ServiceIndex(service), ServiceMetadata(balance: AccountBalance(balance),
    supervisor: ServiceIndex(42), supervisorCreated: AccountSlot(0), created: AccountSlot(0)),
    ByteLimit(ServiceMetadataBytes)).value]

# Share instruction framing; each optional suffix tests one supported or refused interaction.
proc append(code: var seq[seq[byte]], instructions: seq[seq[byte]]) =
  for instruction in instructions:
    code.add(instruction) # Preserve authored opcode boundaries without replacing the production engine.

# Authored four-byte signed immediates keep combined recreation/self-effect programs below 128 bytes.
proc compactImmediate(index: byte, value: uint64): seq[byte] =
  assert value <= 0x7fffffff'u64 or value == high(uint64), "fixture immediates fit signed E4 or minus one"
  result = @[51'u8, index]
  for offset in 0..<4:
    # Full-width minus one is represented by four 0xff bytes and sign-extended by load_imm.
    result.add(byte((value shr (offset*8)) and 255))

proc envelope(checkpoint = false, panic = false, repeat = false, target = 77'u64,
    storage = false, upgrade = false, create = false, provide = false,
    beforeStorage = false, recreate = false, beforeCreate = false,
    provideRecreated = false): seq[byte] =
  var code: seq[seq[byte]] = @[]
  let write = @[@[51'u8, 7, 255], compactImmediate(8, 65536), compactImmediate(9, 1),
    compactImmediate(10, 196640), compactImmediate(11, 1), @[10'u8, 5]]
  if beforeCreate:
    append(code, @[compactImmediate(7, high(uint64)), compactImmediate(8, high(uint64)),
      compactImmediate(9, 0), compactImmediate(10, 196673), @[10'u8,
          20]]) # Eject must retain a child created earlier in this same invocation.
  if beforeStorage:
    append(code, write) # A disabled earlier self trace must remain unsupported even after a traced eject.
  append(code, @[compactImmediate(7, target), compactImmediate(8, 196608), @[10'u8, 23]])
  if checkpoint:
    code.add(@[10'u8, 19]) # Retain the first removal and its beneficiary credit together.
  if repeat:
    append(code, @[compactImmediate(7, 78), @[10'u8, 23]]) # r8 still holds the exact request-hash pointer.
  if storage:
    append(code, write) # Supported self-key mutation must retain deletion membership.
  if upgrade:
    append(code, @[compactImmediate(7, high(uint64)), compactImmediate(8, 196608),
      compactImmediate(9, 17), compactImmediate(10, 19), @[10'u8, 21]])
  if create or recreate:
    append(code, @[compactImmediate(7, high(uint64)),
      compactImmediate(8, if recreate: 77'u64 else: high(uint64)), compactImmediate(9, 0),
      compactImmediate(10, 196673), @[10'u8, 20]]) # Current mode0 reads the complete independent60-byte request.

  if provideRecreated:
    append(code, @[compactImmediate(7, 77), compactImmediate(8, 65536),
      compactImmediate(9, 1), @[10'u8, 28]]) # The local empty replacement request is absent from the preserved prior account.
  if provide:
    append(code, @[compactImmediate(7, 42), compactImmediate(8, 65536),
      compactImmediate(9, 1), @[10'u8, 28]]) # Unrelated requested provision must survive the account-removal phase.
  code.add(if panic: @[0'u8] else: @[50'u8, 0])
  var wire = input
  var request = newSeq[byte](60)
  for index in 0..<32:
    request[index] = input[(if provideRecreated: 33 else: 0)+index] # Select the independently hashed requested code.
  request[32] = (if provideRecreated: 1'u8 else: 3'u8)
  request[36] = 7
  request[44] = 9
  for octet in request:
    wire.add(octet) # Fixed hash/E4 length/E8 minimum gas/E8 minimum transfer/E8 gratis at writable offset65.
  guestEnvelope(code, wire)

# Build complete shared maps with real removable metadata, histories and present preimages.
proc setup(code: seq[byte], two = false, incoming = true): BatchFixture =
  var extra = targetEntries(77, 5)
  if two:
    for entry in targetEntries(78, 6):
      extra.add(entry) # A second distinct target makes per-execution/aggregate count boundaries observable.
  batchFixture(firstEnvelope = code, secondEnvelope = guestEnvelope([@[50'u8, 0]]), extra = extra,
      incoming = incoming)

# Genuine registrar authority allows the occupied prior ID only after a successful local eject.
proc registrarSetup(code: seq[byte]): BatchFixture =
  result = setup(code)
  let roles = privilegeStateEntry(PrivilegeState(registrar: ServiceIndex(42), assigners: @[
      ServiceIndex(0), ServiceIndex(0)]), pvmContextConfig().privileges).value
  for index in 0..<result.entries.len:
    # Change only the authored privilege row before capturing a new complete immutable prior.
    if array[31, byte](result.entries[index].key) == array[31, byte](roles.key):
      result.entries[index] = roles
  result.state = newStateStore(result.entries, integrationStoreLimits()).value

proc execute(fixture: BatchFixture, index = 0'u64, removed = 2'u64,
    keys = 1'u64): AccumulationDispatchResult =
  batchExecution(fixture, index, slot, parameters = profile(), copyLimit = MemoryByteLimit(60),
      deletedAccounts = ElementLimit(removed),
    createdAccounts = ElementLimit(1), accountWriteKeys = ElementLimit(keys),
        serviceProbes = ServiceProbeLimit(1))

proc prepare(fixture: BatchFixture, first, second: AccumulationDispatchResult,
    removed = 2'u64): AccumulationBatchResult[PreparedAccumulationBatch] =
  let prior = fixture.state.snapshot.value
  let executions = [first, second]
  prepareCompleteAccumulationBatch(fixture.inputs, prior, executions, [], slot,
    batchPolicy(selfWrites = 2, selfValueBytes = 2, createdAccounts = 1, deletedAccounts = removed))

# Construct an independent full map by dropping exactly the seeded target records and applying literal credits.
proc expected(fixture: BatchFixture, removed: seq[uint32], incoming = true, storage = false,
    upgrade = false, created = false, provided = false, recreated = false): seq[StateEntry] =
  var reclaimed = if recreated: 5'u64 else: 0'u64
  var removedKeys: seq[StateKey] = @[]
  for service in removed:
    let balance = if service == 77: 5'u64 elif service == 78: 6'u64 else: 20'u64
    reclaimed += balance # At most two authored targets with small literal balances.
    for entry in targetEntries(service, balance):
      removedKeys.add(entry.key)
  result = @[]
  for entry in fixture.entries:
    var keep = true
    for key in removedKeys:
      if array[31, byte](entry.key) == array[31, byte](
          key): keep = false # Remove the entire known eligible target representation.
    if keep:
      var copied = StateEntry(key: entry.key, value: entry.value)
      for ordinal, service in [42'u32, 99'u32]:
        if array[31, byte](entry.key) == array[31, byte](chapterServiceKey(StateChapter(255),
            ServiceIndex(service))):
          var account = decodeServiceMetadata(entry.value, ByteLimit(
              ServiceMetadataBytes)).value.metadata
          account.balance = AccountBalance(if ordinal == 0: (
              if incoming: 17'u64 else: 10'u64)+reclaimed-(if created or
                  recreated: 1'u64 else: 0'u64) else: (
              if incoming: 31'u64 else: 20'u64))
          if ordinal == 0 and storage:
            account.storageItems = AccountStorageItems(1)
            account.storageBytes = AccountStorageBytes(36) # One raw key/value adds its exact footprint.
          if ordinal == 0 and upgrade:
            account.codeHash = CodeHash(array[32, byte](hash))
            account.minimumAccumulationGas = Gas(17)
            account.minimumTransferGas = Gas(19)
          copied = serviceMetadataEntry(ServiceIndex(service), account, ByteLimit(
              ServiceMetadataBytes)).value
      result.add(copied) # Retain all unrelated original chapters, code and account entries.
  if storage:
    result.add(serviceStorageEntry(ServiceIndex(42), @[73'u8], @[81'u8],
      ServiceEntryLimits(keyBytes: ByteLimit(1), valueBytes: ByteLimit(1))).value)
  if created:
    let child = initialAccumulationService(ServiceIndex(42), default(StateEntropyWord), slot).value
    result.add(serviceMetadataEntry(child, ServiceMetadata(codeHash: CodeHash(array[32, byte](hash)),
      balance: AccountBalance(1), storageItems: AccountStorageItems(2),
          storageBytes: AccountStorageBytes(84),
      minimumAccumulationGas: Gas(7), minimumTransferGas: Gas(9), created: AccountSlot(uint32(
          slot)), supervisor: ServiceIndex(42), supervisorCreated: AccountSlot(0),
              parent: ServiceIndex(42)), ByteLimit(ServiceMetadataBytes)).value)
    result.add(serviceRequestEntry(child, hash, RequestLength(3), requestedHistory(),
      RequestEntryConfig(keyBytes: ByteLimit(32), history: RequestHistoryConfig(items: ElementLimit(
          3), maxBytes: ByteLimit(13)))).value)
  if provided:
    let digest = ServicePreimageHash(array[32, byte](blake2b256([73'u8]).value))
    let request = serviceRequestEntry(ServiceIndex(42), digest, RequestLength(1), availableHistory(
        RequestSlot(uint32(slot))),
      RequestEntryConfig(keyBytes: ByteLimit(32), history: RequestHistoryConfig(items: ElementLimit(
          3), maxBytes: ByteLimit(13)))).value
    for index in 0..<result.len:
      if array[31, byte](result[index].key) == array[31, byte](request.key):
        result[index] = request # Independent final history is fulfilled at the exact invocation slot.
    result.add(servicePreimageEntry(ServiceIndex(42), digest, @[73'u8],
      ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(1))).value)

proc sameRoot(state: StateStore, rows: seq[StateEntry]) =
  let wanted = newStateStore(rows, integrationStoreLimits()).value
  assert array[32, byte](state.snapshot.value.commitment.root) == array[32, byte](
      wanted.snapshot.value.commitment.root),
    "complete independent root includes exact removals, beneficiary credits and unchanged unrelated entries"

for checkpoint in [false, true]:
  for panic in [false, true]:
    let fixture = setup(envelope(checkpoint, panic, repeat = true), two = true)
    let first = execute(fixture)
    let second = execute(fixture, 1)
    let selected = normalizeAccumulationOutcome(first).value.outcomeContext.value
    let removed = if panic: (if checkpoint: @[77'u32] else: newSeq[uint32](0)) else: @[77'u32, 78]
    assert selected.effectDeletedAccountCount.value == removed.len, "checkpoint selects the exact deletion proof and reclaimed balance"
    assert first.effects.effectContext(AccumulationDimension.Regular).value.effectDeletedAccountCount.value == 2,
      "both real regular ejections retain their independent target keys"
    let plan = prepare(fixture, first, second).value
    var state = fixture.state
    discard applyAccumulationBatch(state, plan).value
    sameRoot(state, expected(fixture, removed))
    var reverse = fixture.state
    discard applyAccumulationBatch(reverse, prepare(fixture, second, first).value).value
    sameRoot(reverse, expected(fixture, removed))
    assert plan.batchInfo.value.deletedAccounts == removed.len and
        plan.batchInfo.value.accountWrites == 2,
      "deleted target count stays separate from invoking metadata records"
    assert selected.effectDeletedAccountAt(AccumulationDeletedAccountIndex(high(uint64))).error ==
        AccumulationEffectError.InvalidIndex,
      "invalid full-width deletion ordinal never narrows to a real target"

for variant in 0..<5:
  let fixture = setup(envelope(storage = variant == 0, upgrade = variant == 1, create = variant ==
      2, provide = variant == 3, beforeCreate = variant == 4))
  let plan = prepare(fixture, execute(fixture), execute(fixture, 1)).value
  var state = fixture.state
  discard applyAccumulationBatch(state, plan).value
  sameRoot(state, expected(fixture, @[77'u32], storage = variant == 0,
    upgrade = variant == 1, created = variant in [2, 4], provided = variant == 3))

block no_incoming:
  let fixture = setup(envelope(), incoming = false)
  var state = fixture.state
  discard applyAccumulationBatch(state, prepare(fixture, execute(fixture), execute(fixture,
      1)).value).value
  sameRoot(state, expected(fixture, @[77'u32], incoming = false)) # Reclamation publishes even without a prior incoming-credit fork.

block budgets_and_defaults:
  let fixture = setup(envelope(repeat = true), two = true)
  let first = execute(fixture)
  let second = execute(fixture, 1)
  assert execute(fixture, removed = 1).error == AccumulationDispatchError.LimitExceeded, "second ejection exceeds local proof capacity"
  assert prepare(fixture, first, second, removed = 0).error == AccumulationBatchError.LimitExceeded,
    "zero aggregate deletion budget never authorizes target descriptors"
  assert prepare(fixture, first, second, removed = 1).error == AccumulationBatchError.LimitExceeded, "aggregate deletion budget is independent"
  assert prepare(fixture, first, second, removed = 2).error == AccumulationBatchError.None, "exact two-target boundary"
  let disabled = execute(fixture, removed = 0)
  assert disabled.error == AccumulationDispatchError.None and prepare(fixture, disabled,
      second).error == AccumulationBatchError.UnsupportedAccountEffects,
    "zero proof policy retains old successful local eject and publication gate"
  let broader = setup(envelope(beforeStorage = true))
  let unsupported = execute(broader, keys = 0)
  assert prepare(broader, unsupported, execute(broader, 1)).error ==
      AccumulationBatchError.UnsupportedAccountEffects,
    "eject cannot relabel an earlier unsupported self mutation"
  let foreign = setup(envelope(repeat = true), two = true)
  assert prepare(fixture, execute(foreign), second).error == AccumulationBatchError.SourceMismatch, "foreign equal-content proofs cannot replace exact input/prior owners"
  assert default(AccumulationEffectContext).effectDeletedAccountCount.error ==
      AccumulationEffectError.Uninitialized, "default context has no empty deletion proof"
  assert default(AccumulationEffectContext).effectDeletedAccountAt(AccumulationDeletedAccountIndex(
      0)).error == AccumulationEffectError.Uninitialized, "default deletion facts have no payload"

block participating_skip_conflict:
  # Nonexecution alone proves neither unchanged metadata nor collision validity.
  for incoming in [false, true]:
    var fixture = setup(envelope(target = 99), incoming = incoming)
    let old = decodeServiceMetadata(fixture.state.snapshot.value.lookup(chapterServiceKey(
        StateChapter(255), ServiceIndex(99))).value.bytes, ByteLimit(
            ServiceMetadataBytes)).value.metadata
    let codeKey = servicePreimageKey(ServiceIndex(99), ServicePreimageHash(array[32, byte](
        old.codeHash)), ByteLimit(32)).value
    let requestKey = integrationRequest(99, @[81'u8]).key
    let accountKey = chapterServiceKey(StateChapter(255), ServiceIndex(99))
    var entries: seq[StateEntry] = @[]
    for entry in fixture.entries:
      var keep = true
      for oldKey in [accountKey, codeKey, requestKey]:
        if array[31, byte](entry.key) == array[31, byte](
            oldKey): keep = false # Drop each obsolete target component without a wrapped compound predicate.
      if keep:
        entries.add(entry) # Replace target 99 with its coherent eligible owned request/preimage representation.
    for entry in targetEntries(99, 20): entries.add(entry)
    fixture.entries = entries
    fixture.state = newStateStore(entries, integrationStoreLimits()).value
    let first = execute(fixture)
    let prior = fixture.state.snapshot.value
    let service = prepareAccumulationService(fixture.inputs, InvocationServiceIndex(1), prior, slot,
      AccumulationServiceConfig(codeLimit: ServiceCodeLimit(512), preimageBytes: ByteLimit(1024))).value
    let skipped = finishUninvokedAccumulation(service).value
    assert skipped.skipInfo.value.code == AccumulationCodeStatus.Missing, "real owned target has missing executable code"
    let credited = skipped.skipState.value.lookup(accountKey).value.bytes
    let expectedCredit = if incoming: 31'u64 else: 20'u64
    assert uint64(decodeServiceMetadata(credited, ByteLimit(
        ServiceMetadataBytes)).value.metadata.balance) == expectedCredit,
      "missing-code skips retain actual incoming credit without executing"
    let selected = normalizeAccumulationOutcome(first).value.outcomeContext.value
    let beneficiary = selected.effectAccounts.value.lookup(chapterServiceKey(StateChapter(255),
        ServiceIndex(42))).value.bytes
    let expectedBeneficiary = if incoming: 37'u64 else: 30'u64
    assert uint64(decodeServiceMetadata(beneficiary, ByteLimit(
        ServiceMetadataBytes)).value.metadata.balance) == expectedBeneficiary,
      "eject reclaims only the target balance visible in the common prior"
    let complete = prepareCompleteAccumulationBatch(fixture.inputs, prior, [first], [skipped], slot,
        batchPolicy(deletedAccounts = 1))
    assert complete.error == AccumulationBatchError.UnsupportedAccountEffects,
      "participating target validity remains gated with or without incoming credit"
    assert sameStateSnapshot(prior, fixture.state.snapshot.value),
      "refused participating-target preparation preserves the exact prior owner"
    let subset = prepareAccumulationBatch(fixture.inputs, prior, [first], slot, batchPolicy(
        deletedAccounts = 1)).value
    assert not subset.batchInfo.value.completeInputs, "explicit subset certifies no omitted target work"
    var state = fixture.state
    discard applyAccumulationBatch(state, subset).value
    sameRoot(state, expected(fixture, @[99'u32], incoming = incoming)) # Omitted target receives no extra credit; its prior twenty-unit balance is reclaimed exactly once.

block recreate_prior_target:
  for checkpoint in [false, true]:
    for panic in [false, true]:
      # Checkpoint precedes recreation: panic selects a real removal only when that checkpoint exists.
      let fixture = registrarSetup(envelope(checkpoint = checkpoint, panic = panic,
          recreate = true))
      let first = execute(fixture)
      let second = execute(fixture, 1)
      assert uint64(machineInfo(first.value.machine).value.registers[7]) == 77,
        "guest really recreated the ejected reserved target before terminal selection"
      let recreated = not panic
      let removed = if panic and checkpoint: @[77'u32] else: newSeq[uint32](0)
      let plan = prepare(fixture, first, second).value
      assert plan.batchInfo.value.deletedAccounts == removed.len and
          plan.batchInfo.value.createdAccounts == 0,
        "batch membership counts describe final projection rather than historical host calls"
      let selected = plan.batchOutcomeAt(AccumulationProvisionSourceIndex(
          0)).value.outcomeContext.value
      assert selected.effectCreatedAccountCount.value == (if recreated: 1 else: 0),
        "retained selected outcome still exposes exact creation provenance"
      for reverse in [false, true]:
        # Submission order cannot choose a different survivor or redistribute reclaimed balances.
        let ordered = if reverse: prepare(fixture, second, first).value else: plan
        var state = fixture.state
        discard applyAccumulationBatch(state, ordered).value
        sameRoot(state, expected(fixture, removed, recreated = recreated))

  for variant in 0..<4:
    # Other supported self effects must retain the same n/m membership projection.
    let fixture = registrarSetup(envelope(recreate = true, storage = variant == 0,
      upgrade = variant == 1, provide = variant == 2, provideRecreated = variant == 3))
    let first = execute(fixture)
    let second = execute(fixture, 1)
    let plan = prepare(fixture, first, second).value
    if variant == 3:
      # Distinguish local provision acceptance from the later preserved-prior request check.
      assert uint64(machineInfo(first.value.machine).value.registers[7]) == 0,
        "provide into the recreated target really succeeds against its local empty request"
    var state = fixture.state
    discard applyAccumulationBatch(state, plan).value
    sameRoot(state, expected(fixture, @[], recreated = true, storage = variant == 0,
      upgrade = variant == 1, provided = variant == 2))
    assert prepare(fixture, first, second, removed = 0).error ==
        AccumulationBatchError.LimitExceeded,
      "ignored removal facts still consume aggregate traversal capacity"
    let shortCreation = prepareCompleteAccumulationBatch(fixture.inputs,
      fixture.state.snapshot.value,
      [first, second], [], slot, batchPolicy(selfWrites = 2, selfValueBytes = 2,
        createdAccounts = 0, deletedAccounts = 1))
    assert shortCreation.error == AccumulationBatchError.LimitExceeded,
      "ignored recreation facts still consume aggregate creation capacity"

block recreated_owner_and_failures:
  var owned = default(PreparedAccumulationBatch)
  var state = default(StateStore)
  var rows: seq[StateEntry] = @[]
  block sources:
    # Drop every external execution owner before applying or injecting private-phase failures.
    let fixture = registrarSetup(envelope(recreate = true, provide = true))
    owned = prepare(fixture, execute(fixture), execute(fixture, 1)).value
    rows = expected(fixture, @[], recreated = true, provided = true)
    state = fixture.state
  let prior = state.snapshot.value
  failHash(1)
  assert applyAccumulationBatch(state, owned).storeError == StateStoreError.BackendFailure,
    "recreation projection refuses an early account-root backend failure"
  failHash(0)
  assert sameStateSnapshot(prior, state.snapshot.value), "early refusal preserves the exact prior"
  # Cover real account and provision phases after all caller execution owners have gone away.
  assertBatchHashRollback(state, owned)
  discard applyAccumulationBatch(state, owned).value
  sameRoot(state, rows)
  let published = state.snapshot.value
  assert applyAccumulationBatch(state, owned).error == AccumulationBatchError.StaleState,
    "detached recreation plan cannot reclaim or debit a second time"
  assert sameStateSnapshot(published, state.snapshot.value), "stale refusal preserves publication ownership"

let fixture = setup(envelope(provide = true))
let first = execute(fixture)
let second = execute(fixture, 1)
let plan = prepare(fixture, first, second).value
block stale_and_backend:
  var state = fixture.state
  discard applyAccumulationBatch(state, plan).value
  let current = state.snapshot.value
  failHash(1)
  assert applyAccumulationBatch(state, plan).error == AccumulationBatchError.StaleState and
      hashCalls() == 0, "stale proof cannot reclaim a target balance twice"
  failHash(0)
  assert sameStateSnapshot(current, state.snapshot.value), "stale refusal retains exact intervening owner"
  var target = fixture.state
  let prior = target.snapshot.value
  failHash(1)
  assert applyAccumulationBatch(target, plan).storeError == StateStoreError.BackendFailure, "account-root failure publishes no deletion or credit"
  failHash(0)
  assert sameStateSnapshot(prior, target.snapshot.value), "early failure is atomic"
  # Exercise every actual hash without treating full-map constructor work as a mutation prefix.
  assertBatchHashRollback(target, plan)

block detached_owner:
  var owned = default(PreparedAccumulationBatch)
  var state = default(StateStore)
  block sources:
    let local = setup(envelope())
    let first = execute(local)
    let context = normalizeAccumulationOutcome(first).value.outcomeContext.value
    var copied = context.effectDeletedAccountAt(AccumulationDeletedAccountIndex(0)).value
    copied.service = ServiceIndex(0)
    assert uint32(context.effectDeletedAccountAt(AccumulationDeletedAccountIndex(
        0)).value.service) == 77, "copied facts cannot mutate deletion proof backing"
    owned = prepare(local, first, execute(local, 1)).value
    state = local.state # All caller execution/context owners disappear before application.
  discard applyAccumulationBatch(state, owned).value
  assert state.snapshot.value.lookup(chapterServiceKey(StateChapter(255), ServiceIndex(
      77))).error == StateStoreError.MissingKey, "plan retains target deletion after caller sources leave scope"

let recreatedFixture = registrarSetup(envelope(recreate = true))
let recreatedSecond = execute(recreatedFixture, 1)
let before = getOccupiedMem()
for iteration in 0..<1000:
  let owned = prepare(fixture, execute(fixture), second).value
  var state = fixture.state
  discard applyAccumulationBatch(state, owned).value
  assert state.snapshot.value.lookup(chapterServiceKey(StateChapter(255), ServiceIndex(
      77))).error == StateStoreError.MissingKey, "fresh execution, deletion proof and private publication owners release each cycle"
  let recreated = prepare(recreatedFixture, execute(recreatedFixture), recreatedSecond).value
  var retained = recreatedFixture.state
  discard applyAccumulationBatch(retained, recreated).value
  assert retained.snapshot.value.lookup(chapterServiceKey(StateChapter(255), ServiceIndex(
      77))).error == StateStoreError.None, "fresh final-domain projection retains prior target and releases all temporary owners"
let after = getOccupiedMem()
assert before == after, "deleted-account publication has stable ARC ownership"
recordArcRelease("pvm_deleted_accounts", 1000, before, after)
echo "PVM deleted accounts passed"
echo "ARC_RELEASE cycles=1000 unchanged"
