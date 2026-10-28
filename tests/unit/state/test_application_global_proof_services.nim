# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Global plans execute through the same bounded native slot and exclusive Services lease.
import std/[assertions, syncio, monotimes, times]
import ../../support/proof_query_context
import ../../../src/app/[services, options, proof_query, proof_worker]
import ../../../src/chain/[genesis, provider]
import ../../../src/state/[proof_plan, planned_proof, proof_view, trie_proof]
import ../../../src/codec/[bounded, state_layout, state_trie]
import ../../../src/rpc/server
proc pauseMicros(value: cuint): cint {.importc: "usleep", header: "<unistd.h>".}
  ## Yield only between bounded scalar worker polls.
proc identity(owner: Services): tuple[hash: BlockHash, root: StateRoot] =
  ## Retire every temporary canonical ARC alias before the caller can queue proof work.
  let selected = owner.chainView.bestBlock.value
  (selected.blockHash, selected.stateRoot)
proc main() {.raises.} =
  ## Independently verify generic output and preserve legacy error separation.
  let context = queryContext()
  let selected = querySelection(context)
  let plan = captureStateProofPlan([chapterKey(StateChapter(11)), chapterKey(StateChapter(6))],
      ElementLimit(2)).value
  let limits = queryLimits()
  let captured = captureProofQuery(selected, plan, limits)
  assert captured.error == ProofQueryError.None
  let response = executeProofQuery(captured.value).value
  let received = decodePlannedProofs(response.bytes(limits.wireBytes).value, plan,
    selected.value.stateRoot, limits.view, limits.proof, limits.aggregate, limits.wireBytes)
  assert received.error == ProofViewError.None and received.value.readProofTime.error ==
      ProofViewError.None
  var short = limits
  short.wireBytes = ByteLimit(98)
  let refused = executeProofQuery(captureProofQuery(selected, plan, short).value)
  assert refused.error == ProofQueryError.ViewFailure and refused.viewError ==
      ProofViewError.LimitExceeded
  short = limits
  short.map.perValue = ByteLimit(0)
  let generation = executeProofQuery(captureProofQuery(selected, plan, short).value)
  assert generation.error == ProofQueryError.ProofFailure and generation.proofError ==
      StateProofError.LimitExceeded
  assert captureProofQuery(selected, default(StateProofPlan), limits).error ==
      ProofQueryError.InvalidPlan
  const path = "application-global-proof-chain.json"
  writeFile(path, context.text)
  var options = default(Options)
  assert parseCanonicalOptions(@["server", "--chain", path, "--with-state", "--state-writes", "1000",
    "--state-write-bytes", "1000000"], options)
  var owner = default(Services)
  assert owner.start(options, "global proof")
  defer: owner.close()
  let fixed = identity(owner)
  let admitted = owner.beginStateProof(fixed.hash, plan, limits)
  assert admitted.error == StateProofAdmissionError.None and owner.stateProofActive and
      owner.rpc.chainPaused
  let start = getMonoTime()
  while owner.stateProofPhase != ProofWorkerPhase.Done:
    assert (getMonoTime()-start).inSeconds < 20
    owner.tick(0)
    discard pauseMicros(1000)
  let completion = owner.collectStateProof(admitted.value)
  assert completion.kind == ProofWorkerCompletionKind.Completed and not owner.rpc.chainPaused
  let completed = completion.value.value
  let independent = decodePlannedProofs(completed.bytes(limits.wireBytes).value, plan, fixed.root,
    limits.view, limits.proof, limits.aggregate, limits.wireBytes)
  assert independent.error == ProofViewError.None and independent.value.readProofTime.error ==
      ProofViewError.None
  assert not owner.cancelStateProof(admitted.value)
  let closing = owner.beginStateProof(fixed.hash, plan, limits).value
  assert owner.cancelStateProof(closing)
  owner.close()
  assert not owner.stateProofActive and not owner.rpc.chainPaused
  assert owner.collectStateProof(closing).kind == ProofWorkerCompletionKind.Uninitialized
  echo "application-global-proof-services: ok"
try:
  main()
except:
  quit(2) # Genuine fixture, startup or execution errors must fail.
