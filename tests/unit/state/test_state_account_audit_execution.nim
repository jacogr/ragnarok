# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Frozen whole-account execution preserves semantic/backend distinctions, zero-hash early failures and exact owner lifetime.
# @@Verification={"arc": "state_account_audit_execution_arc_release"}
import std/assertions
import std/envvars
import std/syncio
import ../../support/state_inventory_context
import ../../support/state_account_audit_plan_context
import ../../support/testing_arc_evidence
import ../../../src/state/account_audit as state_account_audit
import ../../../src/state/account_audit_plan as state_account_audit_plan
import ../../../src/state/account_invariants as state_account_invariants
import ../../../src/state/inventory as state_inventory
import ../../../src/state/footprint_audit as state_footprint_audit
import ../../../src/state/preimage_content as state_preimage_content
import ../../../src/state/preimage_linkage as state_preimage_linkage
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_accounts as codec_state_accounts
import ../../../src/codec/state_requests as codec_state_requests
include ../../native/nimony_composition_fixture
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Reset counters and optionally reject all hash primitives.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Observe exactly when semantic execution first reaches a content hash.
proc cycle(plan: StateAccountAuditPlan) =
  ## Retire successful joined certificates and failed default-plan results each cycle.
  assert executeAccountAudit(plan).error == AccountAuditError.None
  assert executeAccountAudit(default(StateAccountAuditPlan)).error == AccountAuditError.InvalidPlan
proc main() {.raises.} =
  ## Capture complete structurally valid semantic faults before observing execution boundaries.
  let fixture = compositionFixture(getEnv("RAGNAROK_COMPOSITION_FIXTURE"))
  var services = inventoryServices()
  let source = captureStateInventory(inventoryManifest(fixture, services), services,
      inventoryCaptureLimits).value
  var limits = accountAuditTestLimits
  let plan = planAccountAudit(source, limits).value
  limits.content.totalBytes = ByteLimit(0)
  services[0].metadata.storageItems = AccountStorageItems(4)
  let wrongFootprint = planAccountAudit(captureStateInventory(inventoryManifest(fixture, services),
      services, inventoryCaptureLimits).value, accountAuditTestLimits).value
  services = inventoryServices()
  services[0].requests[0].length = RequestLength(2)
  services[0].metadata.storageBytes = AccountStorageBytes(120)
  let wrongLinkage = planAccountAudit(captureStateInventory(inventoryManifest(fixture, services),
      services, inventoryCaptureLimits).value, accountAuditTestLimits).value
  services = inventoryServices()
  services[0].preimages[0].value[0] = 98
  let wrongContent = planAccountAudit(captureStateInventory(inventoryManifest(fixture, services),
      services, inventoryCaptureLimits).value, accountAuditTestLimits).value
  services = @[]
  let empty = planAccountAudit(captureStateInventory(inventoryManifest(fixture, services), services,
      inventoryCaptureLimits).value, AccountAuditLimits()).value
  fail(0)
  let result = executeAccountAudit(plan)
  assert result.error == AccountAuditError.None and calls() == 1
  assert sameStateInventory(result.value.accountInvariantInventory.value, source)
  assert result.value.accountInvariantInfo.value.content.bytes == 3
  fail(1)
  let badFootprint = executeAccountAudit(wrongFootprint)
  assert badFootprint.error == AccountAuditError.FootprintFailure
  assert badFootprint.footprintFailure.error == FootprintAuditError.ItemsMismatch
  let badLinkage = executeAccountAudit(wrongLinkage)
  assert badLinkage.error == AccountAuditError.LinkageFailure
  assert badLinkage.linkageFailure.error == PreimageLinkageError.MissingRequest
  assert executeAccountAudit(empty).error == AccountAuditError.None and calls() == 0
  let backend = executeAccountAudit(plan)
  assert backend.error == AccountAuditError.ContentFailure and calls() == 1
  assert backend.contentFailure.error == PreimageContentError.BackendFailure
  assert uint32(backend.contentFailure.failedService) == 7
  fail(0)
  let badContent = executeAccountAudit(wrongContent)
  assert badContent.error == AccountAuditError.ContentFailure and calls() == 1
  assert badContent.contentFailure.error == PreimageContentError.HashMismatch
  assert executeAccountAudit(default(StateAccountAuditPlan)).error == AccountAuditError.InvalidPlan
  for i in 0..<25: cycle(plan) # Warm all retained same-source execution evidence.
  let before = getOccupiedMem()
  for i in 0..<1000: cycle(plan) # Retire content copies and joined/source references without accumulation.
  let finalBytes = getOccupiedMem()
  assert before == finalBytes
  recordArcRelease("state_account_audit_execution", 1000, before, finalBytes)
  echo "state-account-audit-execution: ok"
try:
  main()
except:
  quit(2) # Setup failure cannot satisfy semantic/backend or ownership evidence.
