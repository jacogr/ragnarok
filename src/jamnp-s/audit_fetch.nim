# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Detached CE147/138 routing plans derive original identities and shard coordinates from an authenticated audit source. Plans carry no full-state, report, evaluation or private-key aliases and grant no judgment authority.

import ./[audit_origin, audit_context, availability_proof, read_stream, endpoints]
import ../codec/[bounded, guarantees, report_owned]
import ../codec/state/safrole
import ../chain/[genesis, reports]
import ../state/availability/specifier
import ../state/erasure/[layout, words]

type
  AuditFetchLimits* = object ## Whole fixed routing storage and each bounded reply require independent explicit admission.
    bytes*, replyBytes*: ByteLimit
  AuditFetchError* {.pure.} = enum ## A failed/default plan exposes no target prefix or fabricated audit result.
    Uninitialized, None, InvalidPolicy, InvalidOrigin, InvalidIndex, LimitExceeded,
    UnavailableRoster, GeometryFailure, InvalidPacket, TransferFailure
  AuditFetchInfo* = object ## Fixed observations identify the original report independently of native peers or later canonical heads.
    blockReference: AuditBlockReference
    reportHash*: WorkReportHash
    specifier*: AvailabilitySpecifier
    guarantors*, assurers*, threshold*: int
    retainedBytes*: uint64
  AuditFetchTarget* = object ## Original roster ordinals, expected TLS identity and endpoint remain distinct from compressed plan-row positions.
    validator*: StateValidatorIndex
    identity*: StateEdKey
    endpoint*: EndpointResult
    shard*: ErasureShardIndex
  FetchData = ref object ## Private immutable copied fixed routing facts retain no source-bearing ownership.
    info: AuditFetchInfo
    guarantors, assurers: seq[AuditFetchTarget]
    replyBytes: ByteLimit
  AuditFetchPlan* = object ## Only actual retained-origin capture constructs a non-default routing owner.
    data: nil FetchData
  AuditFetchResult*[T] = object ## Private tags guard every successful extraction.
    case status: AuditFetchError
    of None: completed: T
    of TransferFailure: transferReason: AvailabilityTransferResult[VerifiedAvailabilityTransfer]
    else: discard               # No source, successful prefix or judgment capability survives refusal.

func error*[T](outcome: AuditFetchResult[T]): AuditFetchError =
  ## Inspect the selected status before reading a completed plan or fixed routing record.
  outcome.status

func value*[T](outcome: AuditFetchResult[T]): T {.requires: outcome.status ==
    AuditFetchError.None.} =
  ## Success exposes only detached immutable routing and exact request bytes.
  outcome.completed

func transferError*[T](outcome: AuditFetchResult[T]): AvailabilityTransferResult[
    VerifiedAvailabilityTransfer] {.requires: outcome.status == AuditFetchError.TransferFailure.} =
  ## Preserve the actual original-coordinate proof refusal, without replacing a backend failure with a report judgment.
  outcome.transferReason

func hasAuditedBlock*(info: AuditFetchInfo): bool =
  ## A disputed-only fetch plan carries no fabricated availability-block identity.
  info.blockReference.present

func blockHash*(info: AuditFetchInfo): genesis.BlockHash {.requires: info.blockReference.present.} =
  ## Genuine available-report plans preserve their original guarded copied block identity.
  info.blockReference.value

func valid*(limits: AuditFetchLimits): bool =
  ## Default caps never activate retrieval; the wire bound includes the largest legal original bundle and framing.
  uint64(limits.bytes) > 0 and uint64(limits.bytes) <= 4'u64*1024*1024 and
    uint64(limits.replyBytes) >= 8 and uint64(limits.replyBytes) <= 16'u64*1024*1024

func valid*(plan: AuditFetchPlan): bool =
  ## Missing plans cannot authorize even an empty network request.
  plan.data != nil

proc fetchInfo*(plan: AuditFetchPlan): AuditFetchResult[AuditFetchInfo] =
  ## Fixed source observations remain safe while Services leases its separate private state to a worker.
  let data = plan.data
  if data == nil: return AuditFetchResult[AuditFetchInfo](status: AuditFetchError.Uninitialized)
  AuditFetchResult[AuditFetchInfo](status: AuditFetchError.None, completed: data.info)

proc targetAt*(plan: AuditFetchPlan, recovery: bool, ordinal: int): AuditFetchResult[
    AuditFetchTarget] =
  ## Recovery selects original assurer coordinates; direct requests select original credential identities.
  let data = plan.data
  if data == nil: return AuditFetchResult[AuditFetchTarget](status: AuditFetchError.Uninitialized)
  let count = if recovery: data.assurers.len else: data.guarantors.len
  if ordinal < 0 or ordinal >= count:
    return AuditFetchResult[AuditFetchTarget](status: AuditFetchError.InvalidIndex)
  let target = if recovery: data.assurers[ordinal] else: data.guarantors[ordinal]
  AuditFetchResult[AuditFetchTarget](status: AuditFetchError.None, completed: target)

proc requestAt*(plan: AuditFetchPlan, recovery: bool, ordinal: int): AuditFetchResult[ReadRequest] =
  ## Independent original coordinates determine the exact CE138 request; no caller-supplied root or shard can replace them.
  let selected = plan.targetAt(recovery, ordinal)
  if selected.error != AuditFetchError.None:
    return AuditFetchResult[ReadRequest](status: selected.error)
  let data = plan.data
  if data == nil: return AuditFetchResult[ReadRequest](status: AuditFetchError.Uninitialized)
  var payload = newSeq[byte](if recovery: 34 else: 32)
  for index in 0..<32: payload[index] = data.info.specifier.erasureRoot.bytes[index]
  if recovery:
    # Original N<=1023 proves both fixed E2 bytes fit without narrowing an untrusted integer.
    let shard = uint64(selected.value.shard)
    payload[32] = byte(shard and 255)
    payload[33] = byte(shard shr 8)
  let request = decodeReadRequest(if recovery: ReadKind.Audit else: ReadKind.Bundle, payload)
  if request.error != ReadError.None:
    return AuditFetchResult[ReadRequest](status: AuditFetchError.InvalidOrigin)
  AuditFetchResult[ReadRequest](status: AuditFetchError.None, completed: request.value)

func replyLimit*(plan: AuditFetchPlan, recovery = false): ByteLimit =
  ## A missing plan grants zero response storage; native controllers independently enforce this cap before copying bytes.
  let data = plan.data
  if data == nil: return ByteLimit(0)
  if recovery and uint64(data.replyBytes) > uint64(MaxReadReplyBytes): return ByteLimit(MaxReadReplyBytes)
  data.replyBytes

proc captureAuditFetch*(origin: AuditReportOrigin, limits: AuditFetchLimits): AuditFetchResult[
    AuditFetchPlan] =
  ## Run under the source's exclusive lease: reserve all detached rows before copying any keys, metadata or allocating a target prefix.
  if not limits.valid: return AuditFetchResult[AuditFetchPlan](
      status: AuditFetchError.InvalidPolicy)
  if not origin.valid: return AuditFetchResult[AuditFetchPlan](
      status: AuditFetchError.InvalidOrigin)
  let guarantee = origin.originGuarantee.value
  let report = guarantee.report.ownedReportInfo.value
  let header = report.header
  let geometry = erasureGeometry(header.bundleLength, header.erasureShards)
  if geometry.error != ErasureLayoutError.None:
    return AuditFetchResult[AuditFetchPlan](status: AuditFetchError.GeometryFailure)
  let population = uint64(uint16(header.erasureShards))
  var rows = 0'u64
  for roster in 0..<origin.routingRosterCount:
    # Every known candidate epoch is queried separately when compatible; matching N never selects or fabricates an actual assurance epoch.
    if uint64(origin.routingPopulation(roster).value) == population: rows += population
  if rows == 0: return AuditFetchResult[AuditFetchPlan](status: AuditFetchError.UnavailableRoster)
  if guarantee.credentialCount < 2 or guarantee.credentialCount > 3 or sizeof(AuditFetchTarget) > 512:
    return AuditFetchResult[AuditFetchPlan](status: AuditFetchError.InvalidOrigin)
  let reservation = 4096'u64+(rows+3)*(uint64(sizeof(AuditFetchTarget))+64)
  if reservation > uint64(limits.bytes):
    return AuditFetchResult[AuditFetchPlan](status: AuditFetchError.LimitExceeded)
  if uint64(uint32(header.bundleLength))+4 > uint64(limits.replyBytes) or
      geometry.value.bundleChunkBytes+4096 > uint64(limits.replyBytes):
    return AuditFetchResult[AuditFetchPlan](status: AuditFetchError.LimitExceeded)
  var guarantors: seq[AuditFetchTarget] = @[]
  for ordinal in 0..<guarantee.credentialCount:
    # The guarantee slot selects its independently authenticated original C8/C9 credential roster.
    let selected = origin.originGuarantor(ordinal)
    if selected.error != AuditOriginError.None:
      return AuditFetchResult[AuditFetchPlan](status: AuditFetchError.UnavailableRoster)
    let validator = selected.value
    guarantors.add(AuditFetchTarget(validator: StateValidatorIndex(uint64(uint16(
      guarantee.credentials[ordinal].validator))), identity: validator.ed25519,
      endpoint: validatorEndpoint(array[128, byte](validator.metadata))))
  var assurers: seq[AuditFetchTarget] = @[]
  for roster in 0..<origin.routingRosterCount:
    # Available reports retain actual prior-C8 assurership. Unseen reports query all compatible authenticated candidate rosters; proof roots and original coordinates, never a guessed epoch, authenticate recovered bytes.
    if uint64(origin.routingPopulation(roster).value) != population: continue
    for ordinal in 0..<int(population):
      # Keep null/repeated positions and original coordinate arithmetic even when several candidate rosters have the same population.
      let validator = origin.routingValidator(roster, ordinal).value
      let shard = (uint64(report.core)*geometry.value.originalShards+uint64(ordinal)) mod population
      assurers.add(AuditFetchTarget(validator: StateValidatorIndex(uint64(ordinal)),
        identity: validator.ed25519, endpoint: validatorEndpoint(array[128, byte](
            validator.metadata)),
        shard: ErasureShardIndex(shard)))
  AuditFetchResult[AuditFetchPlan](status: AuditFetchError.None, completed: AuditFetchPlan(
    data: FetchData(info: AuditFetchInfo(blockReference: origin.auditedBlock,
      reportHash: origin.originReportHash.value,
      specifier: AvailabilitySpecifier(packageHash: header.packageHash,
        bundleLength: header.bundleLength, erasureRoot: header.erasureRoot,
        erasureShards: header.erasureShards, segmentRoot: header.segmentRoot,
        segmentCount: header.segmentCount),
      guarantors: guarantors.len, assurers: assurers.len,
      threshold: int(geometry.value.originalShards), retainedBytes: reservation),
      guarantors: move(guarantors), assurers: move(assurers), replyBytes: limits.replyBytes)))

proc frameLength(wire: openArray[byte], offset: int): uint64 {.requires: offset >= 0 and offset <= wire.len-4.} =
  ## Exact E4 reads require the complete prefix, avoiding arithmetic on an untrusted announced length.
  uint64(wire[offset]) or (uint64(wire[offset+1]) shl 8) or
    (uint64(wire[offset+2]) shl 16) or (uint64(wire[offset+3]) shl 24)

proc directBundle*(plan: AuditFetchPlan, wire: openArray[byte]): AuditFetchResult[seq[byte]] =
  ## Complete CE147 framing produces untrusted candidate bytes only; genuine private reproduction decides whether they are useful.
  let data = plan.data
  if data == nil: return AuditFetchResult[seq[byte]](status: AuditFetchError.Uninitialized)
  if uint64(wire.len) > uint64(data.replyBytes):
    return AuditFetchResult[seq[byte]](status: AuditFetchError.LimitExceeded)
  if wire.len < 4 or frameLength(wire, 0) != uint64(wire.len-4):
    return AuditFetchResult[seq[byte]](status: AuditFetchError.InvalidPacket)
  if uint64(wire.len-4) != uint64(uint32(data.info.specifier.bundleLength)):
    return AuditFetchResult[seq[byte]](status: AuditFetchError.InvalidPacket)
  var bytes = newSeq[byte](wire.len-4)
  for index in 0..<bytes.len: bytes[index] = wire[index+4]
  AuditFetchResult[seq[byte]](status: AuditFetchError.None, completed: move(bytes))

proc verifyAuditFetchShard*(plan: AuditFetchPlan, ordinal: int, wire: openArray[byte],
    limits: AvailabilityMerkleLimits): AuditFetchResult[VerifiedAvailabilityTransfer] =
  ## Validate both exact response extents before hashing, copying or accepting the original expected root and coordinate. Native callbacks must not call this CPU operation.
  let data = plan.data
  if data == nil: return AuditFetchResult[VerifiedAvailabilityTransfer](
      status: AuditFetchError.Uninitialized)
  let target = plan.targetAt(true, ordinal)
  if target.error != AuditFetchError.None:
    return AuditFetchResult[VerifiedAvailabilityTransfer](status: target.error)
  if uint64(wire.len) > uint64(plan.replyLimit(true)):
    return AuditFetchResult[VerifiedAvailabilityTransfer](status: AuditFetchError.LimitExceeded)
  if wire.len < 8:
    return AuditFetchResult[VerifiedAvailabilityTransfer](status: AuditFetchError.InvalidPacket)
  let geometry = erasureGeometry(data.info.specifier.bundleLength,
      data.info.specifier.erasureShards).value
  let width = frameLength(wire, 0)
  if width != geometry.bundleChunkBytes or width == 0 or width > uint64(wire.len-8):
    return AuditFetchResult[VerifiedAvailabilityTransfer](status: AuditFetchError.InvalidPacket)
  let second = 4+int(width)
  let proof = frameLength(wire, second)
  if proof == 0 or proof != uint64(wire.len-second-4):
    return AuditFetchResult[VerifiedAvailabilityTransfer](status: AuditFetchError.InvalidPacket)
  let request = AvailabilityRequest(kind: AvailabilityTransferKind.Audit,
    root: data.info.specifier.erasureRoot, shard: target.value.shard)
  let checked = verifyAvailabilityTransfer(data.info.specifier, request,
    wire.toOpenArray(4, second-1), [], wire.toOpenArray(second+4, wire.len-1), limits)
  if checked.error != AvailabilityTransferError.None:
    return AuditFetchResult[VerifiedAvailabilityTransfer](status: AuditFetchError.TransferFailure,
      transferReason: checked)
  AuditFetchResult[VerifiedAvailabilityTransfer](status: AuditFetchError.None,
      completed: checked.value)
