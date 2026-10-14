package tests

import codec "../codec"
import checks "../ownership_checks"
import "core:mem"
import "core:testing"

// Return a snapshot of local stack input; the owned copy must survive the original's scope and mutation.
escaped_owner :: proc(allocator: mem.Allocator) -> codec.Owned_Frame {
	temporary := [4]u8{2, 10, 20, 99}
	parsed := codec.decode_owned_bytes(temporary[:], codec.Byte_Limit(2), allocator)
	assert(codec.error_of(parsed) == .None)
	temporary[1] = 88
	return codec.success_of(parsed)
}

// Fail one chosen allocation stage while allowing cleanup to reach the tracked backing allocator.
Budget_Allocator :: struct {
	backing:   mem.Allocator,
	remaining: int,
}

// Delegate frees/queries normally; exhaust the budget only on real allocation requests.
budget_allocator_proc :: proc(
	data: rawptr,
	mode: mem.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	loc := #caller_location,
) -> (
	[]u8,
	mem.Allocator_Error,
) {
	budget := cast(^Budget_Allocator)data
	// Reject the selected allocation stage without preventing earlier allocations from being freed.
	if size > 0 && (mode == .Alloc || mode == .Alloc_Non_Zeroed) {
		// A zero budget models an allocator refusing this specific request.
		if budget.remaining == 0 {return nil, .Out_Of_Memory}
		budget.remaining -= 1
	}
	return budget.backing.procedure(
		budget.backing.data,
		mode,
		size,
		alignment,
		old_memory,
		old_size,
		loc,
	)
}

// Test mutation isolation, independent extraction copies, nested snapshots and atomic errors with tracked allocation cleanup.
@(test)
owned_snapshots :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	allocator := mem.tracking_allocator(&tracking)
	// Repeated successful and malformed requests must leave no live owner allocations after release.
	for iteration in 0 ..< 100 {
		frame := escaped_owner(allocator)
		alias := frame // Borrowing a handle during its owner's lifetime does not transfer ownership.
		info := codec.owned_info(frame)
		testing.expect(t, codec.error_of(info) == .None && codec.success_of(info).consumed == 3)
		payload: [2]u8
		testing.expect(
			t,
			codec.error_of(codec.copy_owned_blob(frame, 0, payload[:])) == .None &&
			payload == [2]u8{10, 20},
		)
		payload[0] = 55 // Modifying an extracted copy cannot alter retained payload bytes.
		testing.expect(
			t,
			codec.error_of(codec.copy_owned_blob(alias, 0, payload[:])) == .None &&
			payload == [2]u8{10, 20},
		)
		short := [1]u8{77}
		testing.expect(
			t,
			codec.error_of(codec.copy_owned_blob(frame, 0, short[:])) == .Output_Too_Small &&
			short[0] == 77,
		)
		testing.expect(
			t,
			codec.error_of(codec.encode_owned(frame, short[:])) == .Output_Too_Small &&
			short[0] == 77,
		)
		testing.expect(
			t,
			codec.error_of(codec.copy_owned_blob(frame, -1, short[:])) == .Invalid_Index,
		)
		testing.expect(
			t,
			codec.error_of(codec.copy_owned_blob(frame, 1, short[:])) == .Invalid_Index,
		)
		testing.expect(t, codec.error_of(codec.owned_digest_info(frame)) == .Wrong_Schema)
		codec.destroy_owned(&frame)
		testing.expect(
			t,
			frame == nil && codec.error_of(codec.owned_info(frame)) == .Invalid_Owner,
		)
		codec.destroy_owned(&frame) // Releasing the same cleared owner twice is harmless; aliases must never be released.
		limits := codec.Preimage_Limits {
			codec.Element_Limit(2),
			codec.Byte_Limit(2),
			codec.Byte_Limit(2),
		}
		wire := [14]u8{2, 1, 0, 0, 0, 2, 10, 20, 2, 0, 0, 0, 0, 99}
		parsed := codec.decode_owned_preimages(wire[:], limits, allocator)
		testing.expect(t, codec.error_of(parsed) == .None)
		records := codec.success_of(parsed)
		wire[6] = 66 // Both nested blobs must stay bound to their immutable snapshot.
		testing.expect(
			t,
			codec.success_of(codec.owned_service(records, 0)) == codec.Service_Index(1),
		)
		testing.expect(
			t,
			codec.success_of(codec.owned_service(records, 1)) == codec.Service_Index(2),
		)
		testing.expect(
			t,
			codec.success_of(codec.copy_owned_blob(records, 0, payload[:])) == 2 &&
			payload == [2]u8{10, 20},
		)
		testing.expect(t, codec.success_of(codec.copy_owned_blob(records, 1, short[:])) == 0)
		testing.expect(t, codec.success_of(codec.owned_info(records)).consumed == 13)
		codec.destroy_owned(&records)
		malformed := [12]u8{2, 1, 0, 0, 0, 1, 7, 2, 0, 0, 0, 1}
		testing.expect(
			t,
			codec.error_of(codec.decode_owned_preimages(malformed[:], limits, allocator)) ==
			.Truncated,
		)
		testing.expect(t, len(tracking.allocation_map) == 0)
	}
	limits := codec.Preimage_Limits {
		codec.Element_Limit(1),
		codec.Byte_Limit(1),
		codec.Byte_Limit(1),
	}
	valid_record := [7]u8{1, 7, 0, 0, 0, 1, 10}
	// Refuse record, wire and owner-header allocation separately, then allow a complete successful allocation.
	for budget_count in 0 ..< 4 {
		budget := Budget_Allocator{allocator, budget_count}
		failing := mem.Allocator {
			procedure = budget_allocator_proc,
			data      = &budget,
		}
		parsed := codec.decode_owned_preimages(valid_record[:], limits, failing)
		// Three successful allocations are required for this nonempty record frame.
		if budget_count < 3 {
			testing.expect(t, codec.error_of(parsed) == .Allocation_Failure)
		} else {
			// Successful owners must free through their original allocator, even after context changes.
			testing.expect(t, codec.error_of(parsed) == .None)
			frame := codec.success_of(parsed)
			codec.destroy_owned(&frame)
		}
		testing.expect(t, len(tracking.allocation_map) == 0)
	}
	digest_wire: [128]u8
	blob := [2]u8{10, 20}
	digest := codec.Work_Digest {
		service = codec.Service_Index(7),
		accumulate_gas = codec.Gas(9),
		output = codec.Blob_Span{0, 2},
		refine = codec.Refine_Load{gas_used = codec.Gas(10)},
	}
	written := codec.encode_digest_borrowed(digest, blob[:], codec.Byte_Limit(2), digest_wire[:])
	testing.expect(t, codec.error_of(written) == .None)
	parsed_digest := codec.decode_owned_digest(digest_wire[:], codec.Byte_Limit(2), allocator)
	testing.expect(t, codec.error_of(parsed_digest) == .None)
	frame_digest := codec.success_of(parsed_digest)
	digest_wire[78] = 99 // Full-frame payload coordinates must refer to the retained copy, not this mutated wire.
	payload: [2]u8
	testing.expect(
		t,
		codec.success_of(codec.copy_owned_blob(frame_digest, 0, payload[:])) == 2 &&
		payload == [2]u8{10, 20},
	)
	testing.expect(
		t,
		codec.success_of(codec.owned_digest_info(frame_digest)).service == codec.Service_Index(7),
	)
	codec.destroy_owned(&frame_digest)
	absent_wire := [1]u8{0}
	absent := codec.success_of(
		codec.decode_owned_optional(absent_wire[:], codec.Byte_Limit(0), allocator),
	)
	_, absent_ok := codec.success_of(codec.owned_optional_info(absent)).(codec.Owned_Absent)
	testing.expect(t, absent_ok)
	codec.destroy_owned(&absent)
	empty_wire := [2]u8{1, 0}
	empty := codec.success_of(
		codec.decode_owned_optional(empty_wire[:], codec.Byte_Limit(0), allocator),
	)
	present, present_ok := codec.success_of(codec.owned_optional_info(empty)).(codec.Owned_Present)
	testing.expect(t, present_ok && present.length == 0)
	codec.destroy_owned(&empty)
	work_wire := [1]u8{1}
	work := codec.success_of(codec.decode_owned_work(work_wire[:], codec.Byte_Limit(0), allocator))
	work_error, work_ok := codec.success_of(codec.owned_work_info(work)).(codec.Work_Error)
	testing.expect(t, work_ok && work_error == .Out_Of_Gas)
	codec.destroy_owned(&work)
	// Allocation refusal is a typed failure rather than a null-success handle.
	bytes_wire := [2]u8{1, 7}
	testing.expect(
		t,
		codec.error_of(
			codec.decode_owned_bytes(bytes_wire[:], codec.Byte_Limit(1), mem.nil_allocator()),
		) ==
		.Allocation_Failure,
	)
	testing.expect(t, len(tracking.allocation_map) == 0)
}

// Compare all owned schemas with borrowed failures/values over deterministic malformed/truncated random input.
@(test)
owned_fuzz :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	context.allocator = mem.tracking_allocator(&tracking)
	random: u64 = 0x4a414d
	fuzz: [96]u8
	limits := codec.Preimage_Limits {
		codec.Element_Limit(2),
		codec.Byte_Limit(2),
		codec.Byte_Limit(2),
	}
	// Exercise all five framing schemas on the same 10000-input corpus.
	for trial in 0 ..< 10000 {
		random = random * 6364136223846793005 + 1
		size := int(random % u64(len(fuzz) + 1))
		// Vary each byte so tags, length prefixes, nested tuples and digest metrics are tested.
		for index in 0 ..< size {random = random * 6364136223846793005 + 1; fuzz[index] = u8(random >> 56)}
		input := fuzz[:size]
		bytes := codec.decode_bytes_borrowed(input, codec.Byte_Limit(64))
		owned_bytes := codec.decode_owned_bytes(input, codec.Byte_Limit(64))
		testing.expect(t, cast(int)codec.error_of(owned_bytes) == cast(int)codec.error_of(bytes))
		// Only successful owned results need release and byte-for-byte snapshot validation.
		if codec.error_of(owned_bytes) == .None {
			frame := codec.success_of(owned_bytes); codec.destroy_owned(&frame)
			checks.check_bytes(input, codec.Byte_Limit(64), bytes)
		}
		optional := codec.decode_optional_borrowed(input, codec.Byte_Limit(64))
		owned_optional := codec.decode_owned_optional(input, codec.Byte_Limit(64))
		testing.expect(
			t,
			cast(int)codec.error_of(owned_optional) == cast(int)codec.error_of(optional),
		)
		if codec.error_of(owned_optional) == .None {
			// Both optional alternatives must match and free their retained snapshots.
			frame := codec.success_of(owned_optional); codec.destroy_owned(&frame)
			checks.check_optional(input, codec.Byte_Limit(64), optional)
		}
		work := codec.decode_work_borrowed(input, codec.Byte_Limit(64))
		owned_work := codec.decode_owned_work(input, codec.Byte_Limit(64))
		testing.expect(t, cast(int)codec.error_of(owned_work) == cast(int)codec.error_of(work))
		if codec.error_of(owned_work) == .None {
			// Successful payloads and work-error values have the same canonical wire image.
			frame := codec.success_of(owned_work); codec.destroy_owned(&frame)
			checks.check_work(input, codec.Byte_Limit(64), work)
		}
		digest := codec.decode_digest_borrowed(input, codec.Byte_Limit(64))
		owned_digest := codec.decode_owned_digest(input, codec.Byte_Limit(64))
		testing.expect(t, cast(int)codec.error_of(owned_digest) == cast(int)codec.error_of(digest))
		if codec.error_of(owned_digest) == .None {
			// The final suffix metric must be validated in both decoding paths.
			frame := codec.success_of(owned_digest); codec.destroy_owned(&frame)
			checks.check_digest(input, codec.Byte_Limit(64), digest)
		}
		records: [2]codec.Preimage
		preimages := codec.decode_preimages_borrowed(input, limits, records[:])
		owned_preimages := codec.decode_owned_preimages(input, limits)
		testing.expect(
			t,
			cast(int)codec.error_of(owned_preimages) == cast(int)codec.error_of(preimages),
		)
		if codec.error_of(owned_preimages) == .None {
			// All nested service IDs and blobs must stay associated with one frame owner.
			frame := codec.success_of(owned_preimages); codec.destroy_owned(&frame)
			checks.check_preimages(input, limits, preimages, records[:])
		}
		testing.expect(t, len(tracking.allocation_map) == 0)
	}
}
