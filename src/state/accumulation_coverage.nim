# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exact explicit-input provider coverage preserves original gas through annulment and distinguishes both no-execution proofs.
## This immutable certificate neither authenticates caller parameters nor publishes a completed block/round.
import ../codec/bounded as codec_bounded
import ../codec/composite as codec_composite
import ../codec/header as codec_header
import ../codec/work_digest as codec_work_digest
import ./accumulation_annulment as state_accumulation_annulment
import ./accumulation_outcome as state_accumulation_outcome
import ./accumulation_skip as state_accumulation_skip
import ./accumulation_absent as state_accumulation_absent
import ./accumulation_service as state_accumulation_service
import ./accumulation_inputs as state_accumulation_inputs
import ./store as state_store

type
  AccumulationCoverageIndex* = distinct uint64 ## Canonical input-service row position is distinct from original producer ordinals.
  AccumulationCoverageKind* {.pure.} = enum ## Only this private row's actual kind authorizes its matching source getter.
    Executed, CodeUnavailable, Absent
  AccumulationCoverageLimits* = object ## Every provider family, final row and predicate has an independent explicit bound.
    services*, executed*, skipped*, absent*, checks*: ElementLimit
    gas*: Gas ## Maximum aggregate actual consumption, not a sum of offered input budgets.
  AccumulationCoverageRow* = object ## Fixed copied observations cannot forge or retag retained source proofs.
    service*: ServiceIndex
    kind*: AccumulationCoverageKind
    gasUsed*: Gas
  AccumulationCoverageInfo* = object ## Complete input coverage is separate from selected state publication and block authority.
    services*, executed*, skipped*, absent*: int
    checks*: uint64
    gasUsed*: Gas
    slot*: HeaderSlot
  AccumulationCoverageError* {.pure.} = enum ## Refused/default alternatives carry a reason without any partial rows.
    Uninitialized, None, InvalidSource, InvalidProvider, SourceMismatch, SlotMismatch,
    CoverageMismatch, DuplicateService, LimitExceeded, GasExceeded, InvalidIndex, KindMismatch
  CoverageRow = object # Private inactive handles are never exposed by a wrong-kind getter.
    filled: bool
    info: AccumulationCoverageRow
    original: AccumulationOutcome
    skipped: SkippedAccumulation
    absent: AbsentAccumulation
  CoverageDraft = object # Explicit bounded work state remains local until all input rows are filled exactly once.
    inputs: PreparedAccumulationInputs
    limits: AccumulationCoverageLimits
    rows: seq[CoverageRow]
    checks, gas: uint64
  CoverageData = ref object # Acyclic genuine sources survive release of caller arrays and construction scopes.
    source: PreparedAccumulationAnnulment
    rows: seq[CoverageRow]
    info: AccumulationCoverageInfo
  PreparedAccumulationCoverage* = object ## Only complete checked preparation constructs canonical provider coverage.
    data: nil CoverageData
  AccumulationCoverageResult*[T] = object ## Successful payloads and result tags are private behind read-only checked access.
    case status: AccumulationCoverageError
    of None:
      completed: T # No public mutable or inactive success payload.
    else:
      discard      # Failure retains the typed reason alone.

func error*[T](outcome: AccumulationCoverageResult[T]): AccumulationCoverageError =
  ## Inspect a refusal without granting retagging.
  outcome.status
func value*[T](outcome: AccumulationCoverageResult[T]): T {.inline,
    requires: outcome.status == AccumulationCoverageError.None.} =
  ## Extract only complete selected success under optimized checked contracts.
  outcome.completed
proc spend(draft: var CoverageDraft): AccumulationCoverageError =
  ## Charge provider/group/final-coverage inspection before access.
  if draft.checks >= uint64(draft.limits.checks): return AccumulationCoverageError.LimitExceeded # No work after quota exhaustion.
  inc draft.checks
  AccumulationCoverageError.None
proc capture(draft: var CoverageDraft, row: CoverageRow): AccumulationCoverageError =
  ## Place one genuine provider into its own canonical input row, checking uniqueness and actual gas before addition.
  for index in 0..<draft.rows.len:
    let charged = draft.spend()
    if charged != AccumulationCoverageError.None: return charged # Bound every inspected input identity.
    let input = draft.inputs.invocationServiceAt(InvocationServiceIndex(uint64(index))).value
    if uint32(input.service) != uint32(row.info.service): continue # Other input groups cannot be replaced by this provider.
    if draft.rows[index].filled: return AccumulationCoverageError.DuplicateService # Never choose among repeated provider claims.
    let actual = uint64(row.info.gasUsed)
    if actual > uint64(input.gas) or actual > uint64(draft.limits.gas)-draft.gas:
      return AccumulationCoverageError.GasExceeded # Check per-service and aggregate budget before wrapping addition.
    draft.gas += actual
    draft.rows[index] = row # The private row carries only genuine matching proof handles.
    return AccumulationCoverageError.None
  AccumulationCoverageError.SourceMismatch # An extra unknown service cannot silently disappear from coverage.
proc prepareAccumulationCoverage*(source: PreparedAccumulationAnnulment,
    skipped: openArray[SkippedAccumulation], absent: openArray[AbsentAccumulation],
        slot: HeaderSlot,
    limits: AccumulationCoverageLimits): AccumulationCoverageResult[PreparedAccumulationCoverage] =
  ## Bind exact complete original/non-executing provider coverage without state hashing, execution or publication.
  template fail(reason: AccumulationCoverageError) =
    return AccumulationCoverageResult[PreparedAccumulationCoverage](status: reason)
  let original = source.annulmentInfo
  if original.error != AccumulationAnnulmentError.None:
    fail(AccumulationCoverageError.InvalidSource) # No caller-authored prior or default empty outcome source.
  let inputs = source.annulmentInputs.value
  let prior = source.annulmentPrior.value
  let count = inputs.invocationServiceCount.value
  if uint64(count) > uint64(limits.services) or count > high(int) div sizeof(CoverageRow) or
      uint64(original.value.outcomes) > uint64(limits.executed) or uint64(skipped.len) > uint64(
          limits.skipped) or uint64(absent.len) > uint64(limits.absent):
    fail(AccumulationCoverageError.LimitExceeded) # Bound every provider family and final native descriptor extent before allocation.
  var remaining = count
  if original.value.outcomes > remaining: fail(AccumulationCoverageError.CoverageMismatch) # Prove provider-count arithmetic by subtraction.
  remaining -= original.value.outcomes
  if skipped.len > remaining: fail(AccumulationCoverageError.CoverageMismatch) # No overflowing sum of three native array lengths.
  remaining -= skipped.len
  if absent.len != remaining: fail(AccumulationCoverageError.CoverageMismatch) # Exactly one candidate provider per input is required before identity checks.
  let frame = source.annulmentSlot
  if frame.error == AccumulationAnnulmentError.None:
    if uint32(frame.value) != uint32(slot): fail(AccumulationCoverageError.SlotMismatch) # Original executed frames already share slot/entropy.
  elif frame.error != AccumulationAnnulmentError.NoInvocationSlot:
    fail(AccumulationCoverageError.InvalidSource) # Only a genuine initialized zero-execution certificate lacks a bootstrap slot.
  var draft = CoverageDraft(inputs: inputs, limits: limits, rows: newSeq[CoverageRow](count),
      checks: 0, gas: 0)
  for index in 0..<original.value.outcomes:
    let charged = draft.spend()
    if charged != AccumulationCoverageError.None: fail(
        charged) # Charge every original, including annulled producers.
    let outcome = source.annulmentOriginalOutcomeAt(AccumulationAnnulmentIndex(uint64(index))).value
    let info = outcome.outcomeInfo.value
    let copied = draft.capture(CoverageRow(filled: true,
      info: AccumulationCoverageRow(service: info.service, kind: AccumulationCoverageKind.Executed,
        gasUsed: info.gasUsed), original: outcome))
    if copied != AccumulationCoverageError.None: fail(
        copied) # Cancellation never erases actual original consumed gas.
  for outcome in skipped:
    let charged = draft.spend()
    if charged != AccumulationCoverageError.None: fail(
        charged) # Bound non-executing source validation as well as final rows.
    let service = outcome.skipService
    if service.error != AccumulationSkipError.None: fail(
        AccumulationCoverageError.InvalidProvider) # No fabricated unavailable-code completion.
    if not service.value.serviceSourceMatches(inputs, prior): fail(
        AccumulationCoverageError.SourceMismatch) # Equal contents cannot replace common source ownership.
    let info = outcome.skipInfo.value
    if uint32(info.slot) != uint32(slot): fail(AccumulationCoverageError.SlotMismatch) # Code-unavailable credits retain the actual invocation slot.
    let copied = draft.capture(CoverageRow(filled: true,
      info: AccumulationCoverageRow(service: info.service,
        kind: AccumulationCoverageKind.CodeUnavailable,
        gasUsed: info.gasUsed), skipped: outcome))
    if copied != AccumulationCoverageError.None: fail(
        copied) # Genuine skip construction guarantees zero actual gas and no execution.
  for outcome in absent:
    let charged = draft.spend()
    if charged != AccumulationCoverageError.None: fail(
        charged) # Bound absent-account source checks independently of input amounts.
    let info = outcome.absentInfo
    if info.error != AccumulationAbsentError.None: fail(
        AccumulationCoverageError.InvalidProvider) # Default absence is not an initialized zero-effect result.
    if not sameAccumulationInputs(outcome.absentInputs.value, inputs) or not sameStateSnapshot(
        outcome.absentState.value, prior):
      fail(AccumulationCoverageError.SourceMismatch) # Absent identity must retain this exact input/prior pair.
    if uint32(info.value.slot) != uint32(slot): fail(
        AccumulationCoverageError.SlotMismatch) # No implicit/default time for absent input groups.
    let copied = draft.capture(CoverageRow(filled: true,
      info: AccumulationCoverageRow(service: info.value.service,
        kind: AccumulationCoverageKind.Absent,
        gasUsed: info.value.gasUsed), absent: outcome))
    if copied != AccumulationCoverageError.None: fail(
        copied) # Retain the actual no-credit proof, never an executed surrogate.
  for index in 0..<draft.rows.len:
    let filled = draft.rows[index].filled
    let charged = draft.spend()
    if charged != AccumulationCoverageError.None: fail(
        charged) # Complete coverage remains an explicit bounded final check.
    if not filled: fail(AccumulationCoverageError.CoverageMismatch) # No private default row escapes as a real execution.
  let info = AccumulationCoverageInfo(services: count, executed: original.value.outcomes,
    skipped: skipped.len, absent: absent.len, checks: draft.checks, gasUsed: Gas(draft.gas), slot: slot)
  AccumulationCoverageResult[PreparedAccumulationCoverage](status: AccumulationCoverageError.None,
    completed: PreparedAccumulationCoverage(data: CoverageData(source: source, rows: draft.rows, info: info)))

proc coverageInfo*(plan: PreparedAccumulationCoverage): AccumulationCoverageResult[
    AccumulationCoverageInfo] =
  ## Copy actual complete provider counts, frame and original gas without granting mutable row access.
  let data = plan.data
  if data == nil: return AccumulationCoverageResult[AccumulationCoverageInfo](
      status: AccumulationCoverageError.Uninitialized) # No default empty coverage.
  AccumulationCoverageResult[AccumulationCoverageInfo](status: AccumulationCoverageError.None,
      completed: data.info)
proc coverageAnnulment*(plan: PreparedAccumulationCoverage): AccumulationCoverageResult[
    PreparedAccumulationAnnulment] =
  ## Retain the exact original/selected conflict certificate behind coverage and gas accounting.
  let data = plan.data
  if data == nil: return AccumulationCoverageResult[PreparedAccumulationAnnulment](
      status: AccumulationCoverageError.Uninitialized) # No substitute original source.
  AccumulationCoverageResult[PreparedAccumulationAnnulment](status: AccumulationCoverageError.None,
      completed: data.source)
proc checkedRow(plan: PreparedAccumulationCoverage,
    index: AccumulationCoverageIndex): AccumulationCoverageResult[CoverageRow] =
  ## Validate the retained owner and full-width position before any kind-specific proof extraction.
  let data = plan.data
  if data == nil: return AccumulationCoverageResult[CoverageRow](
      status: AccumulationCoverageError.Uninitialized) # No default row payload.
  if uint64(index) >= uint64(data.rows.len): return AccumulationCoverageResult[CoverageRow](
      status: AccumulationCoverageError.InvalidIndex) # Upper bits cannot alias a valid input row.
  AccumulationCoverageResult[CoverageRow](status: AccumulationCoverageError.None,
      completed: data.rows[int(uint64(index))])
proc coverageRowAt*(plan: PreparedAccumulationCoverage,
    index: AccumulationCoverageIndex): AccumulationCoverageResult[AccumulationCoverageRow] =
  ## Copy this canonical input row's actual service/kind/gas observations.
  let row = checkedRow(plan, index)
  if row.error != AccumulationCoverageError.None: return AccumulationCoverageResult[
      AccumulationCoverageRow](status: row.error) # No inactive observation payload.
  AccumulationCoverageResult[AccumulationCoverageRow](status: AccumulationCoverageError.None,
      completed: row.value.info)
proc coverageOriginalAt*(plan: PreparedAccumulationCoverage,
    index: AccumulationCoverageIndex): AccumulationCoverageResult[AccumulationOutcome] =
  ## Retain an actual ORIGINAL execution, including one later annulled; selected state belongs to coverageAnnulment.
  let row = checkedRow(plan, index)
  if row.error != AccumulationCoverageError.None: return AccumulationCoverageResult[
      AccumulationOutcome](status: row.error) # No default/bounds surrogate execution.
  if row.value.info.kind != AccumulationCoverageKind.Executed: return AccumulationCoverageResult[
      AccumulationOutcome](
      status: AccumulationCoverageError.KindMismatch) # Non-execution proofs cannot expose inactive raw outcomes.
  AccumulationCoverageResult[AccumulationOutcome](status: AccumulationCoverageError.None,
      completed: row.value.original)
proc coverageSkippedAt*(plan: PreparedAccumulationCoverage,
    index: AccumulationCoverageIndex): AccumulationCoverageResult[SkippedAccumulation] =
  ## Retain only the genuine code-unavailable completion at this input position.
  let row = checkedRow(plan, index)
  if row.error != AccumulationCoverageError.None: return AccumulationCoverageResult[
      SkippedAccumulation](status: row.error) # No substitute skip payload.
  if row.value.info.kind != AccumulationCoverageKind.CodeUnavailable: return AccumulationCoverageResult[
      SkippedAccumulation](
      status: AccumulationCoverageError.KindMismatch) # Execution and absence have different proof domains.
  AccumulationCoverageResult[SkippedAccumulation](status: AccumulationCoverageError.None,
      completed: row.value.skipped)
proc coverageAbsentAt*(plan: PreparedAccumulationCoverage,
    index: AccumulationCoverageIndex): AccumulationCoverageResult[AbsentAccumulation] =
  ## Retain only an actual no-credit absent-account proof at this input position.
  let row = checkedRow(plan, index)
  if row.error != AccumulationCoverageError.None: return AccumulationCoverageResult[
      AbsentAccumulation](status: row.error) # No default identity map surrogate.
  if row.value.info.kind != AccumulationCoverageKind.Absent: return AccumulationCoverageResult[
      AbsentAccumulation](
      status: AccumulationCoverageError.KindMismatch) # A present code-unavailable service is never account absence.
  AccumulationCoverageResult[AbsentAccumulation](status: AccumulationCoverageError.None,
      completed: row.value.absent)
