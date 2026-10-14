package tests
import codec "../codec"
import "core:slice"
import "core:testing"

// Arbitrary-byte entry point: successful variants/records re-encode exactly and failures preserve typed storage.
fuzz_composite :: proc(t: ^testing.T, input: []u8) {
	wire: [128]u8
	optional := codec.decode_optional(input, codec.Byte_Limit(64))
	if codec.error_of(optional) == .None {
		// Successful absence/presence must reproduce the completed tag/blob prefix only.
		encoded := codec.encode_optional(
			codec.success_of(optional).value,
			input,
			codec.Byte_Limit(64),
			wire[:],
		)
		testing.expect(
			t,
			codec.error_of(encoded) == .None &&
			codec.success_of(encoded).written == codec.success_of(optional).consumed,
		)
		for i in 0 ..< codec.success_of(optional).consumed {testing.expect(t, wire[i] == input[i])} 	// Includes nested count.
	}
	work := codec.decode_work(input, codec.Byte_Limit(64))
	if codec.error_of(work) == .None {
		// The union's successful/error variant must retain its complete original wire representation.
		encoded := codec.encode_work(
			codec.success_of(work).value,
			input,
			codec.Byte_Limit(64),
			wire[:],
		)
		testing.expect(
			t,
			codec.error_of(encoded) == .None &&
			codec.success_of(encoded).written == codec.success_of(work).consumed,
		)
		for i in 0 ..< codec.success_of(work).consumed {testing.expect(t, wire[i] == input[i])} 	// Trailing bytes are excluded.
	}
	output: [4]codec.Preimage
	for &item in output {item = {
			service = codec.Service_Index(777),
			blob = {offset = 333, length = 444},
		}} // Failure sentinels.
	limits := codec.Preimage_Limits {
		codec.Element_Limit(4),
		codec.Byte_Limit(32),
		codec.Byte_Limit(64),
	}
	decoded := codec.decode_preimages(input, limits, output[:])
	if codec.error_of(decoded) == .None {
		// Input-relative span descriptors must reconstruct the entire proved nested frame.
		encoded := codec.encode_preimages(
			output[:codec.success_of(decoded).count],
			input,
			limits,
			wire[:],
		)
		testing.expect(
			t,
			codec.error_of(encoded) == .None &&
			codec.success_of(encoded).written == codec.success_of(decoded).consumed,
		)
		for i in 0 ..< codec.success_of(decoded).consumed {testing.expect(t, wire[i] == input[i])} 	// All records and lengths.
	} else {
		// A malformed last record must not expose an earlier partially initialized record.
		testing.expect(t, codec.error_of(decoded) != .None)
		// Check every field of every sentinel descriptor after a failure.
		for item in output {testing.expect(t, u32(item.service) == 777 && item.blob.offset == 333 && item.blob.length == 444)}
	}
}

// Check fixed tuple IDs, nested bounds, all known/unknown tags, atomic failures and alias protection.
@(test)
composite :: proc(t: ^testing.T) {
	pool := [3]u8{1, 2, 3}
	wire: [64]u8
	limits := codec.Preimage_Limits {
		codec.Element_Limit(2),
		codec.Byte_Limit(3),
		codec.Byte_Limit(3),
	}
	records := [2]codec.Preimage {
		{service = codec.Service_Index(7), blob = {offset = 0, length = 3}},
		{service = codec.Service_Index(max(u32)), blob = {offset = 3, length = 0}},
	}
	encoded := codec.encode_preimages(records[:], pool[:], limits, wire[:])
	testing.expect(t, codec.error_of(encoded) == .None && codec.success_of(encoded).written == 14)
	output: [2]codec.Preimage
	decoded := codec.decode_preimages(wire[:14], limits, output[:])
	testing.expect(
		t,
		codec.error_of(decoded) == .None &&
		codec.success_of(decoded).count == 2 &&
		codec.success_of(decoded).consumed == 14,
	)
	testing.expect(t, u32(output[0].service) == 7 && u32(output[1].service) == max(u32))
	testing.expect(
		t,
		output[0].blob.offset == 6 && output[0].blob.length == 3 && output[1].blob.length == 0,
	)
	for cut in 0 ..< 14 {
		// Every truncation, including the final record's length, leaves all caller-owned records unchanged.
		for &item in output {item.service = codec.Service_Index(999)}
		short := codec.decode_preimages(wire[:cut], limits, output[:])
		testing.expect(t, codec.error_of(short) == .Truncated)
		// Even records preceding the truncation must retain their original service.
		for item in output {testing.expect(t, u32(item.service) == 999)}
	}
	tighter := codec.Preimage_Limits {
		codec.Element_Limit(2),
		codec.Byte_Limit(3),
		codec.Byte_Limit(2),
	}
	testing.expect(
		t,
		codec.error_of(codec.decode_preimages(wire[:], tighter, output[:])) == .Limit_Exceeded,
	)
	for &b in wire {b = 77} 	// Preserve encoder output even when a late input descriptor is invalid.
	bad := records
	bad[1].blob.offset = max(int)
	bad[1].blob.length = 1
	testing.expect(
		t,
		codec.error_of(codec.encode_preimages(bad[:], pool[:], limits, wire[:])) == .Invalid_Span,
	)
	// Check the entire destination for a forbidden partial encoder commit.
	for b in wire {testing.expect(t, b == 77)}
	for tag in 1 ..= 6 {
		// All declared errors are payload-free and must not interpret unrelated trailing bytes.
		value := codec.Work_Output(codec.Work_Error(tag))
		testing.expect(
			t,
			codec.success_of(codec.encode_work(value, pool[:], codec.Byte_Limit(0), wire[:])).written ==
			1,
		)
		testing.expect(
			t,
			codec.success_of(codec.decode_work(wire[:], codec.Byte_Limit(0))).consumed == 1,
		)
	}
	wire[0] = 7
	testing.expect(
		t,
		codec.error_of(codec.decode_work(wire[:1], codec.Byte_Limit(0))) == .Invalid_Tag,
	)
	wire[0] = 2
	testing.expect(
		t,
		codec.error_of(codec.decode_optional(wire[:1], codec.Byte_Limit(0))) == .Invalid_Tag,
	)
	wire[0] = 128; wire[1] = 0
	testing.expect(
		t,
		codec.error_of(codec.decode_optional(wire[:2], codec.Byte_Limit(0))) == .Non_Canonical,
	)
	testing.expect(
		t,
		codec.error_of(
			codec.encode_work(
				codec.Work_Output(codec.Work_Error(0)),
				nil,
				codec.Byte_Limit(0),
				wire[:],
			),
		) ==
		.Invalid_Tag,
	)
	invalid := [3]codec.Blob_Span{{-1, 0}, {0, -1}, {max(int), max(int)}}
	for span in invalid {
		// Source endpoint checks must precede indexing and any potentially overflowing offset addition.
		testing.expect(
			t,
			codec.error_of(
				codec.encode_optional(
					{present = true, blob = span},
					pool[:],
					codec.Byte_Limit(max(u64)),
					wire[:],
				),
			) ==
			.Invalid_Span,
		)
	}
	raw := slice.bytes_from_ptr(raw_data(output[:]), size_of(output))
	for &b in raw {b = 0} 	// Create a valid frame inside overlapping typed destination storage.
	raw[0] = 1
	snapshot := output
	testing.expect(
		t,
		codec.error_of(codec.decode_preimages(raw, limits, output[1:])) == .Aliased_Buffers,
	)
	testing.expect(t, output[1].blob.offset == snapshot[1].blob.offset)
	// Protect the borrowed pool even when the present blob is empty and only headers would be written.
	pool_before := pool
	testing.expect(
		t,
		codec.error_of(
			codec.encode_optional(
				{present = true, blob = {0, 0}},
				pool[:],
				codec.Byte_Limit(0),
				pool[:],
			),
		) ==
		.Aliased_Buffers,
	)
	testing.expect(t, pool == pool_before)
	// Typed source descriptors must not be overwritten by a valid encoder's output.
	descriptors := records
	descriptors_before := descriptors
	descriptor_bytes := slice.bytes_from_ptr(raw_data(descriptors[:]), size_of(descriptors))
	testing.expect(
		t,
		codec.error_of(
			codec.encode_preimages(descriptors[:], pool[:], limits, descriptor_bytes),
		) ==
		.Aliased_Buffers,
	)
	testing.expect(t, descriptors == descriptors_before)
	state := u64(0x434f4d504f)
	for iteration in 0 ..< 10000 {
		// Reproducible arbitrary data varies every available prefix length from zero through 64.
		input: [64]u8
		// Deterministic xorshift supplies coverage bytes without cryptographic requirements.
		for &b in input {
			state ~= state << 13
			state ~= state >> 7
			state ~= state << 17
			b = u8(state & 255)
		}
		fuzz_composite(t, input[:iteration % 65])
	}
}
