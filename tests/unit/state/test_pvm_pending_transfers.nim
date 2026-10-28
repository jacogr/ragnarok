# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_pending_transfers_arc_release"}

## Genuine terminal outputs and prior partitions preserve carry order and gas without a second refund.
import std/assertions
import std/syncio
import ../../../src/state/accumulation_pending_transfers as state_accumulation_pending_transfers
import ../../../src/state/accumulation_transfer_partition as state_accumulation_transfer_partition
import ../../../src/state/accumulation_transfers as state_accumulation_transfers
import ../../../src/state/accumulation_outcome as state_accumulation_outcome
import ../../../src/state/accumulation_effects as state_accumulation_effects
import ../../../src/state/store as state_store
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/composite as codec_composite
import ../../../src/codec/state_accounts as codec_state_accounts
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/codec/c2_records as codec_c2_records
import ../../support/state_accumulation_transfers
import ../../support/testing_arc_evidence

# Queue preparation and partitioning perform no new state hashes or publication.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
proc policy(sources = 4'u64, transfers = 8'u64, memo = 1024'u64): PendingTransferLimits =
  ## Producer, record and memo work ceilings remain independent.
  PendingTransferLimits(sources: ElementLimit(sources), transfers: ElementLimit(transfers),
      memoBytes: ByteLimit(memo))
proc partitionPolicy(): TransferPartitionLimits =
  ## Small finite state/active/record work bounds every partition in this suite.
  TransferPartitionLimits(transfers: ElementLimit(8), services: ElementLimit(4),
      checks: ElementLimit(1000))
proc prior(): StateStoreSnapshot =
  ## Current service1 supervises service42 by an actual matching creation slot.
  let entries = [serviceMetadataEntry(ServiceIndex(1), ServiceMetadata(supervisor: ServiceIndex(1),
      supervisorCreated: AccountSlot(11), created: AccountSlot(11)), ByteLimit(
          ServiceMetadataBytes)).value,
      serviceMetadataEntry(ServiceIndex(42), ServiceMetadata(supervisor: ServiceIndex(1),
          supervisorCreated: AccountSlot(11), created: AccountSlot(43)), ByteLimit(
              ServiceMetadataBytes)).value]
  newStateStore(entries, StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(8),
      perValue: ByteLimit(256), totalValueBytes: ByteLimit(2048), nodes: TrieNodeLimit(
          1000)))).value.snapshot.value
proc carried(gas: uint64, ordinal: byte): DeferredTransfer =
  ## Full fixed fields distinguish old records from genuine newly emitted duplicates.
  var memo = default(array[128, byte])
  for index in 0..<128: memo[index] = byte((index+int(ordinal)) mod 256)
  DeferredTransfer(source: ServiceIndex(70'u32+uint32(ordinal)), destination: ServiceIndex(42),
      destinationSupervisor: true, amount: TransferBalance(uint64(ordinal)), gas: Gas(gas),
          memo: TransferMemo(memo))
proc checkRecord(actual, expected: DeferredTransfer) =
  ## Query copies preserve every fixed field while allowing independent caller mutation.
  assert uint32(actual.source) == uint32(expected.source), "pending source identity"
  assert uint32(actual.destination) == uint32(expected.destination), "pending destination identity"
  assert actual.destinationSupervisor == expected.destinationSupervisor, "pending destination pool"
  assert uint64(actual.amount) == uint64(expected.amount), "pending complete amount"
  assert uint64(actual.gas) == uint64(expected.gas), "pending complete gas"
  let actualMemo = array[128, byte](actual.memo)
  let expectedMemo = array[128, byte](expected.memo)
  assert actualMemo == expectedMemo, "pending complete raw memo"

let state = prior()
let outcome = normalizeAccumulationOutcome(transferExecution(duplicate = true,
    offeredGas = 9)).value
let used = uint64(outcome.outcomeInfo.value.gasUsed)
assert used > 18 and used < 99970, "genuine paid host fees leave room for explicit old gas"
let outgoing = prepareAccumulationTransfers([outcome], collectionLimits()).value
assert outgoing.transferCollectionInfo.value.transfers == 2, "genuine duplicate outputs remain two paid records"
let emptyOutgoing = prepareAccumulationTransfers([], collectionLimits(0, 0, 0)).value
let oldFirst = carried(30, 1)
let oldSecond = carried(0, 2)
let accepted = DeferredTransfer(source: ServiceIndex(99), destination: ServiceIndex(1), gas: Gas(7))
let previous = prepareAccumulationTransferPartition(state, [oldFirst, accepted, oldSecond],
    [ServiceIndex(1)], partitionPolicy()).value
assert previous.partitionCount(TransferPartitionKind.Queued).value == 2, "the source contributes only its two held records"
let initial = prepareInitialPendingTransfers(outgoing, Gas(100000), policy()).value
let initialInfo = initial.pendingTransferInfo.value
assert initialInfo.transfers == 2 and initialInfo.carried == 0 and initialInfo.outgoing == 2,
    "initial queue contains only actual newly emitted records"
assert uint64(initialInfo.gasUsed) == used and uint64(initialInfo.outgoingGas) == 18,
    "gas usage is derived from actual retained producers and fixed paid offers"
assert uint64(initialInfo.budget) == 100000-used+18 and uint64(initialInfo.reportBudget) ==
    100000-used,
    "initial next budget restores only paid outgoing gas"
assert uint64(initialInfo.reservedGas) == 18 and uint64(initialInfo.carriedGas) == 0,
    "initial outgoing refund is immediately reserved"
let noPrevious = initial.pendingPreviousPartition
assert noPrevious.error == PendingTransferError.NoPrevious, "initial source absence is not a default fake partition"
let next = prepareCarriedPendingTransfers(previous, outgoing, Gas(100000), policy()).value
let info = next.pendingTransferInfo.value
assert info.transfers == 4 and info.carried == 2 and info.outgoing == 2,
    "old held subsequence precedes new output without collapsing duplicates"
assert uint64(info.budget) == 100000-used+18 and uint64(info.reportBudget) == 100000-used-30,
    "carried gas remains reserved without an additional refund"
assert uint64(info.carriedGas) == 30 and uint64(info.outgoingGas) == 18 and uint64(
    info.reservedGas) == 48,
    "separate old/new reservation observations remain exact"
checkRecord(next.pendingTransferAt(PendingTransferIndex(0)).value, oldFirst)
checkRecord(next.pendingTransferAt(PendingTransferIndex(1)).value, oldSecond)
for index in 0..<2:
  let row = outgoing.collectedTransferAt(CollectedTransferIndex(uint64(index))).value
  checkRecord(next.pendingTransferAt(PendingTransferIndex(uint64(index+2))).value, row)
let retainedPrevious = next.pendingPreviousPartition.value
assert sameStateSnapshot(retainedPrevious.partitionPrior.value, state), "carried source retains its actual immutable prior"
let retainedSource = next.pendingOutgoing.value.transferCollectionSourceAt(
    AccumulationTransferSourceIndex(0)).value
assert sameStateSnapshot(retainedSource.outcomeContext.value.effectAccounts.value,
    outcome.outcomeContext.value.effectAccounts.value), "new source retains the exact producer account owner"
var copied = next.pendingTransferAt(PendingTransferIndex(0)).value
copied.source = ServiceIndex(0)
copied.memo = TransferMemo(default(array[128, byte]))
checkRecord(next.pendingTransferAt(PendingTransferIndex(0)).value, oldFirst)
let allHeld = next.partitionPendingTransfers(state, [ServiceIndex(1)], partitionPolicy()).value
assert allHeld.partitionCount(TransferPartitionKind.Queued).value == 4, "current supervisor execution holds all four pending records"
let deliverable = next.partitionPendingTransfers(state, [], partitionPolicy()).value
assert deliverable.partitionCount(TransferPartitionKind.Accepted).value == 4, "a later quiet entry can deliver every preserved duplicate"
let heldAgain = prepareCarriedPendingTransfers(allHeld, emptyOutgoing, info.budget, policy()).value
let heldInfo = heldAgain.pendingTransferInfo.value
assert uint64(heldInfo.gasUsed) == 0 and uint64(heldInfo.outgoingGas) == 0, "empty producer set cannot fabricate another refund"
assert uint64(heldInfo.budget) == uint64(info.budget) and uint64(heldInfo.carriedGas) == 48,
    "carrying the same paid records again leaves the recursive budget unchanged"
assert uint64(heldInfo.reportBudget) == uint64(info.budget)-48,
    "all old pending gas remains reserved on a repeated carry"

# Boundary arithmetic is proved by subtraction, including full-width carried reservations.
let exact = prepareCarriedPendingTransfers(previous, outgoing, Gas(used+30), policy()).value.pendingTransferInfo.value
assert uint64(exact.budget) == 48 and uint64(exact.reservedGas) == 48 and uint64(
    exact.reportBudget) == 0,
    "exact remaining budget carries30 plus refunds/reserves18 without inventing report credit"
let shortCarry = prepareCarriedPendingTransfers(previous, outgoing, Gas(used+29), policy())
assert shortCarry.error == PendingTransferError.InvalidBudget, "a new refund cannot cover a shortage in already reserved carried gas"
let shortUsage = prepareInitialPendingTransfers(outgoing, Gas(used-1), policy())
assert shortUsage.error == PendingTransferError.InvalidBudget, "actual producer usage cannot exceed the supplied prior budget"
let full = carried(high(uint64), 3)
let fullPrevious = prepareAccumulationTransferPartition(state, [full], [ServiceIndex(1)],
    partitionPolicy()).value
let fullQueue = prepareCarriedPendingTransfers(fullPrevious, emptyOutgoing, Gas(high(uint64)),
    policy()).value
let fullInfo = fullQueue.pendingTransferInfo.value
assert uint64(fullInfo.budget) == high(uint64) and uint64(fullInfo.carriedGas) == high(uint64),
    "a complete unsigned reservation remains exact"
assert uint64(fullInfo.reservedGas) == high(uint64) and uint64(fullInfo.reportBudget) == 0,
    "full-width carry neither wraps nor becomes report allowance"
let overflow = prepareCarriedPendingTransfers(fullPrevious, outgoing, Gas(high(uint64)), policy())
assert overflow.error == PendingTransferError.InvalidBudget, "actual usage plus full carried gas refuses before any aggregate addition can wrap"
let highSafe = carried(high(uint64)-used, 4)
let highPrevious = prepareAccumulationTransferPartition(state, [highSafe], [ServiceIndex(1)],
    partitionPolicy()).value
let highQueue = prepareCarriedPendingTransfers(highPrevious, outgoing, Gas(high(uint64)), policy()).value.pendingTransferInfo.value
assert uint64(highQueue.budget) == high(uint64)-used+18 and uint64(highQueue.reservedGas) == high(
    uint64)-used+18,
    "near-maximum carry and paid gas combine within their proved prior budget"
assert uint64(highQueue.reportBudget) == 0, "near-maximum reservation has exact zero report allowance"

# Every retained producer contributes its actual gas, including duplicates and empty outgoing lists.
let duplicateSources = prepareAccumulationTransfers([outcome, outcome], collectionLimits(2, 4, 512)).value
let both = prepareInitialPendingTransfers(duplicateSources, Gas(200000), policy()).value.pendingTransferInfo.value
assert uint64(both.gasUsed) == 2*used and uint64(both.outgoingGas) == 36,
    "repeated producer contributions retain their complete actual use and paid offers"
assert uint64(both.budget) == 200000-2*used+36 and both.transfers == 4,
    "all producer usage is subtracted before restoring only new paid gas"
let noOutput = transferOutcome(TransferEnding.Panic, checkpoint = false)
let noOutputUsed = uint64(noOutput.outcomeInfo.value.gasUsed)
let noOutputSource = prepareAccumulationTransfers([noOutput], collectionLimits()).value
let noOutputPending = prepareInitialPendingTransfers(noOutputSource, Gas(100000), policy(1, 0,
    0)).value.pendingTransferInfo.value
assert noOutputPending.transfers == 0 and uint64(noOutputPending.gasUsed) == noOutputUsed,
    "a zero-output producer still contributes its actual execution usage"
assert uint64(noOutputPending.budget) == 100000-noOutputUsed and uint64(
    noOutputPending.outgoingGas) == 0,
    "no-output rollback cannot refund gas from discarded regular transfers"
let noSourceWork = prepareInitialPendingTransfers(noOutputSource, Gas(100000), policy(0, 0, 0))
assert noSourceWork.error == PendingTransferError.LimitExceeded,
    "empty outgoing lists still consume producer inspection capacity"

# Each local ceiling and each source/selected-result boundary refuses the whole plan.
for ceiling in [policy(sources = 0), policy(transfers = 3), policy(memo = 511)]:
  let limited = prepareCarriedPendingTransfers(previous, outgoing, Gas(100000), ceiling)
  assert limited.error == PendingTransferError.LimitExceeded, "producer/record/memo limits are independent"
let exactPolicy = prepareCarriedPendingTransfers(previous, outgoing, Gas(100000), policy(1, 4, 512))
assert exactPolicy.error == PendingTransferError.None, "exact independent work/copy limits succeed"
let huge = prepareCarriedPendingTransfers(previous, outgoing, Gas(100000), policy(high(uint64),
    high(uint64), high(uint64)))
assert huge.error == PendingTransferError.None, "large ceilings never authorize an unchecked arithmetic conversion"
let missingSource = prepareInitialPendingTransfers(default(PreparedAccumulationTransfers), Gas(0), policy())
assert missingSource.error == PendingTransferError.InvalidSource, "default producer cannot authorize an empty queue"
let missingPrevious = prepareCarriedPendingTransfers(default(PreparedTransferPartition), outgoing,
    Gas(100000), policy())
assert missingPrevious.error == PendingTransferError.InvalidSource, "later preparation cannot substitute default for prior queued ownership"
let empty = prepareInitialPendingTransfers(emptyOutgoing, Gas(0), policy(0, 0, 0)).value
assert empty.pendingTransferInfo.value.transfers == 0, "genuine empty source fits exactly zero work/copy budgets"
let emptyPrevious = prepareAccumulationTransferPartition(state, [], [], partitionPolicy()).value
let laterEmpty = prepareCarriedPendingTransfers(emptyPrevious, emptyOutgoing, Gas(0), policy(0, 0, 0)).value
assert laterEmpty.pendingPreviousPartition.error == PendingTransferError.None, "genuine empty previous partition remains distinct from no previous source"
for index in [4'u64, high(uint64)]:
  let past = next.pendingTransferAt(PendingTransferIndex(index))
  assert past.error == PendingTransferError.InvalidIndex, "bound full-width pending ordinals before native narrowing"
let invalidPartition = next.partitionPendingTransfers(default(StateStoreSnapshot), [],
    partitionPolicy())
assert invalidPartition.error == PendingTransferError.PartitionFailure, "nested partition refusal retains no successful child"
assert invalidPartition.partitionError == TransferPartitionError.InvalidState, "nested partition reason remains exact"
let noWork = next.partitionPendingTransfers(state, [], default(TransferPartitionLimits))
assert noWork.error == PendingTransferError.PartitionFailure, "partition work limits remain separate from copied pending limits"
assert noWork.partitionError == TransferPartitionError.LimitExceeded, "nested partition capacity reason remains exact"
let defaultInfo = default(PreparedPendingTransfers).pendingTransferInfo
assert defaultInfo.error == PendingTransferError.Uninitialized, "default query contains no gas observations"
let defaultPrevious = default(PreparedPendingTransfers).pendingPreviousPartition
assert defaultPrevious.error == PendingTransferError.Uninitialized, "default ownership is not an initialized first entry"
failHash(1)
let unhashed = prepareCarriedPendingTransfers(previous, outgoing, Gas(100000), policy())
assert unhashed.error == PendingTransferError.None and hashCalls() == 0, "carry/copy/budget preparation performs no new hashes"
failHash(0)
let before = getOccupiedMem()
for iteration in 0..<1000:
  let owned = prepareCarriedPendingTransfers(previous, outgoing, Gas(100000), policy()).value
  let partition = owned.partitionPendingTransfers(state, [ServiceIndex(1)], partitionPolicy()).value
  let again = prepareCarriedPendingTransfers(partition, emptyOutgoing,
      owned.pendingTransferInfo.value.budget, policy()).value
  assert again.pendingTransferInfo.value.transfers == 4, "release copies and provenance handles without parent-queue chains"
let after = getOccupiedMem()
assert before == after, "pending transfer ownership releases every carried/new record and retained source"
recordArcRelease("pvm_pending_transfers", 1000, before, after)
echo "PVM pending transfers passed"
echo "ARC_RELEASE cycles=1000 unchanged"
