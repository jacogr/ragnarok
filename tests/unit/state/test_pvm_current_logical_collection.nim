# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A configured Services parent and genuinely collected native current successor qualify complete logical continuation before enqueue.
import std/[assertions, envvars, syncio, monotimes, times]
import std/posix/posix
import ../../support/[current_namespace_execution_context, current_application_context,
    accumulation_current_candidate_context, parent_profile_context, parent_globals_context,
    supplied_logical_context, current_identity_context, current_namespace_refresh_context,
    current_logical_proof_context]
import ../../../src/app/[services, options, preparation_worker]
import "../../../src/app/current/block/input" as current_block_input
import ../../../src/app/current/handoff as current_handoff
import ../../../src/rpc/server
import ../../../src/chain/[provider, genesis]
import ../../../src/codec/[bounded, block_codec, report_owned]
import ../../../src/state/parent/[profile as parent_profile, globals as parent_globals,
    logical as parent_logical]
import ../../../src/state/current/[identities as current_identities,
    request_keys as current_request_keys]
import ../../../src/state/current/refresh/plan as current_refresh_plan
import ../../../src/state/current/logical/refresh as current_logical_refresh
import ../../../src/state/accumulation/current/update as accumulation_current_update
import ../../../src/state/store
import "../../../src/state/block/admission" as block_admission
import ../../../src/state/report/admission as report_admission
proc waitDone(owner: var Services) =
  ## Only synchronized scalar worker observations and independent service ticks occur during the exclusive canonical graph lease.
  let started = getMonoTime()
  while owner.preparationPhase != PreparationPhase.Done:
    assert (getMonoTime()-started).inSeconds < 20
    owner.tick(0)
    var delay = Timespec(tv_sec: posix.Time(0), tv_nsec: 1_000_000)
    var remaining = default(Timespec)
    discard nanosleep(delay, remaining)
proc scenario(fixture: NamespaceExecutionFixture) {.raises.} =
  ## Startup creates the physical parent that must seed logical qualification; the fixture's equal-root parent cannot substitute for it.
  var path = "pvm-current-logical-collection-chain"
  writeFile(path, fixture.parent.bestBlock.value.currentApplicationText)
  defer: discard posix.unlink(path.toCString())
  var options = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain", path], options)
  let admitted = fixture.source.round.roundBlockQueue.value.accumulationAdmission.value
  let child = admitted.reportBlockStage.value.value.admitted.admittedBlock
  var wire = newSeq[byte](child.blockInfo.value.consumed)
  assert child.encodeOwnedBlock(wire).error == FrameError.None
  var input = default(CurrentBlockInput)
  var owner = default(Services)
  defer: owner.close() # Actual collection or joined shutdown precedes retirement of retained canonical/input owners.
  assert owner.start(options, "current logical collection")
  let before = owner.stateSnapshot.value
  let head = owner.chainView.bestBlock.value.blockHash
  let profile = captureParentProfile(owner.chainView, parentProfileTestLimits)
  assert profile.error == ParentProfileError.None
  let globals = qualifyParentGlobals(profile.value, parentGlobalsTestLimits)
  assert globals.error == ParentGlobalsError.None
  let declarations = fixture.executableNamespaceServices(before)
  let parent = captureLogicalParent(globals.value, declarations, suppliedLogicalTestLimits)
  assert parent.error == ParentLogicalError.None
  let received = owner.beginBlockInput(input, ByteLimit(uint64(wire.len)), [],
      CurrentBlockInputLimits(blockBytes: ByteLimit(uint64(wire.len)),
          ancestorBytes: ByteLimit(10000), ancestors: ElementLimit(4)), currentCandidateLimits())
  assert received.error == CurrentBlockInputError.None
  assert input.append(received.value, wire, true) == CurrentBlockInputError.None
  let ticket = owner.beginPreparation(input, received.value)
  assert ticket.error == PreparationError.None
  owner.waitDone()
  assert owner.preparationActive and owner.rpc.chainPaused
  assert owner.collectPreparation(default(PreparationTicket)).kind ==
      PreparationCompletionKind.Uninitialized
  assert owner.preparationActive and owner.preparationPhase == PreparationPhase.Done
  let completed = owner.collectPreparation(ticket.value)
  assert completed.kind == PreparationCompletionKind.CurrentCompleted
  assert completed.currentValue.error == CurrentBlockInputError.None
  assert not owner.preparationActive and not owner.rpc.chainPaused
  assert owner.preparationAvailable and owner.stateProofAvailable
  assert owner.currentAccumulationPhase == CurrentHandoffPhase.Idle
  let update = completed.currentValue.value
  # Qualification runs on the open host gate; none of these refusals may enqueue or publish the genuine successor.
  let foreignProfile = captureParentProfile(fixture.parent, parentProfileTestLimits).value
  let foreignGlobals = qualifyParentGlobals(foreignProfile, parentGlobalsTestLimits).value
  let foreignServices = fixture.executableNamespaceServices(
      foreignProfile.parentContext.value.state)
  let foreignParent = captureLogicalParent(foreignGlobals, foreignServices,
      suppliedLogicalTestLimits).value
  assert array[32, byte](foreignProfile.parentContext.value.state.commitment.root) == array[32,
      byte](before.commitment.root)
  assert preserveCurrentIdentities(foreignParent, update, currentIdentityTestLimits).error ==
      CurrentIdentityError.ParentMismatch
  let finalized = owner.chainView.finalizeView(head)
  assert finalized.error == ViewFinalizeError.None
  let alteredProfile = captureParentProfile(finalized.value, parentProfileTestLimits).value
  let alteredGlobals = qualifyParentGlobals(alteredProfile, parentGlobalsTestLimits).value
  let alteredParent = captureLogicalParent(alteredGlobals, declarations,
      suppliedLogicalTestLimits).value
  assert sameStateSnapshot(alteredProfile.parentContext.value.state, before)
  assert preserveCurrentIdentities(alteredParent, update, currentIdentityTestLimits).error ==
      CurrentIdentityError.ViewMismatch
  var identityLimits = currentIdentityTestLimits
  identityLimits.keys = ElementLimit(0)
  assert preserveCurrentIdentities(parent.value, update, identityLimits).error ==
      CurrentIdentityError.LimitExceeded
  let identities = preserveCurrentIdentities(parent.value, update, currentIdentityTestLimits)
  assert identities.error == CurrentIdentityError.None
  let keys = captureCurrentRequestKeys(identities.value, namespaceRequestLimits)
  assert keys.error == CurrentRequestKeyError.None
  var keyLimits = namespaceRequestLimits
  keyLimits.requests = ElementLimit(0)
  assert captureCurrentRequestKeys(identities.value, keyLimits).error ==
      CurrentRequestKeyError.LimitExceeded
  var reconstructionLimits = namespaceRefreshLimits
  reconstructionLimits.projection.bytes = ByteLimit(0)
  let refusedCopy = planCurrentRefresh(keys.value, reconstructionLimits)
  assert refusedCopy.error == CurrentRefreshPlanError.LimitExceeded
  assert refusedCopy.refusedPhase == CurrentRefreshRefusal.Projection
  let reconstruction = planCurrentRefresh(keys.value, namespaceRefreshLimits)
  assert reconstruction.error == CurrentRefreshPlanError.None
  let plan = planCurrentLogicalRefresh(reconstruction.value, namespaceLogicalLimits())
  assert plan.error == LogicalRefreshPlanError.None
  var logicalLimits = namespaceLogicalLimits()
  logicalLimits.retainedBytes = ByteLimit(0)
  let refusedLogical = planCurrentLogicalRefresh(reconstruction.value, logicalLimits)
  assert refusedLogical.error == LogicalRefreshPlanError.LimitExceeded
  assert refusedLogical.refusedPhase == LogicalRefreshRefusal.Retention
  assert sameStateSnapshot(before, owner.stateSnapshot.value)
  assert owner.currentAccumulationPhase == CurrentHandoffPhase.Idle
  assert owner.preparationAvailable and owner.stateProofAvailable
  let logical = executeCurrentLogicalRefresh(plan.value)
  assert logical.error == LogicalRefreshError.None
  assert sameStateSnapshot(logical.value.logicalProducer.currentUpdateState,
      update.currentUpdateState)
  assert array[32, byte](update.currentUpdateState.commitment.root) ==
      array[32, byte](fixture.update.currentUpdateState.commitment.root)
  assert sameStateSnapshot(before, owner.stateSnapshot.value)
  assert array[32, byte](owner.chainView.bestBlock.value.blockHash) == array[32, byte](head)
  assert owner.currentAccumulationPhase == CurrentHandoffPhase.Idle # Qualification itself grants neither enqueue nor installation authority.
  assert owner.enqueueCurrentAccumulation(update) == CurrentHandoffAdmission.None
  owner.tick(0)
  assert owner.currentAccumulationPhase == CurrentHandoffPhase.Finished
  assert owner.takeCurrentAccumulation().error == CurrentHandoffError.None
  assert sameStateSnapshot(owner.stateSnapshot.value,
      logical.value.logicalProducer.currentUpdateState)
  assert owner.preparationAvailable and owner.stateProofAvailable
proc main() {.raises.} =
  ## Real complete signed code/request/storage namespaces survive native HALT execution and bounded exact-current matching.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i])
  let code = namespaceHaltCode()
  let fixture = namespaceExecutionFixture(decodeOwnedReport(bytes, 2).value, code, code)
  scenario(fixture)
  echo "PVM current logical collection passed"
try:
  main()
except:
  quit(2) # Native preparation, complete-map qualification and eventual exact installation must all succeed.
