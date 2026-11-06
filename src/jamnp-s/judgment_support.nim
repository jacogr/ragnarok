# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bind a signed negative CE145 claim to genuine standalone guarantor support under an explicitly selected retained canonical reporting context. This worker capability carries public detached provenance/report/rosters, never an invented availability block or full-map authority.
import ./judgment_claim
from ./assurance_store import AssuranceScanControl, stopped
import ../chain/[genesis, provider, parameters]
import ../codec/[bounded, guarantees, report_owned, disputes, owned]
import ../codec/state/[safrole, consensus, layout, trie, disputes as state_disputes]
import ../state/[store, guarantors, guarantee_support]
import ../crypto/primitives

type
  AuditorRosterHash* = distinct array[32, byte] ## Complete original C8/C9 bytes, including every null/repeated position and public key/metadata field, identify one original auditor cohort.
  JudgmentSupportLimits* = object ## Complete chapter reads, decoders, assignment work and detached output accompany narrower signature-support caps.
    support*: GuaranteeSupportLimits
    rosters*: ValidatorStateConfig
    disputes*: DisputeStateConfig
    readBytes*, workspaceBytes*, retainedBytes*, hashBytes*: ByteLimit
    hashes*: ElementLimit
  JudgmentSupportInfo* = object ## Fixed source identifiers name the actual reporting context; none identifies a fabricated audited/availability block.
    sourceHash*: genesis.BlockHash
    sourceRoot*: trie.StateRoot
    sourceTime*: StateTime
    sourceEpoch*, auditEpoch*: uint64
    report*: DisputeHash
    auditorHash*: AuditorRosterHash
    retainedBytes*: uint64
    auditors*, current*, previous*: int
  SupportData = ref object ## Immutable report/public-roster provenance becomes private origin input; all aliases stay frozen if a subsequent worker borrows it.
    claim: SignedJudgmentClaim
    certificate: VerifiedGuaranteeSupport
    auditors, current, previous: ValidatorStateSnapshot
    parameters: Parameters
    info: JudgmentSupportInfo
  VerifiedJudgmentSupport* = object ## Only actual canonical source lookup and complete original-coordinate signature qualification construct this capability.
    data: nil SupportData
  JudgmentSupportError* {.pure.} = enum ## Refusal never certifies report invalidity, missing-data fault or an accepted supporting prefix.
    Uninitialized, None, InvalidPolicy, InvalidClaim, UnknownSource, SourceMismatch,
    LimitExceeded, InvalidSource, Cancelled, StateFailure, ComponentFailure,
    DisputeFailure, AssignmentFailure, SupportFailure, ReportHashMismatch, HashFailure
  JudgmentSupportResult*[T] = object ## Selected actual codec/planner/signature refusals carry only their genuine child cause.
    case status: JudgmentSupportError
    of None: completed: T
    of HashFailure: hashReason: CryptoError
    of StateFailure: stateReason: StateStoreError
    of ComponentFailure: componentReason: StateComponentError
    of DisputeFailure: disputeReason: DisputeStateError
    of AssignmentFailure: assignmentReason: GuarantorError
    of SupportFailure: supportReason: GuaranteeSupportResult[VerifiedGuaranteeSupport]
    else: discard # Simple/default outcomes contain no report, roster, state or partial support.
func error*[T](outcome: JudgmentSupportResult[T]): JudgmentSupportError =
  ## Inspect the selected status before any extraction.
  outcome.status
func value*[T](outcome: JudgmentSupportResult[T]): T {.requires: outcome.status ==
    JudgmentSupportError.None.} =
  ## Complete success alone exposes a provenance capability or copied metadata.
  outcome.completed
func hashError*[T](outcome: JudgmentSupportResult[T]): CryptoError {.requires: outcome.status ==
    JudgmentSupportError.HashFailure.} =
  ## Preserve the actual whole-roster identity hash failure without publishing a partial original cohort.
  outcome.hashReason
func stateError*[T](outcome: JudgmentSupportResult[
    T]): StateStoreError {.requires: outcome.status == JudgmentSupportError.StateFailure.} =
  ## Missing actual full-state chapters are not replaced with empty rosters or offenders.
  outcome.stateReason
func componentError*[T](outcome: JudgmentSupportResult[
    T]): StateComponentError {.requires: outcome.status == JudgmentSupportError.ComponentFailure.} =
  ## Preserve the original clock/entropy/validator decoder refusal.
  outcome.componentReason
func disputeError*[T](outcome: JudgmentSupportResult[
    T]): DisputeStateError {.requires: outcome.status == JudgmentSupportError.DisputeFailure.} =
  ## Offender state retains its own whole canonical decoder cause.
  outcome.disputeReason
func assignmentError*[T](outcome: JudgmentSupportResult[
    T]): GuarantorError {.requires: outcome.status == JudgmentSupportError.AssignmentFailure.} =
  ## Actual rotation/roster planning never fabricates a usable default table.
  outcome.assignmentReason
func supportError*[T](outcome: JudgmentSupportResult[T]): GuaranteeSupportResult[
    VerifiedGuaranteeSupport] {.requires: outcome.status == JudgmentSupportError.SupportFailure.} =
  ## Keep actual canonical shape, coordinate and Ed25519 failure separate from data unavailability or report truth.
  outcome.supportReason
func valid*(limits: JudgmentSupportLimits): bool =
  ## Caller settings cannot change the chain's epoch/rotation; they only bound whole input/output and the maintained actual-source planner.
  limits.support.valid and uint64(limits.rosters.cores) == uint64(limits.support.wire.cores) and
    uint64(limits.rosters.validators) == uint64(limits.support.wire.validators) and
    uint64(limits.rosters.maxBytes) > 0 and uint64(limits.rosters.maxBytes) <= 1024'u64*1024 and
    uint64(limits.disputes.maxBytes) > 0 and uint64(limits.disputes.maxBytes) <= 8'u64*1024*1024 and
    uint64(limits.disputes.totalItems) > 0 and uint64(limits.disputes.totalItems) <= 1000000 and
    uint64(limits.disputes.perSet) > 0 and uint64(limits.disputes.perSet) <= uint64(
        limits.disputes.totalItems) and
    uint64(limits.readBytes) > 0 and uint64(limits.readBytes) <= 16'u64*1024*1024 and
    uint64(limits.workspaceBytes) > 0 and uint64(limits.workspaceBytes) <= 128'u64*1024*1024 and
    uint64(limits.retainedBytes) > 0 and uint64(limits.retainedBytes) <= 16'u64*1024*1024 and
    uint64(limits.hashBytes) > 0 and uint64(limits.hashBytes) <= 16'u64*1024*1024 and
    uint64(limits.hashes) > 0 and uint64(limits.hashes) <= 4096
func valid*(support: VerifiedJudgmentSupport): bool =
  ## Copied source/hash/validity metadata cannot initialize this private tag.
  support.data != nil
proc supportInfo*(support: VerifiedJudgmentSupport): JudgmentSupportResult[JudgmentSupportInfo] =
  ## Read fixed provenance facts only while every alias is idle or under the same exact worker lease.
  let data = support.data
  if data == nil: return JudgmentSupportResult[JudgmentSupportInfo](
      status: JudgmentSupportError.Uninitialized)
  JudgmentSupportResult[JudgmentSupportInfo](status: JudgmentSupportError.None,
      completed: data.info)
proc supportClaim*(support: VerifiedJudgmentSupport): JudgmentSupportResult[SignedJudgmentClaim] =
  ## A plain fixed signed claim retains no graph aliases or replacement signature-valid flag.
  let data = support.data
  if data == nil: return JudgmentSupportResult[SignedJudgmentClaim](
      status: JudgmentSupportError.Uninitialized)
  JudgmentSupportResult[SignedJudgmentClaim](status: JudgmentSupportError.None,
      completed: data.claim)
proc supportCertificate*(support: VerifiedJudgmentSupport): JudgmentSupportResult[
    VerifiedGuaranteeSupport] =
  ## This narrower report/role owner cannot substitute for full inclusion or a private completed evaluation.
  let data = support.data
  if data == nil: return JudgmentSupportResult[VerifiedGuaranteeSupport](
      status: JudgmentSupportError.Uninitialized)
  JudgmentSupportResult[VerifiedGuaranteeSupport](status: JudgmentSupportError.None,
      completed: data.certificate)
proc supportAuditors*(support: VerifiedJudgmentSupport): JudgmentSupportResult[
    ValidatorStateSnapshot] =
  ## Preserve the actual independently selected judgment epoch, including every original null/repeated position.
  let data = support.data
  if data == nil: return JudgmentSupportResult[ValidatorStateSnapshot](
      status: JudgmentSupportError.Uninitialized)
  JudgmentSupportResult[ValidatorStateSnapshot](status: JudgmentSupportError.None,
      completed: data.auditors)
proc supportParameters*(support: VerifiedJudgmentSupport): JudgmentSupportResult[Parameters] =
  ## Exact fixed source parameters stay independent of later heads and caller replacement geometry.
  let data = support.data
  if data == nil: return JudgmentSupportResult[Parameters](
      status: JudgmentSupportError.Uninitialized)
  JudgmentSupportResult[Parameters](status: JudgmentSupportError.None, completed: data.parameters)
proc supportRoster*(support: VerifiedJudgmentSupport, previous: bool): JudgmentSupportResult[
    ValidatorStateSnapshot] =
  ## These are explicitly named actual reporting-context rosters, not a guessed historical assurer epoch selected only by population.
  let data = support.data
  if data == nil: return JudgmentSupportResult[ValidatorStateSnapshot](
      status: JudgmentSupportError.Uninitialized)
  JudgmentSupportResult[ValidatorStateSnapshot](status: JudgmentSupportError.None,
    completed: if previous: data.previous else: data.current)
proc matchesSource*(support: VerifiedJudgmentSupport, source: BlockSnapshotResult): bool =
  ## A private origin must independently bind this qualified reporting context to its own canonical full map and whole parameter profile.
  let data = support.data
  if data == nil or source.error != GenesisError.None: return false
  let actual = source.value
  array[32, byte](actual.blockHash) == array[32, byte](data.info.sourceHash) and
    array[32, byte](actual.stateRoot) == array[32, byte](data.info.sourceRoot) and
    actual.slot == uint64(uint32(data.info.sourceTime)) and
    data.parameters.sameParameterProfile(actual.chainParameters)
proc qualifyJudgmentSupportAt*(view: ChainView, sourceHash: genesis.BlockHash,
    claim: SignedJudgmentClaim, report: OwnedReport, limits: JudgmentSupportLimits,
    control: AssuranceScanControl = default(AssuranceScanControl)): JudgmentSupportResult[
        VerifiedJudgmentSupport] =
  ## The selected block is a genuine retained canonical reporting context; no caller clock or key table is accepted. A refusal for this context makes no statement about other historical contexts or report truth.
  if not limits.valid: return JudgmentSupportResult[VerifiedJudgmentSupport](
      status: JudgmentSupportError.InvalidPolicy)
  if view.fuzzOnly or not claim.valid or claim.judgmentRecord.valid:
    return JudgmentSupportResult[VerifiedJudgmentSupport](status: JudgmentSupportError.InvalidClaim)
  if control.stopped: return JudgmentSupportResult[VerifiedJudgmentSupport](
      status: JudgmentSupportError.Cancelled)
  let facts = claim.claimInfo
  let receipt = view.blockAt(facts.sourceHead)
  let source = view.blockAt(sourceHash)
  if receipt.error != GenesisError.None or source.error != GenesisError.None:
    return JudgmentSupportResult[VerifiedJudgmentSupport](
        status: JudgmentSupportError.UnknownSource)
  if array[32, byte](receipt.value.stateRoot) != array[32, byte](facts.sourceRoot) or
      receipt.value.slot != uint64(uint32(facts.sourceTime)):
    return JudgmentSupportResult[VerifiedJudgmentSupport](
        status: JudgmentSupportError.SourceMismatch)
  let parameters = source.value.chainParameters
  let epochSlots = parameters.get(epochPeriod)
  let rotation = parameters.get(rotationPeriod)
  if not parameters.sameParameterProfile(receipt.value.chainParameters) or epochSlots == 0 or
      rotation == 0 or rotation > epochSlots or epochSlots mod rotation != 0 or
      parameters.get(coreCount) != uint64(limits.rosters.cores):
    return JudgmentSupportResult[VerifiedJudgmentSupport](
        status: JudgmentSupportError.SourceMismatch)
  let receiptEpoch = receipt.value.slot div epochSlots
  let originalEpoch = uint64(uint32(facts.epoch))
  if originalEpoch != receiptEpoch and (receiptEpoch == 0 or originalEpoch != receiptEpoch-1):
    return JudgmentSupportResult[VerifiedJudgmentSupport](
        status: JudgmentSupportError.SourceMismatch)
  let auditChapter = if originalEpoch == receiptEpoch: StateChapter(8) else: StateChapter(9)
  let auditorValue = receipt.value.stateSnapshot.lookup(chapterKey(auditChapter))
  if auditorValue.error != StateStoreError.None:
    return JudgmentSupportResult[VerifiedJudgmentSupport](status: JudgmentSupportError.StateFailure,
        stateReason: auditorValue.error)
  let state = source.value.stateSnapshot
  var readBytes = uint64(auditorValue.value.byteLength)
  if readBytes > uint64(limits.rosters.maxBytes) or readBytes > uint64(limits.readBytes):
    return JudgmentSupportResult[VerifiedJudgmentSupport](
        status: JudgmentSupportError.LimitExceeded)
  for chapter in [5, 6, 8, 9, 11]:
    # Every actual clock/entropy/roster/offender chapter and the original audit roster is admitted before any copy, hash or plan allocation.
    let value = state.lookup(chapterKey(StateChapter(chapter)))
    if value.error != StateStoreError.None:
      return JudgmentSupportResult[VerifiedJudgmentSupport](
          status: JudgmentSupportError.StateFailure, stateReason: value.error)
    let length = uint64(value.value.byteLength)
    if length > uint64(limits.readBytes)-readBytes or
        ((chapter == 8 or chapter == 9) and length > uint64(limits.rosters.maxBytes)) or
        (chapter == 5 and length > uint64(limits.disputes.maxBytes)):
      return JudgmentSupportResult[VerifiedJudgmentSupport](
          status: JudgmentSupportError.LimitExceeded)
    readBytes += length
  let described = report.ownedReportInfo
  if described.error != OwnershipError.None:
    return JudgmentSupportResult[VerifiedJudgmentSupport](
        status: JudgmentSupportError.InvalidSource)
  if sizeof(StateValidator) > 512:
    return JudgmentSupportResult[VerifiedJudgmentSupport](
        status: JudgmentSupportError.LimitExceeded)
  let reportBytes = uint64(described.value.consumed)
  let shuffleHashes = 2*((uint64(limits.rosters.validators)+7) div 8)
  if shuffleHashes+2 > uint64(limits.hashes) or shuffleHashes*36+reportBytes+uint64(
      auditorValue.value.byteLength) > uint64(limits.hashBytes):
    return JudgmentSupportResult[VerifiedJudgmentSupport](
        status: JudgmentSupportError.LimitExceeded)
  # Source reads<=16MiB, report copies<=the support wire cap, and at most3072 fixed public rows prove these aggregate terms fit uint64.
  let rows = uint64(limits.rosters.validators)*3
  let retained = reportBytes+65536+rows*512
  if retained > uint64(limits.retainedBytes) or
      4*readBytes+uint64(limits.support.workspaceBytes)+retained+65536 > uint64(
          limits.workspaceBytes):
    return JudgmentSupportResult[VerifiedJudgmentSupport](
        status: JudgmentSupportError.LimitExceeded)
  let auditorBytes = auditorValue.value.bytes
  let decodedAuditors = decodeStateValidators(auditorBytes, limits.rosters)
  if decodedAuditors.error != StateComponentError.None:
    return JudgmentSupportResult[VerifiedJudgmentSupport](
        status: JudgmentSupportError.ComponentFailure, componentReason: decodedAuditors.error)
  if decodedAuditors.value.consumed != auditorBytes.len:
    return JudgmentSupportResult[VerifiedJudgmentSupport](
        status: JudgmentSupportError.InvalidSource)
  let auditors = decodedAuditors.value.value
  let selected = auditors.validatorAt(StateValidatorIndex(uint64(uint16(facts.validator))))
  if selected.error != StateComponentError.None or auditors.validatorCount.value !=
      facts.population:
    return JudgmentSupportResult[VerifiedJudgmentSupport](
        status: JudgmentSupportError.SourceMismatch)
  if array[32, byte](selected.value.ed25519) != array[32, byte](facts.auditor.ed25519):
    return JudgmentSupportResult[VerifiedJudgmentSupport](
        status: JudgmentSupportError.SourceMismatch)
  let clockBytes = state.lookup(chapterKey(StateChapter(11))).value.bytes
  let clock = decodeStateTime(clockBytes)
  if clock.error != StateComponentError.None:
    return JudgmentSupportResult[VerifiedJudgmentSupport](
        status: JudgmentSupportError.ComponentFailure, componentReason: clock.error)
  if clock.value.consumed != clockBytes.len or uint64(uint32(clock.value.value)) !=
      source.value.slot:
    return JudgmentSupportResult[VerifiedJudgmentSupport](
        status: JudgmentSupportError.InvalidSource)
  let activeBytes = state.lookup(chapterKey(StateChapter(8))).value.bytes
  let previousBytes = state.lookup(chapterKey(StateChapter(9))).value.bytes
  let active = decodeStateValidators(activeBytes, limits.rosters)
  let previous = decodeStateValidators(previousBytes, limits.rosters)
  if active.error != StateComponentError.None:
    return JudgmentSupportResult[VerifiedJudgmentSupport](
        status: JudgmentSupportError.ComponentFailure, componentReason: active.error)
  if previous.error != StateComponentError.None:
    return JudgmentSupportResult[VerifiedJudgmentSupport](
        status: JudgmentSupportError.ComponentFailure, componentReason: previous.error)
  if active.value.consumed != activeBytes.len or previous.value.consumed != previousBytes.len:
    return JudgmentSupportResult[VerifiedJudgmentSupport](
        status: JudgmentSupportError.InvalidSource)
  let entropyBytes = state.lookup(chapterKey(StateChapter(6))).value.bytes
  let entropy = decodeStateEntropy(entropyBytes)
  if entropy.error != StateComponentError.None:
    return JudgmentSupportResult[VerifiedJudgmentSupport](
        status: JudgmentSupportError.ComponentFailure, componentReason: entropy.error)
  if entropy.value.consumed != entropyBytes.len:
    return JudgmentSupportResult[VerifiedJudgmentSupport](
        status: JudgmentSupportError.InvalidSource)
  let disputeBytes = state.lookup(chapterKey(StateChapter(5))).value.bytes
  let disputes = decodeDisputeState(disputeBytes, limits.disputes)
  if disputes.error != DisputeStateError.None:
    return JudgmentSupportResult[VerifiedJudgmentSupport](
        status: JudgmentSupportError.DisputeFailure, disputeReason: disputes.error)
  if disputes.value.consumed != disputeBytes.len:
    return JudgmentSupportResult[VerifiedJudgmentSupport](
        status: JudgmentSupportError.InvalidSource)
  let count = disputes.value.snapshot.disputeStateInfo.value.offenders
  var offenders = newSeq[OffenderKey](count)
  for ordinal in 0..<count:
    # Canonically decoded cumulative offenders feed the maintained actual-source rotation planner unchanged.
    offenders[ordinal] = disputes.value.snapshot.stateOffenderAt(DisputeStateIndex(uint64(
        ordinal))).value
  if control.stopped: return JudgmentSupportResult[VerifiedJudgmentSupport](
      status: JudgmentSupportError.Cancelled)
  let config = GuarantorConfig(roster: limits.rosters, epochSlots: EpochSlots(epochSlots),
    rotationSlots: GuarantorRotationSlots(rotation), offenders: limits.disputes.totalItems)
  let planned = planGuarantors(active.value.value, previous.value.value, entropy.value.value,
    clock.value.value, offenders, config)
  if planned.error != GuarantorError.None:
    return JudgmentSupportResult[VerifiedJudgmentSupport](
        status: JudgmentSupportError.AssignmentFailure, assignmentReason: planned.error)
  let record = claim.judgmentRecord
  let guarantee = Guarantee(report: report, slot: record.slot,
    credentialCount: record.credentialCount, credentials: record.credentials)
  let certified = verifyGuaranteeSupport(guarantee, planned.value, limits.support)
  if certified.error != GuaranteeSupportError.None:
    return JudgmentSupportResult[VerifiedJudgmentSupport](
        status: JudgmentSupportError.SupportFailure, supportReason: certified)
  if array[32, byte](certified.value.supportInfo.value.report) != array[32, byte](record.report):
    return JudgmentSupportResult[VerifiedJudgmentSupport](
        status: JudgmentSupportError.ReportHashMismatch)
  if control.stopped: return JudgmentSupportResult[VerifiedJudgmentSupport](
      status: JudgmentSupportError.Cancelled)
  let auditorHash = blake2b256(auditorBytes)
  if auditorHash.error != CryptoError.None:
    return JudgmentSupportResult[VerifiedJudgmentSupport](status: JudgmentSupportError.HashFailure,
        hashReason: auditorHash.error)
  if control.stopped: return JudgmentSupportResult[VerifiedJudgmentSupport](
      status: JudgmentSupportError.Cancelled)
  JudgmentSupportResult[VerifiedJudgmentSupport](status: JudgmentSupportError.None,
    completed: VerifiedJudgmentSupport(data: SupportData(claim: claim, certificate: certified.value,
      parameters: parameters, auditors: auditors, current: active.value.value,
      previous: previous.value.value,
      info: JudgmentSupportInfo(sourceHash: source.value.blockHash,
        sourceRoot: source.value.stateRoot,
        sourceTime: clock.value.value, sourceEpoch: source.value.slot div epochSlots,
        auditEpoch: originalEpoch, report: record.report, auditorHash: AuditorRosterHash(array[32,
            byte](auditorHash.value)), retainedBytes: retained,
        auditors: auditors.validatorCount.value, current: active.value.value.validatorCount.value,
        previous: previous.value.value.validatorCount.value))))
