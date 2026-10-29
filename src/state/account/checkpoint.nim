# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Restore unchanged checkpoint bytes under an explicit expected root, then certify targeted account invariants.
## No raw restored source escapes failed serialization, capture or invariant checks; installation remains application-owned.
import ../../codec/bounded
import ../../codec/state/[trie as state_trie, composition as state_composition]
import ../[validated_checkpoint, inventory]
import ./invariants as account_invariants
import ../footprint_audit
import ../preimage/[content as preimage_content, linkage as preimage_linkage]

type
  AccountCheckpointLimits* = object ## All restoration/capture/predicate policies remain explicit and independently bounded.
    serialization*: StateCheckpointLimits
    inventory*: StateInventoryLimits
    footprints*: FootprintAuditLimits
    content*: PreimageContentLimits
    linkage*: PreimageLinkageLimits
  AccountCheckpointError* {.pure.} = enum ## Precise failed phases retain their actual nested failure without a prefix owner.
    Uninitialized, None, SerializationFailure, InventoryFailure, FootprintFailure, LinkageFailure,
      ContentFailure, JoinFailure
  AccountCheckpointResult* = object ## Private phase payloads preserve complete-map and expected-root boundaries.
    case status: AccountCheckpointError
    of None:
      completed: CheckedAccountInvariants
    of SerializationFailure:
      serializationReason: ValidatedCheckpointResult
    of InventoryFailure:
      inventoryReason: StateInventoryResult[StateInventory]
    of FootprintFailure:
      footprintReason: FootprintAuditResult[CheckedAccountFootprints]
    of LinkageFailure:
      linkageReason: PreimageLinkageResult[CheckedPreimageLinkage]
    of ContentFailure:
      contentReason: PreimageContentResult[CheckedPreimageContent]
    of JoinFailure:
      joinReason: AccountInvariantResult[CheckedAccountInvariants]
    else:
      discard
func error*(outcome: AccountCheckpointResult): AccountCheckpointError =
  ## Inspect the immutable failed phase or completed targeted certificate.
  outcome.status
func value*(outcome: AccountCheckpointResult): CheckedAccountInvariants {.inline,
    requires: outcome.status == AccountCheckpointError.None.} =
  ## Only all completed phases grant a retained restored source with targeted account evidence.
  outcome.completed
func serializationFailure*(outcome: AccountCheckpointResult): ValidatedCheckpointResult {.inline,
    requires: outcome.status == AccountCheckpointError.SerializationFailure.} =
  ## Expose only the genuinely failed serialization phase, never an unrelated default reason.
  outcome.serializationReason
func inventoryFailure*(outcome: AccountCheckpointResult): StateInventoryResult[
    StateInventory] {.inline,

requires: outcome.status == AccountCheckpointError.InventoryFailure.} =
  ## Expose only the genuinely failed inventory phase, never an unrelated default reason.
  outcome.inventoryReason
func footprintFailure*(outcome: AccountCheckpointResult): FootprintAuditResult[
    CheckedAccountFootprints] {.inline,

requires: outcome.status == AccountCheckpointError.FootprintFailure.} =
  ## Expose only the genuinely failed footprint phase, never an unrelated default reason.
  outcome.footprintReason
func linkageFailure*(outcome: AccountCheckpointResult): PreimageLinkageResult[
    CheckedPreimageLinkage] {.inline,

requires: outcome.status == AccountCheckpointError.LinkageFailure.} =
  ## Expose only the genuinely failed linkage phase, never an unrelated default reason.
  outcome.linkageReason
func contentFailure*(outcome: AccountCheckpointResult): PreimageContentResult[
    CheckedPreimageContent] {.inline,

requires: outcome.status == AccountCheckpointError.ContentFailure.} =
  ## Expose only the genuinely failed content phase, never an unrelated default reason.
  outcome.contentReason
func joinFailure*(outcome: AccountCheckpointResult): AccountInvariantResult[
    CheckedAccountInvariants] {.inline,

requires: outcome.status == AccountCheckpointError.JoinFailure.} =
  ## Expose only the genuinely failed join phase, never an unrelated default reason.
  outcome.joinReason
proc decodeAccountCheckpoint*(input: openArray[byte], expected: StateRoot,
    services: openArray[StateService], profile: StateProfile,
    limits: AccountCheckpointLimits): AccountCheckpointResult =
  ## Borrow bytes/declarations synchronously; expected root is mandatory and never inferred from embedded transport data.
  let serialized = decodeValidatedCheckpoint(input, expected, services, profile,
      limits.serialization)
  if serialized.error != ValidatedCheckpointError.None:
    return AccountCheckpointResult(status: AccountCheckpointError.SerializationFailure,
      serializationReason: serialized) # Existing exact expected-root, global and manifest errors survive unchanged.
  let captured = captureStateInventory(serialized.value, services, limits.inventory)
  if captured.error != StateInventoryError.None:
    return AccountCheckpointResult(status: AccountCheckpointError.InventoryFailure,
      inventoryReason: captured) # Logical capture must complete before any account predicate begins.
  let footprints = auditAccountFootprints(captured.value, limits.footprints)
  if footprints.error != FootprintAuditError.None:
    return AccountCheckpointResult(status: AccountCheckpointError.FootprintFailure,
      footprintReason: footprints) # Dependent metadata mismatch is distinct from malformed transport or hash content.
  let linkage = auditPreimageLinkage(captured.value, limits.linkage)
  if linkage.error != PreimageLinkageError.None:
    return AccountCheckpointResult(status: AccountCheckpointError.LinkageFailure,
      linkageReason: linkage) # Check bounded request membership before copying or hashing preimage payloads.
  let content = auditPreimageContent(captured.value, limits.content)
  if content.error != PreimageContentError.None:
    return AccountCheckpointResult(status: AccountCheckpointError.ContentFailure,
      contentReason: content) # Preserve late backend refusal and invalid hash separately inside this phase.
  let joined = joinAccountInvariants(footprints.value, content.value, linkage.value)
  if joined.error != AccountInvariantError.None:
    return AccountCheckpointResult(status: AccountCheckpointError.JoinFailure,
      joinReason: joined) # A future adapter error must never bypass exact logical owner equality.
  AccountCheckpointResult(status: AccountCheckpointError.None, completed: joined.value)
