# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Apply complete current M/n account selection to a private fork of the authenticated initial-round prior.
## This account phase retains its source and never claims final global chapters, provisions or block publication.
import std/algorithm
import ../codec/[bounded, composite, state_layout, state_trie]
import ./[accumulation_block_guests, accumulation_coverage, accumulation_annulment,
  accumulation_account_selection, accumulation_creation_union, accumulation_selected_writes,
  accumulation_skip, store]

type
  AccumulationAccountStageLimits* = object ## Complete prior inventory and provider traversal are independent of selected proof/write ceilings.
    entries*, providers*: ElementLimit
    selection*: AccumulationAccountSelectionLimits
    creation*: AccumulationCreationLimits
    writes*: SelectedAccountWriteLimits
  AccumulationAccountStageInfo* = object ## Complete prior coverage and applied account descriptors do not imply final block completion.
    entries*, priorAccounts*, newAccounts*, writes*: int
  AccumulationAccountStageError* {.pure.} = enum ## No refusal exposes an intermediate account root or selected prefix.
    Uninitialized, None, InvalidSource, LimitExceeded, SelectionFailure, CreationFailure,
    WriteFailure, StoreFailure
  AccountStageData = ref object # Immutable acyclic ownership retains exact authenticated execution and all complete account projections.
    guests: BlockAccumulationGuests
    selected: PreparedAccumulationAccountSelection
    created: PreparedAccumulationCreationUnion
    writes: PreparedSelectedAccountWrites
    snapshot: StateStoreSnapshot
    info: AccumulationAccountStageInfo
  PreparedAccumulationAccountStage* = object ## Only full inventory/selection/private application constructs this phase.
    data: nil AccountStageData
  AccumulationAccountStageResult*[T] = object ## Successful owners and actual failure reasons occupy distinct private alternatives.
    case status: AccumulationAccountStageError
    of None:
      completed: T
    of SelectionFailure:
      selectionReason: AccumulationAccountSelectionError
    of CreationFailure:
      creationReason: AccumulationCreationError
    of WriteFailure:
      writeReason: SelectedAccountWriteError
    of StoreFailure:
      storeReason: StateStoreError
    else:
      discard # Default/source/count refusals carry no intermediate map.

func error*[T](outcome: AccumulationAccountStageResult[T]): AccumulationAccountStageError =
  ## Inspect the selected alternative without allowing mutation or retagging.
  outcome.status
func value*[T](outcome: AccumulationAccountStageResult[T]): T {.inline,
    requires: outcome.status == AccumulationAccountStageError.None.} =
  ## Extract only a complete selected owner under optimized checked contracts.
  outcome.completed
func selectionFailure*[T](outcome: AccumulationAccountStageResult[
    T]): AccumulationAccountSelectionError {.inline,

requires: outcome.status == AccumulationAccountStageError.SelectionFailure.} =
  ## Inspect the actual complete-prior selection refusal.
  outcome.selectionReason
func creationFailure*[T](outcome: AccumulationAccountStageResult[
    T]): AccumulationCreationError {.inline,

requires: outcome.status == AccumulationAccountStageError.CreationFailure.} =
  ## Inspect the actual nonannulled new-account union refusal.
  outcome.creationReason
func writeFailure*[T](outcome: AccumulationAccountStageResult[
    T]): SelectedAccountWriteError {.inline,

requires: outcome.status == AccumulationAccountStageError.WriteFailure.} =
  ## Inspect the actual physical-fact selection refusal.
  outcome.writeReason
func storeFailure*[T](outcome: AccumulationAccountStageResult[T]): StateStoreError {.inline,
    requires: outcome.status == AccumulationAccountStageError.StoreFailure.} =
  ## Inspect the actual private-fork or atomic apply refusal.
  outcome.storeReason
proc prepareAccumulationAccountStage*(guests: BlockAccumulationGuests,
    limits: AccumulationAccountStageLimits): AccumulationAccountStageResult[
        PreparedAccumulationAccountStage] =
  ## Enumerate every canonical prior C255 account, select M plus n once, then apply only their final physical writes privately.
  template fail(reason: AccumulationAccountStageError) =
    return AccumulationAccountStageResult[PreparedAccumulationAccountStage](status: reason)
  let coverage = guests.guestCoverage
  if coverage.error != BlockGuestError.None:
    fail(AccumulationAccountStageError.InvalidSource) # Pure coverage and default block handles cannot authorize this phase.
  let info = coverage.value.coverageInfo.value
  let source = coverage.value.coverageAnnulment.value
  let prior = source.annulmentPrior.value
  let count = prior.commitment.entries
  if uint64(count) > uint64(limits.entries) or uint64(info.services) > uint64(limits.providers) or
      uint64(info.skipped) > uint64(limits.selection.skipped) or
      info.skipped > high(int) div sizeof(SkippedAccumulation):
    fail(AccumulationAccountStageError.LimitExceeded) # Bound all complete-map/provider traversals and skip allocation before work.
  var services: seq[ServiceIndex] = @[]
  for ordinal in 0..<count:
    let key = prior.keyAt(StateEntryIndex(ordinal)).value
    let raw = array[31, byte](key)
    if raw[0] != 255: continue # Other state chapters and service subkeys do not grant metadata membership.
    var number = 0'u32
    for octet in 0..<4:
      number = number or (uint32(raw[1+2*octet]) shl (
          8*octet)) # Fixed E4 reconstruction cannot overflow its nominal domain.
    let service = ServiceIndex(number)
    let canonical = chapterServiceKey(StateChapter(255), service)
    if array[31, byte](canonical) != raw: continue # A hashed service key beginning with255 is not C255 metadata.
    if uint64(services.len) >= uint64(limits.selection.accounts) or services.len >= high(
        int) div sizeof(ServiceIndex):
      fail(AccumulationAccountStageError.LimitExceeded) # Charge every prior account before retaining its descriptor.
    services.add(service)
  services.sort(proc(left, right: ServiceIndex): int = cmp(uint32(left), uint32(right)))
  var skipped = newSeq[SkippedAccumulation](info.skipped)
  var next = 0
  for ordinal in 0..<info.services:
    let index = AccumulationCoverageIndex(uint64(ordinal))
    if coverage.value.coverageRowAt(index).value.kind == AccumulationCoverageKind.CodeUnavailable:
      skipped[next] = coverage.value.coverageSkippedAt(index).value
      inc next # Exact complete coverage proves the counted skip extent.
  let selected = prepareAccumulationAccountSelection(source, services, limits.selection, skipped)
  if selected.error != AccumulationAccountSelectionError.None:
    return AccumulationAccountStageResult[PreparedAccumulationAccountStage](
      status: AccumulationAccountStageError.SelectionFailure, selectionReason: selected.error)
  let created = prepareAccumulationCreationUnion(source, limits.creation)
  if created.error != AccumulationCreationError.None:
    return AccumulationAccountStageResult[PreparedAccumulationAccountStage](
      status: AccumulationAccountStageError.CreationFailure, creationReason: created.error)
  let prepared = prepareSelectedAccountWrites(selected.value, created.value, limits.writes)
  if prepared.error != SelectedAccountWriteError.None:
    return AccumulationAccountStageResult[PreparedAccumulationAccountStage](
      status: AccumulationAccountStageError.WriteFailure, writeReason: prepared.error)
  let writeCount = prepared.value.selectedWritesInfo.value.writes
  if writeCount > high(int) div sizeof(StateWrite):
    fail(AccumulationAccountStageError.LimitExceeded) # Prove the copied apply descriptor extent independently of the proof's internal row layout.
  var writes = newSeq[StateWrite](writeCount)
  for ordinal in 0..<writeCount:
    writes[ordinal] = prepared.value.selectedWriteAt(AccumulationSelectedWriteIndex(uint64(
        ordinal))).value # Fresh buffers never expose the proof's backing storage.
  var working = forkStateStore(prior)
  if working.error != StateStoreError.None:
    return AccumulationAccountStageResult[PreparedAccumulationAccountStage](
      status: AccumulationAccountStageError.StoreFailure, storeReason: working.error)
  var candidate = working.value
  let applied = candidate.apply(writes)
  if applied.error != StateStoreError.None:
    return AccumulationAccountStageResult[PreparedAccumulationAccountStage](
      status: AccumulationAccountStageError.StoreFailure, storeReason: applied.error)
  AccumulationAccountStageResult[PreparedAccumulationAccountStage](
    status: AccumulationAccountStageError.None,
    completed: PreparedAccumulationAccountStage(data: AccountStageData(guests: guests,
      selected: selected.value, created: created.value, writes: prepared.value,
      snapshot: applied.value,
      info: AccumulationAccountStageInfo(entries: count, priorAccounts: services.len,
        newAccounts: created.value.creationUnionInfo.value.accounts, writes: writeCount))))

proc accountStageInfo*(stage: PreparedAccumulationAccountStage): AccumulationAccountStageResult[
    AccumulationAccountStageInfo] =
  ## Retain the exact info from complete private account preparation; default owners expose no phase.
  let data = stage.data
  if data == nil:
    return AccumulationAccountStageResult[AccumulationAccountStageInfo](
        status: AccumulationAccountStageError.Uninitialized)
  AccumulationAccountStageResult[AccumulationAccountStageInfo](
      status: AccumulationAccountStageError.None, completed: data.info)

proc accountStageGuests*(stage: PreparedAccumulationAccountStage): AccumulationAccountStageResult[
    BlockAccumulationGuests] =
  ## Retain the exact guests from complete private account preparation; default owners expose no phase.
  let data = stage.data
  if data == nil:
    return AccumulationAccountStageResult[BlockAccumulationGuests](
        status: AccumulationAccountStageError.Uninitialized)
  AccumulationAccountStageResult[BlockAccumulationGuests](
      status: AccumulationAccountStageError.None, completed: data.guests)

proc accountStageSelection*(stage: PreparedAccumulationAccountStage): AccumulationAccountStageResult[
    PreparedAccumulationAccountSelection] =
  ## Retain the exact selected from complete private account preparation; default owners expose no phase.
  let data = stage.data
  if data == nil:
    return AccumulationAccountStageResult[PreparedAccumulationAccountSelection](
        status: AccumulationAccountStageError.Uninitialized)
  AccumulationAccountStageResult[PreparedAccumulationAccountSelection](
      status: AccumulationAccountStageError.None, completed: data.selected)

proc accountStageCreation*(stage: PreparedAccumulationAccountStage): AccumulationAccountStageResult[
    PreparedAccumulationCreationUnion] =
  ## Retain the exact created from complete private account preparation; default owners expose no phase.
  let data = stage.data
  if data == nil:
    return AccumulationAccountStageResult[PreparedAccumulationCreationUnion](
        status: AccumulationAccountStageError.Uninitialized)
  AccumulationAccountStageResult[PreparedAccumulationCreationUnion](
      status: AccumulationAccountStageError.None, completed: data.created)

proc accountStageWrites*(stage: PreparedAccumulationAccountStage): AccumulationAccountStageResult[
    PreparedSelectedAccountWrites] =
  ## Retain the exact writes from complete private account preparation; default owners expose no phase.
  let data = stage.data
  if data == nil:
    return AccumulationAccountStageResult[PreparedSelectedAccountWrites](
        status: AccumulationAccountStageError.Uninitialized)
  AccumulationAccountStageResult[PreparedSelectedAccountWrites](
      status: AccumulationAccountStageError.None, completed: data.writes)

proc accountStageSnapshot*(stage: PreparedAccumulationAccountStage): AccumulationAccountStageResult[
    StateStoreSnapshot] =
  ## Retain the exact snapshot from complete private account preparation; default owners expose no phase.
  let data = stage.data
  if data == nil:
    return AccumulationAccountStageResult[StateStoreSnapshot](
        status: AccumulationAccountStageError.Uninitialized)
  AccumulationAccountStageResult[StateStoreSnapshot](status: AccumulationAccountStageError.None,
      completed: data.snapshot)
