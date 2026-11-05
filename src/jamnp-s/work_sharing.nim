# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## CE134 receiving executes the exact whole bundle on one managed lease, checking both guarantors before PVM work.
## No network callback may invoke this state/crypto/PVM pipeline. One returned signature is not a fully guaranteed report.
import ./[sharing_wire, work_submission, work_duty, work_anchors, work_population, work_report,
    work_eligibility, work_signer]
import ../chain/[provider, genesis, parameters]
import ../codec/bounded
import ../codec/work/[package, report, digest]
import ../codec/state/safrole
import ../state/input_refinement
import "../state/import/inputs" as import_inputs
import ../state/computed/[guarantee, report]
import ../state/availability/specifier
import "../state/export/erasure" as export_erasure
import ../state/[bundle_erasure, auditable_bundle]
import ../state/erasure/layout

type
  WorkSharingLimits* = object ## Independent explicit resource ceilings supplement the selected source's actual consensus gas limits.
    packageBytes*, bundleBytes*: ByteLimit
    submission*: WorkSubmissionLimits
    execution*: InputRefinementLimits
    report*: WorkReportLimits
    eligibility*: WorkEligibilityLimits
  WorkSharingError* {.pure.} = enum ## Refusals contain no decoded source, computed prefix or signature authority.
    Uninitialized, None, InvalidSource, InvalidPolicy, InvalidMessage, InvalidPeer, InvalidShards,
    LimitExceeded, PackageFailure, HeaderFailure, DutyFailure, AnchorFailure, PopulationFailure,
    AuthorizationFailure, BodyFailure, RefinementFailure, ReportFailure, EligibilityFailure, SigningFailure
  SharingDutySide* {.pure.} = enum Peer, Local ## Host-authenticated sender and actual local transport identity have separate basic obligations.
  DecodedSharedWork = object ## Private bounded offsets remain borrowed from this call's exact stable whole-bundle input.
    header: WorkSubmissionHeader
    extrinsics, segments, proofs: int
  WorkSharingResult*[T] = object ## Genuine child failures preserve their selected domains; only full success exposes a value.
    case status: WorkSharingError
    of None: completed: T
    of PackageFailure: packageReason: PackageError
    of HeaderFailure: headerReason: WorkSubmissionResult[WorkSubmissionHeader]
    of DutyFailure:
      dutySide: SharingDutySide
      dutyReason: WorkDutyResult[WorkDuty]
    of AnchorFailure: anchorReason: WorkAnchorResult[AnchoredWorkContext]
    of PopulationFailure: populationReason: WorkPopulationResult[WorkShardWindow]
    of AuthorizationFailure: authorizationReason: WorkSubmissionResult[AuthorizedWorkSubmission]
    of BodyFailure: bodyReason: WorkSubmissionResult[VerifiedImportInputs]
    of RefinementFailure: refinementReason: InputRefinementResult[InputRefinement]
    of ReportFailure: reportReason: WorkReportResult
    of EligibilityFailure: eligibilityReason: WorkEligibilityResult[EligibleWorkGuarantee]
    of SigningFailure: signingReason: WorkSignerResult[SignedWorkContribution]
    else: discard # Local/default refusals expose no accepted prefix or fabricated child.
func error*[T](outcome: WorkSharingResult[T]): WorkSharingError =
  ## Observe failure without retagging ownership.
  outcome.status
func value*[T](outcome: WorkSharingResult[T]): T {.requires: outcome.status ==
    WorkSharingError.None.} =
  ## Only complete receiving/response encoding has an extractable result.
  outcome.completed
func packageError*[T](outcome: WorkSharingResult[T]): PackageError {.requires: outcome.status ==
    WorkSharingError.PackageFailure.} =
  ## Preserve the original package-prefix decoder refusal.
  outcome.packageReason
func headerError*[T](outcome: WorkSharingResult[T]): WorkSubmissionResult[
    WorkSubmissionHeader] {.requires: outcome.status == WorkSharingError.HeaderFailure.} =
  ## Preserve exact structural mapping/header failures without a decoded prefix.
  outcome.headerReason
func dutyError*[T](outcome: WorkSharingResult[T]): WorkDutyResult[
    WorkDuty] {.requires: outcome.status == WorkSharingError.DutyFailure.} =
  ## Expose only the genuine failed assignment check.
  outcome.dutyReason
func side*[T](outcome: WorkSharingResult[T]): SharingDutySide {.requires: outcome.status ==
    WorkSharingError.DutyFailure.} =
  ## Identify which actual authenticated party failed its own obligation.
  outcome.dutySide
func anchorError*[T](outcome: WorkSharingResult[T]): WorkAnchorResult[
    AnchoredWorkContext] {.requires: outcome.status == WorkSharingError.AnchorFailure.} =
  ## Preserve complete recent/lookup context refusal.
  outcome.anchorReason
func populationError*[T](outcome: WorkSharingResult[T]): WorkPopulationResult[
    WorkShardWindow] {.requires: outcome.status == WorkSharingError.PopulationFailure.} =
  ## Preserve genuinely unavailable or uncertain anchor-window state.
  outcome.populationReason
func authorizationError*[T](outcome: WorkSharingResult[T]): WorkSubmissionResult[
    AuthorizedWorkSubmission] {.requires: outcome.status ==
    WorkSharingError.AuthorizationFailure.} =
  ## No body or signature is granted by failed pool/guest authorization.
  outcome.authorizationReason
func bodyError*[T](outcome: WorkSharingResult[T]): WorkSubmissionResult[
    VerifiedImportInputs] {.requires: outcome.status == WorkSharingError.BodyFailure.} =
  ## Preserve actual extrinsic/import/mapping/proof refusal.
  outcome.bodyReason
func refinementError*[T](outcome: WorkSharingResult[T]): InputRefinementResult[
    InputRefinement] {.requires: outcome.status == WorkSharingError.RefinementFailure.} =
  ## Failed computation cannot expose partial item outputs.
  outcome.refinementReason
func reportError*[T](outcome: WorkSharingResult[T]): WorkReportResult {.requires: outcome.status ==
    WorkSharingError.ReportFailure.} =
  ## Preserve actual availability/report/transcript preparation failure.
  outcome.reportReason
func eligibilityError*[T](outcome: WorkSharingResult[T]): WorkEligibilityResult[
    EligibleWorkGuarantee] {.requires: outcome.status == WorkSharingError.EligibilityFailure.} =
  ## Preserve full pre-signing report eligibility failure.
  outcome.eligibilityReason
func signingError*[T](outcome: WorkSharingResult[T]): WorkSignerResult[
    SignedWorkContribution] {.requires: outcome.status == WorkSharingError.SigningFailure.} =
  ## A key mismatch/backend error never exposes a signature.
  outcome.signingReason
proc decodeShared(first, bundle: openArray[byte], config: PackageConfig): WorkSharingResult[
    DecodedSharedWork] =
  ## The caller has preflighted complete input sizes; package and body extents are proved before any offset addition.
  let parsed = decodeWorkPackage(bundle, config)
  if parsed.error != PackageError.None:
    return WorkSharingResult[DecodedSharedWork](status: WorkSharingError.PackageFailure,
        packageReason: parsed.error)
  let size = parsed.value.consumed
  if size <= 0 or size > bundle.len:
    return WorkSharingResult[DecodedSharedWork](status: WorkSharingError.InvalidMessage)
  var normalized = newSeq[byte](first.len-2)
  normalized[0] = first[0]
  normalized[1] = first[1]
  for index in 4..<first.len: normalized[index-2] = first[index]
  let header = decodeWorkSubmission(WorkSubmissionKind.Bundle, normalized,
    bundle.toOpenArray(0, size-1), config)
  if header.error != WorkSubmissionError.None:
    return WorkSharingResult[DecodedSharedWork](status: WorkSharingError.HeaderFailure,
        headerReason: header)
  let info = header.value.submissionInfo.value
  if info.extrinsicBytes > bundle.len-size:
    return WorkSharingResult[DecodedSharedWork](status: WorkSharingError.InvalidMessage)
  let segments = size+info.extrinsicBytes
  if info.segmentBytes > bundle.len-segments:
    return WorkSharingResult[DecodedSharedWork](status: WorkSharingError.InvalidMessage)
  let proofs = segments+info.segmentBytes
  WorkSharingResult[DecodedSharedWork](status: WorkSharingError.None,
    completed: DecodedSharedWork(header: header.value, extrinsics: size, segments: segments,
        proofs: proofs))
proc receiveSharedWork*(request: SharedWorkRequest, view: ChainView, local, peer: StateEdKey,
    now: StateTime, signer: WorkSigner, limits: WorkSharingLimits): WorkSharingResult[
        SignedWorkContribution] =
  ## Host identities are actual cached TLS observations, never fields supplied by the sharing packet.
  ## This entire call, including every source/signer alias, belongs to one exclusive managed CPU lease.
  template fail(reason: WorkSharingError) =
    return WorkSharingResult[SignedWorkContribution](status: reason)
  let sizes = request.sharingInfo
  if sizes.error != SharingWireError.None: fail(WorkSharingError.InvalidMessage)
  if uint64(sizes.value.bundleBytes) > uint64(limits.bundleBytes): fail(
      WorkSharingError.LimitExceeded)
  if uint64(limits.packageBytes) > uint64(MaxBundleBytes): fail(WorkSharingError.InvalidPolicy)
  let head = view.bestBlock
  if head.error != GenesisError.None or view.fuzzOnly: fail(WorkSharingError.InvalidSource)
  if array[32, byte](peer) == array[32, byte](local): fail(WorkSharingError.InvalidPeer)
  let first = request.firstMessage
  let core = CoreIndex(uint64(first[0]) or (uint64(first[1]) shl 8))
  let shards = uint16(first[2]) or (uint16(first[3]) shl 8)
  if shards < 6 or shards > 1023 or shards mod 3 != 0: fail(WorkSharingError.InvalidShards)
  let source = head.value.stateSnapshot
  let parameters = head.value.chainParameters
  let sender = captureWorkDuty(source, parameters, workRecipient(peer, now), core,
      limits.eligibility.duty)
  if sender.error != WorkDutyError.None:
    return WorkSharingResult[SignedWorkContribution](status: WorkSharingError.DutyFailure,
      dutySide: SharingDutySide.Peer, dutyReason: sender)
  let recipient = captureWorkDuty(source, parameters, workRecipient(local, now), core,
      limits.eligibility.duty)
  if recipient.error != WorkDutyError.None:
    return WorkSharingResult[SignedWorkContribution](status: WorkSharingError.DutyFailure,
      dutySide: SharingDutySide.Local, dutyReason: recipient)
  let bundle = request.bundleMessage
  let config = PackageConfig(refineGas: Gas(parameters.get(maxRefineGas)),
    accumulateGas: Gas(parameters.get(maxAccumulateGas)), maxBytes: limits.packageBytes)
  let decoded = decodeShared(first, bundle, config)
  if decoded.error == WorkSharingError.PackageFailure:
    return WorkSharingResult[SignedWorkContribution](status: WorkSharingError.PackageFailure,
        packageReason: decoded.packageError)
  if decoded.error == WorkSharingError.HeaderFailure:
    return WorkSharingResult[SignedWorkContribution](status: WorkSharingError.HeaderFailure,
        headerReason: decoded.headerError)
  if decoded.error != WorkSharingError.None: fail(WorkSharingError.InvalidMessage)
  let original = decoded.value.header
  let anchors = captureWorkAnchors(original, view, now, limits.eligibility.anchors)
  if anchors.error != WorkAnchorError.None:
    return WorkSharingResult[SignedWorkContribution](status: WorkSharingError.AnchorFailure,
        anchorReason: anchors)
  let population = captureWorkPopulation(anchors.value, original, view,
      limits.eligibility.population)
  if population.error != WorkPopulationError.None:
    return WorkSharingResult[SignedWorkContribution](status: WorkSharingError.PopulationFailure,
        populationReason: population)
  if not population.value.accepts(ErasureShards(shards), core): fail(WorkSharingError.InvalidShards)
  let authorized = authorizeWorkSubmission(original, source, parameters, limits.submission)
  if authorized.error != WorkSubmissionError.None:
    return WorkSharingResult[SignedWorkContribution](status: WorkSharingError.AuthorizationFailure,
        authorizationReason: authorized)
  let parts = decoded.value
  let inputs = completeBundleSubmission(authorized.value,
    bundle.toOpenArray(parts.extrinsics, parts.segments-1),
    bundle.toOpenArray(parts.segments, parts.proofs-1),
    bundle.toOpenArray(parts.proofs, bundle.high), limits.submission)
  if inputs.error != WorkSubmissionError.None:
    return WorkSharingResult[SignedWorkContribution](status: WorkSharingError.BodyFailure,
        bodyReason: inputs)
  let refined = runInputRefinement(source, inputs.value, core, parameters, limits.execution)
  if refined.error != InputRefinementError.None:
    return WorkSharingResult[SignedWorkContribution](status: WorkSharingError.RefinementFailure,
        refinementReason: refined)
  let computed = prepareWorkReport(refined.value, ErasureShards(shards), limits.report)
  if computed.error != WorkReportError.None:
    return WorkSharingResult[SignedWorkContribution](status: WorkSharingError.ReportFailure,
        reportReason: computed)
  let qualified = qualifyWorkGuarantee(computed.value, original, source, view, local, now,
      limits.eligibility)
  if qualified.error != WorkEligibilityError.None:
    return WorkSharingResult[SignedWorkContribution](status: WorkSharingError.EligibilityFailure,
        eligibilityReason: qualified)
  let signed = signer.signWorkContribution(qualified.value)
  if signed.error != WorkSignerError.None:
    return WorkSharingResult[SignedWorkContribution](status: WorkSharingError.SigningFailure,
        signingReason: signed)
  WorkSharingResult[SignedWorkContribution](status: WorkSharingError.None, completed: signed.value)
proc sharingResponse*(contribution: SignedWorkContribution): WorkSharingResult[array[
    SharingResponseBytes, byte]] =
  ## Encode only a genuine original contribution; neither a caller-supplied hash nor signature can replace its checked transcript.
  let info = contribution.contributionInfo
  if info.error != WorkSignerError.None:
    return WorkSharingResult[array[SharingResponseBytes, byte]](
        status: WorkSharingError.InvalidSource)
  let transcript = contribution.contributionTranscript.value
  let message = array[45, byte](transcript.computedGuaranteeMessage.value)
  let credential = contribution.contributionCredential.value
  let signature = array[64, byte](credential.signature)
  var response = default(array[SharingResponseBytes, byte])
  for index in 0..<32: response[index] = message[13+index]
  for index in 0..<64: response[32+index] = signature[index]
  WorkSharingResult[array[SharingResponseBytes, byte]](status: WorkSharingError.None,
      completed: response)

proc prepareWorkSharing*(contribution: SignedWorkContribution,
    maximum: ByteLimit): WorkSharingResult[SharedWorkRequest] =
  ## Encode the exact original bundle/mappings after preflight; all canonical aliases remain on the managed CPU lease.
  let selected = contribution.contributionTranscript
  if selected.error != WorkSignerError.None:
    return WorkSharingResult[SharedWorkRequest](status: WorkSharingError.InvalidSource)
  let computed = selected.value.computedGuaranteeReport.value
  let available = computed.computedReportSource.value
  let erasure = available.availabilitySource.value.exportErasureSource.value
  let bundle = erasure.bundleErasureSource.value.layoutSource.value
  let size = uint64(bundle.bundleInfo.value.length)
  if size > uint64(maximum) or size > uint64(MaxSharingBundleBytes):
    return WorkSharingResult[SharedWorkRequest](status: WorkSharingError.LimitExceeded)
  let executed = bundle.bundleSource.value
  let lookup = executed.inputRefinementSource.value.importInputsLookup.value
  if lookup.len > 8:
    return WorkSharingResult[SharedWorkRequest](status: WorkSharingError.InvalidSource)
  let info = computed.computedReportInfo.value
  let core = uint64(info.core)
  if core > 65535:
    return WorkSharingResult[SharedWorkRequest](status: WorkSharingError.InvalidSource)
  let shards = uint16(info.header.erasureShards)
  var first = newSeq[byte](5+lookup.len*64)
  first[0] = byte(core and 255)
  first[1] = byte(core shr 8)
  first[2] = byte(shards and 255)
  first[3] = byte(shards shr 8)
  first[4] = byte(lookup.len) # Counts0..8 use the single-octet canonical natural encoding.
  for entry in 0..<lookup.len:
    # Exact original verified mappings retain package/root pairing and canonical order.
    for octet in 0..<32:
      first[5+entry*64+octet] = lookup[entry].packageHash.bytes[octet]
      first[37+entry*64+octet] = lookup[entry].segmentRoot.bytes[octet]
  let captured = captureSharedWork(first, bundle.bundleBytes.value)
  if captured.error != SharingWireError.None:
    return WorkSharingResult[SharedWorkRequest](status: WorkSharingError.InvalidMessage)
  WorkSharingResult[SharedWorkRequest](status: WorkSharingError.None, completed: captured.value)
