# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict runtime extraction, live-owner and managed selected-state access failures.
import std/[assertions, cmdline, syncio]
import ../../src/app/[services, options, proof_query, proof_worker]
import ../../src/chain/[genesis, provider]
import ../../src/codec/[bounded, report_owned]
import ../../src/state/proof_service
import ../support/[application_candidate_context, proof_query_context]
proc main() {.raises.} =
  ## Every invalid case must fail at its exact guard; the control closes actual native work.
  let mode = paramStr(1)
  case mode
  of "query-view-reason":
    let guarded = default(ProofQueryResult[ProofResponse])
    discard guarded.viewError # A default response cannot expose a generic view refusal reason.
  of "admission":
    let guarded = default(StateProofAdmission)
    discard guarded.value
  of "query-reason":
    let guarded = default(StateProofAdmission)
    discard guarded.queryError
  of "worker-reason":
    let guarded = default(StateProofAdmission)
    discard guarded.workerError
  of "worker-admission":
    let guarded = default(ProofWorkerAdmission)
    discard guarded.value
  of "worker-completion":
    let guarded = default(ProofWorkerCompletion)
    discard guarded.value
  of "unclosed-worker":
    var worker = default(StateProofWorker)
    assert worker.start()
    return # The live owner must fail destruction before thread resources can be abandoned.
  of "move-live-worker":
    var worker = default(StateProofWorker)
    assert worker.start()
    var relocated = move(worker)
    relocated.close() # A live address change must fail before this cleanup can run.
    return
  else: discard # Managed graph probes use the independently pinned complete-state fixture below.
  let raw = readFile("tests/fixtures/state-report.bin")
  var wire = newSeq[byte](raw.len)
  for index, octet in raw: wire[index] = byte(octet)
  let context = fixture(decodeOwnedReport(wire, 2).value)
  const path = "build/proof-contract-chain.json"
  writeFile(path, context.text)
  var options = default(Options)
  assert parseOptions(@["server", "--chain", path, "--with-state", "--state-writes", "1000",
    "--state-write-bytes", "1000000"], options)
  var owner = default(Services)
  assert owner.start(options, "proof contract")
  let selected = owner.chainView.bestBlock.value
  let plan = planProofAccount(selected.serviceAt(ServiceListIndex(0)), ElementLimit(1)).value
  let admitted = owner.beginStateProof(selected.blockHash, plan, queryLimits())
  assert admitted.error == StateProofAdmissionError.None
  case mode
  of "view": discard owner.chainView # No selected-history ARC alias may escape the lease.
  of "snapshot": discard owner.stateSnapshot # No complete-state ARC alias may escape the lease.
  of "checkpoint": discard owner.checkpointIdentity # Even fixed context capture first touches canonical state.
  of "serialize": discard owner.prepareCheckpoint(ByteLimit(
      1000000)) # Serialization cannot traverse leased state.
  of "services-destroy": return # The composite destructor must reject a still-started proof child first.
  else:
    owner.close() # Positive joined shutdown releases RPC and canonical state only after execution retires.
    assert not owner.stateProofActive
  owner.close() # Unexpected guard success exits normally and fails the strict negative verdict.
try:
  main()
except:
  quit(2) # Ordinary fixture/startup errors never satisfy an AssertionDefect expectation.
