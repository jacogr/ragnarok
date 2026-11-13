# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Fresh canonical all-local shard checks and durable renewal derive a bounded assurance bitfield; returned facts alone grant no reusable signing authority.

import ./[assurance_duty, assurance_store, assurance_record, availability_proof]
import ../chain/genesis
import ../codec/[assurances, bounded, report_owned]
import ../codec/state/[safrole, availability]
import ../codec/work/report
import ../state/availability/specifier

type
  AssurancePossessionLimits* = object ## Complete source reads, selected coordinates, aggregate read/write/hash work and maximum transient record workspace are independently explicit.
    duty*: AssuranceDutyLimits
    shards*, hashes*: ElementLimit
    ioBytes*, hashBytes*, workspaceBytes*: ByteLimit
  AssurancePossessionInfo* = object ## Fixed observations describe this synchronous check only; a private signer must run the check itself rather than trust caller-provided facts.
    duty*: AssuranceDutyInfo
    bits*: AssuranceBits
    cores*, shards*: int
    promisedAt*: AssuranceTime
  AssurancePossessionError* {.pure.} = enum ## A failed/default check carries no partial bitfield or possession prefix.
    Uninitialized, None, Closed, Faulted, WrongChain, InvalidPolicy, InvalidSelection, InvalidTime,
      LimitExceeded, Cancelled, NoPossession, DutyFailure, PlanningFailure, StorageFailure
  AssurancePossessionResult*[T] = object ## Actual source, geometry and durable-storage failures retain their selected guarded children.
    case status: AssurancePossessionError
    of None: completed: T
    of DutyFailure: dutyReason: AssuranceDutyResult[AssuranceDuty]
    of PlanningFailure: planReason: AvailabilityTransferResult[AvailabilityVerificationInfo]
    of StorageFailure: storageReason: AssuranceStoreResult[StoredAssuranceShard]
    else: discard # No unsuccessful alternative exposes accepted bits or an unrelated successful child.

func error*[T](outcome: AssurancePossessionResult[T]): AssurancePossessionError =
  ## Read the selected outcome before extracting fixed facts or a real failed child.
  outcome.status

func value*[T](outcome: AssurancePossessionResult[T]): T {.requires: outcome.status ==
    AssurancePossessionError.None.} =
  ## Only a complete check exposes its fixed observations, never a reusable signature capability.
  outcome.completed

func dutyError*[T](outcome: AssurancePossessionResult[T]): AssuranceDutyResult[
    AssuranceDuty] {.requires: outcome.status == AssurancePossessionError.DutyFailure.} =
  ## Preserve exact canonical chapter/identity/geometry qualification refusal.
  outcome.dutyReason

func planningError*[T](outcome: AssurancePossessionResult[T]): AvailabilityTransferResult[
    AvailabilityVerificationInfo] {.requires: outcome.status ==
    AssurancePossessionError.PlanningFailure.} =
  ## Retain the actual selected expected-transfer planning failure.
  outcome.planReason

func storageError*[T](outcome: AssurancePossessionResult[T]): AssuranceStoreResult[
    StoredAssuranceShard] {.requires: outcome.status == AssurancePossessionError.StorageFailure.} =
  ## A failed re-verification or barrier remains a failure without a signature or partial bitfield.
  outcome.storageReason

func refused[T](reason: AssurancePossessionError): AssurancePossessionResult[
    T] {.requires: reason notin {AssurancePossessionError.None,
    AssurancePossessionError.DutyFailure, AssurancePossessionError.PlanningFailure,
    AssurancePossessionError.StorageFailure}.} =
  ## Simple refusals cannot contain partially checked source or stored data.
  AssurancePossessionResult[T](status: reason)

func valid*(limits: AssurancePossessionLimits): bool =
  ## All traversal factors are bounded by actual GP domains; policy never guesses missing budgets.
  uint64(limits.duty.chapterBytes) > 0 and uint64(limits.duty.readBytes) > 0 and
    uint64(limits.duty.reports) > 0 and uint64(limits.duty.requests) > 0 and
    uint64(limits.shards) > 0 and uint64(limits.shards) <= 341'u64*1023 and
    uint64(limits.hashes) > 0 and uint64(limits.ioBytes) > 0 and uint64(limits.hashBytes) > 0 and
    uint64(limits.workspaceBytes) > 0 and uint64(limits.workspaceBytes) <= 256'u64*1024*1024

func selected(bits: AssuranceBits, core: int): bool {.requires: core >= 0 and core < 344.} =
  ## Core bits are LSB-first in their fixed native storage; callers enforce the actual profile separately.
  (bits.bytes[core div 8] and byte(1 shl (core mod 8))) != 0

func charge(used: var uint64, amount, ceiling: uint64): bool =
  ## Subtraction preflight proves every aggregate addition before mutation.
  if used > ceiling or amount > ceiling-used: return false
  used += amount
  true

proc expected(duty: AssuranceDuty, core: CoreIndex): AvailabilitySpecifier =
  ## Callers selected only present canonical assignments before extracting their immutable report header.
  let header = duty.assignment(core).value.guarantee.report.ownedReportInfo.value.header
  AvailabilitySpecifier(packageHash: header.packageHash, bundleLength: header.bundleLength,
    erasureRoot: header.erasureRoot, erasureShards: header.erasureShards,
    segmentRoot: header.segmentRoot, segmentCount: header.segmentCount)

proc confirm(owner: var AssuranceStore, specifier: AvailabilitySpecifier,
    request: AvailabilityRequest, now: AssuranceTime): AssurancePossessionResult[bool] =
  ## Retire every payload/record alias in this activation before checking another coordinate; only unavailable/conflicting data clears a core softly.
  let retained = owner.renewAssuranceShard(specifier, request, now)
  if retained.error in [AssuranceStoreError.Missing, AssuranceStoreError.Conflict]:
    return AssurancePossessionResult[bool](status: AssurancePossessionError.None, completed: false)
  if retained.error != AssuranceStoreError.None:
    return AssurancePossessionResult[bool](status: AssurancePossessionError.StorageFailure,
        storageReason: retained)
  let info = retained.value.storedInfo
  if info.error != AssuranceStoreError.None or uint64(now) > high(uint64)-AssuranceRetentionSeconds:
    return AssurancePossessionResult[bool](status: AssurancePossessionError.Faulted)
  if uint64(info.value.retainUntil) < uint64(now)+AssuranceRetentionSeconds:
    return AssurancePossessionResult[bool](status: AssurancePossessionError.Faulted)
  AssurancePossessionResult[bool](status: AssurancePossessionError.None, completed: true)

proc qualifyStoredAssurance*(owner: var AssuranceStore, source: BlockSnapshotResult,
    chain: AssuranceChainId, local: StateEdKey, requested: AssuranceBits, now: AssuranceTime,
    limits: AssurancePossessionLimits, control = default(
        AssuranceScanControl)): AssurancePossessionResult[AssurancePossessionInfo] =
  ## Execute only under the exclusive fixed-owner/source lease; the private signer calls this directly immediately before its single signature.
  if not owner.opened: return refused[AssurancePossessionInfo](AssurancePossessionError.Closed)
  if owner.faulted: return refused[AssurancePossessionInfo](AssurancePossessionError.Faulted)
  if not owner.matchesChain(chain): return refused[AssurancePossessionInfo](
      AssurancePossessionError.WrongChain)
  if not limits.valid: return refused[AssurancePossessionInfo](
      AssurancePossessionError.InvalidPolicy)
  if uint64(now) > high(uint64)-AssuranceRetentionSeconds: return refused[AssurancePossessionInfo](
      AssurancePossessionError.InvalidTime)
  if control.stopped: return refused[AssurancePossessionInfo](AssurancePossessionError.Cancelled)
  let qualified = captureAssuranceDuty(source, local, limits.duty)
  if qualified.error != AssuranceDutyError.None:
    return AssurancePossessionResult[AssurancePossessionInfo](
        status: AssurancePossessionError.DutyFailure, dutyReason: qualified)
  let duty = qualified.value
  let facts = duty.dutyInfo.value
  let cores = int(uint64(facts.cores))
  for core in cores..<344:
    # Neither tail bits nor unused native suffix bytes may disappear silently from a signed selection.
    if requested.selected(core): return refused[AssurancePossessionInfo](
        AssurancePossessionError.InvalidSelection)
  var shards = 0'u64
  var ioBytes = 0'u64
  var hashes = 0'u64
  var hashBytes = 0'u64
  if not charge(hashes, 1, uint64(limits.hashes)) or
      not charge(hashBytes, uint64(32+(cores+7) div 8), uint64(limits.hashBytes)):
    return refused[AssurancePossessionInfo](AssurancePossessionError.LimitExceeded)
  for core in 0..<cores:
    # Complete selected-core/coordinate preflight precedes every record read, renewal hash and signature transcript hash.
    if not requested.selected(core): continue
    if not duty.assignment(CoreIndex(core)).value.present:
      return refused[AssurancePossessionInfo](AssurancePossessionError.InvalidSelection)
    let specifier = duty.expected(CoreIndex(core))
    for ordinal in 0..<facts.localIndices:
      # Repeated identities preserve every original roster position, even when their signatures are interchangeable on the wire.
      if control.stopped: return refused[AssurancePossessionInfo](
          AssurancePossessionError.Cancelled)
      let request = duty.shardRequest(CoreIndex(core), ordinal).value
      let planned = availabilityVerificationInfo(specifier, request)
      if planned.error != AvailabilityTransferError.None:
        return AssurancePossessionResult[AssurancePossessionInfo](
            status: AssurancePossessionError.PlanningFailure, planReason: planned)
      let work = planned.value
      if work.payloadBytes > 16'u64*1024*1024 or
          work.payloadBytes*3+uint64(AssuranceRecordHeaderBytes) > uint64(limits.workspaceBytes):
        return refused[AssurancePossessionInfo](AssurancePossessionError.LimitExceeded)
      if not charge(shards, 1, uint64(limits.shards)):
        return refused[AssurancePossessionInfo](AssurancePossessionError.LimitExceeded)
      let encoded = work.payloadBytes+uint64(AssuranceRecordHeaderBytes)
      if not charge(ioBytes, encoded*2+1, uint64(limits.ioBytes)):
        return refused[AssurancePossessionInfo](AssurancePossessionError.LimitExceeded)
      if not charge(hashes, work.hashes+2, uint64(limits.hashes)):
        return refused[AssurancePossessionInfo](AssurancePossessionError.LimitExceeded)
      if not charge(hashBytes, work.hashBytes+348, uint64(limits.hashBytes)):
        return refused[AssurancePossessionInfo](AssurancePossessionError.LimitExceeded)
  var info = AssurancePossessionInfo(duty: facts, bits: default(AssuranceBits), cores: 0,
    shards: 0, promisedAt: now)
  for core in 0..<cores:
    # Missing any assigned local coordinate clears the whole core while allowing other fully verified selected cores.
    if not requested.selected(core): continue
    let specifier = duty.expected(CoreIndex(core))
    var complete = true
    for ordinal in 0..<facts.localIndices:
      # Only one record graph is resident; every completed renewal has crossed the actual file+directory barrier.
      if control.stopped: return refused[AssurancePossessionInfo](
          AssurancePossessionError.Cancelled)
      let checked = owner.confirm(specifier, duty.shardRequest(CoreIndex(core), ordinal).value, now)
      if checked.error != AssurancePossessionError.None:
        return AssurancePossessionResult[AssurancePossessionInfo](
            status: AssurancePossessionError.StorageFailure, storageReason: checked.storageError)
      if not checked.value:
        complete = false
        break
    if complete:
      # Set the LSB-first bit only after all original local positions are durably retained and their complete proofs reverified.
      info.bits.bytes[core div 8] = info.bits.bytes[core div 8] or byte(1 shl (core mod 8))
      inc info.cores
      info.shards += facts.localIndices
  if info.cores == 0: return refused[AssurancePossessionInfo](AssurancePossessionError.NoPossession)
  if control.stopped: return refused[AssurancePossessionInfo](AssurancePossessionError.Cancelled)
  AssurancePossessionResult[AssurancePossessionInfo](status: AssurancePossessionError.None,
      completed: info)
