# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Complete retained block bodies and their real predecessors derive authenticated newly available audit duties through the existing consensus prefix; source-free output grants neither private signing nor finality authority.

import std/assertions
from ./assurance_store import AssuranceScanControl, stopped
import ../chain/[genesis, provider, parameters, reports]
import ../codec/[bounded, block_codec, report_owned, owned, guarantees, assurances]
import ../codec/state/[safrole, consensus, layout, availability, trie]
import ../codec/work/report
import ../state/[store, disputes, availability as availability_rules]
import "../state/block/admission"
import "../state/block/transition"
import ../state/safrole/transition as safrole_rules
import ../state/entropy
import ../crypto/primitives

type
  AuditContextLimits* = object ## Whole copied input/workspace/output preflight accompanies each maintained child transition's explicit CPU/state policy.
    admission*: BlockAdmissionConfig
    disputes*: DisputesConfig
    safrole*: SafroleTransitionConfig
    availability*: AvailabilityTransitionConfig
    bodyBytes*, chapterBytes*, readBytes*, workspaceBytes*, outputBytes*: ByteLimit
    reports*, hashes*: ElementLimit
    hashBytes*: ByteLimit
  AuditContextError* {.pure.} = enum ## No refusal exposes a newly available prefix, public role set or usable audit obligation.
    Uninitialized, None, InvalidPolicy, UnknownBlock, MissingParent, MissingBody, InvalidSource,
    InvalidIndex, LimitExceeded, StateFailure, BodyFailure, TransitionFailure, ComponentFailure,
      UncertainEpoch, BackendFailure, Cancelled
  AuditContextInfo* = object ## Exact immutable source identities and verified entropy bind every later proof/judgment to one actual block.
    blockHash*, parentHash*: genesis.BlockHash
    blockRoot*, parentRoot*: trie.StateRoot
    bodyDigest*: array[32, byte]
    slot*, parentSlot*: StateTime
    epoch*, slotSeconds*, epochSlots*: uint64
    cores*, maximumCores*: CoreCount
    auditors*, reports*: int
    retainedBytes*: uint64
    entropy*: array[32, byte]
  AuditData = ref object ## No canonical map, mutable chain, native namespace or private signer survives context execution.
    info: AuditContextInfo
    assignments: AvailabilitySnapshot
    auditors, previous: ValidatorStateSnapshot
    available: seq[uint16]
    reports: seq[WorkReportHash]
  AuditContext* = object ## A default carries no source, roster or authenticated available work.
    data: nil AuditData
  AuditContextResult*[T] = object ## Genuine selected child failures retain only their real guarded diagnostics, never a successful earlier prefix.
    case status: AuditContextError
    of None: completed: T
    of StateFailure: stateReason: StateStoreError
    of BodyFailure: bodyReason: FrameResult[BlockRead]
    of TransitionFailure: transitionReason: BlockTransitionResult
    of ComponentFailure: componentReason: StateComponentError
    else: discard # Simple source/policy/index refusals have no payload.

func error*[T](outcome: AuditContextResult[T]): AuditContextError =
  ## Inspect the selected branch before extracting a context or child.
  outcome.status

func value*[T](outcome: AuditContextResult[T]): T {.requires: outcome.status ==
    AuditContextError.None.} =
  ## Whole success alone grants detached immutable audit inputs.
  outcome.completed

func transitionError*[T](outcome: AuditContextResult[
    T]): BlockTransitionResult {.requires: outcome.status == AuditContextError.TransitionFailure.} =
  ## Preserve the actual consensus-prefix authentication refusal.
  outcome.transitionReason

func componentError*[T](outcome: AuditContextResult[
    T]): StateComponentError {.requires: outcome.status == AuditContextError.ComponentFailure.} =
  ## Keep actual public-roster decoder/index failures separate from source absence or a malformed report.
  outcome.componentReason

func stateError*[T](outcome: AuditContextResult[T]): StateStoreError {.requires: outcome.status ==
    AuditContextError.StateFailure.} =
  ## Missing/invalid original state remains an actual selected failure.
  outcome.stateReason

func bodyError*[T](outcome: AuditContextResult[T]): FrameResult[
    BlockRead] {.requires: outcome.status == AuditContextError.BodyFailure.} =
  ## Exact block decoding failure cannot expose a successful prefix.
  outcome.bodyReason

func refused[T](reason: AuditContextError): AuditContextResult[T] {.requires: reason notin [
    AuditContextError.None, AuditContextError.StateFailure, AuditContextError.BodyFailure,
    AuditContextError.TransitionFailure, AuditContextError.ComponentFailure].} =
  ## Simple failures cannot manufacture guarded child success or a partially retained context.
  AuditContextResult[T](status: reason)

func valid*(context: AuditContext): bool =
  ## Defaults are unavailable, independently of all-zero copied metadata.
  context.data != nil

func valid*(limits: AuditContextLimits): bool =
  ## All new traversals and allocations have finite explicit bounds; child policies still validate their own exact semantics.
  uint64(limits.bodyBytes) > 0 and uint64(limits.bodyBytes) <= 32'u64*1024*1024 and
    uint64(limits.chapterBytes) > 0 and uint64(limits.chapterBytes) <= 16'u64*1024*1024 and
    uint64(limits.readBytes) > 0 and uint64(limits.readBytes) <= 64'u64*1024*1024 and
    uint64(limits.workspaceBytes) > 0 and uint64(limits.workspaceBytes) <= 512'u64*1024*1024 and
    uint64(limits.outputBytes) > 0 and uint64(limits.outputBytes) <= 64'u64*1024*1024 and
    uint64(limits.reports) > 0 and uint64(limits.reports) <= 341 and
    uint64(limits.hashes) > 0 and uint64(limits.hashes) <= 1000000 and
    uint64(limits.hashBytes) > 0 and uint64(limits.hashBytes) <= 128'u64*1024*1024

proc contextInfo*(context: AuditContext): AuditContextResult[AuditContextInfo] =
  ## Fixed copied facts contain no current-canonical or audited/finality assertion.
  let data = context.data
  if data == nil: return refused[AuditContextInfo](AuditContextError.Uninitialized)
  AuditContextResult[AuditContextInfo](status: AuditContextError.None, completed: data.info)

proc auditorAt*(context: AuditContext, ordinal: int): AuditContextResult[StateValidator] =
  ## Original prior-C8 ordinals, including null/repeated keys, remain independent authenticated proof domains.
  let data = context.data
  if data == nil: return refused[StateValidator](AuditContextError.Uninitialized)
  if ordinal < 0 or ordinal >= data.info.auditors: return refused[StateValidator](
      AuditContextError.InvalidIndex)
  let found = data.auditors.validatorAt(StateValidatorIndex(uint64(ordinal)))
  if found.error != StateComponentError.None: return refused[StateValidator](
      AuditContextError.InvalidSource)
  AuditContextResult[StateValidator](status: AuditContextError.None, completed: found.value)

proc availableCore*(context: AuditContext, ordinal: int): AuditContextResult[CoreIndex] =
  ## Dense audit report order retains the actual available core, never a shifted pending-report index.
  let data = context.data
  if data == nil: return refused[CoreIndex](AuditContextError.Uninitialized)
  if ordinal < 0 or ordinal >= data.available.len: return refused[CoreIndex](
      AuditContextError.InvalidIndex)
  AuditContextResult[CoreIndex](status: AuditContextError.None, completed: CoreIndex(data.available[ordinal]))

proc auditReportHash*(context: AuditContext, ordinal: int): AuditContextResult[WorkReportHash] =
  ## Fixed already-computed canonical report identity is safe during a foreign source lease.
  let data = context.data
  if data == nil: return refused[WorkReportHash](AuditContextError.Uninitialized)
  if ordinal < 0 or ordinal >= data.reports.len: return refused[WorkReportHash](
      AuditContextError.InvalidIndex)
  AuditContextResult[WorkReportHash](status: AuditContextError.None, completed: data.reports[ordinal])

proc auditGuarantee*(context: AuditContext, ordinal: int): AuditContextResult[Guarantee] =
  ## Copy the full original report and its authentic evaluation slot/two-or-three credentials for an actually newly available report.
  let data = context.data
  if data == nil: return refused[Guarantee](AuditContextError.Uninitialized)
  let core = context.availableCore(ordinal)
  if core.error != AuditContextError.None: return refused[Guarantee](core.error)
  let assigned = data.assignments.availabilityAt(AssignmentCoreIndex(uint64(core.value)))
  if assigned.error != AvailabilityError.None or not assigned.value.present:
    return refused[Guarantee](AuditContextError.InvalidSource)
  AuditContextResult[Guarantee](status: AuditContextError.None, completed: assigned.value.guarantee)

proc auditGuarantor*(context: AuditContext, ordinal, credential: int): AuditContextResult[
    StateValidator] =
  ## The original guarantee evaluation epoch chooses its own C8/C9 roster before any metadata route can be used.
  let data = context.data
  if data == nil: return refused[StateValidator](AuditContextError.Uninitialized)
  let core = context.availableCore(ordinal)
  if core.error != AuditContextError.None: return refused[StateValidator](core.error)
  let selected = context.auditGuarantee(ordinal)
  if selected.error != AuditContextError.None: return refused[StateValidator](selected.error)
  let guarantee = selected.value
  if credential < 0 or credential >= guarantee.credentialCount:
    return refused[StateValidator](AuditContextError.InvalidIndex)
  let reported = uint64(uint32(guarantee.slot)) div data.info.epochSlots
  var roster = default(ValidatorStateSnapshot)
  if reported == data.info.epoch:
    roster = data.auditors # Exact original evaluation epoch selects prior-C8, not a compressed current position.
  elif data.info.epoch > 0 and reported == data.info.epoch-1:
    roster = data.previous # The previous evaluation epoch has its independent C9 population and ordinal namespace.
  else:
    return refused[StateValidator](AuditContextError.UncertainEpoch) # Missing older history cannot select an invented public key.
  let found = roster.validatorAt(StateValidatorIndex(uint64(uint16(guarantee.credentials[
      credential].validator))))
  if found.error != StateComponentError.None:
    return AuditContextResult[StateValidator](status: AuditContextError.ComponentFailure,
        componentReason: found.error)
  AuditContextResult[StateValidator](status: AuditContextError.None, completed: found.value)

proc matches*(context: AuditContext, source: ChainView): bool =
  ## Real retained child/body and predecessor identities must still match; a header-only replacement never revives an obligation.
  let data = context.data
  if data == nil: return false
  let child = source.blockAt(data.info.blockHash)
  let parent = source.blockAt(data.info.parentHash)
  if child.error != GenesisError.None or parent.error != GenesisError.None: return false
  child.value.hasBlockBody and child.value.blockBodyDigest == data.info.bodyDigest and array[32,
      byte](child.value.stateRoot) == array[32, byte](data.info.blockRoot) and
    array[32, byte](parent.value.stateRoot) == array[32, byte](data.info.parentRoot)

proc reportDigest(report: OwnedReport): AuditContextResult[Blake2bHash] =
  ## Independently retained decoder outputs are compared by the canonical full report hash, never just an availability root.
  let info = report.ownedReportInfo
  if info.error != OwnershipError.None: return refused[Blake2bHash](AuditContextError.InvalidSource)
  var bytes = newSeq[byte](info.value.consumed)
  let encoded = report.encodeOwnedReport(bytes)
  if encoded.error != OwnershipError.None: return refused[Blake2bHash](
      AuditContextError.InvalidSource)
  let hashed = blake2b256(bytes)
  if hashed.error != CryptoError.None: return refused[Blake2bHash](AuditContextError.BackendFailure)
  AuditContextResult[Blake2bHash](status: AuditContextError.None, completed: hashed.value)

proc captureAuditContext*(source: ChainView, blockHash: genesis.BlockHash,
    limits: AuditContextLimits, control: AssuranceScanControl = default(
        AssuranceScanControl)): AuditContextResult[AuditContext] =
  ## Run only on the existing closed managed worker: complete preflight precedes body/chapter copies and private consensus-prefix execution.
  if not limits.valid: return refused[AuditContext](AuditContextError.InvalidPolicy)
  if control.stopped: return refused[AuditContext](AuditContextError.Cancelled)
  if source.fuzzOnly: return refused[AuditContext](AuditContextError.InvalidSource)
  let selected = source.blockAt(blockHash)
  if selected.error != GenesisError.None: return refused[AuditContext](
      AuditContextError.UnknownBlock)
  let child = selected.value
  if not child.hasBlockBody: return refused[AuditContext](AuditContextError.MissingBody)
  let previous = source.parentOf(blockHash)
  if previous.error != GenesisError.None: return refused[AuditContext](
      AuditContextError.MissingParent)
  let parent = previous.value
  if parent.slot >= child.slot or child.slot > uint64(high(uint32)):
    return refused[AuditContext](AuditContextError.InvalidSource)
  let profile = parent.chainParameters
  let cores = profile.get(coreCount)
  let epoch = profile.get(epochPeriod)
  if cores < 2 or cores > 341 or epoch == 0 or epoch > uint64(high(uint32)):
    return refused[AuditContext](AuditContextError.InvalidSource)
  if uint64(limits.admission.frame.cores) != cores or uint64(limits.admission.frame.epochSlots) != epoch:
    return refused[AuditContext](AuditContextError.InvalidPolicy)
  let bodyBytes = uint64(child.blockBodyLength)
  if bodyBytes > uint64(limits.bodyBytes) or bodyBytes > uint64(limits.admission.frame.maxBytes):
    return refused[AuditContext](AuditContextError.LimitExceeded)
  let state = parent.stateSnapshot
  var read = 0'u64
  for chapter in [4'u8, 5, 6, 7, 8, 9, 10, 11]:
    # Every original consensus chapter is bounded before any helper can decode or copy it.
    if control.stopped: return refused[AuditContext](AuditContextError.Cancelled)
    let entry = state.lookup(chapterKey(StateChapter(chapter)))
    if entry.error != StateStoreError.None:
      return AuditContextResult[AuditContext](status: AuditContextError.StateFailure,
          stateReason: entry.error)
    let bytes = uint64(entry.value.byteLength)
    if bytes > uint64(limits.chapterBytes) or bytes > uint64(limits.readBytes)-read:
      return refused[AuditContext](AuditContextError.LimitExceeded)
    read += bytes
  if sizeof(StateValidator) > 512 or sizeof(AvailabilityAssignment) > 512 or sizeof(StateEntry) > 256:
    return refused[AuditContext](AuditContextError.InvalidPolicy)
  let output = 4096'u64+read*8+1023'u64*512+uint64(limits.reports)*512
  let workspace = bodyBytes*8+read*8+output+4'u64*1024*1024
  if output > uint64(limits.outputBytes) or workspace > uint64(limits.workspaceBytes):
    return refused[AuditContext](AuditContextError.LimitExceeded)
  let entries = state.commitment.entries
  if entries < 0: return refused[AuditContext](AuditContextError.InvalidSource)
  # The coordinator publishes disputes, Safrole and availability on private stores. Their retained snapshots and merge scratch can copy the complete sorted-map descriptor table, including unrelated service entries. Reserve eight tables plus fixed changed-key/trie scratch above before any fork or chapter copy; division proves multiplication/addition without wrapping.
  let descriptorWidth = uint64(sizeof(StateEntry))*8
  if uint64(entries) > (uint64(limits.workspaceBytes)-workspace) div descriptorWidth:
    return refused[AuditContext](AuditContextError.LimitExceeded)
  let rosterPolicy = ValidatorStateConfig(cores: CoreCount(cores), validators: ElementLimit(1023),
      maxBytes: limits.chapterBytes)
  let activeBytes = state.lookup(chapterKey(StateChapter(8))).value.bytes
  let roster = decodeStateValidators(activeBytes, rosterPolicy)
  if roster.error != StateComponentError.None:
    return AuditContextResult[AuditContext](status: AuditContextError.ComponentFailure,
        componentReason: roster.error)
  let previousBytes = state.lookup(chapterKey(StateChapter(9))).value.bytes
  let oldRoster = decodeStateValidators(previousBytes, rosterPolicy)
  if oldRoster.error != StateComponentError.None:
    return AuditContextResult[AuditContext](status: AuditContextError.ComponentFailure,
        componentReason: oldRoster.error)
  if roster.value.consumed != activeBytes.len or oldRoster.value.consumed != previousBytes.len:
    return refused[AuditContext](AuditContextError.InvalidSource)
  let population = roster.value.value.validatorCount.value
  if population < 3 or population > 1023 or population mod 3 != 0 or uint64(population div 3) > cores:
    return refused[AuditContext](AuditContextError.InvalidSource)
  if control.stopped: return refused[AuditContext](AuditContextError.Cancelled)
  let body = child.blockBody
  let decoded = decodeBlock(body, limits.admission.frame)
  if decoded.error != FrameError.None:
    return AuditContextResult[AuditContext](status: AuditContextError.BodyFailure,
        bodyReason: decoded)
  if decoded.value.consumed != body.len: return refused[AuditContext](
      AuditContextError.InvalidSource)
  let forked = forkStateStore(state)
  if forked.error != StateStoreError.None:
    return AuditContextResult[AuditContext](status: AuditContextError.StateFailure,
        stateReason: forked.error)
  var working = forked.value
  let advanced = advanceBlockState(working, decoded.value.owner, parent.header,
    limits.admission, limits.disputes, limits.safrole, limits.availability)
  if control.stopped: return refused[AuditContext](AuditContextError.Cancelled)
  if advanced.error != BlockTransitionError.None:
    return AuditContextResult[AuditContext](status: AuditContextError.TransitionFailure,
        transitionReason: advanced)
  let available = advanced.value.availability
  let count = available.availableReportCount
  if uint64(count) > uint64(limits.reports): return refused[AuditContext](
      AuditContextError.LimitExceeded)
  if uint64(count)*2 > uint64(limits.hashes):
    return refused[AuditContext](AuditContextError.LimitExceeded)
  var digestBytes = 0'u64
  for ordinal in 0..<count:
    # Whole comparison work is reserved before hashing even the first newly available report.
    if control.stopped: return refused[AuditContext](AuditContextError.Cancelled)
    let report = available.availableReportAt(ordinal).value
    let bytes = uint64(report.ownedReportInfo.value.consumed)*2
    if bytes > uint64(limits.hashBytes)-digestBytes:
      return refused[AuditContext](AuditContextError.LimitExceeded)
    digestBytes += bytes
  let assignments = advanced.value.disputes.disputeAssignments
  var rows = newSeq[uint16](count)
  var identities = newSeq[WorkReportHash](count)
  for ordinal in 0..<count:
    # Only an authenticated availability output with the same original complete report/credentials becomes an audit obligation.
    if control.stopped: return refused[AuditContext](AuditContextError.Cancelled)
    let report = available.availableReportAt(ordinal).value
    let core = report.ownedReportInfo.value.core
    if uint64(core) >= uint64(population div 3):
      return refused[AuditContext](AuditContextError.InvalidSource)
    let pending = assignments.availabilityAt(AssignmentCoreIndex(uint64(core)))
    if pending.error != AvailabilityError.None or not pending.value.present:
      return refused[AuditContext](AuditContextError.InvalidSource)
    let actual = reportDigest(report)
    if actual.error != AuditContextError.None: return refused[AuditContext](actual.error)
    let original = reportDigest(pending.value.guarantee.report)
    if original.error != AuditContextError.None: return refused[AuditContext](original.error)
    if array[32, byte](actual.value) != array[32, byte](original.value):
      return refused[AuditContext](AuditContextError.InvalidSource)
    rows[ordinal] = uint16(uint64(core))
    identities[ordinal] = WorkReportHash(array[32, byte](actual.value))
  if control.stopped: return refused[AuditContext](AuditContextError.Cancelled)
  let info = AuditContextInfo(blockHash: child.blockHash, parentHash: parent.blockHash,
    blockRoot: child.stateRoot, parentRoot: parent.stateRoot, bodyDigest: child.blockBodyDigest,
    slot: StateTime(uint32(child.slot)),
    parentSlot: StateTime(uint32(parent.slot)), epoch: parent.slot div epoch,
    slotSeconds: profile.get(slotPeriodSec), epochSlots: epoch, cores: CoreCount(uint64(
        population div 3)), maximumCores: CoreCount(cores),
    auditors: int(population), reports: count, retainedBytes: output,
    entropy: array[32, byte](advanced.value.safrole.authentication.entropy))
  AuditContextResult[AuditContext](status: AuditContextError.None,
    completed: AuditContext(data: AuditData(info: info, assignments: assignments,
      auditors: roster.value.value, previous: oldRoster.value.value, available: rows,
      reports: identities)))
