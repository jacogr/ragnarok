# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Apply current GP last-accumulation timestamps only to final-present statistics keys on a private selected-state fork.
## Reuses the existing pure account projector/configuration while retaining genuine current terminal provenance.
import ../codec/[bounded, composite, header, state_accounts, state_statistics]
import ./[accumulation_current_statistics, accumulation_current_driver,
  accumulation_current_sequence,
  accumulation_current_round, accumulation_block_guests, accumulation_round, accumulation_queue,
  report_admission, block_transition, block_admission, accumulation_accounts, store]

type
  CurrentAccumulationAccountError* {.pure.} = enum ## Refusals retain no updated metadata prefix or candidate root.
    Uninitialized, None, InvalidSource, LimitExceeded, ProjectionFailure, StateFailure
  CurrentAccountData = ref object # Immutable statistics, copied observations and complete private successor form an acyclic proof graph.
    source: PreparedCurrentAccumulationStatistics
    state: StateStoreSnapshot
    info: AccumulationAccountInfo
  PreparedCurrentAccumulationAccounts* = object ## Only genuine current statistics and admitted time authorize this timestamp successor.
    data: nil CurrentAccountData
  CurrentAccumulationAccountResult*[T] = object ## Private alternatives preserve actual failed parents without exposing successful projections.
    case status: CurrentAccumulationAccountError
    of None:
      completed: T
    of ProjectionFailure:
      projectionReason: AccumulationAccountResult[AccumulationAccountProjection]
    of StateFailure:
      stateReason: StateStoreError
    else:
      discard # Default/source/count refusals carry no fabricated initialized state.

func error*[T](outcome: CurrentAccumulationAccountResult[T]): CurrentAccumulationAccountError =
  ## Inspect only the selected reason without permitting mutation.
  outcome.status
func value*[T](outcome: CurrentAccumulationAccountResult[T]): T {.inline,
    requires: outcome.status == CurrentAccumulationAccountError.None.} =
  ## Extract complete selected successor ownership only after success.
  outcome.completed
func projectionFailure*[T](outcome: CurrentAccumulationAccountResult[T]): AccumulationAccountResult[
    AccumulationAccountProjection] {.inline,

requires: outcome.status == CurrentAccumulationAccountError.ProjectionFailure.} =
  ## Retain only the actual failed pure projector and its strict metadata/policy reason.
  outcome.projectionReason
func stateFailure*[T](outcome: CurrentAccumulationAccountResult[T]): StateStoreError {.inline,
    requires: outcome.status == CurrentAccumulationAccountError.StateFailure.} =
  ## Inspect only the actual private-fork/Merkle refusal.
  outcome.stateReason
proc prepareCurrentAccumulationAccounts*(statistics: PreparedCurrentAccumulationStatistics,
    config: AccumulationAccountConfig): CurrentAccumulationAccountResult[
        PreparedCurrentAccumulationAccounts] =
  ## Derive keys, final selected state and slot from one genuine current source; missing/ejected statistics services never reappear.
  let source = statistics.currentStatisticsSource
  if source.error != CurrentAccumulationStatisticsError.None:
    return CurrentAccumulationAccountResult[PreparedCurrentAccumulationAccounts](
        status: CurrentAccumulationAccountError.InvalidSource)
  let count = statistics.currentStatisticsInfo.value.services
  if uint64(count) > uint64(config.services) or count > high(int) div sizeof(ServiceIndex):
    return CurrentAccumulationAccountResult[PreparedCurrentAccumulationAccounts](
        status: CurrentAccumulationAccountError.LimitExceeded) # Bound complete sorted ID capture before allocation or metadata reads.
  var services = newSeq[ServiceIndex](count)
  for ordinal in 0..<count:
    services[ordinal] = statistics.currentStatisticsAt(StatisticsServiceIndex(uint64(
        ordinal))).value.service # Fixed copies preserve the genuine numeric dictionary order.
  let sequence = source.value.completedSequenceSource.value
  let anchor = sequence.currentSequenceInitial.value.currentRoundGuests.value.guestRound.value.roundBlockQueue.value.accumulationAdmission.value.reportBlockStage.value.value
  let slot = AccountSlot(uint32(headerInfo(anchor.admitted.admittedHeader).value.unsigned.slot))
  let prior = source.value.completedSequenceState.value
  let projected = projectAccumulationAccounts(prior, services, slot, config)
  if projected.error != AccumulationAccountError.None:
    return CurrentAccumulationAccountResult[PreparedCurrentAccumulationAccounts](
      status: CurrentAccumulationAccountError.ProjectionFailure,
      projectionReason: projected) # Missing accounts are normal; real metadata/local-cap refusal is never replaced with an empty write set.
  let forked = forkStateStore(prior)
  if forked.error != StateStoreError.None:
    return CurrentAccumulationAccountResult[PreparedCurrentAccumulationAccounts](
        status: CurrentAccumulationAccountError.StateFailure, stateReason: forked.error)
  var working = forked.value
  let applied = working.apply(projected.value.writes)
  if applied.error != StateStoreError.None:
    return CurrentAccumulationAccountResult[PreparedCurrentAccumulationAccounts](
      status: CurrentAccumulationAccountError.StateFailure,
      stateReason: applied.error) # Late hashing/write-policy refusal publishes no timestamp prefix.
  CurrentAccumulationAccountResult[PreparedCurrentAccumulationAccounts](
    status: CurrentAccumulationAccountError.None,
    completed: PreparedCurrentAccumulationAccounts(data: CurrentAccountData(source: statistics,
        state: applied.value, info: projected.value.info)))

proc currentAccountsInfo*(accounts: PreparedCurrentAccumulationAccounts): CurrentAccumulationAccountResult[
    AccumulationAccountInfo] =
  ## Retain the exact source-bound info projection; default accounts grant no initialized successor.
  let data = accounts.data
  if data == nil:
    return CurrentAccumulationAccountResult[AccumulationAccountInfo](
        status: CurrentAccumulationAccountError.Uninitialized)
  CurrentAccumulationAccountResult[AccumulationAccountInfo](
      status: CurrentAccumulationAccountError.None, completed: data.info)

proc currentAccountsSource*(accounts: PreparedCurrentAccumulationAccounts): CurrentAccumulationAccountResult[
    PreparedCurrentAccumulationStatistics] =
  ## Retain the exact source-bound source projection; default accounts grant no initialized successor.
  let data = accounts.data
  if data == nil:
    return CurrentAccumulationAccountResult[PreparedCurrentAccumulationStatistics](
        status: CurrentAccumulationAccountError.Uninitialized)
  CurrentAccumulationAccountResult[PreparedCurrentAccumulationStatistics](
      status: CurrentAccumulationAccountError.None, completed: data.source)

proc currentAccountsState*(accounts: PreparedCurrentAccumulationAccounts): CurrentAccumulationAccountResult[
    StateStoreSnapshot] =
  ## Retain the exact source-bound state projection; default accounts grant no initialized successor.
  let data = accounts.data
  if data == nil:
    return CurrentAccumulationAccountResult[StateStoreSnapshot](
        status: CurrentAccumulationAccountError.Uninitialized)
  CurrentAccumulationAccountResult[StateStoreSnapshot](status: CurrentAccumulationAccountError.None,
      completed: data.state)
