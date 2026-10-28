# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Execute one authenticated current initial round once, preparing selected state, outputs and next-transfer accounting together.
## This complete parallel-round owner remains distinct from whole-block history/statistics/publication and recursive continuation.
import ../chain/parameters as chain_parameters
import ./accumulation_round as state_accumulation_round
import ./accumulation_block_guests as state_accumulation_block_guests
import ./accumulation_guest_runner as state_accumulation_guest_runner
import ./accumulation_account_stage as state_accumulation_account_stage
import ./accumulation_provision_stage as state_accumulation_provision_stage
import ./accumulation_provisions as state_accumulation_provisions
import ./accumulation_global_stage as state_accumulation_global_stage
import ./accumulation_coverage as state_accumulation_coverage
import ./accumulation_annulment as state_accumulation_annulment
import ./accumulation_annulled_outputs as state_accumulation_annulled_outputs
import ./accumulation_transfers as state_accumulation_transfers
import ./accumulation_pending_transfers as state_accumulation_pending_transfers
import ./store as state_store

type
  CurrentAccumulationRoundLimits* = object ## Each genuine execution and subsequent phase owns its independent explicit resource policy.
    guests*: AccumulationGuestLimits
    accounts*: AccumulationAccountStageLimits
    provisions*: AccumulationProvisionUnionLimits
    globals*: AccumulationGlobalStageLimits
    outputs*: AnnulmentOutputLimits
    transfers*: AccumulationTransferCollectionLimits
    pending*: PendingTransferLimits
  CurrentAccumulationRoundError* {.pure.} = enum ## Refusal never exposes an earlier successful guest/state/output prefix.
    Uninitialized, None, GuestFailure, AccountFailure, ProvisionFailure, GlobalFailure,
    OutputFailure, TransferFailure, PendingFailure
  CurrentRoundData = ref object # Immutable acyclic phase owners retain their exact admitted round and all original providers.
    parameters: Parameters # Retain the exact immutable chain configuration for authenticated later entries.
    globals: PreparedAccumulationGlobalStage
    outputs: PreparedAnnulmentOutputs
    transfers: PreparedAccumulationTransfers
    pending: PreparedPendingTransfers
  PreparedCurrentAccumulationRound* = object ## Only complete current phase orchestration constructs this round owner.
    data: nil CurrentRoundData
  CurrentAccumulationRoundResult*[T] = object ## Only success contains a complete owner; each parent alternative retains an actual failed result.
    case status: CurrentAccumulationRoundError
    of None:
      completed: T
    of GuestFailure:
      guestReason: BlockGuestResult[BlockAccumulationGuests]
    of AccountFailure:
      accountReason: AccumulationAccountStageResult[PreparedAccumulationAccountStage]
    of ProvisionFailure:
      provisionReason: AccumulationProvisionStageResult[PreparedAccumulationProvisionStage]
    of GlobalFailure:
      globalReason: AccumulationGlobalStageResult[PreparedAccumulationGlobalStage]
    of OutputFailure:
      outputReason: AnnulmentOutputsError
    of TransferFailure:
      transferReason: AccumulationTransferCollectionError
    of PendingFailure:
      pendingReason: PendingTransferError
    else:
      discard # Default results cannot masquerade as empty completed rounds.

func error*[T](outcome: CurrentAccumulationRoundResult[T]): CurrentAccumulationRoundError =
  ## Inspect the selected alternative without granting mutation.
  outcome.status
func value*[T](outcome: CurrentAccumulationRoundResult[T]): T {.inline,
    requires: outcome.status == CurrentAccumulationRoundError.None.} =
  ## Extract complete round/phase ownership only after selected success.
  outcome.completed
proc runCurrentBlockAccumulationRound*(round: BlockAccumulationRound, parameters: Parameters,
    limits: CurrentAccumulationRoundLimits): CurrentAccumulationRoundResult[
        PreparedCurrentAccumulationRound] =
  ## Execute each ready guest once, prepare all selected state privately, then bind output/transfer decisions to that exact annulment owner.
  let guests = runBlockAccumulationGuests(round, parameters, limits.guests)
  if guests.error != BlockGuestError.None:
    return CurrentAccumulationRoundResult[PreparedCurrentAccumulationRound](
      status: CurrentAccumulationRoundError.GuestFailure, guestReason: guests)
  let accounts = prepareAccumulationAccountStage(guests.value, limits.accounts)
  if accounts.error != AccumulationAccountStageError.None:
    return CurrentAccumulationRoundResult[PreparedCurrentAccumulationRound](
      status: CurrentAccumulationRoundError.AccountFailure, accountReason: accounts)
  let provisions = prepareAccumulationProvisionStage(accounts.value, limits.provisions)
  if provisions.error != AccumulationProvisionStageError.None:
    return CurrentAccumulationRoundResult[PreparedCurrentAccumulationRound](
      status: CurrentAccumulationRoundError.ProvisionFailure, provisionReason: provisions)
  let globals = prepareAccumulationGlobalStage(provisions.value, limits.globals)
  if globals.error != AccumulationGlobalStageError.None:
    return CurrentAccumulationRoundResult[PreparedCurrentAccumulationRound](
      status: CurrentAccumulationRoundError.GlobalFailure, globalReason: globals)
  let annulment = guests.value.guestCoverage.value.coverageAnnulment.value
  let outputs = prepareAnnulmentOutputs(annulment, limits.outputs)
  if outputs.error != AnnulmentOutputsError.None:
    return CurrentAccumulationRoundResult[PreparedCurrentAccumulationRound](
      status: CurrentAccumulationRoundError.OutputFailure, outputReason: outputs.error)
  let transfers = prepareAnnulmentTransfers(annulment, limits.transfers)
  if transfers.error != AccumulationTransferCollectionError.None:
    return CurrentAccumulationRoundResult[PreparedCurrentAccumulationRound](
      status: CurrentAccumulationRoundError.TransferFailure, transferReason: transfers.error)
  let pending = prepareInitialPendingTransfers(transfers.value,
      round.roundProjection.value.roundInfo.value.budget, limits.pending)
  if pending.error != PendingTransferError.None:
    return CurrentAccumulationRoundResult[PreparedCurrentAccumulationRound](
      status: CurrentAccumulationRoundError.PendingFailure, pendingReason: pending.error)
  CurrentAccumulationRoundResult[PreparedCurrentAccumulationRound](
    status: CurrentAccumulationRoundError.None,
    completed: PreparedCurrentAccumulationRound(data: CurrentRoundData(parameters: parameters,
      globals: globals.value,
      outputs: outputs.value, transfers: transfers.value, pending: pending.value)))

func guestFailure*[T](outcome: CurrentAccumulationRoundResult[T]): BlockGuestResult[
    BlockAccumulationGuests] {.inline, requires: outcome.status ==
    CurrentAccumulationRoundError.GuestFailure.} =
  ## Inspect only the actual failed guestReason parent; successful earlier phases never escape refusal.
  outcome.guestReason

func accountFailure*[T](outcome: CurrentAccumulationRoundResult[T]): AccumulationAccountStageResult[
    PreparedAccumulationAccountStage] {.inline, requires: outcome.status ==
    CurrentAccumulationRoundError.AccountFailure.} =
  ## Inspect only the actual failed accountReason parent; successful earlier phases never escape refusal.
  outcome.accountReason

func provisionFailure*[T](outcome: CurrentAccumulationRoundResult[
    T]): AccumulationProvisionStageResult[PreparedAccumulationProvisionStage] {.inline,
    requires: outcome.status == CurrentAccumulationRoundError.ProvisionFailure.} =
  ## Inspect only the actual failed provisionReason parent; successful earlier phases never escape refusal.
  outcome.provisionReason

func globalFailure*[T](outcome: CurrentAccumulationRoundResult[T]): AccumulationGlobalStageResult[
    PreparedAccumulationGlobalStage] {.inline, requires: outcome.status ==
    CurrentAccumulationRoundError.GlobalFailure.} =
  ## Inspect only the actual failed globalReason parent; successful earlier phases never escape refusal.
  outcome.globalReason

func outputFailure*[T](outcome: CurrentAccumulationRoundResult[T]): AnnulmentOutputsError {.inline,
    requires: outcome.status == CurrentAccumulationRoundError.OutputFailure.} =
  ## Inspect only the actual failed outputReason parent; successful earlier phases never escape refusal.
  outcome.outputReason

func transferFailure*[T](outcome: CurrentAccumulationRoundResult[
    T]): AccumulationTransferCollectionError {.inline, requires: outcome.status ==
    CurrentAccumulationRoundError.TransferFailure.} =
  ## Inspect only the actual failed transferReason parent; successful earlier phases never escape refusal.
  outcome.transferReason

func pendingFailure*[T](outcome: CurrentAccumulationRoundResult[T]): PendingTransferError {.inline,
    requires: outcome.status == CurrentAccumulationRoundError.PendingFailure.} =
  ## Inspect only the actual failed pendingReason parent; successful earlier phases never escape refusal.
  outcome.pendingReason

proc currentRoundGlobals*(round: PreparedCurrentAccumulationRound): CurrentAccumulationRoundResult[
    PreparedAccumulationGlobalStage] =
  ## Retain the complete globals owner; default round handles grant no projection.
  let data = round.data
  if data == nil:
    return CurrentAccumulationRoundResult[PreparedAccumulationGlobalStage](
        status: CurrentAccumulationRoundError.Uninitialized)
  CurrentAccumulationRoundResult[PreparedAccumulationGlobalStage](
      status: CurrentAccumulationRoundError.None, completed: data.globals)

proc currentRoundOutputs*(round: PreparedCurrentAccumulationRound): CurrentAccumulationRoundResult[
    PreparedAnnulmentOutputs] =
  ## Retain the complete outputs owner; default round handles grant no projection.
  let data = round.data
  if data == nil:
    return CurrentAccumulationRoundResult[PreparedAnnulmentOutputs](
        status: CurrentAccumulationRoundError.Uninitialized)
  CurrentAccumulationRoundResult[PreparedAnnulmentOutputs](
      status: CurrentAccumulationRoundError.None, completed: data.outputs)

proc currentRoundTransfers*(round: PreparedCurrentAccumulationRound): CurrentAccumulationRoundResult[
    PreparedAccumulationTransfers] =
  ## Retain the complete transfers owner; default round handles grant no projection.
  let data = round.data
  if data == nil:
    return CurrentAccumulationRoundResult[PreparedAccumulationTransfers](
        status: CurrentAccumulationRoundError.Uninitialized)
  CurrentAccumulationRoundResult[PreparedAccumulationTransfers](
      status: CurrentAccumulationRoundError.None, completed: data.transfers)

proc currentRoundPending*(round: PreparedCurrentAccumulationRound): CurrentAccumulationRoundResult[
    PreparedPendingTransfers] =
  ## Retain the complete pending owner; default round handles grant no projection.
  let data = round.data
  if data == nil:
    return CurrentAccumulationRoundResult[PreparedPendingTransfers](
        status: CurrentAccumulationRoundError.Uninitialized)
  CurrentAccumulationRoundResult[PreparedPendingTransfers](
      status: CurrentAccumulationRoundError.None, completed: data.pending)

proc currentRoundGuests*(round: PreparedCurrentAccumulationRound): CurrentAccumulationRoundResult[
    BlockAccumulationGuests] =
  ## Retain exact admitted guest/provider authority through the complete immutable phase chain.
  let data = round.data
  if data == nil:
    return CurrentAccumulationRoundResult[BlockAccumulationGuests](
        status: CurrentAccumulationRoundError.Uninitialized)
  let guests = data.globals.globalStageProvisions.value.provisionStageAccounts.value.accountStageGuests.value
  CurrentAccumulationRoundResult[BlockAccumulationGuests](
      status: CurrentAccumulationRoundError.None, completed: guests)
proc currentRoundSnapshot*(round: PreparedCurrentAccumulationRound): CurrentAccumulationRoundResult[
    StateStoreSnapshot] =
  ## Retain the complete selected private round map without claiming final whole-block publication.
  let data = round.data
  if data == nil:
    return CurrentAccumulationRoundResult[StateStoreSnapshot](
        status: CurrentAccumulationRoundError.Uninitialized)
  CurrentAccumulationRoundResult[StateStoreSnapshot](status: CurrentAccumulationRoundError.None,
      completed: data.globals.globalStageSnapshot.value)

proc currentRoundParameters*(round: PreparedCurrentAccumulationRound): CurrentAccumulationRoundResult[Parameters] =
  ## Retain the actual initial immutable chain configuration; later execution cannot substitute different prices or eligibility fields.
  let data = round.data
  if data == nil:
    return CurrentAccumulationRoundResult[Parameters](
        status: CurrentAccumulationRoundError.Uninitialized)
  CurrentAccumulationRoundResult[Parameters](status: CurrentAccumulationRoundError.None,
      completed: data.parameters)
