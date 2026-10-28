# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Equal-byte/root current states produced by the same authentic block still retain distinct physical predecessor authority.
# @@Verification={"arc":"state_current_logical_physical_refusals_arc_release"}
import std/assertions
import std/envvars
import std/syncio
import ../../support/state_current_repeated_logical_context
import ../../support/state_current_identity_context
import ../../support/state_current_namespace_refresh_context
import ../../support/state_parent_profile_context
import ../../support/state_parent_globals_context
import ../../support/codec_supplied_logical_context
import ../../support/state_accumulation_current_candidate_context
import ../../support/state_accumulation_current_chain_context
import ../../support/testing_arc_evidence
import ../../../src/state/current_identities as state_current_identities
import ../../../src/state/current_request_keys as state_current_request_keys
import ../../../src/state/current_refresh_plan as state_current_refresh_plan
import ../../../src/state/current_logical_refresh as state_current_logical_refresh
import ../../../src/state/parent_logical as state_parent_logical
import ../../../src/state/parent_globals as state_parent_globals
import ../../../src/state/parent_profile as state_parent_profile
import ../../../src/state/current_logical as state_current_logical
import ../../../src/state/supplied_logical_inventory as state_supplied_logical_inventory
import ../../../src/state/inventory as state_inventory
import ../../../src/state/manifest as state_manifest
import ../../../src/state/store as state_store
import ../../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../../src/state/accumulation_round as state_accumulation_round
import ../../../src/state/accumulation_queue as state_accumulation_queue
import ../../../src/state/report_admission as state_report_admission
import ../../../src/state/block_transition as state_block_transition
import ../../../src/state/block_admission as state_block_admission
import ../../../src/chain/provider as chain_provider
import ../../../src/chain/genesis as chain_genesis
import ../../../src/app/chain as app_chain
import ../../../src/app/candidate as app_candidate
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/report_owned as codec_report_owned
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
