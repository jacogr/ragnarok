# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Frozen supplied plans and logical consumers remain untouched across actual cancelled Done preparation/proof leases and joined shutdown.
import std/[assertions, syncio, monotimes, times]
import ../../support/[collected_native_context, collected_supplied_context,
    collected_logical_context,

accumulation_current_candidate_context, current_logical_proof_context]
import ../../../src/app/[chain, current_block_input, preparation_worker, proof_worker, proof_query,
    collected_supplied_plan, collected_supplied_state, logical_proof]
import ../../../src/state/[current_logical, proof_plan]
import ../../../src/codec/bounded
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
