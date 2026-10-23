# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Equal-byte/root current states produced by the same authentic block still retain distinct physical predecessor authority.
# @@Verification={"arc":"state_current_logical_physical_refusals_arc_release"}
import std/[assertions, envvars, syncio]
import ../../support/[current_repeated_logical_context, current_identity_context,
    current_namespace_refresh_context, parent_profile_context, parent_globals_context,
    supplied_logical_context, accumulation_current_candidate_context,
    accumulation_current_chain_context, arc_evidence]
import ../../../src/state/[current_identities, current_request_keys, current_refresh_plan,
    current_logical_refresh, parent_logical, parent_globals, parent_profile, current_logical,
    supplied_logical_inventory, inventory, manifest, store, accumulation_current_update,
    accumulation_round, accumulation_queue, report_admission, block_transition, block_admission]
import ../../../src/chain/[provider, genesis]
import ../../../src/app/[chain, candidate]
import ../../../src/codec/[bounded, report_owned]
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Honest original-map reconstruction and both actual current pipelines complete before physical identity comparison.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Physical/retained-view original binding never rehashes equal byte roots.
proc check(first, second: CurrentLogicalState, firstNext, secondNext: PreparedCurrentChainUpdate) =
  ## Replayed genuine input under another full physical owner never grants continuation of the first owner's logical context.
  assert preserveCurrentIdentities(first, secondNext, currentIdentityTestLimits).error ==
      CurrentIdentityError.ParentMismatch
  assert preserveCurrentIdentities(second, firstNext, currentIdentityTestLimits).error ==
      CurrentIdentityError.ParentMismatch
proc main() {.raises.} =
  ## Reuse the exact actually signed block bytes, not a forged successful update or substituted detached target.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i])
  let fixture = repeatedLogicalFixture(decodeOwnedReport(bytes, 2).value)
  let originalContext = fixture.first.parent.logicalParentGlobals.value.parentGlobalsProfile.value.parentContext.value
  var writable = genesisStoreLimits()
  writable.writes = ElementLimit(1000)
  writable.writeValueBytes = ByteLimit(1000000) # Replayed execution needs explicit write admission; default genesis capture is read-only.
  let rebuilt = newStateStore(fixture.first.source.entries, writable).value.snapshot.value
  assert array[32, byte](rebuilt.commitment.root) == array[32, byte](
      originalContext.state.commitment.root)
  assert not sameStateSnapshot(rebuilt, originalContext.state)
  let captured = captureBlockSnapshot(currentChainBytes(originalContext.header), rebuilt,
      originalContext.parameters)
  assert captured.error == GenesisError.None
  let view = genesisView(captured).finalizeView(captured.value.blockHash).value
  let profile = captureParentProfile(view, parentProfileTestLimits).value
  let globals = qualifyParentGlobals(profile, parentGlobalsTestLimits).value
  let parent = captureLogicalParent(globals, fixture.first.services,
      suppliedLogicalTestLimits).value
  let admitted = fixture.first.source.round.roundBlockQueue.value.accumulationAdmission.value.reportBlockStage.value.value.admitted.admittedBlock
  let application = initApplicationChain(view).value
  let prepared = prepareCurrentCandidate(application, admitted, fixture.first.source.older,
      currentCandidateLimits())
  assert prepared.error == CurrentCandidateError.None
  let update = prepared.value
  let identities = preserveCurrentIdentities(parent, update, currentIdentityTestLimits).value
  let keys = captureCurrentRequestKeys(identities, namespaceRequestLimits).value
  let reconstruction = planCurrentRefresh(keys, namespaceRefreshLimits).value
  let logical = executeCurrentLogicalRefresh(planCurrentLogicalRefresh(reconstruction,
      namespaceLogicalLimits()).value).value
  let next = nextLogicalEmpty(update)
  let first = fixture.first.update.currentUpdateState
  let second = update.currentUpdateState
  assert array[32, byte](first.commitment.root) == array[32, byte](second.commitment.root)
  assert array[32, byte](fixture.first.update.currentUpdateChildContext.hash) == array[32, byte](
      update.currentUpdateChildContext.hash)
  assert not sameStateSnapshot(first, second)
  assert not sameStateInventory(fixture.logical.currentLogicalInventory.value.suppliedInventory.value,
      logical.currentLogicalInventory.value.suppliedInventory.value)
  fail(1)
  check(fixture.logical, logical, fixture.next, next)
  assert preserveCurrentIdentities(fixture.logical, fixture.next,
      currentIdentityTestLimits).error == CurrentIdentityError.None
  assert preserveCurrentIdentities(logical, next, currentIdentityTestLimits).error ==
      CurrentIdentityError.None
  assert calls() == 0
  for i in 0..<25: check(fixture.logical, logical, fixture.next, next)
  let before = getOccupiedMem()
  for i in 0..<1000: check(fixture.logical, logical, fixture.next, next)
  let finalBytes = getOccupiedMem()
  assert before == finalBytes and calls() == 0
  recordArcRelease("state_current_logical_physical_refusals", 1000, before, finalBytes)
  fail(0)
  echo "state-current-logical-physical-refusals: ok"
try:
  main()
except:
  quit(2) # Only actually replayed authentic current candidate/full matching can establish these equal-root/different-owner sources.
