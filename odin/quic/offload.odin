// Fixed worker ownership proof: no native stream, TLS pointer or allocator owner enters a job.
package main
import bs "../bandersnatch"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:sync"
import "core:thread"
import "core:time"
OFFLOAD :: #config(OFFLOAD, false)
// Odin imports are file-scoped. Mark compile-time-unused imports explicitly while retaining strict vetting.
when !OFFLOAD {
	_ :: bs
	_ :: fmt
	_ :: os
	_ :: strconv
	_ :: sync
	_ :: thread
	_ :: time
}
// A failed job cannot authorize a reply; no verified output is exposed on failure.
Offload_Outcome :: enum {
	Failed,
	Verified,
}
// Nominal generations identify jobs independently of reused stream handles and queue slots.
Job_Id :: distinct u64
// I/O consumes one completed decision; default outcome fails.
Offload_Completion :: struct {
	id:      Job_Id,
	outcome: Offload_Outcome,
}
// A pending poll contains no completion metadata; select the data alternative before access.
Offload_Pending :: enum {
	Pending,
}
// Default selection is pending, never a completed generation or verified decision.
Offload_Poll :: union #no_nil {
	Offload_Pending,
	Offload_Completion,
}
when OFFLOAD {
	// Fixed copied input; these arrays have no allocator or borrowed-buffer lifetime.
	Proof_Job :: struct {
		root:     [144]u8,
		proof:    [784]u8,
		domain:   [48]u8,
		expected: [32]u8,
		invalid:  bool,
	}
	// Running cancellation retains input until Rust returns; Done still consumes admission capacity.
	Job_Phase :: enum {
		Free,
		Queued,
		Running,
		Done,
	}
	// One bounded job owner protected by the pool mutex.
	Job_Slot :: struct {
		job:       Proof_Job,
		id:        Job_Id,
		phase:     Job_Phase,
		cancelled: bool,
		outcome:   Offload_Outcome,
	}
	// Address-stable owner; only the I/O thread starts/stops it, and joins before releasing it.
	Offload_Pool :: struct {
		mutex:                                     sync.Mutex,
		changed:                                   sync.Cond,
		workers:                                   [2]^thread.Thread,
		slots:                                     [4]Job_Slot,
		fixture:                                   Proof_Job,
		capacity, repeats, ready, busy, discarded: int,
		next:                                      u64,
		held, stopping, setup_failed:              bool,
		last:                                      [7]int,
		gate:                                      string,
	}
	// Each worker creates/destroys its own Rust setup using its default context, never the I/O tracking allocator.
	offload_worker :: proc(t: ^thread.Thread) {
		pool := (^Offload_Pool)(t.data)
		setup := bs.new_setup(pool.capacity)
		sync.mutex_lock(&pool.mutex)
		pool.ready += 1
		if bs.error_of(setup) != .None { pool.setup_failed = true } 	// Setup failure cannot create a usable owner.
		sync.cond_broadcast(&pool.changed)
		sync.mutex_unlock(&pool.mutex)
		if bs.error_of(setup) != .None { return } 	// Main joins every worker even after failed setup.
		owner := bs.success_of(setup)
		defer bs.destroy_setup(&owner)
		for {
			sync.mutex_lock(&pool.mutex)
			index := -1
			// Recheck queue and shutdown after every wakeup; there is no per-job polling thread.
			for index < 0 && !pool.stopping {
				for slot, i in pool.slots { if slot.phase == .Queued { index = i; break } } 	// Claim exactly one under lock.
				if index < 0 { sync.cond_wait(&pool.changed, &pool.mutex) } 	// Release lock while idle.
			}
			if pool.stopping { sync.mutex_unlock(&pool.mutex); return } 	// Queued shutdown work never enters Rust.
			pool.slots[index].phase = .Running
			job := pool.slots[index].job
			// Deterministic test holds are separate from actual synchronous verification.
			for pool.held && !pool.stopping { sync.cond_wait(&pool.changed, &pool.mutex) }
			if pool.stopping {
				pool.slots[index] = {}
				sync.mutex_unlock(&pool.mutex)
				return // No active FFI borrower at this test barrier.
			}
			pool.busy += 1
			sync.mutex_unlock(&pool.mutex)
			outcome := Offload_Outcome.Verified
			domain := job.domain
			if job.invalid { domain[0] ~= 1 } 	// Wrong explicit JAM domain tests failure propagation.
			// Repeat real proof calls only to supply bounded compute load; never report the hold as crypto.
			for _ in 0 ..< pool.repeats {
				checked := bs.verify_ring(
					owner,
					bs.Bs_Ring_Root(job.root),
					bs.Bs_Ring_Proof(job.proof),
					domain[:],
					nil,
				)
				if bs.error_of(checked) != .None { outcome = .Failed; break } 	// Error alternative has no output.
				if ([32]u8)(bs.success_of(checked)) != job.expected { outcome = .Failed; break } 	// Match independent official output.
			}
			sync.mutex_lock(&pool.mutex)
			pool.busy -= 1
			if pool.slots[index].cancelled || pool.stopping {
				pool.discarded += 1
				pool.slots[index] = {} // The original input may be released only after Rust returns.
			} else {
				pool.slots[index].outcome = outcome
				pool.slots[index].phase = .Done // Uncollected result still occupies one of four slots.
			}
			sync.mutex_unlock(&pool.mutex)
		}
	}
	// Read a bounded trusted fixture on I/O before worker creation; no network request chooses the path/domain.
	start_pool :: proc(pool: ^Offload_Pool) -> bool {
		path := os.get_env("RAGNAROK_OFFLOAD_FIXTURE", context.allocator)
		defer delete(path)
		wire, err := os.read_entire_file(path, context.allocator)
		defer delete(wire)
		if err != nil || len(wire) != 1012 { return false } 	// Fixed E4 capacity/root/proof/domain/output.
		for i in 0 ..< 4 { pool.capacity |= int(wire[i]) << uint(8 * i) } 	// Trusted little-endian domain capacity.
		if pool.capacity != 6 && pool.capacity != 1023 { return false } 	// Only official tiny/full domains.
		repeats := os.get_env("RAGNAROK_OFFLOAD_REPEATS", context.allocator)
		defer delete(repeats)
		pool.repeats = 1
		if len(repeats) > 0 {
			n, ok := strconv.parse_int(repeats)
			if !ok || n < 1 || n > 256 { return false } 	// Bound noninterruptible work and shutdown.
			pool.repeats = n
		}
		for i in 0 ..< 144 { pool.fixture.root[i] = wire[4 + i] } 	// Copy all retained inputs before file storage is released.
		for i in 0 ..< 784 { pool.fixture.proof[i] = wire[148 + i] } 	// No borrowed slice crosses threads.
		for i in 0 ..< 48 { pool.fixture.domain[i] = wire[932 + i] } 	// Caller constructs the explicit GP domain.
		for i in 0 ..< 32 { pool.fixture.expected[i] = wire[980 + i] } 	// Independent output oracle.
		pool.gate = os.get_env("RAGNAROK_OFFLOAD_GATE", context.allocator)
		pool.held = len(pool.gate) > 0 && !os.exists(pool.gate)
		for &t in pool.workers {
			t = thread.create(offload_worker)
			if t == nil { stop_pool(pool); return false } 	// Failed OS thread creation joins already-started siblings.
			t.data = pool
			thread.start(t) // Exactly two OS workers, independent of connections/streams.
		}
		sync.mutex_lock(&pool.mutex)
		for pool.ready < 2 { sync.cond_wait(&pool.changed, &pool.mutex) } 	// Setup readiness precedes READY.
		ok := !pool.setup_failed
		sync.mutex_unlock(&pool.mutex)
		if !ok { stop_pool(pool) } 	// Failed setup joins successful siblings before returning.
		return ok
	}
	// Count real Rust execution separately from held/queued work, using the same mutex.
	busy_pool :: proc(pool: ^Offload_Pool) -> int {
		sync.mutex_lock(&pool.mutex)
		n := pool.busy
		sync.mutex_unlock(&pool.mutex)
		return n
	}
	// Stop admission, discard queued/completed work, release holds and join before destroying the stable owner.
	stop_pool :: proc(pool: ^Offload_Pool) {
		sync.mutex_lock(&pool.mutex)
		pool.stopping = true
		pool.held = false
		for &slot in pool.slots {
			if slot.phase == .Running { slot.cancelled = true } else { slot = {} } 	// Active borrowers retain original arrays.
		}
		sync.cond_broadcast(&pool.changed)
		sync.mutex_unlock(&pool.mutex)
		joined := 0
		for t in pool.workers {
			if t != nil { thread.join(t); thread.destroy(t); joined += 1 } 	// Join only successfully created handles.
		}
		delete(pool.gate)
		fmt.println("OFFLOAD_JOINED", joined)
	}
	// Snapshot into a free bounded slot. Zero generation explicitly rejects admission, never a default proof.
	submit_pool :: proc(pool: ^Offload_Pool, invalid: bool) -> Job_Id {
		sync.mutex_lock(&pool.mutex)
		defer sync.mutex_unlock(&pool.mutex)
		if pool.stopping { return 0 } 	// No admission after shutdown starts.
		for &slot in pool.slots {
			if slot.phase == .Free {
				pool.next += 1
				scratch := pool.fixture
				scratch.invalid = invalid
				slot = Job_Slot {
					job   = scratch,
					id    = Job_Id(pool.next),
					phase = .Queued,
				}
				scratch = {} // Demonstrate source reuse after owned value capture.
				sync.cond_signal(&pool.changed)
				return slot.id
			}
		}
		return 0 // Queued/running/completed owners all count against four total jobs.
	}
	// Cancel by generation; stream/slot reuse can never redirect cancellation to another job.
	cancel_pool :: proc(pool: ^Offload_Pool, id: Job_Id) {
		if id == 0 { return } 	// This stream never acquired a pool owner.
		sync.mutex_lock(&pool.mutex)
		defer sync.mutex_unlock(&pool.mutex)
		for &slot in pool.slots {
			if slot.id == id && slot.phase != .Free {
				fmt.println("OFFLOAD_CANCEL", u64(id), int(slot.phase))
				if slot.phase == .Running { slot.cancelled = true } else { slot = {} } 	// Running Rust retains input; others free immediately.
				return
			}
		}
	}
	// Consume one completion only on I/O; worker threads cannot access native transport state.
	collect_pool :: proc(pool: ^Offload_Pool) -> Offload_Poll {
		sync.mutex_lock(&pool.mutex)
		defer sync.mutex_unlock(&pool.mutex)
		for &slot in pool.slots {
			if slot.phase == .Done {
				completion := Offload_Completion{slot.id, slot.outcome}
				slot = {} // Release capacity only after explicit consumption.
				return completion
			}
		}
		return Offload_Pending.Pending // No default completion is usable.
	}
	// Report retained states, actual crypto activity and cancellation separately; control files are trusted test inputs.
	tick_pool :: proc(pool: ^Offload_Pool) {
		held := len(pool.gate) > 0 && !os.exists(pool.gate)
		sync.mutex_lock(&pool.mutex)
		defer sync.mutex_unlock(&pool.mutex)
		if held != pool.held { pool.held = held; sync.cond_broadcast(&pool.changed) } 	// Wake only on changed hold.
		stats: [7]int
		for slot in pool.slots {
			if slot.phase != .Free { stats[6] += 1 } 	// All retained job owners count toward capacity.
			switch slot.phase {
			case .Queued:
				stats[0] += 1 // Waiting for a worker.
			case .Running:
				stats[1] += 1
				if slot.cancelled { stats[3] += 1 } 	// Cancelled input intentionally still retained.
			case .Done:
				stats[2] += 1 // Awaiting I/O delivery.
			case .Free: // No job owner.
			}
		}
		stats[4] = pool.busy; stats[5] = pool.discarded
		if stats != pool.last {
			fmt.println(
				"OFFLOAD_STATE",
				stats[0],
				stats[1],
				stats[2],
				stats[3],
				stats[4],
				stats[5],
				stats[6],
			)
			pool.last = stats // Bound diagnostics by changes, not packets/crypto iterations.
		}
	}
} else {
	// Ordinary peers have no linked Rust calls or worker resources; explicit offload mode is unavailable.
	Offload_Pool :: struct {}
	// Unavailable mode cannot initialize a worker owner.
	start_pool :: proc(pool: ^Offload_Pool) -> bool { return false }
	// Empty owner needs no shutdown.
	stop_pool :: proc(pool: ^Offload_Pool) {  }
	// No job admission in a default build.
	submit_pool :: proc(pool: ^Offload_Pool, invalid: bool) -> Job_Id { return 0 }
	// No owned job can be cancelled in a default build.
	cancel_pool :: proc(pool: ^Offload_Pool, id: Job_Id) {  }
	// Never fabricate success for a missing worker.
	collect_pool :: proc(pool: ^Offload_Pool) -> Offload_Poll { return Offload_Pending.Pending }
	// No actual Rust calls can be active in an ordinary peer.
	busy_pool :: proc(pool: ^Offload_Pool) -> int { return 0 }
	// No worker observations in a default build.
	tick_pool :: proc(pool: ^Offload_Pool) {  }
}

when OFFLOAD {
	// Inspect uncollected capacity without moving results; no QUIC owners exist in this focused test.
	phase_count :: proc(pool: ^Offload_Pool, phase: Job_Phase) -> int {
		sync.mutex_lock(&pool.mutex)
		n := 0
		for slot in pool.slots { if slot.phase == phase { n += 1 } } 	// Done owners still consume capacity.
		sync.mutex_unlock(&pool.mutex)
		return n
	}
	// Check default pending, bounded completed ownership and exactly-once collection before networking.
	offload_self_test :: proc() {
		pool: Offload_Pool
		assert(start_pool(&pool))
		defer stop_pool(&pool)
		_, ready := collect_pool(&pool).(Offload_Completion)
		assert(!ready)
		ids: [4]Job_Id
		for &id in ids { id = submit_pool(&pool, false); assert(id != 0) } 	// Independent copied job generations.
		started := time.now()
		for phase_count(&pool, .Done) != 4 {
			assert(time.since(started) < 20 * time.Second)
			time.sleep(2 * time.Millisecond) // No network event loop is blocked by this selftest.
		}
		assert(submit_pool(&pool, false) == 0) // Completed owners cannot admit a fifth job.
		seen: [4]bool
		for _ in 0 ..< 4 {
			polled := collect_pool(&pool)
			completion, ok := polled.(Offload_Completion)
			assert(ok && completion.outcome == .Verified)
			found := false
			for id, index in ids {
				if id == completion.id {
					assert(!seen[index])
					seen[index] = true
					found = true // Duplicate or fabricated generation cannot satisfy this check.
				}
			}
			assert(found)
		}
		_, ready = collect_pool(&pool).(Offload_Completion)
		assert(!ready)
		fmt.println("OFFLOAD_SELFTEST 4")
	}
	// Shutdown releases two held worker borrowers and two queued inputs without first entering Rust.
	offload_held_shutdown_test :: proc() {
		pool: Offload_Pool
		assert(start_pool(&pool))
		defer stop_pool(&pool)
		for _ in 0 ..< 4 { assert(submit_pool(&pool, false) != 0) } 	// Retain every original input until shutdown.
		started := time.now()
		for phase_count(&pool, .Running) != 2 {
			assert(time.since(started) < 20 * time.Second)
			time.sleep(2 * time.Millisecond) // No I/O dispatcher exists in this focused test.
		}
		assert(busy_pool(&pool) == 0)
		tick_pool(&pool)
		fmt.println("OFFLOAD_HELD_SHUTDOWN 4") // Deferred stop drops queued work and joins held workers.
	}
} else {
	// Ordinary binaries cannot claim worker lifecycle coverage.
	offload_self_test :: proc() {  }
	// Ordinary binaries cannot claim held-worker shutdown coverage.
	offload_held_shutdown_test :: proc() {  }
}
