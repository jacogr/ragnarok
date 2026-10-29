# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_annulled_transfers_arc_release"}

## Real annulled producers retain actual gas/provisions while their outgoing transfers disappear from accpar delivery and refund.
import std/[assertions, syncio]
import ../../../src/state/accumulation/[transfers as accumulation_transfers,
    annulment as accumulation_annulment, pending_transfers as accumulation_pending_transfers,
    outcome as accumulation_outcome, effects as accumulation_effects]
import ../../../src/state/store
import ../../../src/codec/bounded
import ../../../src/codec/state/accounts as state_accounts
import ../../../src/codec/c2_records
import ../../support/[accumulation_annulment_context, accumulation_batch_context, arc_evidence]

# Collection/sort/projection and pending-budget accounting do not hash or publish state.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
proc policy(transfers = 2'u64, memo = 256'u64, sources = 2'u64): AccumulationTransferCollectionLimits =
  ## Explicit independent caps count every original producer but only surviving transfer values.
  AccumulationTransferCollectionLimits(sources: ElementLimit(sources), transfers: ElementLimit(
      transfers), memoBytes: ByteLimit(memo))
proc pendingPolicy(): PendingTransferLimits =
  ## Producer usage and fixed-value copies remain independently bounded after projection.
  PendingTransferLimits(sources: ElementLimit(2), transfers: ElementLimit(2), memoBytes: ByteLimit(256))
let source = annulmentFixture()
let first = annulmentOriginal(source, 0)
let second = annulmentOriginal(source, 1)
let conflicts = annulmentPrepared(source, first, second)
let gross = uint64(first.outcomeInfo.value.gasUsed)+uint64(second.outcomeInfo.value.gasUsed)
assert second.outcomeInfo.value.transfers == 1 and second.outcomeInfo.value.provisions == 1, "original canceled producer genuinely emitted a paid transfer and provision"
failHash(1)
let selected = prepareAnnulmentTransfers(conflicts, policy(transfers = 0, memo = 0)).value
assert selected.transferCollectionInfo.value.sources == 2, "canceled producers still consume source capture and gas work"
assert selected.transferCollectionInfo.value.transfers == 0, "N removes canceled outgoing values"
assert uint64(selected.transferCollectionInfo.value.memoBytes) == 0, "no canceled memo is copied or charged"
assert selected.transferCollectionAnnulment.value.annulmentInfo.value.annulled == 1, "collection retains the exact genuine conflict certificate"
let retainedOriginal = selected.transferCollectionSourceAt(AccumulationTransferSourceIndex(1)).value
assert retainedOriginal.outcomeInfo.value.transfers == 1 and
    retainedOriginal.outcomeInfo.value.provisions == 1, "original producer facts remain distinct from selected outgoing counts"
let pending = prepareInitialPendingTransfers(selected, Gas(200000), pendingPolicy()).value.pendingTransferInfo.value
assert uint64(pending.gasUsed) == gross, "annulment does not erase actual gas spent by canceled execution"
assert uint64(pending.outgoingGas) == 0 and uint64(pending.reservedGas) == 0, "canceled paid transfers earn no refund or recipient reservation"
assert uint64(pending.budget) == 200000-gross, "recursive budget subtracts every original execution without refunding canceled transfers"
let raw = prepareAccumulationTransfers([first, second], policy()).value
assert raw.transferCollectionInfo.value.transfers == 1, "ordinary explicit-order collection retains its earlier semantics"
assert raw.transferCollectionAnnulment.error == AccumulationTransferCollectionError.NoAnnulment, "ordinary collection never claims accpar selection proof"
let rawPending = prepareInitialPendingTransfers(raw, Gas(200000), pendingPolicy()).value.pendingTransferInfo.value
assert uint64(rawPending.outgoingGas) == 10 and uint64(rawPending.budget) == 200000-gross+10, "pending accounting consumes the actual projected collection, not hidden raw source append counts"
let sourceRefusal = prepareAnnulmentTransfers(conflicts, policy(transfers = 0, memo = 0, sources = 1))
assert sourceRefusal.error == AccumulationTransferCollectionError.LimitExceeded, "canceled outcomes still consume the independent source limit"
let invalid = prepareAnnulmentTransfers(default(PreparedAccumulationAnnulment), policy())
assert invalid.error == AccumulationTransferCollectionError.InvalidSelection, "default certificate cannot fabricate empty accpar output"
let absent = default(PreparedAccumulationTransfers)
assert absent.transferCollectionAnnulment.error == AccumulationTransferCollectionError.Uninitialized
let emptySource = prepareAccumulationAnnulment(source.inputs, source.state.snapshot.value, [],
    default(AccumulationAnnulmentLimits)).value
let empty = prepareAnnulmentTransfers(emptySource, default(
    AccumulationTransferCollectionLimits)).value
assert empty.transferCollectionInfo.value.sources == 0 and
    empty.transferCollectionInfo.value.transfers == 0
assert empty.transferCollectionAnnulment.error == AccumulationTransferCollectionError.None, "genuine empty accpar selection is distinct from unbound ordinary empty output"
assert hashCalls() == 0, "selection, sorting and pending-budget accounting are hash free"
failHash(0)
# Two real surviving producers arrive reversed; accpar concatenates their outputs in numeric service order.
let surviving = annulmentFixture(supervisor = 99, parentEmit = true)
let a = annulmentOriginal(surviving, 0)
let b = annulmentOriginal(surviving, 1)
assert a.outcomeInfo.value.transfers == 1 and b.outcomeInfo.value.transfers == 1, "both guest programs produce a real record"
let reversed = prepareAccumulationAnnulment(surviving.inputs, surviving.state.snapshot.value, [b,
    a], annulmentPolicy()).value
failHash(1)
let ordered = prepareAnnulmentTransfers(reversed, policy()).value
assert ordered.transferCollectionInfo.value.sources == 2 and
    ordered.transferCollectionInfo.value.transfers == 2
for index, service in [42'u32, 99'u32]:
  let ordinal = CollectedTransferIndex(uint64(index))
  let transfer = ordered.collectedTransferAt(ordinal).value
  let original = ordered.transferCollectionSourceAt(AccumulationTransferSourceIndex(uint64(index))).value
  assert uint32(original.outcomeInfo.value.service) == service and uint32(transfer.source) ==
      service, "numeric service order applies to retained producers and selected records"
  let expected = original.outcomeContext.value.effectTransferAt(AccumulationTransferIndex(0)).value
  assert uint32(transfer.destination) == uint32(expected.destination)
  assert uint64(transfer.amount) == uint64(expected.amount) and uint64(transfer.gas) == uint64(expected.gas)
  assert array[128, byte](transfer.memo) == array[128, byte](expected.memo), "copy every opaque memo byte without normalization or deduplication"
for mode in 0..<3:
  var short = policy()
  case mode
  of 0: short.sources = ElementLimit(1) # Bound producer capture/sort work.
  of 1: short.transfers = ElementLimit(1) # Both actual selected appends count.
  else: short.memoBytes = ByteLimit(255) # Two fixed memos require all256 bytes.
  let refused = prepareAnnulmentTransfers(reversed, short)
  assert refused.error == AccumulationTransferCollectionError.LimitExceeded, "independent selected-source/value/memo ceilings refuse atomically"
let orderedPending = prepareInitialPendingTransfers(ordered, Gas(200000), pendingPolicy()).value.pendingTransferInfo.value
assert uint64(orderedPending.outgoingGas) == 15, "only the actual selected paid gas is refunded"
assert hashCalls() == 0
failHash(0)
var detached = default(PreparedAccumulationTransfers)
block released_callers:
  let temporary = annulmentFixture()
  let source = annulmentPrepared(temporary, annulmentOriginal(temporary, 0), annulmentOriginal(
      temporary, 1))
  detached = prepareAnnulmentTransfers(source, policy()).value
assert detached.transferCollectionAnnulment.value.annulmentInfo.value.annulled == 1, "retained certificate survives caller source release"
assert detached.transferCollectionSourceAt(AccumulationTransferSourceIndex(
    1)).value.outcomeInfo.value.provisions == 1
let before = getOccupiedMem()
for iteration in 0..<1000:
  let projected = prepareAnnulmentTransfers(conflicts, policy()).value
  let pending = prepareInitialPendingTransfers(projected, Gas(200000), pendingPolicy()).value
  assert pending.pendingTransferInfo.value.transfers == 0
  let ordered = prepareAnnulmentTransfers(reversed, policy()).value
  assert ordered.transferCollectionInfo.value.transfers == 2
let after = getOccupiedMem()
assert before == after, "canonical rows, original sources, certificates and selected memo copies release across 1000 cycles"
recordArcRelease("pvm_annulled_transfers", 1000, before, after)
echo "PVM annulled transfers passed"
echo "ARC_RELEASE cycles=1000 unchanged"
