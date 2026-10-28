# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Apply complete current M/n account selection to a private fork of the explicit complete prior.
## Explicit coverage does not authenticate its frame or grant block publication; bound wrappers retain that authority separately.
## This reusable phase trusts explicit coverage/frame configuration; it cannot construct an authenticated Stage owner.
import std/algorithm
import ../codec/bounded as codec_bounded
import ../codec/composite as codec_composite
import ../codec/state_layout as codec_state_layout
import ../codec/state_trie as codec_state_trie
import ./accumulation_coverage as state_accumulation_coverage
import ./accumulation_annulment as state_accumulation_annulment
import ./accumulation_account_selection as state_accumulation_account_selection
import ./accumulation_creation_union as state_accumulation_creation_union
import ./accumulation_selected_writes as state_accumulation_selected_writes
import ./accumulation_skip as state_accumulation_skip
import ./store as state_store

type
  AccumulationAccountPhaseLimits* = object ## Complete prior inventory and provider traversal are independent of selected proof/write ceilings.
    entries*, providers*: ElementLimit
    selection*: AccumulationAccountSelectionLimits
    creation*: AccumulationCreationLimits
    writes*: SelectedAccountWriteLimits
  AccumulationAccountPhaseInfo* = object ## Complete prior coverage and applied account descriptors do not imply final block completion.
    entries*, priorAccounts*, newAccounts*, writes*: int
  AccumulationAccountPhaseError* {.pure.} = enum ## No refusal exposes an intermediate account root or selected prefix.
    Uninitialized, None, InvalidSource, LimitExceeded, SelectionFailure, CreationFailure,
    WriteFailure, StoreFailure
  AccountPhaseData = ref object # Immutable acyclic ownership retains exact explicit source coverage and all complete account projections.
    coverage: PreparedAccumulationCoverage
    selected: PreparedAccumulationAccountSelection
    created: PreparedAccumulationCreationUnion
    writes: PreparedSelectedAccountWrites
    snapshot: StateStoreSnapshot
    info: AccumulationAccountPhaseInfo
  PreparedAccumulationAccountPhase* = object ## Only full inventory/selection/private application constructs this phase.
    data: nil AccountPhaseData
  AccumulationAccountPhaseResult*[T] = object ## Successful owners and actual failure reasons occupy distinct private alternatives.
    case status: AccumulationAccountPhaseError
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

func error*[T](outcome: AccumulationAccountPhaseResult[T]): AccumulationAccountPhaseError =
  ## Inspect the selected alternative without allowing mutation or retagging.
  outcome.status
func value*[T](outcome: AccumulationAccountPhaseResult[T]): T {.inline,
    requires: outcome.status == AccumulationAccountPhaseError.None.} =
  ## Extract only a complete selected owner under optimized checked contracts.
  outcome.completed
func selectionFailure*[T](outcome: AccumulationAccountPhaseResult[
    T]): AccumulationAccountSelectionError {.inline,

requires: outcome.status == AccumulationAccountPhaseError.SelectionFailure.} =
  ## Inspect the actual complete-prior selection refusal.
  outcome.selectionReason
func creationFailure*[T](outcome: AccumulationAccountPhaseResult[
    T]): AccumulationCreationError {.inline,

requires: outcome.status == AccumulationAccountPhaseError.CreationFailure.} =
  ## Inspect the actual nonannulled new-account union refusal.
  outcome.creationReason
func writeFailure*[T](outcome: AccumulationAccountPhaseResult[
    T]): SelectedAccountWriteError {.inline,

requires: outcome.status == AccumulationAccountPhaseError.WriteFailure.} =
  ## Inspect the actual physical-fact selection refusal.
  outcome.writeReason
func storeFailure*[T](outcome: AccumulationAccountPhaseResult[T]): StateStoreError {.inline,
    requires: outcome.status == AccumulationAccountPhaseError.StoreFailure.} =
  ## Inspect the actual private-fork or atomic apply refusal.
  outcome.storeReason
proc prepareAccumulationAccountPhase*(coverage: PreparedAccumulationCoverage,
    limits: AccumulationAccountPhaseLimits): AccumulationAccountPhaseResult[
        PreparedAccumulationAccountPhase] =
  ## Enumerate every canonical prior C255 account, select M plus n once, then apply only their final physical writes privately.
  template fail(reason: AccumulationAccountPhaseError) =
    return AccumulationAccountPhaseResult[PreparedAccumulationAccountPhase](status: reason)
  if coverage.coverageInfo.error != AccumulationCoverageError.None:
    fail(AccumulationAccountPhaseError.InvalidSource) # Uninitialized coverage cannot authorize complete selected preparation.
  let info = coverage.coverageInfo.value
  let source = coverage.coverageAnnulment.value
  let prior = source.annulmentPrior.value
  let count = prior.commitment.entries
  if uint64(count) > uint64(limits.entries) or uint64(info.services) > uint64(limits.providers) or
      uint64(info.skipped) > uint64(limits.selection.skipped) or
      info.skipped > high(int) div sizeof(SkippedAccumulation):
    fail(AccumulationAccountPhaseError.LimitExceeded) # Bound all complete-map/provider traversals and skip allocation before work.
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
      fail(AccumulationAccountPhaseError.LimitExceeded) # Charge every prior account before retaining its descriptor.
    services.add(service)
  services.sort(proc(left, right: ServiceIndex): int = cmp(uint32(left), uint32(right)))
  var skipped = newSeq[SkippedAccumulation](info.skipped)
  var next = 0
  for ordinal in 0..<info.services:
    let index = AccumulationCoverageIndex(uint64(ordinal))
    if coverage.coverageRowAt(index).value.kind == AccumulationCoverageKind.CodeUnavailable:
      skipped[next] = coverage.coverageSkippedAt(index).value
      inc next # Exact complete coverage proves the counted skip extent.
  let selected = prepareAccumulationAccountSelection(source, services, limits.selection, skipped)
  if selected.error != AccumulationAccountSelectionError.None:
    return AccumulationAccountPhaseResult[PreparedAccumulationAccountPhase](
      status: AccumulationAccountPhaseError.SelectionFailure, selectionReason: selected.error)
  let created = prepareAccumulationCreationUnion(source, limits.creation)
  if created.error != AccumulationCreationError.None:
    return AccumulationAccountPhaseResult[PreparedAccumulationAccountPhase](
      status: AccumulationAccountPhaseError.CreationFailure, creationReason: created.error)
  let prepared = prepareSelectedAccountWrites(selected.value, created.value, limits.writes)
  if prepared.error != SelectedAccountWriteError.None:
    return AccumulationAccountPhaseResult[PreparedAccumulationAccountPhase](
      status: AccumulationAccountPhaseError.WriteFailure, writeReason: prepared.error)
  let writeCount = prepared.value.selectedWritesInfo.value.writes
  if writeCount > high(int) div sizeof(StateWrite):
    fail(AccumulationAccountPhaseError.LimitExceeded) # Prove the copied apply descriptor extent independently of the proof's internal row layout.
  var writes = newSeq[StateWrite](writeCount)
  for ordinal in 0..<writeCount:
    writes[ordinal] = prepared.value.selectedWriteAt(AccumulationSelectedWriteIndex(uint64(
        ordinal))).value # Fresh buffers never expose the proof's backing storage.
  var working = forkStateStore(prior)
  if working.error != StateStoreError.None:
    return AccumulationAccountPhaseResult[PreparedAccumulationAccountPhase](
      status: AccumulationAccountPhaseError.StoreFailure, storeReason: working.error)
  var candidate = working.value
  let applied = candidate.apply(writes)
  if applied.error != StateStoreError.None:
    return AccumulationAccountPhaseResult[PreparedAccumulationAccountPhase](
      status: AccumulationAccountPhaseError.StoreFailure, storeReason: applied.error)
  AccumulationAccountPhaseResult[PreparedAccumulationAccountPhase](
    status: AccumulationAccountPhaseError.None,
    completed: PreparedAccumulationAccountPhase(data: AccountPhaseData(coverage: coverage,
      selected: selected.value, created: created.value, writes: prepared.value,
      snapshot: applied.value,
      info: AccumulationAccountPhaseInfo(entries: count, priorAccounts: services.len,
        newAccounts: created.value.creationUnionInfo.value.accounts, writes: writeCount))))

proc accountPhaseInfo*(stage: PreparedAccumulationAccountPhase): AccumulationAccountPhaseResult[
    AccumulationAccountPhaseInfo] =
  ## Retain the exact info from complete private account preparation; default owners expose no phase.
  let data = stage.data
  if data == nil:
    return AccumulationAccountPhaseResult[AccumulationAccountPhaseInfo](
        status: AccumulationAccountPhaseError.Uninitialized)
  AccumulationAccountPhaseResult[AccumulationAccountPhaseInfo](
      status: AccumulationAccountPhaseError.None, completed: data.info)

proc accountPhaseCoverage*(stage: PreparedAccumulationAccountPhase): AccumulationAccountPhaseResult[
    PreparedAccumulationCoverage] =
  ## Retain the exact coverage from complete private account preparation; default owners expose no phase.
  let data = stage.data
  if data == nil:
    return AccumulationAccountPhaseResult[PreparedAccumulationCoverage](
        status: AccumulationAccountPhaseError.Uninitialized)
  AccumulationAccountPhaseResult[PreparedAccumulationCoverage](
      status: AccumulationAccountPhaseError.None, completed: data.coverage)

proc accountPhaseSelection*(stage: PreparedAccumulationAccountPhase): AccumulationAccountPhaseResult[
    PreparedAccumulationAccountSelection] =
  ## Retain the exact selected from complete private account preparation; default owners expose no phase.
  let data = stage.data
  if data == nil:
    return AccumulationAccountPhaseResult[PreparedAccumulationAccountSelection](
        status: AccumulationAccountPhaseError.Uninitialized)
  AccumulationAccountPhaseResult[PreparedAccumulationAccountSelection](
      status: AccumulationAccountPhaseError.None, completed: data.selected)

proc accountPhaseCreation*(stage: PreparedAccumulationAccountPhase): AccumulationAccountPhaseResult[
    PreparedAccumulationCreationUnion] =
  ## Retain the exact created from complete private account preparation; default owners expose no phase.
  let data = stage.data
  if data == nil:
    return AccumulationAccountPhaseResult[PreparedAccumulationCreationUnion](
        status: AccumulationAccountPhaseError.Uninitialized)
  AccumulationAccountPhaseResult[PreparedAccumulationCreationUnion](
      status: AccumulationAccountPhaseError.None, completed: data.created)

proc accountPhaseWrites*(stage: PreparedAccumulationAccountPhase): AccumulationAccountPhaseResult[
    PreparedSelectedAccountWrites] =
  ## Retain the exact writes from complete private account preparation; default owners expose no phase.
  let data = stage.data
  if data == nil:
    return AccumulationAccountPhaseResult[PreparedSelectedAccountWrites](
        status: AccumulationAccountPhaseError.Uninitialized)
  AccumulationAccountPhaseResult[PreparedSelectedAccountWrites](
      status: AccumulationAccountPhaseError.None, completed: data.writes)

proc accountPhaseSnapshot*(stage: PreparedAccumulationAccountPhase): AccumulationAccountPhaseResult[
    StateStoreSnapshot] =
  ## Retain the exact snapshot from complete private account preparation; default owners expose no phase.
  let data = stage.data
  if data == nil:
    return AccumulationAccountPhaseResult[StateStoreSnapshot](
        status: AccumulationAccountPhaseError.Uninitialized)
  AccumulationAccountPhaseResult[StateStoreSnapshot](status: AccumulationAccountPhaseError.None,
      completed: data.snapshot)
