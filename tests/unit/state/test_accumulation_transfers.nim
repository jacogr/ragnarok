# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "accumulation_transfers_arc_release"}

## Collect actual terminal-selected transfers with exact ordering, bounds, immutable provenance and ARC release.

import std/[assertions, syncio]
import ../../../src/state/[accumulation_transfers, accumulation_outcome, accumulation_dispatch,
  accumulation_effects, accumulation_context]
import ../../../src/codec/[bounded, c2_records, composite, state_accounts, state_layout,
    state_service_values, state_trie]
import ../../../src/pvm/step
import ../../support/[accumulation_transfers, arc_evidence]

# Pure collection must succeed even when every new backend hash is disabled.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
# Observe that collection and value extraction never invoke the hashing backend.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}

proc checkTransfer(plan: PreparedAccumulationTransfers, index: uint64, service = 42'u32,
    second = false) =
  ## Independently inspect all fixed fields and every literal memo byte in selected append order.
  let value = plan.collectedTransferAt(CollectedTransferIndex(index)).value
  assert uint32(value.source) == service and uint32(value.destination) == service
  assert uint64(value.amount) == (if second: 0'u64 else: 5'u64)
  assert uint64(value.gas) == 0
  let memo = array[128, byte](value.memo)
  for offset in 0..<128:
    assert memo[offset] == (if second: (if offset == 0: 73'u8 else: 0'u8)
      else: byte((offset*7+3) mod 256)) # Memo identity never depends on a hash or string encoding.

let halted = transferOutcome()
let returned = transferOutcome(TransferEnding.HashReturn)
let panicked = transferOutcome(TransferEnding.Panic)
let faulted = transferOutcome(TransferEnding.Fault)
let exhausted = transferOutcome(TransferEnding.OutOfGas)
let empty = transferOutcome(TransferEnding.Panic, checkpoint = false)
let duplicates = transferOutcome(duplicate = true)
let other = transferOutcome(service = high(uint32))
for source in [halted, returned]:
  let plan = prepareAccumulationTransfers([source], collectionLimits()).value
  assert plan.transferCollectionInfo.value.transfers == 2
  checkTransfer(plan, 0)
  checkTransfer(plan, 1, second = true) # Regular X keeps both transfers even on hash return.
for source in [panicked, faulted, exhausted]:
  let plan = prepareAccumulationTransfers([source], collectionLimits()).value
  assert plan.transferCollectionInfo.value.transfers == 1
  checkTransfer(plan, 0) # Exceptional Y contains only the checkpointed first transfer.
assert exhausted.outcomeInfo.value.termination == AccumulationTermination.OutOfGas
assert faulted.outcomeInfo.value.termination == AccumulationTermination.Panic
assert prepareAccumulationTransfers([empty], collectionLimits(transfers = 0, memoBytes = 0)).value.
  transferCollectionInfo.value.transfers == 0
let duplicatePlan = prepareAccumulationTransfers([duplicates, duplicates], collectionLimits(
  transfers = 4, memoBytes = 512)).value
for index in 0..<4:
  checkTransfer(duplicatePlan, uint64(index)) # Identical source owners and transfers remain separate contributions.
let plan = prepareAccumulationTransfers([other, panicked, halted], collectionLimits(
  transfers = 5, memoBytes = 640)).value
let info = plan.transferCollectionInfo.value
assert info.sources == 3 and info.transfers == 5 and uint64(info.memoBytes) == 640
checkTransfer(plan, 0, high(uint32))
checkTransfer(plan, 1, high(uint32), second = true)
checkTransfer(plan, 2)
checkTransfer(plan, 3)
checkTransfer(plan, 4, second = true) # Supplied outcome order is not sorted or deduplicated.
for limits in [collectionLimits(sources = 2), collectionLimits(transfers = 4),
    collectionLimits(memoBytes = 639), collectionLimits(memoBytes = 0)]:
  assert prepareAccumulationTransfers([other, panicked, halted], limits).error ==
    AccumulationTransferCollectionError.LimitExceeded # Each independent boundary refuses the whole result.
let hugeLimits = collectionLimits(high(uint64), high(uint64), high(uint64))
assert prepareAccumulationTransfers([halted], hugeLimits).value.transferCollectionInfo.value.transfers == 2
let absentOutcome = default(AccumulationOutcome)
assert prepareAccumulationTransfers([halted, absentOutcome], collectionLimits()).error ==
  AccumulationTransferCollectionError.InvalidOutcome # A late invalid source exposes no earlier collection.
let defaultPlan = default(PreparedAccumulationTransfers)
assert defaultPlan.transferCollectionInfo.error == AccumulationTransferCollectionError.Uninitialized
assert defaultPlan.collectedTransferAt(CollectedTransferIndex(0)).error ==
    AccumulationTransferCollectionError.Uninitialized
assert defaultPlan.transferCollectionSourceAt(AccumulationTransferSourceIndex(0)).error ==
    AccumulationTransferCollectionError.Uninitialized
let defaultResult = default(AccumulationTransferCollectionResult[PreparedAccumulationTransfers])
assert defaultResult.error ==
  AccumulationTransferCollectionError.Uninitialized
for index in [5'u64, high(uint64)]:
  assert plan.collectedTransferAt(CollectedTransferIndex(index)).error ==
      AccumulationTransferCollectionError.InvalidIndex
for index in [3'u64, high(uint64)]:
  assert plan.transferCollectionSourceAt(AccumulationTransferSourceIndex(index)).error ==
      AccumulationTransferCollectionError.InvalidIndex
let noSources = prepareAccumulationTransfers([], collectionLimits(0, 0, 0)).value
assert noSources.transferCollectionInfo.value.sources == 0 and
    noSources.transferCollectionInfo.value.transfers == 0
assert noSources.collectedTransferAt(CollectedTransferIndex(0)).error ==
    AccumulationTransferCollectionError.InvalidIndex
var observations = plan.transferCollectionInfo.value
observations.transfers = 0
observations.memoBytes = AccumulationMemoBytes(0)
assert plan.transferCollectionInfo.value.transfers == 5
var copied = plan.collectedTransferAt(CollectedTransferIndex(0)).value
copied.source = ServiceIndex(0)
copied.memo = TransferMemo(default(array[128, byte]))
checkTransfer(plan, 0, high(uint32)) # Extracted byref-marked record still has independent value storage.
var sources = @[halted]
var retained = prepareAccumulationTransfers(sources, collectionLimits()).value
sources[0] = absentOutcome
sources = @[]
checkTransfer(retained, 1, second = true)
let detached = retained.transferCollectionSourceAt(AccumulationTransferSourceIndex(0)).value
retained = defaultPlan
let context = detached.outcomeContext.value
assert context.effectInfo.value.transfers == 2
let entry = context.effectAccounts.value.lookup(chapterServiceKey(StateChapter(255), ServiceIndex(42))).value
assert uint64(decodeServiceMetadata(entry.bytes, ByteLimit(89)).value.metadata.balance) == 95
# Collection does not require a representable sum of outgoing gas; each full-width gas remains exact.
let large = normalizeAccumulationOutcome(transferExecution(second = false,
  offeredGas = 0x8000000000000000'u64, credit = high(uint64))).value
let largePlan = prepareAccumulationTransfers([large, large, large], collectionLimits(
  transfers = 3, memoBytes = 384)).value
for index in 0..<3:
  assert uint64(largePlan.collectedTransferAt(CollectedTransferIndex(uint64(index))).value.gas) ==
    0x8000000000000000'u64 # The mathematical total exceeds uint64; no aggregate gas is computed here.
failHash(1)
let pure = prepareAccumulationTransfers([halted, returned], collectionLimits(transfers = 4,
    memoBytes = 512))
assert pure.error == AccumulationTransferCollectionError.None and hashCalls() == 0
failHash(0)
let before = getOccupiedMem()
for iteration in 0..<1000:
  let selected = transferOutcome(TransferEnding.HashReturn)
  let collected = prepareAccumulationTransfers([selected, panicked], collectionLimits()).value
  checkTransfer(collected, 1, second = true) # Release source effects, copied memos and retained owner arrays every cycle.
let after = getOccupiedMem()
assert before == after
recordArcRelease("accumulation_transfers", 1000, before, after)
echo "Accumulation transfers passed"
echo "ARC_RELEASE cycles=1000 unchanged"
