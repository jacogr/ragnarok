package tests
import codec "../codec"
import "core:slice"
import "core:testing"

// Test natural-length transitions, borrowed payload spans, exact consumption and every truncation.
check_blob :: proc(t: ^testing.T, size: int) {
	value: [16384]u8
	// Recognizable payload bytes detect incorrect offsets, prefix corruption and omitted bytes.
	for i in 0 ..< size { value[i] = u8(i % 256) }
	wire: [16394]u8
	encoded := codec.encode_bytes(value[:size], codec.Byte_Limit(size), wire[:])
	testing.expect(t, codec.error_of(encoded) == .None)
	wire[codec.success_of(encoded).written] = 42
	decoded := codec.decode_bytes_borrowed(
		wire[:codec.success_of(encoded).written + 1],
		codec.Byte_Limit(size),
	)
	testing.expect(
		t,
		codec.error_of(decoded) == .None &&
		codec.success_of(decoded).length == size &&
		codec.success_of(decoded).consumed == codec.success_of(encoded).written,
	)
	// The decoder's indices must identify the exact original payload rather than its prefix or trailing byte.
	for i in 0 ..< size { testing.expect(t, wire[codec.success_of(decoded).offset + i] == value[i]) }
	// Every incomplete container must fail without exposing a valid span or consumed count.
	for cut in 0 ..< codec.success_of(encoded).written {
		short := codec.decode_bytes_borrowed(wire[:cut], codec.Byte_Limit(size))
		testing.expect(t, codec.error_of(short) == .Truncated)
	}
	small := [1]u8{77}
	// A nonempty payload cannot fit a single header byte; policy failures take priority too.
	if size > 0 {
		testing.expect(
			t,
			codec.error_of(codec.encode_bytes(value[:size], codec.Byte_Limit(size), small[:])) ==
			.Output_Too_Small,
		)
		testing.expect(t, small[0] == 77)
		testing.expect(
			t,
			codec.error_of(codec.decode_bytes_borrowed(wire[:], codec.Byte_Limit(size - 1))) ==
			.Limit_Exceeded,
		)
		testing.expect(
			t,
			codec.error_of(
				codec.encode_bytes(value[:size], codec.Byte_Limit(size - 1), small[:]),
			) ==
			.Limit_Exceeded,
		)
	}
}

// Test counts and all fixed strides, including zero wire bytes per bounded zero-valued element.
check_sequence :: proc(t: ^testing.T, count, stride: int) {
	values: [128]codec.Fixed_Unsigned
	// Width zero permits only zero; other widths use changing small values that fit one byte.
	for i in 0 ..< count {
		if stride > 0 { values[i] = codec.Fixed_Unsigned(i % 256) }
	}
	wire: [1034]u8
	encoded := codec.encode_sequence(
		values[:count],
		codec.Byte_Width(stride),
		codec.Element_Limit(count),
		wire[:],
	)
	testing.expect(t, codec.error_of(encoded) == .None)
	output: [129]codec.Fixed_Unsigned
	output[count] = codec.Fixed_Unsigned(999)
	wire[codec.success_of(encoded).written] = 42
	decoded := codec.decode_sequence(
		wire[:codec.success_of(encoded).written + 1],
		codec.Byte_Width(stride),
		codec.Element_Limit(count),
		output[:],
	)
	testing.expect(
		t,
		codec.error_of(decoded) == .None &&
		codec.success_of(decoded).count == count &&
		codec.success_of(decoded).consumed == codec.success_of(encoded).written,
	)
	testing.expect(t, u64(output[count]) == 999)
	// Only the initialized result prefix may change, and it must match the original values.
	for i in 0 ..< count { testing.expect(t, output[i] == values[i]) }
	// All wire truncations fail before overwriting the first caller-owned output element.
	for cut in 0 ..< codec.success_of(encoded).written {
		output[0] = codec.Fixed_Unsigned(777)
		short := codec.decode_sequence(
			wire[:cut],
			codec.Byte_Width(stride),
			codec.Element_Limit(count),
			output[:],
		)
		testing.expect(t, codec.error_of(short) == .Truncated && u64(output[0]) == 777)
	}
}

// Arbitrary-input entry point checks byte spans and exact sequence re-encoding, with atomic failures.
fuzz_bounded :: proc(t: ^testing.T, input: []u8, stride: int, limit: u64) {
	blob := codec.decode_bytes_borrowed(input, codec.Byte_Limit(limit))
	// Every successful span must be bounded by both input size and the caller's resource limit.
	if codec.error_of(blob) == .None {
		testing.expect(
			t,
			codec.success_of(blob).offset + codec.success_of(blob).length ==
				codec.success_of(blob).consumed &&
			codec.success_of(blob).consumed <= len(input),
		)
		testing.expect(t, u64(codec.success_of(blob).length) <= limit)
		prefix := codec.encode(codec.Natural(codec.success_of(blob).length))
		testing.expect(t, prefix.length == codec.success_of(blob).offset)
		// The returned span must begin immediately after the exact canonical encoding of its length.
		for i in 0 ..< prefix.length { testing.expect(t, input[i] == prefix.bytes[i]) }
	}
	output: [8]codec.Fixed_Unsigned
	// Sentinels expose partial output writes on any failing decode path.
	for &item in output { item = codec.Fixed_Unsigned(999) }
	decoded := codec.decode_sequence(
		input,
		codec.Byte_Width(stride),
		codec.Element_Limit(limit),
		output[:],
	)
	// Successful results must re-encode to the complete canonical container prefix they consumed.
	if codec.error_of(decoded) == .None {
		wire: [73]u8
		encoded := codec.encode_sequence(
			output[:codec.success_of(decoded).count],
			codec.Byte_Width(stride),
			codec.Element_Limit(limit),
			wire[:],
		)
		testing.expect(
			t,
			codec.error_of(encoded) == .None &&
			codec.success_of(encoded).written == codec.success_of(decoded).consumed,
		)
		// Compare header and every element byte, leaving unrelated trailing data out of the comparison.
		for i in 0 ..< codec.success_of(decoded).consumed { testing.expect(t, wire[i] == input[i]) }
	} else {
		// Failed decodes have no initialized result prefix and must preserve every output sentinel.
		testing.expect(t, codec.error_of(decoded) != .None)
		for item in output { testing.expect(t, u64(item) == 999) }
	}
}

// Cover bounds, failed-write atomicity, alias safety and reproducible arbitrary inputs.
@(test)
bounded :: proc(t: ^testing.T) {
	sizes := [8]int{0, 1, 127, 128, 255, 256, 16383, 16384}
	// Blob sizes include one-, two- and three-octet natural prefix boundaries.
	for size in sizes { check_blob(t, size) }
	counts := [4]int{0, 1, 127, 128}
	// Counts and every width combine empty containers with multi-octet length prefixes.
	for stride in 0 ..= 8 {
		for count in counts { check_sequence(t, count, stride) }
	}
	noncanonical := [2]u8{128, 0}
	testing.expect(
		t,
		codec.error_of(codec.decode_bytes_borrowed(noncanonical[:], codec.Byte_Limit(max(u64)))) ==
		.Non_Canonical,
	)
	huge := codec.encode(codec.Natural(max(u64)))
	values := [2]codec.Fixed_Unsigned{77, 0}
	testing.expect(
		t,
		codec.error_of(
			codec.decode_sequence(
				huge.bytes[:],
				codec.Byte_Width(0),
				codec.Element_Limit(max(u64)),
				values[:],
			),
		) ==
		.Output_Too_Small,
	)
	testing.expect(
		t,
		codec.error_of(
			codec.decode_sequence(
				huge.bytes[:],
				codec.Byte_Width(8),
				codec.Element_Limit(max(u64)),
				values[:],
			),
		) ==
		.Truncated,
	)
	testing.expect(
		t,
		codec.error_of(
			codec.decode_sequence(
				huge.bytes[:],
				codec.Byte_Width(0),
				codec.Element_Limit(2),
				values[:],
			),
		) ==
		.Limit_Exceeded,
	)
	wire: [32]u8
	// Fill the destination before deliberately rejecting a late overflowing element.
	for &b in wire { b = 77 }
	bad := [2]codec.Fixed_Unsigned{1, 256}
	testing.expect(
		t,
		codec.error_of(
			codec.encode_sequence(bad[:], codec.Byte_Width(1), codec.Element_Limit(2), wire[:]),
		) ==
		.Value_Out_Of_Range,
	)
	for b in wire { testing.expect(t, b == 77) }
	testing.expect(
		t,
		codec.error_of(
			codec.encode_sequence(bad[:], codec.Byte_Width(0), codec.Element_Limit(2), wire[:]),
		) ==
		.Value_Out_Of_Range,
	)
	testing.expect(
		t,
		codec.error_of(
			codec.encode_sequence(nil, codec.Byte_Width(-1), codec.Element_Limit(0), wire[:]),
		) ==
		.Invalid_Width,
	)
	alias: [16]u8
	// In-place encoding is explicitly rejected before its prefix can clobber the input payload.
	for &b in alias { b = 77 }
	testing.expect(
		t,
		codec.error_of(codec.encode_bytes(alias[:4], codec.Byte_Limit(4), alias[:])) ==
		.Aliased_Buffers,
	)
	for b in alias { testing.expect(t, b == 77) }
	typed_bytes := slice.bytes_from_ptr(raw_data(values[:]), 16)
	testing.expect(
		t,
		codec.error_of(
			codec.encode_sequence(
				values[:],
				codec.Byte_Width(1),
				codec.Element_Limit(2),
				typed_bytes,
			),
		) ==
		.Aliased_Buffers,
	)
	typed_bytes[0] = 1
	typed_bytes[1] = 42
	testing.expect(
		t,
		codec.error_of(
			codec.decode_sequence(
				typed_bytes,
				codec.Byte_Width(1),
				codec.Element_Limit(2),
				values[:],
			),
		) ==
		.Aliased_Buffers,
	)
	// Output that overlaps only a trailing field must not destroy that field on success.
	testing.expect(
		t,
		codec.error_of(
			codec.decode_sequence(
				typed_bytes,
				codec.Byte_Width(1),
				codec.Element_Limit(2),
				values[1:],
			),
		) ==
		.Aliased_Buffers,
	)
	testing.expect(t, u64(values[1]) == 0)
	state := u64(0x424f554e44)
	// Vary wire length, stride and resource limit together with a reproducible seed.
	for iteration in 0 ..< 10000 {
		input: [32]u8
		// This xorshift generator supplies deterministic test bytes, not cryptographic material.
		for &b in input {
			state ~= state << 13
			state ~= state >> 7
			state ~= state << 17
			b = u8(state & 255)
		}
		fuzz_bounded(t, input[:iteration % 33], iteration % 13 - 2, u64(iteration % 12))
	}
}
