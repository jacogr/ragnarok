## GP 0.8.0 header.tex/judgments.tex/safrole.tex: admit, derive disputes and authenticate Safrole atomically.
## Other extrinsics, wall-clock admission and complete block execution remain separate stages.
import ../codec/[block_codec, header, tickets, state_disputes]
import ./[store, block_admission, disputes, safrole_transition]

type
  ## Failures select their precise stage cause without carrying staged state or a usable block.
  BlockTransitionError* {.pure.} = enum
    Uninitialized, None, AdmissionFailure, DisputesFailure, SafroleFailure
  ## Success retains the original block binding, complete disputes plan and authenticated posterior state.
  BlockTransition* = object
    admitted*: BoundBlock
    disputes*: DisputesPlan
    safrole*: SafroleTransition
  ## Stage-specific reasons and success are mutually exclusive and private.
  BlockTransitionResult* = object
    case status: BlockTransitionError
    of None:
      completed: BlockTransition
    of AdmissionFailure:
      admissionReason: BlockAdmissionError
    of DisputesFailure:
      disputesReason: DisputesError
    of SafroleFailure:
      safroleReason: SafroleTransitionResult
    else:
      discard # Default carries no candidate, snapshot or reason payload.

## Observe the stage without granting safe-code access to its discriminator.
func error*(outcome: BlockTransitionResult): BlockTransitionError = outcome.status
## Read complete success only after all staged work has been accepted.
func value*(outcome: BlockTransitionResult): BlockTransition {.inline,
    requires: outcome.status == BlockTransitionError.None.} = outcome.completed
## Inspect only an admission failure's cause.
func admissionError*(outcome: BlockTransitionResult): BlockAdmissionError {.inline,
    requires: outcome.status == BlockTransitionError.AdmissionFailure.} = outcome.admissionReason
## Inspect only a disputes failure's cause.
func disputesError*(outcome: BlockTransitionResult): DisputesError {.inline,
    requires: outcome.status == BlockTransitionError.DisputesFailure.} = outcome.disputesReason
## Inspect only a Safrole failure's selected typed stage result.
func safroleError*(outcome: BlockTransitionResult): SafroleTransitionResult {.inline,
    requires: outcome.status == BlockTransitionError.SafroleFailure.} = outcome.safroleReason

## Derive all offenders from this block and the parent C(5), never from a separately supplied projection.
## Work on a private store handle and replace the caller's handle once, after complete success.
proc advanceBlockState*(state: var StateStore, candidate: OwnedBlock, parent: OwnedHeader,
    admission: BlockAdmissionConfig, policy: DisputesConfig,
    safrole: SafroleTransitionConfig): BlockTransitionResult =
  if uint64(policy.epochSlots) != uint64(safrole.state.epochSlots) or
      uint64(policy.rosters.cores) != uint64(safrole.state.validators.cores) or
      uint64(policy.rosters.validators) != uint64(safrole.state.validators.validators) or
      uint64(admission.frame.cores) != uint64(policy.rosters.cores) or
      uint64(admission.frame.validators) != uint64(policy.rosters.validators) or
      uint64(admission.frame.epochSlots) != uint64(policy.epochSlots) or
      uint64(admission.frame.ticketLimit) != uint64(safrole.blockTickets):
    return BlockTransitionResult(status: BlockTransitionError.AdmissionFailure,
      admissionReason: BlockAdmissionError.InvalidConfig) # Reject divergent chain domains before native work.
  let retained = state.snapshot
  if retained.error != StateStoreError.None:
    return BlockTransitionResult(status: BlockTransitionError.AdmissionFailure,
      admissionReason: BlockAdmissionError.Uninitialized) # No synthesized empty parent.
  let admitted = validateBlockCommitments(candidate, parent, retained.value, admission)
  if admitted.error != BlockAdmissionError.None:
    return BlockTransitionResult(status: BlockTransitionError.AdmissionFailure,
      admissionReason: admitted.error) # No disputes or Safrole work after invalid commitments.
  let exact = admitted.value
  let child = readDisputes(extrinsicDisputes(blockExtrinsic(
      exact.admittedBlock).value).value).value.owner
  let plan = planDisputes(retained.value, child, policy)
  if plan.error != DisputesError.None:
    return BlockTransitionResult(status: BlockTransitionError.DisputesFailure,
      disputesReason: plan.error) # No partial offenders or assignments escape.
  let marker = checkDisputeMarker(plan.value, exact.admittedHeader)
  if marker != DisputesError.None:
    return BlockTransitionResult(status: BlockTransitionError.DisputesFailure,
      disputesReason: marker) # Marker order and duplicates are checked before publication/authentication.
  let judged = plan.value.disputeJudgments
  var offenders = newSeq[OffenderKey](disputeStateInfo(judged).value.offenders)
  for i in 0..<offenders.len:
    offenders[i] = stateOffenderAt(judged, DisputeStateIndex(uint64(i))).value # Complete derived cumulative set.
  var working = state
  let published = publishDisputes(working, plan.value)
  if published.error != DisputesError.None:
    return BlockTransitionResult(status: BlockTransitionError.DisputesFailure,
      disputesReason: published.error) # Original handle still owns every parent byte/root.
  let submitted = readTickets(extrinsicTickets(blockExtrinsic(
      exact.admittedBlock).value).value).value
  let advanced = advanceSafroleState(working, exact.admittedHeader, submitted, offenders, safrole)
  if advanced.error != SafroleTransitionError.None:
    return BlockTransitionResult(status: BlockTransitionError.SafroleFailure,
      safroleReason: advanced) # Includes late refusal after privately staged disputes writes.
  state = working # One canonical handle replacement publishes every accepted stage together.
  BlockTransitionResult(status: BlockTransitionError.None,
    completed: BlockTransition(admitted: exact, disputes: plan.value, safrole: advanced.value))
