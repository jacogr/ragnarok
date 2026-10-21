# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## One fixed-address native worker commits an opaque disk publication under an exclusive ARC graph lease.
## The host pauses RPC and all aliases, collects the actual IO outcome, then installs canonical/RPC state.
## There is no cancel-as-rollback operation: joined shutdown preserves every operation that entered IO.
import std/[assertions, locks, rawthreads]
import ./disk_chain
import ../state/disk_store
import ../storage/node_repository

type
  DiskWorkerPhase* {.pure.} = enum ## Done retains capacity and exclusive graph borrowing until collection or joined close.
    Idle, Queued, Executing, Done
  DiskWorkerError* {.pure.} = enum ## Refused admission grants no ticket or graph lease.
    Uninitialized, None, Closed, Busy, NotReady, Exhausted
  WorkerIdentity = ref object ## Host-only namespace is never touched by the native thread.
    marker: uint8
  DiskPublicationTicket* = object ## Retained namespace plus nonwrapping generation rejects foreign and stale tickets.
    owner: nil WorkerIdentity
    generation: uint64
  DiskPublicationAdmission* = object ## Only successful admission exposes a host retirement ticket.
    case status: DiskWorkerError
    of None: ticket: DiskPublicationTicket
    else: discard                    # Defaults and refusals grant no capacity or completion authority.
  DiskCompletionKind* {.pure.} = enum ## Shutdown distinguishes work never entered from any actual durable or failed IO result.
    Uninitialized, Completed, NotExecuted
  DiskPublicationCompletion* = object ## Only Completed carries the exact coordinator result, including IO uncertainty.
    case status: DiskCompletionKind
    of Completed: outcome: DiskChainResult[RepositoryGeneration]
    else: discard # NotExecuted promises no operation entry; it never suppresses an actual commit receipt.
  DiskPublicationWorker* = object ## Noncopyable thread owner remains at one stable address through joined close.
    lock: Lock
    changed: Cond
    thread: RawThread
    started, stopping: bool
    phase: DiskWorkerPhase
    next: uint64
    identity: nil WorkerIdentity
    disk: nil ptr DiskStateStore
    publication: nil ptr PreparedDiskPublication
    outcome: DiskChainResult[RepositoryGeneration]
proc `=wasMoved`*(worker: var DiskPublicationWorker) {.nodestroy, inline,
    requires: not worker.started.} =
  ## Relocation is permitted only before startup or after joined shutdown ends every native borrow.
  `=wasMoved`(worker.outcome)
  `=wasMoved`(worker.identity)
proc `=copy`*(destination: var DiskPublicationWorker, source: DiskPublicationWorker) {.error.}
  ## One composite owner retires synchronization state and its fixed-address thread.
proc `=dup`*(source: DiskPublicationWorker): DiskPublicationWorker {.error.}
  ## Actual ARC lowering must independently reject implicit composite duplication.
proc requireClosed(worker: DiskPublicationWorker) {.requires: not worker.started.} =
  ## Destruction cannot abandon a thread borrowing host disk/publication graphs.
  discard
proc `=destroy`*(worker: DiskPublicationWorker) =
  ## Explicit joined close precedes destruction of every borrowed owner and alias.
  requireClosed(worker)
  `=destroy`(worker.outcome)
  `=destroy`(worker.identity)
func error*(admission: DiskPublicationAdmission): DiskWorkerError =
  ## Inspect admission without granting access to an unowned slot.
  admission.status
func value*(admission: DiskPublicationAdmission): DiskPublicationTicket {.inline,
    requires: admission.status == DiskWorkerError.None.} =
  ## Successful admission alone grants retirement authority.
  admission.ticket
func kind*(completion: DiskPublicationCompletion): DiskCompletionKind =
  ## Inspect lifecycle separately from the actual IO success/failure.
  completion.status
func value*(completion: DiskPublicationCompletion): DiskChainResult[RepositoryGeneration] {.inline,
    requires: completion.status == DiskCompletionKind.Completed.} =
  ## Preserve the exact result, especially partial/uncertain IO failures, after all native temporaries retire.
  completion.outcome
proc execute(worker: ptr DiskPublicationWorker) =
  ## Never touch host canonical/RPC owners; all temporary ARC aliases retire before publishing Done.
  let disk = worker.disk
  let publication = worker.publication
  assert disk != nil and publication != nil
  worker.outcome = commitDiskPublication(disk[], publication[])
proc run(raw: pointer) =
  ## Condition-driven one-slot execution performs no network callbacks or host installation.
  let worker = cast[ptr DiskPublicationWorker](raw)
  acquire(worker.lock)
  while true:
    while worker.phase != DiskWorkerPhase.Queued and not worker.stopping:
      wait(worker.changed, worker.lock) # Spurious wakeups recheck scalar lifecycle state.
    if worker.stopping:
      release(worker.lock)
      return # Queued-only shutdown enters no IO; an already executing operation always reaches Done first.
    worker.phase = DiskWorkerPhase.Executing
    release(worker.lock)
    execute(worker)
    acquire(worker.lock)
    worker.phase = DiskWorkerPhase.Done # All operation-stack aliases have retired before host access is permitted.
proc start*(worker: var DiskPublicationWorker): bool {.raises.} =
  ## Initialize at the final owner address; failed thread creation leaves no live synchronization resources.
  if worker.started: return false
  initLock(worker.lock)
  initCond(worker.changed)
  worker.stopping = false
  worker.phase = DiskWorkerPhase.Idle
  worker.next = 0
  worker.outcome = default(DiskChainResult[RepositoryGeneration])
  try:
    worker.identity = WorkerIdentity(marker: 1)
    worker.thread.create(run, addr worker)
  except:
    worker.identity = nil
    deinitCond(worker.changed)
    deinitLock(worker.lock)
    raise # No running borrower survives a failed start.
  worker.started = true
  true
proc phase*(worker: var DiskPublicationWorker): DiskWorkerPhase =
  ## Scalar-only host observation never increments ARC counts in any leased graph.
  if not worker.started: return DiskWorkerPhase.Idle
  acquire(worker.lock)
  result = worker.phase
  release(worker.lock)
proc submit*(worker: var DiskPublicationWorker, disk: var DiskStateStore,
    publication: var PreparedDiskPublication): DiskPublicationAdmission =
  ## Borrow stable disk/publication addresses and ALL aliases exclusively until collect or joined close.
  ## Canonical/RPC preflight and RPC pause happen on the host before this admission.
  if not worker.started: return DiskPublicationAdmission(status: DiskWorkerError.Closed)
  acquire(worker.lock)
  defer: release(worker.lock)
  if worker.phase != DiskWorkerPhase.Idle:
    return DiskPublicationAdmission(status: DiskWorkerError.Busy) # Check capacity before touching any possibly leased graph.
  if not publication.ready or not disk.opened:
    return DiskPublicationAdmission(status: DiskWorkerError.NotReady)
  if worker.next == high(uint64): return DiskPublicationAdmission(status: DiskWorkerError.Exhausted)
  inc worker.next
  worker.disk = addr disk
  worker.publication = addr publication
  worker.phase = DiskWorkerPhase.Queued
  signal(worker.changed)
  DiskPublicationAdmission(status: DiskWorkerError.None,
    ticket: DiskPublicationTicket(owner: worker.identity, generation: worker.next))
func matches(worker: var DiskPublicationWorker, ticket: DiskPublicationTicket): bool =
  ## Called under the lock; only the current nonidle slot grants collection authority.
  ticket.owner == worker.identity and ticket.generation != 0 and ticket.generation ==
      worker.next and
    worker.phase != DiskWorkerPhase.Idle
proc collect*(worker: var DiskPublicationWorker, ticket: DiskPublicationTicket): DiskPublicationCompletion =
  ## Only Done ends the graph lease; early/foreign/stale collection leaves capacity and borrowers untouched.
  if not worker.started: return default(DiskPublicationCompletion)
  acquire(worker.lock)
  defer: release(worker.lock)
  if not worker.matches(ticket) or worker.phase != DiskWorkerPhase.Done:
    return default(DiskPublicationCompletion)
  result = DiskPublicationCompletion(status: DiskCompletionKind.Completed, outcome: move(
      worker.outcome))
  worker.disk = nil
  worker.publication = nil
  worker.phase = DiskWorkerPhase.Idle
proc close*(worker: var DiskPublicationWorker): DiskPublicationCompletion =
  ## Join before ending any graph lease; return every actual IO outcome even when shutdown raced execution.
  if not worker.started: return default(DiskPublicationCompletion)
  acquire(worker.lock)
  worker.stopping = true
  broadcast(worker.changed)
  release(worker.lock)
  worker.thread.join()
  if worker.phase == DiskWorkerPhase.Done:
    result = DiskPublicationCompletion(status: DiskCompletionKind.Completed, outcome: move(
        worker.outcome))
  elif worker.phase == DiskWorkerPhase.Queued:
    result = DiskPublicationCompletion(status: DiskCompletionKind.NotExecuted) # No operation activation began.
  else:
    result = default(DiskPublicationCompletion) # Idle/collected slots have no second receipt.
  worker.disk = nil
  worker.publication = nil
  worker.phase = DiskWorkerPhase.Idle
  worker.started = false
  worker.identity = nil
  deinitCond(worker.changed)
  deinitLock(worker.lock)
