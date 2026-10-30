# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Authenticated current accumulation sequence ownership and bounded continuation input planning.
## Flat per-entry facts avoid recursive certificate ownership; selected successor state governs pending partitioning.
import ../../../chain/parameters
import ../../../codec/[bounded, composite]
import ../../../codec/work/digest as work_digest
import ../../../codec/[report_owned, c2_records, header]
import ../../../codec/state/[safrole as state_safrole, layout as state_layout]
import ./round as accumulation_current_round
import "../block/guests" as accumulation_block_guests
import ../[round as accumulation_round, queue as accumulation_queue,
    coverage as accumulation_coverage]
import ../global/[stage as accumulation_global_stage, phase as accumulation_global_phase]
import ../[annulled_outputs as accumulation_annulled_outputs,
    pending_transfers as accumulation_pending_transfers,
    transfer_partition as accumulation_transfer_partition, operands as accumulation_operands,
    inputs as accumulation_inputs, guest_runner as accumulation_guest_runner]
import ../account/phase as accumulation_account_phase
import ../provision/phase as accumulation_provision_phase
import ../[provisions as accumulation_provisions, transfers as accumulation_transfers]
import ../../report/admission as report_admission
import "../../block/transition" as block_transition
import "../../block/admission" as block_admission
import ../../store

type
  CurrentSequenceEntryIndex* = distinct uint64 ## A historical sequence entry cannot substitute an input service or report ordinal.
  CurrentPlanReportIndex* = distinct uint64 ## A selected next-report ordinal belongs only to its own continuation plan.
  CurrentContinuationLimits* = object ## Queue inspection, report materialization, grouping and partition work retain independent local ceilings.
    reports*, digests*: ElementLimit
    operands*: AccumulationOperandConfig
    inputs*: AccumulationInputConfig
    partition*: TransferPartitionLimits
  CurrentContinuationExecutionLimits* = object ## Bound retained flat history independently of the existing per-entry guest/selected-state policies.
    entries*: ElementLimit
    round*: CurrentAccumulationRoundLimits
  CurrentSequenceInfo* = object ## Latest budget/progress observations are separate from terminal whole-block publication.
    entries*, pending*: int
    processedReports*: AccumulationReportPrefix
    budget*: Gas
  CurrentContinuationInfo* = object ## Whole selected reports and accepted transfers alone create next guest inputs; initial free allowances never recur.
    start*: AccumulationReportStart
    prefix*: AccumulationReportPrefix
    pendingReports*, accepted*, queued*, services*: int
    budget*, reportGas*: Gas
    dispatch*: bool
  CurrentSequenceError* {.pure.} = enum ## No refusal exposes a selected report prefix or partial invocation inputs.
    Uninitialized, None, InvalidSource, InvalidIndex, LimitExceeded,
    OperandFailure, InputFailure, PartitionFailure, NoDispatch, InvalidParameters,
    GuestFailure, AccountFailure, ProvisionFailure, GlobalFailure, OutputFailure, TransferFailure, PendingFailure
  SequenceFact = object # Every fixed row retains genuine entry proofs without retaining a predecessor sequence owner.
    coverage: PreparedAccumulationCoverage
    globals: PreparedAccumulationGlobalPhase
    outputs: PreparedAnnulmentOutputs
    pending: PreparedPendingTransfers
    processed: AccumulationReportPrefix
  SequenceData = ref object # Immutable flat history shares only acyclic proof/state graphs, not a linked chain of sequence certificates.
    initial: PreparedCurrentAccumulationRound
    facts: seq[SequenceFact]
  CurrentAccumulationSequence* = object ## Only genuine current completion and later checked execution can construct sequence ownership.
    data: nil SequenceData
  CurrentPlanData = ref object # An immutable plan binds exact source history, original queue, selected inputs and transfer classification.
    source: CurrentAccumulationSequence
    queue: AccumulationQueuePlan
    inputs: PreparedAccumulationInputs
    partition: PreparedTransferPartition
    info: CurrentContinuationInfo
  PreparedCurrentContinuation* = object ## Only affordable original-queue suffix selection and current-state partitioning constructs this plan.
    data: nil CurrentPlanData
  CurrentSequenceResult*[T] = object ## Private successful owners and actual child refusals occupy disjoint alternatives.
    case status: CurrentSequenceError
    of None:
      completed: T
    of OperandFailure:
      operandReason: AccumulationOperandError
    of InputFailure:
      inputReason: AccumulationInputError
    of PartitionFailure:
      partitionReason: TransferPartitionError
    of GuestFailure:
      guestReason: AccumulationGuestResult
    of AccountFailure:
      accountReason: AccumulationAccountPhaseResult[PreparedAccumulationAccountPhase]
    of ProvisionFailure:
      provisionReason: AccumulationProvisionPhaseResult[PreparedAccumulationProvisionPhase]
    of GlobalFailure:
      globalReason: AccumulationGlobalPhaseResult[PreparedAccumulationGlobalPhase]
    of OutputFailure:
      outputReason: AnnulmentOutputsError
    of TransferFailure:
      transferReason: AccumulationTransferCollectionError
    of PendingFailure:
      pendingReason: PendingTransferError
    else:
      discard # Defaults and extent/source/index refusals grant no initialized plan or sequence.

func error*[T](outcome: CurrentSequenceResult[T]): CurrentSequenceError =
  ## Inspect only the selected reason without granting mutation.
  outcome.status

func value*[T](outcome: CurrentSequenceResult[T]): T {.inline,
    requires: outcome.status == CurrentSequenceError.None.} =
  ## Extract complete source-bound ownership only after success.
  outcome.completed

func operandFailure*[T](outcome: CurrentSequenceResult[T]): AccumulationOperandError {.inline,
    requires: outcome.status == CurrentSequenceError.OperandFailure.} =
  ## Preserve the actual selected-range capture refusal.
  outcome.operandReason

func inputFailure*[T](outcome: CurrentSequenceResult[T]): AccumulationInputError {.inline,
    requires: outcome.status == CurrentSequenceError.InputFailure.} =
  ## Preserve the actual report-only/final grouping refusal.
  outcome.inputReason

func partitionFailure*[T](outcome: CurrentSequenceResult[T]): TransferPartitionError {.inline,
    requires: outcome.status == CurrentSequenceError.PartitionFailure.} =
  ## Preserve the actual selected-state transfer classification refusal.
  outcome.partitionReason

proc startCurrentAccumulationSequence*(initial: PreparedCurrentAccumulationRound): CurrentSequenceResult[
    CurrentAccumulationSequence] =
  ## Capture exactly one completed authenticated initial round; pure/default phase owners cannot provide an anchor.
  let guests = initial.currentRoundGuests
  if guests.error != CurrentAccumulationRoundError.None:
    return CurrentSequenceResult[CurrentAccumulationSequence](
        status: CurrentSequenceError.InvalidSource)
  let processed = guests.value.guestRound.value.roundProjection.value.roundInfo.value.prefix
  let globals = initial.currentRoundGlobals.value.globalStagePhase.value
  let first = SequenceFact(coverage: guests.value.guestCoverage.value, globals: globals,
    outputs: initial.currentRoundOutputs.value, pending: initial.currentRoundPending.value,
    processed: processed)
  CurrentSequenceResult[CurrentAccumulationSequence](status: CurrentSequenceError.None,
    completed: CurrentAccumulationSequence(data: SequenceData(initial: initial, facts: @[first])))

proc currentSequenceInfo*(sequence: CurrentAccumulationSequence): CurrentSequenceResult[
    CurrentSequenceInfo] =
  ## Copy latest progress/budget without allowing a caller to replace historical rows or their source proofs.
  let data = sequence.data
  if data == nil:
    return CurrentSequenceResult[CurrentSequenceInfo](status: CurrentSequenceError.Uninitialized)
  let latest = data.facts[data.facts.len-1] # Private constructors retain at least one completely prepared entry.
  let pending = latest.pending.pendingTransferInfo.value
  CurrentSequenceResult[CurrentSequenceInfo](status: CurrentSequenceError.None,
    completed: CurrentSequenceInfo(entries: data.facts.len, pending: pending.transfers,
      processedReports: latest.processed, budget: pending.budget))

proc currentSequenceInitial*(sequence: CurrentAccumulationSequence): CurrentSequenceResult[
    PreparedCurrentAccumulationRound] =
  ## Retain the genuine initial block/guest anchor independently of the caller's original handle lifetime.
  let data = sequence.data
  if data == nil:
    return CurrentSequenceResult[PreparedCurrentAccumulationRound](
        status: CurrentSequenceError.Uninitialized)
  CurrentSequenceResult[PreparedCurrentAccumulationRound](status: CurrentSequenceError.None,
      completed: data.initial)

proc planCurrentAccumulationContinuation*(sequence: CurrentAccumulationSequence,
    limits: CurrentContinuationLimits): CurrentSequenceResult[PreparedCurrentContinuation] =
  ## Select the next affordable whole reports, partition pending transfers against latest selected state, and group only accepted inputs without free allowances.
  template fail(reason: CurrentSequenceError) =
    return CurrentSequenceResult[PreparedCurrentContinuation](status: reason)
  let data = sequence.data
  if data == nil:
    fail(CurrentSequenceError.InvalidSource) # No default/partial history can supply an admitted queue or private successor state.
  let latest = data.facts[data.facts.len-1]
  let round = data.initial.currentRoundGuests.value.guestRound.value
  let queue = round.roundBlockQueue.value.accumulationProjection.value
  let count = queue.accumulationCount.value
  let start = uint64(latest.processed)
  if start > uint64(count):
    fail(CurrentSequenceError.InvalidSource) # Prove source-owned suffix conversion before indexing or subtracting its length.
  let pendingInfo = latest.pending.pendingTransferInfo.value
  let reportBudget = uint64(pendingInfo.reportBudget)
  var remaining = reportBudget
  var prefix = 0'u64
  var reports = 0'u64
  var digests = 0'u64
  for ordinal in int(start)..<count:
    if reports >= uint64(limits.reports):
      fail(CurrentSequenceError.LimitExceeded) # Charge the first rejected report too, before retrieving it.
    inc reports
    let report = queue.accumulationAt(AccumulationIndex(uint64(ordinal))).value
    let length = ownedReportInfo(report).value.digestCount
    var candidate = remaining
    var fits = true
    for digest in 0..<length:
      if digests >= uint64(limits.digests):
        fail(CurrentSequenceError.LimitExceeded) # Every inspected gas word consumes explicit work, including an unaffordable suffix.
      inc digests
      let gas = uint64(ownedReportDigest(report, digest).value.accumulateGas)
      if gas > candidate:
        fits = false
        break # No later report bypasses an unaffordable whole report.
      candidate -= gas # Proven subtraction prevents mathematical gas sums from wrapping.
    if not fits: break # Discard every tentative reservation in the rejected report.
    remaining = candidate
    inc prefix # The bounded original queue suffix proves this increment and later range.
  let operands = prepareAccumulationOperandRange(queue, AccumulationReportStart(start),
    AccumulationReportPrefix(prefix), limits.operands)
  if operands.error != AccumulationOperandError.None:
    return CurrentSequenceResult[PreparedCurrentContinuation](
        status: CurrentSequenceError.OperandFailure, operandReason: operands.error)
  let activeInputs = prepareAccumulationInputs(operands.value, [], [], limits.inputs)
  if activeInputs.error != AccumulationInputError.None:
    return CurrentSequenceResult[PreparedCurrentContinuation](
        status: CurrentSequenceError.InputFailure, inputReason: activeInputs.error)
  let serviceCount = if pendingInfo.transfers == 0: 0 else: activeInputs.value.invocationServiceCount.value
  if uint64(pendingInfo.transfers) > uint64(limits.partition.transfers) or
      uint64(pendingInfo.transfers) > uint64(limits.partition.checks) or
      uint64(serviceCount) > uint64(limits.partition.services) or serviceCount > high(
          int) div sizeof(ServiceIndex):
    return CurrentSequenceResult[PreparedCurrentContinuation](
        status: CurrentSequenceError.PartitionFailure,
        partitionReason: TransferPartitionError.LimitExceeded) # Bound pending capture, minimum predicates and active allocation before work.
  var active = newSeq[ServiceIndex](serviceCount)
  for ordinal in 0..<serviceCount:
    active[ordinal] = activeInputs.value.invocationServiceAt(InvocationServiceIndex(uint64(
        ordinal))).value.service # Report services alone are active before transfer credit partitioning.
  let state = latest.globals.globalPhaseSnapshot.value
  let partition = latest.pending.partitionPendingTransfers(state, active, limits.partition)
  if partition.error == PendingTransferError.PartitionFailure:
    return CurrentSequenceResult[PreparedCurrentContinuation](
        status: CurrentSequenceError.PartitionFailure,
        partitionReason: partition.partitionError) # Preserve the actual nested classification refusal.
  if partition.error != PendingTransferError.None:
    fail(CurrentSequenceError.InvalidSource) # Only initialized source-owned pending records may authorize classification.
  let accepted = partition.value.partitionCount(TransferPartitionKind.Accepted).value
  if uint64(accepted) > uint64(limits.inputs.inputs) or accepted > high(int) div sizeof(DeferredTransfer):
    return CurrentSequenceResult[PreparedCurrentContinuation](
        status: CurrentSequenceError.InputFailure,
        inputReason: AccumulationInputError.LimitExceeded) # Bound every accepted record before temporary capture.
  var transfers = newSeq[DeferredTransfer](accepted)
  for ordinal in 0..<accepted:
    transfers[ordinal] = partition.value.partitionTransferAt(TransferPartitionKind.Accepted,
      TransferPartitionIndex(uint64(ordinal))).value # Preserve stable accepted order before destination grouping.
  let inputs = prepareAccumulationInputs(operands.value, transfers, [], limits.inputs)
  if inputs.error != AccumulationInputError.None:
    return CurrentSequenceResult[PreparedCurrentContinuation](
        status: CurrentSequenceError.InputFailure, inputReason: inputs.error)
  let info = CurrentContinuationInfo(start: AccumulationReportStart(start),
      prefix: AccumulationReportPrefix(prefix),
    pendingReports: count-int(start), accepted: accepted,
    queued: partition.value.partitionCount(TransferPartitionKind.Queued).value,
    services: inputs.value.invocationServiceCount.value, budget: pendingInfo.budget,
    reportGas: Gas(reportBudget-remaining), dispatch: prefix != 0 or pendingInfo.transfers != 0)
  CurrentSequenceResult[PreparedCurrentContinuation](status: CurrentSequenceError.None,
    completed: PreparedCurrentContinuation(data: CurrentPlanData(source: sequence, queue: queue,
      inputs: inputs.value, partition: partition.value, info: info)))

proc currentSequenceCoverageAt*(sequence: CurrentAccumulationSequence,
    index: CurrentSequenceEntryIndex): CurrentSequenceResult[PreparedAccumulationCoverage] =
  ## Retain the exact historical entry projection; full-width ordinals cannot alias another source or truncated index.
  let data = sequence.data
  if data == nil:
    return CurrentSequenceResult[PreparedAccumulationCoverage](
        status: CurrentSequenceError.Uninitialized)
  if uint64(index) >= uint64(data.facts.len):
    return CurrentSequenceResult[PreparedAccumulationCoverage](
        status: CurrentSequenceError.InvalidIndex)
  CurrentSequenceResult[PreparedAccumulationCoverage](status: CurrentSequenceError.None,
      completed: data.facts[int(uint64(index))].coverage)

proc currentSequenceOutputsAt*(sequence: CurrentAccumulationSequence,
    index: CurrentSequenceEntryIndex): CurrentSequenceResult[PreparedAnnulmentOutputs] =
  ## Retain the exact historical entry projection; full-width ordinals cannot alias another source or truncated index.
  let data = sequence.data
  if data == nil:
    return CurrentSequenceResult[PreparedAnnulmentOutputs](
        status: CurrentSequenceError.Uninitialized)
  if uint64(index) >= uint64(data.facts.len):
    return CurrentSequenceResult[PreparedAnnulmentOutputs](
        status: CurrentSequenceError.InvalidIndex)
  CurrentSequenceResult[PreparedAnnulmentOutputs](status: CurrentSequenceError.None,
      completed: data.facts[int(uint64(index))].outputs)

proc currentSequenceStateAt*(sequence: CurrentAccumulationSequence,
    index: CurrentSequenceEntryIndex): CurrentSequenceResult[StateStoreSnapshot] =
  ## Retain the exact historical entry projection; full-width ordinals cannot alias another source or truncated index.
  let data = sequence.data
  if data == nil:
    return CurrentSequenceResult[StateStoreSnapshot](status: CurrentSequenceError.Uninitialized)
  if uint64(index) >= uint64(data.facts.len):
    return CurrentSequenceResult[StateStoreSnapshot](status: CurrentSequenceError.InvalidIndex)
  CurrentSequenceResult[StateStoreSnapshot](status: CurrentSequenceError.None,
      completed: data.facts[int(uint64(index))].globals.globalPhaseSnapshot.value)

proc currentSequenceLatestState*(sequence: CurrentAccumulationSequence): CurrentSequenceResult[
    StateStoreSnapshot] =
  ## Retain the complete latest projection, never a fabricated default/empty sequence.
  let data = sequence.data
  if data == nil:
    return CurrentSequenceResult[StateStoreSnapshot](status: CurrentSequenceError.Uninitialized)
  CurrentSequenceResult[StateStoreSnapshot](status: CurrentSequenceError.None,
      completed: data.facts[data.facts.len-1].globals.globalPhaseSnapshot.value)

proc currentSequencePending*(sequence: CurrentAccumulationSequence): CurrentSequenceResult[
    PreparedPendingTransfers] =
  ## Retain the complete latest projection, never a fabricated default/empty sequence.
  let data = sequence.data
  if data == nil:
    return CurrentSequenceResult[PreparedPendingTransfers](
        status: CurrentSequenceError.Uninitialized)
  CurrentSequenceResult[PreparedPendingTransfers](status: CurrentSequenceError.None,
      completed: data.facts[data.facts.len-1].pending)

proc currentContinuationInfo*(plan: PreparedCurrentContinuation): CurrentSequenceResult[
    CurrentContinuationInfo] =
  ## Retain this exact source-bound plan projection; defaults cannot manufacture continuation authority.
  let data = plan.data
  if data == nil:
    return CurrentSequenceResult[CurrentContinuationInfo](
        status: CurrentSequenceError.Uninitialized)
  CurrentSequenceResult[CurrentContinuationInfo](status: CurrentSequenceError.None,
      completed: data.info)

proc currentContinuationSource*(plan: PreparedCurrentContinuation): CurrentSequenceResult[
    CurrentAccumulationSequence] =
  ## Retain this exact source-bound plan projection; defaults cannot manufacture continuation authority.
  let data = plan.data
  if data == nil:
    return CurrentSequenceResult[CurrentAccumulationSequence](
        status: CurrentSequenceError.Uninitialized)
  CurrentSequenceResult[CurrentAccumulationSequence](status: CurrentSequenceError.None,
      completed: data.source)

proc currentContinuationInputs*(plan: PreparedCurrentContinuation): CurrentSequenceResult[
    PreparedAccumulationInputs] =
  ## Retain this exact source-bound plan projection; defaults cannot manufacture continuation authority.
  let data = plan.data
  if data == nil:
    return CurrentSequenceResult[PreparedAccumulationInputs](
        status: CurrentSequenceError.Uninitialized)
  CurrentSequenceResult[PreparedAccumulationInputs](status: CurrentSequenceError.None,
      completed: data.inputs)

proc currentContinuationPartition*(plan: PreparedCurrentContinuation): CurrentSequenceResult[
    PreparedTransferPartition] =
  ## Retain this exact source-bound plan projection; defaults cannot manufacture continuation authority.
  let data = plan.data
  if data == nil:
    return CurrentSequenceResult[PreparedTransferPartition](
        status: CurrentSequenceError.Uninitialized)
  CurrentSequenceResult[PreparedTransferPartition](status: CurrentSequenceError.None,
      completed: data.partition)

proc currentContinuationState*(plan: PreparedCurrentContinuation): CurrentSequenceResult[
    StateStoreSnapshot] =
  ## Retain this exact source-bound plan projection; defaults cannot manufacture continuation authority.
  let data = plan.data
  if data == nil:
    return CurrentSequenceResult[StateStoreSnapshot](status: CurrentSequenceError.Uninitialized)
  CurrentSequenceResult[StateStoreSnapshot](status: CurrentSequenceError.None,
      completed: data.source.currentSequenceLatestState.value)

proc currentContinuationReportAt*(plan: PreparedCurrentContinuation,
    index: CurrentPlanReportIndex): CurrentSequenceResult[OwnedReport] =
  ## Address only this plan's selected original-queue suffix, with upper bits checked before conversion/addition.
  let data = plan.data
  if data == nil:
    return CurrentSequenceResult[OwnedReport](status: CurrentSequenceError.Uninitialized)
  if uint64(index) >= uint64(data.info.prefix):
    return CurrentSequenceResult[OwnedReport](status: CurrentSequenceError.InvalidIndex)
  let absolute = uint64(data.info.start)+uint64(index) # Factory bounds the complete selected range by the genuine native queue count.
  CurrentSequenceResult[OwnedReport](status: CurrentSequenceError.None,
      completed: data.queue.accumulationAt(AccumulationIndex(absolute)).value)

func guestFailure*[T](outcome: CurrentSequenceResult[T]): AccumulationGuestResult {.inline,
    requires: outcome.status == CurrentSequenceError.GuestFailure.} =
  ## Inspect only the actual failed guestReason; successful earlier providers/phases never escape refusal.
  outcome.guestReason

func accountFailure*[T](outcome: CurrentSequenceResult[T]): AccumulationAccountPhaseResult[
    PreparedAccumulationAccountPhase] {.inline, requires: outcome.status ==
    CurrentSequenceError.AccountFailure.} =
  ## Inspect only the actual failed accountReason; successful earlier providers/phases never escape refusal.
  outcome.accountReason

func provisionFailure*[T](outcome: CurrentSequenceResult[T]): AccumulationProvisionPhaseResult[
    PreparedAccumulationProvisionPhase] {.inline, requires: outcome.status ==
    CurrentSequenceError.ProvisionFailure.} =
  ## Inspect only the actual failed provisionReason; successful earlier providers/phases never escape refusal.
  outcome.provisionReason

func globalFailure*[T](outcome: CurrentSequenceResult[T]): AccumulationGlobalPhaseResult[
    PreparedAccumulationGlobalPhase] {.inline, requires: outcome.status ==
    CurrentSequenceError.GlobalFailure.} =
  ## Inspect only the actual failed globalReason; successful earlier providers/phases never escape refusal.
  outcome.globalReason

func outputFailure*[T](outcome: CurrentSequenceResult[T]): AnnulmentOutputsError {.inline,
    requires: outcome.status == CurrentSequenceError.OutputFailure.} =
  ## Inspect only the actual failed outputReason; successful earlier providers/phases never escape refusal.
  outcome.outputReason

func transferFailure*[T](outcome: CurrentSequenceResult[
    T]): AccumulationTransferCollectionError {.inline, requires: outcome.status ==
    CurrentSequenceError.TransferFailure.} =
  ## Inspect only the actual failed transferReason; successful earlier providers/phases never escape refusal.
  outcome.transferReason

func pendingFailure*[T](outcome: CurrentSequenceResult[T]): PendingTransferError {.inline,
    requires: outcome.status == CurrentSequenceError.PendingFailure.} =
  ## Inspect only the actual failed pendingReason; successful earlier providers/phases never escape refusal.
  outcome.pendingReason

proc runCurrentAccumulationContinuation*(plan: PreparedCurrentContinuation,
    limits: CurrentContinuationExecutionLimits): CurrentSequenceResult[
        CurrentAccumulationSequence] =
  ## Execute this genuine selected entry once using frozen initial Parameters and admitted frame, then append genuine flat facts privately.
  template fail(reason: CurrentSequenceError) =
    return CurrentSequenceResult[CurrentAccumulationSequence](status: reason)
  let data = plan.data
  if data == nil:
    fail(CurrentSequenceError.InvalidSource) # Default/pure input owners cannot supply continuation authority.
  if not data.info.dispatch:
    fail(CurrentSequenceError.NoDispatch) # Terminal planning is not a fabricated successful zero-guest entry.
  let source = data.source.data
  if source == nil:
    fail(CurrentSequenceError.InvalidSource) # No detached/default source can authorize execution even inside a retained plan.
  let count = source.facts.len
  if uint64(count) >= uint64(limits.entries) or count >= high(int) div sizeof(SequenceFact):
    fail(CurrentSequenceError.LimitExceeded) # Bound count+1 and the entire new flat vector before any execution/allocation.
  let parameters = source.initial.currentRoundParameters.value
  if not parameters.valid:
    fail(CurrentSequenceError.InvalidSource) # A genuine initial completion always retains valid immutable configuration.
  let anchor = source.initial.currentRoundGuests.value.guestRound.value.roundBlockQueue.value.accumulationAdmission.value.reportBlockStage.value
  let profile = anchor.blockTransitionProfile
  let contexts = limits.round.guests.contexts
  if parameters.get(coreCount) != uint64(profile.cores) or
      parameters.get(epochPeriod) != uint64(profile.epochSlots) or parameters.get(authQueueLen) != 80:
    fail(CurrentSequenceError.InvalidSource) # Frozen chain configuration must retain the original admitted shape.
  if uint64(contexts.validators) != uint64(profile.validators) or
      uint64(contexts.queues.cores) != uint64(profile.cores) or
      uint64(contexts.staging.cores) != uint64(profile.cores) or
      uint64(contexts.privileges.cores) != uint64(profile.cores) or
      uint64(limits.round.globals.roles.privileges.cores) != uint64(profile.cores) or
      uint64(limits.round.globals.queues.cores) != uint64(profile.cores) or
      uint64(limits.round.globals.staging.cores) != uint64(profile.cores):
    fail(CurrentSequenceError.InvalidParameters) # Local shape choices cannot replace authenticated population/core authority.
  let stage = anchor.value
  let slot = headerInfo(stage.admitted.admittedHeader).value.unsigned.slot
  let rawEntropy = stage.snapshot.lookup(chapterKey(StateChapter(6)))
  if rawEntropy.error != StateStoreError.None:
    fail(CurrentSequenceError.InvalidSource) # Never fall back to entropy in the selected common-prior map.
  if rawEntropy.value.byteLength != 128:
    fail(CurrentSequenceError.InvalidSource) # Bound the fixed posterior chapter before capturing/decoding bytes.
  let entropy = decodeStateEntropy(rawEntropy.value.bytes)
  if entropy.error != StateComponentError.None:
    fail(CurrentSequenceError.InvalidSource) # Genuine admitted stage ownership must retain exact posterior entropy.
  let prior = source.facts[count-1].globals.globalPhaseSnapshot.value
  var guestLimits = limits.round.guests
  if uint64(guestLimits.coverage.gas) > uint64(data.info.budget):
    guestLimits.coverage.gas = data.info.budget # A generous caller cap cannot relax this entry's source-derived gas budget.
  let guests = runAccumulationGuests(data.inputs, prior, slot, entropy.value.value[0], parameters, guestLimits)
  if guests.error != AccumulationGuestError.None:
    return CurrentSequenceResult[CurrentAccumulationSequence](
        status: CurrentSequenceError.GuestFailure, guestReason: guests)
  let accounts = prepareAccumulationAccountPhase(guests.value, limits.round.accounts)
  if accounts.error != AccumulationAccountPhaseError.None:
    return CurrentSequenceResult[CurrentAccumulationSequence](
        status: CurrentSequenceError.AccountFailure, accountReason: accounts)
  let provisions = prepareAccumulationProvisionPhase(accounts.value, limits.round.provisions)
  if provisions.error != AccumulationProvisionPhaseError.None:
    return CurrentSequenceResult[CurrentAccumulationSequence](
        status: CurrentSequenceError.ProvisionFailure, provisionReason: provisions)
  let globals = prepareAccumulationGlobalPhase(provisions.value, limits.round.globals)
  if globals.error != AccumulationGlobalPhaseError.None:
    return CurrentSequenceResult[CurrentAccumulationSequence](
        status: CurrentSequenceError.GlobalFailure, globalReason: globals)
  let selection = guests.value.coverageAnnulment.value
  let outputs = prepareAnnulmentOutputs(selection, limits.round.outputs)
  if outputs.error != AnnulmentOutputsError.None:
    return CurrentSequenceResult[CurrentAccumulationSequence](
        status: CurrentSequenceError.OutputFailure, outputReason: outputs.error)
  let transfers = prepareAnnulmentTransfers(selection, limits.round.transfers)
  if transfers.error != AccumulationTransferCollectionError.None:
    return CurrentSequenceResult[CurrentAccumulationSequence](
        status: CurrentSequenceError.TransferFailure, transferReason: transfers.error)
  let pending = prepareCarriedPendingTransfers(data.partition, transfers.value, data.info.budget,
      limits.round.pending)
  if pending.error != PendingTransferError.None:
    return CurrentSequenceResult[CurrentAccumulationSequence](
        status: CurrentSequenceError.PendingFailure, pendingReason: pending.error)
  var facts = newSeq[SequenceFact](count+1)
  for ordinal in 0..<count:
    facts[ordinal] = source.facts[ordinal] # Copy retained immutable facts without a predecessor sequence/plan reference.
  let processed = uint64(data.info.start)+uint64(data.info.prefix) # The genuine original-queue range proves this sum fits.
  facts[count] = SequenceFact(coverage: guests.value, globals: globals.value,
    outputs: outputs.value,
    pending: pending.value, processed: AccumulationReportPrefix(processed))
  CurrentSequenceResult[CurrentAccumulationSequence](status: CurrentSequenceError.None,
    completed: CurrentAccumulationSequence(data: SequenceData(initial: source.initial,
        facts: facts)))
