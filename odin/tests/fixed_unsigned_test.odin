package tests
import codec "../codec"
import "core:testing"

// Check round-trip value/length, every short prefix, and preservation of an unrelated next byte.
check_fixed :: proc(t: ^testing.T, x: u64, count: int) {
	encoded := codec.encode_fixed(codec.Fixed_Unsigned(x), codec.Byte_Width(count))
	testing.expect(
		t,
		codec.error_of(encoded) == .None && codec.success_of(encoded).encoded.length == count,
	)
	// Keep the successful fixed value addressable while lending its byte slices.
	encoded_storage := codec.success_of(encoded).encoded
	decoded := codec.decode_fixed(encoded_storage.bytes[:count], codec.Byte_Width(count))
	testing.expect(
		t,
		codec.error_of(decoded) == .None &&
		u64(codec.success_of(decoded).value) == x &&
		codec.success_of(decoded).consumed == count,
	)
	// A valid positive-width field cannot be decoded from any proper prefix.
	for size in 0 ..< count {
		short := codec.decode_fixed(encoded_storage.bytes[:size], codec.Byte_Width(count))
		testing.expect(t, codec.error_of(short) == .Truncated)
	}
	padded: [9]u8
	copy(padded[:], encoded_storage.bytes[:count])
	padded[count] = 42
	prefix := codec.decode_fixed(padded[:count + 1], codec.Byte_Width(count))
	testing.expect(
		t,
		codec.error_of(prefix) == .None &&
		codec.success_of(prefix).consumed == count &&
		u64(codec.success_of(prefix).value) == x,
	)
}

// Fuzz entry point: all complete patterns are valid, while width/length failures consume nothing.
fuzz_fixed :: proc(t: ^testing.T, input: []u8, width: codec.Byte_Width) {
	decoded := codec.decode_fixed(input, width)
	count := int(width)
	// Invalid widths take priority over missing input and must never reach a shift or access.
	if count < 0 || count > 8 {
		testing.expect(t, codec.error_of(decoded) == .Invalid_Width)
	} else if len(input) < count {
		// For supported widths, require all bytes before returning a value.
		testing.expect(t, codec.error_of(decoded) == .Truncated)
	} else {
		// All full-width byte patterns, including high zero bytes, must round-trip unchanged.
		testing.expect(
			t,
			codec.error_of(decoded) == .None && codec.success_of(decoded).consumed == count,
		)
		encoded := codec.encode_fixed(codec.success_of(decoded).value, width)
		testing.expect(
			t,
			codec.error_of(encoded) == .None && codec.success_of(encoded).encoded.length == count,
		)
		// Compare only the consumed bytes; trailing bytes are a subsequent caller-owned field.
		for i in 0 ..< count {
			testing.expect(t, codec.success_of(encoded).encoded.bytes[i] == input[i])
		}
	}
}

// Exhaust small domains, width/bit boundaries and checked failure paths, then fuzz arbitrary bytes.
@(test)
fixed_unsigned :: proc(t: ^testing.T) {
	// These loops cover every possible one-byte and two-byte value.
	for x in u64(0) ..< 256 { check_fixed(t, x, 1) }
	for x in u64(0) ..< 65536 { check_fixed(t, x, 2) }
	// Cover all widths rather than restricting the API to machine-size fields.
	for count in 0 ..= 8 {
		maximum := max(u64)
		// Avoid a shift by 64: eight bytes use the native maximum directly.
		if count < 8 { maximum = (u64(1) << uint(8 * count)) - 1 }
		check_fixed(t, 0, count)
		check_fixed(t, maximum, count)
		check_fixed(t, maximum / 2, count)
		// Reject the first overflowing value for each narrower width, including width zero.
		if count < 8 {
			overflow := codec.encode_fixed(
				codec.Fixed_Unsigned(maximum + 1),
				codec.Byte_Width(count),
			)
			testing.expect(t, codec.error_of(overflow) == .Value_Out_Of_Range)
		}
		// Check both sides of every internal power of two to exercise byte placement.
		for bits in 1 ..< 8 * count {
			pivot := u64(1) << uint(bits)
			check_fixed(t, pivot - 1, count)
			check_fixed(t, pivot, count)
			check_fixed(t, pivot + 1, count)
		}
	}
	// Width extremes must fail safely even when input is empty or a value could otherwise fit.
	invalid_widths := [4]int{min(int), -1, 9, max(int)}
	for count in invalid_widths {
		encoded := codec.encode_fixed(codec.Fixed_Unsigned(0), codec.Byte_Width(count))
		testing.expect(t, codec.error_of(encoded) == .Invalid_Width)
		fuzz_fixed(t, nil, codec.Byte_Width(count))
	}
	state := u64(0x4a414d)
	// Repeatable byte cases include empty buffers, incomplete fields and unsupported widths.
	for iteration in 0 ..< 10000 {
		bytes: [12]u8
		// Generate deterministic xorshift bytes without allocating storage.
		for &b in bytes {
			state ~= state << 13
			state ~= state >> 7
			state ~= state << 17
			b = u8(state & 255)
		}
		fuzz_fixed(t, bytes[:iteration % 13], codec.Byte_Width(iteration % 13 - 2))
	}
}
