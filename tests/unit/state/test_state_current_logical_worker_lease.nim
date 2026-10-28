# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Frozen logical plans sharing the actual proof worker's canonical graph remain untouched until exact collection or joined shutdown.
# @@Verification={"arc":"state_current_logical_worker_lease_arc_release"}
import std/assertions
import std/envvars
import std/syncio
import std/monotimes
import std/times
import ../../support/state_current_repeated_logical_context
import ../../support/state_current_namespace_refresh_context
import ../../support/state_current_logical_proof_context
import ../../support/testing_arc_evidence
import ../../../src/state/current_logical_refresh as state_current_logical_refresh
import ../../../src/state/current_logical as state_current_logical
import ../../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../../src/state/proof_plan as state_proof_plan
import ../../../src/state/planned_proof as state_planned_proof
import ../../../src/state/proof_view as state_proof_view
import ../../../src/state/proof_global as state_proof_global
import ../../../src/state/trie_proof as state_trie_proof
import ../../../src/state/store as state_store
import ../../../src/app/proof_query as app_proof_query
import ../../../src/app/proof_worker as app_proof_worker
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/codec/state_layout as codec_state_layout
proc pauseMicros(value: cuint): cint {.importc: "usleep", header: "<unistd.h>".}
  ## Scalar-only deadline polling never retains, drops or copies a canonical alias while the worker leases it.
proc waitDone(worker: var StateProofWorker) =
  ## Done still owns the graph; only a matching collection or joined close below reopens host access.
  let start = getMonoTime()
  while worker.phase != ProofWorkerPhase.Done:
    assert (getMonoTime()-start).inSeconds < 20
    discard pauseMicros(1000)
proc cancelledCycle(worker: var StateProofWorker, plan: CurrentLogicalRefreshPlan,
    selection: StateProofPlan, stale: ProofWorkerTicket) =
  ## Construct every shared graph alias before submission and keep all such owners completely untouched until actual collection.
  let logical = executeCurrentLogicalRefresh(plan).value
  var query = logicalProofQuery(logical, selection)
  let ticket = worker.submit(query).value
  worker.waitDone()
  assert worker.cancel(ticket)
  assert worker.phase == ProofWorkerPhase.Done
  assert worker.collect(stale).kind == ProofWorkerCompletionKind.Uninitialized
  assert worker.phase == ProofWorkerPhase.Done
  assert worker.collect(ticket).kind == ProofWorkerCompletionKind.Cancelled
  assert worker.phase == ProofWorkerPhase.Idle
  assert selection.len == 1 # Keep the detached semantic plan live and untouched across the lease as well.
  let refreshed = executeCurrentLogicalRefresh(plan).value
  assert sameStateSnapshot(logical.logicalProducer.currentUpdateState,
      refreshed.logicalProducer.currentUpdateState)
proc main() {.raises.} =
  ## Genuine source/plan construction and independent root expectations finish before starting the fixed-address worker lease.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i])
  let fixture = repeatedLogicalFixture(decodeOwnedReport(bytes, 2).value)
  let plan = namespaceRefreshStages(fixture.logical, fixture.next).complete
  let logical = executeCurrentLogicalRefresh(plan).value
  let root = logical.logicalProducer.currentUpdateState.commitment.root
  let selection = captureStateProofPlan([chapterKey(StateChapter(11))], ElementLimit(1)).value
  var query = logicalProofQuery(logical, selection)
  var worker = default(StateProofWorker)
  assert worker.start()
  defer: worker.close() # Join precedes destruction of every canonical fixture/plan/logical/query owner declared above the worker.
  let first = worker.submit(query).value
  worker.waitDone()
  assert worker.collect(default(ProofWorkerTicket)).kind == ProofWorkerCompletionKind.Uninitialized
  assert worker.phase == ProofWorkerPhase.Done
  let completion = worker.collect(first)
  assert completion.kind == ProofWorkerCompletionKind.Completed and completion.value.error ==
      ProofQueryError.None
  let limits = logicalProofLimits()
  let view = decodePlannedProofs(completion.value.value.bytes(limits.wireBytes).value, selection,
      root, limits.view, limits.proof, limits.aggregate, limits.wireBytes).value
  assert uint32(view.readGlobalTime.value) == 3
  for i in 0..<25: cancelledCycle(worker, plan, selection, first)
  let before = getOccupiedMem()
  for i in 0..<1000: cancelledCycle(worker, plan, selection, first)
  let finalBytes = getOccupiedMem()
  assert before == finalBytes and worker.phase == ProofWorkerPhase.Idle
  recordArcRelease("state_current_logical_worker_lease", 1000, before, finalBytes)
  query = logicalProofQuery(logical, selection)
  let joining = worker.submit(query).value
  assert worker.cancel(joining)
  worker.close() # Join is the only release in this uncollected cancelled case; no canonical getters or destructors precede it.
  assert worker.collect(joining).kind == ProofWorkerCompletionKind.Uninitialized
  assert executeCurrentLogicalRefresh(plan).error == LogicalRefreshError.None
  echo "state-current-logical-worker-lease: ok"
try:
  main()
except:
  quit(2) # Worker lease violations cannot be converted into successful logical/proof authority.
