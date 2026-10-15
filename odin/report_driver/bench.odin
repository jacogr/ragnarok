// Checked complete-report measurements; all file loading, fixture parsing and preflight remain untimed.
package main
import codec "../codec"
import crypto "../crypto"
import "core:fmt"
import "core:mem"
import "core:os"

REPORT_ALLOCATIONS :: #config(REPORT_ALLOCATIONS, false)
// This shared observer is compiled separately without LTO so complete result storage stays observable.
when ODIN_OS == .Darwin { foreign import report_observation "../../build/bench/libobserve.dylib" } else { foreign import report_observation "../../build/bench/libobserve.so" }
foreign report_observation {
	// Opaque nonmutating observation prevents pruning full results to a small benchmark fingerprint.
	rb_observe :: proc "c" (data: rawptr, size: uintptr) ---
	// All candidates use the same platform monotonic clock implementation and resolution.
	rb_now_ns :: proc "c" () -> u64 ---
	// Process peak RSS includes setup, prepared corpus and native crypto providers.
	rb_peak_rss :: proc "c" () -> u64 ---
}
// Prepared input/credentials and typed encoder source remain alive throughout every measurement.
Report_Case :: struct {
	mode:         string,
	wire, output: []u8,
	report:       codec.Work_Report,
	message:      crypto.Guarantee_Message,
	keys:         [2]crypto.Ed_Public_Key,
	signatures:   [2]crypto.Ed_Signature,
}
// Both credentials are checked even when the first fails, preserving the provider's actual verdicts.
report_verify :: proc(item: ^Report_Case, message: []u8) -> bool {
	first := crypto.verify(item.keys[0], item.signatures[0], message)
	second := crypto.verify(item.keys[1], item.signatures[1], message)
	return first && second
}
// One runtime-input operation; complete outputs remain observed across the independently compiled boundary.
report_step :: #force_no_inline proc(item: ^Report_Case) -> u64 {
	switch item.mode {
	case "decode":
		// Observe the complete result, including fields not otherwise used by the small output fingerprint.
		decoded := codec.decode_report_borrowed(item.wire, 341)
		assert(
			codec.error_of(decoded) == .None &&
			codec.success_of(decoded).consumed == len(item.wire),
		)
		rb_observe(&decoded, size_of(decoded))
	case "encode":
		// Typed source preparation is outside timing; encode still performs its ordinary complete preflight.
		written := codec.encode_report_borrowed(item.report, item.wire, 341, item.output)
		assert(
			codec.error_of(written) == .None &&
			codec.success_of(written).written == len(item.wire),
		)
		rb_observe(raw_data(item.output), uintptr(len(item.output)))
	case "owned", "pipeline":
		// Capture, use and exactly one release all belong to the measured operation lifetime.
		captured := codec.decode_owned_report(item.wire, 341)
		assert(codec.error_of(captured) == .None)
		owner := codec.success_of(captured)
		defer codec.release_report(&owner)
		written := codec.encode_owned_report(owner, item.output)
		assert(codec.error_of(written) == .None && codec.success_of(written) == len(item.wire))
		rb_observe(raw_data(item.output), uintptr(len(item.output)))
		if item.mode == "pipeline" {
			// Canonical owned bytes feed the normative hash/domain plus two ordinary-key credential verifications.
			hashed := crypto.guarantee_message(item.output)
			assert(crypto.error_of(hashed) == .None)
			message := crypto.success_of(hashed)
			assert(report_verify(item, message[:]))
			rb_observe(&message, size_of(message))
		}
	case "hash":
		// This includes the actual provider and normative domain construction, not compiler overhead alone.
		message := crypto.guarantee_message(item.wire)
		assert(crypto.error_of(message) == .None)
		rb_observe(&message, size_of(message))
	case "verify2":
		// Prepared message excludes report hashing to expose provider verification cost independently.
		valid := report_verify(item, item.message[:])
		assert(valid); rb_observe(&valid, size_of(valid))
	case:
		assert(false) // Unregistered operation names must never yield plausible performance samples.
	}
	return u64(len(item.wire))
}
// Preflight exact encoded bytes and the full normative signing message before any timing loop.
report_benchmark :: proc() {
	assert(len(os.args) == 11)
	tracking: mem.Tracking_Allocator
	_ = &tracking // Only the separately compiled allocation binary installs this allocator.
	when REPORT_ALLOCATIONS {
		// Instrumentation never enters a binary used for throughput or latency measurements.
		mem.tracking_allocator_init(&tracking, context.allocator)
		defer mem.tracking_allocator_destroy(&tracking)
		context.allocator = mem.tracking_allocator(&tracking)
	}
	wire, err := os.read_entire_file(os.args[3], context.allocator)
	assert(err == nil && len(wire) <= 65536)
	defer delete(wire)
	parsed := codec.decode_report_borrowed(wire, 341)
	assert(codec.error_of(parsed) == .None && codec.success_of(parsed).consumed == len(wire))
	output := make([]u8, len(wire)); defer delete(output)
	item := Report_Case {
		mode   = os.args[2],
		wire   = wire,
		output = output,
		report = codec.success_of(parsed).value,
	}
	written := codec.encode_report_borrowed(item.report, wire, 341, output)
	assert(codec.error_of(written) == .None && codec.success_of(written).written == len(wire))
	// Verify every encoder byte independently before any successful timing record can exist.
	for i in 0 ..< len(wire) { assert(output[i] == wire[i]) }
	// Public credential imports occur once during setup, not inside each signature verification.
	for i in 0 ..< 2 {
		key_storage: [32]u8
		signature_storage: [64]u8
		key, key_ok := parse_hex(
			os.args[4 + 2 * i],
			key_storage[:],
		); assert(key_ok && len(key) == 32)
		signature, signature_ok := parse_hex(
			os.args[5 + 2 * i],
			signature_storage[:],
		); assert(signature_ok && len(signature) == 64)
		public := crypto.import_public_key(key); signed := crypto.import_signature(signature)
		assert(crypto.error_of(public) == .None && crypto.error_of(signed) == .None)
		item.keys[i] = crypto.success_of(public); item.signatures[i] = crypto.success_of(signed)
	}
	message := crypto.guarantee_message(wire)
	assert(crypto.error_of(message) == .None)
	item.message = crypto.success_of(message)
	valid := report_verify(&item, item.message[:])
	verdict := 0
	if valid { verdict = 1 } 	// Preflight reports actual provider verdicts, including explicit invalid-credential checks.
	fmt.print(
		"VERIFY ",
	); print_hex(output); fmt.print(" "); print_hex(item.message[:]); fmt.printf(" %d\n", verdict)
	if item.mode == "check" { return } 	// Negative signatures are tested without entering performance loops.
	assert(valid)
	iterations, iterations_ok := parse_capacity(os.args[8], 20000000)
	samples, samples_ok := parse_capacity(os.args[9], 31)
	latency, latency_ok := parse_capacity(os.args[10], 256)
	_ = latency // Allocation-only builds validate this argument but deliberately produce no latency samples.
	assert(iterations_ok && samples_ok && latency_ok && iterations >= 1 && samples >= 1)
	checksum: u64
	// Warm allocator, provider and code paths identically before either timing or allocation observation.
	for _ in 0 ..< min(iterations, 64) { checksum ~= report_step(&item) }
	when REPORT_ALLOCATIONS {
		// Count allocations only after fixture loading and warmup, in a separate measurement binary.
		allocations, frees := tracking.total_allocation_count, tracking.total_free_count
		live, bytes := tracking.current_memory_allocated, tracking.total_memory_allocated
		for _ in 0 ..< iterations { checksum ~= report_step(&item) } 	// Identical post-warmup operation boundary.
		fmt.println(
			"ALLOC",
			iterations,
			tracking.total_allocation_count - allocations,
			tracking.total_free_count - frees,
			tracking.current_memory_allocated - live,
			tracking.total_memory_allocated - bytes,
		)
	} else {
		// Native batch averages amortize the common timer overhead.
		for _ in 0 ..< samples {
			start := rb_now_ns()
			for _ in 0 ..< iterations { checksum ~= report_step(&item) } 	// Same per-operation work across candidates.
			fmt.println("BATCH", iterations, rb_now_ns() - start)
		}
		latencies := make([]u64, latency); defer delete(latencies)
		for i in 0 ..< latency {
			// Individual-operation latency includes the shared timer and opaque-observer boundary.
			start := rb_now_ns(
				
			); checksum ~= report_step(&item); latencies[i] = rb_now_ns() - start
		}
		for elapsed in latencies { fmt.println("LATENCY", elapsed) } 	// Printing cannot enter individual sample intervals.
	}
	fmt.println("END", checksum, rb_peak_rss())
}
