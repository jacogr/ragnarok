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
  pvm_accumulation_program, pvm_accumulation_context, arc_evidence]

# Observe/inject genuine backend refusals after actual executions and prepared publication plans exist.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
proc hashAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}

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
  result = newSeq[byte](33)
  for index, octet in array[32, byte](hash):
    result[index] = octet
  result[32] = 81
let input = guestInput()

# Owned target metadata names the invoker by raw E32 identity and has exactly one expired request/preimage.
proc targetEntries(service: uint32, balance: uint64): seq[StateEntry] =
  var identity = default(array[32, byte])
  identity[0] = 42
  @[serviceMetadataEntry(ServiceIndex(service), ServiceMetadata(codeHash: CodeHash(identity),
      balance: AccountBalance(balance), storageItems: AccountStorageItems(2),
          storageBytes: AccountStorageBytes(84)), ByteLimit(89)).value,
    serviceRequestEntry(ServiceIndex(service), hash, RequestLength(3),
      unavailableHistory(RequestSlot(5), RequestSlot(7)), RequestEntryConfig(keyBytes: ByteLimit(32),
        history: RequestHistoryConfig(items: ElementLimit(3), maxBytes: ByteLimit(13)))).value,
    servicePreimageEntry(ServiceIndex(service), hash, blob,
      ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(3))).value]

# Share instruction framing; each optional suffix tests one supported or refused interaction.
proc append(code: var seq[seq[byte]], instructions: seq[seq[byte]]) =
  for instruction in instructions:
    code.add(instruction) # Preserve authored opcode boundaries without replacing the production engine.

proc envelope(checkpoint = false, panic = false, repeat = false, target = 77'u64,
    storage = false, upgrade = false, create = false, provide = false,
    beforeStorage = false, recreate = false, beforeCreate = false): seq[byte] =
  var code: seq[seq[byte]] = @[]
  let write = @[registerImmediate(7, 65536), registerImmediate(8, 1),
    registerImmediate(9, 196640), registerImmediate(10, 1), @[10'u8, 5]]
  if beforeCreate:
    append(code, @[registerImmediate(7, 196608), registerImmediate(8, 3),
      registerImmediate(9, 7), registerImmediate(10, 9), registerImmediate(11, 0),
      registerImmediate(12, high(uint64)), @[10'u8,
          19]]) # Eject must retain a child created earlier in this same invocation.
  if beforeStorage:
    append(code, write) # A disabled earlier self trace must remain unsupported even after a traced eject.
  append(code, @[registerImmediate(7, target), registerImmediate(8, 196608), @[10'u8, 22]])
  if checkpoint:
    code.add(@[10'u8, 18]) # Retain the first removal and its beneficiary credit together.
  if repeat:
    append(code, @[registerImmediate(7, 78), @[10'u8, 22]]) # r8 still holds the exact request-hash pointer.
  if storage:
    append(code, write) # Supported self-key mutation must retain deletion membership.
  if upgrade:
    append(code, @[registerImmediate(7, 196608), registerImmediate(8, 17),
      registerImmediate(9, 19), @[10'u8, 20]])
  if create or recreate:
    append(code, @[registerImmediate(7, 196608), registerImmediate(8, 3),
      registerImmediate(9, 7), registerImmediate(10, 9), registerImmediate(11, 0),
      registerImmediate(12, if recreate: 77'u64 else: high(uint64)), @[10'u8,
          19]]) # Recreating a prior ID is a separate explicit batch gate.
  if provide:
    append(code, @[registerImmediate(7, 42), registerImmediate(8, 65536),
      registerImmediate(9, 1), @[10'u8, 27]]) # Unrelated requested provision must survive the account-removal phase.
  code.add(if panic: @[0'u8] else: @[50'u8, 0])
  guestEnvelope(code, input)

# Build complete shared maps with real removable metadata, histories and present preimages.
proc setup(code: seq[byte], two = false, incoming = true): BatchFixture =
  var extra = targetEntries(77, 5)
  if two:
    for entry in targetEntries(78, 6):
      extra.add(entry) # A second distinct target makes per-execution/aggregate count boundaries observable.
  batchFixture(firstEnvelope = code, secondEnvelope = guestEnvelope([@[50'u8, 0]]), extra = extra,
      incoming = incoming)

proc execute(fixture: BatchFixture, index = 0'u64, removed = 2'u64,
    keys = 1'u64): AccumulationDispatchResult =
  batchExecution(fixture, index, slot, parameters = profile(), deletedAccounts = ElementLimit(removed),
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
    upgrade = false, created = false, provided = false): seq[StateEntry] =
  var reclaimed = 0'u64
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
          var account = decodeServiceMetadata(entry.value, ByteLimit(89)).value.metadata
          account.balance = AccountBalance(if ordinal == 0: (
              if incoming: 17'u64 else: 10'u64)+reclaimed-(if created: 1'u64 else: 0'u64) else: (
              if incoming: 31'u64 else: 20'u64))
          if ordinal == 0 and storage:
            account.storageItems = AccountStorageItems(1)
            account.storageBytes = AccountStorageBytes(36) # One raw key/value adds its exact footprint.
          if ordinal == 0 and upgrade:
            account.codeHash = CodeHash(array[32, byte](hash))
            account.minimumAccumulationGas = Gas(17)
            account.minimumTransferGas = Gas(19)
          copied = serviceMetadataEntry(ServiceIndex(service), account, ByteLimit(89)).value
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
          slot)), parent: ServiceIndex(42)), ByteLimit(89)).value)
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
        StateChapter(255), ServiceIndex(99))).value.bytes, ByteLimit(89)).value.metadata
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
    assert uint64(decodeServiceMetadata(credited, ByteLimit(89)).value.metadata.balance) ==
        (if incoming: 31'u64 else: 20'u64),
      "missing-code skips retain actual incoming credit without executing"
    let selected = normalizeAccumulationOutcome(first).value.outcomeContext.value
    let beneficiary = selected.effectAccounts.value.lookup(chapterServiceKey(StateChapter(255),
        ServiceIndex(42))).value.bytes
    assert uint64(decodeServiceMetadata(beneficiary, ByteLimit(89)).value.metadata.balance) ==
        (if incoming: 37'u64 else: 30'u64),
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
  var fixture = setup(envelope(recreate = true))
  let roles = privilegeStateEntry(PrivilegeState(registrar: ServiceIndex(42), assigners: @[
      ServiceIndex(0), ServiceIndex(0)]), pvmContextConfig().privileges).value
  for index in 0..<fixture.entries.len:
    if array[31, byte](fixture.entries[index].key) == array[31, byte](roles.key):
      fixture.entries[index] = roles # Genuine current registrar authority permits the reserved-ID recreation locally.
  fixture.state = newStateStore(fixture.entries, integrationStoreLimits()).value
  let first = execute(fixture)
  assert uint64(machineInfo(first.value.machine).value.registers[7]) == 77, "guest really recreated the ejected reserved target"
  assert prepare(fixture, first, execute(fixture, 1)).error ==
      AccumulationBatchError.UnsupportedAccountEffects,
    "prior-present delete/recreate needs separate n/m conflict handling and cannot silently replace its old record"

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
  let rows = expected(fixture, @[77'u32])
  failHash(0)
  let accountOnly = newStateStore(rows, integrationStoreLimits()).value
  let hashes = hashCalls()
  assert hashes > 0, "independent exact account-only root calibrates the phase boundary"
  hashAfter(hashes)
  let late = applyAccumulationBatch(target, plan)
  assert late.error == AccumulationBatchError.TerminalFailure and late.provisionError ==
      AccumulationProvisionError.BackendFailure, "late provision failure discards complete deletion/credit candidate"
  failHash(0)
  assert sameStateSnapshot(prior, target.snapshot.value), "late refusal retains original target, balance and requests"

block detached_owner:
  var owned = default(PreparedAccumulationBatch)
  var state = default(StateStore)
  block sources:
    let local = setup(envelope())
    let first = execute(local)
    let context = normalizeAccumulationOutcome(first).value.outcomeContext.value
    var copied = context.effectDeletedAccountAt(AccumulationDeletedAccountIndex(0)).value
    copied.service = ServiceIndex(0)
    copied.requestKey = chapterKey(StateChapter(250))
    assert uint32(context.effectDeletedAccountAt(AccumulationDeletedAccountIndex(
        0)).value.service) == 77, "copied facts cannot mutate deletion proof backing"
    owned = prepare(local, first, execute(local, 1)).value
    state = local.state # All caller execution/context owners disappear before application.
  discard applyAccumulationBatch(state, owned).value
  assert state.snapshot.value.lookup(chapterServiceKey(StateChapter(255), ServiceIndex(
      77))).error == StateStoreError.MissingKey, "plan retains target deletion after caller sources leave scope"

let before = getOccupiedMem()
for iteration in 0..<1000:
  let owned = prepare(fixture, execute(fixture), second).value
  var state = fixture.state
  discard applyAccumulationBatch(state, owned).value
  assert state.snapshot.value.lookup(chapterServiceKey(StateChapter(255), ServiceIndex(
      77))).error == StateStoreError.MissingKey, "fresh execution, deletion proof and private publication owners release each cycle"
let after = getOccupiedMem()
assert before == after, "deleted-account publication has stable ARC ownership"
recordArcRelease("pvm_deleted_accounts", 1000, before, after)
echo "PVM deleted accounts passed"
echo "ARC_RELEASE cycles=1000 unchanged"
