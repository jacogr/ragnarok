# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_account_publication_arc_release"}

## Genuine upgrade executions publish only selected self metadata across common-source service views.

import std/[assertions, syncio]
import ../../../src/state/[accumulation_batch, accumulation_dispatch, accumulation_effects,
  accumulation_context, accumulation_outcome, accumulation_provisions, store]
import ../../../src/codec/[bounded, composite, header, state_accounts, state_service_values,
  state_layout, state_trie]
import ../../../src/pvm/machine
import ../../../src/crypto/primitives
import ../../support/[accumulation_batch_context, accumulation_provision_integration,
  pvm_accumulation_program, arc_evidence]

# Count and inject actual root failures after a genuine guest execution, never replace the production verdict.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
# Allow all metadata-root hashes before refusing the subsequent provision phase.
proc hashAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}

# An authored fixed upgrade target is independent from both fixtures' actual code preimages.
proc targetDigest(): array[32, byte] =
  result = default(array[32, byte])
  for i in 0..<32:
    result[i] = byte(i+1) # Every digest byte participates in the canonical metadata comparison.
let digest = targetDigest()
# Copy fixed guest input without exposing mutable global state to helper routines.
proc targetInput(): seq[byte] =
  result = newSeq[byte](32)
  for i, octet in digest:
    result[i] = octet # Expected fixed hash and guest input do not share mutable storage.
let input = targetInput()

# Emit one exact upgrade with distinct per-service gas fields and the actual fixed writable input pointer.
proc upgrade(gas: uint32): seq[seq[byte]] =
  @[@[51'u8, 7, 255], registerImmediate(8, 196608), registerImmediate(9, gas), registerImmediate(10,
      gas+1), @[10'u8, 21]]

# Assemble repeated upgrade/checkpoint combinations without another bytecode framing implementation.
proc envelope(gas: uint32, checkpoint = false, panic = false, provide = false,
    repeat = false): seq[byte] =
  var instructions = upgrade(gas)
  if checkpoint:
    instructions.add(@[10'u8, 19]) # Select the first complete metadata/scope owner on exceptional termination.
  if repeat:
    for instruction in upgrade(gas+10):
      instructions.add(instruction) # An uncheckpointed later upgrade remains regular only.
  if provide:
    instructions.add(registerImmediate(7, 196608))
    instructions.add(@[10'u8, 27]) # Yield shares the same metadata-scope lineage before the pending provision.
    for instruction in [registerImmediate(7, 42), registerImmediate(8, 65536),
        registerImmediate(9, 1), @[10'u8, 28]]:
      instructions.add(instruction) # Pending provision must preserve the self-metadata proof.
  instructions.add(if panic: @[0'u8] else: @[50'u8, 0])
  guestEnvelope(instructions, input)

# Extract canonical metadata by exact own service key; no selected observation supplies the expected values.
proc metadata(state: StateStoreSnapshot, service: uint32): ServiceMetadata =
  decodeServiceMetadata(state.lookup(chapterServiceKey(StateChapter(255),
    ServiceIndex(service))).value.bytes, ByteLimit(ServiceMetadataBytes)).value.metadata

# Plan complete coverage while permitting input execution order to be reversed independently of numeric service order.
proc prepare(fixture: BatchFixture, first, second: AccumulationDispatchResult,
    accounts = 2'u64): AccumulationBatchResult[PreparedAccumulationBatch] =
  let prior = fixture.state.snapshot.value
  let executions = [first, second]
  prepareCompleteAccumulationBatch(fixture.inputs, prior, executions, [], HeaderSlot(128),
    batchPolicy(accounts))

# Build a complete independent expected mapping by replacing only literal own credit/upgrade records.
proc expected(fixture: BatchFixture, firstGas, secondGas: uint32, incoming = true): StateStore =
  var rows: seq[StateEntry] = @[]
  for entry in fixture.entries:
    var copied = StateEntry(key: entry.key, value: entry.value)
    for ordinal, service in [42'u32, 99'u32]:
      if array[31, byte](entry.key) == array[31, byte](chapterServiceKey(StateChapter(255),
          ServiceIndex(service))):
        var account = decodeServiceMetadata(entry.value, ByteLimit(
            ServiceMetadataBytes)).value.metadata
        if incoming:
          account.balance = AccountBalance(if ordinal ==
              0: 17 else: 31) # Distinct original balances plus actual incoming amounts.
        let gas = if ordinal == 0: firstGas else: secondGas
        if gas != 0:
          account.codeHash = CodeHash(digest)
          account.minimumAccumulationGas = Gas(uint64(gas))
          account.minimumTransferGas = Gas(uint64(gas)+1) # Full independently encoded metadata must match.
        copied = serviceMetadataEntry(ServiceIndex(service), account, ByteLimit(
            ServiceMetadataBytes)).value
    rows.add(copied) # Preserve all unrelated code, storage, request and opaque chapter entries.
  newStateStore(rows, integrationStoreLimits()).value

block scope_default:
  assert default(AccumulationEffectContext).effectAccountScope.error ==
      AccumulationEffectError.Uninitialized,
    "default context cannot certify untouched accounts"

# Both common-source executions see stale sibling records; publication must copy each distinct own record only.
for checkpoint in [false, true]:
  for panic in [false, true]:
    let fixture = batchFixture(firstEnvelope = envelope(7, checkpoint, panic, repeat = true),
      secondEnvelope = envelope(19))
    let first = batchExecution(fixture, 0)
    let second = batchExecution(fixture, 1)
    let selected = normalizeAccumulationOutcome(first).value.outcomeContext.value
    let gas = if panic: (if checkpoint: 7'u32 else: 0'u32) else: 17'u32
    let scope = if panic and not checkpoint: AccumulationAccountScope.Initial else: AccumulationAccountScope.SelfMetadata
    assert selected.effectAccountScope.value == scope, "scope follows the exact terminal-selected checkpoint"
    let plan = prepare(fixture, first, second).value
    let reversed = prepare(fixture, second, first).value
    var state = fixture.state
    var other = fixture.state
    discard applyAccumulationBatch(state, plan).value
    discard applyAccumulationBatch(other, reversed).value
    let wanted = expected(fixture, gas, 19)
    assert array[32, byte](state.snapshot.value.commitment.root) == array[32, byte](
        wanted.snapshot.value.commitment.root),
      "exact complete-map root preserves own upgrade/credits and all unrelated entries"
    assert array[32, byte](other.snapshot.value.commitment.root) == array[32, byte](
        wanted.snapshot.value.commitment.root),
      "execution permutation cannot overwrite a sibling upgrade with its stale local view"
    assert uint64(metadata(state.snapshot.value, 42).balance) == 17 and uint64(metadata(
        state.snapshot.value, 99).balance) == 31,
      "incoming credit is already in selected metadata and must not be added twice"
    assert uint64(metadata(fixture.state.snapshot.value, 42).balance) == 10, "retained common prior stays unchanged"
    failHash(1)
    assert applyAccumulationBatch(state, plan).error == AccumulationBatchError.StaleState and
        hashCalls() == 0,
      "stale plan refuses before hashing or replaying upgrade/credits"
    failHash(0)
    assert prepare(fixture, first, second, 1).error == AccumulationBatchError.LimitExceeded,
      "two distinct selected self records need exactly two account writes"

block upgrade_without_credit:
  let fixture = batchFixture(incoming = false, firstEnvelope = envelope(7),
      secondEnvelope = envelope(19))
  let plan = prepare(fixture, batchExecution(fixture, 0), batchExecution(fixture, 1)).value
  var state = fixture.state
  discard applyAccumulationBatch(state, plan).value
  let wanted = expected(fixture, 7, 19, incoming = false)
  assert array[32, byte](state.snapshot.value.commitment.root) == array[32, byte](
      wanted.snapshot.value.commitment.root),
    "selected metadata changes publish even when incoming credits do not fork the service source"

block broader_mutation_is_sticky:
  for storage in [false, true]:
    var instructions: seq[seq[byte]] = @[]
    if storage:
      instructions = @[@[51'u8, 7, 255], registerImmediate(8, 65536), registerImmediate(9, 1),
        registerImmediate(10, 196608), registerImmediate(11, 1), @[10'u8, 5]] # Real self storage mutation.
    else:
      instructions = @[@[51'u8, 7, 255], registerImmediate(8, 196608), registerImmediate(9, 3), @[
          10'u8, 25]] # Real request mutation.
    for instruction in upgrade(7):
      instructions.add(instruction) # A later upgrade cannot relabel the broader lineage as self-metadata-only.
    instructions.add(@[50'u8, 0])
    let fixture = batchFixture(firstEnvelope = guestEnvelope(instructions, input))
    let first = batchExecution(fixture, 0)
    assert first.effects.effectContext(AccumulationDimension.Regular).value.effectAccountScope.value ==
        AccumulationAccountScope.Unsupported,
      "unsupported lineage remains sticky through upgrade"
    assert prepare(fixture, first, batchExecution(fixture, 1)).error ==
        AccumulationBatchError.UnsupportedAccountEffects,
      "broader selected effects remain a reason-only publication gate"

# Genuine supervised upgrades remain explicit publication gates until parallel conflict selection is implemented.
block supervised_upgrade_requires_conflict_selection:
  var instructions = @[registerImmediate(7, 99), registerImmediate(8, 196608),
      registerImmediate(9, 7), registerImmediate(10, 8), @[10'u8, 21]]
  for instruction in upgrade(17):
    instructions.add(instruction) # A later genuine self upgrade cannot erase foreign provenance.
  instructions.add(@[50'u8, 0])
  var fixture = batchFixture(incoming = false, firstEnvelope = guestEnvelope(instructions, input))
  let targetKey = chapterServiceKey(StateChapter(255), ServiceIndex(99))
  var target = metadata(fixture.state.snapshot.value, 99)
  target.supervisor = ServiceIndex(42)
  target.supervisorCreated = metadata(fixture.state.snapshot.value, 42).created
  let entry = serviceMetadataEntry(ServiceIndex(99), target, ByteLimit(ServiceMetadataBytes)).value
  discard fixture.state.apply([StateWrite(key: targetKey, kind: StateWriteKind.Put,
      value: entry.value)]).value
  let priorRoot = array[32, byte](fixture.state.snapshot.value.commitment.root)
  let first = batchExecution(fixture, 0)
  let second = batchExecution(fixture, 1)
  let selected = first.effects.effectContext(AccumulationDimension.Regular).value
  assert selected.effectAccountScope.value == AccumulationAccountScope.Unsupported,
      "foreign metadata cannot masquerade as self publication"
  assert uint64(metadata(selected.effectAccounts.value, 99).minimumAccumulationGas) == 7,
      "supervised foreign upgrade actually executed before publication refusal"
  let refused = prepare(fixture, first, second)
  assert refused.error == AccumulationBatchError.UnsupportedAccountEffects,
      "parallel batch needs a conflict-selection proof; actual reason " & $uint32(refused.error)
  assert array[32, byte](fixture.state.snapshot.value.commitment.root) == priorRoot,
      "failed publication leaves the complete source map unchanged"

# Supervisor self changes use the metadata proof; foreign changes retain the same explicit batch gate.
block supervisor_publication:
  for foreign in [false, true]:
    let target = if foreign: 77'u64 else: high(uint64)
    let instructions = @[registerImmediate(7, target), registerImmediate(8, 99), @[10'u8, 29], @[
        50'u8, 0]]
    let child = serviceMetadataEntry(ServiceIndex(77), ServiceMetadata(supervisor: ServiceIndex(42),
        supervisorCreated: AccountSlot(0)), ByteLimit(ServiceMetadataBytes)).value
    var fixture = batchFixture(incoming = false, firstEnvelope = guestEnvelope(instructions, input),
        secondEnvelope = guestEnvelope(@[@[50'u8, 0]], input), extra = @[child])
    let prior = fixture.state.snapshot.value
    let first = batchExecution(fixture, 0)
    let second = batchExecution(fixture, 1)
    if foreign:
      # A real foreign supervisor execution cannot opt itself into the self-record projection.
      assert prepare(fixture, first, second).error ==
          AccumulationBatchError.UnsupportedAccountEffects,
          "foreign supervisor reassignment needs parallel conflict selection"
      assert array[32, byte](fixture.state.snapshot.value.commitment.root) == array[32, byte](
          prior.commitment.root),
          "foreign supervisor publication refusal retains the complete prior root"
    else:
      # The existing metadata projection publishes exactly the selected self identity pair.
      let plan = prepare(fixture, first, second).value
      discard applyAccumulationBatch(fixture.state, plan).value
      let published = fixture.state.snapshot.value
      let own = metadata(published, 42)
      assert uint32(own.supervisor) == 99 and uint32(own.supervisorCreated) == uint32(metadata(
          prior, 99).created),
          "self supervisor identity publishes with the nominee's exact current creation slot"
      let ownKey = chapterServiceKey(StateChapter(255), ServiceIndex(42))
      for entry in fixture.entries:
        if array[31, byte](entry.key) != array[31, byte](ownKey):
          assert published.lookup(entry.key).value.bytes == entry.value,
              "self reassignment publishes no unrelated account or namespace changes"
      assert uint32(metadata(prior, 42).supervisor) == 0,
          "retained prior metadata does not change on publication"

# A genuine supervised storage write retains the foreign publication gate under the existing self-key policy.
block foreign_storage_publication:
  let instructions = @[registerImmediate(7, 77), registerImmediate(8, 65536), registerImmediate(9,
      1), registerImmediate(10, 196608), registerImmediate(11, 1), @[10'u8, 5], @[50'u8, 0]]
  let child = serviceMetadataEntry(ServiceIndex(77), ServiceMetadata(supervisor: ServiceIndex(42),
      supervisorCreated: AccountSlot(0)), ByteLimit(ServiceMetadataBytes)).value
  let fixture = batchFixture(incoming = false, firstEnvelope = guestEnvelope(instructions, input),
      secondEnvelope = guestEnvelope(@[@[50'u8, 0]], input), extra = @[child])
  let first = batchExecution(fixture, 0)
  let selected = first.effects.effectContext(AccumulationDimension.Regular).value
  let key = serviceStorageKey(ServiceIndex(77), @[73'u8], ByteLimit(1)).value
  assert selected.effectAccounts.value.lookup(key).value.bytes == @[1'u8],
      "supervised foreign storage mutation actually executes"
  assert selected.effectAccountScope.value == AccumulationAccountScope.Unsupported,
      "foreign storage cannot impersonate bounded self-key provenance"
  assert prepare(fixture, first, batchExecution(fixture, 1)).error ==
      AccumulationBatchError.UnsupportedAccountEffects,
      "foreign storage still needs parallel modified-account conflict selection"
  assert fixture.state.snapshot.value.lookup(key).error == StateStoreError.MissingKey,
      "refused foreign storage publication retains the prior namespace"

# Provide/yield versions preserve scope, and a refusal after preparation never publishes the earlier metadata candidate.
let fixture = batchFixture(firstEnvelope = envelope(7, provide = true), secondEnvelope = envelope(19))
let first = batchExecution(fixture, 0)
let second = batchExecution(fixture, 1)
let plan = prepare(fixture, first, second).value
assert plan.batchInfo.value.accountWrites == 2 and plan.batchInfo.value.terminal.provisions.items == 1,
  "selected self metadata composes with existing terminal provision integration"
assert plan.batchOutcomeAt(AccumulationProvisionSourceIndex(0)).value.outcomeInfo.value.hasYield,
  "yield preserves the selected metadata scope"
block exact_provision_root:
  var state = fixture.state
  discard applyAccumulationBatch(state, plan).value
  var wanted = expected(fixture, 7, 19)
  let request = integrationRequest(42, @[73'u8], @[1'u8, 128, 0, 0, 0])
  let hash = ServicePreimageHash(array[32, byte](blake2b256([73'u8]).value))
  let preimage = servicePreimageEntry(ServiceIndex(42), hash, @[73'u8],
    ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(1))).value
  discard wanted.apply([StateWrite(key: request.key, kind: StateWriteKind.Put,
      value: request.value),
    StateWrite(key: preimage.key, kind: StateWriteKind.Put, value: preimage.value)]).value
  assert array[32, byte](state.snapshot.value.commitment.root) == array[32, byte](
      wanted.snapshot.value.commitment.root),
    "full root contains both upgrades, exact credits, fulfillment slot and actual provision blob"
block late_backend_atomicity:
  var credited = fixture.state
  var writes: seq[StateWrite] = @[]
  for service in [42'u32, 99'u32]:
    var account = metadata(fixture.state.snapshot.value, service)
    account.balance = AccountBalance(if service == 42: 17 else: 31)
    account.codeHash = CodeHash(digest)
    account.minimumAccumulationGas = Gas(if service == 42: 7 else: 19)
    account.minimumTransferGas = Gas(if service == 42: 8 else: 20)
    let entry = serviceMetadataEntry(ServiceIndex(service), account, ByteLimit(
        ServiceMetadataBytes)).value
    writes.add(StateWrite(key: entry.key, kind: StateWriteKind.Put, value: entry.value))
  failHash(0)
  discard credited.apply(writes).value
  let accountHashes = hashCalls()
  assert accountHashes > 0, "independent metadata-only root calibrates the exact phase boundary"
  var state = fixture.state
  let prior = state.snapshot.value
  hashAfter(accountHashes)
  let failed = applyAccumulationBatch(state, plan)
  assert failed.error == AccumulationBatchError.TerminalFailure and
    failed.provisionError == AccumulationProvisionError.BackendFailure,
    "late provision refusal discards a fully computed upgraded account map"
  failHash(0)
  assert sameStateSnapshot(prior, state.snapshot.value), "late refusal publishes no selected upgrades or credits"
block detached_plan:
  var owned = default(PreparedAccumulationBatch)
  var state = default(StateStore)
  block source_lifetime:
    let local = batchFixture(firstEnvelope = envelope(7), secondEnvelope = envelope(19))
    owned = prepare(local, batchExecution(local, 0), batchExecution(local, 1)).value
    state = local.state # No execution or local fixture survives this scope.
  discard applyAccumulationBatch(state, owned).value
  assert uint64(metadata(state.snapshot.value, 99).minimumAccumulationGas) == 19,
    "plan retains selected metadata after all caller execution handles are released"
block backend_atomicity:
  var state = fixture.state
  let prior = state.snapshot.value
  failHash(1)
  let failed = applyAccumulationBatch(state, plan)
  assert failed.error == AccumulationBatchError.StoreFailure and failed.storeError ==
      StateStoreError.BackendFailure,
    "failed account root has no successful batch payload"
  failHash(0)
  assert sameStateSnapshot(prior, state.snapshot.value), "backend refusal publishes neither upgrades nor incoming credits"

# One retained plan owns selected metadata and outcomes after the caller's execution handles leave scope.
let before = getOccupiedMem()
for iteration in 0..<1000:
  var state = fixture.state
  let owned = prepare(fixture, batchExecution(fixture, 0), second).value
  discard applyAccumulationBatch(state, owned).value
  assert uint64(metadata(state.snapshot.value, 42).minimumAccumulationGas) == 7,
    "fresh execution, selected metadata and publication release all temporary owners"
let after = getOccupiedMem()
assert before == after, "self-metadata publication has stable ARC ownership"
recordArcRelease("pvm_account_publication", 1000, before, after)
echo "PVM account publication passed"
echo "ARC_RELEASE cycles=1000 unchanged"
