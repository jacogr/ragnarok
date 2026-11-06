# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Private audit execution origins pin the actual complete predecessor and its parameters alongside authenticated available work. They are source-bearing worker objects: all aliases remain frozen through exact collection or joined cancellation.
import ./[audit_context, judgment_support]
import ../codec/state/[safrole, consensus, layout]
from ./assurance_store import AssuranceScanControl, stopped
import ../chain/[genesis, provider, parameters, reports]
import ../codec/[bounded, owned, report_owned, header, guarantees]
import ../codec/state/trie as state_trie
import ../state/[store, guarantee_support]

type
  AuditOriginLimits* = object ## Logical entry/node/value ceilings bound retained full state independently of source-free context output budgets.
    entries*: ElementLimit
    nodes*: TrieNodeLimit
    valueBytes*: ByteLimit
  AuditOriginInfo* = object ## Detached fixed facts can be cached before worker publication; they grant no execution or signing authority.
    blockHash*, parentHash*: genesis.BlockHash
    parentRoot*: state_trie.StateRoot
    entries*, reports*: int
    nodes*, valueBytes*: uint64
  OriginData = ref object ## Acyclic immutable ownership pins one genuine full parent for all reports from its block, without copying or replacing its map.
    context: AuditContext
    state: StateStoreSnapshot
    parameters: Parameters
    info: AuditOriginInfo
  AuditBlockOrigin* = object ## Defaults contain no full state, parameter profile or actual available report set.
    data: nil OriginData
  AuditBlockReference* = object ## An optional fixed audited-block identity never invents an availability block for a disputed-only report.
    present: bool
    hash: genesis.BlockHash
  AuditReportSourceKind* {.pure.} = enum ## Separate authenticated source forms carry different provenance, without a fabricated pending C10 assignment.
    Uninitialized, Available, Disputed
  AuditDisputeOriginInfo* = object ## Actual support and execution contexts remain distinct from an optional audited block.
    supportHash*, executionHash*, receiptHash*: genesis.BlockHash
    supportRoot*, executionRoot*, receiptRoot*: state_trie.StateRoot
    executionTime*: StateTime
    reportHash*: WorkReportHash
    auditorHash*: AuditorRosterHash
    epoch*, nodes*, valueBytes*, retainedBytes*: uint64
    entries*: int
  DisputeData = ref object ## Full execution state and genuine qualified report/auditor provenance form an acyclic private worker graph.
    support: VerifiedJudgmentSupport
    state: StateStoreSnapshot
    parameters: Parameters
    info: AuditDisputeOriginInfo
  AuditDisputeOrigin* = object ## Only independent actual canonical bindings and complete retention scans construct a usable disputed-report source.
    data: nil DisputeData
  AuditReportOrigin* = object ## Only a guarded lookup binds one original report ordinal to its actual retained execution source.
    source: AuditBlockOrigin
    dispute: AuditDisputeOrigin
    ordinal: int
  AuditOriginError* {.pure.} = enum ## No failed/default result carries a state or partially selected report capability.
    Uninitialized, None, InvalidPolicy, InvalidSource, InvalidIndex, NoReports,
    LimitExceeded, Cancelled, ContextFailure, StateFailure, HistoryUnavailable
  AuditOriginResult*[T] = object ## Genuine selected source/transition failures preserve their exact child cause.
    case status: AuditOriginError
    of None: completed: T
    of ContextFailure: contextReason: AuditContextResult[AuditContext]
    of StateFailure: stateReason: StateStoreError
    else: discard # Ordinary refusals contain no usable origin or unrelated child.
func error*[T](outcome: AuditOriginResult[T]): AuditOriginError =
  ## Inspect the selected branch before extracting any source-bearing ownership.
  outcome.status
func value*[T](outcome: AuditOriginResult[T]): T {.requires: outcome.status ==
    AuditOriginError.None.} =
  ## Successful access remains confined to an idle owner or the actual managed worker's exclusive lease.
  outcome.completed
func contextError*[T](outcome: AuditOriginResult[T]): AuditContextResult[
    AuditContext] {.requires: outcome.status == AuditOriginError.ContextFailure.} =
  ## Preserve the actual complete-body, prior-state or consensus-prefix refusal.
  outcome.contextReason
func stateError*[T](outcome: AuditOriginResult[T]): StateStoreError {.requires: outcome.status ==
    AuditOriginError.StateFailure.} =
  ## Retention scans never replace a failed full-map lookup with an empty value.
  outcome.stateReason
func valid*(limits: AuditOriginLimits): bool =
  ## Missing bounds cannot retain any source; entry/node counts and logical values have independent finite ceilings.
  uint64(limits.entries) > 0 and uint64(limits.entries) <= 1000000 and
    uint64(limits.nodes) > 0 and uint64(limits.nodes) <= 256'u64*1024*1024 and
    uint64(limits.valueBytes) > 0 and uint64(limits.valueBytes) <= 8'u64*1024*1024*1024
func valid*(origin: AuditBlockOrigin): bool =
  ## A default cannot masquerade as an empty initialized full-state source.
  origin.data != nil
func valid*(origin: AuditDisputeOrigin): bool =
  ## Defaults contain no trusted report, original auditor set or complete execution state.
  origin.data != nil
func valid*(origin: AuditReportOrigin): bool =
  ## Private construction binds either one actual available ordinal or the single separately qualified disputed report.
  if origin.dispute.valid: return not origin.source.valid and origin.ordinal == 0
  origin.source.valid
func present*(reference: AuditBlockReference): bool =
  ## A disputed-only report has no audited availability-block identity.
  reference.present
func value*(reference: AuditBlockReference): genesis.BlockHash {.requires: reference.present.} =
  ## Only an actual available-report origin can provide this copied identity.
  reference.hash
func sourceKind*(origin: AuditReportOrigin): AuditReportSourceKind =
  ## This fixed discriminator grants no replacement full-state or report authority.
  if origin.dispute.valid: AuditReportSourceKind.Disputed
  elif origin.source.valid: AuditReportSourceKind.Available
  else: AuditReportSourceKind.Uninitialized
proc auditedBlock*(origin: AuditReportOrigin): AuditBlockReference =
  ## Genuine available reports identify their actual block; disputed-only sources return an explicitly absent reference.
  let data = origin.source.data
  if data == nil: return default(AuditBlockReference)
  AuditBlockReference(present: true, hash: data.info.blockHash)

proc originInfo*(origin: AuditBlockOrigin): AuditOriginResult[AuditOriginInfo] =
  ## Copy logical accounting only while its source graph is exclusively accessible; cache it before asynchronous submission.
  let data = origin.data
  if data == nil: return AuditOriginResult[AuditOriginInfo](status: AuditOriginError.Uninitialized)
  AuditOriginResult[AuditOriginInfo](status: AuditOriginError.None, completed: data.info)
proc originContext*(origin: AuditBlockOrigin): AuditOriginResult[AuditContext] =
  ## Extract source-free role/report facts under the same exclusive lease; this does not release the pinned execution source.
  let data = origin.data
  if data == nil: return AuditOriginResult[AuditContext](status: AuditOriginError.Uninitialized)
  AuditOriginResult[AuditContext](status: AuditOriginError.None, completed: data.context)
proc reportAt*(origin: AuditBlockOrigin, ordinal: int): AuditOriginResult[AuditReportOrigin] =
  ## Dense original available-report ordinals remain bound to this exact block and complete predecessor.
  let data = origin.data
  if data == nil: return AuditOriginResult[AuditReportOrigin](
      status: AuditOriginError.Uninitialized)
  if ordinal < 0 or ordinal >= data.info.reports:
    return AuditOriginResult[AuditReportOrigin](status: AuditOriginError.InvalidIndex)
  AuditOriginResult[AuditReportOrigin](status: AuditOriginError.None,
    completed: AuditReportOrigin(source: origin, dispute: default(AuditDisputeOrigin),
        ordinal: ordinal))
proc disputeInfo*(origin: AuditDisputeOrigin): AuditOriginResult[AuditDisputeOriginInfo] =
  ## Fixed accounting/source facts stay separate from the original complete execution map.
  let data = origin.data
  if data == nil: return AuditOriginResult[AuditDisputeOriginInfo](
      status: AuditOriginError.Uninitialized)
  AuditOriginResult[AuditDisputeOriginInfo](status: AuditOriginError.None, completed: data.info)
proc reportAt*(origin: AuditDisputeOrigin, ordinal: int): AuditOriginResult[AuditReportOrigin] =
  ## Standalone supported reports occupy one private original target, with no constructed availability block or assignment.
  if not origin.valid: return AuditOriginResult[AuditReportOrigin](
      status: AuditOriginError.Uninitialized)
  if ordinal != 0: return AuditOriginResult[AuditReportOrigin](
      status: AuditOriginError.InvalidIndex)
  AuditOriginResult[AuditReportOrigin](status: AuditOriginError.None,
    completed: AuditReportOrigin(source: default(AuditBlockOrigin), dispute: origin, ordinal: 0))
func sameAuditOrigin*(left, right: AuditReportOrigin): bool =
  ## Exact private owner identity and original report ordinal bind evaluation/signing to a registered source, independently of copied public metadata.
  if not left.valid or not right.valid: return false
  if left.dispute.valid or right.dispute.valid:
    return left.dispute.valid and right.dispute.valid and left.dispute.data == right.dispute.data
  left.source.data == right.source.data and left.ordinal == right.ordinal
proc originInfo*(origin: AuditReportOrigin): AuditOriginResult[AuditOriginInfo] =
  ## Read a target's actual source facts only under its exclusive worker lease.
  if origin.dispute.valid: return AuditOriginResult[AuditOriginInfo](
      status: AuditOriginError.InvalidSource)
  origin.source.originInfo
proc originContext*(origin: AuditReportOrigin): AuditOriginResult[AuditContext] =
  ## Retain original auditor/guarantor role facts without accepting a caller-replacement key table.
  if origin.dispute.valid: return AuditOriginResult[AuditContext](
      status: AuditOriginError.InvalidSource)
  origin.source.originContext
proc originState*(origin: AuditReportOrigin): AuditOriginResult[StateStoreSnapshot] =
  ## Only immutable original full state is exposed to the leased evaluator; a replacement or partial light map is never accepted.
  let disputed = origin.dispute.data
  if disputed != nil: return AuditOriginResult[StateStoreSnapshot](status: AuditOriginError.None,
      completed: disputed.state)
  let data = origin.source.data
  if data == nil: return AuditOriginResult[StateStoreSnapshot](
      status: AuditOriginError.Uninitialized)
  AuditOriginResult[StateStoreSnapshot](status: AuditOriginError.None, completed: data.state)
proc originParameters*(origin: AuditReportOrigin): AuditOriginResult[Parameters] =
  ## Report computation uses the exact source profile, independently of later head changes or caller limits.
  let disputed = origin.dispute.data
  if disputed != nil: return AuditOriginResult[Parameters](status: AuditOriginError.None,
      completed: disputed.parameters)
  let data = origin.source.data
  if data == nil: return AuditOriginResult[Parameters](status: AuditOriginError.Uninitialized)
  AuditOriginResult[Parameters](status: AuditOriginError.None, completed: data.parameters)
proc originReport*(origin: AuditReportOrigin): AuditOriginResult[OwnedReport] =
  ## The full original guarantee report cannot be replaced by separately decoded caller bytes.
  let disputed = origin.dispute.data
  if disputed != nil: return AuditOriginResult[OwnedReport](status: AuditOriginError.None,
    completed: disputed.support.supportCertificate.value.supportedGuarantee.value.report)
  let data = origin.source.data
  if data == nil: return AuditOriginResult[OwnedReport](status: AuditOriginError.Uninitialized)
  let selected = data.context.auditGuarantee(origin.ordinal)
  if selected.error != AuditContextError.None:
    return AuditOriginResult[OwnedReport](status: AuditOriginError.InvalidSource)
  AuditOriginResult[OwnedReport](status: AuditOriginError.None, completed: selected.value.report)
proc originGuarantee*(origin: AuditReportOrigin): AuditOriginResult[Guarantee] =
  ## Negative judgments carry the exact originally admitted slot and distinct qualified credentials, never a caller replacement certificate.
  let disputed = origin.dispute.data
  if disputed != nil: return AuditOriginResult[Guarantee](status: AuditOriginError.None,
    completed: disputed.support.supportCertificate.value.supportedGuarantee.value)
  let data = origin.source.data
  if data == nil: return AuditOriginResult[Guarantee](status: AuditOriginError.Uninitialized)
  let selected = data.context.auditGuarantee(origin.ordinal)
  if selected.error != AuditContextError.None: return AuditOriginResult[Guarantee](
      status: AuditOriginError.InvalidSource)
  AuditOriginResult[Guarantee](status: AuditOriginError.None, completed: selected.value)
proc originReportHash*(origin: AuditReportOrigin): AuditOriginResult[WorkReportHash] =
  ## Cached canonical identity belongs to the original available report and exact parent state.
  let disputed = origin.dispute.data
  if disputed != nil: return AuditOriginResult[WorkReportHash](status: AuditOriginError.None,
      completed: disputed.info.reportHash)
  let data = origin.source.data
  if data == nil: return AuditOriginResult[WorkReportHash](status: AuditOriginError.Uninitialized)
  let selected = data.context.auditReportHash(origin.ordinal)
  if selected.error != AuditContextError.None:
    return AuditOriginResult[WorkReportHash](status: AuditOriginError.InvalidSource)
  AuditOriginResult[WorkReportHash](status: AuditOriginError.None, completed: selected.value)
proc auditEpoch*(origin: AuditReportOrigin): AuditOriginResult[uint64] =
  ## A disputed judgment's independently authenticated original epoch is not replaced by the report's availability or guarantee epoch.
  let disputed = origin.dispute.data
  if disputed != nil: return AuditOriginResult[uint64](status: AuditOriginError.None,
      completed: disputed.info.epoch)
  let context = origin.originContext
  if context.error != AuditOriginError.None: return AuditOriginResult[uint64](status: context.error)
  AuditOriginResult[uint64](status: AuditOriginError.None,
      completed: context.value.contextInfo.value.epoch)
proc auditorCount*(origin: AuditReportOrigin): AuditOriginResult[int] =
  ## Preserve every original ordinal of the actual independently selected auditor roster.
  let disputed = origin.dispute.data
  if disputed != nil: return AuditOriginResult[int](status: AuditOriginError.None,
      completed: disputed.support.supportInfo.value.auditors)
  let context = origin.originContext
  if context.error != AuditOriginError.None: return AuditOriginResult[int](status: context.error)
  AuditOriginResult[int](status: AuditOriginError.None,
      completed: context.value.contextInfo.value.auditors)
proc auditorAt*(origin: AuditReportOrigin, ordinal: int): AuditOriginResult[StateValidator] =
  ## Signing uses the source's actual original epoch/index, including repeated and null positions.
  let disputed = origin.dispute.data
  if disputed != nil:
    let roster = disputed.support.supportAuditors.value
    if ordinal < 0 or ordinal >= roster.validatorCount.value:
      return AuditOriginResult[StateValidator](status: AuditOriginError.InvalidIndex)
    return AuditOriginResult[StateValidator](status: AuditOriginError.None,
      completed: roster.validatorAt(StateValidatorIndex(uint64(ordinal))).value)
  let context = origin.originContext
  if context.error != AuditOriginError.None: return AuditOriginResult[StateValidator](
      status: context.error)
  let selected = context.value.auditorAt(ordinal)
  if selected.error != AuditContextError.None: return AuditOriginResult[StateValidator](
      status: AuditOriginError.InvalidIndex)
  AuditOriginResult[StateValidator](status: AuditOriginError.None, completed: selected.value)
proc originGuarantor*(origin: AuditReportOrigin, ordinal: int): AuditOriginResult[StateValidator] =
  ## Exact original slot/core credential qualification supplies direct-fetch identities independently of any availability or audit epoch.
  let disputed = origin.dispute.data
  if disputed != nil:
    let selected = disputed.support.supportCertificate.value.supportValidator(ordinal)
    if selected.error != GuaranteeSupportError.None:
      return AuditOriginResult[StateValidator](status: AuditOriginError.InvalidIndex)
    return AuditOriginResult[StateValidator](status: AuditOriginError.None,
        completed: selected.value)
  let data = origin.source.data
  if data == nil: return AuditOriginResult[StateValidator](status: AuditOriginError.Uninitialized)
  let selected = data.context.auditGuarantor(origin.ordinal, ordinal)
  if selected.error != AuditContextError.None:
    return AuditOriginResult[StateValidator](status: AuditOriginError.InvalidIndex)
  AuditOriginResult[StateValidator](status: AuditOriginError.None, completed: selected.value)
proc routingRosterCount*(origin: AuditReportOrigin): int =
  ## Available reports have one actual original assurer roster. Disputed-only reports retain explicitly named candidate epochs, never choose an assurer epoch by matching population alone.
  let disputed = origin.dispute.data
  if disputed != nil:
    if disputed.support.supportInfo.value.sourceEpoch > 0: return 3
    return 2 # Epoch-zero C9 is not an invented epoch minus one.
  if origin.source.valid: return 1
  0
proc routingRosterEpoch*(origin: AuditReportOrigin, roster: int): AuditOriginResult[uint64] =
  ## Reporting-current, reporting-previous and independently selected original auditor epochs stay explicit even when their populations happen to agree.
  if roster < 0 or roster >= origin.routingRosterCount:
    return AuditOriginResult[uint64](status: AuditOriginError.InvalidIndex)
  let disputed = origin.dispute.data
  if disputed == nil: return origin.auditEpoch
  let facts = disputed.support.supportInfo.value
  if roster == 0: return AuditOriginResult[uint64](status: AuditOriginError.None,
      completed: facts.sourceEpoch)
  if facts.sourceEpoch > 0 and roster == 1:
    return AuditOriginResult[uint64](status: AuditOriginError.None, completed: facts.sourceEpoch-1)
  AuditOriginResult[uint64](status: AuditOriginError.None, completed: facts.auditEpoch)
proc routingPopulation*(origin: AuditReportOrigin, roster: int): AuditOriginResult[int] =
  ## Population validates shard-coordinate geometry only; it does not authenticate which epoch actually assured an unseen report.
  if roster < 0 or roster >= origin.routingRosterCount:
    return AuditOriginResult[int](status: AuditOriginError.InvalidIndex)
  let disputed = origin.dispute.data
  if disputed == nil: return origin.auditorCount
  let facts = disputed.support.supportInfo.value
  let count = if roster == 0: facts.current
    elif facts.sourceEpoch > 0 and roster == 1: facts.previous
    else: facts.auditors
  AuditOriginResult[int](status: AuditOriginError.None, completed: count)
proc routingValidator*(origin: AuditReportOrigin, roster, ordinal: int): AuditOriginResult[
    StateValidator] =
  ## Return one fixed copied original-position key from an explicitly selected actual candidate roster, without exporting any mutable roster storage.
  let population = origin.routingPopulation(roster)
  if population.error != AuditOriginError.None or ordinal < 0 or ordinal >= population.value:
    return AuditOriginResult[StateValidator](status: AuditOriginError.InvalidIndex)
  let disputed = origin.dispute.data
  if disputed == nil: return origin.auditorAt(ordinal)
  let facts = disputed.support.supportInfo.value
  let selected = if roster == 0: disputed.support.supportRoster(false).value
    elif facts.sourceEpoch > 0 and roster == 1: disputed.support.supportRoster(true).value
    else: disputed.support.supportAuditors.value
  AuditOriginResult[StateValidator](status: AuditOriginError.None,
    completed: selected.validatorAt(StateValidatorIndex(uint64(ordinal))).value)
proc executionTime*(origin: AuditReportOrigin): AuditOriginResult[StateTime] =
  ## Historical lookup's validity domain uses the pinned execution snapshot's actual clock, not receipt time or an unsigned guarantee label.
  let disputed = origin.dispute.data
  if disputed != nil: return AuditOriginResult[StateTime](status: AuditOriginError.None,
      completed: disputed.info.executionTime)
  let data = origin.source.data
  if data == nil: return AuditOriginResult[StateTime](status: AuditOriginError.Uninitialized)
  let selected = data.state.lookup(chapterKey(StateChapter(11)))
  if selected.error != StateStoreError.None:
    return AuditOriginResult[StateTime](status: AuditOriginError.StateFailure,
        stateReason: selected.error)
  if selected.value.byteLength != 4:
    return AuditOriginResult[StateTime](status: AuditOriginError.InvalidSource)
  let decoded = decodeStateTime(selected.value.bytes)
  if decoded.error != StateComponentError.None:
    return AuditOriginResult[StateTime](status: AuditOriginError.InvalidSource)
  AuditOriginResult[StateTime](status: AuditOriginError.None, completed: decoded.value.value)
proc originParameters*(origin: AuditBlockOrigin): AuditOriginResult[Parameters] =
  ## Whole source profile participates in checkpoint/registry binding rather than a caller's copied public identity fields.
  let data = origin.data
  if data == nil: return AuditOriginResult[Parameters](status: AuditOriginError.Uninitialized)
  AuditOriginResult[Parameters](status: AuditOriginError.None, completed: data.parameters)
proc matchesTrustedBlock*(origin: AuditBlockOrigin, trusted: BlockSnapshotResult): bool =
  ## An independently trusted complete block/checkpoint can bind an already authenticated body/prior origin, including when its own body is unavailable. A bare header alone never creates this origin capability.
  let data = origin.data
  if data == nil or trusted.error != GenesisError.None: return false
  let selected = trusted.value
  let facts = data.context.contextInfo.value
  let described = selected.header.headerInfo
  if described.error != HeaderError.None: return false
  let parent = described.value.unsigned
  if array[32, byte](facts.blockHash) != array[32, byte](selected.blockHash) or
      array[32, byte](facts.blockRoot) != array[32, byte](selected.stateRoot) or
      array[32, byte](facts.parentHash) != array[32, byte](parent.parent) or
      array[32, byte](facts.parentRoot) != array[32, byte](parent.priorState) or
      array[32, byte](data.state.commitment.root) != array[32, byte](parent.priorState):
    return false # Actual full-root and sealed-header linkage, not caller-supplied eligibility or key tables.
  if not data.parameters.sameParameterProfile(selected.chainParameters): return false
  if selected.hasBlockBody and selected.blockBodyDigest != facts.bodyDigest: return false
  true
proc captureAuditOrigin*(source: ChainView, blockHash: genesis.BlockHash,
    contextLimits: AuditContextLimits, limits: AuditOriginLimits,
    control: AssuranceScanControl = default(AssuranceScanControl)): AuditOriginResult[
        AuditBlockOrigin] =
  ## Run on the managed worker: actual body/prefix qualification precedes whole logical source accounting; no partial origin survives cancellation or a late retention refusal.
  if not limits.valid: return AuditOriginResult[AuditBlockOrigin](
      status: AuditOriginError.InvalidPolicy)
  if control.stopped: return AuditOriginResult[AuditBlockOrigin](status: AuditOriginError.Cancelled)
  let context = captureAuditContext(source, blockHash, contextLimits, control)
  if context.error == AuditContextError.Cancelled:
    return AuditOriginResult[AuditBlockOrigin](status: AuditOriginError.Cancelled)
  if context.error != AuditContextError.None:
    return AuditOriginResult[AuditBlockOrigin](status: AuditOriginError.ContextFailure,
        contextReason: context)
  let info = context.value.contextInfo.value
  if info.reports == 0: return AuditOriginResult[AuditBlockOrigin](
      status: AuditOriginError.NoReports)
  let parent = source.parentOf(blockHash)
  if parent.error != GenesisError.None:
    return AuditOriginResult[AuditBlockOrigin](status: AuditOriginError.InvalidSource)
  let state = parent.value.stateSnapshot
  let counts = state.commitment
  if counts.entries < 0 or uint64(counts.entries) > uint64(limits.entries) or counts.nodes > uint64(limits.nodes):
    return AuditOriginResult[AuditBlockOrigin](status: AuditOriginError.LimitExceeded)
  var bytes = 0'u64
  for ordinal in 0..<counts.entries:
    # Length-only reads cover every unrelated service entry without copying any payload; all aliases remain on the managed worker until publication or refusal.
    if control.stopped: return AuditOriginResult[AuditBlockOrigin](
        status: AuditOriginError.Cancelled)
    let key = state.keyAt(StateEntryIndex(ordinal))
    if key.error != StateStoreError.None:
      return AuditOriginResult[AuditBlockOrigin](status: AuditOriginError.StateFailure,
          stateReason: key.error)
    let selected = state.lookup(key.value)
    if selected.error != StateStoreError.None:
      return AuditOriginResult[AuditBlockOrigin](status: AuditOriginError.StateFailure,
          stateReason: selected.error)
    let length = uint64(selected.value.byteLength)
    if length > uint64(limits.valueBytes)-bytes:
      return AuditOriginResult[AuditBlockOrigin](status: AuditOriginError.LimitExceeded)
    bytes += length
  if control.stopped: return AuditOriginResult[AuditBlockOrigin](status: AuditOriginError.Cancelled)
  AuditOriginResult[AuditBlockOrigin](status: AuditOriginError.None,
    completed: AuditBlockOrigin(data: OriginData(context: context.value, state: state,
      parameters: parent.value.chainParameters,
      info: AuditOriginInfo(blockHash: info.blockHash, parentHash: info.parentHash,
        parentRoot: info.parentRoot, entries: counts.entries, reports: info.reports,
        nodes: counts.nodes, valueBytes: bytes))))
proc historicalExecution(view: ChainView, minimum, maximum: uint64): BlockSnapshotResult =
  ## Search only actual ordered retained full snapshots plus the separately trusted finalized snapshot; no fabricated clock/header fills a history gap.
  var first = 0
  var last = view.retainedCount
  while first < last:
    # Subtraction-based binary search takes at most the configured history bound's logarithmic number of actual metadata reads.
    let middle = first+(last-first) div 2
    let source = view.retainedBlockAt(RetainedBlockIndex(middle))
    if source.error != GenesisError.None: return unavailableGenesis()
    if source.value.slot <= maximum: first = middle+1
    else: last = middle
  var selected = unavailableGenesis()
  if first > 0:
    let candidate = view.retainedBlockAt(RetainedBlockIndex(first-1))
    if candidate.error == GenesisError.None and candidate.value.slot >= minimum:
      selected = candidate
  let finalized = view.finalizedBlock
  if finalized.error == GenesisError.None and finalized.value.slot >= minimum and
      finalized.value.slot <= maximum:
    if selected.error != GenesisError.None or finalized.value.slot > selected.value.slot:
      selected = finalized
  selected
proc matchesTrustedDispute*(origin: AuditDisputeOrigin, view: ChainView): bool =
  ## Independent Services trust binds all three actual contexts: original judge membership, guarantor support and complete historical execution state.
  let data = origin.data
  if data == nil or view.fuzzOnly: return false
  let role = view.blockAt(data.info.supportHash)
  if not data.support.matchesSource(role): return false
  let membership = data.support.supportInfo.value
  let receipt = view.blockAt(membership.membershipHash)
  if receipt.error != GenesisError.None or array[32, byte](receipt.value.stateRoot) != array[32,
      byte](membership.membershipRoot):
    return false
  if receipt.value.slot != uint64(uint32(membership.membershipTime)) or
      not data.parameters.sameParameterProfile(receipt.value.chainParameters):
    return false
  let execution = view.blockAt(data.info.executionHash)
  if execution.error != GenesisError.None: return false
  array[32, byte](execution.value.stateRoot) == array[32, byte](data.info.executionRoot) and
    array[32, byte](data.state.commitment.root) == array[32, byte](data.info.executionRoot) and
    execution.value.slot == uint64(uint32(data.info.executionTime)) and
    data.parameters.sameParameterProfile(execution.value.chainParameters)
proc captureAuditDisputeOrigin*(view: ChainView, support: VerifiedJudgmentSupport,
    limits: AuditOriginLimits, control: AssuranceScanControl = default(AssuranceScanControl)):
    AuditOriginResult[AuditDisputeOrigin] =
  ## Qualified standalone signatures never create C10 availability. Actual canonical bindings and whole-map retention complete before the private single-report execution source is published.
  if not limits.valid: return AuditOriginResult[AuditDisputeOrigin](
      status: AuditOriginError.InvalidPolicy)
  if view.fuzzOnly or not support.valid:
    return AuditOriginResult[AuditDisputeOrigin](status: AuditOriginError.InvalidSource)
  if control.stopped: return AuditOriginResult[AuditDisputeOrigin](
      status: AuditOriginError.Cancelled)
  let facts = support.supportInfo.value
  let role = view.blockAt(facts.sourceHash)
  if not support.matchesSource(role):
    return AuditOriginResult[AuditDisputeOrigin](status: AuditOriginError.InvalidSource)
  let membership = support.supportInfo.value
  let receipt = view.blockAt(membership.membershipHash)
  let parameters = support.supportParameters.value
  if receipt.error != GenesisError.None or array[32, byte](receipt.value.stateRoot) != array[32,
      byte](membership.membershipRoot):
    return AuditOriginResult[AuditDisputeOrigin](status: AuditOriginError.InvalidSource)
  if receipt.value.slot != uint64(uint32(membership.membershipTime)) or
      not parameters.sameParameterProfile(receipt.value.chainParameters):
    return AuditOriginResult[AuditDisputeOrigin](status: AuditOriginError.InvalidSource)
  let report = support.supportCertificate.value.supportedGuarantee.value.report.ownedReportInfo.value
  let lookup = uint64(uint32(report.header.lookupSlot))
  let anchor = uint64(uint32(report.header.anchorSlot))
  let duration = uint64(parameters.expungePeriod)
  if duration > high(uint64)-lookup:
    return AuditOriginResult[AuditDisputeOrigin](status: AuditOriginError.InvalidSource)
  let maximum = lookup+duration
  let minimum = if anchor > lookup: anchor else: lookup
  if minimum > maximum:
    return AuditOriginResult[AuditDisputeOrigin](status: AuditOriginError.HistoryUnavailable)
  var execution = role
  if role.value.slot < minimum or role.value.slot > maximum:
    # Historical lookup is defined only on [source_time-D, source_time]. A later signed slot label must never turn expired/missing old code into an invalid judgment.
    execution = historicalExecution(view, minimum, maximum)
  if execution.error != GenesisError.None:
    return AuditOriginResult[AuditDisputeOrigin](status: AuditOriginError.HistoryUnavailable)
  if not parameters.sameParameterProfile(execution.value.chainParameters):
    return AuditOriginResult[AuditDisputeOrigin](status: AuditOriginError.InvalidSource)
  let state = execution.value.stateSnapshot
  let clockValue = state.lookup(chapterKey(StateChapter(11)))
  if clockValue.error != StateStoreError.None:
    return AuditOriginResult[AuditDisputeOrigin](status: AuditOriginError.StateFailure,
        stateReason: clockValue.error)
  if clockValue.value.byteLength != 4:
    return AuditOriginResult[AuditDisputeOrigin](status: AuditOriginError.InvalidSource)
  let clock = decodeStateTime(clockValue.value.bytes)
  if clock.error != StateComponentError.None or uint64(uint32(clock.value.value)) !=
      execution.value.slot:
    return AuditOriginResult[AuditDisputeOrigin](status: AuditOriginError.InvalidSource)
  let counts = state.commitment
  if counts.entries < 0 or uint64(counts.entries) > uint64(limits.entries) or counts.nodes > uint64(limits.nodes):
    return AuditOriginResult[AuditDisputeOrigin](status: AuditOriginError.LimitExceeded)
  var bytes = 0'u64
  for ordinal in 0..<counts.entries:
    # Logical full-map retention covers unrelated service values too; no partial or light map can masquerade as the original execution state.
    if control.stopped: return AuditOriginResult[AuditDisputeOrigin](
        status: AuditOriginError.Cancelled)
    let key = state.keyAt(StateEntryIndex(ordinal))
    if key.error != StateStoreError.None:
      return AuditOriginResult[AuditDisputeOrigin](status: AuditOriginError.StateFailure,
          stateReason: key.error)
    let selected = state.lookup(key.value)
    if selected.error != StateStoreError.None:
      return AuditOriginResult[AuditDisputeOrigin](status: AuditOriginError.StateFailure,
          stateReason: selected.error)
    let length = uint64(selected.value.byteLength)
    if length > uint64(limits.valueBytes)-bytes:
      return AuditOriginResult[AuditDisputeOrigin](status: AuditOriginError.LimitExceeded)
    bytes += length
  if control.stopped: return AuditOriginResult[AuditDisputeOrigin](
      status: AuditOriginError.Cancelled)
  AuditOriginResult[AuditDisputeOrigin](status: AuditOriginError.None,
    completed: AuditDisputeOrigin(data: DisputeData(support: support, state: state,
      parameters: parameters,
      info: AuditDisputeOriginInfo(supportHash: facts.sourceHash, supportRoot: facts.sourceRoot,
        executionHash: execution.value.blockHash, executionRoot: execution.value.stateRoot,
        executionTime: clock.value.value, reportHash: WorkReportHash(array[32, byte](facts.report)),
        epoch: facts.auditEpoch, auditorHash: facts.auditorHash,
            receiptHash: membership.membershipHash, receiptRoot: membership.membershipRoot,
                entries: counts.entries, nodes: counts.nodes, valueBytes: bytes,
        retainedBytes: facts.retainedBytes))))
