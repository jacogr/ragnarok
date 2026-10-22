# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## One reusable fixed-address worker owns an admitted query while exclusively leasing its selected-state ARC graph.
## Plain ARC requires all external selected-state aliases to remain untouched through cancellation and Done.
## One host thread serializes controls; the worker stays at its final address until joined close.

import std/[assertions, locks, rawthreads]
import ./proof_query

type
  ProofWorkerPhase* {.pure.} = enum ## Done still occupies capacity and retains the exclusive graph lease.
    Idle, Queued, Running, Done
  ProofWorkerError* {.pure.} = enum ## Admission failures retain no ticket or borrowed graph.
    Uninitialized, None, Closed, Busy, NotReady, Exhausted
  ProofWorkerIdentity = ref object ## Host-only namespace; the worker never accesses this ARC reference.
    marker: uint8
  ProofWorkerTicket* = object ## Retained namespace and nonwrapping generation prevent foreign or stale retirement.
    owner: nil ProofWorkerIdentity
    generation: uint64
  ProofWorkerAdmission* = object ## Successful admission alone exposes its lease ticket.
    case status: ProofWorkerError
    of None: ticket: ProofWorkerTicket
    else: discard                # Refusals retain no authority.
  ProofWorkerCompletionKind* {.pure.} = enum ## Cancellation never exposes a proof success prefix.
    Uninitialized, Completed, Cancelled
  ProofWorkerCompletion* = object ## Only a collected uncancelled completion exposes its typed query outcome.
    case status: ProofWorkerCompletionKind
    of Completed: response: ProofQueryResult[ProofResponse]
    else: discard # Defaults and cancellation have no response payload.
  StateProofWorker* = object ## Must remain at one address from start through explicit joined close.
    lock: Lock
    changed: Cond
    thread: RawThread
    started, stopping, cancelled: bool
    phase: ProofWorkerPhase
    next: uint64
    identity: nil ProofWorkerIdentity
    query: ProofQuery
    outcome: ProofQueryResult[ProofResponse]

proc `=wasMoved`*(worker: var StateProofWorker) {.nodestroy, inline,
    requires: not worker.started.} =
  ## Moving a live worker would invalidate the address borrowed by its native thread.
  `=wasMoved`(worker.query)
  `=wasMoved`(worker.outcome)
  `=wasMoved`(worker.identity)

proc `=copy`*(destination: var StateProofWorker, source: StateProofWorker) {.error.}
  ## A native thread and its borrowed stack addresses have exactly one owner.
proc `=dup`*(source: StateProofWorker): StateProofWorker {.error.}
  ## Composite owners must reject duplication explicitly.
proc requireClosed(worker: StateProofWorker) {.requires: not worker.started.} =
  ## Destruction cannot silently abandon a thread borrowing host memory.
  discard
proc `=destroy`*(worker: StateProofWorker) =
  ## Host cleanup joins explicitly while all borrowed inputs and aliases still exist.
  requireClosed(worker)
  `=destroy`(worker.query)
  `=destroy`(worker.outcome)
  `=destroy`(worker.identity)

func error*(admission: ProofWorkerAdmission): ProofWorkerError =
  ## Observe admission without granting ticket authority.
  admission.status
func value*(admission: ProofWorkerAdmission): ProofWorkerTicket {.inline,
    requires: admission.status == ProofWorkerError.None.} =
  ## Only admitted work grants a ticket.
  admission.ticket
func kind*(completion: ProofWorkerCompletion): ProofWorkerCompletionKind =
  ## Observe default/cancelled results without extracting a response.
  completion.status
func value*(completion: ProofWorkerCompletion): ProofQueryResult[ProofResponse] {.inline,
    requires: completion.status == ProofWorkerCompletionKind.Completed.} =
  ## The query's own guarded result retains all typed failures and finalized success.
  completion.response

proc execute(worker: ptr StateProofWorker) =
  ## All selected-state aliases and generation scratch retire before run publishes Done.
  worker.outcome = executeProofQuery(worker.query)

proc run(raw: pointer) =
  ## A single condition-driven thread performs no service, transport or canonical-publication work.
  let worker = cast[ptr StateProofWorker](raw)
  acquire(worker.lock)
  while true:
    while worker.phase != ProofWorkerPhase.Queued and not worker.stopping:
      wait(worker.changed, worker.lock) # Recheck after spurious wakeups; never poll for jobs.
    if worker.stopping:
      release(worker.lock)
      return # Shutdown ends all borrowing before the host clears retained owners.
    worker.phase = ProofWorkerPhase.Running
    let skip = worker.cancelled
    release(worker.lock)
    if not skip:
      execute(worker) # The host cannot touch any alias of the exclusively borrowed ARC graph.
    acquire(worker.lock)
    worker.phase = ProofWorkerPhase.Done # execute's entire activation has already retired.

proc start*(worker: var StateProofWorker): bool {.raises.} =
  ## Initialize one worker at its final address; preserve generations across close/restart.
  if worker.started: return false # Reinitialization cannot replace live locks or thread state.
  initLock(worker.lock)
  initCond(worker.changed)
  worker.stopping = false
  worker.phase = ProofWorkerPhase.Idle
  try:
    worker.thread.create(run, addr worker)
  except:
    deinitCond(worker.changed)
    deinitLock(worker.lock)
    raise # Failed creation leaves no running borrower or initialized synchronization owner.
  worker.identity = ProofWorkerIdentity(marker: 1) # Host-only ticket identity is fresh even when an address is reused.
  worker.started = true
  true

proc phase*(worker: var StateProofWorker): ProofWorkerPhase =
  ## Scalar-only polling never copies a leased ARC owner.
  if not worker.started: return ProofWorkerPhase.Idle # Defaults/closed workers own no slot.
  acquire(worker.lock)
  result = worker.phase
  release(worker.lock)

proc submit*(worker: var StateProofWorker, query: var ProofQuery): ProofWorkerAdmission =
  ## Transfer one query; every external selected-state alias remains untouched until collect/join.
  if not worker.started: return ProofWorkerAdmission(status: ProofWorkerError.Closed)
  acquire(worker.lock)
  defer: release(worker.lock)
  if worker.phase != ProofWorkerPhase.Idle:
    return ProofWorkerAdmission(status: ProofWorkerError.Busy)
  if not query.valid:
    return ProofWorkerAdmission(status: ProofWorkerError.NotReady)
  if worker.next == high(uint64):
    return ProofWorkerAdmission(status: ProofWorkerError.Exhausted)
  inc worker.next
  worker.query = move(query)
  worker.cancelled = false
  worker.phase = ProofWorkerPhase.Queued
  signal(worker.changed)
  ProofWorkerAdmission(status: ProofWorkerError.None,
    ticket: ProofWorkerTicket(owner: worker.identity, generation: worker.next))

func matches(worker: var StateProofWorker, ticket: ProofWorkerTicket): bool =
  ## Called under the lock; generation zero and idle slots never authorize retirement.
  ticket.owner == worker.identity and ticket.generation != 0 and ticket.generation ==
      worker.next and
    worker.phase != ProofWorkerPhase.Idle

proc cancel*(worker: var StateProofWorker, ticket: ProofWorkerTicket): bool =
  ## Mark unwanted work without freeing capacity, ending the lease or interrupting proof/FFI execution.
  if not worker.started: return false # A closed/default owner never accepts cancellation.
  acquire(worker.lock)
  defer: release(worker.lock)
  if not worker.matches(ticket): return false # Foreign/stale tickets cannot affect another lease.
  worker.cancelled = true
  true

proc collect*(worker: var StateProofWorker, ticket: ProofWorkerTicket): ProofWorkerCompletion =
  ## Only Done collection ends the lease; defaults leave the slot and graph entirely untouched.
  if not worker.started: return default(ProofWorkerCompletion)
  acquire(worker.lock)
  defer: release(worker.lock)
  if not worker.matches(ticket) or worker.phase != ProofWorkerPhase.Done:
    return default(ProofWorkerCompletion) # Still-running work and foreign tickets retain all ownership.
  if worker.cancelled:
    worker.outcome = default(ProofQueryResult[ProofResponse])
    result = ProofWorkerCompletion(status: ProofWorkerCompletionKind.Cancelled)
  else:
    result = ProofWorkerCompletion(status: ProofWorkerCompletionKind.Completed,
      response: move(worker.outcome)) # Transfer on the host only after all worker aliases have retired.
  worker.query = default(ProofQuery)
  worker.phase = ProofWorkerPhase.Idle

proc close*(worker: var StateProofWorker) =
  ## Join before releasing results or ending the exclusive graph lease; running computation is not preemptible.
  if not worker.started: return # Defaults and repeated cleanup have no native lifetime.
  acquire(worker.lock)
  worker.stopping = true
  broadcast(worker.changed)
  release(worker.lock)
  worker.thread.join()
  worker.outcome = default(ProofQueryResult[ProofResponse])
  worker.query = default(ProofQuery)
  worker.phase = ProofWorkerPhase.Idle
  worker.started = false
  deinitCond(worker.changed)
  deinitLock(worker.lock)
