# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## One fixed-address I/O worker publishes detached envelopes or verifies complete files.
## Canonical graphs never cross its thread boundary.
## One host thread serializes stage/begin/collect/close; native work and shutdown never run in network callbacks.

import std/[locks, rawthreads]
import ./[file as checkpoint_file, writer as checkpoint_writer, identity as checkpoint_identity,
    transfer as checkpoint_transfer, codec as checkpoint_codec]
import ../../codec/bounded
import ../../state/store

type
  ApplicationCheckpointOperation* {.pure.} = enum ## Verified file content and durable publication have distinct fixed receipt meanings.
    Publish, Verify
  ApplicationCheckpointWorkerPhase* {.pure.} = enum ## Done retains capacity until explicit collection; Staged has not begun I/O.
    Idle, Staged, Running, Executing, Done
  ApplicationCheckpointWorkerError* {.pure.} = enum ## Refused admission never consumes the caller's sole prepared owner.
    Uninitialized, None, Closed, Busy, NotReady, InvalidContext, LimitExceeded, Exhausted
  WorkerIdentity = ref object ## Host-only namespace is never accessed by the native I/O thread.
    marker: uint8
  ApplicationCheckpointTicket* = object ## Identity plus nonwrapping local generation prevent foreign/stale completion access.
    owner: nil WorkerIdentity
    generation: uint64
  ApplicationCheckpointAdmission* = object ## Only admitted staged work exposes an ownership ticket.
    case status: ApplicationCheckpointWorkerError
    of None:
      ticket: ApplicationCheckpointTicket
    else:
      discard                              # Failed/default admission retains no lease authority.
  ApplicationCheckpointCompletionKind* {.pure.} = enum ## Completed means the operation returned; its writer outcome may still be a failure.
    Uninitialized, Completed, Cancelled, Interrupted
  ApplicationCheckpointCompletion* = object ## Only completed work exposes its exact typed writer outcome.
    case status: ApplicationCheckpointCompletionKind
    of Completed:
      performed: ApplicationCheckpointOperation
      outcome: ApplicationCheckpointFileResult[ApplicationCheckpointIdentity]
    else:
      discard # No default/cancelled publication receipt can be adopted.
  ApplicationCheckpointShutdown* = object ## Joining preserves any actual operation receipt independently of native retirement errors.
    finished: ApplicationCheckpointCompletion
    retirement: ApplicationCheckpointFileError
  ApplicationCheckpointWorker* = object ## Keep this noncopyable owner at one address from start until joined close.
    lock: Lock
    changed: Cond
    thread: RawThread
    started, stopping, cancelled: bool
    phase: ApplicationCheckpointWorkerPhase
    next: uint64
    identity: nil WorkerIdentity
    writer: ApplicationCheckpointWriter
    prepared: PreparedApplicationCheckpoint
    limit: ByteLimit
    request: ApplicationCheckpointOperation
    expected: ApplicationCheckpointIdentity
    verifyLimits: StateStoreLimits
    outcome: ApplicationCheckpointFileResult[ApplicationCheckpointIdentity]

proc `=wasMoved`*(worker: var ApplicationCheckpointWorker) {.nodestroy, inline,
    requires: not worker.started.} =
  ## Only inactive owners may relocate; a running thread retains the exact original worker address until joined close.
  `=wasMoved`(worker.prepared)
  `=wasMoved`(worker.writer)
  `=wasMoved`(worker.identity)

proc `=copy`*(destination: var ApplicationCheckpointWorker,
    source: ApplicationCheckpointWorker) {.error.}
  ## Thread synchronization and the private writer's lock have one composite owner.

proc `=dup`*(source: ApplicationCheckpointWorker): ApplicationCheckpointWorker {.error.}
  ## Actual ARC lowering must independently reject composite worker duplication.

proc requireClosed(worker: ApplicationCheckpointWorker) {.requires: not worker.started.} =
  ## A live native thread cannot outlive its stable owner address or private writer.
  discard

proc `=destroy`*(worker: ApplicationCheckpointWorker) =
  ## Explicit joined close ends every worker borrow before host-owned buffers and writer paths retire.
  requireClosed(worker)
  `=destroy`(worker.prepared)
  `=destroy`(worker.writer)
  `=destroy`(worker.identity)

func error*(admission: ApplicationCheckpointAdmission): ApplicationCheckpointWorkerError =
  ## Observe refusal without granting access to an unowned staged slot.
  admission.status

func value*(admission: ApplicationCheckpointAdmission): ApplicationCheckpointTicket {.inline,
    requires: admission.status == ApplicationCheckpointWorkerError.None.} =
  ## Only successful admission grants the host a ticket.
  admission.ticket

func kind*(completion: ApplicationCheckpointCompletion): ApplicationCheckpointCompletionKind =
  ## Default and cancelled work remain distinct from an actual typed writer outcome.
  completion.status

func value*(completion: ApplicationCheckpointCompletion): ApplicationCheckpointFileResult[
    ApplicationCheckpointIdentity] {.inline,

requires: completion.status == ApplicationCheckpointCompletionKind.Completed.} =
  ## Callers must also check the returned writer outcome before extracting a committed head.
  completion.outcome

func completion*(shutdown: ApplicationCheckpointShutdown): ApplicationCheckpointCompletion =
  ## Preserve a possibly committed operation even when native retirement separately fails.
  shutdown.finished

func retirementError*(shutdown: ApplicationCheckpointShutdown): ApplicationCheckpointFileError =
  ## None confirms actual idempotent/native close; default shutdown reports Uninitialized.
  shutdown.retirement

func operation*(completion: ApplicationCheckpointCompletion): ApplicationCheckpointOperation {.inline,
    requires: completion.status == ApplicationCheckpointCompletionKind.Completed.} =
  ## An actual verified file never masquerades as a durable publication receipt.
  completion.performed

proc execute(worker: ptr ApplicationCheckpointWorker) =
  ## Native verification retires decoded graphs on this thread; publication borrows only host-owned detached bytes.
  case worker.request
  of ApplicationCheckpointOperation.Publish:
    worker.outcome = worker.writer.save(worker.prepared, worker.limit)
  of ApplicationCheckpointOperation.Verify:
    worker.outcome = worker.writer.verify(worker.expected, worker.verifyLimits, worker.limit)

proc run(raw: pointer) =
  ## A condition-driven single thread performs only ordered writer I/O, with no canonical adoption or dispatcher callbacks.
  let worker = cast[ptr ApplicationCheckpointWorker](raw)
  acquire(worker.lock)
  while true:
    while worker.phase != ApplicationCheckpointWorkerPhase.Running and not worker.stopping:
      wait(worker.changed, worker.lock) # Recheck after spurious wakeups without polling or consuming staged-only work.
    if worker.stopping:
      release(worker.lock)
      return # Joined close can distinguish an unstarted request from Done after the final activation.
    worker.phase = ApplicationCheckpointWorkerPhase.Executing # Distinguish native entry from dispatched work skipped by shutdown.
    release(worker.lock)
    execute(worker)
    acquire(worker.lock)
    worker.phase = ApplicationCheckpointWorkerPhase.Done # No stack-local buffer/path alias remains active when the host can collect.

proc start*(worker: var ApplicationCheckpointWorker,
    prefix: string): ApplicationCheckpointFileError {.raises.} =
  ## Startup acquires the private cooperative writer before starting one thread at the owner's final address.
  if worker.started: return ApplicationCheckpointFileError.Busy # Repeated startup cannot replace live synchronization state.
  let opened = worker.writer.openApplicationCheckpointWriter(prefix)
  if opened != ApplicationCheckpointFileError.None: return opened # No thread or condition exists after failed path/lock admission.
  initLock(worker.lock)
  initCond(worker.changed)
  worker.stopping = false
  worker.cancelled = false
  worker.phase = ApplicationCheckpointWorkerPhase.Idle
  worker.next = 0
  worker.limit = ByteLimit(0)
  worker.request = ApplicationCheckpointOperation.Publish
  worker.expected = default(ApplicationCheckpointIdentity)
  worker.verifyLimits = default(StateStoreLimits)
  worker.outcome = default(ApplicationCheckpointFileResult[ApplicationCheckpointIdentity])
  worker.prepared = default(PreparedApplicationCheckpoint)
  try:
    worker.identity = WorkerIdentity(marker: 1) # Allocate host identity before a thread can retain the stable address.
    worker.thread.create(run, addr worker)
  except:
    deinitCond(worker.changed)
    deinitLock(worker.lock)
    discard worker.writer.close()
    worker.identity = nil
    raise # Thread creation failure cannot leave an active writer or initialized synchronization resource.
  worker.started = true
  ApplicationCheckpointFileError.None

proc phase*(worker: var ApplicationCheckpointWorker): ApplicationCheckpointWorkerPhase =
  ## Host polling reads scalar state only; it never accesses the worker's exclusive buffer or native writer paths.
  if not worker.started: return ApplicationCheckpointWorkerPhase.Idle
  acquire(worker.lock)
  result = worker.phase
  release(worker.lock)

proc stage*(worker: var ApplicationCheckpointWorker, prepared: var PreparedApplicationCheckpoint,
    limit: ByteLimit): ApplicationCheckpointAdmission =
  ## Consume the caller's sole buffer only after every bounded admission check; staging itself performs no disk I/O.
  if not worker.started: return ApplicationCheckpointAdmission(
      status: ApplicationCheckpointWorkerError.Closed)
  acquire(worker.lock)
  defer: release(worker.lock)
  if worker.phase != ApplicationCheckpointWorkerPhase.Idle: return ApplicationCheckpointAdmission(
      status: ApplicationCheckpointWorkerError.Busy) # Done retains backpressure until collection.
  if prepared.error != ApplicationCheckpointError.None: return ApplicationCheckpointAdmission(
      status: ApplicationCheckpointWorkerError.NotReady) # Caller retains the exact codec refusal.
  if uint64(prepared.byteLength) > uint64(limit): return ApplicationCheckpointAdmission(
      status: ApplicationCheckpointWorkerError.LimitExceeded) # Refusal precedes buffer transfer.
  if worker.next == high(uint64): return ApplicationCheckpointAdmission(
      status: ApplicationCheckpointWorkerError.Exhausted) # No request generation wraps to revive a stale ticket.
  inc worker.next
  worker.prepared = move(prepared)
  worker.cancelled = false
  worker.limit = limit
  worker.request = ApplicationCheckpointOperation.Publish
  worker.expected = default(ApplicationCheckpointIdentity)
  worker.verifyLimits = default(StateStoreLimits)
  worker.outcome = default(ApplicationCheckpointFileResult[ApplicationCheckpointIdentity])
  worker.phase = ApplicationCheckpointWorkerPhase.Staged
  ApplicationCheckpointAdmission(status: ApplicationCheckpointWorkerError.None,
    ticket: ApplicationCheckpointTicket(owner: worker.identity, generation: worker.next))

proc stageVerification*(worker: var ApplicationCheckpointWorker,
    expected: ApplicationCheckpointIdentity,

limits: StateStoreLimits, limit: ByteLimit): ApplicationCheckpointAdmission =
  ## Only independent fixed context and explicit map/byte policy cross the thread; no filesystem work happens during admission.
  if not worker.started: return ApplicationCheckpointAdmission(
      status: ApplicationCheckpointWorkerError.Closed)
  acquire(worker.lock)
  defer: release(worker.lock)
  if worker.phase != ApplicationCheckpointWorkerPhase.Idle:
    return ApplicationCheckpointAdmission(status: ApplicationCheckpointWorkerError.Busy) # All request kinds retain Done acknowledgement backpressure.
  if not expected.ready:
    return ApplicationCheckpointAdmission(status: ApplicationCheckpointWorkerError.InvalidContext) # File metadata cannot authorize its own verification.
  if worker.next == high(uint64):
    return ApplicationCheckpointAdmission(status: ApplicationCheckpointWorkerError.Exhausted) # Verification shares the same nonwrapping namespace as publication.
  inc worker.next
  worker.prepared = default(PreparedApplicationCheckpoint)
  worker.cancelled = false
  worker.request = ApplicationCheckpointOperation.Verify
  worker.expected = expected
  worker.verifyLimits = limits
  worker.limit = limit
  worker.outcome = default(ApplicationCheckpointFileResult[ApplicationCheckpointIdentity])
  worker.phase = ApplicationCheckpointWorkerPhase.Staged
  ApplicationCheckpointAdmission(status: ApplicationCheckpointWorkerError.None,
    ticket: ApplicationCheckpointTicket(owner: worker.identity, generation: worker.next))

func matches(worker: ApplicationCheckpointWorker, ticket: ApplicationCheckpointTicket): bool =
  ## Host-only identity comparison runs under the lock and grants no authority to idle or zero-generation tickets.
  ticket.owner == worker.identity and ticket.generation != 0 and ticket.generation ==
      worker.next and worker.phase != ApplicationCheckpointWorkerPhase.Idle

proc begin*(worker: var ApplicationCheckpointWorker, ticket: ApplicationCheckpointTicket): bool =
  ## The explicit staged-to-running transition permits host policy checks before any file I/O begins.
  if not worker.started: return false
  acquire(worker.lock)
  defer: release(worker.lock)
  if not worker.matches(ticket) or worker.phase !=
      ApplicationCheckpointWorkerPhase.Staged: return false # Foreign/stale/repeated dispatch cannot start another transaction.
  worker.phase = ApplicationCheckpointWorkerPhase.Running
  signal(worker.changed)
  true

proc cancel*(worker: var ApplicationCheckpointWorker, ticket: ApplicationCheckpointTicket): bool =
  ## Only a matching staged-only request may become Cancelled; dispatched or completed publication remains observable.
  if not worker.started: return false
  acquire(worker.lock)
  defer: release(worker.lock)
  if not worker.matches(ticket) or worker.phase != ApplicationCheckpointWorkerPhase.Staged:
    return false # Foreign/stale/running/executing/done authority cannot hide a possible publication.
  worker.prepared = default(PreparedApplicationCheckpoint) # No native activation has borrowed these host-owned bytes.
  worker.cancelled = true
  worker.phase = ApplicationCheckpointWorkerPhase.Done # Acknowledgement still owns the single capacity slot.
  true

proc peek*(worker: var ApplicationCheckpointWorker,
    ticket: ApplicationCheckpointTicket): ApplicationCheckpointCompletion =
  ## Inspect only a matching Done outcome without releasing capacity or publishing a retry.
  if not worker.started: return default(ApplicationCheckpointCompletion)
  acquire(worker.lock)
  defer: release(worker.lock)
  if not worker.matches(ticket) or worker.phase != ApplicationCheckpointWorkerPhase.Done:
    return default(ApplicationCheckpointCompletion) # Wrong/not-ready tickets reveal no other request's outcome.
  if worker.cancelled:
    return ApplicationCheckpointCompletion(status: ApplicationCheckpointCompletionKind.Cancelled)
  ApplicationCheckpointCompletion(status: ApplicationCheckpointCompletionKind.Completed,
      performed: worker.request, outcome: worker.outcome)

proc collect*(worker: var ApplicationCheckpointWorker,
    ticket: ApplicationCheckpointTicket): ApplicationCheckpointCompletion =
  ## Collect only Done after all worker-local aliases retire, then release the sole buffer on its host allocator thread.
  if not worker.started: return default(ApplicationCheckpointCompletion)
  acquire(worker.lock)
  defer: release(worker.lock)
  if not worker.matches(ticket) or worker.phase != ApplicationCheckpointWorkerPhase.Done:
    return default(ApplicationCheckpointCompletion) # Not-ready or foreign requests retain the slot and its owner.
  if worker.cancelled:
    result = ApplicationCheckpointCompletion(status: ApplicationCheckpointCompletionKind.Cancelled) # Unstarted cancellation has no publication receipt.
  else:
    result = ApplicationCheckpointCompletion(status: ApplicationCheckpointCompletionKind.Completed,
        performed: worker.request, outcome: worker.outcome) # Actual returned success or refusal remains distinct from cancellation.
  worker.cancelled = false
  worker.outcome = default(ApplicationCheckpointFileResult[ApplicationCheckpointIdentity])
  worker.prepared = default(PreparedApplicationCheckpoint)
  worker.phase = ApplicationCheckpointWorkerPhase.Idle

proc close*(worker: var ApplicationCheckpointWorker): ApplicationCheckpointShutdown =
  ## Join before retiring the private buffer/writer; never label an already completed publication as cancelled.
  result = default(ApplicationCheckpointShutdown) # Initialize the whole aggregate before assigning its independent completion and retirement fields.
  if not worker.started:
    return ApplicationCheckpointShutdown(finished: default(ApplicationCheckpointCompletion),
        retirement: ApplicationCheckpointFileError.None) # Default/repeated close performs no native lifetime work.
  acquire(worker.lock)
  worker.stopping = true
  broadcast(worker.changed)
  release(worker.lock)
  worker.thread.join()
  if worker.phase == ApplicationCheckpointWorkerPhase.Done:
    if worker.cancelled:
      result.finished = ApplicationCheckpointCompletion(
          status: ApplicationCheckpointCompletionKind.Cancelled) # Preserve an explicit staged cancellation after joined retirement.
    else:
      result.finished = ApplicationCheckpointCompletion(
          status: ApplicationCheckpointCompletionKind.Completed,

performed: worker.request, outcome: worker.outcome) # Joined shutdown preserves an actual returned publication receipt.
  elif worker.phase == ApplicationCheckpointWorkerPhase.Executing:
    result.finished = ApplicationCheckpointCompletion(
        status: ApplicationCheckpointCompletionKind.Interrupted) # A missing outcome after native entry must never be described as an unstarted/cancelled transaction.
  elif worker.phase == ApplicationCheckpointWorkerPhase.Staged or worker.phase ==
      ApplicationCheckpointWorkerPhase.Running:
    result.finished = ApplicationCheckpointCompletion(
        status: ApplicationCheckpointCompletionKind.Cancelled) # Joined thread never completed this unstarted request.
  else:
    result.finished = default(ApplicationCheckpointCompletion) # Idle shutdown has no operation receipt.
  worker.outcome = default(ApplicationCheckpointFileResult[ApplicationCheckpointIdentity])
  worker.prepared = default(PreparedApplicationCheckpoint)
  worker.phase = ApplicationCheckpointWorkerPhase.Idle
  worker.started = false
  worker.cancelled = false
  worker.identity = nil
  result.retirement = worker.writer.close() # Keep a native close error separate from the possibly committed operation.
  deinitCond(worker.changed)
  deinitLock(worker.lock)
