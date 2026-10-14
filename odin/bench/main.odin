// Optimized checked M1/M2 measurements; preflight and allocator instrumentation never enter throughput timing.
package main
import codec "../codec"
import crypto "../crypto"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:strconv"
import "core:time"

ALLOCATIONS :: #config(ALLOCATIONS, false)
// The same separate non-LTO observation library prevents result pruning in both languages.
when ODIN_OS == .Darwin { foreign import observation "../../build/bench/libobserve.dylib" } else { foreign import observation "../../build/bench/libobserve.so" }
foreign observation {
	// Observe complete output storage without reading/writing it; no application policy lives in C.
	rb_observe :: proc "c" (data: rawptr, size: uintptr) ---
	// Normalized process peak includes startup and prepared fixture/runtime storage.
	rb_peak_rss :: proc "c" () -> u64 ---
}
// Stable nonoverlapping source/destination storage and nominal input values live across every measured call.
Bench_Case :: struct {
	kind, operation:                        string,
	wire, output:                           []u8,
	offset, length:                         int,
	number:                                 u64,
	values, values_storage, decoded_values: []codec.Fixed_Unsigned,
	digest:                                 codec.Work_Digest,
	owner:                                  codec.Owned_Frame,
}

// Small fingerprint consumes observed data; preflight verifies all encoder bytes separately.
wire_mark :: proc(bytes: []u8, length: int) -> u64 {
	mark := u64(length)
	if length > 0 { mark ~= u64(bytes[0]) ~ u64(bytes[length - 1]) } 	// Empty fixed-width encodings have no bytes to sample.
	return mark
}

// Keep the runtime-input operation boundary intact while letting the real codec optimize normally inside it.
step :: #force_no_inline proc(item: ^Bench_Case) -> u64 {
	if item.kind ==
	   "baseline" { rb_observe(&item.number, size_of(item.number)); return item.number } 	// Common call/observation overhead.
	if item.kind == "natural" {
		if item.operation == "encode" {
			encoded := codec.encode(codec.Natural(item.number))
			rb_observe(&encoded, size_of(encoded))
			return wire_mark(encoded.bytes[:], encoded.length)
		} else {
			decoded := codec.decode(item.wire)
			rb_observe(&decoded, size_of(decoded))
			assert(codec.error_of(decoded) == .None)
			value := codec.success_of(decoded)
			return u64(value.value) ~ u64(value.consumed)
		}
	}
	if item.kind == "fixed" {
		if item.operation == "encode" {
			encoded := codec.encode_fixed(
				codec.Fixed_Unsigned(item.number),
				codec.Byte_Width(len(item.wire)),
			)
			rb_observe(&encoded, size_of(encoded))
			assert(codec.error_of(encoded) == .None)
			value := codec.success_of(encoded).encoded
			return wire_mark(value.bytes[:], value.length)
		} else {
			decoded := codec.decode_fixed(item.wire, codec.Byte_Width(len(item.wire)))
			rb_observe(&decoded, size_of(decoded))
			assert(codec.error_of(decoded) == .None)
			value := codec.success_of(decoded)
			return u64(value.value) ~ u64(value.consumed)
		}
	}
	// The crypto case includes the existing provider, not just native adapter/compiler overhead.
	if item.kind == "blake2b" {
		hashed := crypto.blake2b256(item.wire)
		rb_observe(&hashed, size_of(hashed))
		assert(crypto.error_of(hashed) == .None)
		bytes := crypto.success_of(hashed)
		return wire_mark(bytes[:], len(bytes))
	}
	if item.operation == "owned-encode" {
		written := codec.encode_owned(item.owner, item.output)
		assert(codec.error_of(written) == .None)
		size := codec.success_of(written)
		rb_observe(raw_data(item.output), uintptr(size))
		return wire_mark(item.output, size) // Prepared owner excludes hidden decode/allocation from this operation.
	}
	if item.operation == "owned-decode" {
		decoded :=
			codec.decode_owned_bytes(item.wire, codec.Byte_Limit(1048576)) if item.kind == "blob" else codec.decode_owned_digest(item.wire, codec.Byte_Limit(1048576))
		assert(codec.error_of(decoded) == .None)
		owner := codec.success_of(decoded)
		defer codec.destroy_owned(&owner) // Final single-owner release belongs to the measured operation.
		info := codec.owned_info(owner)
		assert(codec.error_of(info) == .None)
		mark := u64(codec.success_of(info).consumed)
		if item.kind == "blob" {
			length := codec.owned_blob_length(owner, 0)
			assert(codec.error_of(length) == .None)
			mark ~= u64(codec.success_of(length))
		} else {
			fields := codec.owned_digest_info(owner)
			assert(codec.error_of(fields) == .None)
			value := codec.success_of(fields)
			mark ~= u64(value.service) ~ u64(value.accumulate_gas) ~ u64(value.refine.gas_used)
		}
		rb_observe(&decoded, size_of(decoded))
		return mark
	}
	// Caller-owned destination storage is stable across partial work; no measured allocation occurs here.
	if item.operation == "encode" {
		written: int
		if item.kind == "blob" {
			encoded := codec.encode_bytes(
				item.wire[item.offset:item.offset + item.length],
				codec.Byte_Limit(1048576),
				item.output,
			)
			assert(codec.error_of(encoded) == .None)
			written = codec.success_of(encoded).written
		} else if item.kind == "sequence" {
			encoded := codec.encode_sequence(
				item.values,
				codec.Byte_Width(4),
				codec.Element_Limit(16384),
				item.output,
			)
			assert(codec.error_of(encoded) == .None)
			written = codec.success_of(encoded).written
		} else {
			encoded := codec.encode_digest_borrowed(
				item.digest,
				item.wire,
				codec.Byte_Limit(1048576),
				item.output,
			)
			assert(codec.error_of(encoded) == .None)
			written = codec.success_of(encoded).written
		}
		rb_observe(raw_data(item.output), uintptr(written))
		return wire_mark(item.output, written)
	}
	// Observe whole decode results and destination records so unreported fields cannot disappear under optimization.
	if item.kind == "blob" {
		decoded := codec.decode_bytes_borrowed(item.wire, codec.Byte_Limit(1048576))
		rb_observe(&decoded, size_of(decoded))
		assert(codec.error_of(decoded) == .None)
		value := codec.success_of(decoded)
		return u64(value.consumed) ~ u64(value.length)
	} else if item.kind == "sequence" {
		decoded := codec.decode_sequence(
			item.wire,
			codec.Byte_Width(4),
			codec.Element_Limit(16384),
			item.decoded_values,
		)
		rb_observe(&decoded, size_of(decoded))
		rb_observe(
			raw_data(item.decoded_values),
			uintptr(len(item.decoded_values) * size_of(codec.Fixed_Unsigned)),
		)
		assert(codec.error_of(decoded) == .None)
		value := codec.success_of(decoded)
		return u64(value.consumed) ~ u64(value.count)
	} else {
		decoded := codec.decode_digest_borrowed(item.wire, codec.Byte_Limit(1048576))
		rb_observe(&decoded, size_of(decoded))
		assert(codec.error_of(decoded) == .None)
		value := codec.success_of(decoded)
		return(
			u64(value.consumed) ~
			u64(value.value.service) ~
			u64(value.value.accumulate_gas) ~
			u64(value.value.refine.gas_used) \
		)
	}
}

// Read trusted fixtures, prepare nominal encode inputs and validate full inverse bytes before any timing.
prepare :: proc(kind, operation, path: string) -> Bench_Case {
	data, err := os.read_entire_file(path, context.allocator)
	assert(err == nil && len(data) <= 1048832)
	item := Bench_Case {
		kind      = kind,
		operation = operation,
		wire      = data,
		output    = make([]u8, max(1, len(data))),
	}
	switch kind {
	case "baseline":
		item.number = 17 // No codec in the overhead control.
	case "natural":
		decoded := codec.decode(data)
		assert(codec.error_of(decoded) == .None)
		value := codec.success_of(decoded)
		assert(value.consumed == len(data))
		item.number = u64(value.value)
		encoded := codec.encode(value.value)
		for byte, i in data { assert(encoded.bytes[i] == byte) } 	// Full preflight inverse, outside timing.
	case "fixed":
		decoded := codec.decode_fixed(data, codec.Byte_Width(len(data)))
		assert(codec.error_of(decoded) == .None)
		item.number = u64(codec.success_of(decoded).value)
		encoded := codec.encode_fixed(codec.success_of(decoded).value, codec.Byte_Width(len(data)))
		assert(codec.error_of(encoded) == .None)
		for byte, i in data { assert(codec.success_of(encoded).encoded.bytes[i] == byte) } 	// Fixed-width inverse.
	case "blob":
		decoded := codec.decode_bytes_borrowed(data, codec.Byte_Limit(1048576))
		assert(codec.error_of(decoded) == .None)
		value := codec.success_of(decoded)
		assert(value.consumed == len(data))
		item.offset, item.length = value.offset, value.length
	case "sequence":
		item.values_storage = make([]codec.Fixed_Unsigned, 16384)
		item.values = item.values_storage
		decoded := codec.decode_sequence(
			data,
			codec.Byte_Width(4),
			codec.Element_Limit(16384),
			item.values,
		)
		assert(codec.error_of(decoded) == .None)
		value := codec.success_of(decoded)
		assert(value.consumed == len(data))
		item.decoded_values = make([]codec.Fixed_Unsigned, max(1, value.count))
		item.length = value.count // Retain the original allocation length for its single release owner.
	case "digest":
		decoded := codec.decode_digest_borrowed(data, codec.Byte_Limit(1048576))
		assert(codec.error_of(decoded) == .None)
		value := codec.success_of(decoded)
		assert(value.consumed == len(data))
		item.digest = value.value
	case "blake2b":
		hashed := crypto.blake2b256(data)
		assert(crypto.error_of(hashed) == .None)
		bytes := crypto.success_of(hashed)
		fmt.print("HASH ")
		for byte in bytes { fmt.printf("%02x", byte) } 	// Independent Python oracle checks this actual digest.
		fmt.println()
	case:
		assert(false) // Undefined trusted case selections cannot silently become valid operations.
	}
	// Only owned encoding prepares a retained snapshot; other operations release their own owners per call.
	if operation == "owned-encode" {
		decoded :=
			codec.decode_owned_bytes(data, codec.Byte_Limit(1048576)) if kind == "blob" else codec.decode_owned_digest(data, codec.Byte_Limit(1048576))
		assert(codec.error_of(decoded) == .None)
		item.owner = codec.success_of(decoded)
	}
	// The logical values slice borrows an allocation retained separately for one correct allocator release.
	if kind == "sequence" { item.values = item.values_storage[:item.length] }
	mark := step(&item)
	fmt.println("VERIFY", mark)
	if (kind == "blob" || kind == "sequence" || kind == "digest") &&
	   (operation == "encode" || operation == "owned-encode") {
		for byte, i in data { assert(item.output[i] == byte) } 	// Full encoder output equivalence is untimed.
	}
	return item
}

// One bounded process prints native batch and operation timings, excluding Python startup/IPC and fixture parsing.
main :: proc() {
	_ = time.tick_now // The separately compiled allocation mode deliberately performs no timing.
	assert(len(os.args) == 7)
	tracking: mem.Tracking_Allocator
	_ = &tracking // Only the separately compiled allocation mode installs this tracker.
	when ALLOCATIONS {
		mem.tracking_allocator_init(&tracking, context.allocator)
		defer mem.tracking_allocator_destroy(&tracking)
		context.allocator = mem.tracking_allocator(&tracking) // Instrumentation has a separate binary, never timed as performance evidence.
	}
	item := prepare(os.args[1], os.args[2], os.args[3])
	defer {
		codec.destroy_owned(&item.owner)
		delete(
			item.wire,
		); delete(item.output); delete(item.values_storage); delete(item.decoded_values)
	}
	iterations, ok := strconv.parse_int(os.args[4])
	samples, samples_ok := strconv.parse_int(os.args[5])
	latency_samples, latency_ok := strconv.parse_int(os.args[6])
	assert(
		ok &&
		iterations >= 1 &&
		iterations <= 20000000 &&
		samples_ok &&
		samples >= 1 &&
		samples <= 31 &&
		latency_ok &&
		latency_samples >= 0 &&
		latency_samples <= 256,
	)
	checksum := u64(0)
	for _ in 0 ..< min(iterations, 64) { checksum ~= step(&item) } 	// Warm code/allocator paths before recording.
	when ALLOCATIONS {
		allocations, frees := tracking.total_allocation_count, tracking.total_free_count
		live, bytes := tracking.current_memory_allocated, tracking.total_memory_allocated
		for _ in 0 ..< iterations { checksum ~= step(&item) } 	// Count only real operations after setup/warmup.
		fmt.println(
			"ALLOC",
			iterations,
			tracking.total_allocation_count - allocations,
			tracking.total_free_count - frees,
			tracking.current_memory_allocated - live,
			tracking.total_memory_allocated - bytes,
		)
	} else {
		for _ in 0 ..< samples {
			started := time.tick_now()
			for _ in 0 ..< iterations { checksum ~= step(&item) } 	// Batch amortizes monotonic timer overhead.
			elapsed := i64(time.tick_diff(started, time.tick_now()))
			fmt.println("BATCH", iterations, elapsed)
		}
		latencies := make([]i64, latency_samples)
		defer delete(latencies)
		for sample in 0 ..< latency_samples {
			started := time.tick_now()
			checksum ~= step(&item)
			latencies[sample] = i64(time.tick_diff(started, time.tick_now())) // Real per-operation samples include timer overhead.
		}
		for elapsed in latencies { fmt.println("LATENCY", elapsed) }
	}
	fmt.println("END", checksum, rb_peak_rss())
}
