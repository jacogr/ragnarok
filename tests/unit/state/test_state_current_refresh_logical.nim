# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Frozen complete current continuation admits every later capture/map quota, preserves typed backend refusal and produces existing full current logical provenance.
# @@Verification={"arc":"state_current_refresh_logical_arc_release"}
import std/[assertions, envvars, syncio]
import ../../support/[current_refresh_context, current_logical_refresh_context, arc_evidence]
import ../../../src/state/current/logical/refresh as current_logical_refresh
import ../../../src/state/current/refresh as current_refresh
import ../../../src/state/current/refresh/plan as current_refresh_plan
import ../../../src/state/current/[request_keys as current_request_keys,
    identities as current_identities, profile as current_profile, globals as current_globals,
    state as current_state, logical as current_logical]
import ../../../src/state/supplied/logical_inventory as supplied_logical_inventory
import ../../../src/state/[inventory, manifest, store]
import ../../../src/state/accumulation/current/update as accumulation_current_update
import ../../../src/state/global_snapshot
import ../../../src/codec/[bounded, report_owned]
import ../../../src/codec/state/[trie as state_trie, composition as state_composition]
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Original/current/request/reconstruction preparation completes before zero-hash full planning or backend refusal observation.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Full plan admission is hash-free; whole matching deliberately uses maintained hashing under the frozen policies.
proc refuse(source: CurrentRefreshPlan, limits: CurrentLogicalRefreshLimits,
    phase: LogicalRefreshRefusal) =
  ## An admitted source never turns one-short policy into an empty complete current state.
  let refused = planCurrentLogicalRefresh(source, limits)
  assert refused.error == LogicalRefreshPlanError.LimitExceeded and refused.refusedPhase == phase
proc after(successes: cint) {.importc: "ro_blake_after", cdecl.}
  ## An independently measured maintained current qualification prefix selects the real later raw-key backend boundary.
proc cycle(plan: CurrentLogicalRefreshPlan, prefix: cint) =
  ## Retire both complete captures and a real late backend refusal after the successful current prefix each cycle.
  fail(0)
  assert executeCurrentLogicalRefresh(plan).value.currentLogicalInventory.value.suppliedLogicalInfo.value.services == 2
  after(prefix)
  let failed = executeCurrentLogicalRefresh(plan)
  assert failed.error == LogicalRefreshError.LogicalFailure
  assert failed.logicalFailure.logicalFailure.inventoryFailure.manifestFailure.compositionError ==
      StateCompositionError.BackendFailure
proc main() {.raises.} =
  ## All source identities and actual producer output come from genuine complete signed/current fixtures.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i])
  let keys = namespaceRefreshKeys(decodeOwnedReport(bytes, 2).value)
  let source = planCurrentRefresh(keys, currentRefreshTestLimits).value
  let binding = keys.requestKeysSource.value
  let original = binding.identityLogical.value
  let compact = original.suppliedInventory.value.inventoryInfo.value
  let logical = original.suppliedLogicalInfo.value
  assert compact.descriptorBytes <= 65536 and logical.retainedBytes <=
      65536 # Tiny known fixture bounds prove independent expected-retention arithmetic.
  let expectedRetained = 2*compact.descriptorBytes+logical.retainedBytes
  let target = binding.identityUpdate.value.currentUpdateState
  assert target.commitment.nodes > 0
  fail(1)
  let plan = planCurrentLogicalRefresh(source, currentLogicalRefreshTestLimits).value
  let info = plan.logicalRefreshPlanInfo.value
  assert info.services == 2 and info.entries == 30 and info.checks == 36 and info.facts == 14
  assert info.rawKeyBytes == 3 and info.retainedBytes == expectedRetained
  var exact = currentLogicalRefreshTestLimits
  exact.retainedBytes = ByteLimit(expectedRetained)
  exact.logical.inventory.facts = ElementLimit(14)
  exact.logical.inventory.bytes = ByteLimit(compact.descriptorBytes)
  exact.logical.keys = ElementLimit(4)
  exact.logical.rawKeyBytes = ByteLimit(3)
  exact.logical.bytes = ByteLimit(logical.retainedBytes)
  exact.logical.inventory.manifest.services = ElementLimit(2)
  exact.logical.inventory.manifest.serialized.items = ElementLimit(30)
  exact.logical.inventory.manifest.serialized.nodes = TrieNodeLimit(target.commitment.nodes)
  exact.logical.inventory.manifest.serialized.totalValueBytes = ByteLimit(info.valueBytes)
  exact.logical.inventory.manifest.storageKeyBytes = ByteLimit(2)
  assert planCurrentLogicalRefresh(source, exact).error == LogicalRefreshPlanError.None
  var short = exact
  short.checks = ElementLimit(35)
  refuse(source, short, LogicalRefreshRefusal.Scan)
  short = exact
  short.retainedBytes = ByteLimit(expectedRetained-1)
  refuse(source, short, LogicalRefreshRefusal.Retention)
  short = exact
  short.logical.inventory.manifest.services = ElementLimit(1)
  refuse(source, short, LogicalRefreshRefusal.Mapping)
  short = exact
  short.logical.inventory.manifest.serialized.items = ElementLimit(29)
  refuse(source, short, LogicalRefreshRefusal.Mapping)
  short = exact
  short.logical.inventory.manifest.serialized.nodes = TrieNodeLimit(target.commitment.nodes-1)
  refuse(source, short, LogicalRefreshRefusal.Mapping)
  short = exact
  short.logical.inventory.manifest.serialized.totalValueBytes = ByteLimit(info.valueBytes-1)
  refuse(source, short, LogicalRefreshRefusal.Mapping)
  short = exact
  short.logical.inventory.manifest.serialized.perValue = ByteLimit(1)
  refuse(source, short, LogicalRefreshRefusal.Mapping)
  short = exact
  short.logical.inventory.facts = ElementLimit(13)
  refuse(source, short, LogicalRefreshRefusal.Capture)
  short = exact
  short.logical.inventory.bytes = ByteLimit(compact.descriptorBytes-1)
  refuse(source, short, LogicalRefreshRefusal.Capture)
  short = exact
  short.logical.keys = ElementLimit(3)
  refuse(source, short, LogicalRefreshRefusal.Capture)
  short = exact
  short.logical.rawKeyBytes = ByteLimit(2)
  refuse(source, short, LogicalRefreshRefusal.Capture)
  short = exact
  short.logical.bytes = ByteLimit(logical.retainedBytes-1)
  refuse(source, short, LogicalRefreshRefusal.Capture)
  short = exact
  short.logical.inventory.manifest.storageKeyBytes = ByteLimit(1)
  refuse(source, short, LogicalRefreshRefusal.Capture)
  short = exact
  short.profile.bytes = ByteLimit(0)
  let badProfile = planCurrentLogicalRefresh(source, short)
  assert badProfile.error == LogicalRefreshPlanError.ProfileFailure and
      badProfile.profileFailure.error == CurrentProfileError.LimitExceeded
  short = exact
  short.globals.totalBytes = ByteLimit(0)
  let badGlobals = planCurrentLogicalRefresh(source, short)
  assert badGlobals.error == LogicalRefreshPlanError.GlobalsFailure and
      badGlobals.globalsFailure.globalFailure.error == GlobalStateError.LimitExceeded
  assert planCurrentLogicalRefresh(default(CurrentRefreshPlan), exact).error ==
      LogicalRefreshPlanError.InvalidSource
  var copied = plan.logicalRefreshPlanLimits.value
  copied.logical.keys = ElementLimit(0)
  copied.retainedBytes = ByteLimit(0)
  assert uint64(plan.logicalRefreshPlanLimits.value.logical.keys) == 64
  var facts = plan.logicalRefreshPlanInfo.value
  facts.entries = 0
  assert plan.logicalRefreshPlanInfo.value.entries == 30
  assert executeCurrentLogicalRefresh(default(CurrentLogicalRefreshPlan)).error ==
      LogicalRefreshError.InvalidPlan
  assert calls() == 0
  let failed = executeCurrentLogicalRefresh(plan)
  assert failed.error == LogicalRefreshError.StateFailure
  assert failed.stateFailure.error == CurrentStateError.ManifestFailure
  assert failed.stateFailure.manifestFailure.error == StateManifestError.CompositionFailure
  assert failed.stateFailure.manifestFailure.compositionError ==
      StateCompositionError.BackendFailure and calls() > 0
  fail(0)
  let completed = executeCurrentLogicalRefresh(plan)
  assert completed.error == LogicalRefreshError.None
  let owner = completed.value
  let result = owner.currentLogicalInventory.value.suppliedInventory.value
  let state = owner.currentLogicalSource.value
  assert sameStateSnapshot(result.inventorySource.value.manifestSource.value, target)
  assert sameStateSnapshot(state.currentStateInventory.value.inventorySource.value.manifestSource.value, target)
  assert not sameStateInventory(result, state.currentStateInventory.value)
  assert result.inventorySource.value.manifestInfo.value.valueBytes == info.valueBytes
  assert result.inventoryInfo.value.descriptorBytes == compact.descriptorBytes
  assert owner.currentLogicalInventory.value.suppliedLogicalInfo.value.retainedBytes ==
      logical.retainedBytes
  assert sameStateSnapshot(state.currentStateGlobals.value.qualifiedCurrentProfile.value.derivedUpdate.value.currentUpdateState, target)
  let declarations = executeCurrentRefresh(source).value
  fail(0)
  assert qualifyCurrentState(state.currentStateGlobals.value, declarations,
      plan.logicalRefreshPlanLimits.value.logical.inventory).error == CurrentStateError.None
  let prefix = calls()
  assert prefix > 0 and prefix < 100000 # Fixture bounds prove the observer's finite signed call-count domain.
  after(prefix)
  let later = executeCurrentLogicalRefresh(plan)
  assert later.error == LogicalRefreshError.LogicalFailure
  assert later.logicalFailure.error == CurrentLogicalError.LogicalFailure
  assert later.logicalFailure.logicalFailure.error == SuppliedLogicalError.InventoryFailure
  assert later.logicalFailure.logicalFailure.inventoryFailure.error ==
      StateInventoryError.ManifestFailure
  assert later.logicalFailure.logicalFailure.inventoryFailure.manifestFailure.compositionError ==
      StateCompositionError.BackendFailure
  for i in 0..<25: cycle(plan, prefix)
  let before = getOccupiedMem()
  for i in 0..<1000: cycle(plan, prefix)
  let finalBytes = getOccupiedMem()
  assert before == finalBytes
  recordArcRelease("state_current_refresh_logical", 1000, before, finalBytes)
  fail(0)
  echo "state-current-refresh-logical: ok"
try:
  main()
except:
  quit(2) # No frozen full-plan execution can bypass genuine producer/context or actual whole-map qualification.
