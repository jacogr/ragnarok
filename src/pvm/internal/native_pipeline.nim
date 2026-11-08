# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## One shared compiler work slot, four exclusive completion credits, copied IR and a closed lifetime anchor.
## Host-side handle ownership follows the existing sequential execution-worker contract; the compiler
## touches only the locked mailbox/POD IR, never a session/Program/frame ARC graph.

import std/[assertions, locks, rawthreads]
import ../[machine, program]
import ./[native_ir, native_platform, native_read_body]
export native_ir, native_read_body

type NativeRequest = object
  ## The locked job key selects the sole live payload in this mailbox.
  span: NativeSpan
  when NativeCheckedReadEnabled:
    body: NativeReadBody

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
    when defined(pvmSharedAsyncWitness):
      paused, gateReached, gateReleased: bool
      gate, followingGate: NativeCompilerPoint
      observation: NativeCompilerObservation
  NativeRuntimeData = ref object ## The named field has a supported stable address, unlike a ref payload cast.
    storage: NativeRuntimeStorage
  NativeRuntime* = object ## Copyable host-side closed lifetime anchor; no worker refcount access.
    data: nil NativeRuntimeData
  NativeSessionStorage = object ## Exactly one registered source-policy identity; only its caller mutates it.
    runtime: nil NativeRuntimeData
    slot: int
    generation, epoch, ticket: uint64
    state: NativeState
    span: NativeSpan
    when NativeCheckedReadEnabled:
      readBody: NativeReadBody # Retained deferred nomination, then the immutable accepted certificate.
      readNominated, readValidated: bool # Source validation belongs to this invocation, not a prior stream lease.
    image: NativeImage
    invocation, allowed: bool
    provenWork, invocationWork, invocationBudget, calls, operations, publications: uint64
    branchCalls, headerCalls: uint64
    nextScan: uint32
    workValid: bool
  NativeSessionData = ref NativeSessionStorage
  NativeSession* = object ## Shared prepared identity, used exclusively under PreparedStorage.busy.
    data: nil NativeSessionData
  NativeRuntimeInfo* = object ## Copied work and parked-result activity, never a borrowed session/cache view.
    phase*: NativePhase
    registered*, active*: int
    completions*: int ## Uncollected Complete rows, including empty failed images; independent of work phase.
    submitted*, completed*: uint64
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
  of NativeKind.CheckedReadBody:
    when NativeCheckedReadEnabled:
      request.body.complete and request.body.info.epoch == key.epoch
    else:
      false

func acceptedKind(data: NativeSessionData): NativeKind =
  ## A nonzero ticket binds one immutable caller-side certificate until collection.
  assert data.ticket != 0
  when NativeCheckedReadEnabled:
    if data.readBody.complete: return NativeKind.CheckedReadBody
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
  if runtime.slots[index].state == Retiring:
    # A final drop's credit becomes reusable only after the detached/worker local was destroyed.
    runtime.slots[index].state = Free

proc retireOwner(runtime: ptr NativeRuntimeStorage, slot: int, generation: uint64,
    finalDrop: bool, image: var NativeImage): Retirement =
  ## One canonical cancellation/detach path; its caller keeps the stable runtime anchor alive.
  if slot < 0 or slot >= runtime.slots.len: return NoWork
  acquire(runtime.lock)
  if runtime.slots[slot].generation != generation or runtime.slots[slot].state != Live:
    release(runtime.lock)
    return NoWork
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

proc compilerRun(raw: pointer) =
  ## Only the worker lowers copied POD requests; completions park in their own bounded credit rows.
  let runtime = cast[ptr NativeRuntimeStorage](raw)
  acquire(runtime.lock)
  while true:
    var runnable = runtime.work == WorkPhase.Queued
    when defined(pvmSharedAsyncWitness): runnable = runnable and not runtime.paused
    while not runnable and not runtime.stopping:
      wait(runtime.changed, runtime.lock)
      runnable = runtime.work == WorkPhase.Queued
      when defined(pvmSharedAsyncWitness): runnable = runnable and not runtime.paused
    if runtime.stopping:
      release(runtime.lock)
      return
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
    of NativeKind.CheckedReadBody:
      when NativeCheckedReadEnabled:
        # Only read-capable builds own this payload, with no invocation memory borrow.
        let body = runtime.request.body
        if releaseCompilerClaim(runtime, key):
          image = lowerNativeReadBody(body)
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
  ## Start at the stable anchor address, not implicitly in a guest/source constructor.
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
  data.started = true
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
  let phase = if data.work == WorkPhase.Queued: NativePhase.Queued
    elif data.work == WorkPhase.Running: NativePhase.Running
    elif completions > 0: NativePhase.Done else: NativePhase.Idle
  result = NativeRuntimeInfo(phase: phase, registered: count, active: data.active,
    completions: completions, submitted: data.submitted, completed: data.completed)
  release(data.lock)

proc registerSession(data: NativeSessionData): bool =
  ## Capacity is reversible: an unregistered source can retry next invocation after orphan retirement.
  let anchor {.cursor.} = data.runtime
  if anchor == nil: return false
  let runtime = addr anchor.storage
  acquire(runtime.lock)
  defer: release(runtime.lock)
  if not runtime.started or runtime.stopping:
    data.state = NativeState.Closed
    return false
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
        data.state = NativeState.Deferred
        return true
  false

proc newNativeSession*(runtime: NativeRuntime): NativeSession =
  ## Retain a safe anchor, not a dangling registration; native capacity is acquired only at an invocation.
  let anchor {.cursor.} = runtime.data
  if anchor == nil: return default(NativeSession)
  NativeSession(data: NativeSessionData(runtime: anchor, slot: -1, epoch: 1,
    state: NativeState.Deferred, image: default(NativeImage)))

proc collectNative(session: NativeSession)
  ## Exact nonblocking collection is legal only at an exclusive invocation boundary.

proc beginNativeInvocation*(session: NativeSession, budget: uint64) =
  ## Whole-public-call lease prevents runtime close while a callable image/register borrow is active.
  let data {.cursor.} = session.data
  if data == nil: return
  assert not data.invocation
  if data.slot < 0 and not registerSession(data): return
  let anchor {.cursor.} = data.runtime
  if anchor == nil: return
  let runtime = addr anchor.storage
  acquire(runtime.lock)
  if runtime.started and not runtime.stopping:
    inc runtime.active
    data.invocation = true
    data.invocationWork = 0
    data.invocationBudget = budget
    data.workValid = true
    when NativeCheckedReadEnabled:
      # A retained nomination must be rebound to this invocation's restored source stream before retry.
      data.readValidated = false
    # Coarse shared horizon is necessary, not a claim of candidate-specific measured profitability.
    data.allowed = budget >= NativeInvocationFloor and data.provenWork >= NativeInvocationFloor
  else:
    data.state = NativeState.Closed
  release(runtime.lock)
  if data.invocation: collectNative(session)

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
  func nativeReadAdmissionEpoch*(session: NativeSession): uint64 =
    ## Only the exclusive deferred owner may compare an unpublished read with its incumbent.
    let data {.cursor.} = session.data
    if data == nil or not data.invocation or data.state != NativeState.Deferred or
        data.ticket != 0 or data.image.ready or data.invocationBudget < NativeInvocationFloor or
        data.readBody.complete: return 0'u64
    data.epoch

  proc nominateNativeRead*(session: NativeSession, body: NativeReadBody) =
    ## Stage this call's exact copied certificate in the same storage used for an accepted read.
    let data {.cursor.} = session.data
    if data == nil or not body.complete or nativeReadAdmissionEpoch(session) != body.info.epoch:
      return
    data.readBody = body
    data.readNominated = true
    data.readValidated = true

  func deferredNativeReadInfo*(session: NativeSession): NativeReadBodyInfo =
    ## Copy only retained coordinates for bounded source revalidation, never another discovery scan.
    let data {.cursor.} = session.data
    if data == nil or not data.invocation or data.state != NativeState.Deferred or
        not data.readNominated or data.ticket != 0 or data.image.ready or
        data.invocationBudget < NativeInvocationFloor: return default(NativeReadBodyInfo)
    data.readBody.info

  proc validateNativeRead*(session: NativeSession, body: NativeReadBody): bool =
    ## Only an exact current source/epoch certificate permits this invocation to retry the retained read.
    let data {.cursor.} = session.data
    if data == nil or deferredNativeReadInfo(session).epoch == 0: return false
    result = body.info.epoch == data.epoch and data.readBody.sameReadBody(body)
    data.readValidated = result

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
  ## Zero has no registration or publication authority.
  let data {.cursor.} = session.data
  if data == nil or data.slot < 0: return 0'u64
  data.epoch

proc invalidateNativeStream*(session: NativeSession) =
  ## Destructive same-plan repricing/rebuild invalidates a pending image without waiting for its worker.
  let data {.cursor.} = session.data
  if data == nil: return
  let anchor {.cursor.} = data.runtime
  if anchor == nil: return
  discard retireOwner(addr anchor.storage, data.slot, data.generation, false, data.image)
  data.span = default(NativeSpan)
  when NativeCheckedReadEnabled:
    data.readBody = default(NativeReadBody)
    data.readNominated = false
    data.readValidated = false
  data.nextScan = 0
  data.ticket = 0
  data.provenWork = 0
  data.allowed = false
  if data.epoch == high(uint64): data.state = NativeState.Unavailable
  else:
    inc data.epoch
    data.state = NativeState.Deferred

proc collectNative(session: NativeSession) =
  ## Exact ticket/source epoch only, at caller-side quiescence. No wait for unfinished compilation.
  let data {.cursor.} = session.data
  if data == nil or data.ticket == 0: return
  let anchor {.cursor.} = data.runtime
  if anchor == nil: return
  let runtime = addr anchor.storage
  if not tryAcquire(runtime.lock): return
  defer: release(runtime.lock)
  let key = JobKey(slot: data.slot, generation: data.generation, ticket: data.ticket,
    epoch: data.epoch, kind: acceptedKind(data))
  if not matchesRow(runtime, key) or runtime.slots[data.slot].state != Live or
      runtime.slots[data.slot].location != CompletionLocation.Complete or
      runtime.slots[data.slot].cancelled: return
  assert not data.image.ready
  # A wrong ready ABI leaves the image with its registration until retirement.
  if runtime.slots[data.slot].completion.ready and
      runtime.slots[data.slot].completion.kind != key.kind: return
  data.image = move(runtime.slots[data.slot].completion)
  data.state = if data.image.ready: NativeState.Ready else: NativeState.Unavailable
  if data.image.ready:
    # Keep the exact key until installed-image retirement; the row cannot submit another job.
    runtime.slots[data.slot].location = CompletionLocation.Installed
    if data.publications < high(uint64): inc data.publications
  else:
    # Failed lowering consumes one completion but never a publication or automatic retry.
    runtime.slots[data.slot].location = CompletionLocation.Empty
    runtime.slots[data.slot].key = default(JobKey)
  data.ticket = 0

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
  ## Conservative settled public-call work gates one background job; never lifetime tiny-call accumulation.
  let data {.cursor.} = session.data
  if data == nil or not data.invocation: return
  collectNative(session)
  # Keep a source/epoch-bound maximum of ONE call, not the immediately prior input or a lifetime sum.
  # Short inputs neither manufacture eligibility nor revoke a genuinely long same-source observation.
  data.provenWork = max(data.provenWork, completedWork)
  let anchor {.cursor.} = data.runtime
  assert anchor != nil
  let runtime = addr anchor.storage
  let selectRead = when NativeCheckedReadEnabled:
    data.readNominated and data.readValidated and completedWork >= NativeInvocationFloor and
      data.span.kind != NativeKind.ClosedRegisterLoop
  else:
    false
  let waitingRead = when NativeCheckedReadEnabled:
    data.readNominated and data.span.kind != NativeKind.ClosedRegisterLoop
  else:
    false
  # Short/failed calls cannot replace a stronger retained nomination with its pure prefix.
  let candidate = if waitingRead: selectRead else: data.span.len >= NativeMinimumOperations
  # Check admission under the mutex already required to release this invocation's lease.
  acquire(runtime.lock)
  if runtime.started and not runtime.stopping and runtime.work == WorkPhase.Idle and
      runtime.slots[data.slot].state == Live and
      runtime.slots[data.slot].generation == data.generation and
      runtime.slots[data.slot].location == CompletionLocation.Empty and
      data.state == NativeState.Deferred and candidate and
      completedWork > 0 and data.provenWork >= NativeInvocationFloor and
      runtime.nextTicket < high(uint64):
    inc runtime.nextTicket
    assert not data.image.ready and not runtime.slots[data.slot].completion.ready
    # selectRead already excludes a certified closed loop. Write only the selected payload.
    let kind = if selectRead: NativeKind.CheckedReadBody else: data.span.kind
    let key = JobKey(slot: data.slot, generation: data.generation, ticket: runtime.nextTicket,
      epoch: data.epoch, kind: kind)
    when NativeCheckedReadEnabled:
      if selectRead:
        runtime.request.body = data.readBody
      else:
        runtime.request.span = data.span
    else:
      runtime.request.span = data.span
    assert requestMatches(runtime.request, key)
    runtime.key = key
    runtime.slots[data.slot].key = key
    runtime.slots[data.slot].cancelled = false
    runtime.slots[data.slot].location = CompletionLocation.Queued
    runtime.work = WorkPhase.Queued
    data.ticket = key.ticket
    data.state = NativeState.Pending
    if runtime.submitted < high(uint64): inc runtime.submitted
    signal(runtime.changed)
  when NativeCheckedReadEnabled:
    if data.readNominated and data.ticket != 0:
      # Submission fixes the selected ABI; occupied work slots retain the qualified copied nomination.
      if not selectRead: data.readBody = default(NativeReadBody)
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
  assert data != nil and nativeSpanReady(session)
  enterNative(data.image, registers)
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
  if data == nil or not nativeSpanReady(session): abortNativeReceipt()
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
  if data.calls < high(uint64): inc data.calls
  if data.branchCalls < high(uint64): inc data.branchCalls
  if context.visits > 1 and data.headerCalls < high(uint64): inc data.headerCalls
  if data.operations <= high(uint64)-operations: data.operations += operations

func nativeControlStatistics*(session: NativeSession): NativeControlStatistics =
  ## Copied counters for the quiescent public owner; no completion collection or waits.
  let data {.cursor.} = session.data
  if data == nil: return default(NativeControlStatistics)
  NativeControlStatistics(branchCalls: data.branchCalls, headerCalls: data.headerCalls)

when NativeCheckedReadEnabled:
  func nativeReadInfo*(session: NativeSession): NativeReadBodyInfo =
    ## An installed, permitted read image exposes only its copied geometry.
    let data {.cursor.} = session.data
    if data == nil or not data.invocation or not data.allowed or data.state != NativeState.Ready or
        not data.image.isReadBody:
      return default(NativeReadBodyInfo)
    data.readBody.info

  func nativeReadContinuation*(session: NativeSession): NativeReadContinuation {.inline.} =
    ## The caller has already verified the ready read image through nativeReadInfo.
    let data {.cursor.} = session.data
    assert data != nil
    data.readBody.continuationInfo

  func matchesNativeReadBody*(session: NativeSession, body: NativeReadBody): bool =
    ## Install compares the rebuilt source certificate and every copied operand.
    let data {.cursor.} = session.data
    data != nil and data.readBody.sameReadBody(body)

  proc runNativeReadBody*(session: NativeSession, registers: var RegisterFile,
      context: var NativeReadContext): bool =
    ## Only a completed image contributes native calls and original body operations.
    let data {.cursor.} = session.data
    assert data != nil and nativeReadInfo(session).epoch != 0
    if not enterNativeReadBody(data.image, registers, context): return false
    if data.calls < high(uint64): inc data.calls
    let count = uint64(data.readBody.len)
    if data.operations <= high(uint64)-count: data.operations += count
    true

proc nativeStatistics*(session: NativeSession): array[5, uint64] =
  ## Copy quiescent shared image/activity counters; compilation CPU is not fabricated from a process clock.
  let data {.cursor.} = session.data
  if data == nil: return default(array[5, uint64])
  [data.publications, data.calls, data.operations, data.image.codeBytes, 0'u64]

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
  proc waitNativeCompiler*(runtime: NativeRuntime) =
    ## Explicit qualification synchronization OUTSIDE invocation clocks; production never waits for readiness.
    let anchor {.cursor.} = runtime.data
    if anchor == nil: return
    let data = addr anchor.storage
    acquire(data.lock)
    while data.started and data.work != WorkPhase.Idle:
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
