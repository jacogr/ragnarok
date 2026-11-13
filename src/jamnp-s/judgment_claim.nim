# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Whole CE145 batches authenticate each original epoch/key and exact GP judgment message. A signed negative claim does not qualify its inline guarantees, establish report invalidity, or grant private evaluation/signing authority.

import ./audits
from ./assurance_store import AssuranceScanControl, stopped
import ../chain/[genesis, provider, parameters]
import ../codec/[bounded, disputes]
import ../codec/state/[safrole, consensus, layout, trie]
import ../state/store
import ../crypto/primitives

type
  JudgmentClaimLimits* = object ## Finite complete-message, original-roster, workspace, signature and retained-output admission are independently explicit.
    message*: AuditLimits
    rosters*: ValidatorStateConfig
    readBytes*, workspaceBytes*, retainedBytes*, signatureBytes*: ByteLimit
    signatures*: ElementLimit
  JudgmentClaimError* {.pure.} = enum ## Failed/default operations expose no authenticated prefix, accepted credential or judgment capability.
    Uninitialized, None, InvalidPolicy, InvalidSource, InvalidIndex, LimitExceeded,
    UnknownEpoch, InvalidAuditor, InvalidSignature, Cancelled, DecodeFailure,
    StateFailure, ComponentFailure
  JudgmentClaimInfo* = object ## Copied source/membership facts grant no fork choice, finality or guarantee authentication.
    sourceHead*: genesis.BlockHash
    sourceRoot*: trie.StateRoot
    sourceTime*: StateTime
    epoch*: DisputeEpoch
    validator*: JudgeIndex
    population*: int
    auditor*: StateValidator
  SignedJudgmentClaim* = object ## A plain fixed opaque claim crosses worker boundaries without canonical or mutable ARC aliases.
    ready: bool
    record: AuditJudgment
    info: JudgmentClaimInfo
  ClaimData = ref object ## Immutable source-free ownership contains only fixed completely checked claims.
    records: seq[SignedJudgmentClaim]
    retainedBytes: uint64
  SignedJudgmentBatch* = object ## Only whole-batch success publishes any original signature claim.
    data: nil ClaimData
  JudgmentClaimResult*[T] = object ## Actual selected decoder/state causes remain distinct from policy, membership and cryptographic refusal.
    case status: JudgmentClaimError
    of None: completed: T
    of DecodeFailure: decodeReason: AuditError
    of StateFailure: stateReason: StateStoreError
    of ComponentFailure: componentReason: StateComponentError
    else: discard # A default/failure has no accepted record or unrelated child.

func error*[T](outcome: JudgmentClaimResult[T]): JudgmentClaimError =
  ## Observe status before extracting any complete result or selected cause.
  outcome.status

func value*[T](outcome: JudgmentClaimResult[T]): T {.requires: outcome.status ==
    JudgmentClaimError.None.} =
  ## Only complete success exposes fixed data or a source-free immutable batch.
  outcome.completed

func decodeError*[T](outcome: JudgmentClaimResult[T]): AuditError {.requires: outcome.status ==
    JudgmentClaimError.DecodeFailure.} =
  ## Preserve the actual complete structural refusal without a parser offset or accepted prefix.
  outcome.decodeReason

func stateError*[T](outcome: JudgmentClaimResult[T]): StateStoreError {.requires: outcome.status ==
    JudgmentClaimError.StateFailure.} =
  ## Missing full-state chapters cannot be replaced with fabricated empty rosters.
  outcome.stateReason

func componentError*[T](outcome: JudgmentClaimResult[
    T]): StateComponentError {.requires: outcome.status == JudgmentClaimError.ComponentFailure.} =
  ## Preserve the actual original clock/validator decoder refusal.
  outcome.componentReason

func valid*(limits: JudgmentClaimLimits): bool =
  ## Default or unbounded settings never activate CPU verification; the whole batch remains at most sixteen maximum-sized negative records.
  limits.message.valid and uint64(limits.message.records) <= 16 and
    uint64(limits.message.bytes) > 0 and uint64(limits.message.bytes) <= 16'u64*306 and
    uint64(limits.rosters.cores) == uint64(limits.message.cores) and
    uint64(limits.rosters.validators) == uint64(limits.message.validators) and
    uint64(limits.rosters.maxBytes) > 0 and uint64(limits.rosters.maxBytes) <= 1024'u64*1024 and
    uint64(limits.readBytes) > 0 and uint64(limits.readBytes) <= 4'u64*1024*1024 and
    uint64(limits.workspaceBytes) > 0 and uint64(limits.workspaceBytes) <= 32'u64*1024*1024 and
    uint64(limits.retainedBytes) > 0 and uint64(limits.retainedBytes) <= 1024'u64*1024 and
    uint64(limits.signatures) > 0 and uint64(limits.signatures) <= 64 and
    uint64(limits.signatureBytes) > 0 and uint64(limits.signatureBytes) <= 64'u64*43

func valid*(claim: SignedJudgmentClaim): bool =
  ## Plain copied claim metadata cannot initialize this private success flag.
  claim.ready

func valid*(batch: SignedJudgmentBatch): bool =
  ## Default ownership does not represent an authenticated empty message.
  batch.data != nil

func claimInfo*(claim: SignedJudgmentClaim): JudgmentClaimInfo {.requires: claim.ready.} =
  ## Fixed original membership/source observations are detached from every full-state owner.
  claim.info

func judgmentRecord*(claim: SignedJudgmentClaim): AuditJudgment {.requires: claim.ready.} =
  ## Negative credentials are still structural claims until report/guarantor qualification; this accessor never upgrades them.
  claim.record

proc len*(batch: SignedJudgmentBatch): int =
  ## A default is unavailable, independently of a valid initialized empty batch.
  let data = batch.data
  if data == nil: return 0
  data.records.len

proc retainedBytes*(batch: SignedJudgmentBatch): uint64 =
  ## Whole fixed-row accounting is safe while other actors lease their unrelated private state.
  let data = batch.data
  if data == nil: return 0
  data.retainedBytes

proc claimAt*(batch: SignedJudgmentBatch, ordinal: int): JudgmentClaimResult[SignedJudgmentClaim] =
  ## Copy one fixed verified claim, without lending any batch sequence or canonical map to its consumer.
  let data = batch.data
  if data == nil: return JudgmentClaimResult[SignedJudgmentClaim](
      status: JudgmentClaimError.Uninitialized)
  if ordinal < 0 or ordinal >= data.records.len:
    return JudgmentClaimResult[SignedJudgmentClaim](status: JudgmentClaimError.InvalidIndex)
  JudgmentClaimResult[SignedJudgmentClaim](status: JudgmentClaimError.None, completed: data.records[ordinal])

proc checkJudgmentRoster(source: BlockSnapshotResult, decoded: JudgmentBatch,
    claims: var seq[SignedJudgmentClaim], failures: var seq[JudgmentClaimError],
    limits: JudgmentClaimLimits, control: AssuranceScanControl, wireLength, retained,
    floor: uint64, reads, signatures: var uint64): JudgmentClaimResult[SignedJudgmentBatch] =
  if control.stopped: return JudgmentClaimResult[SignedJudgmentBatch](
      status: JudgmentClaimError.Cancelled)
  if source.error != GenesisError.None:
    return JudgmentClaimResult[SignedJudgmentBatch](status: JudgmentClaimError.InvalidSource)
  let parameters = source.value.chainParameters
  let epochSlots = parameters.get(epochPeriod)
  if epochSlots == 0 or parameters.get(coreCount) != uint64(limits.message.cores):
    return JudgmentClaimResult[SignedJudgmentBatch](status: JudgmentClaimError.InvalidPolicy)
  let sourceEpoch = source.value.slot div epochSlots
  var needed = false
  for ordinal in 0..<claims.len:
    if claims[ordinal].valid: continue
    let epoch = uint64(uint32(decoded.judgmentAt(ordinal).value.epoch))
    if epoch >= floor and epoch <= sourceEpoch and sourceEpoch-epoch <= 1:
      needed = true
      break
  if not needed: return JudgmentClaimResult[SignedJudgmentBatch](status: JudgmentClaimError.None)
  let state = source.value.stateSnapshot
  for chapter in [8, 9, 11]:
    # Validate every complete chapter length before copying even the first roster or clock byte.
    let selected = state.lookup(chapterKey(StateChapter(chapter)))
    if selected.error != StateStoreError.None:
      return JudgmentClaimResult[SignedJudgmentBatch](status: JudgmentClaimError.StateFailure,
          stateReason: selected.error)
    let length = uint64(selected.value.byteLength)
    if length > uint64(limits.readBytes)-reads or (chapter != 11 and length > uint64(
        limits.rosters.maxBytes)):
      return JudgmentClaimResult[SignedJudgmentBatch](status: JudgmentClaimError.LimitExceeded)
    reads += length
  # Reads<=4MiB, wire<=4896 and count<=16 prove each multiplication/addition before any allocation.
  if 4*reads+2*wireLength+retained+65536 > uint64(limits.workspaceBytes):
    return JudgmentClaimResult[SignedJudgmentBatch](status: JudgmentClaimError.LimitExceeded)
  let clockBytes = state.lookup(chapterKey(StateChapter(11))).value.bytes
  let clock = decodeStateTime(clockBytes)
  if clock.error != StateComponentError.None:
    return JudgmentClaimResult[SignedJudgmentBatch](status: JudgmentClaimError.ComponentFailure,
        componentReason: clock.error)
  if clock.value.consumed != clockBytes.len or uint64(uint32(clock.value.value)) !=
      source.value.slot:
    return JudgmentClaimResult[SignedJudgmentBatch](status: JudgmentClaimError.InvalidSource)
  let epoch = source.value.slot div epochSlots
  let activeBytes = state.lookup(chapterKey(StateChapter(8))).value.bytes
  let active = decodeStateValidators(activeBytes, limits.rosters)
  if active.error != StateComponentError.None:
    return JudgmentClaimResult[SignedJudgmentBatch](status: JudgmentClaimError.ComponentFailure,
        componentReason: active.error)
  let previousBytes = state.lookup(chapterKey(StateChapter(9))).value.bytes
  let previous = decodeStateValidators(previousBytes, limits.rosters)
  if previous.error != StateComponentError.None:
    return JudgmentClaimResult[SignedJudgmentBatch](status: JudgmentClaimError.ComponentFailure,
        componentReason: previous.error)
  if active.value.consumed != activeBytes.len or previous.value.consumed != previousBytes.len:
    return JudgmentClaimResult[SignedJudgmentBatch](status: JudgmentClaimError.InvalidSource)
  for ordinal in 0..<claims.len:
    # Every original epoch/index selects its own actual roster; neither relay TLS identity nor an equal current ordinal can replace it.
    if control.stopped: return JudgmentClaimResult[SignedJudgmentBatch](
        status: JudgmentClaimError.Cancelled)
    if claims[ordinal].valid: continue
    let record = decoded.judgmentAt(ordinal).value
    let originalEpoch = uint64(uint32(record.epoch))
    if originalEpoch < floor or originalEpoch > epoch or epoch-originalEpoch > 1:
      continue
    let roster = if originalEpoch == epoch: active.value.value else: previous.value.value
    let population = roster.validatorCount.value
    let selected = roster.validatorAt(StateValidatorIndex(uint64(uint16(record.validator))))
    if selected.error != StateComponentError.None:
      failures[ordinal] = JudgmentClaimError.InvalidAuditor
      continue
    let auditor = selected.value
    let public = array[32, byte](auditor.ed25519)
    if public == default(array[32, byte]) or public == array[32, byte](nullValidator().ed25519):
      failures[ordinal] = JudgmentClaimError.InvalidAuditor
      continue
    if signatures >= uint64(limits.signatures) or (signatures+1)*43 > uint64(limits.signatureBytes):
      return JudgmentClaimResult[SignedJudgmentBatch](status: JudgmentClaimError.LimitExceeded)
    inc signatures
    var message: seq[byte] = @[]
    for character in (if record.valid: "jam_valid" else: "jam_invalid"): message.add(byte(ord(character)))
    for octet in array[32, byte](record.report): message.add(octet)
    if not verify(EdPublicKey(public), EdSignature(array[64, byte](record.signature)), message):
      failures[ordinal] = JudgmentClaimError.InvalidSignature
      continue
    claims[ordinal] = SignedJudgmentClaim(ready: true, record: record,
      info: JudgmentClaimInfo(sourceHead: source.value.blockHash,
        sourceRoot: source.value.stateRoot,
        sourceTime: clock.value.value, epoch: record.epoch, validator: record.validator,
        population: population, auditor: auditor))
  JudgmentClaimResult[SignedJudgmentBatch](status: JudgmentClaimError.None)

func complete(claims: openArray[SignedJudgmentClaim]): bool =
  for claim in claims:
    if not claim.valid: return false
  true

proc verifyJudgmentClaims*(view: ChainView, wire: openArray[byte], limits: JudgmentClaimLimits,
    control: AssuranceScanControl = default(AssuranceScanControl),
    alternatives: openArray[ChainView] = [], history = false): JudgmentClaimResult[
        SignedJudgmentBatch] =
  ## Run on the fixed managed worker with the entire selected canonical view frozen; whole signature, scratch and retention reservations precede any accepted record.
  if not limits.valid: return JudgmentClaimResult[SignedJudgmentBatch](
      status: JudgmentClaimError.InvalidPolicy)
  if view.fuzzOnly or view.retainedCount > 64 or alternatives.len > 64: return JudgmentClaimResult[
      SignedJudgmentBatch](status: JudgmentClaimError.InvalidSource)
  if control.stopped: return JudgmentClaimResult[SignedJudgmentBatch](
      status: JudgmentClaimError.Cancelled)
  let inspected = inspectJudgments(wire, limits.message)
  if inspected.error != AuditError.None:
    return JudgmentClaimResult[SignedJudgmentBatch](status: JudgmentClaimError.DecodeFailure,
        decodeReason: inspected.error)
  let count = inspected.value
  if sizeof(SignedJudgmentClaim) > 1024 or sizeof(StateValidator) > 512:
    return JudgmentClaimResult[SignedJudgmentBatch](status: JudgmentClaimError.LimitExceeded)
  let retained = 4096'u64+uint64(count)*(uint64(sizeof(SignedJudgmentClaim))+64)
  if retained > uint64(limits.retainedBytes) or uint64(count) > uint64(limits.signatures) or
      uint64(count)*43 > uint64(limits.signatureBytes):
    return JudgmentClaimResult[SignedJudgmentBatch](status: JudgmentClaimError.LimitExceeded)
  let selected = view.bestBlock
  if selected.error != GenesisError.None:
    return JudgmentClaimResult[SignedJudgmentBatch](status: JudgmentClaimError.InvalidSource)
  let parameters = selected.value.chainParameters
  let period = parameters.get(epochPeriod)
  if period == 0:
    return JudgmentClaimResult[SignedJudgmentBatch](status: JudgmentClaimError.InvalidPolicy)
  var floor = 0'u64
  let finalized = view.finalizedBlock
  if finalized.error == GenesisError.None:
    let epoch = finalized.value.slot div period
    if epoch > 0: floor = epoch-1
  let decoded = decodeJudgments(wire, limits.message).value
  var claims = newSeq[SignedJudgmentClaim](count)
  var failures = newSeq[JudgmentClaimError](count)
  var reads, signatures = 0'u64
  let current = checkJudgmentRoster(selected, decoded, claims, failures, limits, control,
      uint64(wire.len), retained, floor, reads, signatures)
  if current.error != JudgmentClaimError.None: return current
  for branch in alternatives:
    if claims.complete: break
    let source = branch.bestBlock
    if branch.fuzzOnly or source.error != GenesisError.None or
        not parameters.sameParameterProfile(source.value.chainParameters): continue
    let checked = checkJudgmentRoster(source, decoded, claims, failures, limits, control,
        uint64(wire.len), retained, floor, reads, signatures)
    if checked.error != JudgmentClaimError.None: return checked
  if history and not claims.complete:
    # An independently retained original epoch can still authorize a successor's receipt.
    var checkedEpoch = selected.value.slot div period
    for offset in 0..<view.retainedCount:
      if claims.complete: break
      let source = view.retainedBlockAt(RetainedBlockIndex(view.retainedCount-1-offset))
      if source.error != GenesisError.None: continue
      let epoch = source.value.slot div period
      if epoch >= checkedEpoch or epoch < floor: continue
      checkedEpoch = epoch
      let checked = checkJudgmentRoster(source, decoded, claims, failures, limits, control,
          uint64(wire.len), retained, floor, reads, signatures)
      if checked.error != JudgmentClaimError.None: return checked
    if not claims.complete and finalized.error == GenesisError.None and
        finalized.value.slot div period < checkedEpoch and finalized.value.slot div period >= floor:
      let checked = checkJudgmentRoster(finalized, decoded, claims, failures, limits, control,
          uint64(wire.len), retained, floor, reads, signatures)
      if checked.error != JudgmentClaimError.None: return checked
  if control.stopped:
    return JudgmentClaimResult[SignedJudgmentBatch](status: JudgmentClaimError.Cancelled)
  for ordinal in 0..<claims.len:
    if claims[ordinal].valid: continue
    let reason = failures[ordinal]
    return JudgmentClaimResult[SignedJudgmentBatch](status:
      if reason == JudgmentClaimError.Uninitialized: JudgmentClaimError.UnknownEpoch else: reason)
  JudgmentClaimResult[SignedJudgmentBatch](status: JudgmentClaimError.None,
    completed: SignedJudgmentBatch(data: ClaimData(records: move(claims), retainedBytes: retained)))

proc hasJudgmentAuthority(view: ChainView, facts: JudgmentClaimInfo): bool =
  if view.fuzzOnly: return false
  let source = view.blockAt(facts.sourceHead)
  source.error == GenesisError.None and
    array[32, byte](source.value.stateRoot) == array[32, byte](facts.sourceRoot) and
    source.value.slot == uint64(uint32(facts.sourceTime))

proc judgmentAuthorityView*(view: ChainView, alternatives: openArray[ChainView],
    claim: SignedJudgmentClaim): ChainView =
  ## Follow the exact authenticated membership source through subsequent receipt stages.
  if not claim.valid: return default(ChainView)
  let facts = claim.claimInfo
  let finalized = view.finalizedBlock
  if finalized.error == GenesisError.None:
    let period = finalized.value.chainParameters.get(epochPeriod)
    if period == 0: return default(ChainView)
    let epoch = finalized.value.slot div period
    if epoch > 0 and uint64(uint32(facts.epoch)) < epoch-1: return default(ChainView)
  if view.hasJudgmentAuthority(facts): return view
  for branch in alternatives:
    let best = branch.bestBlock
    if best.error == GenesisError.None and
        array[32, byte](best.value.blockHash) == array[32, byte](facts.sourceHead) and
        branch.hasJudgmentAuthority(facts): return branch
  for branch in alternatives:
    if branch.hasJudgmentAuthority(facts): return branch
  default(ChainView)
