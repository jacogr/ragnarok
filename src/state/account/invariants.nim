# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Join independent dependent-field/content/linkage certificates only for the exact same logical inventory.
## This targeted accounts certificate deliberately grants no trusted root or full STF validity.
import ../[inventory, footprint_audit]
import ../preimage/[content as preimage_content, linkage as preimage_linkage]

type
  AccountInvariantInfo* = object ## Fixed completed observations preserve each independently bounded predicate.
    footprints*: FootprintAuditInfo
    content*: PreimageContentInfo
    linkage*: PreimageLinkageInfo
  CheckedAccountInvariants* = object ## Private input identity prevents equal-root or partial-evidence joins.
    source: StateInventory
    info: AccountInvariantInfo
  AccountInvariantError* {.pure.} = enum ## Invalid/default inputs and cross-owner substitution are distinct failures.
    Uninitialized, None, InvalidFootprints, InvalidContent, InvalidLinkage, SourceMismatch
  AccountInvariantResult*[T] = object ## No success prefix can be extracted from a failed join.
    case status: AccountInvariantError
    of None:
      completed: T
    else:
      discard
func error*[T](outcome: AccountInvariantResult[T]): AccountInvariantError =
  ## Read the immutable alternative without permitting caller retagging.
  outcome.status
func value*[T](outcome: AccountInvariantResult[T]): T {.inline,
    requires: outcome.status == AccountInvariantError.None.} =
  ## Only all three same-owner predicates grant the targeted certificate.
  outcome.completed
proc joinAccountInvariants*(footprints: CheckedAccountFootprints,
    content: CheckedPreimageContent, linkage: CheckedPreimageLinkage): AccountInvariantResult[
        CheckedAccountInvariants] =
  ## Constant bounded work joins already completed immutable certificates without copies, allocation or hashing.
  let footprintSource = footprints.footprintInventory
  if footprintSource.error != FootprintAuditError.None:
    return AccountInvariantResult[CheckedAccountInvariants](
        status: AccountInvariantError.InvalidFootprints) # No default dependent-field evidence.
  let contentSource = content.contentInventory
  if contentSource.error != PreimageContentError.None:
    return AccountInvariantResult[CheckedAccountInvariants](
        status: AccountInvariantError.InvalidContent) # No default content evidence.
  let linkageSource = linkage.linkageInventory
  if linkageSource.error != PreimageLinkageError.None:
    return AccountInvariantResult[CheckedAccountInvariants](
        status: AccountInvariantError.InvalidLinkage) # No default membership evidence.
  if not sameStateInventory(footprintSource.value, contentSource.value) or
      not sameStateInventory(footprintSource.value, linkageSource.value):
    return AccountInvariantResult[CheckedAccountInvariants](
        status: AccountInvariantError.SourceMismatch) # Equal serialized roots or snapshots cannot substitute another logical capture.
  AccountInvariantResult[CheckedAccountInvariants](status: AccountInvariantError.None,
    completed: CheckedAccountInvariants(source: footprintSource.value,
      info: AccountInvariantInfo(footprints: footprints.footprintInfo.value,
        content: content.contentInfo.value, linkage: linkage.linkageInfo.value)))
proc accountInvariantInfo*(checked: CheckedAccountInvariants): AccountInvariantResult[
    AccountInvariantInfo] =
  ## Copy completed observations only from a genuine joined owner.
  if not sameStateInventory(checked.source, checked.source):
    return AccountInvariantResult[AccountInvariantInfo](
        status: AccountInvariantError.Uninitialized) # Default has no retained provenance.
  AccountInvariantResult[AccountInvariantInfo](status: AccountInvariantError.None,
      completed: checked.info)
proc accountInvariantInventory*(checked: CheckedAccountInvariants): AccountInvariantResult[
    StateInventory] =
  ## Retain the exact original complete logical inventory without adding root authority.
  if not sameStateInventory(checked.source, checked.source):
    return AccountInvariantResult[StateInventory](
        status: AccountInvariantError.Uninitialized) # Default is not an empty valid inventory.
  AccountInvariantResult[StateInventory](status: AccountInvariantError.None,
      completed: checked.source)
