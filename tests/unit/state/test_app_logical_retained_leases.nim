# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Frozen supplied plans and logical consumers remain untouched across actual cancelled Done preparation/proof leases and joined shutdown.
import std/assertions
import std/syncio
import std/monotimes
import std/times
import ../../support/app_collected_native_context
import ../../support/app_collected_supplied_context
import ../../support/app_collected_logical_context
import ../../support/state_accumulation_current_candidate_context
import ../../support/state_current_logical_proof_context
import ../../../src/app/chain as app_chain
import ../../../src/app/current_block_input as app_current_block_input
import ../../../src/app/preparation_worker as app_preparation_worker
import ../../../src/app/proof_worker as app_proof_worker
import ../../../src/app/proof_query as app_proof_query
import ../../../src/app/collected_supplied_plan as app_collected_supplied_plan
import ../../../src/app/collected_supplied_state as app_collected_supplied_state
import ../../../src/app/logical_proof as app_logical_proof
import ../../../src/state/current_logical as state_current_logical
import ../../../src/state/proof_plan as state_proof_plan
import ../../../src/codec/bounded as codec_bounded
proc pauseMicros(value: cuint): cint {.importc: "usleep", header: "<unistd.h>".}
  ## Synchronized scalar waits never copy or retire canonical graph aliases.
proc waitProof(worker: var StateProofWorker) =
  ## Done is observed without ending the native graph lease.
  let start = getMonoTime()
  while worker.phase != ProofWorkerPhase.Done:
    assert (getMonoTime()-start).inSeconds < 20, "proof worker timed out"
    discard pauseMicros(1000)
proc cycle(preparation: var PreparationWorker, proof: var StateProofWorker,
    chain: var ApplicationChain, input: var CurrentBlockInput, fixture: CollectedNativeFixture,
        plan: CollectedSuppliedPlan,
    logical: CurrentLogicalState, selection: StateProofPlan, limits: LogicalProofLimits) =
  ## Build all aliases before each enqueue, and touch retained source/plan/selection owners only after matching actual collection.
  let id = receiveCurrent(input, chain, [255'u8], [], currentCandidateLimits())
  let ticket = preparation.submit(input, id, chain).value
  preparation.waitPreparationDone()
  assert preparation.cancel(ticket)
  assert preparation.collect(default(PreparationTicket)).kind ==
      PreparationCompletionKind.Uninitialized
  assert preparation.phase == PreparationPhase.Done
  assert preparation.collect(ticket).kind == PreparationCompletionKind.Cancelled
  assert executeCollectedSupplied(chain, plan, fixture.declarations).error ==
      CollectedSuppliedError.None
  var query = captureLogicalProofQuery(logical, selection, limits).value
  let proofTicket = proof.submit(query).value
  proof.waitProof()
  assert proof.cancel(proofTicket)
  assert proof.collect(default(ProofWorkerTicket)).kind == ProofWorkerCompletionKind.Uninitialized
  assert proof.phase == ProofWorkerPhase.Done
  assert proof.collect(proofTicket).kind == ProofWorkerCompletionKind.Cancelled
  assert executeCollectedSupplied(chain, plan, fixture.declarations).error ==
      CollectedSuppliedError.None
proc main() {.raises.} =
  ## Real reusable native workers share canonical graphs with persistent frozen plans and complete logical owners under plain ARC.
  let fixture = collectedNativeFixture()
  let plan = suppliedNativePlan(fixture)
  let logical = suppliedNativeState(fixture)
  let selection = logicalProofPlan()
  let limits = LogicalProofLimits(blocks: ElementLimit(16), viewBytes: ByteLimit(33554432),
      query: logicalProofLimits())
  var chain = fixture.chain
  var input = default(CurrentBlockInput)
  var preparation = default(PreparationWorker)
  var proof = default(StateProofWorker)
  assert preparation.start() and proof.start()
  defer: preparation.close()
  defer: proof.close()
  # Thread-local occupied bytes include delayed foreign frees; this native-worker workload checks
  # actual lease/alias reuse through collection and join, without claiming whole-process ARC counts.
  for i in 0..<1000:
    cycle(preparation, proof, chain, input, fixture, plan, logical, selection, limits)
  let id = receiveCurrent(input, chain, [255'u8], [], currentCandidateLimits())
  discard preparation.submit(input, id, chain).value
  preparation.close() # Actual join retires every queued/running/Done activation before source access resumes.
  assert executeCollectedSupplied(chain, plan, fixture.declarations).error ==
      CollectedSuppliedError.None
  var query = captureLogicalProofQuery(logical, selection, limits).value
  discard proof.submit(query).value
  proof.close()
  assert executeCollectedSupplied(chain, plan, fixture.declarations).error ==
      CollectedSuppliedError.None
  echo "application-logical-retained-leases: ok"
try:
  main()
except:
  quit(2) # Cancel or Done alone cannot grant safe source capture, alias retirement or frozen-plan execution.
