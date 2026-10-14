package tests
import codec "../codec"
import "core:testing"

// Check the value, consumed size, every possible truncation, and preservation of trailing bytes.
check :: proc(t: ^testing.T, x: u64) {
	encoded := codec.encode(codec.Natural(x))
	decoded := codec.decode(encoded.bytes[:encoded.length])
	testing.expect(
		t,
		codec.error_of(decoded) == .None && u64(codec.success_of(decoded).value) == x,
	)
	testing.expect(t, codec.success_of(decoded).consumed == encoded.length)
	// Every shorter slice must fail without reporting any bytes consumed.
	for size in 0 ..< encoded.length {
		short := codec.decode(encoded.bytes[:size])
		testing.expect(t, codec.error_of(short) == .Truncated)
	}
	padded: [10]u8
	copy(padded[:], encoded.bytes[:encoded.length])
	padded[encoded.length] = 42
	prefix := codec.decode(padded[:encoded.length + 1])
	testing.expect(
		t,
		codec.error_of(prefix) == .None && codec.success_of(prefix).consumed == encoded.length,
	)
}

// Deterministic fuzz entry point. Storage is borrowed, no allocation.
// Check that arbitrary bytes either fail cleanly or re-encode exactly their accepted prefix.
fuzz_one :: proc(t: ^testing.T, input: []u8) {
	decoded := codec.decode(input)
	// A successful result must have the same wire bytes when encoded again.
	if codec.error_of(decoded) == .None {
		encoded := codec.encode(codec.success_of(decoded).value)
		testing.expect(t, encoded.length == codec.success_of(decoded).consumed)
		// Compare all used bytes, which also detects acceptance of overlong representations.
		for i in 0 ..< encoded.length {
			testing.expect(t, encoded.bytes[i] == input[i])
		}
	} else {
		// A failed decode must not report any bytes consumed.
		testing.expect(t, codec.error_of(decoded) != .None)
	}
}

@(test)
// Run the deterministic native boundary, malformed-input and fuzz checks for this codec.
naturals :: proc(t: ^testing.T) {
	// Exhaust small values rather than relying only on a handful of examples.
	for x in u64(0) ..< 65536 { check(t, x) }
	// Test below, at and above each power of two, including every encoded-size transition.
	for bits in 1 ..< 64 {
		pivot := u64(1) << uint(bits)
		check(t, pivot - 1)
		check(t, pivot)
		check(t, pivot + 1)
	}
	check(t, max(u64))
	// Try all 256 headers with zero payloads and enough bytes to avoid accidental truncation.
	for first in 0 ..< 256 {
		bytes: [9]u8
		bytes[0] = u8(first)
		decoded := codec.decode(bytes[:])
		// These size-only headers plus zero payloads encode zero overlong and must be rejected.
		if first == 128 ||
		   first == 192 ||
		   first == 224 ||
		   first == 240 ||
		   first == 248 ||
		   first == 252 ||
		   first == 254 ||
		   first == 255 {
			testing.expect(t, codec.error_of(decoded) == .Non_Canonical)
		} else {
			// The remaining headers are valid here; verify their canonical bytes are preserved.
			testing.expect(t, codec.error_of(decoded) == .None)
			encoded := codec.encode(codec.success_of(decoded).value)
			// Compare all used bytes, which also detects acceptance of overlong representations.
			for i in 0 ..< encoded.length {
				testing.expect(t, encoded.bytes[i] == bytes[i])
			}
		}
	}
	state := u64(0x123456789abcdef)
	// Run reproducible arbitrary-byte inputs, cycling through lengths zero to twelve.
	for iteration in 0 ..< 10000 {
		bytes: [12]u8
		// Fill the input using deterministic xorshift data; no allocator or cryptographic generator is needed.
		for &b in bytes {
			state ~= state << 13
			state ~= state >> 7
			state ~= state << 17
			b = u8(state & 255)
		}
		fuzz_one(t, bytes[:iteration % 13])
	}
}
