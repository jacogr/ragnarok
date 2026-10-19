# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Native incoming-transfer credit witnesses over complete owned maps, including independent roots.
## Hastur entry point covers ordering, code alternatives, bootstrap/context integration, rollback and ARC.

# @@Verification={"arc": "accumulation_credit_arc_release"}

import std/[assertions, envvars, strutils, parseutils, syncio]
import ../../../src/state/[accumulation_service, accumulation_skip, accumulation_invocation,
  accumulation_inputs, accumulation_operands, accumulation_queue, store]
import ../../../src/codec/[bounded, composite, work_digest, c2_records, state_accounts,
  state_service_values, state_workqueues, state_privileges, state_safrole, state_trie, state_layout, header]
import ../../../src/crypto/primitives
import ../../support/[report_context, arc_evidence]

## Refuse a precisely chosen hash after all independent fixture state is constructed.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
## Permit namespace/code hashes, then fail a later complete-map leaf or branch hash.
proc hashAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
## Observe whether zero credit unnecessarily attempted state Merklization.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}

## Parse full unsigned transport without signed intermediates or silent suffix acceptance.
proc number(text: string): uint64 =
  var parsed = 0'u64
  assert parseBiggestUInt(text, parsed) == text.len
  parsed

## Empty real queue/operand owners allow a transfer-only invocation without manufacturing private input handles.
proc inputs(transfers: openArray[DeferredTransfer], service = ServiceIndex(
    42)): PreparedAccumulationInputs =
  let queue = planAccumulationQueues([], [0'u8], [0'u8], HeaderSlot(0),
    AccumulationQueueConfig(queues: WorkQueueConfig(cores: CoreCount(2), epochSlots: EpochSlots(1),
      maxBytes: ByteLimit(1000)))).value
  let operands = prepareAccumulationOperands(queue, AccumulationReportPrefix(0), default(
      AccumulationOperandConfig)).value
  prepareAccumulationInputs(operands, transfers, [AlwaysAccumulate(service: service)],
    AccumulationInputConfig(inputs: ElementLimit(100), allowances: ElementLimit(1),
      services: ElementLimit(100))).value

## Keep one-byte code eligible while bounding full preimage work independently.
proc config(): AccumulationServiceConfig =
  AccumulationServiceConfig(codeLimit: ServiceCodeLimit(1), preimageBytes: ByteLimit(100))

## Observe full root identity only through the initialized immutable map contract.
proc root(state: StateStoreSnapshot): array[32, byte] = array[32, byte](state.commitment.root)

## Read actual retained metadata rather than trusting copied service information alone.
proc account(state: StateStoreSnapshot, service = ServiceIndex(42)): ServiceMetadata =
  decodeServiceMetadata(state.lookup(chapterServiceKey(StateChapter(255), service)).value.bytes,
    ByteLimit(89)).value.metadata

## Independent expected bytes and embedding-map roots cover literal arithmetic and published balance projections.
proc projections() {.raises.} =
  var count = 0
  # Every transport row supplies before/after metadata and roots computed without the Nim implementation.
  for line in readFile(getEnv("RAGNAROK_ACCUMULATION_CREDIT")).splitLines:
    if line.len == 0: continue # Only the final transport newline is empty.
    let f = line.splitWhitespace
    let service = ServiceIndex(uint32(number(f[1])))
    let key = chapterServiceKey(StateChapter(255), service)
    let records = @[StateEntry(key: key, value: unhex(f[2])),
      StateEntry(key: chapterKey(StateChapter(250)), value: @[byte('o'), byte('p'), byte('a'), byte(
          'q'), byte('u'), byte('e')])]
    let prior = newStateStore(records, limits()).value.snapshot.value
    var transfers: seq[DeferredTransfer] = @[]
    # Filtered source order remains visible; other destinations must not contribute any balance.
    let amounts = f[6].split(',')
    for ordinal, amount in amounts:
      transfers.add(DeferredTransfer(source: ServiceIndex(uint32(ordinal)), destination: service,
        amount: TransferBalance(number(amount)), gas: Gas(1)))
    let prepared = inputs(transfers, service)
    let owner = prepareAccumulationService(prepared, InvocationServiceIndex(0), prior,
      HeaderSlot(43), config()).value
    assert owner.serviceState.value.lookup(key).value.bytes == unhex(f[3]), f[0]
    assert root(prior) == root(owner.servicePriorState.value)
    assert unhex(f[4]) == @(root(prior))
    assert unhex(f[5]) == @(root(owner.serviceState.value))
    assert prior.lookup(key).value.bytes == unhex(f[2])
    assert owner.serviceInfo.value.transfers == transfers.len
    # Extracting input/metadata/state or completing skips repeatedly never applies a second credit.
    for i, transfer in transfers:
      assert uint64(owner.serviceInputAt(InvocationInputIndex(uint64(i))).value.transfer.amount) ==
          uint64(transfer.amount)
    let skipped = finishUninvokedAccumulation(owner).value
    assert root(skipped.skipState.value) == root(owner.serviceState.value)
    assert uint64(skipped.skipInfo.value.gasUsed) == 0 and skipped.skipInfo.value.transfers == 0
    assert root(finishUninvokedAccumulation(owner).value.skipState.value) == root(
        owner.serviceState.value)
    inc count
  assert count == 38

## Complete maps include unrelated opaque data and another account whose balance never changes.
proc records(raw: seq[byte], includeCode = true, balance = 10'u64): seq[StateEntry] =
  let hash = array[32, byte](blake2b256(raw).value)
  result = @[serviceMetadataEntry(ServiceIndex(42), ServiceMetadata(codeHash: CodeHash(hash),
    balance: AccountBalance(balance), lastAccumulation: AccountSlot(9),
        storageItems: AccountStorageItems(3)), ByteLimit(89)).value,
    serviceMetadataEntry(ServiceIndex(99), ServiceMetadata(balance: AccountBalance(50)), ByteLimit(
        89)).value,
    StateEntry(key: chapterKey(StateChapter(250)), value: @[1'u8, 2, 3])]
  if includeCode:
    result.add(servicePreimageEntry(ServiceIndex(42), ServicePreimageHash(hash), raw,
      ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(100))).value) # Exact hashed envelope.

## Multiple destinations, all code gates and zero/exact-maximum/overflow amounts preserve source ownership.
proc boundaries(): PreparedAccumulationService =
  result = default(PreparedAccumulationService) # Explicitly initialize the retained return owner.
  let transfers = @[DeferredTransfer(source: ServiceIndex(42), destination: ServiceIndex(42),
      amount: TransferBalance(7)),
    DeferredTransfer(destination: ServiceIndex(99), amount: TransferBalance(high(uint64))),
    DeferredTransfer(source: ServiceIndex(7), destination: ServiceIndex(42),
        amount: TransferBalance(13))]
  let source = inputs(transfers)
  # Every code gate receives the same incoming credit before skip or real invocation setup.
  for mode in 0..<5:
    let raw = if mode == 1: @[128'u8] elif mode == 2: @[0'u8, 1, 2] elif mode == 4: @[0'u8] else: @[
        0'u8, 7] # Missing, malformed, oversized, ready and empty ready.
    let prior = newStateStore(records(raw, mode != 0), limits()).value.snapshot.value
    let owner = prepareAccumulationService(source, InvocationServiceIndex(0), prior, HeaderSlot(3),
        config()).value
    assert uint64(owner.serviceInfo.value.account.balance) == 30
    assert uint64(owner.serviceState.value.account.balance) == 30
    assert uint64(owner.servicePriorState.value.account.balance) == 10
    assert uint64(owner.serviceState.value.account(ServiceIndex(99)).balance) == 50
    assert uint32(owner.serviceInfo.value.account.lastAccumulation) == 9
    assert uint32(owner.serviceInputAt(InvocationInputIndex(0)).value.transfer.source) == 42
    assert uint32(owner.serviceInputAt(InvocationInputIndex(1)).value.transfer.source) == 7
    if mode < 3:
      let skipped = finishUninvokedAccumulation(owner).value
      assert uint64(skipped.skipState.value.account.balance) ==
          30 # Missing/malformed/oversized code retains credit.
    else:
      let invoked = prepareAccumulationInvocation(owner, default(StateEntropyWord),
          ServiceProbeLimit(1)).value
      assert uint64(invoked.bootstrapInfo.value.inputs) == 2
      assert invoked.bootstrapArguments.value == @[3'u8, 42, 2]
      assert uint64(invoked.bootstrapService.value.serviceState.value.account.balance) == 30
      assert finishUninvokedAccumulation(owner).error == AccumulationSkipError.ExecutionRequired
    result = owner
  let prior = newStateStore(records(@[0'u8], false), limits()).value.snapshot.value
  let overflowing = inputs([DeferredTransfer(destination: ServiceIndex(42), amount: TransferBalance(
      high(uint64)))])
  failHash(1)
  assert prepareAccumulationService(overflowing, InvocationServiceIndex(0), prior, HeaderSlot(0),
      config()).error ==
    AccumulationServiceError.BalanceOverflow # Arithmetic preflight refuses before namespace hashing.
  failHash(0)
  let cumulative = inputs([DeferredTransfer(destination: ServiceIndex(42), amount: TransferBalance(
      high(uint64)-10)),
    DeferredTransfer(destination: ServiceIndex(42), amount: TransferBalance(1))])
  assert prepareAccumulationService(cumulative, InvocationServiceIndex(0), prior, HeaderSlot(0),
      config()).error == AccumulationServiceError.BalanceOverflow
  assert uint64(prior.account.balance) == 10
  assert default(PreparedAccumulationService).servicePriorState.error ==
      AccumulationServiceError.Uninitialized

## Inherited local ceilings and late hashing failures leave every source root and metadata byte unchanged.
proc rollback() =
  let raw = @[0'u8, 7]
  let rows = records(raw)
  let transferred = inputs([DeferredTransfer(destination: ServiceIndex(42), amount: TransferBalance(1))])
  # Reach each independently inherited write/byte/node limit only on the private credited candidate.
  for mode in 0..<3:
    var policy = limits()
    if mode == 0: policy.writes = ElementLimit(0) # Source initialization remains valid without write allowance.
    elif mode == 1: policy.writeValueBytes = ByteLimit(88) # Exact 89-byte replacement must fit.
    else: policy.trie.nodes = TrieNodeLimit(uint64(stateTrieRoot(rows,
        policy.trie).value.nodes)) # Same-shape replacement still fits.
    let prior = newStateStore(rows, policy).value.snapshot.value
    let observed = prepareAccumulationService(transferred, InvocationServiceIndex(0), prior,
        HeaderSlot(0), config())
    if mode < 2:
      assert observed.error == AccumulationServiceError.LimitExceeded # No credited success after resource refusal.
    else:
      assert observed.error == AccumulationServiceError.None # Exact trie-node budget is sufficient.
    assert uint64(prior.account.balance) == 10
    let zero = inputs([DeferredTransfer(destination: ServiceIndex(42), amount: TransferBalance(0))])
    let unchanged = prepareAccumulationService(zero, InvocationServiceIndex(0), prior, HeaderSlot(
        0), config())
    assert unchanged.error == AccumulationServiceError.None
  let prior = newStateStore(rows, limits()).value.snapshot.value
  let expectedRoot = root(prior)
  # Two long account values add payload hashes to the leaf/branch hashes; include the final root refusal.
  for successful in 2..<4+int(prior.commitment.nodes):
    hashAfter(cint(successful))
    assert prepareAccumulationService(transferred, InvocationServiceIndex(0), prior, HeaderSlot(0),
        config()).error == AccumulationServiceError.BackendFailure
    failHash(0)
    assert root(prior) == expectedRoot and uint64(prior.account.balance) == 10
  let zero = inputs([DeferredTransfer(destination: ServiceIndex(42))])
  hashAfter(2)
  let unchanged = prepareAccumulationService(zero, InvocationServiceIndex(0), prior, HeaderSlot(0),
      config())
  assert unchanged.error == AccumulationServiceError.None
  assert hashCalls() == 2 # Zero credit avoids all Merklization work.
  failHash(0)

## Successful credited owners and overflow refusals release all acyclic branch/input storage each cycle.
proc lifetime() =
  let prior = newStateStore(records(@[0'u8], false), limits()).value.snapshot.value
  let source = inputs([DeferredTransfer(destination: ServiceIndex(42), amount: TransferBalance(1))])
  let refused = inputs([DeferredTransfer(destination: ServiceIndex(42), amount: TransferBalance(
      high(uint64)))])
  discard prepareAccumulationService(source, InvocationServiceIndex(0), prior, HeaderSlot(0),
      config())
  let before = getOccupiedMem()
  # Discarded successes, skips and refusals must retain no branch snapshots after the iteration.
  for i in 0..<1000:
    let owner = prepareAccumulationService(source, InvocationServiceIndex(0), prior, HeaderSlot(0),
        config()).value
    assert uint64(finishUninvokedAccumulation(owner).value.skipState.value.account.balance) == 11
    assert prepareAccumulationService(refused, InvocationServiceIndex(0), prior, HeaderSlot(0),
        config()).error == AccumulationServiceError.BalanceOverflow
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("accumulation_credit", 1000, before, after)

## Run independent projections and literal boundary/lifetime tests through the supported native runner.
proc main() {.raises.} =
  projections()
  let retained = boundaries()
  assert uint64(retained.serviceState.value.account.balance) == 30
  rollback()
  lifetime()
  echo "PASS accumulation credit: checked balances, complete roots, code gates, rollback and ARC"
try:
  main() # All native assertions and fixture reads must complete.
except:
  quit(2) # Unexpected I/O or exceptions are failures, never skipped witnesses.
