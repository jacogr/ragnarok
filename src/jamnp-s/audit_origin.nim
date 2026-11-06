# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Private audit execution origins pin the actual complete predecessor and its parameters alongside authenticated available work. They are source-bearing worker objects: all aliases remain frozen through exact collection or joined cancellation.
import ./audit_context
from ./assurance_store import AssuranceScanControl, stopped
import ../chain/[genesis, provider, parameters, reports]
import ../codec/[bounded, owned, report_owned, header]
import ../codec/state/trie as state_trie
import ../state/store

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
  AuditReportOrigin* = object ## Only a guarded lookup binds one original report ordinal to its actual retained execution source.
    source: AuditBlockOrigin
    ordinal: int
  AuditOriginError* {.pure.} = enum ## No failed/default result carries a state or partially selected report capability.
    Uninitialized, None, InvalidPolicy, InvalidSource, InvalidIndex, NoReports,
    LimitExceeded, Cancelled, ContextFailure, StateFailure
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
func valid*(origin: AuditReportOrigin): bool =
  ## Private construction binds the ordinal once; callers cannot retarget an existing source.
  origin.source.valid
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
    completed: AuditReportOrigin(source: origin, ordinal: ordinal))
func sameAuditOrigin*(left, right: AuditReportOrigin): bool =
  ## Exact private owner identity and original report ordinal bind evaluation/signing to a registered source, independently of copied public metadata.
  left.valid and right.valid and left.source.data == right.source.data and left.ordinal == right.ordinal
proc originInfo*(origin: AuditReportOrigin): AuditOriginResult[AuditOriginInfo] =
  ## Read a target's actual source facts only under its exclusive worker lease.
  origin.source.originInfo
proc originContext*(origin: AuditReportOrigin): AuditOriginResult[AuditContext] =
  ## Retain original auditor/guarantor role facts without accepting a caller-replacement key table.
  origin.source.originContext
proc originState*(origin: AuditReportOrigin): AuditOriginResult[StateStoreSnapshot] =
  ## Only immutable original full state is exposed to the leased evaluator; a replacement or partial light map is never accepted.
  let data = origin.source.data
  if data == nil: return AuditOriginResult[StateStoreSnapshot](
      status: AuditOriginError.Uninitialized)
  AuditOriginResult[StateStoreSnapshot](status: AuditOriginError.None, completed: data.state)
proc originParameters*(origin: AuditReportOrigin): AuditOriginResult[Parameters] =
  ## Report computation uses the exact source profile, independently of later head changes or caller limits.
  let data = origin.source.data
  if data == nil: return AuditOriginResult[Parameters](status: AuditOriginError.Uninitialized)
  AuditOriginResult[Parameters](status: AuditOriginError.None, completed: data.parameters)
proc originReport*(origin: AuditReportOrigin): AuditOriginResult[OwnedReport] =
  ## The full original guarantee report cannot be replaced by separately decoded caller bytes.
  let data = origin.source.data
  if data == nil: return AuditOriginResult[OwnedReport](status: AuditOriginError.Uninitialized)
  let selected = data.context.auditGuarantee(origin.ordinal)
  if selected.error != AuditContextError.None:
    return AuditOriginResult[OwnedReport](status: AuditOriginError.InvalidSource)
  AuditOriginResult[OwnedReport](status: AuditOriginError.None, completed: selected.value.report)
proc originReportHash*(origin: AuditReportOrigin): AuditOriginResult[WorkReportHash] =
  ## Cached canonical identity belongs to the original available report and exact parent state.
  let data = origin.source.data
  if data == nil: return AuditOriginResult[WorkReportHash](status: AuditOriginError.Uninitialized)
  let selected = data.context.auditReportHash(origin.ordinal)
  if selected.error != AuditContextError.None:
    return AuditOriginResult[WorkReportHash](status: AuditOriginError.InvalidSource)
  AuditOriginResult[WorkReportHash](status: AuditOriginError.None, completed: selected.value)
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
