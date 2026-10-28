# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Restore unchanged checkpoint transport under an explicit root, then preflight whole-account policies before semantic execution.
## All phases are synchronous and source-bound; this adapter never installs state or discovers root/profile authority.
import ../codec/state_trie as codec_state_trie
import ../codec/state_composition as codec_state_composition
import ./validated_checkpoint as state_validated_checkpoint
import ./inventory as state_inventory
import ./account_audit_plan as state_account_audit_plan
import ./account_audit as state_account_audit
import ./account_invariants as state_account_invariants

type
  PlannedAccountCheckpointLimits* = object ## Restoration, exact capture and all planning/execution policies stay explicit.
    serialization*: StateCheckpointLimits
    inventory*: StateInventoryLimits
    audit*: AccountAuditLimits
  PlannedAccountCheckpointError* {.pure.} = enum ## Failure preserves the actual phase and never returns a restored prefix owner.
    Uninitialized, None, SerializationFailure, InventoryFailure, PlanningFailure, AuditFailure
  PlannedAccountCheckpointResult* = object ## Only expected-root restoration plus complete admitted successful predicates expose evidence.
    case status: PlannedAccountCheckpointError
    of None:
      completed: CheckedAccountInvariants
    of SerializationFailure:
      serializationReason: ValidatedCheckpointResult
    of InventoryFailure:
      inventoryReason: StateInventoryResult[StateInventory]
    of PlanningFailure:
      planningReason: AccountAuditPlanResult[StateAccountAuditPlan]
    of AuditFailure:
      auditReason: AccountAuditResult
    else:
      discard
func error*(outcome: PlannedAccountCheckpointResult): PlannedAccountCheckpointError =
  ## Inspect the immutable selected phase.
  outcome.status
func value*(outcome: PlannedAccountCheckpointResult): CheckedAccountInvariants {.inline,
    requires: outcome.status == PlannedAccountCheckpointError.None.} =
  ## Only all successful phases grant a retained restored complete-source account certificate.
  outcome.completed
func serializationFailure*(outcome: PlannedAccountCheckpointResult): ValidatedCheckpointResult {.inline,
    requires: outcome.status == PlannedAccountCheckpointError.SerializationFailure.} =
  ## Expose only the actual failed serialization phase, including its existing guarded nested reasons.
  outcome.serializationReason
func inventoryFailure*(outcome: PlannedAccountCheckpointResult): StateInventoryResult[
    StateInventory] {.inline,

requires: outcome.status == PlannedAccountCheckpointError.InventoryFailure.} =
  ## Expose only the actual failed inventory phase, including its existing guarded nested reasons.
  outcome.inventoryReason
func planningFailure*(outcome: PlannedAccountCheckpointResult): AccountAuditPlanResult[
    StateAccountAuditPlan] {.inline,

requires: outcome.status == PlannedAccountCheckpointError.PlanningFailure.} =
  ## Expose only the actual failed planning phase, including its existing guarded nested reasons.
  outcome.planningReason
func auditFailure*(outcome: PlannedAccountCheckpointResult): AccountAuditResult {.inline,
    requires: outcome.status == PlannedAccountCheckpointError.AuditFailure.} =
  ## Expose only the actual failed audit phase, including its existing guarded nested reasons.
  outcome.auditReason
proc decodePlannedAccountCheckpoint*(input: openArray[byte], expected: StateRoot,
    services: openArray[StateService], profile: StateProfile,
    limits: PlannedAccountCheckpointLimits): PlannedAccountCheckpointResult =
  ## Borrow bytes/declarations only for this call; embedded transport identity cannot replace the mandatory caller root.
  let serialized = decodeValidatedCheckpoint(input, expected, services, profile,
      limits.serialization)
  if serialized.error != ValidatedCheckpointError.None:
    return PlannedAccountCheckpointResult(status: PlannedAccountCheckpointError.SerializationFailure,
      serializationReason: serialized) # Preserve unchanged restoration/global/exact-map failures.
  let captured = captureStateInventory(serialized.value, services, limits.inventory)
  if captured.error != StateInventoryError.None:
    return PlannedAccountCheckpointResult(status: PlannedAccountCheckpointError.InventoryFailure,
      inventoryReason: captured) # No raw restored map escapes failed logical capture.
  let planned = planAccountAudit(captured.value, limits.audit)
  if planned.error != AccountAuditPlanError.None:
    return PlannedAccountCheckpointResult(status: PlannedAccountCheckpointError.PlanningFailure,
      planningReason: planned) # All account predicate policies are admitted before payload copying/content hashes.
  let audited = executeAccountAudit(planned.value)
  if audited.error != AccountAuditError.None:
    return PlannedAccountCheckpointResult(status: PlannedAccountCheckpointError.AuditFailure,
      auditReason: audited) # Resource admission is not mistaken for semantic validity.
  PlannedAccountCheckpointResult(status: PlannedAccountCheckpointError.None,
      completed: audited.value)
