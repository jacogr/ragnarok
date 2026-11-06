# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## CE135 complete-state qualification is distinct from actual block admission and from proof of execution or retained availability.
## Managed callers freeze the selected view and input through verification; only successful private owners expose guarantees and recipient facts.
import ./[work_anchors, work_eligibility]
import ../chain/[provider, genesis, parameters]
import ../codec/[bounded, guarantees, assurances, report_owned, owned, header, disputes]
import ../codec/work/[package, report]
import ../codec/state/[safrole, consensus, layout, trie, disputes as state_disputes]
import ../state/[store, guarantors, guarantee_credentials]
import ../state/report/[policy, packages]
import ../crypto/primitives

type
  WorkDistributionLimits* = object ## Wire and unique-recipient ceilings accompany the same explicit source/policy budgets used before signing.
    eligibility*: WorkEligibilityLimits
    wireBytes*: ByteLimit
    targets*: ElementLimit
  WorkDistributionError* {.pure.} = enum ## Refusals expose neither a credential prefix nor a default distribution plan.
    Uninitialized, None, InvalidSource, InvalidPolicy, InvalidSlot, UncertainEpoch, LimitExceeded,
    InvalidState, StateFailure, ComponentFailure, DisputeFailure, DecodeFailure, TrailingBytes,
    CredentialFailure, AnchorFailure, PolicyFailure, PipelineFailure, BackendFailure, InvalidIndex
  WorkDistributionInfo* = object ## Fixed facts identify the exact complete source and clock observation used by this qualification.
    head*: genesis.BlockHash
    root*: trie.StateRoot
    observed*, inclusion*, lastSlot*: StateTime
    slot*: GuaranteeSlot
    reportHash*: array[32, byte]
    core*: CoreIndex
    targets*, credentials*, wireBytes*: int
  DistributionData = ref object ## Acyclic immutable provenance retains complete source, actual verified credentials and full anchor evidence together.
    source: StateStoreSnapshot
    credentials: VerifiedGuaranteeCredentials
    anchors: RefinementAnchors
    info: WorkDistributionInfo
    recipients: seq[StateValidator]
    wire: seq[byte]
  CheckedWorkDistribution* = object ## No caller-supplied signature, roster or head stamp can manufacture a successful CE135 qualification.
    data: nil DistributionData
  WorkDistributionResult*[T] = object ## Selected child failures preserve their genuine reason and chapter only.
    case status: WorkDistributionError
    of None: completed: T
    of InvalidState: invalidChapter: StateChapter
    of StateFailure:
      stateChapter: StateChapter
      stateReason: StateStoreError
    of ComponentFailure:
      componentChapter: StateChapter
      componentReason: StateComponentError
    of DisputeFailure: disputeReason: DisputeStateError
    of DecodeFailure: decodeReason: GuaranteeError
    of CredentialFailure: credentialReason: GuaranteeCredentialResult[VerifiedGuaranteeCredentials]
    of AnchorFailure: anchorReason: WorkAnchorResult[RefinementAnchors]
    of PolicyFailure: policyReason: ReportPolicyError
    of PipelineFailure: pipelineReason: ReportPackageError
    else: discard # Local/default refusals contain no payload or invented child outcome.
func error*[T](outcome: WorkDistributionResult[T]): WorkDistributionError =
  ## Observe refusal without granting mutable tag access.
  outcome.status
func value*[T](outcome: WorkDistributionResult[T]): T {.requires: outcome.status ==
    WorkDistributionError.None.} =
  ## Only fully qualified results expose owned evidence or fixed copies.
  outcome.completed
func chapter*[T](outcome: WorkDistributionResult[T]): StateChapter {.requires: outcome.status in {
    WorkDistributionError.InvalidState, WorkDistributionError.StateFailure,
    WorkDistributionError.ComponentFailure}.} =
  ## Distinguish an actual failed canonical chapter from report or credential indices.
  case outcome.status
  of WorkDistributionError.InvalidState: outcome.invalidChapter
  of WorkDistributionError.StateFailure: outcome.stateChapter
  else: outcome.componentChapter
func stateError*[T](outcome: WorkDistributionResult[
    T]): StateStoreError {.requires: outcome.status == WorkDistributionError.StateFailure.} =
  ## Preserve only actual failed complete-store lookups.
  outcome.stateReason
func componentError*[T](outcome: WorkDistributionResult[
    T]): StateComponentError {.requires: outcome.status ==
    WorkDistributionError.ComponentFailure.} =
  ## Preserve the actual time/entropy/roster codec refusal.
  outcome.componentReason
func disputeError*[T](outcome: WorkDistributionResult[
    T]): DisputeStateError {.requires: outcome.status == WorkDistributionError.DisputeFailure.} =
  ## C5 decoding remains distinct from ordinary state components.
  outcome.disputeReason
func decodeError*[T](outcome: WorkDistributionResult[
    T]): GuaranteeError {.requires: outcome.status == WorkDistributionError.DecodeFailure.} =
  ## Expose only a genuine canonical standalone guarantee decoder failure.
  outcome.decodeReason
func credentialError*[T](outcome: WorkDistributionResult[T]): GuaranteeCredentialResult[
    VerifiedGuaranteeCredentials] {.requires: outcome.status ==
    WorkDistributionError.CredentialFailure.} =
  ## Preserve exact assignment/signature/population refusals without a certified prefix.
  outcome.credentialReason
func anchorError*[T](outcome: WorkDistributionResult[T]): WorkAnchorResult[
    RefinementAnchors] {.requires: outcome.status == WorkDistributionError.AnchorFailure.} =
  ## Keep complete recent/lookup-context causes selected by their actual failed stage.
  outcome.anchorReason
func policyError*[T](outcome: WorkDistributionResult[
    T]): ReportPolicyError {.requires: outcome.status == WorkDistributionError.PolicyFailure.} =
  ## The source-bound service/authorization/gas refusal is not a signature failure.
  outcome.policyReason
func pipelineError*[T](outcome: WorkDistributionResult[
    T]): ReportPackageError {.requires: outcome.status == WorkDistributionError.PipelineFailure.} =
  ## Retain actual package uniqueness/dependency/root reasons.
  outcome.pipelineReason
proc distributionInfo*(owner: CheckedWorkDistribution): WorkDistributionResult[
    WorkDistributionInfo] =
  ## Read copied source facts only under the managed graph gate.
  let data = owner.data
  if data == nil: return default(WorkDistributionResult[WorkDistributionInfo])
  WorkDistributionResult[WorkDistributionInfo](status: WorkDistributionError.None,
      completed: data.info)
proc distributionGuarantee*(owner: CheckedWorkDistribution): WorkDistributionResult[Guarantee] =
  ## A copied record retains only the exact report whose credentials were verified; it does not permit modifying this owner.
  let data = owner.data
  if data == nil: return default(WorkDistributionResult[Guarantee])
  WorkDistributionResult[Guarantee](status: WorkDistributionError.None,
      completed: data.credentials.verifiedGuaranteeAt(0).value)
proc distributionTarget*(owner: CheckedWorkDistribution, index: int): WorkDistributionResult[
    StateValidator] =
  ## Copy one actual current/required-next record, never an index into a substitute roster.
  let data = owner.data
  if data == nil: return default(WorkDistributionResult[StateValidator])
  if index < 0 or index >= data.recipients.len:
    return WorkDistributionResult[StateValidator](status: WorkDistributionError.InvalidIndex)
  WorkDistributionResult[StateValidator](status: WorkDistributionError.None,
      completed: data.recipients[index])
proc distributionPayload*(owner: CheckedWorkDistribution): WorkDistributionResult[seq[byte]] =
  ## Produce detached canonical transport bytes before this owner's graphs are frozen by another worker.
  let data = owner.data
  if data == nil: return default(WorkDistributionResult[seq[byte]])
  var bytes = newSeq[byte](data.wire.len)
  for index in 0..<bytes.len: bytes[index] = data.wire[index]
  WorkDistributionResult[seq[byte]](status: WorkDistributionError.None, completed: bytes)
proc readChapter(source: StateStoreSnapshot, chapter: StateChapter, limit: ByteLimit,
    bytes: var seq[byte], failure: var WorkDistributionResult[CheckedWorkDistribution]): bool =
  ## Bound the original complete-state extent before copying and preserve genuine lookup failures.
  let entry = source.lookup(chapterKey(chapter))
  if entry.error != StateStoreError.None:
    failure = WorkDistributionResult[CheckedWorkDistribution](
      status: WorkDistributionError.StateFailure,
      stateChapter: chapter, stateReason: entry.error)
    return false
  if uint64(entry.value.byteLength) > uint64(limit):
    failure = WorkDistributionResult[CheckedWorkDistribution](
        status: WorkDistributionError.LimitExceeded)
    return false
  bytes = entry.value.bytes
  true
proc includeTarget(values: var seq[StateValidator], candidate: StateValidator,
    limit: ElementLimit): bool =
  ## Current/next overlap consumes one identity; vacant GP records are not network recipients.
  let key = array[32, byte](candidate.ed25519)
  if key == default(array[32, byte]) or key == array[32, byte](nullValidator().ed25519): return true
  for index in 0..<values.len:
    if array[32, byte](values[index].ed25519) == key: return true
  if uint64(values.len) >= uint64(limit): return false
  values.add(candidate)
  true
func withinCredentialWindow*(info: WorkDistributionInfo): bool =
  ## Potential next inclusion must precede fixed GP expiry; this scalar check alone grants no source, credential or delivery authority.
  uint32(info.inclusion) <= uint32(info.lastSlot)
proc qualifyWorkDistribution*(wire: openArray[byte], view: ChainView, now: StateTime,
    limits: WorkDistributionLimits): WorkDistributionResult[CheckedWorkDistribution] =
  ## Verify under one managed exclusive lease against actual current complete state; later block admission must still use its own posterior context.
  template fail(reason: WorkDistributionError) =
    return WorkDistributionResult[CheckedWorkDistribution](status: reason)
  result = default(WorkDistributionResult[CheckedWorkDistribution])
  let head = view.bestBlock
  if head.error != GenesisError.None or view.fuzzOnly: fail(WorkDistributionError.InvalidSource)
  let saved = head.value
  let parameters = saved.chainParameters
  if not parameters.valid: fail(WorkDistributionError.InvalidPolicy)
  let cores = parameters.get(coreCount)
  let epoch = parameters.get(epochPeriod)
  let rotation = parameters.get(rotationPeriod)
  if cores < 2 or cores > 341 or epoch == 0 or rotation == 0 or rotation > epoch:
    fail(WorkDistributionError.InvalidPolicy)
  if epoch mod rotation != 0: fail(WorkDistributionError.InvalidPolicy)
  if epoch > uint64(high(uint32)) or rotation > uint64(high(uint32)):
    fail(WorkDistributionError.InvalidPolicy)
  let local = limits.eligibility
  let sameCores = uint64(local.policy.pools.cores) == cores and uint64(
      local.pipeline.queues.cores) == cores
  let sameAvailability = uint64(local.pipeline.availability.guarantee.cores) == cores
  let sameEpoch = uint64(local.pipeline.queues.epochSlots) == epoch
  let sameGas = uint64(local.policy.reportGas) == parameters.get(maxAccumulateGas) and uint64(
      local.policy.refinementGas) == parameters.get(maxRefineGas)
  if not sameCores or not sameAvailability or not sameEpoch or not sameGas: fail(
      WorkDistributionError.InvalidPolicy)
  if uint64(limits.targets) == 0 or uint64(limits.targets) > 2046: fail(
      WorkDistributionError.InvalidPolicy)
  if uint64(wire.len) > uint64(limits.wireBytes): fail(WorkDistributionError.LimitExceeded)
  let config = GuaranteeConfig(cores: CoreCount(cores), validators: ValidatorCount(3*cores),
      maxBytes: limits.wireBytes)
  let decoded = decodeGuarantee(wire, config)
  if decoded.error != GuaranteeError.None:
    return WorkDistributionResult[CheckedWorkDistribution](
        status: WorkDistributionError.DecodeFailure, decodeReason: decoded.error)
  if decoded.value.consumed != wire.len: fail(WorkDistributionError.TrailingBytes)
  let source = saved.stateSnapshot
  var timeBytes, entropyBytes, activeBytes, previousBytes, disputeBytes: seq[byte] = @[]
  if not readChapter(source, StateChapter(11), local.duty.chapterBytes, timeBytes, result): return
  let clock = decodeStateTime(timeBytes)
  if clock.error != StateComponentError.None:
    return WorkDistributionResult[CheckedWorkDistribution](
        status: WorkDistributionError.ComponentFailure, componentChapter: StateChapter(11),
        componentReason: clock.error)
  if clock.value.consumed != timeBytes.len or uint32(clock.value.value) != saved.slot:
    return WorkDistributionResult[CheckedWorkDistribution](
        status: WorkDistributionError.InvalidState, invalidChapter: StateChapter(11))
  if uint32(now) < saved.slot: fail(WorkDistributionError.InvalidSlot)
  if uint64(uint32(now)) div epoch != uint64(saved.slot) div epoch: fail(
      WorkDistributionError.UncertainEpoch)
  let roster = ValidatorStateConfig(cores: CoreCount(cores), validators: ElementLimit(3*cores),
      maxBytes: local.duty.chapterBytes)
  if not readChapter(source, StateChapter(8), local.duty.chapterBytes, activeBytes, result): return
  let active = decodeStateValidators(activeBytes, roster)
  if active.error != StateComponentError.None:
    return WorkDistributionResult[CheckedWorkDistribution](
        status: WorkDistributionError.ComponentFailure, componentChapter: StateChapter(8),
        componentReason: active.error)
  if active.value.consumed != activeBytes.len:
    return WorkDistributionResult[CheckedWorkDistribution](
        status: WorkDistributionError.InvalidState, invalidChapter: StateChapter(8))
  if not readChapter(source, StateChapter(9), local.duty.chapterBytes, previousBytes,
      result): return
  let previous = decodeStateValidators(previousBytes, roster)
  if previous.error != StateComponentError.None:
    return WorkDistributionResult[CheckedWorkDistribution](
        status: WorkDistributionError.ComponentFailure, componentChapter: StateChapter(9),
        componentReason: previous.error)
  if previous.value.consumed != previousBytes.len:
    return WorkDistributionResult[CheckedWorkDistribution](
        status: WorkDistributionError.InvalidState, invalidChapter: StateChapter(9))
  if not readChapter(source, StateChapter(6), local.duty.chapterBytes, entropyBytes, result): return
  let entropy = decodeStateEntropy(entropyBytes)
  if entropy.error != StateComponentError.None:
    return WorkDistributionResult[CheckedWorkDistribution](
        status: WorkDistributionError.ComponentFailure, componentChapter: StateChapter(6),
        componentReason: entropy.error)
  if entropy.value.consumed != entropyBytes.len:
    return WorkDistributionResult[CheckedWorkDistribution](
        status: WorkDistributionError.InvalidState, invalidChapter: StateChapter(6))
  if not readChapter(source, StateChapter(5), local.duty.chapterBytes, disputeBytes, result): return
  let disputes = decodeDisputeState(disputeBytes, DisputeStateConfig(
      perSet: local.duty.disputeItems, totalItems: local.duty.disputeItems,
      maxBytes: local.duty.chapterBytes))
  if disputes.error != DisputeStateError.None:
    return WorkDistributionResult[CheckedWorkDistribution](
        status: WorkDistributionError.DisputeFailure, disputeReason: disputes.error)
  if disputes.value.consumed != disputeBytes.len:
    return WorkDistributionResult[CheckedWorkDistribution](
        status: WorkDistributionError.InvalidState, invalidChapter: StateChapter(5))
  let count = disputes.value.snapshot.disputeStateInfo.value.offenders
  var offenders = newSeq[OffenderKey](count)
  for index in 0..<count:
    # Exact C5 decoding already bounded and ordered every cumulative offender descriptor.
    offenders[index] = disputes.value.snapshot.stateOffenderAt(DisputeStateIndex(index)).value
  let value = decoded.value.value
  let credentials = verifyGuaranteeCredentials([value], active.value.value, previous.value.value,
    entropy.value.value, now, offenders, GuaranteeCredentialConfig(assignments: GuarantorConfig(
        roster: roster, epochSlots: EpochSlots(epoch), rotationSlots: GuarantorRotationSlots(
        rotation), offenders: local.duty.disputeItems), maxBytes: ByteLimit(uint64(wire.len)+1),
        reporters: ElementLimit(3)))
  if credentials.error != GuaranteeCredentialError.None:
    return WorkDistributionResult[CheckedWorkDistribution](
        status: WorkDistributionError.CredentialFailure, credentialReason: credentials)
  let report = value.report
  let header = report.ownedReportInfo.value.header
  let anchors = captureRefinementAnchors(RefinementContext(anchor: header.anchor,
      anchorSlot: header.anchorSlot, stateRoot: header.stateRoot,
      accumulationRoot: header.accumulationRoot, lookupAnchor: header.lookupAnchor,
      lookupSlot: header.lookupSlot, lookupStateRoot: header.lookupStateRoot), view, now, local.anchors)
  if anchors.error != WorkAnchorError.None:
    return WorkDistributionResult[CheckedWorkDistribution](
        status: WorkDistributionError.AnchorFailure, anchorReason: anchors)
  let policy = inspectReportPolicy(report, source, local.policy)
  if policy != ReportPolicyError.None:
    return WorkDistributionResult[CheckedWorkDistribution](
        status: WorkDistributionError.PolicyFailure, policyReason: policy)
  let pipeline = inspectReportPipeline([report], source, anchors.value.refinementHistory.value,
      local.pipeline)
  if pipeline != ReportPackageError.None:
    return WorkDistributionResult[CheckedWorkDistribution](
        status: WorkDistributionError.PipelineFailure, pipelineReason: pipeline)
  var recipients: seq[StateValidator] = @[]
  for index in 0..<active.value.value.validatorCount.value:
    # Current validators always precede any additional next-epoch identities in the private bounded plan.
    let record = active.value.value.validatorAt(StateValidatorIndex(index)).value
    if not includeTarget(recipients, record, limits.targets): fail(
        WorkDistributionError.LimitExceeded)
  if uint64(uint32(now)) mod epoch >= epoch-rotation:
    var pendingBytes: seq[byte] = @[]
    if not readChapter(source, StateChapter(4), local.population.maxBytes, pendingBytes,
        result): return
    let population = local.population
    if uint64(population.validators.cores) != cores or uint64(population.epochSlots) != epoch: fail(
        WorkDistributionError.InvalidPolicy)
    let pending = decodeSafroleState(pendingBytes, population)
    if pending.error != StateComponentError.None:
      return WorkDistributionResult[CheckedWorkDistribution](
          status: WorkDistributionError.ComponentFailure, componentChapter: StateChapter(4),
          componentReason: pending.error)
    if pending.value.consumed != pendingBytes.len:
      return WorkDistributionResult[CheckedWorkDistribution](
          status: WorkDistributionError.InvalidState, invalidChapter: StateChapter(4))
    for index in 0..<pending.value.snapshot.safroleInfo.value.validators:
      # Overlap preserves the current validator's actual routing record; no duplicate key is sent the same guarantee twice.
      let record = pending.value.snapshot.pendingValidatorAt(StateValidatorIndex(index)).value
      if not includeTarget(recipients, record, limits.targets): fail(
          WorkDistributionError.LimitExceeded)
  let length = report.ownedReportInfo.value.consumed
  let hash = blake2b256(wire.toOpenArray(0, length-1))
  if hash.error != CryptoError.None: fail(WorkDistributionError.BackendFailure)
  let start = uint64(uint32(value.slot))-uint64(uint32(value.slot)) mod rotation
  let span = 2*rotation-1 # Positive E4 geometry proves this widened product/subtraction cannot wrap.
  let remaining = uint64(high(uint32))-start
  let last = if span > remaining: uint64(high(uint32)) else: start+span
  var payload = newSeq[byte](wire.len)
  for index in 0..<wire.len: payload[index] = wire[index]
  WorkDistributionResult[CheckedWorkDistribution](status: WorkDistributionError.None,
    completed: CheckedWorkDistribution(data: DistributionData(source: source,
      credentials: credentials.value,
      anchors: anchors.value, recipients: recipients, wire: payload, info: WorkDistributionInfo(
      head: saved.blockHash,
      root: saved.stateRoot, observed: now, inclusion: anchors.value.anchorInfo.value.inclusionSlot,
      slot: value.slot, reportHash: array[32, byte](hash.value),
          core: report.ownedReportInfo.value.core,
      lastSlot: StateTime(uint32(last)), credentials: value.credentialCount, wireBytes: wire.len,
      targets: recipients.len))))
