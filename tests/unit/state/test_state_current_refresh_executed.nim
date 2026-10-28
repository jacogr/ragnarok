# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual custom HALT metadata refresh retains complete code/request namespaces and source-bound account predicate evidence.
# @@Verification={"arc":"state_current_refresh_executed_arc_release"}
import std/assertions
import std/envvars
import std/syncio
import ../../support/state_current_namespace_transition_context
import ../../support/state_current_namespace_execution_context
import ../../support/state_current_namespace_context
import ../../support/state_current_namespace_refresh_context
import ../../support/state_accumulation_execution_context
import ../../support/state_supplied_services_context
import ../../support/testing_arc_evidence
import ../../../src/state/current_logical_refresh as state_current_logical_refresh
import ../../../src/state/current_refresh_plan as state_current_refresh_plan
import ../../../src/state/current_request_keys as state_current_request_keys
import ../../../src/state/current_identities as state_current_identities
import ../../../src/state/current_logical as state_current_logical
import ../../../src/state/current_state as state_current_state
import ../../../src/state/current_globals as state_current_globals
import ../../../src/state/current_profile as state_current_profile
import ../../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../../src/state/supplied_logical_inventory as state_supplied_logical_inventory
import ../../../src/state/supplied_services as state_supplied_services
import ../../../src/state/inventory as state_inventory
import ../../../src/state/manifest as state_manifest
import ../../../src/state/store as state_store
import ../../../src/state/account_audit_plan as state_account_audit_plan
import ../../../src/state/account_audit as state_account_audit
import ../../../src/state/account_invariants as state_account_invariants
import ../../../src/state/footprint_audit as state_footprint_audit
import ../../../src/state/preimage_content as state_preimage_content
import ../../../src/state/preimage_linkage as state_preimage_linkage
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/codec/state_accounts as codec_state_accounts
import ../../../src/codec/state_requests as codec_state_requests
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Actual signed/current execution and request-key capture precede hash-free plans and independently counted audit execution.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Only full matching and explicit content execution hash; cached planning/projection cannot.
proc auditPolicy(codeBytes: int): AccountAuditLimits =
  ## Exact independent work for two accounts, four storage rows, six requests and six preimages including both whole code blobs.
  assert codeBytes >= 3 and codeBytes <= 65536 # Tiny actual code extent proves byte total and native limit conversion.
  AccountAuditLimits(planning: ElementLimit(10), footprints: FootprintAuditLimits(
      services: ElementLimit(2), checks: ElementLimit(12)), content: PreimageContentLimits(
      services: ElementLimit(2), preimages: ElementLimit(6), perValue: ByteLimit(uint64(codeBytes)),
      totalBytes: ByteLimit(4+2*uint64(codeBytes))), linkage: PreimageLinkageLimits(
      services: ElementLimit(2), preimages: ElementLimit(6), comparisons: ElementLimit(18)))
proc cycle(plan: CurrentLogicalRefreshPlan, codeBytes: int) =
  ## Retire real refreshed payloads, both compact/raw-key captures, detached code copies and joined account predicate evidence.
  let logical = executeCurrentLogicalRefresh(plan).value
  let inventory = logical.currentLogicalInventory.value.suppliedInventory.value
  assert copySuppliedServices(logical.currentLogicalInventory.value,
      suppliedServicesTestLimits).value.len == 2
  assert executeAccountAudit(planAccountAudit(inventory, auditPolicy(codeBytes)).value).error ==
      AccountAuditError.None
proc main() {.raises.} =
  ## Both original programs and all complete namespaces/code requests enter actual parent roots/signatures before guest execution.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i])
  let code = namespaceHaltCode()
  var options = executionFixtureConfig()
  options.firstProgram = code
  options.secondProgram = code
  options.secondBalance = 1000000
  options.signed.serviceNamespaces = namespaceSeeds()
  let fixture = namespaceTransitionFixture(decodeOwnedReport(bytes, 2).value, options)
  assert uint32(fixture.services[0].metadata.lastAccumulation) == 0 and uint32(fixture.services[
      1].metadata.lastAccumulation) == 0
  let stages = namespaceRefreshStages(fixture)
  assert stages.identities.identityInfo.value.entries == 34 and
      stages.keys.requestKeysInfo.value.requests == 6
  fail(1)
  let reconstruct = planCurrentRefresh(stages.keys, namespaceRefreshLimits).value
  assert reconstruct.refreshPlanInfo.value.facts == 18 and
      reconstruct.refreshPlanInfo.value.wireBytes == 240
  assert planCurrentLogicalRefresh(reconstruct, namespaceLogicalLimits()).value.logicalRefreshPlanInfo.value.checks == 40
  assert calls() == 0
  fail(0)
  let logical = executeCurrentLogicalRefresh(stages.complete).value
  let inventory = logical.currentLogicalInventory.value.suppliedInventory.value
  for i in 0..<2:
    let row = inventory.inventoryServiceAt(InventoryServiceIndex(uint64(i))).value
    assert uint32(row.metadata.lastAccumulation) == 2 and uint32(row.metadata.storageItems) == 8
    assert uint64(row.metadata.storageBytes) == (if i == 0: 317'u64 else: 314'u64)+uint64(code.len)
    assert row.preimages == 3 and row.requests == 3 and row.storage == 2
  assert sameStateSnapshot(logical.currentLogicalSource.value.currentStateGlobals.value.qualifiedCurrentProfile.value.derivedUpdate.value.currentUpdatePriorState,
      fixture.source.state.snapshot.value)
  assert sameStateSnapshot(inventory.inventorySource.value.manifestSource.value,
      fixture.update.currentUpdateState)
  fail(1)
  let copied = copySuppliedServices(logical.currentLogicalInventory.value,
      suppliedServicesTestLimits).value
  assert copied[0].preimages[2].value == code and copied[1].preimages[2].value == code
  assert uint32(copied[0].requests[2].length) == uint32(code.len)
  let planned = planAccountAudit(inventory, auditPolicy(code.len)).value
  assert planned.accountPlanInfo.value.planningChecks == 10 and
      planned.accountPlanInfo.value.footprintChecks == 12
  assert planned.accountPlanInfo.value.comparisonCeiling == 18 and calls() == 0
  fail(0)
  let audited = executeAccountAudit(planned).value
  assert calls() == 6 and sameStateInventory(audited.accountInvariantInventory.value, inventory)
  for i in 0..<25: cycle(stages.complete, code.len)
  let before = getOccupiedMem()
  for i in 0..<1000: cycle(stages.complete, code.len)
  let finalBytes = getOccupiedMem()
  assert before == finalBytes
  recordArcRelease("state_current_refresh_executed", 1000, before, finalBytes)
  echo "state-current-refresh-executed: ok"
try:
  main()
except:
  quit(2) # Actual guest metadata, complete namespaces and source-bound predicates must agree on the original genuine successor.
