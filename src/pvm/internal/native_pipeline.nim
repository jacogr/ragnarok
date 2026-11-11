# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Shared ARM64 and x86-64 scheduling for one compiler work slot and four image credits.
## The host serializes handle operations. The worker receives copied IR and a scalar job key
## under the runtime lock. Parked completions belong to individual registrations and free
## the worker before the host collects them. Credits bound image owners through unmapping.
## A connected Read owner can also queue one auxiliary mixed loop, leaving a usable credit
## for primary work. The worker claims queued primary work first. Pressure may cancel the
## auxiliary while borrowed. The last return completes retirement after the frame restores
## its checked handler, and only physical unmapping releases the credit.
## Deferred identities hold no credit; only eligible work that can queue claims one.
## Installed owners retain credits while idle, so a serialized second consumer can still
## exhaust the table. Consumer reservations, fairness and aggregate prepared-memory limits
## belong to the enclosing execution environment; this scheduler implements no such policy.
##
## A source epoch retains its first structural pure candidate.
## At most one later Read can replace an unused installed image per stream epoch.
## Physical retirement releases the incumbent's credit before fresh admission.
## Busy work or occupied credits can defer the replacement and leave execution checked.
##
## The 4096-work gate is the maximum settled work of one public call, not lifetime heat or
## evidence that the selected candidate is profitable. Ready entry also needs the current
## call's 4096-step horizon. Deferred read nominations survive busy-slot retry after source
## revalidation, and acquire a credit only when eligible work can queue.

import std/[assertions, locks, rawthreads]
import ../[machine, program]
import ./[native_ir, native_platform, native_read_body, native_register_ring]
export native_ir, native_read_body, native_register_ring

when NativeReadCycleEnabled:
  import ./native_read_cycle
  export native_read_cycle
  import ./native_mixed_loop

when NativeCheckedReadEnabled:
  when NativeReadCycleEnabled:
    type NativeReadStorage = NativeReadCycle ## One embedded body for either checked read ABI.
  else:
    type NativeReadStorage = NativeReadBody ## Leaf-only builds retain just the checked body.

  template readCertificate(proof: NativeReadStorage): untyped =
    ## Select the existing body field without copying the retained proof.
    when NativeReadCycleEnabled:
      proof.read
    else:
      proof

type NativeImageKey* = object
  ## A copied installed-image identity never grants entry without the current invocation lease.
  slot*: int
  generation*, ticket*, epoch*: uint64
  kind*: NativeKind

when NativeCheckedReadEnabled:
  const
    NativeReadProbeWalkLimit* = 128 ## Whole-call certificate attempts, including refused cached bodies.
    NativeReadProbeSeenSlots = NativeReadProbeWalkLimit*2 ## Fixed scalar table, never a full PC map.
    NativeReadProbeSearchLimit = NativeReadProbeWalkLimit*NativeReadProbeWalkLimit
      ## Total cell probes over one public call, including collisions and repeats.
  type
    NativeReadDiscoveryWorkspace = object
      ## Session-owned POD initialized for later discovery only; no guest or frame borrow.
      seen: array[NativeReadProbeSeenSlots, uint32]
      searches: int
      active: bool
    NativeReadCandidate = object
      ## One bounded later-region proof is independent of the immutable installed proof.
      proof: NativeReadStorage
      incumbent: NativeImageKey
      kind: NativeKind
      streak: range[0'u8..2'u8]
      observed, validated: bool

type NativeRequest = object
  ## The locked job key selects the sole live payload in this mailbox.
  span: NativeSpan
  when NativeCheckedReadEnabled:
    readProof: NativeReadStorage
    ring: NativeRegisterRing
    ringEpoch: uint64

when defined(pvmSharedAsyncWitness):
  type
    NativeCompilerPoint* {.pure.} = enum ## Witness-only gates are armed outside public invocation clocks.
      None, AfterClaim, BeforePublish, AfterPublish, BeforeRetire
    NativeCompilerObservation* = object ## Owned scalar witness, never an executable or host-graph borrow.
      point*: NativeCompilerPoint
      slot*: int
      generation*, ticket*, epoch*: uint64
      hasImage*: bool
      kind*: NativeKind

type
  NativePhase* {.pure.} = enum ## Active work wins; otherwise Done observes parked completions, never blocks admission.
    Idle, Queued, Running, Done
  NativeState* {.pure.} = enum ## Profit deferral is reversible; unavailable lowering is not a timed guest failure.
    Absent, Deferred, Pending, Ready, Unavailable, Closed
  RegistrationState = enum
    Free, Live, Retiring, Exhausted
  WorkPhase {.pure.} = enum ## One compiler request; parked results belong to their registrations.
    Idle, Queued, Running
  CompletionLocation {.pure.} = enum ## Credit follows the sole image through physical retirement.
    Empty, Queued, Running, Complete, Installed, Reclaiming
  JobKey = object ## Copied authority; no session, Program, frame or callback reference crosses threads.
    slot: int
    generation, ticket, epoch: uint64
    kind: NativeKind
  Retirement = enum
    NoWork, WorkerOwned, Detached
  Registration = object ## Own one uncollected image; retain no registered prepared owner.
    state: RegistrationState
    generation: uint64
    key: JobKey
    location: CompletionLocation
    cancelled: bool
    completion: NativeImage
    when NativeReadCycleEnabled:
      mixedRefusals: array[NativeMixedLoopCandidateLimit,
          uint32]       ## Source header tokens for this primary job key.
  NativeRuntimeStorage = object ## Stable heap allocation owns synchronization until the last closed host handle drops.
    lock: Lock
    changed: Cond
    thread: RawThread
    initialized, started, stopping: bool
    work: WorkPhase
    slots: array[NativeSessionLimit, Registration]
    active: int
    nextTicket: uint64
    key: JobKey
    request: NativeRequest
    submitted, completed: uint64
    when NativeReadCycleEnabled:
      mixedKey, mixedOwner: JobKey ## The auxiliary row and exact installed primary ticket.
      mixedProof: NativeMixedLoop
      mixedBorrowed: bool
    when defined(pvmSharedAsyncWitness):
      paused, gateReached, gateReleased: bool
      gate, followingGate: NativeCompilerPoint
      observation: NativeCompilerObservation
  NativeRuntimeData = ref object ## The named field has a supported stable address, unlike a ref payload cast.
    storage: NativeRuntimeStorage
  NativeRuntime* = object ## Copyable host-side closed lifetime anchor; no worker refcount access.
    data: nil NativeRuntimeData
  NativeSessionStorage = object ## One source-policy identity; an image credit is owned only after submission.
    runtime: nil NativeRuntimeData
    slot: int
    generation, epoch, ticket: uint64
    state: NativeState
    span: NativeSpan
    when NativeCheckedReadEnabled:
      readProof: NativeReadStorage
      readNominated, readValidated: bool # Validation belongs to this invocation's restored stream.
      ring: NativeRegisterRing
      ringEpoch: uint64                  # Only the exact stream epoch may nominate or collect this ring.
      laterRead: NativeReadCandidate
      readDiscovery: NativeReadDiscoveryWorkspace
      replacementArmed, replacedRead: bool
    when NativeReadCycleEnabled:
      readRouteValid: bool
    image: NativeImage
    imageKey: NativeImageKey
    invocationImageKey: NativeImageKey
    invocation, allowed, invocationUsed, invocationQualified: bool
    provenWork, invocationWork, invocationBudget, calls, operations, publications: uint64
    branchCalls, headerCalls: uint64
    nextScan: uint32
    workValid: bool
    when NativeReadCycleEnabled:
      mixedOffered: bool
      mixedObserved: JobKey
      mixedPublications, mixedCalls, mixedOperations, mixedHeaderCalls: uint64
  NativeSessionData = ref NativeSessionStorage
  NativeSession* = object ## Shared prepared identity, used exclusively under PreparedStorage.busy.
    data: nil NativeSessionData
  NativeRuntimeInfo* = object ## Copied work and parked-result activity, never a borrowed session/cache view.
    phase*: NativePhase
    registered*: int ## Image credits held by live/retiring requests, not cold prepared identities.
    active*: int     ## Whole public invocation leases, including calls with no image credit.
    completions*: int ## Uncollected Complete rows, including empty failed images; independent of work phase.
    submitted*, completed*: uint64 ## Cumulative requests queued and completions parked across both work kinds.
  NativeControlStatistics* = object ## Cumulative physical calls with branch or backedge activity.
    branchCalls*, headerCalls*: uint64

proc `=copy`(destination: var Registration, source: Registration) {.error.}

proc `=dup`(source: Registration): Registration {.error.}

proc `=wasMoved`(row: var Registration) {.nodestroy, inline,
    requires: row.state == Free and row.generation == 0 and
      row.location == CompletionLocation.Empty.} =
  ## Only empty uninitialized rows move; never reset a live namespace's generation history.
  `=wasMoved`(row.completion)

proc `=destroy`(row: Registration) =
  ## Proper retirement leaves no mapping; delegate the exclusive child rather than copying its handle.
  assert row.location == CompletionLocation.Empty, "destroy registration only after physical retirement"
  `=destroy`(row.completion)

proc `=copy`(destination: var NativeRuntimeStorage, source: NativeRuntimeStorage) {.error.}

proc `=dup`(source: NativeRuntimeStorage): NativeRuntimeStorage {.error.}

proc `=wasMoved`(runtime: var NativeRuntimeStorage) {.nodestroy, inline,
    requires: not runtime.initialized.} =
  ## Only uninitialized storage can move; even closed initialized mutexes remain at their anchor address.
  for index in 0..<runtime.slots.len:
    # This hook is legal only before synchronization initialization and registration admission.
    `=wasMoved`(runtime.slots[index])
  runtime.initialized = false
  runtime.started = false
  runtime.stopping = false

proc `=destroy`(runtime: var NativeRuntimeStorage) =
  ## Last host anchor must be closed. Sessions retain the allocation/locks after an explicit close.
  assert not runtime.started, "close NativeRuntime before releasing its last anchor"
  for index in 0..<runtime.slots.len:
    # Closed surviving clients retain the anchor until their own image/credit retirement finishes.
    `=destroy`(runtime.slots[index])
  if runtime.initialized:
    deinitCond(runtime.changed)
    deinitLock(runtime.lock)

when NativeCheckedReadEnabled:
  proc clearReadCertificate(data: NativeSessionData) =
    ## Clear leaf authority and retire the route. Inactive POD bytes need no reset.
    readCertificate(data.readProof) = default(NativeReadBody)
    when NativeReadCycleEnabled:
      data.readRouteValid = false

func sameKey(left, right: JobKey): bool =
  ## Compare copied scalar authority without copying an owning registration row.
  if left.kind != right.kind: return false
  left.slot == right.slot and left.generation == right.generation and
    left.ticket == right.ticket and left.epoch == right.epoch

func requestMatches(request: NativeRequest, key: JobKey): bool =
  ## The selected ABI and exact source epoch must agree before a request enters the worker.
  if key.epoch == 0: return false
  case key.kind
  of NativeKind.PurePrefix, NativeKind.ClosedRegisterLoop:
    request.span.len >= NativeMinimumOperations and request.span.epoch == key.epoch and
      request.span.kind == key.kind
  of NativeKind.RegisterRing:
    when NativeCheckedReadEnabled:
      request.ringEpoch == key.epoch and request.ring.complete
    else:
      false
  of NativeKind.CheckedReadBody:
    when NativeCheckedReadEnabled:
      readCertificate(request.readProof).complete and
        readCertificate(request.readProof).info.epoch == key.epoch
    else:
      false
  else:
    when NativeReadCycleEnabled:
      # Nimony case arms cannot be conditional. Reject every other kind before using the ABI.
      key.kind == NativeKind.ConnectedReadCycle and request.readProof.read.complete and
        request.readProof.read.info.epoch == key.epoch
    else:
      false

func acceptedKind(data: NativeSessionData): NativeKind =
  ## A nonzero ticket binds one immutable caller-side certificate until collection.
  assert data.ticket != 0
  when NativeReadCycleEnabled:
    if data.readRouteValid and readCertificate(data.readProof).complete:
      return NativeKind.ConnectedReadCycle
  when NativeCheckedReadEnabled:
    if readCertificate(data.readProof).complete: return NativeKind.CheckedReadBody
    if data.ringEpoch == data.epoch: return NativeKind.RegisterRing
  data.span.kind

func matchesRow(runtime: ptr NativeRuntimeStorage, key: JobKey): bool =
  ## Caller holds the mutex; a live job keeps this generation occupied until physical cleanup.
  if key.slot < 0 or key.slot >= runtime.slots.len: return false
  runtime.slots[key.slot].generation == key.generation and
    sameKey(runtime.slots[key.slot].key, key)

proc finishRetirement(runtime: ptr NativeRuntimeStorage, key: JobKey) =
  ## Caller relocked only AFTER image destruction; recycle the exact row without erasing generation.
  assert matchesRow(runtime, key), "retirement must retain the exact generation/ticket/epoch"
  let index = key.slot
  assert runtime.slots[index].location == CompletionLocation.Reclaiming, "retirement location changed"
  assert not runtime.slots[index].completion.ready, "retirement left a row-owned image"
  runtime.slots[index].location = CompletionLocation.Empty
  runtime.slots[index].key = default(JobKey)
  runtime.slots[index].cancelled = false
  when NativeReadCycleEnabled:
    if sameKey(runtime.mixedKey, key):
      assert not runtime.mixedBorrowed
      runtime.mixedKey = default(JobKey)
      runtime.mixedOwner = default(JobKey)
      runtime.mixedProof = default(NativeMixedLoop)
      runtime.slots[index].state = Free
      return
  if runtime.slots[index].state == Retiring:
    # A detached registration becomes reusable only after its host/worker image was destroyed.
    runtime.slots[index].state = Free

when NativeReadCycleEnabled:
  func freeNativeCredits(runtime: ptr NativeRuntimeStorage): int =
    ## This predicate is read under the runtime lock. Exhausted rows cannot be reused.
    result = 0
    for row in runtime.slots:
      if row.state == Free and row.generation < high(uint64): inc result

  proc retireMixedLoopLocked(runtime: ptr NativeRuntimeStorage) =
    ## Cancel a queued or running owner, or detach a completed image after its last borrow.
    let key = runtime.mixedKey
    if key.generation == 0: return
    assert matchesRow(runtime, key)
    let slot = key.slot
    runtime.slots[slot].cancelled = true
    case runtime.slots[slot].location
    of CompletionLocation.Queued:
      assert not runtime.slots[slot].completion.ready
      runtime.slots[slot].location = CompletionLocation.Reclaiming
      finishRetirement(runtime, key)
    of CompletionLocation.Complete:
      if not runtime.mixedBorrowed:
        var image = move(runtime.slots[slot].completion)
        runtime.slots[slot].location = CompletionLocation.Reclaiming
        release(runtime.lock)
        image = default(NativeImage)
        acquire(runtime.lock)
        finishRetirement(runtime, key)
    of CompletionLocation.Running, CompletionLocation.Reclaiming:
      discard # The current worker or detached host owns physical retirement.
    else:
      abortNativeReceipt()
    broadcast(runtime.changed)

proc retireOwner(runtime: ptr NativeRuntimeStorage, slot: int, generation: uint64,
    finalDrop: bool, image: var NativeImage): Retirement =
  ## One canonical cancellation/detach path; its caller keeps the stable runtime anchor alive.
  if slot < 0 or slot >= runtime.slots.len: return NoWork
  acquire(runtime.lock)
  if runtime.slots[slot].generation != generation or runtime.slots[slot].state != Live:
    release(runtime.lock)
    return NoWork
  when NativeReadCycleEnabled:
    if runtime.mixedKey.generation != 0 and sameKey(runtime.mixedOwner, runtime.slots[slot].key):
      # Only the same serialized prepared owner can retire its installed primary row.
      assert not runtime.mixedBorrowed
      retireMixedLoopLocked(runtime)
  if finalDrop: runtime.slots[slot].state = Retiring
  case runtime.slots[slot].location
  of CompletionLocation.Queued, CompletionLocation.Running:
    # Session.ticket may already be zero after invalidation; the row still owns the old obligation.
    runtime.slots[slot].cancelled = true
    broadcast(runtime.changed)
    release(runtime.lock)
    return WorkerOwned
  of CompletionLocation.Empty:
    # No image or outstanding key exists, so final drop can return this credit immediately.
    assert not image.ready and not runtime.slots[slot].completion.ready
    if finalDrop: runtime.slots[slot].state = Free
    release(runtime.lock)
    return NoWork
  of CompletionLocation.Complete, CompletionLocation.Installed:
    # Complete detaches the row image; Installed already belongs exclusively to this caller.
    let key = runtime.slots[slot].key
    if runtime.slots[slot].location == CompletionLocation.Complete:
      assert not image.ready
      image = move(runtime.slots[slot].completion)
    runtime.slots[slot].location = CompletionLocation.Reclaiming
    release(runtime.lock)
    image = default(NativeImage) # Actual unmapping is outside the mutex; credit is still occupied.
    acquire(runtime.lock)
    finishRetirement(runtime, key)
    broadcast(runtime.changed)
    release(runtime.lock)
    return Detached
  of CompletionLocation.Reclaiming:
    # The worker unlocks while releasing a cancelled local; serialized host invalidate/drop is legal here.
    if runtime.work == WorkPhase.Running and runtime.key.slot == slot and
        runtime.key.generation == generation and matchesRow(runtime, runtime.key):
      runtime.slots[slot].cancelled = true
      broadcast(runtime.changed)
      release(runtime.lock)
      return WorkerOwned
    # A different caller cannot overlap a synchronous host-owned image release under our host contract.
    assert false, "overlapping native owner retirement"
    release(runtime.lock)
    return NoWork

proc `=copy`(destination: var NativeSessionStorage, source: NativeSessionStorage) {.error.}

proc `=dup`(source: NativeSessionStorage): NativeSessionStorage {.error.}

proc `=wasMoved`(session: var NativeSessionStorage) {.nodestroy, inline,
    requires: not session.invocation.} =
  ## Transfer children without decrementing them; the source can no longer retire a registration.
  `=wasMoved`(session.runtime)
  `=wasMoved`(session.image)
  session.invocation = false
  session.allowed = false

proc `=destroy`(session: NativeSessionStorage) =
  ## Native image release precedes freeing its bounded registration credit.
  assert not session.invocation
  `=destroy`(session.image)
  let anchor {.cursor.} = session.runtime
  if anchor != nil:
    # Installed storage was released above, before the canonical helper returns its credit.
    var detached = default(NativeImage)
    discard retireOwner(addr anchor.storage, session.slot, session.generation, true, detached)
  `=destroy`(session.runtime)

proc newNativeRuntime*(): NativeRuntime =
  ## Allocate code-independent synchronization only; explicit start is separately visible lifecycle work.
  let anchor = NativeRuntimeData(storage: NativeRuntimeStorage(work: WorkPhase.Idle))
  initLock(anchor.storage.lock)
  initCond(anchor.storage.changed)
  anchor.storage.initialized = true
  NativeRuntime(data: anchor)

when defined(pvmSharedAsyncWitness):
  proc compilerGate(runtime: ptr NativeRuntimeStorage, key: JobKey,
      point: NativeCompilerPoint, hasImage: bool) =
    ## Called with the mutex held; wait releases it, and stop always bypasses a one-shot gate.
    if runtime.gate != point or runtime.stopping: return
    runtime.observation = NativeCompilerObservation(point: point, slot: key.slot,
      generation: key.generation, ticket: key.ticket, epoch: key.epoch, hasImage: hasImage,
      kind: key.kind)
    runtime.gateReached = true
    broadcast(runtime.changed)
    while not runtime.gateReleased and not runtime.stopping:
      wait(runtime.changed, runtime.lock)
    runtime.gate = if runtime.stopping: NativeCompilerPoint.None else: runtime.followingGate
    runtime.followingGate = NativeCompilerPoint.None
    runtime.gateReached = false
    runtime.gateReleased = false
    broadcast(runtime.changed)

proc releaseCompilerClaim(runtime: ptr NativeRuntimeStorage, key: JobKey): bool {.inline.} =
  ## The worker already copied the selected payload. Sample cancellation after the witness gate.
  when defined(pvmSharedAsyncWitness):
    compilerGate(runtime, key, NativeCompilerPoint.AfterClaim, false)
  result = not runtime.stopping and not runtime.slots[key.slot].cancelled
  release(runtime.lock)

when NativeReadCycleEnabled:
  func mixedLoopRefused(tokens: array[NativeMixedLoopCandidateLimit, uint32],
      header: uint32): bool =
    ## Within the exact primary key the checked header identifies immutable original source.
    for token in tokens:
      if token == 0: return false
      if token == header+1: return true
    true

  func mixedLoopQueued(runtime: ptr NativeRuntimeStorage): bool =
    runtime.mixedKey.generation != 0 and
      runtime.slots[runtime.mixedKey.slot].location == CompletionLocation.Queued

  proc compileMixedLoop(runtime: ptr NativeRuntimeStorage) =
    ## Copy the bounded certificate under the lock. The existing worker publishes its row.
    let key = runtime.mixedKey
    assert matchesRow(runtime, key) and mixedLoopQueued(runtime)
    let proof = runtime.mixedProof
    runtime.slots[key.slot].location = CompletionLocation.Running
    var image = default(NativeImage)
    var refused = false
    if releaseCompilerClaim(runtime, key): image = lowerNativeMixedLoop(proof, refused)
    acquire(runtime.lock)
    when defined(pvmSharedAsyncWitness):
      compilerGate(runtime, key, NativeCompilerPoint.BeforePublish, image.ready)
    assert sameKey(runtime.mixedKey, key) and matchesRow(runtime, key)
    if refused and not runtime.stopping and not runtime.slots[key.slot].cancelled:
      let owner = runtime.mixedOwner
      assert matchesRow(runtime, owner) and
        runtime.slots[owner.slot].location == CompletionLocation.Installed
      for index in 0..<NativeMixedLoopCandidateLimit:
        if runtime.slots[owner.slot].mixedRefusals[index] == 0:
          runtime.slots[owner.slot].mixedRefusals[index] = proof.header+1
          break
    if runtime.stopping or runtime.slots[key.slot].cancelled or not image.ready:
      runtime.slots[key.slot].location = CompletionLocation.Reclaiming
      when defined(pvmSharedAsyncWitness):
        compilerGate(runtime, key, NativeCompilerPoint.BeforeRetire, image.ready)
      release(runtime.lock)
      image = default(NativeImage)
      acquire(runtime.lock)
      finishRetirement(runtime, key)
    else:
      assert image.kind == NativeKind.MixedSelfLoop
      runtime.slots[key.slot].completion = move(image)
      runtime.slots[key.slot].location = CompletionLocation.Complete
      if runtime.completed < high(uint64): inc runtime.completed
      when defined(pvmSharedAsyncWitness):
        compilerGate(runtime, key, NativeCompilerPoint.AfterPublish, true)
    broadcast(runtime.changed)

proc compilerRun(raw: pointer) =
  ## Only the worker lowers copied POD requests; completions park in their own bounded credit rows.
  let runtime = cast[ptr NativeRuntimeStorage](raw)
  acquire(runtime.lock)
  # The starter can proceed once this worker reaches the idle mailbox wait.
  runtime.started = true
  broadcast(runtime.changed)
  while true:
    var runnable = runtime.work == WorkPhase.Queued
    when NativeReadCycleEnabled: runnable = runnable or mixedLoopQueued(runtime)
    when defined(pvmSharedAsyncWitness): runnable = runnable and not runtime.paused
    while not runnable and not runtime.stopping:
      wait(runtime.changed, runtime.lock)
      runnable = runtime.work == WorkPhase.Queued
      when NativeReadCycleEnabled: runnable = runnable or mixedLoopQueued(runtime)
      when defined(pvmSharedAsyncWitness): runnable = runnable and not runtime.paused
    if runtime.stopping:
      release(runtime.lock)
      return
    when NativeReadCycleEnabled:
      if runtime.work != WorkPhase.Queued:
        compileMixedLoop(runtime)
        continue
    let key = runtime.key
    assert requestMatches(runtime.request, key)
    assert matchesRow(runtime, key), "compiler claim lost its exact row certificate"
    assert runtime.slots[key.slot].location == CompletionLocation.Queued, "compiler claim is not Queued"
    runtime.work = WorkPhase.Running
    runtime.slots[key.slot].location = CompletionLocation.Running
    var image = default(NativeImage)
    case key.kind
    of NativeKind.PurePrefix, NativeKind.ClosedRegisterLoop:
      # Copy the selected certificate before the lock or any witness gate can release.
      let span = runtime.request.span
      if releaseCompilerClaim(runtime, key):
        image = lowerNative(span)
    of NativeKind.RegisterRing:
      when NativeCheckedReadEnabled:
        # The exact copied ring is private to this worker before the lock can be released.
        let ring = runtime.request.ring
        if releaseCompilerClaim(runtime, key):
          image = lowerNativeRegisterRing(ring)
      else:
        abortNativeReceipt()
    of NativeKind.CheckedReadBody:
      when NativeCheckedReadEnabled:
        # Only read-capable builds own this payload, with no invocation memory borrow.
        let body = readCertificate(runtime.request.readProof)
        if releaseCompilerClaim(runtime, key):
          image = lowerNativeReadBody(body)
      else:
        abortNativeReceipt()
    else:
      when NativeReadCycleEnabled:
        # Fail closed before copying the region or releasing its exact mailbox claim.
        if key.kind != NativeKind.ConnectedReadCycle: abortNativeReceipt()
        let cycle = runtime.request.readProof
        if releaseCompilerClaim(runtime, key):
          image = lowerNativeReadCycle(cycle)
      else:
        abortNativeReceipt()
    assert not image.ready or image.kind == key.kind
    acquire(runtime.lock)
    when defined(pvmSharedAsyncWitness):
      compilerGate(runtime, key, NativeCompilerPoint.BeforePublish, image.ready)
    assert sameKey(runtime.key, key) and matchesRow(runtime, key), "compiler publication certificate changed"
    assert runtime.slots[key.slot].location == CompletionLocation.Running, "compiler local is not Running"
    if runtime.stopping or runtime.slots[key.slot].cancelled:
      # A worker local remains charged until its real mapping is destroyed outside the mutex.
      runtime.slots[key.slot].location = CompletionLocation.Reclaiming
      when defined(pvmSharedAsyncWitness):
        # The gate releases the mutex with the actual local image still owned, before physical disposal.
        compilerGate(runtime, key, NativeCompilerPoint.BeforeRetire, image.ready)
      release(runtime.lock)
      image = default(NativeImage)
      acquire(runtime.lock)
      finishRetirement(runtime, key)
      runtime.work = WorkPhase.Idle
      runtime.key = default(JobKey)
      broadcast(runtime.changed)
    else:
      # Destination is empty: synthesized assignment destruction cannot release a mapping here.
      assert not runtime.slots[key.slot].completion.ready
      runtime.slots[key.slot].completion = move(image)
      runtime.slots[key.slot].location = CompletionLocation.Complete
      if runtime.completed < high(uint64): inc runtime.completed
      runtime.work = WorkPhase.Idle
      runtime.key = default(JobKey)
      broadcast(runtime.changed)
      when defined(pvmSharedAsyncWitness):
        # B may queue while this gate waits: use A's LOCAL saved key, never the new global key.
        compilerGate(runtime, key, NativeCompilerPoint.AfterPublish,
          runtime.slots[key.slot].completion.ready)

proc start*(runtime: NativeRuntime): bool {.raises.} =
  ## Start at the stable anchor address and wait for the worker to enter its mailbox loop.
  let anchor {.cursor.} = runtime.data
  if anchor == nil or not nativePlatformSupported(): return false
  let data = addr anchor.storage
  if data.started: return false
  for index in 0..<data.slots.len:
    if data.slots[index].state in {Live, Retiring}: return false # Closed live clients cannot cross a restarted namespace.
  data.stopping = false
  when defined(pvmSharedAsyncWitness):
    # A restarted empty namespace cannot inherit a prior test gate or paused worker.
    data.paused = false
    data.gate = NativeCompilerPoint.None
    data.followingGate = NativeCompilerPoint.None
    data.gateReached = false
    data.gateReleased = false
  data.thread.create(compilerRun, data)
  acquire(data.lock)
  while not data.started:
    wait(data.changed, data.lock)
  release(data.lock)
  true

proc close*(runtime: NativeRuntime): bool =
  ## Refuse an active public invocation; join outside the lock, retaining closed storage for live sessions.
  let anchor {.cursor.} = runtime.data
  if anchor == nil: return true
  let data = addr anchor.storage
  acquire(data.lock)
  if not data.started:
    release(data.lock)
    return true
  if data.active != 0:
    release(data.lock)
    return false
  data.stopping = true
  broadcast(data.changed)
  release(data.lock)
  data.thread.join()
  var images = default(array[NativeSessionLimit, NativeImage])
  var keys = default(array[NativeSessionLimit, JobKey])
  var detached = default(array[NativeSessionLimit, bool])
  acquire(data.lock)
  for index in 0..<data.slots.len:
    # With the worker joined, every parked completion can detach without racing publication.
    case data.slots[index].location
    of CompletionLocation.Complete, CompletionLocation.Queued:
      keys[index] = data.slots[index].key
      detached[index] = true
      assert not images[index].ready
      images[index] = move(data.slots[index].completion)
      data.slots[index].location = CompletionLocation.Reclaiming
    of CompletionLocation.Empty, CompletionLocation.Installed:
      discard # Installed storage stays in its closed surviving session, still holding its credit.
    of CompletionLocation.Running, CompletionLocation.Reclaiming:
      assert false, "worker join or serialized retirement left unfinished native ownership"
  release(data.lock)
  for index in 0..<images.len:
    # No runtime mutex is held while executable storage is physically released.
    images[index] = default(NativeImage)
  acquire(data.lock)
  for index in 0..<data.slots.len:
    if detached[index]: finishRetirement(data, keys[index])
  data.work = WorkPhase.Idle
  data.key = default(JobKey)
  data.started = false
  broadcast(data.changed)
  release(data.lock)
  true

proc runtimeInfo*(runtime: NativeRuntime): NativeRuntimeInfo =
  ## Closed/default observation remains safe; no ARC handle is read by the compiler thread.
  let anchor {.cursor.} = runtime.data
  if anchor == nil: return default(NativeRuntimeInfo)
  let data = addr anchor.storage
  acquire(data.lock)
  var count = 0
  var completions = 0
  for index in 0..<data.slots.len:
    # Read only scalar row fields; registrations now own noncopyable completion images.
    if data.slots[index].state in {Live, Retiring}: inc count
    if data.slots[index].location == CompletionLocation.Complete: inc completions
  let auxiliary = when NativeReadCycleEnabled:
      if data.mixedKey.generation != 0: data.slots[data.mixedKey.slot].location
      else: CompletionLocation.Empty
    else: CompletionLocation.Empty
  let phase = if data.work == WorkPhase.Queued: NativePhase.Queued
    elif data.work == WorkPhase.Running: NativePhase.Running
    elif auxiliary == CompletionLocation.Queued: NativePhase.Queued
    elif auxiliary == CompletionLocation.Running: NativePhase.Running
    elif completions > 0: NativePhase.Done else: NativePhase.Idle
  result = NativeRuntimeInfo(phase: phase, registered: count, active: data.active,
    completions: completions, submitted: data.submitted, completed: data.completed)
  release(data.lock)

proc registerSession(runtime: ptr NativeRuntimeStorage, data: NativeSessionData): bool =
  ## The finish lock already proves an eligible request can queue; claim only its image credit.
  assert runtime.started and not runtime.stopping and runtime.work == WorkPhase.Idle
  assert data.slot < 0 and data.ticket == 0 and not data.image.ready
  for index in 0..<runtime.slots.len:
    if runtime.slots[index].state == Free:
      assert runtime.slots[index].location == CompletionLocation.Empty
      assert not runtime.slots[index].completion.ready
      if runtime.slots[index].generation == high(uint64):
        runtime.slots[index].state = Exhausted
      else:
        inc runtime.slots[index].generation
        runtime.slots[index].state = Live
        data.slot = index
        data.generation = runtime.slots[index].generation
        return true
  false

proc newNativeSession*(runtime: NativeRuntime): NativeSession =
  ## Retain source identity and a safe anchor; proof and nomination do not consume image capacity.
  let anchor {.cursor.} = runtime.data
  if anchor == nil: return default(NativeSession)
  NativeSession(data: NativeSessionData(runtime: anchor, slot: -1, epoch: 1,
    state: NativeState.Deferred, image: default(NativeImage)))

proc collectNative(session: NativeSession)
  ## Exact nonblocking collection is legal only at an exclusive invocation boundary.

func nativeInstalledKey*(session: NativeSession): NativeImageKey =
  ## Copy the collected key without granting entry or collecting a pending completion.
  let data {.cursor.} = session.data
  if data == nil or data.state != NativeState.Ready or not data.image.ready:
    return default(NativeImageKey)
  data.imageKey

func matchesNativeImage*(session: NativeSession, key: NativeImageKey, kind: NativeKind): bool =
  ## A bridge needs its exact installed revision and typed ABI under the current permitted lease.
  let data {.cursor.} = session.data
  if data == nil: return false
  data.invocation and data.allowed and data.state == NativeState.Ready and
    key.ticket != 0 and key == data.imageKey and key.epoch == data.epoch and
    key.kind == kind and data.image.kind == kind and data.image.ready

func nativeInvocationUsed*(session: NativeSession): bool =
  ## Track current-call primary execution for Read training and replacement.
  ## The public outcome uses the combined primary and auxiliary operation count.
  let data {.cursor.} = session.data
  if data == nil: return false
  data.invocation and data.invocationUsed

proc completeNativeObservation*(session: NativeSession, successfulHalt: bool) =
  ## Only the real returned frame can qualify the complete public call, after all host segments.
  let data {.cursor.} = session.data
  if data == nil or not data.invocation: return
  data.invocationQualified = successfulHalt

when NativeCheckedReadEnabled:
  func nativeReplacementObservation*(session: NativeSession): bool =
    ## Admit later observation only while the armed incumbent's exact image key remains unused.
    let data {.cursor.} = session.data
    if data == nil: return false
    data.invocation and data.state == NativeState.Ready and data.imageKey.ticket != 0 and
      data.invocationImageKey == data.imageKey and
      data.replacementArmed and not data.invocationUsed and
      data.invocationBudget >= NativeInvocationFloor and data.image.ready

  proc beginNativeReadDiscovery*(session: NativeSession) =
    ## Clear the session-owned table once before the first later observation segment.
    let data {.cursor.} = session.data
    assert data != nil and data.invocation and not data.readDiscovery.active
    data.readDiscovery = default(NativeReadDiscoveryWorkspace)
    data.readDiscovery.active = true

  proc admitReadProbeHeader(probe: var NativeReadDiscoveryWorkspace, header: uint32): bool =
    ## Bound header deduplication by the table size and the invocation-wide search budget.
    if probe.searches == NativeReadProbeSearchLimit: return false
    assert header < NativeEntryLimit
    let key = header+1
    var slot = int(header and uint32(NativeReadProbeSeenSlots-1))
    var probes = 0
    while probes < NativeReadProbeSeenSlots and probe.searches < NativeReadProbeSearchLimit:
      inc probes
      inc probe.searches
      let seen = probe.seen[slot]
      if seen == key: return false
      if seen == 0:
        probe.seen[slot] = key
        return true
      slot = (slot+1) and (NativeReadProbeSeenSlots-1)
    false

  proc admitNativeReadDiscoveryHeader*(session: NativeSession, header: uint32): bool =
    ## Exclusive invocation owns the scalar table across every host segment and memory replacement.
    let data {.cursor.} = session.data
    if data == nil or not data.invocation or not data.readDiscovery.active: return false
    admitReadProbeHeader(data.readDiscovery, header)

  func readIntervalsOverlap(left, right: NativeReadBodyInfo): bool =
    ## Either shared physical handler geometry or shared immutable source facts is conservatively protected.
    (left.header <= right.terminal and right.header <= left.terminal) or
      (left.first <= right.last and right.first <= left.last)

  func readOverlapsBlock(candidate: NativeReadBodyInfo, header, first, span: uint32): bool =
    ## Invalid geometry is never a reason to install an observer over an incumbent's guards.
    if span == 0 or header > high(uint32)-span or first > high(uint32)-span: return true
    readIntervalsOverlap(candidate, NativeReadBodyInfo(header: header, terminal: header+span,
      first: first, last: first+span-1))

  func nativeReadObservationOverlaps*(session: NativeSession, candidate: NativeReadBodyInfo): bool =
    ## Temporary observation must not suppress any installed entry, checked fallback or source guard.
    let data {.cursor.} = session.data
    if data == nil or data.state != NativeState.Ready or data.imageKey.ticket == 0: return false
    if candidate.epoch != data.epoch or candidate.header > candidate.terminal or
        candidate.first > candidate.last: return true
    when NativeReadCycleEnabled:
      if data.imageKey.kind == NativeKind.ConnectedReadCycle:
        for role in NativeCycleRole:
          let site = data.readProof.layout.sites[role]
          if readOverlapsBlock(candidate, site.header, site.first, uint32(NativeCycleSpans[role])):
            return true
        let outside = data.readProof.layout.outsideHeader
        return candidate.header <= outside and outside <= candidate.terminal
    case data.imageKey.kind
    of NativeKind.PurePrefix, NativeKind.ClosedRegisterLoop:
      let span = info(data.span)
      let header = if span.entry == 0: 0'u32 else: span.entry-1
      let protected = NativeReadBodyInfo(header: header, terminal: span.past,
        first: span.first, last: span.last)
      if readIntervalsOverlap(candidate, protected): return true
      let loop = data.span.loopInfo
      loop.sourceSpan != 0 and candidate.header <= loop.exitHeader and loop.exitHeader <=
          candidate.terminal
    of NativeKind.RegisterRing:
      for index in 0..2:
        let item = data.ring.blocks[index]
        if readOverlapsBlock(candidate, item.header, item.first, item.span): return true
      false
    of NativeKind.CheckedReadBody:
      let body = readCertificate(data.readProof)
      if readIntervalsOverlap(candidate, body.info): return true
      let next = body.continuationInfo
      if body.info.last == high(uint32): return true
      next.terminal != 0 and readOverlapsBlock(candidate, next.header, body.info.last+1,
        NativeReadContinuationSpan)
    else:
      true

  func nativeReadObservationGuardHeader*(session: NativeSession): uint32 =
    ## The real frame must also protect the original complete checked successor's source interval.
    let data {.cursor.} = session.data
    if data == nil or data.state != NativeState.Ready: return NativeEntryLimit
    when NativeReadCycleEnabled:
      if data.imageKey.kind == NativeKind.ConnectedReadCycle:
        return data.readProof.layout.outsideHeader
    if data.imageKey.kind == NativeKind.ClosedRegisterLoop:
      return data.span.loopInfo.exitHeader
    NativeEntryLimit

  func nativeReadBodyObservationOverlaps*(session: NativeSession, candidate: NativeReadBody): bool =
    ## Optional checked continuation geometry is protected as part of a candidate's complete proof.
    if nativeReadObservationOverlaps(session, candidate.info): return true
    let next = candidate.continuationInfo
    if next.terminal == 0: return false
    let last = candidate.info.last
    if last > high(uint32)-NativeReadContinuationSpan: return true
    nativeReadObservationOverlaps(session, NativeReadBodyInfo(header: next.header,
      terminal: next.terminal, first: last+1, last: last+NativeReadContinuationSpan,
      epoch: candidate.info.epoch))

  when NativeReadCycleEnabled:
    func nativeReadCycleObservationOverlaps*(session: NativeSession,
        candidate: NativeReadCycle): bool =
      ## A later connected route must be disjoint from every incumbent protected block as well as Read.
      if nativeReadObservationOverlaps(session, candidate.read.info): return true
      for role in NativeCycleRole:
        let site = candidate.layout.sites[role]
        let span = uint32(NativeCycleSpans[role])
        if site.header > high(uint32)-span or site.first > high(uint32)-span: return true
        let part = NativeReadBodyInfo(header: site.header, terminal: site.header+span,
          first: site.first, last: site.first+span-1, epoch: candidate.read.info.epoch)
        if nativeReadObservationOverlaps(session, part): return true
      false

when NativeReadCycleEnabled:
  func mixedLoopPrimaryReady*(session: NativeSession): bool =
    ## An auxiliary image is always subordinate to the current connected Read ticket.
    matchesNativeImage(session, nativeInstalledKey(session), NativeKind.ConnectedReadCycle)

  func mixedLoopDisjoint*(session: NativeSession, proof: NativeMixedLoop): bool =
    ## Preserve original authority for every incumbent protected source interval.
    not nativeReadObservationOverlaps(session, NativeReadBodyInfo(
      header: proof.header, terminal: proof.terminal, first: proof.first,
      last: proof.first+uint32(proof.span)-1, epoch: proof.epoch))

  proc offerNativeMixedLoop*(session: NativeSession, proof: NativeMixedLoop): bool =
    ## Queue under the exact installed Read ticket and stream epoch. Require an idle primary
    ## mailbox and leave one usable primary credit. The proof copies source facts only.
    if not mixedLoopPrimaryReady(session) or not proof.complete or not mixedLoopDisjoint(session, proof):
      return false
    let data {.cursor.} = session.data
    assert data != nil and data.slot >= 0
    let anchor {.cursor.} = data.runtime
    assert anchor != nil
    let runtime = addr anchor.storage
    acquire(runtime.lock)
    if runtime.stopping or runtime.work != WorkPhase.Idle or runtime.mixedKey.generation != 0 or
        runtime.nextTicket == high(uint64) or freeNativeCredits(runtime) < 2 or
        mixedLoopRefused(runtime.slots[data.slot].mixedRefusals, proof.header):
      release(runtime.lock)
      return false
    var slot = 0
    while runtime.slots[slot].state != Free or runtime.slots[slot].generation == high(uint64):
      inc slot
    assert runtime.slots[data.slot].location == CompletionLocation.Installed and
      runtime.slots[slot].location == CompletionLocation.Empty
    inc runtime.slots[slot].generation
    inc runtime.nextTicket
    let key = JobKey(slot: slot, generation: runtime.slots[slot].generation,
      epoch: data.epoch, ticket: runtime.nextTicket, kind: NativeKind.MixedSelfLoop)
    runtime.mixedKey = key
    runtime.mixedOwner = runtime.slots[data.slot].key
    runtime.mixedProof = proof
    runtime.slots[slot].key = key
    runtime.slots[slot].state = Live
    runtime.slots[slot].location = CompletionLocation.Queued
    if runtime.submitted < high(uint64): inc runtime.submitted
    data.mixedOffered = true
    signal(runtime.changed)
    release(runtime.lock)
    true

  proc observeMixedPublication(data: var NativeSessionStorage, key: JobKey) =
    ## Record each exact physical publication on its first owner observation.
    if sameKey(data.mixedObserved, key): return
    data.mixedObserved = key
    if data.mixedPublications < high(uint64): inc data.mixedPublications

  type NativeMixedLoopBorrow* = object
    image*: nil ptr NativeImage
    refused*: bool

  proc borrowNativeMixedLoop*(session: NativeSession,
      proof: NativeMixedLoop): NativeMixedLoopBorrow =
    ## Try once for the exact completed ticket and proof in the current owner epoch.
    ## Pressure may revoke the image during the segment. Unmapping waits for its return.
    result = default(NativeMixedLoopBorrow)
    if not mixedLoopPrimaryReady(session): return
    let data {.cursor.} = session.data
    assert data != nil and data.slot >= 0
    let anchor {.cursor.} = data.runtime
    assert anchor != nil
    let runtime = addr anchor.storage
    if not tryAcquire(runtime.lock): return
    let key = runtime.mixedKey
    if not runtime.stopping and key.generation != 0 and not runtime.mixedBorrowed and
        runtime.slots[key.slot].location == CompletionLocation.Complete and
        not runtime.slots[key.slot].cancelled and
        sameKey(runtime.mixedOwner, runtime.slots[data.slot].key) and runtime.mixedProof == proof:
      assert matchesRow(runtime, key) and runtime.slots[key.slot].completion.ready
      runtime.mixedBorrowed = true
      observeMixedPublication(data[], key)
      result.image = addr runtime.slots[key.slot].completion
    else:
      result.refused = mixedLoopRefused(runtime.slots[data.slot].mixedRefusals, proof.header)
    release(runtime.lock)

  proc returnNativeMixedLoop*(session: NativeSession) =
    ## The frame restores the original checked handler before releasing the borrow.
    ## Complete any pending revocation while retaining the credit until unmapping.
    let data {.cursor.} = session.data
    assert data != nil and data.invocation and data.slot >= 0
    let anchor {.cursor.} = data.runtime
    assert anchor != nil
    let runtime = addr anchor.storage
    acquire(runtime.lock)
    let key = runtime.mixedKey
    assert key.generation != 0 and runtime.mixedBorrowed and
      sameKey(runtime.mixedOwner, runtime.slots[data.slot].key) and
      runtime.slots[key.slot].location == CompletionLocation.Complete
    runtime.mixedBorrowed = false
    if runtime.slots[key.slot].cancelled: retireMixedLoopLocked(runtime)
    release(runtime.lock)

proc beginNativeInvocation*(session: NativeSession, budget: uint64) =
  ## Lease the runtime for the whole public call, even during unregistered checked execution.
  ## The source epoch binds proof and nominations. A credit is acquired separately when
  ## an eligible request can actually queue. Entry requires its own installed-image checks.
  let data {.cursor.} = session.data
  if data == nil: return
  assert not data.invocation
  let anchor {.cursor.} = data.runtime
  if anchor == nil: return
  let runtime = addr anchor.storage
  acquire(runtime.lock)
  if runtime.started and not runtime.stopping and runtime.active < high(int):
    inc runtime.active
    data.invocation = true
    data.invocationUsed = false
    data.invocationQualified = false
    data.invocationImageKey = default(NativeImageKey)
    data.invocationWork = 0
    data.invocationBudget = budget
    data.workValid = true
    when NativeCheckedReadEnabled:
      # A retained nomination must be rebound to this invocation's restored source stream before retry.
      data.readValidated = false
      # Ordinary calls invalidate availability without clearing the inactive discovery table.
      data.readDiscovery.active = false
      data.laterRead.observed = false
      data.laterRead.validated = false
    # Coarse shared horizon is necessary, not a claim of candidate-specific measured profitability.
    data.allowed = budget >= NativeInvocationFloor and data.provenWork >= NativeInvocationFloor
  # Closed observation must not erase terminal Unavailable state or implicitly retry failed lowering
  # when an explicitly restarted empty runtime later accepts this still-unregistered source.
  release(runtime.lock)
  if data.invocation:
    collectNative(session)
    if data.allowed: data.invocationImageKey = nativeInstalledKey(session)

proc considerNativeSpan*(session: NativeSession, span: NativeSpan) =
  ## Keep one structural pure candidate per source epoch; profit deferral does not buy emission work.
  let data {.cursor.} = session.data
  if data == nil or not data.invocation or data.state != NativeState.Deferred: return
  if data.span.len == 0 and span.len >= NativeMinimumOperations and span.epoch == data.epoch:
    data.span = span

func nativePromotionOpen*(session: NativeSession): bool =
  ## Deferred zero-ticket storage is caller-owned. Queued and completed requests remain immutable.
  let data {.cursor.} = session.data
  if data == nil: return false
  data.invocation and data.state == NativeState.Deferred and data.ticket == 0 and
    not data.image.ready and data.span.len >= NativeMinimumOperations and
    data.span.epoch == data.epoch and data.span.kind == NativeKind.PurePrefix

proc promoteNativeLoop*(session: NativeSession, loop: NativeLoopInfo) =
  ## The checked stream verified this certificate against the already selected prefix.
  if not nativePromotionOpen(session): return
  let data {.cursor.} = session.data
  assert data != nil
  if loop.header < NativeEntryLimit and loop.header+1 == data.span.entry and
      loop.sourceSpan == uint32(data.span.len)+1:
    data.span.promote(loop)

when NativeCheckedReadEnabled:
  func nativeRingAdmissionEpoch*(session: NativeSession): uint64 =
    ## Only deferred owner storage can retain a newly observed complete checked round.
    let data {.cursor.} = session.data
    if data == nil or not data.invocation or data.state != NativeState.Deferred or
        data.ticket != 0 or data.image.ready or data.ringEpoch != 0 or
        data.invocationBudget < NativeInvocationFloor or
        data.span.kind == NativeKind.ClosedRegisterLoop:
      return 0'u64
    data.epoch

  proc nominateNativeRing*(session: NativeSession, ring: NativeRegisterRing, epoch: uint64) =
    ## Keep a single exact source-bound ring, with no new image or worker credit.
    let data {.cursor.} = session.data
    if data != nil and epoch != 0 and nativeRingAdmissionEpoch(session) == epoch and ring.complete:
      data.ring = ring
      data.ringEpoch = epoch

  func nativeReadAdmissionEpoch*(session: NativeSession): uint64 =
    ## Deferred selection and armed later-region observation have separate proof storage.
    let data {.cursor.} = session.data
    if data == nil: return 0'u64
    if nativeReplacementObservation(session): return data.epoch
    if not data.invocation or data.state != NativeState.Deferred or
        data.ticket != 0 or data.image.ready or data.invocationBudget < NativeInvocationFloor or
        readCertificate(data.readProof).complete: return 0'u64
    data.epoch

  proc considerLaterRead(data: NativeSessionData, proof: NativeReadStorage, kind: NativeKind) =
    ## Require two consecutive observations of the same qualified certificate and incumbent key.
    if data.laterRead.observed: return
    when NativeReadCycleEnabled:
      if kind == NativeKind.ConnectedReadCycle and data.image.kind == kind and
          sameNativeReadCycle(data.readProof, proof): return
    if kind == NativeKind.CheckedReadBody and data.image.kind == kind and
        readCertificate(data.readProof).sameReadBody(readCertificate(proof)): return
    var same = data.laterRead.streak != 0 and data.laterRead.incumbent == data.imageKey and
      data.laterRead.kind == kind
    when NativeReadCycleEnabled:
      if kind == NativeKind.ConnectedReadCycle:
        same = same and sameNativeReadCycle(data.laterRead.proof, proof)
      else:
        same = same and readCertificate(data.laterRead.proof).sameReadBody(readCertificate(proof))
    else:
      same = same and data.laterRead.proof.sameReadBody(proof)
    if same:
      data.laterRead.streak = 2'u8
      data.laterRead.observed = true
    else:
      data.laterRead = NativeReadCandidate(proof: proof, incumbent: data.imageKey,
        kind: kind, streak: 1'u8, observed: true)

  func nativeReplacementReadInfo*(session: NativeSession): NativeReadBodyInfo =
    ## Only this call's twice-qualified candidate may request real-frame final validation.
    let data {.cursor.} = session.data
    if data == nil or not nativeReplacementObservation(session) or
        not data.laterRead.observed or data.laterRead.streak != 2 or
        data.laterRead.incumbent != data.imageKey:
      return default(NativeReadBodyInfo)
    readCertificate(data.laterRead.proof).info

  func nativeReplacementContinuation*(session: NativeSession): NativeReadContinuation =
    ## Copy candidate geometry without exposing or mutating either proof owner.
    let data {.cursor.} = session.data
    assert data != nil and nativeReplacementReadInfo(session).epoch != 0
    readCertificate(data.laterRead.proof).continuationInfo

  proc validateNativeReplacementRead*(session: NativeSession, body: NativeReadBody): bool =
    ## The real frame must reproduce every copied candidate operand after restoring old patches.
    let data {.cursor.} = session.data
    if data == nil or nativeReplacementReadInfo(session).epoch == 0: return false
    result = data.laterRead.kind == NativeKind.CheckedReadBody and
      not nativeReadBodyObservationOverlaps(session, body) and
      readCertificate(data.laterRead.proof).sameReadBody(body)
    data.laterRead.validated = result

  proc nominateNativeRead*(session: NativeSession, body: NativeReadBody) =
    ## Initial nominations own deferred storage; replacement nominations own a separate bounded record.
    let data {.cursor.} = session.data
    if data == nil or not body.complete or nativeReadAdmissionEpoch(session) != body.info.epoch:
      return
    if data.state == NativeState.Ready:
      if nativeReadBodyObservationOverlaps(session, body): return
      var proof = default(NativeReadStorage)
      readCertificate(proof) = body
      considerLaterRead(data, proof, NativeKind.CheckedReadBody)
      return
    readCertificate(data.readProof) = body
    when NativeReadCycleEnabled:
      data.readRouteValid = false
    data.readNominated = true
    data.readValidated = true

  func deferredNativeReadInfo*(session: NativeSession): NativeReadBodyInfo =
    ## Copy only retained coordinates for bounded source revalidation, never another discovery scan.
    let data {.cursor.} = session.data
    if data == nil or not data.invocation or data.state != NativeState.Deferred or
        not data.readNominated or data.ticket != 0 or data.image.ready or
        data.invocationBudget < NativeInvocationFloor: return default(NativeReadBodyInfo)
    readCertificate(data.readProof).info

  proc validateNativeRead*(session: NativeSession, body: NativeReadBody): bool =
    ## Only an exact current source/epoch certificate permits this invocation to retry the retained read.
    let data {.cursor.} = session.data
    if data == nil or deferredNativeReadInfo(session).epoch == 0: return false
    result = body.info.epoch == data.epoch and readCertificate(data.readProof).sameReadBody(body)
    data.readValidated = result

when NativeReadCycleEnabled:
  proc nominateNativeReadCycle*(session: NativeSession, cycle: NativeReadCycle) =
    ## Retain a complete connected extension under the same deferred read admission gate.
    let data {.cursor.} = session.data
    let epoch = nativeReadAdmissionEpoch(session)
    if data == nil or epoch == 0 or not cycle.read.complete or cycle.read.info.epoch != epoch: return
    if data.state == NativeState.Ready:
      if nativeReadCycleObservationOverlaps(session, cycle): return
      considerLaterRead(data, cycle, NativeKind.ConnectedReadCycle)
      return
    data.readProof = cycle
    data.readRouteValid = true
    data.readNominated = true
    data.readValidated = true

  func nativeReplacementIsCycle*(session: NativeSession): bool =
    ## This copied tag selects only the candidate's existing typed certificate builder.
    let data {.cursor.} = session.data
    data != nil and data.laterRead.kind == NativeKind.ConnectedReadCycle and
      nativeReplacementReadInfo(session).epoch != 0

  proc validateNativeReplacementCycle*(session: NativeSession, cycle: NativeReadCycle): bool =
    ## A complete real-frame route must match the immutable copied candidate before retirement.
    let data {.cursor.} = session.data
    if data == nil or nativeReplacementReadInfo(session).epoch == 0: return false
    result = data.laterRead.kind == NativeKind.ConnectedReadCycle and
      not nativeReadCycleObservationOverlaps(session, cycle) and
      sameNativeReadCycle(data.laterRead.proof, cycle)
    data.laterRead.validated = result

  func nativeCycleNominated*(session: NativeSession): bool =
    ## Reconstruct the extended proof only while its ordinary read remains deferred.
    let data {.cursor.} = session.data
    if data == nil: return false
    data.readNominated and data.readRouteValid and readCertificate(data.readProof).complete

  proc validateNativeCycleNomination*(session: NativeSession, cycle: NativeReadCycle) =
    ## Loss of the extra geometry leaves the separately revalidated read leaf eligible.
    let data {.cursor.} = session.data
    if data == nil or not data.readNominated or not data.readValidated or
        not data.readRouteValid or data.ticket != 0: return
    if not sameNativeReadCycle(data.readProof, cycle):
      data.readRouteValid = false

func nativeScanStart*(session: NativeSession): uint32 =
  ## One monotone classification cursor prevents rescanning structurally unsupported cached nodes each call.
  let data {.cursor.} = session.data
  if data == nil: return NativeEntryLimit
  data.nextScan

proc completeNativeScan*(session: NativeSession, past: uint32) =
  ## Lazy append remains reconsiderable; destructive rebuild resets this cursor with the source epoch.
  let data {.cursor.} = session.data
  if data != nil and past > data.nextScan: data.nextScan = past

func nativeEpoch*(session: NativeSession): uint64 =
  ## This source certificate exists before registration; it grants no publication or entry authority.
  let data {.cursor.} = session.data
  if data == nil: return 0'u64
  data.epoch

proc releaseNativeCredit(data: NativeSessionData) =
  ## Detach the host's credit; cancelled worker-owned images keep their row until physical retirement.
  let anchor {.cursor.} = data.runtime
  if anchor != nil:
    discard retireOwner(addr anchor.storage, data.slot, data.generation, true, data.image)
  data.slot = -1
  data.generation = 0
  data.ticket = 0
  data.imageKey = default(NativeImageKey)

when NativeCheckedReadEnabled:
  proc discardNativeReplacement*(session: NativeSession) =
    ## A refused candidate loses only its observation streak, never the installed image's authority.
    let data {.cursor.} = session.data
    if data != nil: data.laterRead = default(NativeReadCandidate)

  proc retireNativeForReadReplacement*(session: NativeSession, key: NativeImageKey): bool =
    ## Require the exact incumbent key and a candidate revalidated on the restored frame.
    ## Its active lease prevents close while physical retirement unlocks to unmap the installed image.
    let data {.cursor.} = session.data
    if data == nil or nativeReplacementReadInfo(session).epoch == 0 or
        not data.invocationQualified or not data.laterRead.validated or data.imageKey != key:
      return false
    let anchor {.cursor.} = data.runtime
    if anchor == nil: return false
    let runtime = addr anchor.storage
    let job = JobKey(slot: key.slot, generation: key.generation, ticket: key.ticket,
      epoch: key.epoch, kind: key.kind)
    acquire(runtime.lock)
    let installed = runtime.started and not runtime.stopping and runtime.active > 0 and
      matchesRow(runtime, job) and runtime.slots[key.slot].state == Live and
      runtime.slots[key.slot].location == CompletionLocation.Installed
    release(runtime.lock)
    if not installed: return false
    # No worker can mutate an Installed row. Serialized host use and the still-active lease
    # preserve this exact key through retireOwner's unlocked physical-unmapping window.
    let retired = retireOwner(runtime, data.slot, data.generation, true, data.image)
    assert retired == Detached and not data.image.ready
    data.slot = -1
    data.generation = 0
    data.ticket = 0
    data.imageKey = default(NativeImageKey)
    data.readProof = data.laterRead.proof
    when NativeReadCycleEnabled:
      data.readRouteValid = data.laterRead.kind == NativeKind.ConnectedReadCycle
    data.ringEpoch = 0
    data.readNominated = true
    data.readValidated = true
    data.replacedRead = true
    data.replacementArmed = false
    data.laterRead = default(NativeReadCandidate)
    data.state = NativeState.Deferred
    true

proc invalidateNativeStream*(session: NativeSession) =
  ## Destructive same-plan repricing/rebuild invalidates a pending image without waiting for its worker.
  let data {.cursor.} = session.data
  if data == nil: return
  let anchor {.cursor.} = data.runtime
  if anchor == nil: return
  releaseNativeCredit(data)
  data.span = default(NativeSpan)
  when NativeCheckedReadEnabled:
    clearReadCertificate(data)
    data.readNominated = false
    data.readValidated = false
    data.ringEpoch = 0
    data.laterRead = default(NativeReadCandidate)
    data.replacementArmed = false
    data.replacedRead = false
  data.nextScan = 0
  data.ticket = 0
  data.provenWork = 0
  data.allowed = false
  if data.epoch == high(uint64): data.state = NativeState.Unavailable
  else:
    inc data.epoch
    data.state = NativeState.Deferred

proc collectNative(session: NativeSession) =
  ## At an invocation boundary, try to collect the completion for the exact registration,
  ## ticket, source epoch and ABI. A busy lock or unfinished job leaves checked execution
  ## available without waiting. A failed image retires its credit and leaves Unavailable.
  let data {.cursor.} = session.data
  if data == nil or data.ticket == 0 or data.slot < 0: return
  let anchor {.cursor.} = data.runtime
  if anchor == nil: return
  let runtime = addr anchor.storage
  if not tryAcquire(runtime.lock): return
  let key = JobKey(slot: data.slot, generation: data.generation, ticket: data.ticket,
    epoch: data.epoch, kind: acceptedKind(data))
  if not matchesRow(runtime, key) or runtime.slots[data.slot].state != Live or
      runtime.slots[data.slot].location != CompletionLocation.Complete or
      runtime.slots[data.slot].cancelled:
    release(runtime.lock)
    return
  assert not data.image.ready
  # A wrong ready ABI leaves the image with its registration until retirement.
  if runtime.slots[data.slot].completion.ready and
      runtime.slots[data.slot].completion.kind != key.kind:
    release(runtime.lock)
    return
  if runtime.slots[data.slot].completion.ready:
    # Keep the exact key until installed-image retirement; the row cannot submit another job.
    data.image = move(runtime.slots[data.slot].completion)
    data.imageKey = NativeImageKey(slot: key.slot, generation: key.generation,
      ticket: key.ticket, epoch: key.epoch, kind: key.kind)
    data.state = NativeState.Ready
    runtime.slots[data.slot].location = CompletionLocation.Installed
    if data.publications < high(uint64): inc data.publications
    data.ticket = 0
    release(runtime.lock)
  else:
    # No automatic retry. The exact failed completion releases its credit via ordinary retirement,
    # outside this mutex, so a retained Unavailable owner cannot strand unused image capacity.
    data.state = NativeState.Unavailable
    release(runtime.lock)
    releaseNativeCredit(data)

proc recordNativeWork*(session: NativeSession, completed: uint64) =
  ## Add disjoint settled checked segment receipts, never the public initial budget at every host resume.
  let data {.cursor.} = session.data
  if data == nil or not data.invocation or not data.workValid: return
  if data.invocationWork > data.invocationBudget or completed >
      data.invocationBudget-data.invocationWork:
    data.workValid = false
    data.invocationWork = 0
  else: data.invocationWork += completed

func observedNativeWork*(session: NativeSession): uint64 =
  ## Invalid/local/unsupported receipt paths never manufacture an admission credit.
  let data {.cursor.} = session.data
  if data == nil or not data.workValid: return 0
  data.invocationWork

proc nativeState*(session: NativeSession): NativeState =
  ## Default has no registered source, distinct from a deferred or ready native candidate.
  let data {.cursor.} = session.data
  if data == nil: return NativeState.Absent
  let anchor {.cursor.} = data.runtime
  if anchor == nil: return NativeState.Absent
  let runtime = addr anchor.storage
  acquire(runtime.lock)
  let open = runtime.started and not runtime.stopping
  release(runtime.lock)
  if not open: return NativeState.Closed
  data.state

proc finishNativeInvocation*(session: NativeSession, completedWork: uint64) =
  ## Gate scheduling on settled work from a single public call of this source epoch.
  ## Queue admission and active-lease release share the mutex. A busy slot or full
  ## credit table leaves execution checked and eligible evidence available for retry.
  ## A submission fixes one immutable ticket. Only the real-frame later-Read boundary may
  ## first retire an unused installed image; admission here never evicts another consumer.
  let data {.cursor.} = session.data
  if data == nil or not data.invocation: return
  collectNative(session)
  # Keep a source/epoch-bound maximum of ONE call, not the immediately prior input or a lifetime sum.
  # Short inputs neither manufacture eligibility nor revoke a genuinely long same-source observation.
  data.provenWork = max(data.provenWork, completedWork)
  when NativeCheckedReadEnabled:
    # A complete checked halt with settled work at the floor and the same unused image can arm
    # discovery. An unqualified call or missing observation clears the previous streak.
    # Physical retirement consumes the epoch's one replacement until stream invalidation.
    let unused = not data.replacedRead and data.state == NativeState.Ready and data.image.ready and
      data.invocationImageKey.ticket != 0 and data.invocationImageKey == data.imageKey and
      data.invocationQualified and completedWork >= NativeInvocationFloor and
          not data.invocationUsed
    if unused:
      data.replacementArmed = true
      if not data.laterRead.observed: data.laterRead = default(NativeReadCandidate)
    else:
      data.replacementArmed = false
      data.laterRead = default(NativeReadCandidate)
  let anchor {.cursor.} = data.runtime
  assert anchor != nil
  let runtime = addr anchor.storage
  let selectRead = when NativeCheckedReadEnabled:
    data.readNominated and data.readValidated and completedWork >= NativeInvocationFloor and
      (data.span.kind != NativeKind.ClosedRegisterLoop or data.replacedRead)
  else:
    false
  let waitingRead = when NativeCheckedReadEnabled:
    data.readNominated and (data.span.kind != NativeKind.ClosedRegisterLoop or data.replacedRead)
  else:
    false
  let selectRing = when NativeCheckedReadEnabled:
    not waitingRead and data.span.kind == NativeKind.PurePrefix and data.ringEpoch == data.epoch
  else:
    false
  # Preserve read and certified self-loop precedence. A real ring outranks a bare pure prefix.
  let candidate = if waitingRead: selectRead
    else: selectRing or data.span.len >= NativeMinimumOperations
  # Check admission under the mutex already required to release this invocation's lease.
  var submitted = false
  acquire(runtime.lock)
  template primaryCanQueue(): bool =
    runtime.started and not runtime.stopping and runtime.work == WorkPhase.Idle and
      data.state == NativeState.Deferred and candidate and
      completedWork > 0 and data.provenWork >= NativeInvocationFloor and
      runtime.nextTicket < high(uint64)
  when NativeReadCycleEnabled:
    if primaryCanQueue() and runtime.mixedKey.generation != 0 and freeNativeCredits(runtime) <= 1:
      retireMixedLoopLocked(runtime)
  # A physical optional release drops and reacquires the lock. Recheck the full predicate.
  if primaryCanQueue() and registerSession(runtime, data):
    inc runtime.nextTicket
    assert not data.image.ready and not runtime.slots[data.slot].completion.ready
    # Selection is fixed for this ticket. Only the selected ABI crosses the mailbox.
    template stockKind(): NativeKind =
      if selectRead: NativeKind.CheckedReadBody
      elif selectRing: NativeKind.RegisterRing
      else: data.span.kind
    when NativeReadCycleEnabled:
      let selectCycle = selectRead and data.readRouteValid and readCertificate(
          data.readProof).complete
      let kind = if selectCycle: NativeKind.ConnectedReadCycle else: stockKind()
    else:
      let kind = stockKind()
    let key = JobKey(slot: data.slot, generation: data.generation, ticket: runtime.nextTicket,
      epoch: data.epoch, kind: kind)
    when NativeCheckedReadEnabled:
      if selectRead:
        when NativeReadCycleEnabled:
          if selectCycle: runtime.request.readProof = data.readProof
          else: readCertificate(runtime.request.readProof) = readCertificate(data.readProof)
        else:
          readCertificate(runtime.request.readProof) = readCertificate(data.readProof)
      elif selectRing:
        runtime.request.ring = data.ring
        runtime.request.ringEpoch = data.ringEpoch
      else:
        runtime.request.span = data.span
      if not selectRing: data.ringEpoch = 0
    else:
      runtime.request.span = data.span
    assert requestMatches(runtime.request, key)
    runtime.key = key
    runtime.slots[data.slot].key = key
    when NativeReadCycleEnabled:
      runtime.slots[data.slot].mixedRefusals = default(array[NativeMixedLoopCandidateLimit, uint32])
    runtime.slots[data.slot].cancelled = false
    runtime.slots[data.slot].location = CompletionLocation.Queued
    runtime.work = WorkPhase.Queued
    data.ticket = key.ticket
    data.state = NativeState.Pending
    submitted = true
    if runtime.submitted < high(uint64): inc runtime.submitted
    signal(runtime.changed)
  when NativeCheckedReadEnabled:
    if data.readNominated and submitted:
      # Submission fixes the selected ABI; occupied work slots retain the qualified copied nomination.
      if not selectRead:
        clearReadCertificate(data)
      data.readNominated = false
    data.readValidated = false
  assert runtime.active > 0
  dec runtime.active
  data.invocation = false
  data.allowed = false
  release(runtime.lock)

func nativeSpanReady*(session: NativeSession): bool =
  ## Ready is separate from this invocation's conservative horizon; neither forces a losing short call.
  let data {.cursor.} = session.data
  if data == nil: return false
  data.invocation and data.allowed and data.state == NativeState.Ready and
    data.image.kind == data.span.kind

func nativeSpanInfo*(session: NativeSession): NativeSpanInfo =
  ## Native entry copies only scalar coordinates, not the fixed64-operation compiler request.
  let data {.cursor.} = session.data
  if data == nil: return default(NativeSpanInfo)
  info(data.span)

func nativeLoopInfo*(session: NativeSession): NativeLoopInfo =
  ## Copy the loop certificate separately so pure entry keeps its original small scalar view.
  let data {.cursor.} = session.data
  if data == nil: return default(NativeLoopInfo)
  data.span.loopInfo

func matchesNativeOperation*(session: NativeSession, index: int, opcode: byte,
    slots: RegisterSlots, immediate: uint64): bool =
  ## Consumer revalidates every copied semantic operation against its current immutable source facts.
  let data {.cursor.} = session.data
  if data == nil or index < 0 or index >= data.span.len: return false
  let op = data.span.operation(index)
  op.opcode == opcode and op.slots == slots and op.immediate == immediate

proc runNativeSpan*(session: NativeSession, registers: var RegisterFile) =
  ## The common checked bridge proves span/reservation before the backend sees fresh registers.
  let data {.cursor.} = session.data
  assert data != nil and nativeSpanReady(session) and
    matchesNativeImage(session, data.imageKey, NativeKind.PurePrefix)
  enterNative(data.image, registers)
  data.invocationUsed = true
  if data.calls < high(uint64): inc data.calls
  if data.operations <= high(uint64)-uint64(data.span.len): data.operations += uint64(data.span.len)

func validLoopReceipt(loop: NativeLoopInfo, destination: uint32, gas, remaining: uint64,
    context: NativeLoopContext, left, right: uint64): bool =
  ## Exact quotient checks prove the subsequent products before any accounting is committed.
  let span = uint64(loop.sourceSpan)
  if span == 0 or context.visits == 0 or context.gas > gas or context.remaining > remaining or
      remaining > high(uint64)-span: return false
  let extra = context.visits-1
  let quotaDelta = remaining-context.remaining
  let gasDelta = gas-context.gas
  if extra > quotaDelta div span or extra*span != quotaDelta: return false
  if loop.price == 0:
    if gasDelta != 0: return false
  elif extra > gasDelta div loop.price or extra*loop.price != gasDelta:
    return false
  if destination == loop.exitHeader: return left >= right
  destination == loop.header and left < right and
    (context.remaining < span or context.gas < loop.price)

proc runNativeLoop*(session: NativeSession, registers: var RegisterFile,
    context: var NativeLoopContext): uint32 =
  ## Only a validated receipt can return to checked dispatch or credit physical activity.
  let data {.cursor.} = session.data
  if data == nil or not nativeSpanReady(session) or
      not matchesNativeImage(session, data.imageKey,
          NativeKind.ClosedRegisterLoop): abortNativeReceipt()
  let loop = data.span.loopInfo
  let gas = context.gas
  let remaining = context.remaining
  if loop.kind != NativeKind.ClosedRegisterLoop or
      remaining > high(uint64)-uint64(loop.sourceSpan): abortNativeReceipt()
  result = enterNativeLoop(data.image, registers, context)
  let left = uint64(registers[loop.slots.aIndex])
  let right = if loop.rightKind == NativeLoopRightKind.Immediate: loop.rightImmediate
    else: uint64(registers[loop.slots.bIndex])
  if not validLoopReceipt(loop, result, gas, remaining, context, left, right):
    abortNativeReceipt()
  # Exact quota accounting plus the checked first reservation bound visits*sourceSpan.
  let operations = context.visits*uint64(loop.sourceSpan)
  data.invocationUsed = true
  if data.calls < high(uint64): inc data.calls
  if data.branchCalls < high(uint64): inc data.branchCalls
  if context.visits > 1 and data.headerCalls < high(uint64): inc data.headerCalls
  if data.operations <= high(uint64)-operations: data.operations += operations

when NativeReadCycleEnabled:
  func addNativeCount(left, right: uint64): uint64 {.inline.} =
    if right > high(uint64)-left: high(uint64) else: left+right

func nativeControlStatistics*(session: NativeSession): NativeControlStatistics =
  ## Copied counters for the quiescent public owner; no completion collection or waits.
  let data {.cursor.} = session.data
  if data == nil: return default(NativeControlStatistics)
  when NativeReadCycleEnabled:
    NativeControlStatistics(branchCalls: addNativeCount(data.branchCalls, data.mixedCalls),
      headerCalls: addNativeCount(data.headerCalls, data.mixedHeaderCalls))
  else:
    NativeControlStatistics(branchCalls: data.branchCalls, headerCalls: data.headerCalls)

when NativeCheckedReadEnabled:
  func nativeRingReady(session: NativeSession): bool =
    ## A ready ring is usable only under this invocation's existing work horizon and exact epoch.
    let data {.cursor.} = session.data
    if data == nil: return false
    data.invocation and data.allowed and data.state == NativeState.Ready and
      data.ringEpoch == data.epoch and data.image.kind == NativeKind.RegisterRing

  func nativeRingInfo*(session: NativeSession): NativeRegisterRing =
    ## Compare the image-bound proof to the restored checked stream before its first entry.
    let data {.cursor.} = session.data
    if data != nil and nativeRingReady(session): return nativeRegisterRingCertificate(data.image)
    default(NativeRegisterRing)

  func nativeRingRotation*(session: NativeSession, header: uint32): uint64 =
    ## The installed image maps an original charged header to a bounded rotation.
    let data {.cursor.} = session.data
    if data != nil and nativeRingReady(session): return nativeRegisterRingRotation(data.image, header)
    high(uint64)

  proc runNativeRing*(session: NativeSession, registers: var RegisterFile,
      context: var NativeRingContext): uint32 =
    ## The exact image checks the unpaid return and all debits before recording native work.
    let data {.cursor.} = session.data
    if data == nil or not nativeRingReady(session) or
        not matchesNativeImage(session, data.imageKey, NativeKind.RegisterRing): abortNativeReceipt()
    let remaining = context.remaining
    result = enterNativeRegisterRing(data.image, registers, context)
    let operations = remaining-context.remaining
    if operations == 0: return
    data.invocationUsed = true
    if data.calls < high(uint64): inc data.calls
    if data.branchCalls < high(uint64): inc data.branchCalls
    if context.visits[0]+context.visits[1]+context.visits[2] > 1 and
        data.headerCalls < high(uint64): inc data.headerCalls
    if data.operations <= high(uint64)-operations: data.operations += operations

  func nativeReadInfo*(session: NativeSession): NativeReadBodyInfo =
    ## An installed, permitted read image exposes only its copied geometry.
    let data {.cursor.} = session.data
    if data == nil or not data.invocation or not data.allowed or data.state != NativeState.Ready or
        not data.image.isReadBody:
      return default(NativeReadBodyInfo)
    readCertificate(data.readProof).info

  func nativeReadContinuation*(session: NativeSession): NativeReadContinuation {.inline.} =
    ## The caller has already verified the ready read image through nativeReadInfo.
    let data {.cursor.} = session.data
    assert data != nil
    readCertificate(data.readProof).continuationInfo

  func matchesNativeReadBody*(session: NativeSession, body: NativeReadBody): bool =
    ## Install compares the rebuilt source certificate and every copied operand.
    let data {.cursor.} = session.data
    data != nil and readCertificate(data.readProof).sameReadBody(body)

  proc runNativeReadBody*(session: NativeSession, registers: var RegisterFile,
      context: var NativeReadContext): bool =
    ## Only a completed image contributes native calls and original body operations.
    let data {.cursor.} = session.data
    assert data != nil and nativeReadInfo(session).epoch != 0 and
      matchesNativeImage(session, data.imageKey, NativeKind.CheckedReadBody)
    if not enterNativeReadBody(data.image, registers, context): return false
    data.invocationUsed = true
    if data.calls < high(uint64): inc data.calls
    let count = uint64(readCertificate(data.readProof).len)
    if data.operations <= high(uint64)-count: data.operations += count
    true

when NativeReadCycleEnabled:
  func nativeReadCycleInfo*(session: NativeSession): NativeReadBodyInfo =
    ## Expose only the first paid entry of a ready and permitted connected image.
    let data {.cursor.} = session.data
    if data == nil or not data.invocation or not data.allowed or data.state != NativeState.Ready or
        not data.readRouteValid or data.image.kind != NativeKind.ConnectedReadCycle:
      return default(NativeReadBodyInfo)
    data.readProof.read.info

  func matchesNativeReadCycle*(session: NativeSession, cycle: NativeReadCycle): bool =
    ## Install authority requires the complete copied certificate from this source epoch.
    let data {.cursor.} = session.data
    if data == nil: return false
    data.readRouteValid and sameNativeReadCycle(data.readProof, cycle)

  proc runNativeCycle*(session: NativeSession, registers: var RegisterFile,
      context: var NativeCycleContext, lastHeader: var uint32): uint32 =
    ## Validate the entered receipt before exposing its budgets and exact continuation.
    let data {.cursor.} = session.data
    assert data != nil and nativeReadCycleInfo(session).epoch != 0 and
      matchesNativeImage(session, data.imageKey, NativeKind.ConnectedReadCycle)
    let gas = context.gas
    let remaining = context.remaining
    result = enterNativeReadCycle(data.image, registers, context)
    if not validNativeCycleReceipt(data.readProof.layout, result, gas, remaining, context):
      abortNativeReceipt()
    if context.lastCompleted == NativeCycleNoCompleted: return
    let role = NativeCycleRole(context.lastCompleted)
    if nativeCycleSuccessor(data.readProof, role, registers) != result: abortNativeReceipt()
    lastHeader = data.readProof.layout.sites[role].header
    let readSpan = NativeCycleSpans[NativeCycleRole.Read]
    let spent = remaining - context.remaining
    if context.paidRead == 0 and spent > high(uint64) - readSpan: abortNativeReceipt()
    let operations = if context.paidRead == 1: spent else: spent + readSpan
    if operations != 0: data.invocationUsed = true
    if data.calls < high(uint64): inc data.calls
    if data.operations <= high(uint64) - operations: data.operations += operations
    if (context.visits[NativeCycleRole.Store] != 0 or context.visits[NativeCycleRole.Tail] != 0 or
        context.visits[NativeCycleRole.Outer] != 0 or context.visits[NativeCycleRole.Gate] != 0):
      if data.branchCalls < high(uint64): inc data.branchCalls
      if hasNativeCycleBackedge(context.visits) and data.headerCalls < high(uint64):
        inc data.headerCalls

proc nativeStatistics*(session: NativeSession): array[5, uint64] =
  ## Copy quiescent shared image/activity counters; compilation CPU is not fabricated from a process clock.
  let data {.cursor.} = session.data
  if data == nil: return default(array[5, uint64])
  [data.publications, data.calls, data.operations, data.image.codeBytes, 0'u64]

when NativeReadCycleEnabled:
  proc recordNativeMixedLoop*(session: NativeSession, operations: uint64, repeatedHeader: bool) =
    ## Count one physical call and all original attempted facts in a validated nonempty receipt.
    ## The checked continuation contributes no native work.
    let data {.cursor.} = session.data
    if data == nil: return
    assert data.invocation and operations > 0
    if data.mixedCalls < high(uint64): inc data.mixedCalls
    if repeatedHeader and data.mixedHeaderCalls < high(uint64): inc data.mixedHeaderCalls
    data.mixedOperations = addNativeCount(data.mixedOperations, operations)

proc nativeOperationCount*(session: NativeSession): uint64 {.inline.} =
  ## Actual execution detection needs only owner-local counters, even during a runtime borrow.
  let data {.cursor.} = session.data
  if data == nil: return 0
  when NativeReadCycleEnabled: addNativeCount(data.operations, data.mixedOperations)
  else: data.operations

proc nativeOwnerStatistics*(session: NativeSession): array[5, uint64] =
  ## Count each observed auxiliary publication once per ticket. Read current auxiliary
  ## occupancy under the runtime lock only after this owner has offered an auxiliary.
  result = nativeStatistics(session)
  when NativeReadCycleEnabled:
    let data {.cursor.} = session.data
    if data == nil: return
    result[1] = addNativeCount(result[1], data.mixedCalls)
    result[2] = addNativeCount(result[2], data.mixedOperations)
    if data.mixedOffered:
      let anchor {.cursor.} = data.runtime
      if anchor != nil and data.slot >= 0:
        let runtime = addr anchor.storage
        acquire(runtime.lock)
        let key = runtime.mixedKey
        if key.generation != 0 and sameKey(runtime.mixedOwner, runtime.slots[data.slot].key):
          if runtime.slots[key.slot].location == CompletionLocation.Complete:
            assert matchesRow(runtime, key) and runtime.slots[key.slot].completion.ready
            observeMixedPublication(data[], key)
            result[3] += runtime.slots[key.slot].completion.codeBytes
        else:
          data.mixedOffered = false
        release(runtime.lock)
      else:
        data.mixedOffered = false
    result[0] = addNativeCount(result[0], data.mixedPublications)

when defined(pvmSharedAsyncWitness):
  proc pauseNativeCompiler*(runtime: NativeRuntime, paused: bool) =
    ## Deterministic qualification barrier, never a timing warmup or production readiness wait.
    let anchor {.cursor.} = runtime.data
    if anchor == nil: return
    let data = addr anchor.storage
    acquire(data.lock)
    data.paused = paused
    broadcast(data.changed)
    release(data.lock)

when defined(pvmSharedAsyncWitness):
  proc exhaustNativeNamespace*(runtime: NativeRuntime, tickets: bool) =
    ## Qualification-only finite-counter boundary; an idle empty namespace may never wrap IDs.
    let anchor {.cursor.} = runtime.data
    assert anchor != nil
    let data = addr anchor.storage
    acquire(data.lock)
    assert data.started and not data.stopping and data.active == 0 and data.work == WorkPhase.Idle
    for index in 0..<data.slots.len:
      assert data.slots[index].state == Free and
        data.slots[index].location == CompletionLocation.Empty
    if tickets:
      data.nextTicket = high(uint64)
    else:
      for index in 0..<data.slots.len: data.slots[index].generation = high(uint64)
    release(data.lock)

  proc waitNativeCompiler*(runtime: NativeRuntime) =
    ## Explicit qualification synchronization OUTSIDE invocation clocks; production never waits for readiness.
    let anchor {.cursor.} = runtime.data
    if anchor == nil: return
    let data = addr anchor.storage
    acquire(data.lock)
    template workPending(): bool =
      when NativeReadCycleEnabled:
        data.work != WorkPhase.Idle or (data.mixedKey.generation != 0 and
          data.slots[data.mixedKey.slot].location in {CompletionLocation.Queued,
            CompletionLocation.Running, CompletionLocation.Reclaiming})
      else:
        data.work != WorkPhase.Idle
    while data.started and workPending():
      wait(data.changed, data.lock)
    release(data.lock)

when defined(pvmSharedAsyncWitness):
  proc armNativeCompilerGate*(runtime: NativeRuntime, point: NativeCompilerPoint) =
    ## Arm one scalar compiler checkpoint before submitting work, never from a public invocation.
    let anchor {.cursor.} = runtime.data
    assert anchor != nil and point != NativeCompilerPoint.None
    let data = addr anchor.storage
    acquire(data.lock)
    assert data.started and not data.stopping and data.gate == NativeCompilerPoint.None
    data.gate = point
    data.followingGate = NativeCompilerPoint.None
    data.gateReached = false
    data.gateReleased = false
    data.observation = default(NativeCompilerObservation)
    release(data.lock)

  proc waitNativeCompilerGate*(runtime: NativeRuntime): NativeCompilerObservation =
    ## Wait OUTSIDE calls for the armed gate; copy only its saved key and local-image bit.
    let anchor {.cursor.} = runtime.data
    assert anchor != nil
    let data = addr anchor.storage
    acquire(data.lock)
    assert data.gate != NativeCompilerPoint.None
    while data.started and not data.stopping and not data.gateReached:
      wait(data.changed, data.lock)
    assert data.gateReached
    result = data.observation
    release(data.lock)

  proc releaseNativeCompilerGate*(runtime: NativeRuntime,
      following = NativeCompilerPoint.None) =
    ## Atomically resume/rearm a different next gate; never race the worker's short retirement window.
    let anchor {.cursor.} = runtime.data
    assert anchor != nil
    let data = addr anchor.storage
    acquire(data.lock)
    assert data.gateReached and data.gate != NativeCompilerPoint.None
    let previous = data.gate
    assert following != previous, "gate rearm needs a distinct acknowledged point"
    data.followingGate = following
    data.gateReleased = true
    broadcast(data.changed)
    while data.started and not data.stopping and data.gate == previous:
      wait(data.changed, data.lock)
    release(data.lock)
