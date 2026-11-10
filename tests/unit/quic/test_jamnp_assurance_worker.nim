# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "jamnp_assurance_worker_arc_release"}

## Actual reusable-worker namespace jobs keep native owners frozen through exact collection and cooperate with Running cancellation and joined close.

import std/[assertions, syncio, dirs, paths, strutils, monotimes, times]
import ../../../src/app/proof/[worker, assurance_storage]
import ../../../src/jamnp-s/[assurance_store, assurance_record, availability_proof]
import ../../../src/codec/bounded
import ../../../src/state/erasure/words
import ../../../src/lib/atomic/file as atomic_file
import ../../support/[pvm_computed_report, storage_io, arc_evidence]

proc pauseMicros(value: cuint): cint {.importc: "usleep", header: "<unistd.h>".}
  ## Yield only between mutex-protected scalar worker observations under a fixed test deadline.

proc limits(): AssuranceStoreLimits =
  ## A real full-population archive has explicit disk, scan and per-record work ceilings; none comes from a native default.
  AssuranceStoreLimits(entries: ElementLimit(1023), scanEntries: ElementLimit(2000),
      bytes: ByteLimit(64000000),
    record: AssuranceRecordLimits(bytes: ByteLimit(16000000),
        verification: AvailabilityMerkleLimits(
      bytes: ByteLimit(64000000), hashes: ElementLimit(10000), hashBytes: ByteLimit(64000000))))

proc chain(): AssuranceChainId =
  ## Complete chain identity is selected independently of an incoming record.
  var bytes = default(array[32, byte])
  bytes[0] = 41
  AssuranceChainId(bytes)

proc clean(folder: string) =
  ## Only process-specific private fixture directories are removed after all native borrowers have joined or collected.
  try: removeDir(path(folder))
  except: assert false, "worker fixture cleanup"

proc staged(owner: var AssuranceStore, folder: string,
    mode: AssuranceStorageMode): AssuranceStorageJob =
  ## The temporary admission/result and path aliases retire before native submission starts any non-atomic ARC borrow.
  let captured = captureAssuranceStorage(owner, folder, chain(), limits(), mode)
  assert captured.error == AssuranceStorageJobError.None, "complete job capture"
  captured.value

proc waitDone(worker: var StateProofWorker) =
  ## No job, path, outcome or mutable store alias is touched while the worker retains its lease.
  let deadline = getMonoTime()+initDuration(seconds = 20)
  while worker.phase != ProofWorkerPhase.Done:
    assert getMonoTime() < deadline, "assurance worker completion deadline"
    discard pauseMicros(100)

proc waitRunning(worker: var StateProofWorker) =
  ## Byte-limited real reads make the admitted archive scan long enough to observe actual execution before requesting cancellation.
  let deadline = getMonoTime()+initDuration(seconds = 20)
  while worker.phase == ProofWorkerPhase.Queued:
    assert getMonoTime() < deadline, "assurance worker start deadline"
    discard pauseMicros(100)
  assert worker.phase == ProofWorkerPhase.Running, "observe Running before cancellation/join"

proc create(worker: var StateProofWorker, owner: var AssuranceStore, folder: string) =
  ## Only exact uncancelled collection grants access to the namespace mutation performed on the native thread.
  var job = staged(owner, folder, AssuranceStorageMode.Create)
  let admitted = worker.submit(job)
  assert admitted.error == ProofWorkerError.None and not job.valid, "move one closed job into bounded slot"
  assert worker.submit(job).error == ProofWorkerError.Busy, "occupied capacity refuses another job"
  worker.waitDone()
  assert worker.collect(default(ProofWorkerTicket)).kind == ProofWorkerCompletionKind.Uninitialized, "foreign collection cannot release mutable borrow"
  let completed = worker.collect(admitted.value)
  assert completed.kind == ProofWorkerCompletionKind.AssuranceCompleted, "exact assurance completion kind"
  assert completed.assuranceStorageValue.error == AssuranceStoreError.None, "actual managed creation succeeded"
  assert owner.opened and owner.len == 0, "observe native owner only after collection"

proc fill(folder: string) =
  ## All 1023 per-shard records come from genuine execution and proofs; fixture construction ends before asynchronous store borrowing.
  let source = computedAvailabilityAtCore(0, 1, 1023)
  let spec = source.availabilityInfo.value.specifier
  var root = ""
  for octet in spec.erasureRoot.bytes: root.add(toHex(int(octet), 2).toLowerAscii())
  for index in 0..<1023:
    # Offline fixture publication holds no competing store lock; each record remains independently correct under full restore.
    let request = AvailabilityRequest(kind: AvailabilityTransferKind.Distribution,
      root: spec.erasureRoot,
      shard: ErasureShardIndex(index))
    let prepared = prepareAvailabilityTransfer(source, request, limits().record.verification).value
    let verified = verifyAvailabilityTransfer(spec, request, prepared.bundleShard,
      prepared.segmentShards, prepared.justification, limits().record.verification)
    assert verified.error == AvailabilityTransferError.None, "genuine full-population distribution"
    let record = prepareAssuranceRecord(verified.value, chain(), AssuranceTime(1000), limits().record).value
    let encoded = encodeAssuranceRecord(record, limits().record).value
    let name = folder & "/" & root.substr(0, 1) & "/" & root & "-" & toHex(index, 4).toLowerAscii() & ".shard"
    assert replaceAtomicFile(name, encoded, limits().record.bytes) == AtomicFileError.None, "actual offline record publication"

proc active(worker: var StateProofWorker, owner: var AssuranceStore, folder: string,
    joining: bool) =
  ## Cancellation must interrupt real bounded header reads; a full uninterruptible scan would read all 1023 headers and leave an open owner.
  resetIo()
  limitReads(1)
  var job = staged(owner, folder, AssuranceStorageMode.Open)
  let ticket = worker.submit(job).value
  worker.waitRunning()
  if joining:
    # Close releases the worker mutex before join, so the executing scan can lock it and observe stopping.
    worker.close()
    assert worker.phase == ProofWorkerPhase.Idle, "joined close retires native execution"
  else:
    assert worker.cancel(ticket), "exact Running cancellation"
    worker.waitDone()
    assert worker.collect(default(ProofWorkerTicket)).kind ==
        ProofWorkerCompletionKind.Uninitialized, "wrong ticket preserves Done ownership"
    assert worker.collect(ticket).kind == ProofWorkerCompletionKind.Cancelled, "cancelled job exposes no setup result"
  let reads = ioCalls(readIo) # The native IO observer is quiescent only after exact collection or joined close.
  assert reads < 1023'u64*206, "cancellation stops before a whole archive scan"
  assert not owner.opened, "cooperative scan unwinds its namespace lease before Done/join"
  resetIo()
  assert owner.close().error == AssuranceStoreError.None, "idempotent cancelled-owner cleanup"

proc cycle(worker: var StateProofWorker, owner: var AssuranceStore, missing: string, index: int) =
  ## A moved private path and completed failure retire before the next CPU job; Done cancellation retains capacity until matching collection.
  var job = staged(owner, missing, AssuranceStorageMode.Open)
  let ticket = worker.submit(job).value
  worker.waitDone()
  assert worker.collect(default(ProofWorkerTicket)).kind == ProofWorkerCompletionKind.Uninitialized, "ARC foreign ticket cannot collect"
  if index mod 2 == 0: assert worker.cancel(ticket), "ARC Done cancellation"
  let completed = worker.collect(ticket)
  if index mod 2 == 0:
    assert completed.kind == ProofWorkerCompletionKind.Cancelled, "ARC cancellation has no result payload"
  else:
    assert completed.kind == ProofWorkerCompletionKind.AssuranceCompleted, "ARC closed job completed"
    assert completed.assuranceStorageValue.error == AssuranceStoreError.InvalidNamespace, "missing directory preserves actual I/O refusal"
  assert worker.phase == ProofWorkerPhase.Idle and not owner.opened, "ARC exact retirement"

proc main() {.raises.} =
  ## Real Running and Done cases distinguish cooperative worker cancellation from merely hiding an already completed result.
  let folder = "assurance-worker-" & $storageProcessId()
  clean(folder)
  defer: clean(folder)
  var owner = default(AssuranceStore)
  defer: discard owner.close()
  var worker = default(StateProofWorker)
  defer: worker.close() # Worker joins before its borrowed native owner may close.
  var job = staged(owner, folder, AssuranceStorageMode.Create)
  assert worker.submit(job).error == ProofWorkerError.Closed and job.valid, "closed submission keeps caller ownership"
  job = default(AssuranceStorageJob)
  assert worker.start(), "native worker start"
  create(worker, owner, folder)
  assert owner.close().error == AssuranceStoreError.None, "close before offline full archive construction"
  fill(folder)
  var other = default(AssuranceStore)
  defer: discard other.close()
  var foreign = default(StateProofWorker)
  defer: foreign.close() # Foreign native input borrowing retires before the other store may close.
  assert foreign.start(), "foreign namespace worker"
  var invalid = staged(other, "missing-assurance-worker-foreign-directory",
      AssuranceStorageMode.Open)
  let foreignTicket = foreign.submit(invalid).value
  foreign.waitDone()
  let missing = "missing-assurance-worker-" & repeat("x", 96)
  resetIo()
  limitReads(1)
  var opening = staged(owner, folder, AssuranceStorageMode.Open)
  let pending = worker.submit(opening).value
  worker.waitRunning()
  assert not foreign.cancel(pending), "foreign cancellation cannot affect a live store lease"
  assert worker.collect(foreignTicket).kind == ProofWorkerCompletionKind.Uninitialized, "foreign ticket never ends this mutable lease"
  assert worker.cancel(pending), "cancel actual scan"
  worker.waitDone()
  assert worker.collect(pending).kind == ProofWorkerCompletionKind.Cancelled, "exact Running scan cancellation"
  assert ioCalls(readIo) < 1023'u64*206 and not owner.opened, "cancelled existing namespace remains closed without reading the whole archive"
  resetIo()
  assert foreign.collect(foreignTicket).kind == ProofWorkerCompletionKind.AssuranceCompleted, "foreign failure retires independently"
  limitReads(1) # An uncancelled scan must exercise the same observed one-byte read loop.
  opening = staged(owner, folder, AssuranceStorageMode.Open)
  let done = worker.submit(opening).value
  worker.waitDone()
  assert worker.cancel(done), "Done cancellation remains supported"
  assert worker.collect(done).kind == ProofWorkerCompletionKind.Cancelled, "Done result hidden"
  assert owner.opened, "cancellation cannot undo completed filesystem ownership; caller retires only after collection"
  assert ioCalls(readIo) >= 1023'u64*206, "complete scan observes every fixed header byte under short reads"
  resetIo()
  assert owner.close().error == AssuranceStoreError.None, "retire completed cancelled owner"
  active(worker, owner, folder, false)
  active(worker, owner, folder, true)
  assert worker.start(), "reopen worker after joined cancellation"
  cycle(worker, owner, missing, 1)
  let before = getOccupiedMem()
  for index in 0..<1000:
    # Native dispatch, private path ARC and both failure/completed-cancellation outcomes release every job input.
    cycle(worker, owner, missing, index)
  let after = getOccupiedMem()
  assert before == after, "assurance storage worker ARC release"
  recordArcRelease("jamnp_assurance_worker", 1000, before, after)
  echo "JAMNP-S assurance worker passed"
try:
  main()
except:
  quit(2)
