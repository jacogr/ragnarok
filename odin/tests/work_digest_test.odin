package tests
import codec "../codec"
import "core:testing"

// Arbitrary-input entry point verifies complete metadata and reconstruction of every successful consumed prefix.
fuzz_digest :: proc(t: ^testing.T, input: []u8) {
	parsed := codec.decode_digest_borrowed(input, codec.Byte_Limit(64))
	// Failed nested variants or metrics cannot advance the caller cursor.
	if codec.error_of(parsed) != .None {
		testing.expect(t, codec.error_of(parsed) != .None)
		return
	}
	bytes: [256]u8
	written := codec.encode_digest_borrowed(
		codec.success_of(parsed).value,
		input,
		codec.Byte_Limit(64),
		bytes[:],
	)
	testing.expect(
		t,
		codec.error_of(written) == .None &&
		codec.success_of(written).written == codec.success_of(parsed).consumed,
	)
	// Check fixed fields, translated blob coordinates, and all five metrics.
	for i in 0 ..< codec.success_of(written).written { testing.expect(t, bytes[i] == input[i]) }
}

// Test the full C.2 tuple, exact nominal fields, every truncation, overlap, late output failure and fuzz reconstruction.
@(test)
work_digest :: proc(t: ^testing.T) {
	code, payload: [32]u8
	// Different patterns catch swapped or reversed hash fields.
	for i in 0 ..< 32 { code[i] = u8(i); payload[i] = u8(255 - i) }
	pool := [3]u8{1, 2, 3}
	value := codec.Work_Digest {
		service        = codec.Service_Index(max(u32)),
		code_hash      = codec.Code_Hash(code),
		payload_hash   = codec.Payload_Hash(payload),
		accumulate_gas = codec.Gas(max(u64)),
		output         = codec.Work_Output(codec.Blob_Span{0, 3}),
		refine         = {
			codec.Gas(127),
			codec.Import_Count(128),
			codec.Extrinsic_Count(16384),
			codec.Extrinsic_Bytes(u64(1) << 56),
			codec.Export_Count(max(u64)),
		},
	}
	wire: [256]u8
	encoded := codec.encode_digest_borrowed(value, pool[:], codec.Byte_Limit(3), wire[:])
	testing.expect(t, codec.error_of(encoded) == .None)
	decoded := codec.decode_digest_borrowed(
		wire[:codec.success_of(encoded).written],
		codec.Byte_Limit(3),
	)
	testing.expect(
		t,
		codec.error_of(decoded) == .None &&
		codec.success_of(decoded).consumed == codec.success_of(encoded).written,
	)
	span := codec.success_of(decoded).value.output.(codec.Blob_Span)
	testing.expect(t, span.offset == 78 && span.length == 3)
	testing.expect(
		t,
		u64(codec.success_of(decoded).value.refine.imports) == 128 &&
		u64(codec.success_of(decoded).value.refine.exports) == max(u64),
	)
	fuzz_digest(t, wire[:codec.success_of(encoded).written])
	// Every incomplete prefix, including each suffix byte, must fail without consuming input.
	for cut in 0 ..< codec.success_of(encoded).written {
		short := codec.decode_digest_borrowed(wire[:cut], codec.Byte_Limit(3))
		testing.expect(t, codec.error_of(short) == .Truncated)
	}
	// Refill the entire destination to detect a premature fixed-prefix commit.
	for &b in wire { b = 77 }
	short_write := codec.encode_digest_borrowed(
		value,
		pool[:],
		codec.Byte_Limit(3),
		wire[:codec.success_of(encoded).written - 1],
	)
	testing.expect(t, codec.error_of(short_write) == .Output_Too_Small)
	// Include unused output storage in the atomic-failure check.
	for b in wire { testing.expect(t, b == 77) }
	value.output = codec.Blob_Span{0, 0}
	before := wire
	testing.expect(
		t,
		codec.error_of(
			codec.encode_digest_borrowed(value, wire[:], codec.Byte_Limit(0), wire[:]),
		) ==
		.Aliased_Buffers,
	)
	testing.expect(t, wire == before)
	value.output = codec.Blob_Span{max(int), 1}
	testing.expect(
		t,
		codec.error_of(
			codec.encode_digest_borrowed(value, pool[:], codec.Byte_Limit(3), wire[:]),
		) ==
		.Invalid_Span,
	)
	testing.expect(t, wire == before)
	state := u64(0x444947455354)
	// Longer arbitrary buffers exercise nested variants/metrics beyond the 76-byte fixed prefix.
	for iteration in 0 ..< 10000 {
		input: [160]u8
		// Deterministic xorshift supplies fuzz bytes rather than cryptographic randomness.
		for &b in input {
			state ~= state << 13; state ~= state >> 7; state ~= state << 17
			b = u8(state & 255)
		}
		fuzz_digest(t, input[:iteration % 161])
	}
}
