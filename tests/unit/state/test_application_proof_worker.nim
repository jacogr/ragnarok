# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A single native proof slot retains capacity and state authority until exact collection or join.
import std/[assertions, syncio, monotimes, times]
import ../../support/proof_query_context
import ../../../src/app/proof/[query as proof_query, worker as proof_worker]
import ../../../src/chain/[genesis, provider]
import ../../../src/app/proof/network_read
import ../../../src/jamnp-s/read_stream
import ../../../src/state/proof/service as proof_service
import ../../../src/codec/bounded
proc pauseMicros(value: cuint): cint {.importc: "usleep", header: "<unistd.h>".}
  ## Yield between scalar worker polls under a fixed test deadline.
proc waitDone(worker: var StateProofWorker) =
  ## Poll no ARC query aliases while the native thread may still be using selected state.
  let start = getMonoTime()
  while worker.phase != ProofWorkerPhase.Done:
    assert (getMonoTime()-start).inSeconds < 20
    discard pauseMicros(1000)
proc main() {.raises.} =
  ## Selected/plan aliases remain alive but untouched throughout every admitted native lease.
  let selected = querySelection(queryContext())
  let service = selected.value.serviceAt(ServiceListIndex(0))
  let plan = planProofAccount(service, ElementLimit(1)).value
  var query = captureProofQuery(selected, plan, queryLimits()).value
  var worker = default(StateProofWorker)
  var foreign = default(StateProofWorker)
  assert worker.submit(query).error == ProofWorkerError.Closed
  assert query.valid
  assert worker.start() and foreign.start()
  defer: worker.close()
  defer: foreign.close()
  assert not worker.start()
  let admitted = worker.submit(query)
  assert admitted.error == ProofWorkerError.None and not query.valid
  assert worker.submit(query).error == ProofWorkerError.Busy
  assert not foreign.cancel(admitted.value)
  assert worker.collect(default(ProofWorkerTicket)).kind == ProofWorkerCompletionKind.Uninitialized
  worker.waitDone()
  assert worker.submit(query).error == ProofWorkerError.Busy
  let completed = worker.collect(admitted.value)
  assert completed.kind == ProofWorkerCompletionKind.Completed
  assert completed.value.error == ProofQueryError.None
  assert completed.value.value.valid
  assert not worker.cancel(admitted.value)
  assert worker.collect(admitted.value).kind == ProofWorkerCompletionKind.Uninitialized
  for iteration in 0..<20:
    # A completed cancellation still owns its slot until matching explicit collection.
    query = captureProofQuery(selected, plan, queryLimits()).value
    let next = worker.submit(query).value
    worker.waitDone()
    assert worker.cancel(next)
    assert worker.phase == ProofWorkerPhase.Done
    assert worker.collect(next).kind == ProofWorkerCompletionKind.Cancelled
    assert worker.phase == ProofWorkerPhase.Idle
  var payload = newSeq[byte](98)
  let identity = array[32, byte](selected.value.blockHash)
  for index in 0..<32: payload[index] = identity[index]
  for index in 63..<94: payload[index] = 255 # Full inclusive key range at the selected complete map.
  payload[96] = 16 # E4 maximum1MiB, independent of canonical state cardinality.
  let decoded = decodeReadRequest(ReadKind.State, payload)
  assert decoded.error == ReadError.None
  let readView = genesisView(selected)
  var readJob = captureNetworkRead(readView, decoded.value).value
  let expected = executeNetworkRead(readJob)
  assert expected.error == ReadError.None
  let readTicket = worker.submit(readJob)
  assert readTicket.error == ProofWorkerError.None and not readJob.valid
  assert worker.submit(readJob).error == ProofWorkerError.Busy
  assert not foreign.cancel(readTicket.value)
  worker.waitDone()
  let readCompletion = worker.collect(readTicket.value)
  assert readCompletion.kind == ProofWorkerCompletionKind.ReadCompleted
  assert readCompletion.readValue.error == ReadError.None
  assert readCompletion.readValue.value.bytes == expected.value.bytes
  assert not worker.cancel(readTicket.value)
  for iteration in 0..<20:
    # Network cancellation, like RPC cancellation, keeps Done capacity/lease until exact collection.
    readJob = captureNetworkRead(readView, decoded.value).value
    let ticket = worker.submit(readJob).value
    worker.waitDone()
    assert worker.cancel(ticket)
    assert worker.submit(readJob).error == ProofWorkerError.Busy
    assert worker.collect(ticket).kind == ProofWorkerCompletionKind.Cancelled
    assert worker.phase == ProofWorkerPhase.Idle
  readJob = captureNetworkRead(readView, decoded.value).value
  let joined = worker.submit(readJob).value
  assert worker.cancel(joined)
  worker.close() # Join before touching any canonical alias or freeing an uncancelled network result.
  assert worker.collect(joined).kind == ProofWorkerCompletionKind.Uninitialized
  assert worker.start()
  worker.close()
  worker.close()
  assert worker.start()
  query = captureProofQuery(selected, plan, queryLimits()).value
  let later = worker.submit(query).value
  assert not worker.cancel(admitted.value)
  assert worker.cancel(later)
  worker.close() # Join queued/running/completed work before releasing any selected-state alias.
  assert worker.phase == ProofWorkerPhase.Idle
  assert worker.collect(later).kind == ProofWorkerCompletionKind.Uninitialized
  echo "application-proof-worker: ok"
try:
  main()
except:
  quit(2) # A thread or genuine fixture failure must fail the native suite.
