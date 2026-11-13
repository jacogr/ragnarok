# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "jamnp_read_verification_worker_arc_release"}

## Detached trusted-root verification reuses one CPU thread, preserving cancellation/Done capacity and immutable output lifetime.

import std/[assertions, syncio, monotimes, times]
import ../../../src/app/proof/[worker, read_validation as verification_job]
import ../../../src/jamnp-s/[read_stream, read_validation, canonical_read]
import ../../../src/chain/[genesis, provider]
import ../../../src/state/range_proof
import ../../support/[jamnp_topology_fixture, jamnp_read_validation_context, arc_evidence]

proc pauseMicros(value: cuint): cint {.importc: "usleep", header: "<unistd.h>".}
  ## Yield while polling synchronized worker scalars, never any captured input/output owner.

proc waitDone(worker: var StateProofWorker) =
  ## Native generation completes under a bounded test deadline; Done still occupies the slot.
  let started = getMonoTime()
  while worker.phase != ProofWorkerPhase.Done:
    assert getMonoTime()-started < initDuration(seconds = 10)
    discard pauseMicros(1000)

proc main() {.raises.} =
  ## One actual worker handles both successful verification and discarded results without leaking ARC graphs or admitting stale tickets.
  let saved = topologyCaptured([topologyRecords(0, 6), topologyRecords(1, 9), topologyRecords(2, 12)])
  let view = genesisView(saved)
  let request = readStateRequest(saved.value.blockHash)
  let policy = readVerificationLimits()
  let wire = serveCanonicalRead(view, request).value.bytes
  let expectedRoot = array[32, byte](saved.value.stateRoot)
  let expectedCount = saved.value.keyCount
  var worker = default(StateProofWorker)
  defer: worker.close()
  assert worker.start()
  var empty = default(ReadVerificationJob)
  assert worker.submit(empty).error == ProofWorkerError.NotReady
  let missingView = default(ChainView)
  let missing = captureReadVerification(missingView, request, wire, policy)
  assert missing.error == ReadVerificationError.NoSource
  var mutableWire: seq[byte] = @[]
  for octet in wire: mutableWire.add(octet)
  var job = captureReadVerification(view, request, mutableWire, policy).value
  mutableWire[0] = mutableWire[0] xor 1 # Capture owns a fresh input copy before any worker thread reads it.
  let admitted = worker.submit(job)
  assert admitted.error == ProofWorkerError.None and not job.valid
  let foreignTicket = default(ProofWorkerTicket)
  assert worker.collect(foreignTicket).kind == ProofWorkerCompletionKind.Uninitialized
  waitDone(worker)
  assert worker.submit(empty).error == ProofWorkerError.Busy
  let completed = worker.collect(admitted.value)
  assert completed.kind == ProofWorkerCompletionKind.ReadVerified
  let checked = completed.verifiedReadValue
  assert checked.error == ReadVerificationError.None and checked.value.kind == ReadKind.State
  assert checked.value.statePage.len == expectedCount and checked.value.statePage.complete
  assert array[32, byte](checked.value.statePage.root) == expectedRoot
  assert worker.collect(admitted.value).kind == ProofWorkerCompletionKind.Uninitialized
  job = captureReadVerification(view, request, wire, policy).value
  let warm = worker.submit(job)
  waitDone(worker)
  discard worker.collect(warm.value)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    job = captureReadVerification(view, request, wire, policy).value
    let active = worker.submit(job)
    assert active.error == ProofWorkerError.None and not job.valid
    waitDone(worker)
    assert not worker.cancel(admitted.value), "stale generations never discard a later verification"
    if iteration mod 2 == 0:
      assert worker.cancel(active.value)
      assert worker.phase == ProofWorkerPhase.Done
      assert worker.submit(empty).error == ProofWorkerError.Busy
      assert worker.collect(active.value).kind == ProofWorkerCompletionKind.Cancelled
    else:
      let result = worker.collect(active.value)
      assert result.kind == ProofWorkerCompletionKind.ReadVerified
      assert result.verifiedReadValue.error == ReadVerificationError.None
  let after = getOccupiedMem()
  assertArcRelease(before, after, "read verification collection and cancellation")
  recordArcRelease("jamnp_read_verification_worker", 1000, before, after)
  job = captureReadVerification(view, request, wire, policy).value
  let closing = worker.submit(job)
  assert closing.error == ProofWorkerError.None
  worker.close()
  assert worker.phase == ProofWorkerPhase.Idle
  assert checked.value.statePage.len == expectedCount, "collected immutable evidence outlives joined worker shutdown"
  assert worker.collect(closing.value).kind == ProofWorkerCompletionKind.Uninitialized
  echo "jamnp verification worker: fresh inputs and complete verified outputs retire safely"
try:
  main()
except:
  quit 2 # Native startup failure cannot substitute for successful worker lifecycle evidence.
