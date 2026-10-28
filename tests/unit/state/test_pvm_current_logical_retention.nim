# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exact-wire admitted plans from real Services collection retain original logical provenance beyond joined close and release every repeated ARC result.
# @@Verification={"arc":"pvm_current_logical_retention_arc_release"}
import std/[assertions, envvars, syncio]
import std/posix/posix
import ../../support/[current_namespace_execution_context, current_logical_history_context,
    current_logical_collection_context, current_application_context, parent_profile_context,
    parent_globals_context, supplied_logical_context, current_identity_context,
    accumulation_current_candidate_context, current_logical_proof_context,
    current_namespace_refresh_context, arc_evidence]
import ../../../src/app/[services, options, current_block_input, current_handoff]
import ../../../src/chain/[provider, genesis]
import ../../../src/codec/[bounded, report_owned, state_accounts, state_service_values]
import ../../../src/state/[parent_profile, parent_globals, parent_logical, current_identities,
    current_request_keys, current_refresh_plan, current_logical_refresh,
    accumulation_current_update, store, block_admission, report_admission]
type RetainedHistoryPlan = object ## Only actual successful opaque plan construction grants this test descriptor; mutable fields grant no State authority.
  plan: CurrentLogicalRefreshPlan
  state: StateStoreSnapshot
  hash: ServicePreimageHash
  restored: bool
proc collectRetainedHistory(base: OwnedReport, restore: bool): RetainedHistoryPlan {.raises.} =
  ## Build/collect genuine native execution, admit its changed history at the exact wire boundary, then join Services before returning the retained immutable plan.
  let fixture = logicalHistoryFixture(base, restore)
  var path = "pvm-current-logical-retention-chain"
  writeFile(path, fixture.parent.bestBlock.value.currentApplicationText)
  defer: discard posix.unlink(path.toCString())
  var options = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain", path], options)
  var input = default(CurrentBlockInput)
  var owner = default(Services)
  defer: owner.close() # Original worker/canonical owners retire only after collection; the returned frozen plan owns its required immutable provenance.
  assert owner.start(options, "retained collected logical plan")
  let before = owner.stateSnapshot.value
  let profile = captureParentProfile(owner.chainView, parentProfileTestLimits)
  assert profile.error == ParentProfileError.None
  let globals = qualifyParentGlobals(profile.value, parentGlobalsTestLimits)
  assert globals.error == ParentGlobalsError.None
  let declarations = fixture.executableNamespaceServices(before)
  let parent = captureLogicalParent(globals.value, declarations, suppliedLogicalTestLimits)
  assert parent.error == ParentLogicalError.None
  let child = fixture.source.round.roundBlockQueue.value.accumulationAdmission.value.reportBlockStage.value.value.admitted.admittedBlock
  let update = owner.collectLogicalChild(input, child, currentCandidateLimits())
  let identities = preserveCurrentIdentities(parent.value, update, currentIdentityTestLimits)
  assert identities.error == CurrentIdentityError.None
  let keys = captureCurrentRequestKeys(identities.value, namespaceRequestLimits)
  assert keys.error == CurrentRequestKeyError.None
  let wireBytes = if restore: 248'u64 else: 244'u64
  assert wireBytes > 0
  var resources = namespaceRefreshLimits
  resources.wireBytes = ByteLimit(wireBytes-1)
  let refused = planCurrentRefresh(keys.value, resources)
  assert refused.error == CurrentRefreshPlanError.LimitExceeded
  assert refused.refusedPhase == CurrentRefreshRefusal.Wire
  assert sameStateSnapshot(before, owner.stateSnapshot.value)
  assert owner.currentAccumulationPhase == CurrentHandoffPhase.Idle
  resources.wireBytes = ByteLimit(wireBytes)
  let reconstruction = planCurrentRefresh(keys.value, resources)
  assert reconstruction.error == CurrentRefreshPlanError.None
  assert reconstruction.value.refreshPlanInfo.value.wireBytes == wireBytes
  let plan = planCurrentLogicalRefresh(reconstruction.value, namespaceLogicalLimits())
  assert plan.error == LogicalRefreshPlanError.None
  RetainedHistoryPlan(plan: plan.value, state: update.currentUpdateState,
      hash: fixture.seeds[1].preimages[1].hash, restored: restore)
proc cycle(source: RetainedHistoryPlan) =
  ## Every complete result still names the exact real collected snapshot after its original Services lifetime; function exit retires all temporary capture/key owners.
  let logical = executeCurrentLogicalRefresh(source.plan)
  assert logical.error == LogicalRefreshError.None
  assert sameStateSnapshot(logical.value.logicalProducer.currentUpdateState, source.state)
  logical.value.checkCollectedHistory(source.hash, source.restored)
proc main() {.raises.} =
  ## Both independently collected history branches survive their original native/application owners and repeated complete logical qualification under ARC.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i])
  let base = decodeOwnedReport(bytes, 2).value
  let forgotten = collectRetainedHistory(base, false)
  let restored = collectRetainedHistory(base, true)
  for i in 0..<25:
    cycle(forgotten)
    cycle(restored) # Warm both actual branches before measuring only repeated logical result ownership.
  let before = getOccupiedMem()
  for i in 0..<1000:
    cycle(forgotten)
    cycle(restored)
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("pvm_current_logical_retention", 1000, before, after)
  echo "PVM current logical retention passed"
try:
  main()
except:
  quit(2) # Actual execution/admission, scope provenance and ARC release must all succeed before recording evidence.
