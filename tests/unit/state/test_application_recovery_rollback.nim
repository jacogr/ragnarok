# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Late native refusal and inherited composition ceilings cannot partially replace a recovered canonical pair.
import std/[assertions, syncio, envvars]
import std/posix/posix
import ../../../src/app/[services, chain, candidate, handoff]
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/report_owned
import ../../../src/state/store
import ../../../src/state/accumulation/[chain as accumulation_chain, state as accumulation_state,
    completion as accumulation_completion, consensus as accumulation_consensus]
import ../../support/application_candidate_context as candidate_context
import ../../support/accumulation_completion_context
import ../../support/application_recovery_execution
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Existing observer injects an actual maintained primitive refusal without changing production state logic.
proc failAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
  ## Refuse only after the measured positive path has completed all earlier hashes.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Observe actual Blake2b calls, including the selected failing invocation.
proc main() {.raises.} =
  ## Fresh source authority is prepared once against the recovered map, then exercised through private branches and late failure.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var report = newSeq[byte](raw.len)
  for index, octet in raw:
    report[index] = byte(octet) # Only initialized pinned report bytes supply the genuine signed fixture.
  let fixture = recoveryFixture(decodeOwnedReport(report, 2).value)
  let child = candidate_context.candidateBlock(fixture.origin)
  let resources = candidate_context.preparationLimits()
  let composition = completionLimits().composition
  var path = "application-recovery-rollback-chain"
  defer: discard posix.unlink(path.toCString())
  var owner = default(Services)
  defer: owner.close()
  startRecoveredExecution(owner, fixture, path, candidate_context.policy())
  let before = owner.stateSnapshot.value
  let queued = owner.enqueueCandidate(child, [], resources, composition)
  assert queued.error == ApplicationCandidateError.None
  assert owner.cancelAccumulation() # Retain the immutable source locally while freeing producer capacity without publication.
  var control = initApplicationChain(owner.chainView).value
  failHash(0)
  let succeeded = control.applyAccumulation(queued.value, composition)
  let cost = hashCalls()
  assert succeeded.error == ApplicationChainError.None and cost > 0
  assert sameStateSnapshot(before, owner.stateSnapshot.value) # Successful private branch application cannot update the original handle pair.
  failAfter(cost - 1)
  let failed = owner.applyAccumulation(queued.value, composition)
  let observed = hashCalls()
  failHash(0)
  assert failed.error == ApplicationChainError.ChainFailure
  assert failed.chainFailure.error == AccumulationChainError.CaptureFailure
  assert observed == cost # All composition hashes succeeded before the actual sealed-header hash refusal.
  assert sameStateSnapshot(before, owner.stateSnapshot.value)
  assert owner.chainView.retainedCount == 1
  let retried = owner.applyAccumulation(queued.value, composition)
  assert retried.error == ApplicationChainError.None
  assert hashCalls() == cost
  assert array[32, byte](retried.value.stateRoot) == array[32, byte](succeeded.value.stateRoot)
  assert sameStateSnapshot(retried.value.stateSnapshot, owner.stateSnapshot.value)
  var capped = default(Services)
  defer: capped.close()
  startRecoveredExecution(capped, fixture, path, candidate_context.policy(6))
  let limitedBefore = capped.stateSnapshot.value
  let prepared = capped.enqueueCandidate(child, [], resources, composition)
  assert prepared.error == ApplicationCandidateError.None # Earlier per-stage batches fit; the inherited final consensus batch does not.
  capped.tick(0)
  let limited = capped.takeAccumulation()
  assert limited.error == ApplicationChainError.ChainFailure
  assert limited.chainFailure.applicationFailure.compositionFailure.consensusFailure.stateError ==
      StateStoreError.LimitExceeded
  assert sameStateSnapshot(limitedBefore, capped.stateSnapshot.value)
  assert capped.chainView.retainedCount == 1
  assert capped.enqueueAccumulation(prepared.value, composition) == AccumulationEnqueueError.None
  capped.tick(0)
  let repeated = capped.takeAccumulation()
  assert repeated.chainFailure.applicationFailure.compositionFailure.consensusFailure.stateError ==
      StateStoreError.LimitExceeded
  assert sameStateSnapshot(limitedBefore, capped.stateSnapshot.value) # Explicit retry cannot widen inherited storage policy.
  echo "PASS application recovery rollback: actual late hash refusal, exact retry and inherited late quota atomicity"
try:
  main() # Genuine controls distinguish actual native refusal from malformed source or setup failure.
except:
  quit(2)
