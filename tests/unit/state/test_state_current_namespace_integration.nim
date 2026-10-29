# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Nonempty supplied namespaces retain genuine current provenance, detached copy isolation and independently bounded account audits.
# @@Verification={"arc":"state_current_namespace_integration_arc_release"}
import std/[assertions, envvars, syncio]
import ../../support/[current_namespace_context, service_namespace_seed,
    accumulation_current_chain_context, current_checkpoint_context, parent_profile_context,
    parent_globals_context, supplied_logical_context, supplied_services_context,
    state_inventory_context, arc_evidence]
import ../../../src/chain/[provider, genesis]
import ../../../src/state/parent/[profile as parent_profile, globals as parent_globals,
    logical as parent_logical]
import ../../../src/state/current/[profile as current_profile, globals as current_globals,
    state as current_state, logical as current_logical]
import ../../../src/state/accumulation/current/update as accumulation_current_update
import ../../../src/state/[global_snapshot, store, inventory, manifest]
import ../../../src/state/supplied/[logical_inventory as supplied_logical_inventory,
    services as supplied_services]
import ../../../src/state/account/audit/plan as account_audit_plan
import ../../../src/state/account/[audit as account_audit, invariants as account_invariants]
import ../../../src/state/footprint_audit
import ../../../src/state/preimage/[content as preimage_content, linkage as preimage_linkage]
import ../../../src/codec/[bounded, report_owned]
import ../../../src/codec/state/[composition as state_composition, accounts as state_accounts]
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Exact map matching happens before hash-free audit planning and observational projections.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Only admitted preimage content validation invokes content hashing.
proc qualified(update: PreparedCurrentChainUpdate, seeds: openArray[
    ServiceNamespaceSeed]): CurrentLogicalState =
  ## Always derive profile/globals and supplied declarations from the actual captured current successor.
  let profile = captureCurrentProfile(update, CurrentProfileLimits(validators: ElementLimit(1024),
      bytes: ByteLimit(65536))).value
  let globals = qualifyCurrentGlobals(profile, parentGlobalsTestLimits).value
  let services = currentNamespaceServices(update.currentUpdateState, seeds)
  let state = qualifyCurrentState(globals, services, inventoryCaptureLimits).value
  captureCurrentLogicalState(state, services, suppliedLogicalTestLimits).value
proc policy(): AccountAuditLimits =
  ## Independent exact work:2 rows*2 passes+4 preimages,2 accounts+4 storage+4 requests,4 bytes and8 comparisons.
  AccountAuditLimits(planning: ElementLimit(8), footprints: FootprintAuditLimits(
      services: ElementLimit(2), checks: ElementLimit(10)),
    content: PreimageContentLimits(services: ElementLimit(2), preimages: ElementLimit(4),
        perValue: ByteLimit(3), totalBytes: ByteLimit(4)),
    linkage: PreimageLinkageLimits(services: ElementLimit(2), preimages: ElementLimit(4),
        comparisons: ElementLimit(8)))
proc verify(owner: CurrentLogicalState) =
  ## Plan/query/detached projection cannot replace the exact original full-source/current provenance.
  let logical = owner.currentLogicalInventory.value
  let inventory = logical.suppliedInventory.value
  let source = inventory.inventorySource.value.manifestSource.value
  fail(1)
  let plan = planAccountAudit(inventory, policy()).value
  let info = plan.accountPlanInfo.value
  assert info.planningChecks == 8 and info.footprintChecks == 10 and info.preimages == 4 and
      info.contentBytes == 4 and info.comparisonCeiling == 8
  var copied = copySuppliedServices(logical, suppliedServicesTestLimits).value
  assert copied.len == 2 and copied[0].storage[0].key.len == 0 and copied[0].storage[0].value.len == 0
  assert copied[0].preimages[0].value.len == 0 and copied[1].storage[1].value.len == 0
  copied[0].storage[1].key[0] = 255
  copied[0].preimages[1].value[0] = 255
  let original = copySuppliedServices(logical, suppliedServicesTestLimits).value
  assert original[0].storage[1].key[0] == 1 and original[0].preimages[1].value[0] == 97
  assert sameStateSnapshot(source, owner.currentLogicalSource.value.currentStateInventory.value.inventorySource.value.manifestSource.value)
  var short = policy()
  short.planning = ElementLimit(7)
  assert planAccountAudit(inventory, short).refusedPhase == AccountAuditRefusal.Planning
  short = policy()
  short.footprints.checks = ElementLimit(9)
  assert planAccountAudit(inventory, short).refusedPhase == AccountAuditRefusal.Footprints
  short = policy()
  short.content.totalBytes = ByteLimit(3)
  assert planAccountAudit(inventory, short).refusedPhase == AccountAuditRefusal.Content
  short = policy()
  short.linkage.comparisons = ElementLimit(7)
  assert planAccountAudit(inventory, short).refusedPhase == AccountAuditRefusal.Linkage
  assert calls() == 0
  fail(0)
  let audit = executeAccountAudit(plan)
  assert audit.error == AccountAuditError.None and calls() == 4
  assert sameStateInventory(audit.value.accountInvariantInventory.value, inventory)
proc cycle(source: CurrentStateSerialization, services: openArray[StateService]) =
  ## Retire complete logical/raw-key capture and detached empty/nonempty payload arrays each cycle.
  let logical = captureCurrentLogicalState(source, services, suppliedLogicalTestLimits).value
  assert copySuppliedServices(logical.currentLogicalInventory.value,
      suppliedServicesTestLimits).value.len == 2
proc main() {.raises.} =
  ## All ordinary/assured/disputed/ticketed/epoch fixtures run actual current candidate preparation.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i])
  let base = decodeOwnedReport(bytes, 2).value
  let seeds = namespaceSeeds()
  let normal = qualified(currentCheckpointPrepared(currentChainFixture(base, completeState = true,
      serviceNamespaces = seeds)), seeds)
  verify(normal)
  verify(qualified(currentCheckpointPrepared(currentChainFixture(base, available = true,
      completeState = true, serviceNamespaces = seeds)), seeds))
  verify(qualified(currentCheckpointPrepared(currentChainFixture(base, available = true,
      disputed = true, completeState = true, serviceNamespaces = seeds)), seeds))
  verify(qualified(currentCheckpointPrepared(currentChainFixture(base, available = true,
      ticket = true, completeState = true, serviceNamespaces = seeds)), seeds))
  verify(qualified(currentCheckpointPrepared(currentChainFixture(base, available = true,
      rotated = true, completeState = true, serviceNamespaces = seeds)), seeds))
  let source = normal.currentLogicalSource.value
  let services = currentNamespaceServices(source.currentStateInventory.value.inventorySource.value.manifestSource.value, seeds)
  for i in 0..<25: cycle(source, services)
  let before = getOccupiedMem()
  for i in 0..<1000: cycle(source, services)
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("state_current_namespace_integration", 1000, before, after)
  echo "state-current-namespace-integration: ok"
try:
  main()
except:
  quit(2) # Invalid actual successor, full matching or bounded audit cannot qualify supplied integration evidence.
