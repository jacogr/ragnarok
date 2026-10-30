# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## One fixed-address worker borrows an exclusively leased input/chain graph until collect or joined close.
## Plain ARC requires every host alias to remain untouched throughout that lease, including on cancellation.
## One host thread serializes control calls; worker/input/chain addresses cannot move while borrowed.

import std/[assertions, locks, rawthreads]
import "./block/input" as block_input
import "./current/block/input" as current_block_input
import ./chain

type
  PreparationPhase* {.pure.} = enum ## Done still occupies capacity and retains the exclusive graph lease.
    Idle, Queued, Running, Done
  PreparationError* {.pure.} = enum ## Admission failures retain no ticket or borrowed graph.
    Uninitialized, None, Closed, Busy, NotReady, Exhausted
  PreparationIdentity = ref object ## Host-only namespace; the worker never accesses this ARC reference.
    marker: uint8
  PreparationTicket* = object ## Retained namespace and nonwrapping generation prevent foreign or stale retirement.
    owner: nil PreparationIdentity
    generation: uint64
  PreparationAdmission* = object ## Successful admission alone exposes its lease ticket.
    case status: PreparationError
    of None: ticket: PreparationTicket
    else: discard                # Refusals retain no authority.
  PreparationCompletionKind* {.pure.} = enum ## Cancellation never exposes a preparation success prefix.
    Uninitialized, Completed, Cancelled, CurrentCompleted
  PreparationCompletion* = object ## Only a collected uncancelled completion exposes its typed pipeline outcome.
    case status: PreparationCompletionKind
    of Completed: prepared: BlockInputResult
    of CurrentCompleted: currentPrepared: CurrentBlockInputResult
    else: discard # Defaults and cancellation have no candidate payload.
  PreparationOperation {.pure.} = enum ## Payload selection preserves the shared one-slot/ticket lifecycle.
    Legacy, Current
  PreparationWorker* = object ## Must remain at one address from start through explicit joined close.
    lock: Lock
    changed: Cond
    thread: RawThread
    started, stopping, cancelled: bool
    phase: PreparationPhase
    next: uint64
    identity: nil PreparationIdentity
    input: nil ptr BlockInput
    chain: nil ptr ApplicationChain
    id: BlockInputId
    outcome: BlockInputResult
    operation: PreparationOperation
    currentInput: nil ptr CurrentBlockInput
    currentId: CurrentBlockInputId
    currentOutcome: CurrentBlockInputResult

proc `=copy`*(destination: var PreparationWorker, source: PreparationWorker) {.error.}
  ## A native thread and its borrowed stack addresses have exactly one owner.

proc `=dup`*(source: PreparationWorker): PreparationWorker {.error.}
  ## Composite owners must reject duplication explicitly.

proc requireClosed(worker: PreparationWorker) {.requires: not worker.started.} =
  ## Destruction cannot silently abandon a thread borrowing host memory.
  discard

proc `=wasMoved`*(worker: var PreparationWorker) {.nodestroy, inline,
    requires: not worker.started.} =
  ## Disarm transferred fields through their own move hooks; never destroy the destination resources.
  `=wasMoved`(worker.lock)
  `=wasMoved`(worker.changed)
  `=wasMoved`(worker.thread)
  `=wasMoved`(worker.started)
  `=wasMoved`(worker.stopping)
  `=wasMoved`(worker.cancelled)
  `=wasMoved`(worker.phase)
  `=wasMoved`(worker.next)
  `=wasMoved`(worker.identity)
  `=wasMoved`(worker.input)
  `=wasMoved`(worker.chain)
  `=wasMoved`(worker.id)
  `=wasMoved`(worker.outcome)
  `=wasMoved`(worker.operation)
  `=wasMoved`(worker.currentInput)
  `=wasMoved`(worker.currentId)
  `=wasMoved`(worker.currentOutcome)

proc `=destroy`*(worker: PreparationWorker) =
  ## Host cleanup joins explicitly while all borrowed inputs and aliases still exist.
  requireClosed(worker)
  `=destroy`(worker.currentOutcome)
  `=destroy`(worker.outcome)
  `=destroy`(worker.identity)

func error*(admission: PreparationAdmission): PreparationError =
  ## Observe admission without granting ticket authority.
  admission.status

func value*(admission: PreparationAdmission): PreparationTicket {.inline,
    requires: admission.status == PreparationError.None.} =
  ## Only admitted work grants a ticket.
  admission.ticket

func kind*(completion: PreparationCompletion): PreparationCompletionKind =
  ## Observe default/cancelled results without extracting preparation.
  completion.status

func value*(completion: PreparationCompletion): BlockInputResult {.inline,
    requires: completion.status == PreparationCompletionKind.Completed.} =
  ## The pipeline's own guarded result retains all typed failures and finalized success.
  completion.prepared

func currentValue*(completion: PreparationCompletion): CurrentBlockInputResult {.inline,
    requires: completion.status == PreparationCompletionKind.CurrentCompleted.} =
  ## Only actual current execution can expose a current result; legacy completion grants no such authority.
  completion.currentPrepared

proc execute(worker: ptr PreparationWorker) =
  ## All preparation temporaries and their ARC aliases retire before the caller publishes Done.
  let borrowedChain = worker.chain
  assert borrowedChain != nil, "active preparation chain borrow"
  let chain: ptr ApplicationChain = borrowedChain
  case worker.operation
  of PreparationOperation.Current:
    let borrowedInput = worker.currentInput
    assert borrowedInput != nil, "active current preparation borrow"
    let input: ptr CurrentBlockInput = borrowedInput
    worker.currentOutcome = input[].prepare(worker.currentId, chain[])
  of PreparationOperation.Legacy:
    let borrowedInput = worker.input
    assert borrowedInput != nil, "active legacy preparation borrow"
    let input: ptr BlockInput = borrowedInput
    worker.outcome = input[].prepare(worker.id, chain[])

proc run(raw: pointer) =
  ## A single condition-driven thread performs no service, transport or canonical-publication work.
  let worker = cast[ptr PreparationWorker](raw)
  acquire(worker.lock)
  while true:
    while worker.phase != PreparationPhase.Queued and not worker.stopping:
      wait(worker.changed, worker.lock) # Recheck after spurious wakeups; never poll for jobs.
    if worker.stopping:
      release(worker.lock)
      return # Shutdown ends all borrowing before the host clears retained owners.
    worker.phase = PreparationPhase.Running
    let skip = worker.cancelled
    release(worker.lock)
    if not skip:
      execute(worker) # The host cannot touch any alias of the exclusively borrowed ARC graph.
    acquire(worker.lock)
    worker.phase = PreparationPhase.Done # execute's entire activation has already retired.

proc start*(worker: var PreparationWorker): bool {.raises.} =
  ## Initialize one worker at its final address; preserve generations across close/restart.
  if worker.started: return false # Reinitialization cannot replace live locks or thread state.
  initLock(worker.lock)
  initCond(worker.changed)
  worker.stopping = false
  worker.phase = PreparationPhase.Idle
  try:
    worker.thread.create(run, addr worker)
  except:
    deinitCond(worker.changed)
    deinitLock(worker.lock)
    raise # Failed creation leaves no running borrower or initialized synchronization owner.
  worker.identity = PreparationIdentity(marker: 1) # Host-only ticket identity is fresh even when an address is reused.
  worker.started = true
  true

proc phase*(worker: var PreparationWorker): PreparationPhase =
  ## Scalar-only polling never copies a leased ARC owner.
  if not worker.started: return PreparationPhase.Idle # Defaults/closed workers own no slot.
  acquire(worker.lock)
  result = worker.phase
  release(worker.lock)

proc submit*(worker: var PreparationWorker, input: var BlockInput, id: BlockInputId,
    chain: var ApplicationChain): PreparationAdmission =
  ## Borrow stable input/chain exclusively, including ALL aliases, until collect or close; no canonical host work is allowed.
  if not worker.started: return PreparationAdmission(status: PreparationError.Closed)
  acquire(worker.lock)
  defer: release(worker.lock)
  if worker.phase != PreparationPhase.Idle: return PreparationAdmission(
      status: PreparationError.Busy)
  if input.stage != BlockInputStage.Ready: return PreparationAdmission(
      status: PreparationError.NotReady)
  if worker.next == high(uint64): return PreparationAdmission(status: PreparationError.Exhausted)
  inc worker.next
  worker.operation = PreparationOperation.Legacy
  worker.input = addr input
  worker.chain = addr chain
  worker.id = id
  worker.cancelled = false
  worker.phase = PreparationPhase.Queued
  signal(worker.changed)
  PreparationAdmission(status: PreparationError.None,
    ticket: PreparationTicket(owner: worker.identity, generation: worker.next))

proc submit*(worker: var PreparationWorker, input: var CurrentBlockInput, id: CurrentBlockInputId,
    chain: var ApplicationChain): PreparationAdmission =
  ## Borrow the genuine current receiver and every input/chain alias exclusively until collection or joined close.
  if not worker.started: return PreparationAdmission(status: PreparationError.Closed)
  acquire(worker.lock)
  defer: release(worker.lock)
  if worker.phase != PreparationPhase.Idle: return PreparationAdmission(
      status: PreparationError.Busy)
  if input.stage != CurrentBlockInputStage.Ready: return PreparationAdmission(
      status: PreparationError.NotReady)
  if worker.next == high(uint64): return PreparationAdmission(status: PreparationError.Exhausted)
  inc worker.next
  worker.operation = PreparationOperation.Current
  worker.currentInput = addr input
  worker.chain = addr chain
  worker.currentId = id
  worker.cancelled = false
  worker.phase = PreparationPhase.Queued
  signal(worker.changed)
  PreparationAdmission(status: PreparationError.None,
    ticket: PreparationTicket(owner: worker.identity, generation: worker.next))

func matches(worker: var PreparationWorker, ticket: PreparationTicket): bool =
  ## Called under the lock; generation zero and idle slots never authorize retirement.
  ticket.owner == worker.identity and ticket.generation != 0 and ticket.generation ==
      worker.next and
    worker.phase != PreparationPhase.Idle

proc cancel*(worker: var PreparationWorker, ticket: PreparationTicket): bool =
  ## Mark unwanted work without freeing capacity, ending the lease or interrupting PVM/FFI execution.
  if not worker.started: return false # A closed/default owner never accepts cancellation.
  acquire(worker.lock)
  defer: release(worker.lock)
  if not worker.matches(ticket): return false # Foreign/stale tickets cannot affect another lease.
  worker.cancelled = true
  true

proc collect*(worker: var PreparationWorker, ticket: PreparationTicket): PreparationCompletion =
  ## Only Done collection ends the lease; defaults leave the slot and graph entirely untouched.
  if not worker.started: return default(PreparationCompletion)
  acquire(worker.lock)
  defer: release(worker.lock)
  if not worker.matches(ticket) or worker.phase != PreparationPhase.Done:
    return default(PreparationCompletion) # Still-running work and foreign tickets retain all ownership.
  if worker.cancelled:
    worker.outcome = default(BlockInputResult)
    worker.currentOutcome = default(CurrentBlockInputResult)
    result = PreparationCompletion(status: PreparationCompletionKind.Cancelled)
  elif worker.operation == PreparationOperation.Current:
    result = PreparationCompletion(status: PreparationCompletionKind.CurrentCompleted,
      currentPrepared: move(worker.currentOutcome)) # Current and legacy successes remain distinct alternatives.
  else:
    result = PreparationCompletion(status: PreparationCompletionKind.Completed,
      prepared: move(worker.outcome)) # Transfer on the host only after all worker aliases have retired.
  worker.input = nil
  worker.currentInput = nil
  worker.chain = nil
  worker.phase = PreparationPhase.Idle

proc close*(worker: var PreparationWorker) =
  ## Join before releasing results or ending the exclusive graph lease; running computation is not preemptible.
  if not worker.started: return # Defaults and repeated cleanup have no native lifetime.
  acquire(worker.lock)
  worker.stopping = true
  broadcast(worker.changed)
  release(worker.lock)
  worker.thread.join()
  worker.outcome = default(BlockInputResult)
  worker.currentOutcome = default(CurrentBlockInputResult)
  worker.input = nil
  worker.currentInput = nil
  worker.chain = nil
  worker.phase = PreparationPhase.Idle
  worker.started = false
  deinitCond(worker.changed)
  deinitLock(worker.lock)
