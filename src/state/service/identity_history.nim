# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Freeze selected creation and ejection membership from a genuine completed current sequence; separate fixed arrays preserve source positions without interpreting an operation log.
import ../accumulation/current/[driver as accumulation_current_driver,
    sequence as accumulation_current_sequence]
import ../accumulation/[coverage as accumulation_coverage, annulment as accumulation_annulment,
    effects as accumulation_effects, outcome as accumulation_outcome]
import ../store
import ../../codec/bounded
import ../../codec/state/layout as state_layout
type
  ServiceIdentityHistoryLimits* = object ## Original coverage and each selected fixed-array extent are independently admitted.
    entries*, outcomes*, creations*, deletions*: ElementLimit
    bytes*: ByteLimit
  ServiceCreationIndex* = distinct uint64 ## Selected creation ordinal cannot substitute a deletion or invocation.
  ServiceDeletionIndex* = distinct uint64 ## Selected ejection ordinal cannot substitute a creation or service identity.
  ServiceCreationRow* = object ## Detached fixed creation observations retain original parallel positions.
    entry*: CurrentSequenceEntryIndex
    outcome*: AccumulationAnnulmentIndex
    fact*: AccumulationCreatedAccount
  ServiceDeletionRow* = object ## Detached fixed ejection observations retain original parallel positions.
    entry*: CurrentSequenceEntryIndex
    outcome*: AccumulationAnnulmentIndex
    fact*: AccumulationDeletedAccount
    local: AccumulationDeletedAccountIndex # Private original invocation position binds a selected fact to its retained atomic map.
  ServiceIdentityHistoryInfo* = object ## Exact selected membership is distinct from final service presence or payload values.
    entries*, outcomes*, creations*, deletions*: int
    bytes*: uint64
  ServiceIdentityHistory* = object ## Only complete bounded capture can bind immutable arrays to original producer authority.
    initialized: bool
    source: CompletedCurrentAccumulationSequence
    creations: seq[ServiceCreationRow]
    deletions: seq[ServiceDeletionRow]
    info: ServiceIdentityHistoryInfo
  ServiceIdentityHistoryError* {.pure.} = enum ## Disabled capture never masquerades as initialized empty membership.
    Uninitialized, None, InvalidSource, LimitExceeded, CreatedAccountsDisabled,
    DeletedAccountsDisabled, InvalidIndex, InvalidRetirement
  ServiceIdentityHistoryResult*[T] = object ## No successful prefix escapes default or refused capture.
    case status: ServiceIdentityHistoryError
    of None: completed: T
    else: discard # Only the selected immutable reason survives refusal.
func error*[T](outcome: ServiceIdentityHistoryResult[T]): ServiceIdentityHistoryError =
  ## Observe only the selected capture or lookup status.
  outcome.status
func value*[T](outcome: ServiceIdentityHistoryResult[T]): T {.inline,
    requires: outcome.status == ServiceIdentityHistoryError.None.} =
  ## Extract only a complete source-bound history or validated detached observation.
  outcome.completed
proc captureServiceIdentityHistory*(source: CompletedCurrentAccumulationSequence,
    limits: ServiceIdentityHistoryLimits): ServiceIdentityHistoryResult[ServiceIdentityHistory] =
  ## Admit the entire selected descriptor ledger before either output array allocation; never rerun a guest or hash a map.
  template fail(reason: ServiceIdentityHistoryError) =
    return ServiceIdentityHistoryResult[ServiceIdentityHistory](status: reason)
  let info = source.completedSequenceInfo
  if info.error != CurrentSequenceDriverError.None: fail(ServiceIdentityHistoryError.InvalidSource)
  if uint64(info.value.entries) > uint64(limits.entries): fail(
      ServiceIdentityHistoryError.LimitExceeded)
  let sequence = source.completedSequenceSource.value
  let outcomeBudget = min(uint64(limits.outcomes), uint64(high(int)))
  let creationBudget = min(uint64(limits.creations), uint64(high(int) div sizeof(
      ServiceCreationRow)))
  let deletionBudget = min(uint64(limits.deletions), uint64(high(int) div sizeof(
      ServiceDeletionRow)))
  var outcomes = outcomeBudget
  var creations = creationBudget
  var deletions = deletionBudget
  for i in 0..<info.value.entries:
    # Count every executed original invocation, including later cancelled membership.
    let selected = sequence.currentSequenceCoverageAt(CurrentSequenceEntryIndex(uint64(
        i))).value.coverageAnnulment.value
    let count = selected.annulmentInfo.value.outcomes
    if uint64(count) > outcomes: fail(ServiceIdentityHistoryError.LimitExceeded)
    outcomes -= uint64(count)
    for j in 0..<count:
      # Cancelled invocations contribute zero; surviving invocations must have both tracing policies enabled.
      let ordinal = AccumulationAnnulmentIndex(uint64(j))
      let created = selected.annulmentSelectedCreatedAccountFactCountAt(ordinal)
      let deleted = selected.annulmentSelectedDeletedAccountFactCountAt(ordinal)
      if created.error == AccumulationAnnulmentError.CreatedAccountsDisabled:
        fail(ServiceIdentityHistoryError.CreatedAccountsDisabled)
      if deleted.error == AccumulationAnnulmentError.DeletedAccountsDisabled:
        fail(ServiceIdentityHistoryError.DeletedAccountsDisabled)
      if created.error != AccumulationAnnulmentError.None or deleted.error !=
          AccumulationAnnulmentError.None:
        fail(ServiceIdentityHistoryError.InvalidSource)
      if uint64(created.value) > creations or uint64(deleted.value) > deletions:
        fail(ServiceIdentityHistoryError.LimitExceeded)
      creations -= uint64(created.value)
      deletions -= uint64(deleted.value)
  let creationCount = creationBudget-creations
  let deletionCount = deletionBudget-deletions
  let byteBudget = min(uint64(limits.bytes), uint64(high(int)))
  if creationCount > byteBudget div uint64(sizeof(ServiceCreationRow)):
    fail(ServiceIdentityHistoryError.LimitExceeded) # Prove the first multiplication before using it.
  let creationBytes = creationCount*uint64(sizeof(ServiceCreationRow))
  if deletionCount > (byteBudget-creationBytes) div uint64(sizeof(ServiceDeletionRow)):
    fail(ServiceIdentityHistoryError.LimitExceeded) # Prove aggregate bytes and narrowing before either allocation.
  var createdRows = newSeq[ServiceCreationRow](int(creationCount))
  var deletedRows = newSeq[ServiceDeletionRow](int(deletionCount))
  var c, d = 0
  for i in 0..<info.value.entries:
    # Preserve original entry and parallel invocation positions without inventing interleaved host ordering.
    let entry = CurrentSequenceEntryIndex(uint64(i))
    let selected = sequence.currentSequenceCoverageAt(entry).value.coverageAnnulment.value
    for j in 0..<selected.annulmentInfo.value.outcomes:
      let ordinal = AccumulationAnnulmentIndex(uint64(j))
      for k in 0..<selected.annulmentSelectedCreatedAccountFactCountAt(ordinal).value:
        createdRows[c] = ServiceCreationRow(entry: entry, outcome: ordinal,
          fact: selected.annulmentSelectedCreatedAccountFactAt(ordinal,
              AccumulationCreatedAccountIndex(uint64(k))).value)
        inc c # Complete preflight bounds every selected creation write.
      for k in 0..<selected.annulmentSelectedDeletedAccountFactCountAt(ordinal).value:
        deletedRows[d] = ServiceDeletionRow(entry: entry, outcome: ordinal,
          local: AccumulationDeletedAccountIndex(uint64(k)),
          fact: selected.annulmentSelectedDeletedAccountFactAt(ordinal,
              AccumulationDeletedAccountIndex(uint64(k))).value)
        inc d # Complete preflight bounds every selected deletion write.
  ServiceIdentityHistoryResult[ServiceIdentityHistory](status: ServiceIdentityHistoryError.None,
    completed: ServiceIdentityHistory(initialized: true, source: source, creations: createdRows,
      deletions: deletedRows, info: ServiceIdentityHistoryInfo(entries: info.value.entries,
        outcomes: int(outcomeBudget-outcomes), creations: c, deletions: d,
        bytes: creationBytes+deletionCount*uint64(sizeof(ServiceDeletionRow)))))
proc serviceIdentityHistoryInfo*(history: ServiceIdentityHistory): ServiceIdentityHistoryResult[
    ServiceIdentityHistoryInfo] =
  ## Inspect exact selected coverage without granting mutable arrays.
  if not history.initialized:
    return ServiceIdentityHistoryResult[ServiceIdentityHistoryInfo](
        status: ServiceIdentityHistoryError.InvalidSource)
  ServiceIdentityHistoryResult[ServiceIdentityHistoryInfo](status: ServiceIdentityHistoryError.None,
      completed: history.info)
proc serviceIdentityHistorySource*(history: ServiceIdentityHistory): ServiceIdentityHistoryResult[
    CompletedCurrentAccumulationSequence] =
  ## Retain the authentic completed producer graph under its original execution bounds.
  if not history.initialized:
    return ServiceIdentityHistoryResult[CompletedCurrentAccumulationSequence](
        status: ServiceIdentityHistoryError.InvalidSource)
  ServiceIdentityHistoryResult[CompletedCurrentAccumulationSequence](
      status: ServiceIdentityHistoryError.None, completed: history.source)
proc serviceIdentityCreationAt*(history: ServiceIdentityHistory,
    index: ServiceCreationIndex): ServiceIdentityHistoryResult[ServiceCreationRow] =
  ## Validate initialization and the complete full-width ordinal before copying one fixed observation.
  if not history.initialized:
    return ServiceIdentityHistoryResult[ServiceCreationRow](
        status: ServiceIdentityHistoryError.InvalidSource)
  if uint64(index) >= uint64(history.creations.len):
    return ServiceIdentityHistoryResult[ServiceCreationRow](
        status: ServiceIdentityHistoryError.InvalidIndex)
  ServiceIdentityHistoryResult[ServiceCreationRow](status: ServiceIdentityHistoryError.None,
    completed: history.creations[int(uint64(index))])
proc serviceIdentityDeletionAt*(history: ServiceIdentityHistory,
    index: ServiceDeletionIndex): ServiceIdentityHistoryResult[ServiceDeletionRow] =
  ## Validate initialization and the complete full-width ordinal before copying one fixed observation.
  if not history.initialized:
    return ServiceIdentityHistoryResult[ServiceDeletionRow](
        status: ServiceIdentityHistoryError.InvalidSource)
  if uint64(index) >= uint64(history.deletions.len):
    return ServiceIdentityHistoryResult[ServiceDeletionRow](
        status: ServiceIdentityHistoryError.InvalidIndex)
  ServiceIdentityHistoryResult[ServiceDeletionRow](status: ServiceIdentityHistoryError.None,
    completed: history.deletions[int(uint64(index))])

proc serviceIdentityRetirementAt*(history: ServiceIdentityHistory,
    creationIndex: ServiceCreationIndex,
    deletionIndex: ServiceDeletionIndex): ServiceIdentityHistoryResult[StateStoreSnapshot] =
  ## Resolve only the authentic atomic post-ejection state before same-invocation recreation.
  ## The consumer must still prove every original namespace key absent in this exact immutable map.
  template fail(reason: ServiceIdentityHistoryError) =
    return ServiceIdentityHistoryResult[StateStoreSnapshot](status: reason)
  let created = history.serviceIdentityCreationAt(creationIndex)
  if created.error != ServiceIdentityHistoryError.None: fail(created.error)
  let deleted = history.serviceIdentityDeletionAt(deletionIndex)
  if deleted.error != ServiceIdentityHistoryError.None: fail(deleted.error)
  let birth = created.value
  let death = deleted.value
  if uint32(birth.fact.service) != uint32(death.fact.service) or
      uint64(birth.entry) != uint64(death.entry) or
      uint64(birth.outcome) != uint64(death.outcome) or
      uint64(death.fact.ordinal) >= uint64(birth.fact.ordinal):
    fail(ServiceIdentityHistoryError.InvalidRetirement) # Parallel positions cannot establish a local barrier.
  let selected = history.source.completedSequenceSource.value.currentSequenceCoverageAt(
    birth.entry).value.coverageAnnulment.value
  if selected.annulmentDecisionAt(birth.outcome).value.annulled:
    fail(ServiceIdentityHistoryError.InvalidRetirement) # Cancelled original history is never selected evidence.
  let context = selected.annulmentOriginalOutcomeAt(birth.outcome).value.outcomeContext.value
  let retired = context.effectDeletedAccountStateAt(death.local)
  if retired.error != AccumulationEffectError.None:
    fail(ServiceIdentityHistoryError.InvalidRetirement) # Only the terminal-selected context may bind the retained original position.
  let accounts = retired.value
  if accounts.lookup(chapterServiceKey(StateChapter(255), birth.fact.service)).error !=
      StateStoreError.MissingKey:
    fail(ServiceIdentityHistoryError.InvalidRetirement) # Ejection must genuinely remove metadata in the retained atomic map.
  ServiceIdentityHistoryResult[StateStoreSnapshot](status: ServiceIdentityHistoryError.None,
    completed: accounts)
