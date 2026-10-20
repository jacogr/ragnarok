# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## One fixed-address native I/O worker consumes sole-owner prepared bytes without borrowing canonical state.
## One host thread serializes stage/begin/collect/close; native work and shutdown never run in network callbacks.

import std/[locks, rawthreads]
import ./[checkpoint_bank, checkpoint_head, checkpoint_transfer, checkpoint]
import ../codec/bounded

type
  CheckpointWorkerPhase* {.pure.} = enum ## Done retains capacity until explicit collection; Staged has not begun I/O.
    Idle, Staged, Running, Executing, Done
  CheckpointOperation* {.pure.} = enum ## Both operations share the bank's typed durable-publication contract.
    Bootstrap, Advance
  CheckpointWorkerError* {.pure.} = enum ## Refused admission never consumes the caller's sole prepared owner.
    Uninitialized, None, Closed, Busy, NotReady, InvalidHead, LimitExceeded, Exhausted
  WorkerIdentity = ref object ## Host-only namespace is never accessed by the native I/O thread.
    marker: uint8
  CheckpointTicket* = object ## Identity plus nonwrapping local generation prevent foreign/stale completion access.
    owner: nil WorkerIdentity
    generation: uint64
  CheckpointAdmission* = object ## Only admitted staged work exposes an ownership ticket.
    case status: CheckpointWorkerError
    of None:
      ticket: CheckpointTicket
    else:
      discard                   # Failed/default admission retains no lease authority.
  CheckpointCompletionKind* {.pure.} = enum ## Completed means the operation returned; its bank outcome may still be a failure.
    Uninitialized, Completed, Cancelled, Interrupted
  CheckpointCompletion* = object ## Only completed work exposes its exact typed bank outcome.
    case status: CheckpointCompletionKind
    of Completed:
      outcome: CheckpointBankResult[CheckpointHead]
    else:
      discard                    # No default/cancelled publication receipt can be adopted.
  CheckpointShutdown* = object ## Joining preserves any actual operation receipt independently of native retirement errors.
    finished: CheckpointCompletion
    retirement: CheckpointBankError
  CheckpointWorker* = object ## Keep this noncopyable owner at one address from start until joined close.
    lock: Lock
    changed: Cond
    thread: RawThread
    started, stopping, cancelled: bool
    phase: CheckpointWorkerPhase
    next: uint64
    identity: nil WorkerIdentity
    bank: CheckpointBank
    prepared: PreparedCheckpoint
    operation: CheckpointOperation
    expected: CheckpointHead
    limit: ByteLimit
    outcome: CheckpointBankResult[CheckpointHead]

proc `=wasMoved`*(worker: var CheckpointWorker) {.nodestroy, inline,
    requires: not worker.started.} =
  ## Only inactive owners may relocate; a running thread retains the exact original worker address until joined close.
  `=wasMoved`(worker.prepared)
  `=wasMoved`(worker.bank)
  `=wasMoved`(worker.identity)
proc `=copy`*(destination: var CheckpointWorker, source: CheckpointWorker) {.error.}
  ## Thread synchronization and the private bank's lock have one composite owner.
proc `=dup`*(source: CheckpointWorker): CheckpointWorker {.error.}
  ## Actual ARC lowering must independently reject composite worker duplication.
proc requireClosed(worker: CheckpointWorker) {.requires: not worker.started.} =
  ## A live native thread cannot outlive its stable owner address or private bank.
  discard
proc `=destroy`*(worker: CheckpointWorker) =
  ## Explicit joined close ends every worker borrow before host-owned buffers and bank paths retire.
  requireClosed(worker)
  `=destroy`(worker.prepared)
  `=destroy`(worker.bank)
  `=destroy`(worker.identity)
func error*(admission: CheckpointAdmission): CheckpointWorkerError =
  ## Observe refusal without granting access to an unowned staged slot.
  admission.status
func value*(admission: CheckpointAdmission): CheckpointTicket {.inline,
    requires: admission.status == CheckpointWorkerError.None.} =
  ## Only successful admission grants the host a ticket.
  admission.ticket
func kind*(completion: CheckpointCompletion): CheckpointCompletionKind =
  ## Default and cancelled work remain distinct from an actual typed bank outcome.
  completion.status
func value*(completion: CheckpointCompletion): CheckpointBankResult[CheckpointHead] {.inline,
    requires: completion.status == CheckpointCompletionKind.Completed.} =
  ## Callers must also check the returned bank outcome before extracting a committed head.
  completion.outcome
func completion*(shutdown: CheckpointShutdown): CheckpointCompletion =
  ## Preserve a possibly committed operation even when native retirement separately fails.
  shutdown.finished
func retirementError*(shutdown: CheckpointShutdown): CheckpointBankError =
  ## None confirms actual idempotent/native close; default shutdown reports Uninitialized.
  shutdown.retirement
proc execute(worker: ptr CheckpointWorker) =
  ## Entire filesystem/metadata activations retire before the thread publishes Done.
  case worker.operation
  of CheckpointOperation.Bootstrap:
    worker.outcome = worker.bank.initialize(worker.prepared,
        worker.limit) # The source complete-map graph is absent from this worker.
  of CheckpointOperation.Advance:
    worker.outcome = worker.bank.advance(worker.expected, worker.prepared,
        worker.limit) # The bank rechecks/resynchronizes the actual visible selector.
proc run(raw: pointer) =
  ## A condition-driven single thread performs only ordered bank I/O, with no canonical adoption or dispatcher callbacks.
  let worker = cast[ptr CheckpointWorker](raw)
  acquire(worker.lock)
  while true:
    while worker.phase != CheckpointWorkerPhase.Running and not worker.stopping:
      wait(worker.changed, worker.lock) # Recheck after spurious wakeups without polling or consuming staged-only work.
    if worker.stopping:
      release(worker.lock)
      return # Joined close can distinguish an unstarted request from Done after the final activation.
    worker.phase = CheckpointWorkerPhase.Executing # Distinguish native entry from dispatched work skipped by shutdown.
    release(worker.lock)
    execute(worker)
    acquire(worker.lock)
    worker.phase = CheckpointWorkerPhase.Done # No stack-local buffer/path alias remains active when the host can collect.
proc start*(worker: var CheckpointWorker, prefix: string): CheckpointBankError {.raises.} =
  ## Startup acquires the private cooperative bank before starting one thread at the owner's final address.
  if worker.started: return CheckpointBankError.Busy # Repeated startup cannot replace live synchronization state.
  let opened = worker.bank.openCheckpointBank(prefix)
  if opened != CheckpointBankError.None: return opened # No thread or condition exists after failed path/lock admission.
  initLock(worker.lock)
  initCond(worker.changed)
  worker.stopping = false
  worker.cancelled = false
  worker.phase = CheckpointWorkerPhase.Idle
  worker.next = 0
  worker.operation = CheckpointOperation.Bootstrap
  worker.expected = default(CheckpointHead)
  worker.limit = ByteLimit(0)
  worker.outcome = default(CheckpointBankResult[CheckpointHead])
  worker.prepared = default(PreparedCheckpoint)
  try:
    worker.thread.create(run, addr worker)
  except:
    deinitCond(worker.changed)
    deinitLock(worker.lock)
    discard worker.bank.close()
    raise # Thread creation failure cannot leave an active bank or initialized synchronization resource.
  worker.identity = WorkerIdentity(marker: 1) # Fresh host-only identity makes restart generations unambiguous.
  worker.started = true
  CheckpointBankError.None
proc phase*(worker: var CheckpointWorker): CheckpointWorkerPhase =
  ## Host polling reads scalar state only; it never accesses the worker's exclusive buffer or native bank paths.
  if not worker.started: return CheckpointWorkerPhase.Idle
  acquire(worker.lock)
  result = worker.phase
  release(worker.lock)
proc stage*(worker: var CheckpointWorker, prepared: var PreparedCheckpoint,
    operation: CheckpointOperation, expected: CheckpointHead,
        limit: ByteLimit): CheckpointAdmission =
  ## Consume the caller's sole buffer only after every bounded admission check; staging itself performs no disk I/O.
  if not worker.started: return CheckpointAdmission(status: CheckpointWorkerError.Closed)
  acquire(worker.lock)
  defer: release(worker.lock)
  if worker.phase != CheckpointWorkerPhase.Idle: return CheckpointAdmission(
      status: CheckpointWorkerError.Busy) # Done retains backpressure until collection.
  if prepared.error != CheckpointError.None: return CheckpointAdmission(
      status: CheckpointWorkerError.NotReady) # Caller retains the exact codec refusal.
  if operation == CheckpointOperation.Advance and not expected.ready:
    return CheckpointAdmission(status: CheckpointWorkerError.InvalidHead) # Default metadata cannot authorize an advancement request.
  if uint64(prepared.byteLength) > uint64(limit): return CheckpointAdmission(
      status: CheckpointWorkerError.LimitExceeded) # Refusal precedes buffer transfer.
  if worker.next == high(uint64): return CheckpointAdmission(
      status: CheckpointWorkerError.Exhausted) # No request generation wraps to revive a stale ticket.
  inc worker.next
  worker.prepared = move(prepared)
  worker.cancelled = false
  worker.operation = operation
  worker.expected = expected
  worker.limit = limit
  worker.outcome = default(CheckpointBankResult[CheckpointHead])
  worker.phase = CheckpointWorkerPhase.Staged
  CheckpointAdmission(status: CheckpointWorkerError.None,
    ticket: CheckpointTicket(owner: worker.identity, generation: worker.next))
func matches(worker: CheckpointWorker, ticket: CheckpointTicket): bool =
  ## Host-only identity comparison runs under the lock and grants no authority to idle or zero-generation tickets.
  ticket.owner == worker.identity and ticket.generation != 0 and ticket.generation ==
      worker.next and worker.phase != CheckpointWorkerPhase.Idle
proc begin*(worker: var CheckpointWorker, ticket: CheckpointTicket): bool =
  ## The explicit staged-to-running transition permits host policy checks before any file I/O begins.
  if not worker.started: return false
  acquire(worker.lock)
  defer: release(worker.lock)
  if not worker.matches(ticket) or worker.phase !=
      CheckpointWorkerPhase.Staged: return false # Foreign/stale/repeated dispatch cannot start another transaction.
  worker.phase = CheckpointWorkerPhase.Running
  signal(worker.changed)
  true
proc cancel*(worker: var CheckpointWorker, ticket: CheckpointTicket): bool =
  ## Cancel only a matching staged request before dispatch; already dispatched or completed publication is never hidden.
  if not worker.started: return false # Closed/default workers own no cancellable slot.
  acquire(worker.lock)
  defer: release(worker.lock)
  if not worker.matches(ticket) or worker.phase != CheckpointWorkerPhase.Staged:
    return false # Foreign/stale/running/executing/done work cannot be reclassified as an unstarted cancellation.
  worker.prepared = default(PreparedCheckpoint) # No native activation has accessed this sole host-owned buffer.
  worker.cancelled = true
  worker.phase = CheckpointWorkerPhase.Done # Keep capacity occupied until explicit matching collection or joined close.
  true
proc peek*(worker: var CheckpointWorker, ticket: CheckpointTicket): CheckpointCompletion =
  ## Inspect only a matching Done receipt without releasing its private buffer or acknowledgement capacity.
  if not worker.started: return default(CheckpointCompletion) # Closed/default owners have no observable receipt.
  acquire(worker.lock)
  defer: release(worker.lock)
  if not worker.matches(ticket) or worker.phase != CheckpointWorkerPhase.Done:
    return default(CheckpointCompletion) # Foreign/stale/not-ready tickets expose no result.
  if worker.cancelled: return CheckpointCompletion(status: CheckpointCompletionKind.Cancelled)
  CheckpointCompletion(status: CheckpointCompletionKind.Completed, outcome: worker.outcome)
proc retry*(worker: var CheckpointWorker, ticket: CheckpointTicket,
    expected: CheckpointHead): CheckpointAdmission =
  ## Restage only an exact stale-head refusal with the same sole buffer and explicit new expectation; uncertain/successful writes cannot retry implicitly.
  if not worker.started: return CheckpointAdmission(status: CheckpointWorkerError.Closed)
  acquire(worker.lock)
  defer: release(worker.lock)
  if not worker.matches(ticket) or worker.phase != CheckpointWorkerPhase.Done or worker.cancelled:
    return CheckpointAdmission(status: CheckpointWorkerError.NotReady) # Cancellation, foreign generations and active requests retain their exact state.
  if worker.operation != CheckpointOperation.Advance or worker.outcome.error !=
      CheckpointBankError.StaleHead:
    return CheckpointAdmission(status: CheckpointWorkerError.NotReady) # Actual publication or I/O uncertainty requires explicit collection/reconciliation, never a duplicate hidden write.
  if not expected.ready: return CheckpointAdmission(status: CheckpointWorkerError.InvalidHead)
  if worker.next == high(uint64): return CheckpointAdmission(
      status: CheckpointWorkerError.Exhausted) # A retry receives fresh nonwrapping ticket authority.
  inc worker.next
  worker.expected = expected
  worker.outcome = default(CheckpointBankResult[CheckpointHead])
  worker.phase = CheckpointWorkerPhase.Staged # Explicit begin remains required before any new I/O.
  CheckpointAdmission(status: CheckpointWorkerError.None,
    ticket: CheckpointTicket(owner: worker.identity, generation: worker.next))
proc collect*(worker: var CheckpointWorker, ticket: CheckpointTicket): CheckpointCompletion =
  ## Collect only Done after all worker-local aliases retire, then release the sole buffer on its host allocator thread.
  if not worker.started: return default(CheckpointCompletion)
  acquire(worker.lock)
  defer: release(worker.lock)
  if not worker.matches(ticket) or worker.phase != CheckpointWorkerPhase.Done:
    return default(CheckpointCompletion) # Not-ready or foreign requests retain the slot and its owner.
  if worker.cancelled:
    result = CheckpointCompletion(status: CheckpointCompletionKind.Cancelled) # A staged cancellation has no native publication outcome.
  else:
    result = CheckpointCompletion(status: CheckpointCompletionKind.Completed,
        outcome: worker.outcome) # Preserve actual dispatched success or refusal.
  worker.outcome = default(CheckpointBankResult[CheckpointHead])
  worker.prepared = default(PreparedCheckpoint)
  worker.expected = default(CheckpointHead)
  worker.cancelled = false
  worker.phase = CheckpointWorkerPhase.Idle
proc close*(worker: var CheckpointWorker): CheckpointShutdown =
  ## Join before retiring the private buffer/bank; never label an already completed publication as cancelled.
  result = default(CheckpointShutdown) # Initialize the whole aggregate before assigning its independent completion and retirement fields.
  if not worker.started:
    return CheckpointShutdown(finished: default(CheckpointCompletion),
        retirement: CheckpointBankError.None) # Default/repeated close performs no native lifetime work.
  acquire(worker.lock)
  worker.stopping = true
  broadcast(worker.changed)
  release(worker.lock)
  worker.thread.join()
  if worker.phase == CheckpointWorkerPhase.Done:
    if worker.cancelled:
      result.finished = CheckpointCompletion(status: CheckpointCompletionKind.Cancelled) # Preserve an explicit staged cancellation through joined close too.
    else:
      result.finished = CheckpointCompletion(status: CheckpointCompletionKind.Completed,
        outcome: worker.outcome) # Preserve actual success or failure even when the host skipped collect.
  elif worker.phase == CheckpointWorkerPhase.Executing:
    result.finished = CheckpointCompletion(status: CheckpointCompletionKind.Interrupted) # A missing outcome after native entry must never be described as an unstarted/cancelled transaction.
  elif worker.phase == CheckpointWorkerPhase.Staged or worker.phase ==
      CheckpointWorkerPhase.Running:
    result.finished = CheckpointCompletion(status: CheckpointCompletionKind.Cancelled) # Joined thread never completed this unstarted request.
  else:
    result.finished = default(CheckpointCompletion) # Idle shutdown has no operation receipt.
  worker.outcome = default(CheckpointBankResult[CheckpointHead])
  worker.prepared = default(PreparedCheckpoint)
  worker.expected = default(CheckpointHead)
  worker.phase = CheckpointWorkerPhase.Idle
  worker.started = false
  worker.cancelled = false
  worker.identity = nil
  result.retirement = worker.bank.close() # Keep a native close error separate from the possibly committed operation.
  deinitCond(worker.changed)
  deinitLock(worker.lock)
