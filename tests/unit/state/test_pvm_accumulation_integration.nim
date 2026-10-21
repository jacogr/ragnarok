# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_accumulation_integration_arc_release"}

## Cross-host executions bind current effects, terminal checkpoints and conservative complete-batch publication.

import std/[assertions, syncio]
import ../../../src/chain/parameters
import ../../../src/codec/[bounded, composite, header, state_accounts, state_service_values,
  state_requests, state_layout, state_trie, state_outputs]
import ../../../src/state/[accumulation_dispatch, accumulation_effects, accumulation_context,
  accumulation_outcome, accumulation_batch, accumulation_provisions, store]
import ../../../src/pvm/[machine, step]
import ../../../src/crypto/primitives
import ../../support/[pvm_accumulation_context, pvm_accumulation_program,
  accumulation_batch_context, accumulation_provision_integration, arc_evidence]

# Inject backend refusal only after genuine execution and batch preparation.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
# Prove stale application performs no hashing or partial incoming credit.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}

# Preserve the independent zero deposit profile while matching the fixed transfer memo width.
proc profile(): Parameters =
  var wire = encodeParameters(pvmParameters())
  for i in 0..<24:
    wire[i] = 0 # Account effects are exercised at the fixture's real small incoming-credit balances.
  for i in 110..<114:
    wire[i] = 0 # The C.2 memo remains exactly 128 bytes.
  wire[110] = 128
  decodeParameters(wire).value

let blob = @[5'u8, 7, 9]
let hash = ServicePreimageHash(array[32, byte](blake2b256(blob).value))
var input = newSeq[byte](128)
for i, octet in array[32, byte](hash):
  input[i] = octet # Fixed digest occupies the first 32 bytes of an independently owned memo/input buffer.

# Run the maintained production engine with exact common-source ownership and explicit finite policy.
proc execute(fixture: BatchFixture, index = 0'u64): AccumulationDispatchResult =
  batchExecution(fixture, index, copyLimit = MemoryByteLimit(128), parameters = profile(),
      transferLimit = ElementLimit(1))

# Extract only an execution's own completed implication version.
proc context(done: AccumulationDispatchResult, dimension = AccumulationDimension.Regular): AccumulationEffectContext =
  assert done.error == AccumulationDispatchError.None, "completed guest execution"
  done.effects.effectContext(dimension).value

# Inspect canonical balances independently of terminal union observations.
proc balance(state: StateStoreSnapshot, service: uint32): uint64 =
  let found = state.lookup(chapterServiceKey(StateChapter(255), ServiceIndex(service))).value
  uint64(decodeServiceMetadata(found.bytes, ByteLimit(ServiceMetadataBytes)).value.metadata.balance)

# Prepare complete coverage of exactly this fixture's two genuine input services and original prior.
proc prepare(fixture: BatchFixture, first, second: AccumulationDispatchResult): AccumulationBatchResult[
    PreparedAccumulationBatch] =
  let prior = fixture.state.snapshot.value
  let completed = [first, second]
  prepareCompleteAccumulationBatch(fixture.inputs, prior, completed, [], HeaderSlot(128),
      batchPolicy())


# Assert exact fulfillment at the batch's verified invocation slot, rather than just counting pending contributions.
proc fulfilled(state: StateStoreSnapshot, service: uint32, bytes: seq[byte]) =
  let digest = ServicePreimageHash(array[32, byte](blake2b256(bytes).value))
  let found = state.lookup(serviceRequestKey(ServiceIndex(service), digest, RequestLength(uint32(
      bytes.len)), ByteLimit(32)).value).value
  let history = decodeRequestHistory(found.bytes, RequestHistoryConfig(items: ElementLimit(3),
      maxBytes: ByteLimit(13))).value.history
  assert history.state == RequestState.Available and uint32(history.since) == 128, "exact terminal fulfillment slot"
  assert state.lookup(servicePreimageKey(ServiceIndex(service), digest, ByteLimit(
      32)).value).value.bytes == bytes, "exact fulfilled raw blob"

# Literal original halt envelope independently witnesses framing compatibility after sharing the builder.
block envelope_compatibility:
  assert guestEnvelope([@[50'u8, 0]]) == pvmEnvelope(), "shared framing retains the original literal halt envelope"

# Request create/query/delete/query returns to equal map bytes but retains a distinct immutable account version.
let lifecycle = guestEnvelope([registerImmediate(7, 196608), registerImmediate(8, 3), @[10'u8, 25],
  registerImmediate(7, 196608), @[10'u8, 24], registerImmediate(7, 196608), registerImmediate(8, 3),
      @[10'u8, 26],
  registerImmediate(7, 196608), @[10'u8, 24], @[50'u8, 0]], input)
block request_lifecycle:
  let fixture = batchFixture(firstEnvelope = lifecycle)
  let first = execute(fixture)
  let second = execute(fixture, 1)
  let cpu = machineInfo(first.value.machine).value
  assert first.value.exit == StepExit.Halt and uint64(cpu.registers[7]) == high(uint64) and
      uint64(cpu.registers[8]) == 0,
    "query sees current deletion instead of the initial solicitation"
  let regular = context(first).effectAccounts.value
  let exceptional = context(first, AccumulationDimension.Exceptional).effectAccounts.value
  assert array[32, byte](regular.commitment.root) == array[32, byte](exceptional.commitment.root), "request lifecycle has no net map-byte change"
  assert not sameStateSnapshot(regular, exceptional), "equal roots do not certify identical account provenance"
  assert prepare(fixture, first, second).error ==
      AccumulationBatchError.UnsupportedAccountEffects,
    "conservative merger does not silently replace an unsupported version with equal-root initial credit"
  assert balance(fixture.state.snapshot.value, 42) == 10 and balance(regular, 42) == 17, "parent remains uncredited while execution owns its incoming credit"

# Read-only query and gas calls preserve the exact credited account owner and permit supported publication.
let requested = blake2b256([73'u8]).value
var readInput = newSeq[byte](32)
for i, octet in array[32, byte](requested):
  readInput[i] = octet # Existing service-42 request is independent from the lifecycle hash.
let readEnvelope = guestEnvelope([registerImmediate(7, 196608), registerImmediate(8, 1), @[10'u8,
    24], @[10'u8, 0], @[50'u8, 0]], readInput)
let readable = batchFixture(firstEnvelope = readEnvelope)
let readFirst = execute(readable)
let readSecond = execute(readable, 1)
let supported = prepare(readable, readFirst, readSecond).value
block supported_publication:
  let cpu = machineInfo(readFirst.value.machine).value
  let normalized = normalizeAccumulationOutcome(readFirst).value
  assert uint64(cpu.registers[7]) == uint64(cpu.gas) and uint64(
      normalized.outcomeInfo.value.gasUsed) == 100000-uint64(cpu.gas),
    "gas host and normalized actual consumption agree"
  assert supported.batchInfo.value.completeInputs and supported.batchInfo.value.executions == 2, "complete common-source coverage"
  var published = readable.state
  assert applyAccumulationBatch(published, supported).error == AccumulationBatchError.None, "supported batch publishes atomically"
  assert balance(published.snapshot.value, 42) == 17 and balance(published.snapshot.value, 99) == 31,
    "incoming credits applied once with exact balances"
  fulfilled(published.snapshot.value, 42, @[73'u8])
  fulfilled(published.snapshot.value, 99, @[81'u8])
  assert balance(readable.state.snapshot.value, 42) == 10, "original common source remains immutable"
  let post = published.snapshot.value
  failHash(1)
  assert applyAccumulationBatch(published, supported).error ==
      AccumulationBatchError.StaleState and hashCalls() == 0,
    "stale plan cannot double-credit or double-fulfill"
  failHash(0)
  assert sameStateSnapshot(post, published.snapshot.value), "stale refusal preserves exact intervening owner"

# A real deferred debit remains regular until a checkpoint selects it; target credit remains deferred.
for amount in [0'u64, 1]:
  for checkpoint in [false, true]:
    for panic in [false, true]:
      var instructions = @[registerImmediate(7, high(uint64)), registerImmediate(8, 99),
          @[51'u8, 9, 0], registerImmediate(10, amount), registerImmediate(11, 0),
          registerImmediate(12, 196608), @[10'u8, 22]]
      if checkpoint:
        instructions.add(@[10'u8, 19]) # Retain the debit/outgoing owner only after its explicit checkpoint.
      instructions.add(if panic: @[0'u8] else: @[50'u8, 0])
      let fixture = batchFixture(firstEnvelope = guestEnvelope(instructions, input))
      let first = execute(fixture)
      let second = execute(fixture, 1)
      assert context(first).effectInfo.value.transfers == 1 and balance(context(
          first).effectAccounts.value, 42) == 17-amount,
        "transfer retains exact regular debit and outgoing count"
      assert balance(context(first).effectAccounts.value, 99) == 20, "destination receives no immediate outgoing credit"
      let selected = normalizeAccumulationOutcome(first).value
      let plan = prepare(fixture, first, second)
      if panic and not checkpoint:
        assert selected.outcomeInfo.value.transfers == 0 and plan.error ==
            AccumulationBatchError.None,
          "uncheckpointed debit and outgoing transfer roll back together"
        var state = fixture.state
        discard applyAccumulationBatch(state, plan.value).value
        assert balance(state.snapshot.value, 42) == 17 and balance(state.snapshot.value, 99) == 31,
          "publication retains incoming credit without applying rolled-back outgoing transfers"
      else:
        assert selected.outcomeInfo.value.transfers == 1 and plan.error ==
            AccumulationBatchError.None,
          "selected deferred debits publish only their invoking metadata"
        var state = fixture.state
        discard applyAccumulationBatch(state, plan.value).value
        assert balance(state.snapshot.value, 42) == 17-amount and balance(state.snapshot.value,
            99) == 31,
          "incoming credits and selected debit publish once; outgoing destination credit remains deferred"

# Pre-mutation checkpoint retains provide/yield while later request mutation rolls back; later checkpoint gates publication.
for retainMutation in [false, true]:
  var instructions = @[registerImmediate(7, 42), registerImmediate(8, 65536), registerImmediate(9,
      1), @[10'u8, 28],
    registerImmediate(7, 196608), @[10'u8, 27], @[10'u8, 19], registerImmediate(7, 196608),
        registerImmediate(8, 3), @[10'u8, 25]]
  if retainMutation:
    instructions.add(@[10'u8, 19]) # Select the new request and its footprint as well as pending outputs.
  instructions.add(@[0'u8])
  let fixture = batchFixture(firstEnvelope = guestEnvelope(instructions, input))
  let first = execute(fixture)
  let second = execute(fixture, 1)
  let plan = prepare(fixture, first, second)
  if retainMutation:
    assert plan.error == AccumulationBatchError.UnsupportedAccountEffects, "checkpoint-selected solicitation cannot be silently dropped"
  else:
    assert plan.error == AccumulationBatchError.None, "discarded solicitation permits supported terminal outputs"
    let outcome = plan.value.batchOutcomeAt(AccumulationProvisionSourceIndex(0)).value
    assert outcome.outcomeInfo.value.hasYield and outcome.outcomeInfo.value.provisions == 1,
      "selected pre-mutation yield/provision retained together"
    assert array[32, byte](outcome.outcomeContext.value.effectYield.value) == array[32, byte](
        hash), "exact selected yield"
    let union = plan.value.batchInfo.value.terminal.provisions
    assert union.inputItems == 3 and union.items == 2, "checkpoint contributions deduplicate with sibling provides"
    var published = fixture.state
    discard applyAccumulationBatch(published, plan.value).value
    fulfilled(published.snapshot.value, 42, @[73'u8])
    fulfilled(published.snapshot.value, 99, @[81'u8])
    assert published.snapshot.value.lookup(serviceRequestKey(ServiceIndex(42), hash,
        RequestLength(3), ByteLimit(32)).value).error == StateStoreError.MissingKey,
      "rolled-back solicitation never enters the published map"

block upgrade_boundary:
  let envelope = guestEnvelope([registerImmediate(7, 196608), registerImmediate(8, 7),
      registerImmediate(9, 9), @[10'u8, 21], @[50'u8, 0]], input)
  let fixture = batchFixture(firstEnvelope = envelope)
  let first = execute(fixture)
  let record = context(first).effectAccounts.value.lookup(chapterServiceKey(StateChapter(255),
      ServiceIndex(42))).value
  let metadata = decodeServiceMetadata(record.bytes, ByteLimit(ServiceMetadataBytes)).value.metadata
  assert array[32, byte](metadata.codeHash) == array[32, byte](hash) and uint64(
      metadata.minimumTransferGas) == 9,
    "upgrade changes current metadata while original guest reaches halt"
  let plan = prepare(fixture, first, execute(fixture, 1)).value
  var published = fixture.state
  discard applyAccumulationBatch(published, plan).value
  assert published.snapshot.value.lookup(chapterServiceKey(StateChapter(255),
    ServiceIndex(42))).value.bytes == record.bytes,
    "proven selected self-metadata upgrade publishes without losing its incoming credit"

block grow_heap_query:
  let fixture = batchFixture(firstEnvelope = guestEnvelope([@[10'u8, 1], @[50'u8, 0]]))
  let done = execute(fixture)
  assert done.error == AccumulationDispatchError.None and done.value.exit == StepExit.Halt,
    "adopted heap query is a genuine completed host outcome"
  assert uint64(machineInfo(done.value.machine).value.registers[7]) == 50,
    "oversized requested endpoint returns the actual heap endpoint"
  let plan = prepare(fixture, done, execute(fixture, 1)).value
  var state = fixture.state
  discard applyAccumulationBatch(state, plan).value
  assert balance(state.snapshot.value, 42) == 17 and balance(state.snapshot.value, 99) == 31,
    "heap query composes with incoming-credit publication"
  assert balance(fixture.state.snapshot.value, 42) == 10, "publication preserves the immutable prior"

block backend_atomicity:
  var target = readable.state
  let before = target.snapshot.value
  failHash(1)
  let failed = applyAccumulationBatch(target, supported)
  assert failed.error == AccumulationBatchError.StoreFailure and failed.storeError ==
      StateStoreError.BackendFailure,
    "account-root backend refusal remains a typed atomic application failure"
  failHash(0)
  assert sameStateSnapshot(before, target.snapshot.value), "failed application publishes no incoming credit or provision"

let before = getOccupiedMem()
for iteration in 0..<1000:
  let first = execute(readable)
  let plan = prepare(readable, first, readSecond).value
  var published = readable.state
  discard applyAccumulationBatch(published, plan).value
  assert balance(published.snapshot.value, 42) == 17, "repeat fresh execution/batch application releases all intermediate owners"
let after = getOccupiedMem()
assert before == after, "integration releases all ARC-owned execution/terminal/batch graphs"
recordArcRelease("pvm_accumulation_integration", 1000, before, after)
echo "PVM accumulation integration passed"
echo "ARC_RELEASE cycles=1000 unchanged"
