# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_transfer_publication_arc_release"}

## Genuine common-source transfers publish only selected own debits, preserve ordered outputs and roll back atomically.

import std/assertions
import std/syncio
import ../../../src/chain/parameters as chain_parameters
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/composite as codec_composite
import ../../../src/codec/header as codec_header
import ../../../src/codec/c2_records as codec_c2_records
import ../../../src/codec/state_accounts as codec_state_accounts
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_service_values as codec_state_service_values
import ../../../src/codec/state_requests as codec_state_requests
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/state/accumulation_batch as state_accumulation_batch
import ../../../src/state/accumulation_dispatch as state_accumulation_dispatch
import ../../../src/state/accumulation_effects as state_accumulation_effects
import ../../../src/state/accumulation_context as state_accumulation_context
import ../../../src/state/accumulation_invocation as state_accumulation_invocation
import ../../../src/state/accumulation_outcome as state_accumulation_outcome
import ../../../src/state/accumulation_provisions as state_accumulation_provisions
import ../../../src/state/accumulation_transfers as state_accumulation_transfers
import ../../../src/state/accumulation_inputs as state_accumulation_inputs
import ../../../src/state/accumulation_service as state_accumulation_service
import ../../../src/state/store as state_store
import ../../../src/pvm/machine as pvm_machine
import ../../../src/pvm/step as pvm_step
import ../../../src/crypto/primitives as crypto_primitives
import ../../support/state_accumulation_batch_context
import ../../support/state_accumulation_provision_integration
import ../../support/pvm_accumulation_context
import ../../support/pvm_accumulation_program
import ../../support/testing_arc_evidence

# Observe exact publication phases without replacing the maintained backend or outcome constructors.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
proc hashAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}

type
  DebitEnding {.pure.} = enum ## Authored terminal alternatives select real X/Y owners.
    Halt, Panic, Fault, OutOfGas, HashReturn

proc memo(): seq[byte] =
  ## Every fixed memo byte has an independent literal pattern, including non-ASCII octets.
  result = newSeq[byte](128)
  for index in 0..<128:
    result[index] = byte((index*7+3) mod 256) # Bounded opaque input is not a string or hash-only witness.

proc profile(): Parameters =
  ## Small actual balances use zero deposits while retaining the required fixed memo profile.
  var bytes = encodeParameters(pvmParameters())
  for index in 0..<24:
    bytes[index] = 0 # Initialize every deposit word before real host funding validation.
  for index in 110..<114:
    bytes[index] = 0 # Set the whole E4 memo-size field, with no stale high bytes.
  bytes[110] = 128
  for index in 74..<78:
    bytes[index] = 0 # Retain a validated one-slot lookup age; current eject uses empty-account supervisor authorization.
  bytes[74] = 1
  decodeParameters(bytes).value

proc transfer(destination, amount: uint64): seq[seq[byte]] =
  ## Assemble a complete successful-row proposal; the production host supplies its verdict and debit.
  @[@[51'u8, 7, 255], @[51'u8, 9, 0], registerImmediate(8, destination), registerImmediate(10,
      amount), registerImmediate(11, 0),
    registerImmediate(12, 196608), @[10'u8, 22]]

proc append(code: var seq[seq[byte]], more: seq[seq[byte]]) =
  ## Preserve authored instruction boundaries through the existing envelope builder.
  for instruction in more:
    code.add(instruction) # Borrowed fixture instructions never substitute a production effect certificate.

proc envelope(amount = 5'u64, destination = 99'u64, checkpoint = false,
    repeat = false, ending = DebitEnding.Halt): seq[byte] =
  ## Checkpoint after the first debit, then optionally duplicate it before the selected terminal.
  var code = transfer(destination, amount)
  if checkpoint:
    code.add(@[10'u8, 19]) # Y retains the exact first debit and outgoing sequence together.
  if repeat:
    code.add(registerImmediate(7, high(uint64)))
    code.add(@[10'u8, 22]) # Same amount/gas/memo: duplicates are separate debits.
  case ending
  of DebitEnding.Halt:
    discard # Ordinary halt selects every regular append.
  of DebitEnding.Panic:
    code.add(@[0'u8]) # A genuine trap rolls back the later regular suffix.
  of DebitEnding.Fault:
    code.add(@[52'u8, 2, 0, 0, 4]) # Unmapped physical load selects the same exceptional checkpoint.
  of DebitEnding.OutOfGas:
    code.add(registerImmediate(7, high(uint64)))
    code.add(registerImmediate(11, 100000))
    code.add(@[10'u8, 22]) # Valid third proposal exceeds remaining gas before any new debit or append.
  of DebitEnding.HashReturn:
    code.add(registerImmediate(7, 65536))
    code.add(registerImmediate(8, 32)) # Readable return hash overrides only the yield.
  code.add(@[50'u8, 0])
  guestEnvelope(code, memo())

proc fixture(first: seq[byte], second: seq[byte] = guestEnvelope([@[50'u8, 0]]),
    incoming = true): BatchFixture =
  ## Both services share one actual input/prior owner; default sibling halt contributes no pending provision.
  batchFixture(firstEnvelope = first, secondEnvelope = second, incoming = incoming)

proc execute(source: BatchFixture, index = 0'u64, keys = 0'u64): AccumulationDispatchResult =
  ## Use real guest execution with finite memo, transfer and optional self-write tracing ceilings.
  batchExecution(source, index, copyLimit = MemoryByteLimit(128), parameters = profile(),
    transferLimit = ElementLimit(3), accountWriteKeys = ElementLimit(keys))

proc prepare(source: BatchFixture, first, second: AccumulationDispatchResult,
    accounts = 2'u64, keys = 0'u64, bytes = 0'u64): AccumulationBatchResult[
        PreparedAccumulationBatch] =
  ## Preserve common-source provenance and full service coverage through the maintained batch coordinator.
  let prior = source.state.snapshot.value
  let executions = [first, second]
  prepareCompleteAccumulationBatch(source.inputs, prior, executions, [], HeaderSlot(128),
    batchPolicy(accounts, selfWrites = keys, selfValueBytes = bytes))

proc metadata(state: StateStoreSnapshot, service: uint32): ServiceMetadata =
  ## Decode the exact canonical record rather than trusting a copied batch balance observation.
  decodeServiceMetadata(state.lookup(chapterServiceKey(StateChapter(255),
    ServiceIndex(service))).value.bytes, ByteLimit(ServiceMetadataBytes)).value.metadata

proc expectedRows(source: BatchFixture, firstBalance, secondBalance: uint64,
    upgrade = false, storage = false): seq[StateEntry] =
  ## Replace literal final balances/fields in a complete independent map, preserving all unrelated entries.
  result = @[]
  for entry in source.entries:
    var copied = StateEntry(key: entry.key, value: entry.value)
    for service in [42'u32, 99'u32]:
      if array[31, byte](entry.key) == array[31, byte](chapterServiceKey(StateChapter(255),
          ServiceIndex(service))):
        var account = decodeServiceMetadata(entry.value, ByteLimit(
            ServiceMetadataBytes)).value.metadata
        account.balance = AccountBalance(if service == 42: firstBalance else: secondBalance)
        if service == 42 and upgrade:
          var digest = default(array[32, byte])
          let input = memo()
          for index in 0..<32:
            digest[index] = input[index] # Code hash is the raw fixed guest proposal, not its hash.
          account.codeHash = CodeHash(digest)
          account.minimumAccumulationGas = Gas(7)
          account.minimumTransferGas = Gas(9)
        if service == 42 and storage:
          account.storageItems = AccountStorageItems(1)
          account.storageBytes = AccountStorageBytes(
              36) # Existing self-write fixture's independently derived footprint.
        copied = serviceMetadataEntry(ServiceIndex(service), account, ByteLimit(
            ServiceMetadataBytes)).value
    result.add(copied)
  if storage:
    result.add(serviceStorageEntry(ServiceIndex(42), @[73'u8], @[3'u8],
      ServiceEntryLimits(keyBytes: ByteLimit(1), valueBytes: ByteLimit(
          1))).value) # RO key and first RW memo octet.

proc sameRoot(state: StateStore, rows: seq[StateEntry]) =
  ## Compare complete-map commitments, never a root reconstructed from partial service state.
  let wanted = newStateStore(rows, integrationStoreLimits()).value
  assert array[32, byte](state.snapshot.value.commitment.root) ==
    array[32, byte](wanted.snapshot.value.commitment.root), "exact full map including unrelated records"

proc collect(plan: PreparedAccumulationBatch): PreparedAccumulationTransfers =
  ## Only this common-source batch's actual normalized outcomes can contribute outgoing values.
  let outcomes = [plan.batchOutcomeAt(AccumulationProvisionSourceIndex(0)).value,
    plan.batchOutcomeAt(AccumulationProvisionSourceIndex(1)).value]
  prepareAccumulationTransfers(outcomes, AccumulationTransferCollectionLimits(
    sources: ElementLimit(2), transfers: ElementLimit(6), memoBytes: ByteLimit(768))).value

# Halt/hash return preserve both appends; every exceptional terminal selects the checkpoint prefix or original credit.
for ending in [DebitEnding.Halt, DebitEnding.HashReturn, DebitEnding.Panic, DebitEnding.Fault,
    DebitEnding.OutOfGas]:
  for checkpoint in [false, true]:
    let source = fixture(envelope(checkpoint = checkpoint, repeat = true, ending = ending))
    let first = execute(source)
    let second = execute(source, 1)
    assert first.error == AccumulationDispatchError.None and second.error ==
        AccumulationDispatchError.None
    let normal = ending in {DebitEnding.Halt, DebitEnding.HashReturn}
    let retained = (if normal: 2 else: (if checkpoint: 1 else: 0))
    let wantedBalance = 17-5*uint64(retained)
    for reverse in [false, true]:
      let plan = (if reverse: prepare(source, second, first) else: prepare(source, first, second)).value
      let outgoing = collect(plan)
      assert outgoing.transferCollectionInfo.value.transfers == retained
      for index in 0..<retained:
        let value = outgoing.collectedTransferAt(CollectedTransferIndex(uint64(index))).value
        assert uint32(value.source) == 42 and uint32(value.destination) == 99
        assert uint64(value.amount) == 5 and uint64(value.gas) == 0
        let bytes = array[128, byte](value.memo)
        for offset in 0..<128:
          assert bytes[offset] == byte((offset*7+3) mod 256) # Complete duplicate memos survive publication planning.
      var state = source.state
      discard applyAccumulationBatch(state, plan).value
      sameRoot(state, expectedRows(source, wantedBalance, 31))
      assert uint64(metadata(source.state.snapshot.value, 42).balance) == 10, "prior remains uncredited"
      assert uint64(metadata(state.snapshot.value, 99).balance) == 31, "outgoing destination gets no credit in this round"

# Two stale sibling views cannot replace each other's own final debits or incoming credits.
let mutual = fixture(envelope(), envelope(3, 42))
let a = execute(mutual)
let b = execute(mutual, 1)
let selected = prepare(mutual, a, b).value
var mutualState = mutual.state
discard applyAccumulationBatch(mutualState, selected).value
sameRoot(mutualState, expectedRows(mutual, 12, 28))
assert collect(selected).transferCollectionInfo.value.transfers == 2
let beforeStale = mutualState.snapshot.value
failHash(1)
assert applyAccumulationBatch(mutualState, selected).error == AccumulationBatchError.StaleState and
    hashCalls() == 0
failHash(0)
assert sameStateSnapshot(beforeStale, mutualState.snapshot.value), "stale application cannot debit or credit again"
let foreign = fixture(envelope(), envelope(3, 42))
assert prepare(mutual, execute(foreign), b).error == AccumulationBatchError.SourceMismatch
assert prepare(mutual, a, a).error == AccumulationBatchError.DuplicateService
failHash(1)
assert prepare(mutual, a, b, accounts = 1).error == AccumulationBatchError.LimitExceeded and
    hashCalls() == 0
failHash(0)

# Self and zero transfers retain their debit proof even without an incoming-credit map fork.
for incoming in [false, true]:
  for amount in [0'u64, 5]:
    let source = fixture(envelope(amount, 42), incoming = incoming)
    let first = execute(source)
    let context = first.effects.effectContext(AccumulationDimension.Regular).value
    assert context.effectAccountScope.value == AccumulationAccountScope.SelfMetadata
    let second = execute(source, 1)
    let plan = prepare(source, first, second).value
    var state = source.state
    discard applyAccumulationBatch(state, plan).value
    sameRoot(state, expectedRows(source, (if incoming: 17'u64 else: 10'u64)-amount,
      (if incoming: 31'u64 else: 20'u64)))
    let outgoing = collect(plan).collectedTransferAt(CollectedTransferIndex(0)).value
    assert uint32(outgoing.destination) == 42 and uint64(outgoing.amount) == amount
    if not incoming and amount == 0:
      assert plan.batchInfo.value.accountWrites == 1, "equal metadata does not erase successful mutation ancestry"
      failHash(1)
      assert prepare(source, first, second, accounts = 0).error ==
          AccumulationBatchError.LimitExceeded
      failHash(0)

# Upgrade and bounded self-key writes compose on either side of a transfer without losing their proof traces.
for storage in [false, true]:
  for before in [false, true]:
    let mutation = (if storage:
      @[@[51'u8, 7, 255], registerImmediate(8, 65536), registerImmediate(9, 1), registerImmediate(
          10, 196608),
        registerImmediate(11, 1), @[10'u8, 5]] else:
      @[@[51'u8, 7, 255], registerImmediate(8, 196608), registerImmediate(9, 7), registerImmediate(
          10, 9), @[10'u8, 21]])
    var code: seq[seq[byte]] = @[]
    if before:
      append(code, mutation) # A later transfer must preserve an existing supported key proof.
    append(code, transfer(99, 5))
    if not before:
      append(code, mutation) # A later self writer must preserve the earlier debit and outgoing sequence.
    code.add(@[50'u8, 0])
    let source = fixture(guestEnvelope(code, memo()))
    let first = execute(source, keys = 1)
    let plan = prepare(source, first, execute(source, 1), keys = 1, bytes = 1).value
    var state = source.state
    discard applyAccumulationBatch(state, plan).value
    sameRoot(state, expectedRows(source, 12, 31, upgrade = not storage, storage = storage))
    assert collect(plan).transferCollectionInfo.value.transfers == 1
    if storage:
      assert plan.batchInfo.value.selfWrites == 1 and plan.batchInfo.value.selfValueBytes == 1
      assert prepare(source, first, execute(source, 1)).error ==
          AccumulationBatchError.LimitExceeded
    # The same untraced storage change must remain unsupported, even after a later supported transfer.
    if storage:
      let untraced = execute(source)
      assert untraced.effects.effectContext(AccumulationDimension.Regular).value.effectAccountScope.value ==
        AccumulationAccountScope.Unsupported
      assert prepare(source, untraced, execute(source, 1)).error ==
          AccumulationBatchError.UnsupportedAccountEffects

# Transfer preserves created-account facts regardless of whether the child was created before or after the debit.
for before in [false, true]:
  var code: seq[seq[byte]] = @[]
  if before:
    append(code, transfer(99, 5)) # Creation must retain an already certified self debit.
  append(code, @[@[51'u8, 7, 255], registerImmediate(8, high(uint64)), @[51'u8, 9, 0],
    registerImmediate(10, 196736), @[10'u8, 20]])
  if not before:
    append(code, transfer(99, 5)) # Transfer must retain the earlier child's membership proof.
  code.add(@[50'u8, 0])
  var childInput = memo()
  childInput.setLen(188)
  for index in 0..<32:
    let octet = childInput[index]
    childInput[128+index] = octet # Scalar extraction ends the immutable borrow before the destination mutation.
  childInput[160] = 1 # Current E4 code length follows that code hash at RW+128.
  let source = fixture(guestEnvelope(code, childInput))
  let first = batchExecution(source, 0, copyLimit = MemoryByteLimit(128), parameters = profile(),
    transferLimit = ElementLimit(1), createdAccounts = ElementLimit(1),
        serviceProbes = ServiceProbeLimit(1))
  let second = execute(source, 1)
  let context = first.effects.effectContext(AccumulationDimension.Regular).value
  assert context.effectAccountScope.value == AccumulationAccountScope.CreatedAccounts, "creation scope survives transfer on either side"
  let child = context.effectCreatedAccountAt(AccumulationCreatedAccountIndex(0)).value.service
  let plan = prepareCompleteAccumulationBatch(source.inputs, source.state.snapshot.value,
    [first, second], [], HeaderSlot(128), batchPolicy(createdAccounts = 1)).value
  var state = source.state
  discard applyAccumulationBatch(state, plan).value
  var rows = expectedRows(source, 12, 31)
  var digest = default(array[32, byte])
  let input = memo()
  for index in 0..<32:
    digest[index] = input[index] # Literal code-hash proposal is copied exactly into child metadata.
  rows.add(serviceMetadataEntry(child, ServiceMetadata(codeHash: CodeHash(digest),
    storageItems: AccountStorageItems(2), storageBytes: AccountStorageBytes(82),
    supervisor: ServiceIndex(42), created: AccountSlot(128), parent: ServiceIndex(42)), ByteLimit(
        ServiceMetadataBytes)).value)
  rows.add(serviceRequestEntry(child, ServicePreimageHash(digest), RequestLength(1),
      requestedHistory(),
    RequestEntryConfig(keyBytes: ByteLimit(32), history: RequestHistoryConfig(items: ElementLimit(
        0), maxBytes: ByteLimit(1)))).value)
  sameRoot(state, rows)
  assert plan.batchInfo.value.createdAccounts == 1 and collect(
      plan).transferCollectionInfo.value.transfers == 1
  assert prepare(source, first, second).error == AccumulationBatchError.LimitExceeded

# Eject and transfer keep the genuine foreign removal proof on either side of the own-metadata debit.
for before in [false, true]:
  let blob = @[5'u8, 7, 9]
  let digest = ServicePreimageHash(array[32, byte](blake2b256(blob).value))
  var input = memo()
  for index, octet in array[32, byte](digest):
    input[index] = octet # Eject ignores memo/hash bytes; transfer retains this exact fixed memo.
  var identity = default(array[32, byte])
  identity[0] = 42
  let target = @[
    serviceMetadataEntry(ServiceIndex(77), ServiceMetadata(codeHash: CodeHash(identity),
      supervisor: ServiceIndex(42), balance: AccountBalance(9)), ByteLimit(
          ServiceMetadataBytes)).value]
  var code: seq[seq[byte]] = @[]
  if before:
    append(code, transfer(99, 5)) # A later eject must retain the prior debit's supported ancestry.
  append(code, @[registerImmediate(7, 77), registerImmediate(8, 196608), @[10'u8, 23]])
  if not before:
    append(code, transfer(99, 5)) # A later transfer must preserve the captured deletion facts.
  code.add(@[50'u8, 0])
  let source = batchFixture(firstEnvelope = guestEnvelope(code, input),
    secondEnvelope = guestEnvelope([@[50'u8, 0]]), extra = target)
  let first = batchExecution(source, 0, slot = HeaderSlot(50000), copyLimit = MemoryByteLimit(128),
      parameters = profile(),
    transferLimit = ElementLimit(1), deletedAccounts = ElementLimit(1))
  let second = batchExecution(source, 1, slot = HeaderSlot(50000))
  assert first.effects.effectContext(AccumulationDimension.Regular).value.effectAccountScope.value ==
    AccumulationAccountScope.DeletedAccounts, "mature eligible eject retains deletion scope across transfer"
  let plan = prepareCompleteAccumulationBatch(source.inputs, source.state.snapshot.value,
    [first, second], [], HeaderSlot(50000), batchPolicy(deletedAccounts = 1)).value
  var rows: seq[StateEntry] = @[]
  for entry in expectedRows(source, 21, 31):
    var removed = false
    for deleted in target:
      if array[31, byte](entry.key) == array[31, byte](deleted.key):
        removed = true # The empty target metadata is the only deleted service record.
    if not removed:
      rows.add(entry) # Preserve every unrelated record and the independently credited/debited self metadata.
  var state = source.state
  discard applyAccumulationBatch(state, plan).value
  sameRoot(state, rows)
  assert plan.batchInfo.value.deletedAccounts == 1 and collect(
      plan).transferCollectionInfo.value.transfers == 1
  assert prepareCompleteAccumulationBatch(source.inputs, source.state.snapshot.value,
    [first, second], [], HeaderSlot(50000), batchPolicy()).error ==
        AccumulationBatchError.LimitExceeded,
    "retained deletion proof consumes its independent batch budget"

# A no-credit preparation must still pay for one metadata replacement, and a backend failure publishes neither debit.
let noCredit = fixture(envelope(), incoming = false)
let noCreditFirst = execute(noCredit)
let noCreditSecond = execute(noCredit, 1)
failHash(1)
assert prepare(noCredit, noCreditFirst, noCreditSecond, accounts = 0).error ==
    AccumulationBatchError.LimitExceeded
failHash(0)
for successful in [0, 2]:
  var state = mutual.state
  let prior = state.snapshot.value
  hashAfter(cint(successful))
  let failed = applyAccumulationBatch(state, selected)
  assert failed.error == AccumulationBatchError.StoreFailure and failed.storeError ==
      StateStoreError.BackendFailure
  failHash(0)
  assert sameStateSnapshot(prior, state.snapshot.value), "early or delayed account hashing failure retains the exact prior"

# A late provision failure must discard a fully computed debit/credit candidate too.
let withProvision = batchFixture(firstEnvelope = envelope())
let debit = execute(withProvision)
let provider = execute(withProvision, 1)
let pending = prepare(withProvision, debit, provider).value
var calibrated = withProvision.state
var writes: seq[StateWrite] = @[]
for service in [42'u32, 99'u32]:
  var account = metadata(withProvision.state.snapshot.value, service)
  account.balance = AccountBalance(if service == 42: 12 else: 31)
  let entry = serviceMetadataEntry(ServiceIndex(service), account, ByteLimit(
      ServiceMetadataBytes)).value
  writes.add(StateWrite(key: entry.key, kind: StateWriteKind.Put, value: entry.value))
failHash(0)
discard calibrated.apply(writes).value
let accountHashes = hashCalls()
assert accountHashes > 0
var late = withProvision.state
let latePrior = late.snapshot.value
hashAfter(accountHashes)
let refused = applyAccumulationBatch(late, pending)
assert refused.error == AccumulationBatchError.TerminalFailure and refused.provisionError ==
    AccumulationProvisionError.BackendFailure
failHash(0)
assert sameStateSnapshot(latePrior, late.snapshot.value), "late provision refusal publishes no credit or debit"

var detached = default(PreparedAccumulationBatch)
var detachedState = default(StateStore)
block released_callers:
  let local = fixture(envelope())
  detached = prepare(local, execute(local), execute(local, 1)).value
  detachedState = local.state # Execution arrays and their local fixture do not survive this scope.
discard applyAccumulationBatch(detachedState, detached).value
assert uint64(metadata(detachedState.snapshot.value, 42).balance) == 12
assert collect(detached).transferCollectionInfo.value.transfers == 1
block deferred_funding_publication:
  for foreign in [false, true]:
    for mode in 0'u64..3:
      let instructions = @[registerImmediate(7, (if foreign: 77'u64 else: high(uint64))),
          registerImmediate(8, 99), registerImmediate(9, mode), registerImmediate(10, 5),
          registerImmediate(11, 0), registerImmediate(12, 196608), @[10'u8, 22], @[50'u8, 0]]
      let payer = ServiceMetadata(balance: AccountBalance(10), supervisorBalance: AccountBalance(
          10), supervisor: ServiceIndex(42), supervisorCreated: AccountSlot(0),
              created: AccountSlot(7))
      let payerEntry = serviceMetadataEntry(ServiceIndex(77), payer, ByteLimit(
          ServiceMetadataBytes)).value
      var source = batchFixture(incoming = false, firstEnvelope = guestEnvelope(instructions, memo(
        )), secondEnvelope = guestEnvelope([@[50'u8, 0]]), extra = @[payerEntry])
      let ownKey = chapterServiceKey(StateChapter(255), ServiceIndex(42))
      var own = metadata(source.state.snapshot.value, 42)
      own.supervisorBalance = AccountBalance(10)
      let ownEntry = serviceMetadataEntry(ServiceIndex(42), own, ByteLimit(
          ServiceMetadataBytes)).value
      discard source.state.apply([StateWrite(key: ownKey, kind: StateWriteKind.Put,
          value: ownEntry.value)]).value
      let first = execute(source)
      let second = execute(source, 1)
      assert first.error == AccumulationDispatchError.None, "funding matrix executes genuine deferred transfers"
      let selected = first.effects.effectContext(AccumulationDimension.Regular).value
      let outgoing = selected.effectTransferAt(AccumulationTransferIndex(0)).value
      assert uint32(outgoing.source) == (if foreign: 77'u32 else: 42'u32) and
          outgoing.destinationSupervisor == (mode >= 2), "retained output preserves payer and destination pool"
      let plan = prepare(source, first, second)
      if foreign:
        assert plan.error == AccumulationBatchError.UnsupportedAccountEffects,
            "foreign debit cannot inherit a self metadata publication certificate"
        let unchanged = metadata(source.state.snapshot.value, 77)
        assert uint64(unchanged.balance) == 10 and uint64(unchanged.supervisorBalance) == 10,
            "refused foreign publication retains both payer pools"
      else:
        assert plan.error == AccumulationBatchError.None, "self deferred funding modes retain complete publication"
        discard applyAccumulationBatch(source.state, plan.value).value
        let paid = metadata(source.state.snapshot.value, 42)
        assert uint64(paid.balance) == (if mode in [0'u64, 2]: 5'u64 else: 10'u64) and
            uint64(paid.supervisorBalance) == (if mode in [1'u64, 3]: 5'u64 else: 10'u64),
            "complete self publication debits only its selected pool"
        let recipient = metadata(source.state.snapshot.value, 99)
        assert uint64(recipient.balance) == 20 and uint64(recipient.supervisorBalance) == 0,
            "neither deferred destination pool receives an early batch credit"
        let creditedInputs = prepareAccumulationInputs(source.inputs.invocationOperands.value,
            [outgoing], [], AccumulationInputConfig(inputs: ElementLimit(1),
                allowances: ElementLimit(0), services: ElementLimit(1))).value
        let receiver = prepareAccumulationService(creditedInputs, InvocationServiceIndex(0),
            source.state.snapshot.value, HeaderSlot(129), AccumulationServiceConfig(
                codeLimit: ServiceCodeLimit(512), preimageBytes: ByteLimit(1024))).value
        let credited = receiver.serviceInfo.value.account
        assert uint64(credited.balance) == (if mode < 2: 25'u64 else: 20'u64) and
            uint64(credited.supervisorBalance) == (if mode < 2: 0'u64 else: 5'u64),
            "the produced record credits exactly its selected pool in the next invocation"


block direct_cross_pool_publication:
  for foreign in [false, true]:
    for mode in [1'u64, 2]:
      let endpoint = if foreign: 77'u64 else: high(uint64)
      let instructions = @[registerImmediate(7, endpoint), registerImmediate(8, endpoint),
          registerImmediate(9, mode), registerImmediate(10, 5), registerImmediate(11, high(uint64)),
          registerImmediate(12, 0), @[10'u8, 22], @[50'u8, 0]]
      let payer = ServiceMetadata(balance: AccountBalance(10), supervisorBalance: AccountBalance(
          10), supervisor: ServiceIndex(42), supervisorCreated: AccountSlot(0),
              created: AccountSlot(7))
      let payerEntry = serviceMetadataEntry(ServiceIndex(77), payer, ByteLimit(
          ServiceMetadataBytes)).value
      var source = batchFixture(incoming = false, writes = 2, firstEnvelope = guestEnvelope(
          instructions), secondEnvelope = guestEnvelope([@[50'u8, 0]]), extra = @[payerEntry])
      let ownKey = chapterServiceKey(StateChapter(255), ServiceIndex(42))
      var own = metadata(source.state.snapshot.value, 42)
      own.supervisorBalance = AccountBalance(10)
      let ownEntry = serviceMetadataEntry(ServiceIndex(42), own, ByteLimit(
          ServiceMetadataBytes)).value
      discard source.state.apply([StateWrite(key: ownKey, kind: StateWriteKind.Put,
          value: ownEntry.value)]).value
      let first = batchExecution(source, 0, parameters = profile(), copyLimit = MemoryByteLimit(0))
      let second = batchExecution(source, 1, parameters = profile(), copyLimit = MemoryByteLimit(0))
      assert first.error == AccumulationDispatchError.None, "same-account direct funding needs only one metadata write"
      let selected = first.effects.effectContext(AccumulationDimension.Regular).value
      assert selected.effectInfo.value.transfers == 0, "direct cross-pool move owns no deferred output"
      let accountKey = chapterServiceKey(StateChapter(255), ServiceIndex(
          if foreign: 77'u32 else: 42'u32))
      let accountBytes = selected.effectAccounts.value.lookup(accountKey).value.bytes
      let paid = decodeServiceMetadata(accountBytes, ByteLimit(ServiceMetadataBytes)).value.metadata
      assert uint64(paid.balance) == (if mode == 1: 15'u64 else: 5'u64) and
          uint64(paid.supervisorBalance) == (if mode == 1: 5'u64 else: 15'u64),
          "one metadata write combines same-account selected debit and credit"
      let plan = prepare(source, first, second)
      if foreign:
        assert plan.error == AccumulationBatchError.UnsupportedAccountEffects,
            "even a single foreign cross-pool record retains the parallel publication gate"
      else:
        assert plan.error == AccumulationBatchError.None, "self direct cross-pool effects retain metadata publication"
        discard applyAccumulationBatch(source.state, plan.value).value
        let published = metadata(source.state.snapshot.value, 42)
        assert uint64(published.balance) == uint64(paid.balance) and
            uint64(published.supervisorBalance) == uint64(paid.supervisorBalance),
            "complete self publication retains both direct pool fields"

let before = getOccupiedMem()
for iteration in 0..<1000:
  let plan = prepare(mutual, a, b).value
  var state = mutual.state
  discard applyAccumulationBatch(state, plan).value
  assert uint64(metadata(state.snapshot.value, 42).balance) == 12
  assert collect(plan).transferCollectionInfo.value.transfers ==
      2 # Release candidate maps and retained collection owners each cycle.
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_transfer_publication", 1000, before, after)
echo "PVM transfer publication passed"
echo "ARC_RELEASE cycles=1000 unchanged"
