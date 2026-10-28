# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real selected-state proof jobs hold the Services graph/RPC gate through cancellation and Done.
import std/[assertions, syncio, monotimes, times]
import ../../../src/app/[services, options, proof_query, proof_worker]
import ../../../src/chain/[genesis, provider]
import ../../../src/state/proof_service
import ../../../src/codec/bounded
import ../../../src/rpc/server
import ../../support/proof_query_context
proc pauseMicros(value: cuint): cint {.importc: "usleep", header: "<unistd.h>".}
  ## Yield to one native worker while the host polls only synchronized scalars.
proc waitDone(owner: var Services) =
  ## Dispatcher ticks may service UI but cannot create canonical/RPC contexts during the lease.
  let start = getMonoTime()
  while owner.stateProofPhase != ProofWorkerPhase.Done:
    assert (getMonoTime()-start).inSeconds < 20
    owner.tick(0)
    discard pauseMicros(1000)
proc main() {.raises.} =
  ## Keep all externally retained canonical aliases alive and untouched until collect/join.
  let context = queryContext()
  let path = "application-proof-services-chain.json"
  writeFile(path, context.text)
  var options = default(Options)
  assert parseCanonicalOptions(@["server", "--chain", path, "--with-state", "--state-writes", "1000",
    "--state-write-bytes", "1000000"], options)
  var owner = default(Services)
  let limits = queryLimits()
  let missing = default(ServiceProofPlan)
  let unknown = default(BlockHash)
  assert owner.beginStateProof(unknown, missing, limits).error == StateProofAdmissionError.Closed
  assert owner.start(options, "proof services")
  defer: owner.close()
  let selected = owner.chainView.bestBlock.value
  let hash = selected.blockHash
  let root = selected.stateRoot
  let plan = planProofAccount(selected.serviceAt(ServiceListIndex(0)), ElementLimit(1)).value
  assert owner.stateProofAvailable
  let invalid = owner.beginStateProof(unknown, plan, limits)
  assert invalid.error == StateProofAdmissionError.QueryFailure
  assert invalid.queryError == ProofQueryError.InvalidSelection
  assert not owner.stateProofActive and not owner.rpc.chainPaused
  let paused = owner.rpc.pauseChain()
  assert owner.beginStateProof(hash, plan, limits).error == StateProofAdmissionError.Busy
  assert owner.rpc.resumeChain(paused)
  let admitted = owner.beginStateProof(hash, plan, limits)
  assert admitted.error == StateProofAdmissionError.None
  assert owner.stateProofActive and owner.rpc.chainPaused and not owner.preparationAvailable
  assert owner.beginStateProof(hash, plan, limits).error == StateProofAdmissionError.Busy
  owner.stopPreparation() # Another worker's cleanup must not release the proof lease.
  assert owner.stateProofActive and owner.rpc.chainPaused
  assert not owner.rpc.resumeChain(paused)
  assert owner.collectStateProof(default(ProofWorkerTicket)).kind ==
      ProofWorkerCompletionKind.Uninitialized
  owner.waitDone()
  assert owner.stateProofActive and not owner.stateProofAvailable
  let completed = owner.collectStateProof(admitted.value)
  assert completed.kind == ProofWorkerCompletionKind.Completed
  assert completed.value.error == ProofQueryError.None
  let response = completed.value.value
  assert array[32, byte](response.blockHash) == array[32, byte](hash)
  assert array[32, byte](response.stateRoot) == array[32, byte](root)
  assert not owner.stateProofActive and not owner.rpc.chainPaused and owner.preparationAvailable
  assert not owner.cancelStateProof(admitted.value)
  let later = owner.beginStateProof(hash, plan, limits).value
  assert owner.cancelStateProof(later)
  owner.waitDone()
  assert owner.collectStateProof(later).kind == ProofWorkerCompletionKind.Cancelled
  let closing = owner.beginStateProof(hash, plan, limits).value
  owner.close() # Join active computation before canonical and RPC owners retire.
  assert not owner.stateProofActive and not owner.rpc.chainPaused
  assert owner.collectStateProof(closing).kind == ProofWorkerCompletionKind.Uninitialized
  assert response.bytes(ByteLimit(20000000)).error == ProofQueryError.None
  echo "application-proof-services: ok"
try:
  main()
except:
  quit(2) # Fixture, startup or native execution failures must fail this suite.
