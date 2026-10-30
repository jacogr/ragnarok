# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Execute a frozen complete-source account audit plan without accepting substituted sources or policies.
## Successful targeted predicates remain distinct from global validity, application installation or trusted-root authority.
import ./audit/plan as account_audit_plan
import ./invariants as account_invariants
import ../footprint_audit
import ../preimage/[content as preimage_content, linkage as preimage_linkage]

type
  AccountAuditError* {.pure.} = enum ## Semantic/backend failures preserve their actual phase; invalid/default plans grant no prefix.
    Uninitialized, None, InvalidPlan, FootprintFailure, LinkageFailure, ContentFailure, JoinFailure
  AccountAuditResult* = object ## Only all completed same-source predicates expose a joined account certificate.
    case status: AccountAuditError
    of None:
      completed: CheckedAccountInvariants
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

func error*(outcome: AccountAuditResult): AccountAuditError =
  ## Inspect the immutable selected execution phase.
  outcome.status

func value*(outcome: AccountAuditResult): CheckedAccountInvariants {.inline,
    requires: outcome.status == AccountAuditError.None.} =
  ## Failed/default execution grants neither a complete result nor an earlier successful predicate prefix.
  outcome.completed

func footprintFailure*(outcome: AccountAuditResult): FootprintAuditResult[
    CheckedAccountFootprints] {.inline,

requires: outcome.status == AccountAuditError.FootprintFailure.} =
  ## Preserve only the genuine failed footprint predicate/owner join.
  outcome.footprintReason

func linkageFailure*(outcome: AccountAuditResult): PreimageLinkageResult[
    CheckedPreimageLinkage] {.inline,

requires: outcome.status == AccountAuditError.LinkageFailure.} =
  ## Preserve only the genuine failed linkage predicate/owner join.
  outcome.linkageReason

func contentFailure*(outcome: AccountAuditResult): PreimageContentResult[
    CheckedPreimageContent] {.inline,

requires: outcome.status == AccountAuditError.ContentFailure.} =
  ## Preserve only the genuine failed content predicate/owner join.
  outcome.contentReason

func joinFailure*(outcome: AccountAuditResult): AccountInvariantResult[
    CheckedAccountInvariants] {.inline,

requires: outcome.status == AccountAuditError.JoinFailure.} =
  ## Preserve only the genuine failed join predicate/owner join.
  outcome.joinReason

proc executeAccountAudit*(plan: StateAccountAuditPlan): AccountAuditResult =
  ## Use only frozen source/policies; resource admission has completed before any detached payload or content hash.
  let source = plan.accountPlanInventory
  if source.error != AccountAuditPlanError.None:
    return AccountAuditResult(status: AccountAuditError.InvalidPlan) # Defaults cannot masquerade as empty executable audits.
  let limits = plan.accountPlanLimits.value
  let footprints = auditAccountFootprints(source.value, limits.footprints)
  if footprints.error != FootprintAuditError.None:
    return AccountAuditResult(status: AccountAuditError.FootprintFailure,
        footprintReason: footprints) # Reject dependent metadata before any content hash.
  let linkage = auditPreimageLinkage(source.value, limits.linkage)
  if linkage.error != PreimageLinkageError.None:
    return AccountAuditResult(status: AccountAuditError.LinkageFailure,
        linkageReason: linkage) # Reject missing request associations without hashing payloads.
  let content = auditPreimageContent(source.value, limits.content)
  if content.error != PreimageContentError.None:
    return AccountAuditResult(status: AccountAuditError.ContentFailure,
        contentReason: content) # Preserve malformed hash versus backend refusal precisely.
  let joined = joinAccountInvariants(footprints.value, content.value, linkage.value)
  if joined.error != AccountInvariantError.None:
    return AccountAuditResult(status: AccountAuditError.JoinFailure,
        joinReason: joined) # A future source-wiring mistake must not bypass exact-owner joining.
  AccountAuditResult(status: AccountAuditError.None, completed: joined.value)
