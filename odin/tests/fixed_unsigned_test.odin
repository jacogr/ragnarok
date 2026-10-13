package tests
import codec "../codec"
import "core:testing"

// Check round-trip value/length, every short prefix, and preservation of an unrelated next byte.
check_fixed :: proc(t: ^testing.T, x: u64, count: int) {
	encoded := codec.encode_fixed(codec.Fixed_Unsigned(x), codec.Byte_Width(count))
	testing.expect(t, encoded.error == .None && encoded.encoded.length == count)
	decoded := codec.decode_fixed(encoded.encoded.bytes[:count], codec.Byte_Width(count))
	testing.expect(
		t,
		decoded.error == .None && u64(decoded.value) == x && decoded.consumed == count,
	)
	// A valid positive-width field cannot be decoded from any proper prefix.
	for size in 0 ..< count {
		short := codec.decode_fixed(encoded.encoded.bytes[:size], codec.Byte_Width(count))
		testing.expect(t, short.error == .Truncated && short.consumed == 0)
	}
	padded: [9]u8
	copy(padded[:], encoded.encoded.bytes[:count])
	padded[count] = 42
	prefix := codec.decode_fixed(padded[:count + 1], codec.Byte_Width(count))
	testing.expect(t, prefix.error == .None && prefix.consumed == count && u64(prefix.value) == x)
}

// Fuzz entry point: all complete patterns are valid, while width/length failures consume nothing.
fuzz_fixed :: proc(t: ^testing.T, input: []u8, width: codec.Byte_Width) {
	decoded := codec.decode_fixed(input, width)
	count := int(width)
	// Invalid widths take priority over missing input and must never reach a shift or access.
	if count < 0 || count > 8 {
		testing.expect(t, decoded.error == .Invalid_Width && decoded.consumed == 0)
	} else if len(input) < count {
		// For supported widths, require all bytes before returning a value.
		testing.expect(t, decoded.error == .Truncated && decoded.consumed == 0)
	} else {
		// All full-width byte patterns, including high zero bytes, must round-trip unchanged.
		testing.expect(t, decoded.error == .None && decoded.consumed == count)
		encoded := codec.encode_fixed(decoded.value, width)
		testing.expect(t, encoded.error == .None && encoded.encoded.length == count)
		// Compare only the consumed bytes; trailing bytes are a subsequent caller-owned field.
		for i in 0 ..< count {
			testing.expect(t, encoded.encoded.bytes[i] == input[i])
		}
	}
}

// Exhaust small domains, width/bit boundaries and checked failure paths, then fuzz arbitrary bytes.
@(test)
fixed_unsigned :: proc(t: ^testing.T) {
	// These loops cover every possible one-byte and two-byte value.
	for x in u64(0) ..< 256 {check_fixed(t, x, 1)}
	for x in u64(0) ..< 65536 {check_fixed(t, x, 2)}
	// Cover all widths rather than restricting the API to machine-size fields.
	for count in 0 ..= 8 {
		maximum := max(u64)
		// Avoid a shift by 64: eight bytes use the native maximum directly.
		if count < 8 {maximum = (u64(1) << uint(8 * count)) - 1}
		check_fixed(t, 0, count)
		check_fixed(t, maximum, count)
		check_fixed(t, maximum / 2, count)
		// Reject the first overflowing value for each narrower width, including width zero.
		if count < 8 {
			overflow := codec.encode_fixed(
				codec.Fixed_Unsigned(maximum + 1),
				codec.Byte_Width(count),
			)
			testing.expect(
				t,
				overflow.error == .Value_Out_Of_Range && overflow.encoded.length == 0,
			)
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
		testing.expect(t, encoded.error == .Invalid_Width && encoded.encoded.length == 0)
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
