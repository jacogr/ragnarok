package tests
import codec "../codec"
import "core:testing"

// Arbitrary-input entry point verifies complete metadata and reconstruction of every successful consumed prefix.
fuzz_digest :: proc(t: ^testing.T, input: []u8) {
	parsed := codec.decode_digest(input, codec.Byte_Limit(64))
	// Failed nested variants or metrics cannot advance the caller cursor.
	if parsed.error != .None {
		testing.expect(t, parsed.consumed == 0)
		return
	}
	bytes: [256]u8
	written := codec.encode_digest(parsed.value, input, codec.Byte_Limit(64), bytes[:])
	testing.expect(t, written.error == .None && written.written == parsed.consumed)
	// Check fixed fields, translated blob coordinates, and all five metrics.
	for i in 0 ..< written.written {testing.expect(t, bytes[i] == input[i])}
}

// Test the full C.2 tuple, exact nominal fields, every truncation, overlap, late output failure and fuzz reconstruction.
@(test)
work_digest :: proc(t: ^testing.T) {
	code, payload: [32]u8
	// Different patterns catch swapped or reversed hash fields.
	for i in 0 ..< 32 {code[i] = u8(i); payload[i] = u8(255 - i)}
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
	encoded := codec.encode_digest(value, pool[:], codec.Byte_Limit(3), wire[:])
	testing.expect(t, encoded.error == .None)
	decoded := codec.decode_digest(wire[:encoded.written], codec.Byte_Limit(3))
	testing.expect(t, decoded.error == .None && decoded.consumed == encoded.written)
	span := decoded.value.output.(codec.Blob_Span)
	testing.expect(t, span.offset == 78 && span.length == 3)
	testing.expect(
		t,
		u64(decoded.value.refine.imports) == 128 && u64(decoded.value.refine.exports) == max(u64),
	)
	fuzz_digest(t, wire[:encoded.written])
	// Every incomplete prefix, including each suffix byte, must fail without consuming input.
	for cut in 0 ..< encoded.written {
		short := codec.decode_digest(wire[:cut], codec.Byte_Limit(3))
		testing.expect(t, short.error == .Truncated && short.consumed == 0)
	}
	// Refill the entire destination to detect a premature fixed-prefix commit.
	for &b in wire {b = 77}
	short_write := codec.encode_digest(
		value,
		pool[:],
		codec.Byte_Limit(3),
		wire[:encoded.written - 1],
	)
	testing.expect(t, short_write.error == .Output_Too_Small && short_write.written == 0)
	// Include unused output storage in the atomic-failure check.
	for b in wire {testing.expect(t, b == 77)}
	value.output = codec.Blob_Span{0, 0}
	before := wire
	testing.expect(
		t,
		codec.encode_digest(value, wire[:], codec.Byte_Limit(0), wire[:]).error ==
		.Aliased_Buffers,
	)
	testing.expect(t, wire == before)
	value.output = codec.Blob_Span{max(int), 1}
	testing.expect(
		t,
		codec.encode_digest(value, pool[:], codec.Byte_Limit(3), wire[:]).error == .Invalid_Span,
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
