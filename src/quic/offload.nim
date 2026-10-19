# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Fixed two-worker proof queue. Only copied values cross threads; no stream/TLS/ARC owner does.
##
## Exposes nominal job generations and completion results, plus the feature-gated proof-pool
## submission, cancellation and polling API.

const OffloadEnabled* = defined(offload)
# Nominal generations cannot be confused with native stream handles or fixture indices.
type
  JobId* = distinct uint64
  OffloadOutcome* = enum Failed, Verified ## A failed proof cannot authorize a reply; this outcome contains no output on failure.
  OffloadCompletion* = object ## Generation is never reused during one pool lifetime, including after cancellation.
    id*: JobId
    outcome*: OffloadOutcome
  OffloadPollResult* = object ## Pending has no readable completion or generation; callers must select the ready branch.
    case hasCompletion: bool
    of true: completed: OffloadCompletion
    of false: discard
func ready*(value: OffloadPollResult): bool =
  ## Select readiness without permitting forged completions or public discriminator mutation.
  value.hasCompletion
func completion*(value: OffloadPollResult): OffloadCompletion {.inline,
    requires: value.hasCompletion.} =
  ## A pending/default poll has no readable completion; callers must establish readiness first.
  value.completed
# Compare/print only job generations; implicit integer conversion remains forbidden.
proc `==`*(a, b: JobId): bool {.borrow.}
# Diagnostic printing preserves the generation without permitting implicit integer conversion.
proc `$`*(id: JobId): string {.borrow.}
when OffloadEnabled:
  import std/[os, strutils, locks, monotimes, times, rawthreads, syncio, envvars, assertions]
  import std/posix/posix
  import ../bandersnatch/bandersnatch
  type
    # Every admitted slot owns these fixed bytes independently of caller storage.
    ProofJob = object
      root: array[144, byte]
      proof: array[784, byte]
      context: array[48, byte]
      expected: array[32, byte]
      invalid: bool
    # Running cancellation retains the slot until the synchronous Rust operation returns.
    Phase = enum Free, Queued, Running, Done
    # Completion and input have one pool owner, protected by its mutex.
    Slot = object
      job: ProofJob
      id: JobId
      phase: Phase
      cancelled: bool
      outcome: OffloadOutcome
    OffloadPool* = object ## Stack-stable owner; initialization/destruction must happen once on the I/O thread.
      lock: Lock
      changed: Cond
      workers: array[2, RawThread]
      slots: array[4, Slot]
      fixture: ProofJob
      capacity, repeats, ready, busy, discarded: int
      next: uint64
      held, stopping, setupFailed: bool
      last: array[7, int]
      gate: string
  # Mutexes, worker handles and borrowed stack pointers have exactly one stable pool owner.
  proc `=copy`*(destination: var OffloadPool, source: OffloadPool) {.error: "OffloadPool owns joined workers".}
  # Flush complete bounded public markers immediately; native I/O buffering must not hide live worker state.
  template progress() {.varargs.} =
    for field in unpack(): stdout.write(field) # Only the I/O thread emits these diagnostics.
    stdout.write('\n')
    stdout.flushFile()
  # Selftest polling owns no network dispatcher; POSIX sleep yields without adding any worker.
  proc pause() =
    var requested = Timespec(tv_sec: posix.Time(0), tv_nsec: 2_000_000)
    var remaining = default(Timespec)
    discard nanosleep(requested, remaining) # Interrupted sleeps return to the selftest's monotonic deadline.
  # Create and destroy the Rust setup on this worker; neither owner nor allocator crosses threads.
  proc worker(raw: pointer) =
    let pool = cast[ptr OffloadPool](raw) # The stack-stable pool outlives both joined workers.
    let setup = newSetup(pool.capacity)
    acquire(pool.lock)
    inc pool.ready
    if setup.error != BsError.None: pool.setupFailed = true # Initialization cannot manufacture a setup.
    broadcast(pool.changed)
    release(pool.lock)
    if setup.error != BsError.None: return # Main joins failed workers before returning initialization failure.
    defer: close(setup.value)
    while true:
      acquire(pool.lock)
      var index = -1
      # Sleep on one condition; wakeups recheck both shutdown and bounded queued work.
      while index < 0 and not pool.stopping:
        for i in 0..<4:
          if pool.slots[i].phase == Queued: index = i; break # Only one worker claims this slot under lock.
        if index < 0: wait(pool.changed, pool.lock) # No polling or per-job thread creation.
      if pool.stopping: release(pool.lock); return # Shutdown drops queued work without entering Rust.
      pool.slots[index].phase = Running
      let job = pool.slots[index].job
      # Test-only hold proves queue/cancellation ownership; it is not reported as crypto execution.
      while pool.held and not pool.stopping: wait(pool.changed, pool.lock)
      if pool.stopping:
        pool.slots[index] = Slot()
        release(pool.lock)
        return # Shutdown can release a held job before its first FFI call.
      inc pool.busy
      release(pool.lock)
      var outcome = Verified
      var context = job.context
      if job.invalid: context[0] = context[0] xor 1 # Negative fixture uses a wrong domain, never fake success.
      # Repeated real verification supplies bounded compute load, without optimizing the primitive.
      for iteration in 0..<pool.repeats:
        let checked = verifyRing(setup.value, BsRingRoot(job.root), BsRingProof(job.proof), context,
            [])
        # Failed crypto alternatives contain no readable output.
        if checked.error != BsError.None:
          outcome = Failed
          break
        # Independent official output must match before authorizing a reply.
        if array[32, byte](checked.value) != job.expected:
          outcome = Failed
          break
      acquire(pool.lock)
      dec pool.busy
      if pool.slots[index].cancelled or pool.stopping:
        inc pool.discarded
        pool.slots[index] = Slot() # Only after Rust returns can cancellation release/reuse this owner.
      else:
        pool.slots[index].outcome = outcome
        pool.slots[index].phase = Done # Uncollected completion still occupies capacity.
      release(pool.lock)
  proc startPool*(pool: var OffloadPool): bool {.raises.} =
    ## Read one trusted harness fixture before starting threads. Network bytes never choose this file/domain.
    let wire = readFile(getEnv("RAGNAROK_OFFLOAD_FIXTURE"))
    if wire.len != 1012: return false # Fixed capacity/root/proof/context/output fixture layout.
    for i in 0..<4: pool.capacity = pool.capacity or (int(byte(wire[i])) shl (
        8*i)) # Trusted little-endian capacity.
    if pool.capacity notin [6, 1023]: return false # Only pinned official fixture domains are accepted.
    pool.repeats = parseInt(getEnv("RAGNAROK_OFFLOAD_REPEATS", "1"))
    if pool.repeats < 1 or pool.repeats > 256: return false # Bound shutdown's noninterruptible crypto work.
    for i in 0..<144: pool.fixture.root[i] = byte(wire[4+i]) # Copy all bytes into the pool's stable owner.
    for i in 0..<784: pool.fixture.proof[i] = byte(wire[148+i]) # No borrowed string pointer crosses threads.
    for i in 0..<48: pool.fixture.context[i] = byte(wire[932+i]) # Native caller owns the explicit JAM domain.
    for i in 0..<32: pool.fixture.expected[i] = byte(wire[980+i]) # Independent official output assertion.
    pool.gate = getEnv("RAGNAROK_OFFLOAD_GATE")
    pool.held = pool.gate.len > 0 and not fileExists(pool.gate)
    initLock(pool.lock); initCond(pool.changed)
    var created = 0
    try:
      for i in 0..<2:
        create(pool.workers[i], worker, addr pool) # Fixed workers, independent of peers/streams.
        inc created
    except:
      # Partial OS setup joins successful siblings before the pool's stack owner retires.
      acquire(pool.lock)
      pool.stopping = true
      broadcast(pool.changed)
      release(pool.lock)
      for i in 0..<created: join(pool.workers[i]) # Only successful creations have joinable handles.
      deinitCond(pool.changed); deinitLock(pool.lock)
      return false
    acquire(pool.lock)
    while pool.ready < 2: wait(pool.changed, pool.lock) # Setup readiness precedes listener advertisement.
    result = not pool.setupFailed
    release(pool.lock)
    if not result:
      acquire(pool.lock)
      pool.stopping = true
      broadcast(pool.changed)
      release(pool.lock)
      for i in 0..<2: join(pool.workers[i]) # Both worker-owned Rust setups retire before the shared mutex.
      deinitCond(pool.changed); deinitLock(pool.lock) # Failed setup retires successful siblings too.
  proc busyPool*(pool: var OffloadPool): int {.raises: [].} =
    ## Count actual crypto activity under the same mutex; held/queued jobs are deliberately excluded.
    acquire(pool.lock)
    result = pool.busy
    release(pool.lock)
  proc stopPool*(pool: var OffloadPool) =
    ## Stop admission, cancel queued/completed work, unblock test holds, and join before releasing mutexes.
    acquire(pool.lock)
    pool.stopping = true
    pool.held = false
    for index in 0..<4:
      let slot = addr pool.slots[index]
      if slot.phase == Running: slot.cancelled = true # Synchronous Rust may still borrow the copied input.
      else: slot[] = Slot() # No worker can borrow queued or completed slots.
    broadcast(pool.changed)
    release(pool.lock)
    for i in 0..<2: join(pool.workers[i]) # Both worker-owned Rust setups retire before the shared mutex.
    deinitCond(pool.changed); deinitLock(pool.lock)
    progress "OFFLOAD_JOINED 2" # Every Rust setup and worker has retired before the pool owner.
  proc submitPool*(pool: var OffloadPool, invalid: bool): JobId {.raises: [].} =
    ## Admission copies a temporary value into a free slot; zero is the explicit rejected generation.
    acquire(pool.lock)
    defer: release(pool.lock)
    if pool.stopping: return JobId(0) # No new work after teardown begins.
    for index in 0..<4:
      let slot = addr pool.slots[index]
      if slot.phase == Free:
        if pool.next == high(uint64): return JobId(0) # Exhaustion cannot wrap into a reused generation.
        inc pool.next
        var scratch = pool.fixture
        scratch.invalid = invalid
        slot[] = Slot(job: scratch, id: JobId(pool.next), phase: Queued)
        scratch = ProofJob() # Reuse caller storage after the owned snapshot has been copied.
        signal(pool.changed)
        return slot.id
    JobId(0) # Queued, running and uncollected completions all count toward the four-slot cap.
  proc cancelPool*(pool: var OffloadPool, id: JobId) {.raises: [].} =
    ## Cancel by generation; a reused stream or slot can never cancel another job.
    if id == JobId(0): return # Streams without an admitted job own no pool resource.
    acquire(pool.lock)
    defer: release(pool.lock)
    for index in 0..<4:
      let slot = addr pool.slots[index]
      if slot.id == id and slot.phase != Free:
        progress "OFFLOAD_CANCEL ", $id, " ", ord(slot.phase)
        if slot.phase == Running: slot.cancelled = true # Retain original bytes until FFI completion.
        else: slot[] = Slot() # Queued/done work has no active borrower.
        return
  proc collectPool*(pool: var OffloadPool): OffloadPollResult {.raises: [].} =
    ## Poll a bounded completion on the I/O thread; workers never touch networking or diagnostics.
    acquire(pool.lock)
    defer: release(pool.lock)
    for index in 0..<4:
      let slot = addr pool.slots[index]
      if slot.phase == Done:
        result = OffloadPollResult(hasCompletion: true, completed: OffloadCompletion(id: slot.id,
            outcome: slot.outcome))
        slot[] = Slot() # Capacity becomes reusable only after collecting/discarding the result.
        return
    OffloadPollResult() # No completion means no default success is observable.
  proc tickPool*(pool: var OffloadPool) =
    ## Observe held versus actual Rust execution separately, and release only the explicit test barrier.
    let held = pool.gate.len > 0 and not fileExists(pool.gate)
    acquire(pool.lock)
    defer: release(pool.lock)
    if pool.held != held: pool.held = held; broadcast(pool.changed) # Wake workers only on a changed control.
    var stats = default(array[7, int])
    for slot in pool.slots:
      if slot.phase != Free: inc stats[6] # Every retained input/completion occupies one slot.
      case slot.phase
      of Queued: inc stats[0] # Awaiting a worker.
      of Running:
        inc stats[1]
        if slot.cancelled: inc stats[3] # Running cancelled owner is deliberately still retained.
      of Done: inc stats[2] # Finished but not yet delivered on I/O.
      of Free: discard # No owned job.
    stats[4] = pool.busy; stats[5] = pool.discarded
    if stats != pool.last:
      progress "OFFLOAD_STATE ", stats[0], " ", stats[1], " ", stats[2], " ", stats[3], " ", stats[
          4], " ", stats[5], " ", stats[6]
      pool.last = stats # Bounded change-only diagnostics.
else:
  # Ordinary peers do not link Rust or create workers; this inert type keeps the CLI layout simple.
  type OffloadPool* = object
  proc startPool*(pool: var OffloadPool): bool = false # Explicit mode is unavailable in ordinary builds.
  proc stopPool*(pool: var OffloadPool) = discard # An inert owner has no native resource.
  proc submitPool*(pool: var OffloadPool, invalid: bool): JobId {.raises: [].} = JobId(
      0) # Admission always rejects.
  proc cancelPool*(pool: var OffloadPool, id: JobId) {.raises: [].} = discard # No retained jobs.
  proc collectPool*(pool: var OffloadPool): OffloadPollResult {.raises: [].} = OffloadPollResult() # No fabricated completion.
  proc tickPool*(pool: var OffloadPool) = discard # No worker diagnostics.

when not OffloadEnabled:
  proc busyPool*(pool: var OffloadPool): int {.raises: [].} =
    ## An ordinary peer can never claim concurrent crypto activity.
    0

when OffloadEnabled:
  # Inspect completion capacity without consuming a result; used only by the bounded ownership selftest.
  proc phaseCount(pool: var OffloadPool, phase: Phase): int =
    result = 0
    acquire(pool.lock)
    for slot in pool.slots:
      if slot.phase == phase: inc result # Observe ownership without consuming or releasing a job.
    release(pool.lock)
  proc offloadSelfTest*() {.raises.} =
    ## Exercise default result safety, completed capacity and collection before any QUIC engine exists.
    var pool = default(OffloadPool)
    assert startPool(pool)
    defer: stopPool(pool)
    var ids = default(array[4, JobId])
    assert not collectPool(pool).ready
    for i in 0..<4: ids[i] = submitPool(pool, false) # Each admitted snapshot must produce its own generation.
    let started = getMonoTime()
    while phaseCount(pool, Done) != 4:
      assert (getMonoTime() - started).inSeconds < 20
      pause() # There is no network owner in this completion-capacity test.
    assert submitPool(pool, false) == JobId(0) # Four completed owners still reject a fifth job.
    var seen = default(array[4, bool])
    for i in 0..<4:
      let polled = collectPool(pool)
      assert polled.ready and polled.completion.outcome == Verified
      var found = false
      for index, id in ids:
        if id == polled.completion.id:
          assert not seen[index]
          seen[index] = true
          found = true # A duplicate or fabricated completion cannot satisfy this ownership proof.
      assert found
    assert not collectPool(pool).ready
    # Generations are never reused: the last representable ID is valid, but the following submission rejects.
    acquire(pool.lock)
    pool.next = high(uint64) - 1
    release(pool.lock)
    let last = submitPool(pool, false)
    assert last == JobId(high(uint64))
    assert submitPool(pool, false) == JobId(0)
    let exhausted = getMonoTime()
    while phaseCount(pool, Done) != 1:
      assert (getMonoTime() - exhausted).inSeconds < 20
      pause() # The final job retains the same owned bytes/worker semantics as earlier generations.
    let final = collectPool(pool)
    assert final.ready and final.completion.id == last and final.completion.outcome == Verified
    assert not collectPool(pool).ready
    progress "OFFLOAD_EXHAUSTED"
    progress "OFFLOAD_SELFTEST 4"
  proc offloadHeldShutdownTest*() {.raises.} =
    ## Exercise join with two held running owners plus two queued owners, before any FFI borrow begins.
    var pool = default(OffloadPool)
    assert startPool(pool)
    defer: stopPool(pool)
    for i in 0..<4: assert submitPool(pool, false) != JobId(0) # Four original inputs remain owned at shutdown.
    let started = getMonoTime()
    while phaseCount(pool, Running) != 2:
      assert (getMonoTime() - started).inSeconds < 20
      pause() # This focused hold test owns no event loop or network callbacks.
    assert busyPool(pool) == 0
    tickPool(pool)
    progress "OFFLOAD_HELD_SHUTDOWN 4" # Deferred stop releases holds, drops queued work and joins both workers.
else:
  proc offloadSelfTest*() =
    ## Ordinary binaries cannot claim worker lifecycle coverage.
    discard

when not OffloadEnabled:
  proc offloadHeldShutdownTest*() =
    ## Ordinary binaries cannot claim held-worker shutdown coverage.
    discard
