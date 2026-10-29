# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Restored maps require fresh source-bound execution; root-equal old certificates never regain adoption authority.
import std/[assertions, syncio, envvars]
import std/posix/posix
import ../../../src/app/[services, chain, candidate, handoff]
import ../../../src/app/checkpoint/identity as checkpoint_identity
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/[report_owned, bounded]
import ../../../src/codec/state/layout as state_layout
import ../../../src/state/store
import ../../../src/state/accumulation/chain as accumulation_chain
import ../../support/application_candidate_context as candidate_context
import ../../support/accumulation_completion_context
import ../../support/application_recovery_execution
proc main() {.raises.} =
  ## The genuine signed child is prepared independently against direct and recovered complete-map owners.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var report = newSeq[byte](raw.len)
  for index, octet in raw:
    report[index] = byte(octet) # Only initialized pinned fixture bytes reach owned report decoding.
  let fixture = recoveryFixture(decodeOwnedReport(report, 2).value)
  let child = candidate_context.candidateBlock(fixture.origin)
  let resources = candidate_context.preparationLimits()
  let composition = completionLimits().composition
  var direct = candidate_context.initialized(fixture.origin)
  let prepared = direct.prepareCandidate(child, [], resources)
  assert prepared.error == ApplicationCandidateError.None
  let expected = direct.applyAccumulation(prepared.value, composition)
  assert expected.error == ApplicationChainError.None
  var path = "application-recovery-successor-chain"
  defer: discard posix.unlink(path.toCString())
  var owner = default(Services)
  defer: owner.close()
  startRecoveredExecution(owner, fixture, path, candidate_context.policy())
  let before = owner.stateSnapshot.value
  let detached = owner.applyAccumulation(fixture.origin.source, composition)
  assert detached.error == ApplicationChainError.ChainFailure
  assert detached.chainFailure.error == AccumulationChainError.StaleState
  assert sameStateSnapshot(before, owner.stateSnapshot.value)
  let queued = owner.enqueueCandidate(child, [], resources, composition)
  assert queued.error == ApplicationCandidateError.None
  assert owner.accumulationStage == AccumulationHandoffStage.Pending
  assert sameStateSnapshot(before, owner.stateSnapshot.value) # Successful private preparation alone grants no canonical publication.
  owner.tick(0)
  assert owner.accumulationStage == AccumulationHandoffStage.Finished
  let adopted = owner.takeAccumulation()
  assert adopted.error == ApplicationChainError.None
  assert adopted.value.slot == expected.value.slot
  assert array[32, byte](adopted.value.blockHash) == array[32, byte](expected.value.blockHash)
  let actual = owner.stateSnapshot.value
  let oracle = direct.stateSnapshot.value
  assert array[32, byte](actual.commitment.root) == array[32, byte](oracle.commitment.root)
  assert actual.commitment.entries == oracle.commitment.entries
  for index in 0..<oracle.commitment.entries:
    let key = oracle.keyAt(StateEntryIndex(index)).value
    assert actual.lookup(key).value.bytes == oracle.lookup(
        key).value.bytes # Exact count and every original entry establish full-map parity with uninterrupted execution.
  assert sameStateSnapshot(actual, adopted.value.stateSnapshot)
  assert owner.chainView.retainedCount == 2
  assert owner.chainView.parentOf(adopted.value.blockHash).error == GenesisError.None
  assert owner.chainView.finalizedBlock.error != GenesisError.None
  assert before.lookup(chapterKey(StateChapter(11))).value.bytes == @[1'u8, 0, 0, 0]
  assert actual.lookup(chapterKey(StateChapter(11))).value.bytes == @[2'u8, 0, 0, 0]
  let replay = owner.applyAccumulation(queued.value, composition)
  assert replay.chainFailure.error == AccumulationChainError.StaleState
  assert sameStateSnapshot(actual, owner.stateSnapshot.value) # Replayed pre-adoption authority cannot publish twice.
  echo "PASS application recovery successor: fresh signed execution, full-map parity, stale authority refusal and retained parent"
try:
  main() # Fixture/native errors cannot turn an unexecuted recovered map into a successful block.
except:
  quit(2)
