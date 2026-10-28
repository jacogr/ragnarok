# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Restored canonical maps cross real managed native execution leases without early publication or alias retirement.
import std/assertions
import std/syncio
import std/envvars
import std/posix/posix
import ../../../src/app/services as app_services
import ../../../src/app/chain as app_chain
import ../../../src/app/block_input as app_block_input
import ../../../src/app/preparation_worker as app_preparation_worker
import ../../../src/app/handoff as app_handoff
import ../../../src/rpc/server as rpc_server
import ../../../src/chain/genesis as chain_genesis
import ../../../src/chain/provider as chain_provider
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/state/store as state_store
import ../../../src/state/accumulation_finalization as state_accumulation_finalization
import ../../support/app_candidate_context as candidate_context
import ../../support/state_accumulation_completion_context
import ../../support/app_recovery_execution
proc main() {.raises.} =
  ## Independent fixture graphs remain idle; only the freshly restored canonical graph is leased to native execution.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var report = newSeq[byte](raw.len)
  for index, octet in raw:
    report[index] = byte(octet) # Owned report decode sees only initialized pinned bytes.
  let fixture = recoveryFixture(decodeOwnedReport(report, 2).value)
  let wire = recoveryChildBytes(fixture)
  var path = "application-recovery-preparation-chain"
  defer: discard posix.unlink(path.toCString())
  var input = default(BlockInput)
  var owner = default(Services)
  defer: owner.close() # Join before the borrowed input and canonical owners retire.
  startRecoveredExecution(owner, fixture, path, candidate_context.policy())
  assert owner.preparationAvailable
  let id = receiveRecoveryInput(owner, input, wire)
  let admitted = owner.beginPreparation(input, id)
  assert admitted.error == PreparationError.None
  assert owner.preparationActive and owner.rpc.chainPaused
  assert not owner.preparationAvailable and not owner.cancelAccumulation()
  let foreign = default(PreparationTicket)
  assert owner.collectPreparation(foreign).kind == PreparationCompletionKind.Uninitialized
  assert owner.preparationActive # Foreign collection never releases the actual canonical graph gate.
  waitRecoveredPreparation(owner)
  assert owner.preparationActive and owner.rpc.chainPaused and not owner.preparationAvailable
  let completed = owner.collectPreparation(admitted.value)
  assert completed.kind == PreparationCompletionKind.Completed
  assert completed.value.error == BlockInputError.None
  assert not owner.preparationActive and not owner.rpc.chainPaused
  let parent = completed.value.value.finalAccumulationParent.value
  assert sameStateSnapshot(parent, owner.stateSnapshot.value)
  assert owner.chainView.retainedCount == 1 # Native completion alone cannot publish the returned certificate.
  assert owner.enqueueAccumulation(completed.value.value, completionLimits().composition) ==
      AccumulationEnqueueError.None
  owner.tick(0)
  let adopted = owner.takeAccumulation()
  assert adopted.error == ApplicationChainError.None and adopted.value.slot == 2
  assert owner.chainView.retainedCount == 2 and owner.chainView.finalizedBlock.error !=
      GenesisError.None
  let next = receiveRecoveryInput(owner, input, [255'u8])
  let cancelled = owner.beginPreparation(input, next)
  assert cancelled.error == PreparationError.None
  assert not owner.cancelPreparation(admitted.value) # A collected generation cannot cancel later work.
  assert owner.cancelPreparation(cancelled.value)
  waitRecoveredPreparation(owner)
  assert owner.preparationActive and owner.rpc.chainPaused
  assert owner.collectPreparation(cancelled.value).kind == PreparationCompletionKind.Cancelled
  assert not owner.preparationActive and not owner.rpc.chainPaused
  discard input.cancel(next) # Only after collection may the host retire raw receiver ownership.
  let joined = receiveRecoveryInput(owner, input, [255'u8])
  assert owner.beginPreparation(input, joined).error == PreparationError.None
  owner.close() # Joined shutdown precedes every canonical/input alias destruction.
  assert not owner.preparationActive and not owner.rpc.chainPaused
  assert owner.stateSnapshot.error == StateStoreError.Uninitialized
  discard input.cancel(joined)
  echo "PASS application recovery preparation: genuine native lease, delayed adoption, cancellation and joined shutdown"
try:
  main() # Real execution/native errors cannot yield a successful collected source.
except:
  quit(2)
