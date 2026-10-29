# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bind initial accumulation planning to the original computed report gas parameters and exact admitted parent.

import ../../chain/parameters
import ./[publication as computed_publication, admission as computed_admission,
    inclusion as computed_inclusion, batch as computed_batch, envelope as computed_envelope,
    credentials as computed_credentials, guarantors as computed_guarantors,
    roster as computed_roster, transition as computed_transition, profile as computed_profile]
import ../accumulation/[queue as accumulation_queue, round as accumulation_round]

type
  ComputedRoundConfig* = object ## Independent queue/round ceilings retain semantic gas fields that must match original execution.
    queue*: AccumulationQueueConfig
    round*: AccumulationRoundConfig
  ComputedRoundError* {.pure.} = enum ## Only selected child alternatives carry their precise failure cause.
    Uninitialized, None, InvalidSource, ProfileMismatch, QueueFailure, RoundFailure
  ComputedRoundData = ref object ## Immutable acyclic storage retains both computed publication and genuine initial round provenance.
    source: ComputedReportSuccessor
    round: BlockAccumulationRound
    parameters: Parameters
  ComputedAccumulationRound* = object ## Initial planning is not service execution or final block publication.
    data: nil ComputedRoundData
  ComputedRoundResult*[T] = object ## Private alternatives prevent default/refused rounds exposing partial plans.
    case status: ComputedRoundError
    of None:
      completed: T
    of QueueFailure:
      queueReason: AccumulationQueueError
    of RoundFailure:
      roundReason: AccumulationRoundError
    else:
      discard # Defaults and ordinary refusals expose reasons alone.

func error*[T](outcome: ComputedRoundResult[T]): ComputedRoundError =
  ## Inspect selection without writable discriminator access.
  outcome.status
func value*[T](outcome: ComputedRoundResult[T]): T
    {.requires: outcome.status == ComputedRoundError.None.} =
  ## Guard complete-success extraction under optimized compilation.
  outcome.completed
func queueError*[T](outcome: ComputedRoundResult[T]): AccumulationQueueError
    {.requires: outcome.status == ComputedRoundError.QueueFailure.} =
  ## Inspect only the genuine selected queue refusal.
  outcome.queueReason
func roundError*[T](outcome: ComputedRoundResult[T]): AccumulationRoundError
    {.requires: outcome.status == ComputedRoundError.RoundFailure.} =
  ## Inspect only the genuine selected initial-round refusal.
  outcome.roundReason
proc computedRoundSource*(round: ComputedAccumulationRound): ComputedRoundResult[
    ComputedReportSuccessor] =
  ## Retain all original computed reports and the matching pending-assignment successor.
  let data = round.data
  if data == nil: return ComputedRoundResult[ComputedReportSuccessor](
      status: ComputedRoundError.Uninitialized)
  ComputedRoundResult[ComputedReportSuccessor](status: ComputedRoundError.None,
      completed: data.source)
proc computedRoundPlan*(round: ComputedAccumulationRound): ComputedRoundResult[
    BlockAccumulationRound] =
  ## Share the actual parent-bound initial plan, never detached invocation observations.
  let data = round.data
  if data == nil: return ComputedRoundResult[BlockAccumulationRound](
      status: ComputedRoundError.Uninitialized)
  ComputedRoundResult[BlockAccumulationRound](status: ComputedRoundError.None,
      completed: data.round)
proc computedRoundParameters*(round: ComputedAccumulationRound): ComputedRoundResult[Parameters] =
  ## Copy the exact original fixed parameter tuple for inspection without granting replacement authority.
  let data = round.data
  if data == nil: return ComputedRoundResult[Parameters](status: ComputedRoundError.Uninitialized)
  ComputedRoundResult[Parameters](status: ComputedRoundError.None, completed: data.parameters)
proc prepareComputedRound*(source: ComputedReportSuccessor,
    config: ComputedRoundConfig): ComputedRoundResult[ComputedAccumulationRound] =
  ## Require original semantic gas before deriving the maintained queue and exact-parent privilege/input plan.
  let selected = source.computedSuccessorSource
  if selected.error != ComputedPublicationError.None:
    return ComputedRoundResult[ComputedAccumulationRound](status: ComputedRoundError.InvalidSource)
  let batch = selected.value.computedAdmissionSource.value.computedInclusionSource.value
  let first = batch.computedBatchSourceAt(ComputedBatchIndex(0)).value
  let parameters = first.computedEnvelopeSource.value.computedCredentialSource.value.computedGuarantorSource.value.computedRosterSource.value.computedTransitionSource.value.computedProfileContext.value.parameters
  let sameReportGas = uint64(config.round.reportGas) == parameters.get(maxAccumulateGas)
  let sameBlockGas = uint64(config.round.blockGas) == parameters.get(blockGasLimit)
  if not sameReportGas or not sameBlockGas:
    return ComputedRoundResult[ComputedAccumulationRound](
        status: ComputedRoundError.ProfileMismatch)
  let queue = planBlockAccumulationQueue(selected.value.computedAdmissionReports.value, config.queue)
  if queue.error != AccumulationQueueError.None:
    return ComputedRoundResult[ComputedAccumulationRound](status: ComputedRoundError.QueueFailure,
        queueReason: queue.error)
  let round = planBlockInitialAccumulation(queue.value, config.round)
  if round.error != AccumulationRoundError.None:
    return ComputedRoundResult[ComputedAccumulationRound](status: ComputedRoundError.RoundFailure,
        roundReason: round.error)
  ComputedRoundResult[ComputedAccumulationRound](status: ComputedRoundError.None,
    completed: ComputedAccumulationRound(data: ComputedRoundData(source: source,
      round: round.value, parameters: parameters)))
