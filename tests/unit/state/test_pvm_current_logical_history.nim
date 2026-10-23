# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual Services native forget/restore execution refreshes complete logical request histories before host enqueue.
import std/[assertions, envvars, syncio]
import std/posix/posix
import ../../support/[current_namespace_execution_context, current_logical_history_context,
    current_logical_collection_context, current_application_context, parent_profile_context,
    parent_globals_context, supplied_logical_context, current_identity_context,
    accumulation_current_candidate_context, current_logical_proof_context]
import ../../../src/app/[services, options, current_block_input, current_handoff]
import ../../../src/chain/[provider, genesis]
import ../../../src/codec/[bounded, report_owned, state_accounts, state_requests]
import ../../../src/state/[parent_profile, parent_globals, parent_logical, current_identities,
    accumulation_current_update, store, block_admission, report_admission]
proc scenario(fixture: NamespaceExecutionFixture, restore: bool) {.raises.} =
  ## Seed the actual configured physical parent, collect a genuinely executed history update and qualify it while host access is open.
  var path = "pvm-current-logical-history-chain"
  writeFile(path, fixture.parent.bestBlock.value.currentApplicationText)
  defer: discard posix.unlink(path.toCString())
  var options = default(Options)
  assert parseOptions(@["server", "--with-state", "--chain", path], options)
  var input = default(CurrentBlockInput)
  var owner = default(Services)
  defer: owner.close()
  assert owner.start(options, "collected logical history")
  let before = owner.stateSnapshot.value
  let hash = fixture.seeds[1].preimages[1].hash
  let key = serviceRequestKey(ServiceIndex(99), hash, RequestLength(1), ByteLimit(32)).value
  assert before.lookup(key).value.byteLength == 5
  let profile = captureParentProfile(owner.chainView, parentProfileTestLimits).value
  let globals = qualifyParentGlobals(profile, parentGlobalsTestLimits).value
  let declarations = fixture.executableNamespaceServices(before)
  let parent = captureLogicalParent(globals, declarations, suppliedLogicalTestLimits).value
  let child = fixture.source.round.roundBlockQueue.value.accumulationAdmission.value.reportBlockStage.value.value.admitted.admittedBlock
  let update = owner.collectLogicalChild(input, child, currentCandidateLimits())
  let identities = preserveCurrentIdentities(parent, update, currentIdentityTestLimits)
  assert identities.error == CurrentIdentityError.None
  let logical = refreshCollectedIdentities(identities.value)
  logical.checkCollectedHistory(hash, restore)
  assert sameStateSnapshot(logical.logicalProducer.currentUpdateState, update.currentUpdateState)
  assert sameStateSnapshot(before, owner.stateSnapshot.value)
  assert owner.currentAccumulationPhase == CurrentHandoffPhase.Idle
  assert owner.enqueueCurrentAccumulation(update) == CurrentHandoffAdmission.None
  owner.tick(0)
  assert owner.currentAccumulationPhase == CurrentHandoffPhase.Finished
  assert owner.takeCurrentAccumulation().error == CurrentHandoffError.None
  assert sameStateSnapshot(owner.stateSnapshot.value, logical.logicalProducer.currentUpdateState)
  assert before.lookup(key).value.byteLength == 5 # The original configured owner remains unchanged after actual logical history adoption.
proc main() {.raises.} =
  ## Available(1) becomes Unavailable(1,2) or Reavailable(1,2,2) through real native guest hosts, never caller-authored posterior histories.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i])
  let base = decodeOwnedReport(bytes, 2).value
  for restore in [false, true]: scenario(logicalHistoryFixture(base, restore), restore)
  echo "PVM current logical histories passed"
try:
  main()
except:
  quit(2) # Native request execution, exact logical provenance and host installation must all succeed.
