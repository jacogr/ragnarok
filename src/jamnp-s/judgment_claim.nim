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
    uint64(limits.signatures) > 0 and uint64(limits.signatures) <= 16 and
    uint64(limits.signatureBytes) > 0 and uint64(limits.signatureBytes) <= 16'u64*43
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
proc verifyJudgmentClaims*(view: ChainView, wire: openArray[byte], limits: JudgmentClaimLimits,
    control: AssuranceScanControl = default(AssuranceScanControl)): JudgmentClaimResult[
        SignedJudgmentBatch] =
  ## Run on the fixed managed worker with the entire selected canonical view frozen; whole signature, scratch and retention reservations precede any accepted record.
  if not limits.valid: return JudgmentClaimResult[SignedJudgmentBatch](
      status: JudgmentClaimError.InvalidPolicy)
  if view.fuzzOnly: return JudgmentClaimResult[SignedJudgmentBatch](
      status: JudgmentClaimError.InvalidSource)
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
  let source = view.bestBlock
  if source.error != GenesisError.None:
    return JudgmentClaimResult[SignedJudgmentBatch](status: JudgmentClaimError.InvalidSource)
  let parameters = source.value.chainParameters
  let epochSlots = parameters.get(epochPeriod)
  if epochSlots == 0 or parameters.get(coreCount) != uint64(limits.message.cores):
    return JudgmentClaimResult[SignedJudgmentBatch](status: JudgmentClaimError.InvalidPolicy)
  let state = source.value.stateSnapshot
  var reads = 0'u64
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
  if 4*reads+2*uint64(wire.len)+retained+65536 > uint64(limits.workspaceBytes):
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
  let previousBytes = state.lookup(chapterKey(StateChapter(9))).value.bytes
  let active = decodeStateValidators(activeBytes, limits.rosters)
  let previous = decodeStateValidators(previousBytes, limits.rosters)
  if active.error != StateComponentError.None:
    return JudgmentClaimResult[SignedJudgmentBatch](status: JudgmentClaimError.ComponentFailure,
        componentReason: active.error)
  if previous.error != StateComponentError.None:
    return JudgmentClaimResult[SignedJudgmentBatch](status: JudgmentClaimError.ComponentFailure,
        componentReason: previous.error)
  if active.value.consumed != activeBytes.len or previous.value.consumed != previousBytes.len:
    return JudgmentClaimResult[SignedJudgmentBatch](status: JudgmentClaimError.InvalidSource)
  let decoded = decodeJudgments(wire, limits.message).value
  var claims = newSeq[SignedJudgmentClaim](count)
  for ordinal in 0..<count:
    # Every original epoch/index selects its own actual roster; neither relay TLS identity nor an equal current ordinal can replace it.
    if control.stopped: return JudgmentClaimResult[SignedJudgmentBatch](
        status: JudgmentClaimError.Cancelled)
    let record = decoded.judgmentAt(ordinal).value
    let originalEpoch = uint64(uint32(record.epoch))
    if originalEpoch != epoch and (epoch == 0 or originalEpoch != epoch-1):
      return JudgmentClaimResult[SignedJudgmentBatch](status: JudgmentClaimError.UnknownEpoch)
    let roster = if originalEpoch == epoch: active.value.value else: previous.value.value
    let population = roster.validatorCount.value
    let selected = roster.validatorAt(StateValidatorIndex(uint64(uint16(record.validator))))
    if selected.error != StateComponentError.None:
      return JudgmentClaimResult[SignedJudgmentBatch](status: JudgmentClaimError.InvalidAuditor)
    let auditor = selected.value
    let public = array[32, byte](auditor.ed25519)
    if public == default(array[32, byte]) or public == array[32, byte](nullValidator().ed25519):
      return JudgmentClaimResult[SignedJudgmentBatch](status: JudgmentClaimError.InvalidAuditor)
    var message: seq[byte] = @[]
    for character in (if record.valid: "jam_valid" else: "jam_invalid"): message.add(byte(ord(character)))
    for octet in array[32, byte](record.report): message.add(octet)
    if not verify(EdPublicKey(public), EdSignature(array[64, byte](record.signature)), message):
      return JudgmentClaimResult[SignedJudgmentBatch](status: JudgmentClaimError.InvalidSignature)
    claims[ordinal] = SignedJudgmentClaim(ready: true, record: record,
      info: JudgmentClaimInfo(sourceHead: source.value.blockHash,
        sourceRoot: source.value.stateRoot,
        sourceTime: clock.value.value, epoch: record.epoch, validator: record.validator,
        population: population, auditor: auditor))
  if control.stopped: return JudgmentClaimResult[SignedJudgmentBatch](
      status: JudgmentClaimError.Cancelled)
  JudgmentClaimResult[SignedJudgmentBatch](status: JudgmentClaimError.None,
    completed: SignedJudgmentBatch(data: ClaimData(records: move(claims), retainedBytes: retained)))
