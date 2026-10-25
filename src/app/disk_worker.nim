# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## One fixed-address native worker serializes distinct full/light publication and retirement or full maintenance under an exclusive ARC graph lease.
## The host pauses RPC and all aliases, collects the actual IO outcome, then installs canonical/RPC state.
## There is no cancel-as-rollback operation: joined shutdown preserves every operation that entered IO.
import std/[assertions, locks, rawthreads]
import ./[disk_chain, light_store]
import ../state/disk_store
import ../storage/[node_repository, managed_repository, full_paged_store, paged_store]

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
    Uninitialized, Completed, NotExecuted, Maintained, Retired, LightCompleted, LightRetired
  DiskPublicationCompletion* = object ## Each selected operation carries its exact typed IO result; queued shutdown grants no outcome.
    case status: DiskCompletionKind
    of Completed: outcome: DiskChainResult[RepositoryGeneration]
    of Maintained: maintenanceOutcome: DiskChainResult[ManagedCompaction]
    of Retired: retirementOutcome: DiskStoreResult[FullPagedReclamation]
    of LightCompleted: lightOutcome: LightStoreResult[LightStorageSnapshot]
    of LightRetired: lightRetirementOutcome: LightStoreResult[PagedReclamation]
    else: discard # NotExecuted promises no operation entry; it never suppresses an actual commit receipt.
  DiskOperation {.pure.} = enum # Payload selection never changes the shared capacity, ticket, execution or retirement protocol.
    Publication, CurrentPublication, Maintenance, Retirement, LightPublication, LightRetirement
  DiskPublicationWorker* = object ## Noncopyable thread owner remains at one stable address through joined close.
    lock: Lock
    changed: Cond
    thread: RawThread
    started, stopping: bool
    phase: DiskWorkerPhase
    next: uint64
    identity: nil WorkerIdentity
    light: nil ptr LightPagedStore
    lightPublication: nil ptr PreparedLightPublication
    lightRetirement: nil ptr PreparedLightRetirement
    lightOutcome: LightStoreResult[LightStorageSnapshot]
    lightRetirementOutcome: LightStoreResult[PagedReclamation]
    disk: nil ptr DiskStateStore
    publication: nil ptr PreparedDiskPublication
    maintenance: nil ptr PreparedDiskMaintenance
    retirement: nil ptr PreparedPagedRetirement
    currentPublication: nil ptr PreparedCurrentDiskPublication
    operation: DiskOperation
    maintenanceOutcome: DiskChainResult[ManagedCompaction]
    retirementOutcome: DiskStoreResult[FullPagedReclamation]
    outcome: DiskChainResult[RepositoryGeneration]
proc `=wasMoved`*(worker: var DiskPublicationWorker) {.nodestroy, inline,
    requires: not worker.started.} =
  ## Relocation is permitted only before startup or after joined shutdown ends every native borrow.
  `=wasMoved`(worker.lightOutcome)
  `=wasMoved`(worker.lightRetirementOutcome)
  `=wasMoved`(worker.retirementOutcome)
  `=wasMoved`(worker.maintenanceOutcome)
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
  `=destroy`(worker.lightOutcome)
  `=destroy`(worker.lightRetirementOutcome)
  `=destroy`(worker.retirementOutcome)
  `=destroy`(worker.maintenanceOutcome)
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
func maintenanceValue*(completion: DiskPublicationCompletion): DiskChainResult[
    ManagedCompaction] {.inline, requires: completion.status == DiskCompletionKind.Maintained.} =
  ## Preserve the actual maintenance/cleanup receipt without granting a canonical publication outcome.
  completion.maintenanceOutcome
func retirementValue*(completion: DiskPublicationCompletion): DiskStoreResult[
    FullPagedReclamation] {.inline, requires: completion.status == DiskCompletionKind.Retired.} =
  ## Keep cleanup success, Busy and uncertainty separate from ordinary publication and maintenance receipts.
  completion.retirementOutcome
func lightValue*(completion: DiskPublicationCompletion): LightStoreResult[
    LightStorageSnapshot] {.inline, requires: completion.status ==
        DiskCompletionKind.LightCompleted.} =
  ## A light metadata/proof publication receipt never grants a full-state execution snapshot.
  completion.lightOutcome
func lightRetirementValue*(completion: DiskPublicationCompletion): LightStoreResult[
    PagedReclamation] {.inline, requires: completion.status == DiskCompletionKind.LightRetired.} =
  ## Keep actual light cleanup outcomes separate from both full-state and light core publication.
  completion.lightRetirementOutcome
proc execute(worker: ptr DiskPublicationWorker) =
  ## Never touch host canonical/RPC owners; all temporary ARC aliases retire before publishing Done.
  let disk = worker.disk
  case worker.operation
  of DiskOperation.LightPublication:
    let light = worker.light
    let publication = worker.lightPublication
    assert light != nil and publication != nil
    worker.lightOutcome = light[].commit(publication[])
  of DiskOperation.LightRetirement:
    let light = worker.light
    let retirement = worker.lightRetirement
    assert light != nil and retirement != nil
    worker.lightRetirementOutcome = light[].retire(retirement[])
  of DiskOperation.Retirement:
    assert disk != nil # Full-state operations retain their distinct complete-store owner.
    let retirement = worker.retirement
    assert retirement != nil
    worker.retirementOutcome = commitPagedRetirement(disk[], retirement[])
  of DiskOperation.Maintenance:
    assert disk != nil # Full-state operations retain their distinct complete-store owner.
    let maintenance = worker.maintenance
    assert maintenance != nil
    worker.maintenanceOutcome = commitDiskMaintenance(disk[], maintenance[])
  of DiskOperation.CurrentPublication:
    assert disk != nil # Full-state operations retain their distinct complete-store owner.
    let publication = worker.currentPublication
    assert publication != nil
    worker.outcome = commitDiskPublication(disk[], publication[])
  of DiskOperation.Publication:
    assert disk != nil # Full-state operations retain their distinct complete-store owner.
    let publication = worker.publication
    assert publication != nil
    worker.outcome = commitDiskPublication(disk[], publication[]) # Every payload uses the same excluded activation and receipt lifetime.
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
  worker.lightOutcome = default(LightStoreResult[LightStorageSnapshot])
  worker.lightRetirementOutcome = default(LightStoreResult[PagedReclamation])
  worker.retirementOutcome = default(DiskStoreResult[FullPagedReclamation])
  worker.maintenanceOutcome = default(DiskChainResult[ManagedCompaction])
  worker.operation = DiskOperation.Publication
  worker.light = nil
  worker.lightPublication = nil
  worker.lightRetirement = nil
  worker.disk = nil
  worker.publication = nil
  worker.currentPublication = nil
  worker.maintenance = nil
  worker.retirement = nil
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
  worker.light = nil
  worker.lightPublication = nil
  worker.lightRetirement = nil
  worker.disk = addr disk
  worker.publication = addr publication
  worker.currentPublication = nil
  worker.maintenance = nil
  worker.retirement = nil
  worker.operation = DiskOperation.Publication
  worker.phase = DiskWorkerPhase.Queued
  signal(worker.changed)
  DiskPublicationAdmission(status: DiskWorkerError.None,
    ticket: DiskPublicationTicket(owner: worker.identity, generation: worker.next))
proc submit*(worker: var DiskPublicationWorker, disk: var DiskStateStore,
    publication: var PreparedCurrentDiskPublication): DiskPublicationAdmission =
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
  worker.light = nil
  worker.lightPublication = nil
  worker.lightRetirement = nil
  worker.disk = addr disk
  worker.publication = nil
  worker.currentPublication = addr publication
  worker.maintenance = nil
  worker.retirement = nil
  worker.operation = DiskOperation.CurrentPublication
  worker.phase = DiskWorkerPhase.Queued
  signal(worker.changed)
  DiskPublicationAdmission(status: DiskWorkerError.None,
    ticket: DiskPublicationTicket(owner: worker.identity, generation: worker.next))
proc submitMaintenance*(worker: var DiskPublicationWorker, disk: var DiskStateStore,
    maintenance: var PreparedDiskMaintenance): DiskPublicationAdmission =
  ## Borrow all aliases exclusively in the existing one-slot thread; Busy checks precede graph access.
  if not worker.started: return DiskPublicationAdmission(status: DiskWorkerError.Closed)
  acquire(worker.lock)
  defer: release(worker.lock)
  if worker.phase != DiskWorkerPhase.Idle: return DiskPublicationAdmission(
      status: DiskWorkerError.Busy)
  if not maintenance.ready or not disk.opened: return DiskPublicationAdmission(
      status: DiskWorkerError.NotReady)
  if worker.next == high(uint64): return DiskPublicationAdmission(status: DiskWorkerError.Exhausted)
  inc worker.next
  worker.light = nil
  worker.lightPublication = nil
  worker.lightRetirement = nil
  worker.disk = addr disk
  worker.publication = nil
  worker.currentPublication = nil
  worker.maintenance = addr maintenance
  worker.retirement = nil
  worker.operation = DiskOperation.Maintenance
  worker.phase = DiskWorkerPhase.Queued
  signal(worker.changed)
  DiskPublicationAdmission(status: DiskWorkerError.None,
    ticket: DiskPublicationTicket(owner: worker.identity, generation: worker.next))
proc submitRetirement*(worker: var DiskPublicationWorker, disk: var DiskStateStore,
    retirement: var PreparedPagedRetirement): DiskPublicationAdmission =
  ## The host borrows stable disk/job addresses exclusively until collection or joined shutdown.
  if not worker.started: return DiskPublicationAdmission(status: DiskWorkerError.Closed)
  acquire(worker.lock)
  defer: release(worker.lock)
  if worker.phase != DiskWorkerPhase.Idle:
    return DiskPublicationAdmission(status: DiskWorkerError.Busy) # Never inspect a leased graph before checking capacity.
  if not retirement.ready or not disk.opened:
    return DiskPublicationAdmission(status: DiskWorkerError.NotReady)
  if worker.next == high(uint64): return DiskPublicationAdmission(status: DiskWorkerError.Exhausted)
  inc worker.next
  worker.light = nil
  worker.lightPublication = nil
  worker.lightRetirement = nil
  worker.disk = addr disk
  worker.publication = nil
  worker.currentPublication = nil
  worker.maintenance = nil
  worker.retirement = addr retirement
  worker.operation = DiskOperation.Retirement
  worker.phase = DiskWorkerPhase.Queued
  signal(worker.changed)
  DiskPublicationAdmission(status: DiskWorkerError.None,
    ticket: DiskPublicationTicket(owner: worker.identity, generation: worker.next))
proc submit*(worker: var DiskPublicationWorker, light: var LightPagedStore,
    publication: var PreparedLightPublication): DiskPublicationAdmission =
  ## Borrow stable light owner/job addresses and every shared ARC alias exclusively through collection or joined close.
  if not worker.started: return DiskPublicationAdmission(
      status: DiskWorkerError.Closed) # No native thread owns these inputs.
  acquire(worker.lock)
  defer: release(worker.lock)
  if worker.phase != DiskWorkerPhase.Idle: return DiskPublicationAdmission(
      status: DiskWorkerError.Busy) # Capacity is checked before touching a potentially leased graph.
  if not publication.ready or not light.opened: return DiskPublicationAdmission(
      status: DiskWorkerError.NotReady) # Passive readiness grants no native authority.
  if worker.next == high(uint64): return DiskPublicationAdmission(
      status: DiskWorkerError.Exhausted) # Ticket generations never wrap.
  inc worker.next
  worker.disk = nil
  worker.publication = nil
  worker.currentPublication = nil
  worker.maintenance = nil
  worker.retirement = nil
  worker.light = addr light
  worker.lightPublication = addr publication
  worker.lightRetirement = nil
  worker.operation = DiskOperation.LightPublication
  worker.phase = DiskWorkerPhase.Queued
  signal(worker.changed)
  DiskPublicationAdmission(status: DiskWorkerError.None,
    ticket: DiskPublicationTicket(owner: worker.identity, generation: worker.next))
proc submitRetirement*(worker: var DiskPublicationWorker, light: var LightPagedStore,
    retirement: var PreparedLightRetirement): DiskPublicationAdmission =
  ## Borrow stable light owner/job addresses and every shared ARC alias exclusively through collection or joined close.
  if not worker.started: return DiskPublicationAdmission(
      status: DiskWorkerError.Closed) # No native thread owns these inputs.
  acquire(worker.lock)
  defer: release(worker.lock)
  if worker.phase != DiskWorkerPhase.Idle: return DiskPublicationAdmission(
      status: DiskWorkerError.Busy) # Capacity is checked before touching a potentially leased graph.
  if not retirement.ready or not light.opened: return DiskPublicationAdmission(
      status: DiskWorkerError.NotReady) # Passive readiness grants no native authority.
  if worker.next == high(uint64): return DiskPublicationAdmission(
      status: DiskWorkerError.Exhausted) # Ticket generations never wrap.
  inc worker.next
  worker.disk = nil
  worker.publication = nil
  worker.currentPublication = nil
  worker.maintenance = nil
  worker.retirement = nil
  worker.light = addr light
  worker.lightPublication = nil
  worker.lightRetirement = addr retirement
  worker.operation = DiskOperation.LightRetirement
  worker.phase = DiskWorkerPhase.Queued
  signal(worker.changed)
  DiskPublicationAdmission(status: DiskWorkerError.None,
    ticket: DiskPublicationTicket(owner: worker.identity, generation: worker.next))
proc completion(worker: var DiskPublicationWorker): DiskPublicationCompletion =
  ## Only Done collection or joined Done shutdown moves the actual selected operation result once.
  if worker.operation == DiskOperation.LightPublication:
    DiskPublicationCompletion(status: DiskCompletionKind.LightCompleted, lightOutcome: move(
        worker.lightOutcome))
  elif worker.operation == DiskOperation.LightRetirement:
    DiskPublicationCompletion(status: DiskCompletionKind.LightRetired, lightRetirementOutcome: move(
        worker.lightRetirementOutcome))
  elif worker.operation == DiskOperation.Retirement:
    DiskPublicationCompletion(status: DiskCompletionKind.Retired, retirementOutcome: move(
        worker.retirementOutcome))
  elif worker.operation == DiskOperation.Maintenance:
    DiskPublicationCompletion(status: DiskCompletionKind.Maintained, maintenanceOutcome: move(
        worker.maintenanceOutcome))
  else:
    DiskPublicationCompletion(status: DiskCompletionKind.Completed, outcome: move(worker.outcome))
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
  result = completion(worker)
  worker.light = nil
  worker.lightPublication = nil
  worker.lightRetirement = nil
  worker.disk = nil
  worker.publication = nil
  worker.currentPublication = nil
  worker.maintenance = nil
  worker.retirement = nil
  worker.operation = DiskOperation.Publication
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
    result = completion(worker)
  elif worker.phase == DiskWorkerPhase.Queued:
    result = DiskPublicationCompletion(status: DiskCompletionKind.NotExecuted) # No operation activation began.
  else:
    result = default(DiskPublicationCompletion) # Idle/collected slots have no second receipt.
  worker.light = nil
  worker.lightPublication = nil
  worker.lightRetirement = nil
  worker.disk = nil
  worker.publication = nil
  worker.currentPublication = nil
  worker.maintenance = nil
  worker.retirement = nil
  worker.operation = DiskOperation.Publication
  worker.phase = DiskWorkerPhase.Idle
  worker.started = false
  worker.identity = nil
  deinitCond(worker.changed)
  deinitLock(worker.lock)
