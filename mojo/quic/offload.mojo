from std.collections import Array, List, Optional
from std.ffi import external_call, c_int, c_size_t
from std.os import getenv
from std.os.path import exists
from std.sys import get_defined_bool
from codec.types import Quantity
from bandersnatch.primitives import (
    BsSetup,
    BsRingRoot,
    BsRingProof,
    BsOutput,
    new_setup,
    verify_ring,
    release_setup,
)
from quic.transport import NativePointer, PollFd, now_ms
from tests.support import capacity


comptime ENABLED = get_defined_bool["OFFLOAD", False]()
comptime JobId = Quantity[30]


# Every admitted job owns fixed public proof/domain/output bytes independently of temporary caller storage.
@fieldwise_init
struct ProofJob(Copyable, Movable):
    var root: Array[UInt8, 144]
    var proof: Array[UInt8, 784]
    var context: Array[UInt8, 48]
    var expected: Array[UInt8, 32]
    var invalid: Bool


# One bounded slot retains queued, running, or uncollected completed ownership under the pool mutex.
@fieldwise_init
struct Slot(Copyable, Movable):
    var job: ProofJob
    var id: JobId
    var phase: Int
    var cancelled: Bool
    var verified: Bool


# Ready completion has a nominal generation and verdict; absence contains no readable completion fields.
@fieldwise_init
struct Completion(Copyable, Movable):
    var id: JobId
    var verified: Bool


# Stack-stable pool owns exactly two OS workers and four retained job/completion slots.
@fieldwise_init
struct Pool(Movable):
    var mutex: Optional[NativePointer]
    var changed: Optional[NativePointer]
    var workers: Array[Optional[NativePointer], 2]
    var slots: List[Slot]
    var fixture: ProofJob
    var domain_capacity: Int
    var repeats: Int
    var ready: Int
    var busy: Int
    var discarded: Int
    var next: UInt64
    var held: Bool
    var stopping: Bool
    var setup_failed: Bool
    var last: Array[Int, 7]
    var gate: String


# Empty public proof storage is not a verified proof or usable output.
def empty_job() -> ProofJob:
    return ProofJob(
        Array[UInt8, 144](fill=0),
        Array[UInt8, 784](fill=0),
        Array[UInt8, 48](fill=0),
        Array[UInt8, 32](fill=0),
        False,
    )


# A free slot carries no active generation, borrower or successful proof verdict.
def empty_slot() -> Slot:
    return Slot(empty_job(), JobId(0), 0, False, False)


# Construct the pool before any worker borrows its stable address; no synchronization owner exists yet.
def empty_pool() -> Pool:
    return Pool(
        None,
        None,
        Array[Optional[NativePointer], 2](fill=None),
        List[Slot](),
        empty_job(),
        0,
        0,
        0,
        0,
        0,
        0,
        False,
        False,
        False,
        Array[Int, 7](fill=-1),
        String(),
    )


# Fail-stop only on broken internal OS synchronization/lifetime invariants, never malformed network/proof input.
def checked(status: c_int):
    if status != 0:
        # Continuing without a held lock would permit unsynchronized mutation of native owners.
        external_call["abort", NoneType]()


# Acquire the sole pool mutex before examining or changing shared job/worker state.
def lock(pool: Pool):
    checked(external_call["rqm_mutex_lock", c_int](pool.mutex.value()))


# Release the pool mutex after a bounded native-language critical section.
def unlock(pool: Pool):
    checked(external_call["rqm_mutex_unlock", c_int](pool.mutex.value()))


# Atomically wait for changed queue/hold/shutdown state; callers recheck the predicate after every wake.
def wait(pool: Pool):
    checked(external_call["rqm_cond_wait", c_int](pool.changed.value(), pool.mutex.value()))


# Wake the fixed workers only after changing the shared queue/hold/shutdown predicate under lock.
def broadcast(pool: Pool):
    checked(external_call["rqm_cond_broadcast", c_int](pool.changed.value()))


# One fixed C-compatible worker owns its Rust SRS setup and copied job bytes until FFI completion.
def worker(user: OpaquePointer[mut=True, _]) abi("C") -> Optional[NativePointer]:
    ref pool = user.unsafe_bitcast[Pool]()[]
    var loaded = new_setup(pool.domain_capacity)
    lock(pool)
    pool.ready += 1
    if not loaded.isa[BsSetup]():
        # Failed initialization cannot manufacture a valid setup or hide a missing worker.
        pool.setup_failed = True
    broadcast(pool)
    unlock(pool)
    if not loaded.isa[BsSetup]():
        # The controller joins failed workers before retiring any pool synchronization owner.
        return None
    var setup = loaded[BsSetup].copy()
    try:
        # No thread is created per job/stream; these exact two workers serve the entire bounded pool lifetime.
        while True:
            lock(pool)
            var index = -1
            while index < 0 and not pool.stopping:
                # Exactly one worker claims one queued slot while holding the common mutex.
                for i in range(4):
                    if pool.slots[i].phase == 1:
                        index = i
                        break
                if index < 0:
                    # Idle workers block on the public POSIX condition rather than polling or spinning.
                    wait(pool)
            if pool.stopping:
                # Shutdown drops queued work without entering another synchronous Rust call.
                unlock(pool)
                return None
            pool.slots[index].phase = 2
            var job = pool.slots[index].job.copy()
            while pool.held and not pool.stopping:
                # The explicit test hold proves queue ownership; it is never reported as crypto execution.
                wait(pool)
            if pool.stopping:
                pool.slots[index] = empty_slot()
                unlock(pool)
                return None
            pool.busy += 1
            unlock(pool)
            var verified = True
            var context = job.context.copy()
            if job.invalid:
                # Negative policy uses a wrong actual domain and a real verification rejection.
                context[0] ^= 1
            var empty = List[UInt8]()
            for _ in range(pool.repeats):
                # Each repetition performs real historical RingVRF verification on copied public inputs.
                var result = verify_ring(
                    setup,
                    BsRingRoot(job.root.copy()),
                    BsRingProof(job.proof.copy()),
                    context,
                    empty,
                )
                if not result.isa[BsOutput]():
                    # Failed verification has no output bytes to authorize a CE reply.
                    verified = False
                    break
                var output = result[BsOutput].copy()
                for i in range(32):
                    # Independently sourced official output must match in full before success is published.
                    if output.bytes[i] != job.expected[i]:
                        verified = False
                if not verified:
                    # Do not waste more bounded compute after a wrong independently expected output.
                    break
            lock(pool)
            pool.busy -= 1
            if pool.slots[index].cancelled or pool.stopping:
                pool.discarded += 1
                pool.slots[index] = empty_slot()
                # Only after Rust returns may a cancelled running slot release or reuse its original owner.
            else:
                pool.slots[index].verified = verified
                pool.slots[index].phase = 3
                # Uncollected completed results still consume one of the same four admission slots.
            unlock(pool)
    finally:
        # Rust setup creation and destruction occur on this same worker, never on an unrelated I/O thread.
        release_setup(setup)


# Stop admission, cancel retained work, unblock holds and join all created workers before retiring OS synchronization.
def stop_pool(mut pool: Pool):
    if not pool.mutex:
        # An inert/failed-before-mutex pool owns no worker or synchronization state.
        return
    lock(pool)
    pool.stopping = True
    pool.held = False
    for i in range(4):
        if pool.slots[i].phase == 2:
            # A running Rust call keeps its original slot until its synchronous borrow ends.
            pool.slots[i].cancelled = True
        else:
            # Queued/completed values have no active foreign borrower and retire immediately.
            pool.slots[i] = empty_slot()
    if pool.changed:
        # Partial initialization may have created a mutex before its condition owner.
        broadcast(pool)
    unlock(pool)
    for i in range(2):
        if pool.workers[i]:
            # Every successfully created worker joins before its stable pool owner can leave scope.
            checked(external_call["rqm_thread_join", c_int](pool.workers[i].value()))
            pool.workers[i] = None
    if pool.changed:
        # No waiter remains after the joins, so condition destruction cannot race a worker.
        external_call["rqm_cond_free", NoneType](pool.changed.value())
        pool.changed = None
    external_call["rqm_mutex_free", NoneType](pool.mutex.value())
    pool.mutex = None
    print("OFFLOAD_JOINED 2")


# Copy the fixed public official ticket fixture before threads/networking exist and validate all controller bounds.
def start_pool(mut pool: Pool) raises -> Bool:
    var wire: List[UInt8]
    with open(getenv("RAGNAROK_OFFLOAD_FIXTURE"), "r") as file:
        wire = file.read_bytes()
    if len(wire) != 1012:
        # No malformed fixture may choose an arbitrary SRS/domain or partial proof.
        return False
    var domain_capacity = 0
    for i in range(4):
        # Trusted controller E4 is decoded in Mojo, never inside the OS synchronization helper.
        domain_capacity |= Int(wire[i]) << (8 * i)
    if domain_capacity != 6 and domain_capacity != 1023:
        # Only independently pinned tiny/full fixture domains qualify for this explicit workload.
        return False
    var repeats = capacity(getenv("RAGNAROK_OFFLOAD_REPEATS", "1"), 256)
    if repeats < 1:
        # Bound the noninterruptible Rust work and never fake an empty successful batch.
        return False
    pool.slots = List[Slot](length=4, fill=empty_slot())
    pool.domain_capacity = domain_capacity
    pool.repeats = repeats
    for i in range(144):
        # Own the complete immutable root bytes independently of the file buffer.
        pool.fixture.root[i] = wire[4 + i]
    for i in range(784):
        # No borrowed proof pointer crosses the native worker boundary.
        pool.fixture.proof[i] = wire[148 + i]
    for i in range(48):
        # The explicit JAM domain stays language policy, separate from the Rust primitive ABI.
        pool.fixture.context[i] = wire[932 + i]
    for i in range(32):
        # Retain the official independently expected output, never a self-generated verification oracle.
        pool.fixture.expected[i] = wire[980 + i]
    pool.gate = getenv("RAGNAROK_OFFLOAD_GATE")
    pool.held = pool.gate != "" and not exists(pool.gate)
    pool.mutex = external_call["rqm_mutex_new", Optional[NativePointer]]()
    if not pool.mutex:
        # No worker can be created without its synchronization owner.
        return False
    pool.changed = external_call["rqm_cond_new", Optional[NativePointer]]()
    if not pool.changed:
        # Partial OS setup releases only the already-created original mutex.
        stop_pool(pool)
        return False
    for i in range(2):
        pool.workers[i] = external_call["rqm_thread_new", Optional[NativePointer]](
            worker, Pointer(to=pool).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        )
        if not pool.workers[i]:
            # Partial launch joins created siblings before allowing the pool's stack address to retire.
            stop_pool(pool)
            return False
    lock(pool)
    while pool.ready < 2:
        # Successful Rust setup readiness precedes listener advertisement and application admission.
        wait(pool)
    var good = not pool.setup_failed
    unlock(pool)
    if not good:
        # A failed setup joins both created workers and retires every synchronization owner.
        stop_pool(pool)
    return good


# Admission copies one job into a free slot; zero is rejected and queued/running/done all count toward capacity.
def submit(mut pool: Pool, invalid: Bool) -> JobId:
    lock(pool)
    try:
        if pool.stopping or pool.next == UInt64.MAX:
            # No admission occurs after shutdown or after exhausting unique nonzero generations.
            return JobId(0)
        for i in range(4):
            if pool.slots[i].phase == 0:
                pool.next += 1
                var job = pool.fixture.copy()
                job.invalid = invalid
                pool.slots[i] = Slot(job^, JobId(pool.next), 1, False, False)
                checked(external_call["rqm_cond_signal", c_int](pool.changed.value()))
                return JobId(pool.next)
        # A finished but uncollected result cannot silently free capacity for a fifth owner.
        return JobId(0)
    finally:
        # Every admitted/rejected path releases the same sole pool mutex.
        unlock(pool)


# Cancel by generation, retaining running original bytes until their synchronous foreign borrow ends.
def cancel(mut pool: Pool, id: JobId):
    if id.value == 0:
        # Streams without an admitted job own no queue resource.
        return
    lock(pool)
    try:
        for i in range(4):
            if pool.slots[i].id.value == id.value and pool.slots[i].phase != 0:
                print("OFFLOAD_CANCEL", id.value, pool.slots[i].phase)
                if pool.slots[i].phase == 2:
                    # Running cancellation cannot erase/reuse bytes still borrowed by Rust.
                    pool.slots[i].cancelled = True
                else:
                    # Queued or completed jobs have no active borrower and release their owned slot now.
                    pool.slots[i] = empty_slot()
                return
    finally:
        # Generation mismatch and successful cancellation both release the common mutex.
        unlock(pool)


# Collect at most one ready completion on I/O; None has no default generation or success verdict.
def collect(mut pool: Pool) -> Optional[Completion]:
    lock(pool)
    try:
        for i in range(4):
            if pool.slots[i].phase == 3:
                var result = Completion(pool.slots[i].id.copy(), pool.slots[i].verified)
                pool.slots[i] = empty_slot()
                return result^
        # Pending is a distinct empty alternative, never a fabricated successful completion.
        return None
    finally:
        # Collection is the point where completed capacity becomes reusable.
        unlock(pool)


# Count actual Rust work under the mutex; test holds and queued jobs are deliberately excluded.
def busy(pool: Pool) -> Int:
    lock(pool)
    var result = pool.busy
    unlock(pool)
    return result


# Release only changed controller holds and emit bounded queue-state transitions separately from actual crypto work.
def tick(mut pool: Pool):
    var held = pool.gate != "" and not exists(pool.gate)
    lock(pool)
    try:
        if held != pool.held:
            # Workers wake only when the explicit hold predicate changes.
            pool.held = held
            broadcast(pool)
        var stats = Array[Int, 7](fill=0)
        for i in range(4):
            if pool.slots[i].phase != 0:
                # Every retained input or uncollected completion consumes one bounded admission slot.
                stats[6] += 1
            if pool.slots[i].phase == 1:
                stats[0] += 1
            elif pool.slots[i].phase == 2:
                # Running-held ownership is distinct from busy actual Rust execution below.
                stats[1] += 1
                if pool.slots[i].cancelled:
                    stats[3] += 1
            elif pool.slots[i].phase == 3:
                # Completed values remain owned until their I/O consumer collects them.
                stats[2] += 1
        stats[4] = pool.busy
        stats[5] = pool.discarded
        var changed = False
        for i in range(7):
            if stats[i] != pool.last[i]:
                # Diagnostics grow only with actual state changes, never each idle poll iteration.
                changed = True
        if changed:
            print(
                "OFFLOAD_STATE",
                stats[0],
                stats[1],
                stats[2],
                stats[3],
                stats[4],
                stats[5],
                stats[6],
            )
            pool.last = stats^
    finally:
        # The I/O observer never leaves workers blocked behind its statistics read.
        unlock(pool)


# Count one ownership phase without consuming a completion or changing the four-slot admission budget.
def phase_count(pool: Pool, phase: Int) -> Int:
    lock(pool)
    var count = 0
    for i in range(4):
        if pool.slots[i].phase == phase:
            # Completed capacity remains occupied until collection, exactly like queued/running ownership.
            count += 1
    unlock(pool)
    return count


# Yield a short native readiness wait; focused pool tests have no live socket or network callback owner.
def sleep_ms(delay: Int):
    var item = PollFd(c_int(-1), 0, 0)
    _ = external_call["rqm_poll", c_int](Pointer(to=item), c_size_t(0), c_int(delay))


# Prove four completed results still occupy capacity and every collection returns a unique verified generation.
def selftest() raises:
    var pool = empty_pool()
    if not start_pool(pool):
        # Missing pinned parameters cannot count as a successful completion-capacity proof.
        raise Error("pool selftest setup")
    try:
        if collect(pool):
            # An empty pool has no default readable completion or successful verdict.
            raise Error("fabricated completion")
        var ids = Array[UInt64, 4](fill=0)
        for i in range(4):
            ids[i] = submit(pool, False).value
            if ids[i] == 0:
                # All four owned slots must admit their own nonzero generation.
                raise Error("initial admission")
        var started = now_ms()
        while phase_count(pool, 3) != 4:
            if now_ms() - started > 20000:
                # Real Rust work must complete within the same focused test deadline as the other adapters.
                raise Error("completion deadline")
            sleep_ms(2)
        if submit(pool, False).value != 0:
            # Finished but uncollected owners must not silently authorize a fifth allocation.
            raise Error("completed capacity escaped")
        var seen = Array[Bool, 4](fill=False)
        for _ in range(4):
            var polled = collect(pool)
            if not polled or not polled.value().verified:
                # Only actual verified completions may authorize the controlled response.
                raise Error("missing verified completion")
            var matched = False
            for i in range(4):
                if polled.value().id.value == ids[i]:
                    if seen[i]:
                        # Reused/fabricated generations cannot satisfy the ownership proof twice.
                        raise Error("duplicate generation")
                    seen[i] = True
                    matched = True
            if not matched:
                # A completion must identify one of the original four admitted copies.
                raise Error("foreign generation")
        if collect(pool):
            # Collecting the exact four results retires all completion ownership.
            raise Error("extra completion")
        print("OFFLOAD_SELFTEST 4")
    finally:
        # Every Rust setup and native worker joins before its sole synchronization/pool owner retires.
        stop_pool(pool)


# Exercise joined shutdown with two held running owners and two queued owners before any Rust borrow begins.
def held_shutdown_test() raises:
    var pool = empty_pool()
    if not start_pool(pool):
        # Explicit hold controls do not permit missing/failed worker setup.
        raise Error("held pool setup")
    try:
        for _ in range(4):
            if submit(pool, False).value == 0:
                # All four original copied inputs must still be admitted at the shutdown boundary.
                raise Error("held admission")
        var started = now_ms()
        while phase_count(pool, 2) != 2:
            if now_ms() - started > 20000:
                # A dead worker/controller cannot conceal an unbounded shutdown wait.
                raise Error("held workers deadline")
            sleep_ms(2)
        # Record held ownership separately from actual crypto work before joined shutdown begins.
        tick(pool)
        print("OFFLOAD_HELD_SHUTDOWN 4")
    finally:
        # Shutdown releases held waiters and queued owners, then joins both workers without entering crypto.
        stop_pool(pool)
