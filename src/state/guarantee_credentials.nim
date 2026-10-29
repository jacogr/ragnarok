# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 reporting_assurance.tex guarantorsig/reporters and active-population erasure-shard
## equality. This certifies credentials only; history, authorization, service/gas and package
## checks precede C(10) publication.
##
## Exposes verifyGuaranteeCredentials and immutable verified-guarantee/reporter/context access
## with typed structure/assignment failures.

import ../codec/[guarantees, assurances, bounded]
import ../codec/state/safrole as state_safrole
import ../codec/[disputes, report_owned, owned, natural]
import ../crypto/[primitives, guarantee]
import ./guarantors

type
  GuaranteeCredentialConfig* = object ## One assignment profile, aggregate canonical extrinsic byte budget and distinct reporter-key ceiling.
    assignments*: GuarantorConfig
    maxBytes*: ByteLimit
    reporters*: ElementLimit
  GuaranteeCredentialError* {.pure.} = enum ## Failure alternatives have no successfully certified records, reporter keys or partial counts.
    Uninitialized, None, StructureFailure, AssignmentFailure, InactiveCore, WrongErasureShards,
    WrongAssignment, InvalidSignature, BackendFailure, LimitExceeded, InvalidIndex
  VerifiedGuaranteeContext* = object ## Copied candidate context belongs to the completed verification, including an empty guarantee batch.
    slot*: StateTime
    population*: ValidatorCount
  ## Private acyclic storage keeps copied guarantees/report handles and the exact assignment context together.
  CredentialData = ref object
    assignments: GuarantorPlan
    context: VerifiedGuaranteeContext
    guarantees: seq[Guarantee]
    reporters: seq[StateEdKey]
  VerifiedGuaranteeCredentials* = object ## Immutable success handle cannot be forged by substituting a key table or mutable report buffer.
    data: nil CredentialData
  GuaranteeCredentialResult*[T] = object ## Selected success alone carries application data; selected child failures alone carry their exact cause.
    case status: GuaranteeCredentialError
    of None:
      completed: T
    of StructureFailure:
      structureReason: GuaranteeError
    of AssignmentFailure:
      assignmentReason: GuarantorError
    else:
      discard # Defaults and other failures carry their reason only.

func error*[T](outcome: GuaranteeCredentialResult[T]): GuaranteeCredentialError =
  ## Expose the status without permitting external retagging.
  outcome.status
func value*[T](outcome: GuaranteeCredentialResult[T]): T {.inline,
    requires: outcome.status == GuaranteeCredentialError.None.} =
  ## Extract only a completed operation under supported optimized-build contracts.
  outcome.completed
func structureError*[T](outcome: GuaranteeCredentialResult[T]): GuaranteeError {.inline,
    requires: outcome.status == GuaranteeCredentialError.StructureFailure.} =
  ## Inspect the codec's precise refusal only when the structure-failure alternative is selected.
  outcome.structureReason
func assignmentError*[T](outcome: GuaranteeCredentialResult[T]): GuarantorError {.inline,
    requires: outcome.status == GuaranteeCredentialError.AssignmentFailure.} =
  ## Inspect rotation/profile/index/slot failures only when the assignment-failure alternative is selected.
  outcome.assignmentReason

proc verifiedGuaranteeCount*(owner: VerifiedGuaranteeCredentials): GuaranteeCredentialResult[int] =
  ## Count completed guarantees without treating a default owner as a successfully verified empty extrinsic.
  let data = owner.data
  if data == nil:
    return GuaranteeCredentialResult[int](status: GuaranteeCredentialError.Uninitialized) # No owner.
  GuaranteeCredentialResult[int](status: GuaranteeCredentialError.None,
      completed: data.guarantees.len)

proc verifiedGuaranteeContext*(owner: VerifiedGuaranteeCredentials): GuaranteeCredentialResult[
    VerifiedGuaranteeContext] =
  ## Retain candidate time and current active population from the exact completed verification context.
  let data = owner.data
  if data == nil:
    return GuaranteeCredentialResult[VerifiedGuaranteeContext](
        status: GuaranteeCredentialError.Uninitialized) # No invented genesis context.
  GuaranteeCredentialResult[VerifiedGuaranteeContext](status: GuaranteeCredentialError.None,
      completed: data.context)

proc verifiedGuaranteeAt*(owner: VerifiedGuaranteeCredentials,
    index: int): GuaranteeCredentialResult[Guarantee] =
  ## Return one copied record retaining its immutable report; modifying the copy cannot change this verified owner.
  let data = owner.data
  if data == nil:
    return GuaranteeCredentialResult[Guarantee](status: GuaranteeCredentialError.Uninitialized) # No records.
  if index < 0 or index >= data.guarantees.len:
    return GuaranteeCredentialResult[Guarantee](status: GuaranteeCredentialError.InvalidIndex) # Check signed ordinal.
  GuaranteeCredentialResult[Guarantee](status: GuaranteeCredentialError.None,
      completed: data.guarantees[index])

proc verifiedReporterCount*(owner: VerifiedGuaranteeCredentials): GuaranteeCredentialResult[int] =
  ## Count distinct signing Ed25519 keys, not credential indices or signature occurrences.
  let data = owner.data
  if data == nil:
    return GuaranteeCredentialResult[int](status: GuaranteeCredentialError.Uninitialized) # No fabricated empty set.
  GuaranteeCredentialResult[int](status: GuaranteeCredentialError.None,
      completed: data.reporters.len)

proc verifiedReporterAt*(owner: VerifiedGuaranteeCredentials,
    index: int): GuaranteeCredentialResult[StateEdKey] =
  ## Extract a copied reporter identity in deterministic lexicographic order, bound to its successful owner.
  let data = owner.data
  if data == nil:
    return GuaranteeCredentialResult[StateEdKey](status: GuaranteeCredentialError.Uninitialized) # No key set.
  if index < 0 or index >= data.reporters.len:
    return GuaranteeCredentialResult[StateEdKey](status: GuaranteeCredentialError.InvalidIndex) # No unchecked access.
  GuaranteeCredentialResult[StateEdKey](status: GuaranteeCredentialError.None,
      completed: data.reporters[index])

## Compare exact public-key octets for set ordering; curve validity remains the maintained backend's policy.
func compare(a, b: StateEdKey): int =
  let left = array[32, byte](a)
  let right = array[32, byte](b)
  for i in 0..<32:
    if left[i] < right[i]: return -1 # First different byte establishes the smaller key.
    if left[i] > right[i]: return 1 # First different byte establishes the larger key.
  0

## Insert a verified key into bounded sorted scratch without counting duplicate identities twice.
proc includeReporter(keys: var seq[StateEdKey], key: StateEdKey, ceiling: ElementLimit): bool =
  var first = 0
  var last = keys.len
  while first < last:
    let middle = first+(last-first) div 2
    let order = compare(key, keys[middle])
    if order == 0: return true # Existing identity consumes no additional reporter budget.
    if order < 0:
      last = middle # Continue within the lower half of the canonical set.
    else:
      first = middle+1 # Continue within the upper half.
  if uint64(keys.len) >= uint64(ceiling): return false # Refuse before extending storage.
  keys.add(key)
  var cursor = keys.len-1
  while cursor > first:
    let prior = keys[cursor-1]
    keys[cursor] = prior # Shift copied fixed keys without borrowing an overlapping sequence element.
    dec cursor
  keys[first] = key
  true

proc verifyGuaranteeCredentials*(values: openArray[Guarantee], active,
    previous: ValidatorStateSnapshot, entropy: StateEntropy, slot: StateTime, offenders: openArray[
        OffenderKey],
    config: GuaranteeCredentialConfig): GuaranteeCredentialResult[VerifiedGuaranteeCredentials] =
  ## Verify one stable borrowed batch against completed posterior context, retaining only complete success.
  ## Canonical source preflight bounds all scratch before hashing. Context authentication and full admission are external.
  let wire = GuaranteeConfig(cores: config.assignments.roster.cores,
    validators: ValidatorCount(uint64(config.assignments.roster.validators)),
        maxBytes: config.maxBytes)
  if not validConfig(AssuranceConfig(cores: wire.cores, validators: wire.validators)):
    return GuaranteeCredentialResult[VerifiedGuaranteeCredentials](
      status: GuaranteeCredentialError.StructureFailure,
      structureReason: GuaranteeError.InvalidConfig) # Explicit chain domains precede count narrowing.
  if uint64(values.len) > uint64(wire.cores):
    return GuaranteeCredentialResult[VerifiedGuaranteeCredentials](
        status: GuaranteeCredentialError.LimitExceeded) # At most one report per core.
  var total = uint64(natural.encode(JamNatural(values.len)).len)
  var priorCore = 0'u64
  for i, value in values:
    let size = measureGuarantee(value, wire)
    if size.error != GuaranteeError.None:
      return GuaranteeCredentialResult[VerifiedGuaranteeCredentials](
        status: GuaranteeCredentialError.StructureFailure,
        structureReason: size.error) # All child owners, credential counts and ordinal ordering must be canonical.
    let core = uint64(ownedReportInfo(value.report).value.core)
    if i > 0 and core <= priorCore:
      return GuaranteeCredentialResult[VerifiedGuaranteeCredentials](
        status: GuaranteeCredentialError.StructureFailure,
        structureReason: GuaranteeError.NonCanonical) # No core sorting/deduplication fallback.
    priorCore = core
    if total > uint64(config.maxBytes) or uint64(size.value) > uint64(config.maxBytes)-total:
      return GuaranteeCredentialResult[VerifiedGuaranteeCredentials](
          status: GuaranteeCredentialError.LimitExceeded) # Check before aggregate addition.
    total += uint64(size.value)
  if total > uint64(config.maxBytes):
    return GuaranteeCredentialResult[VerifiedGuaranteeCredentials](
        status: GuaranteeCredentialError.LimitExceeded) # Empty extrinsics still have a count byte.
  let planned = planGuarantors(active, previous, entropy, slot, offenders, config.assignments)
  if planned.error != GuarantorError.None:
    return GuaranteeCredentialResult[VerifiedGuaranteeCredentials](
      status: GuaranteeCredentialError.AssignmentFailure,
      assignmentReason: planned.error) # Empty batches also require valid posterior context.
  let population = uint64(validatorCount(active).value)
  let data = CredentialData(assignments: planned.value, guarantees: newSeq[Guarantee](values.len),
      reporters: @[], context: VerifiedGuaranteeContext(slot: slot, population: ValidatorCount(population)))
  for i, value in values:
    let info = ownedReportInfo(value.report).value
    let core = uint64(info.core)
    if core >= population div 3:
      return GuaranteeCredentialResult[VerifiedGuaranteeCredentials](
          status: GuaranteeCredentialError.InactiveCore) # Current activity overrides previous-rotation capacity.
    if uint64(info.header.erasureShards) != population:
      return GuaranteeCredentialResult[VerifiedGuaranteeCredentials](
          status: GuaranteeCredentialError.WrongErasureShards) # Current population even for previous credentials.
    var keys = default(array[3, StateEdKey])
    for j in 0..<value.credentialCount:
      let assigned = planned.value.guarantorAt(value.slot, value.credentials[j].validator)
      if assigned.error != GuarantorError.None:
        return GuaranteeCredentialResult[VerifiedGuaranteeCredentials](
          status: GuaranteeCredentialError.AssignmentFailure,
          assignmentReason: assigned.error) # No stale/future slot or nonexistent selected-roster index.
      if uint64(assigned.value.core) != core:
        return GuaranteeCredentialResult[VerifiedGuaranteeCredentials](
            status: GuaranteeCredentialError.WrongAssignment) # Signatures cannot authorize a different core.
      keys[j] = assigned.value.validator.ed25519
    var canonical = newSeq[byte](info.consumed)
    let copied = encodeOwnedReport(value.report, canonical)
    if copied.error != OwnershipError.None:
      return GuaranteeCredentialResult[VerifiedGuaranteeCredentials](
          status: GuaranteeCredentialError.BackendFailure) # Complete owned report copy is required.
    let message = guaranteeMessage(canonical)
    if message.error != CryptoError.None:
      return GuaranteeCredentialResult[VerifiedGuaranteeCredentials](
          status: GuaranteeCredentialError.BackendFailure) # No zero transcript on provider refusal.
    let bytes = array[45, byte](message.value)
    for j in 0..<value.credentialCount:
      let signature = importSignature(array[64, byte](value.credentials[j].signature)).value
      let key = EdPublicKey(array[32, byte](keys[j]))
      if not verify(key, signature, bytes):
        return GuaranteeCredentialResult[VerifiedGuaranteeCredentials](
            status: GuaranteeCredentialError.InvalidSignature) # Preserve actual backend acceptance policy.
      if not includeReporter(data.reporters, keys[j], config.reporters):
        return GuaranteeCredentialResult[VerifiedGuaranteeCredentials](
            status: GuaranteeCredentialError.LimitExceeded) # A later refusal discards all earlier keys/records.
    data.guarantees[i] = value # Copy metadata and retain the exact immutable report owner only after all its credentials verify.
  GuaranteeCredentialResult[VerifiedGuaranteeCredentials](status: GuaranteeCredentialError.None,
    completed: VerifiedGuaranteeCredentials(data: data))
