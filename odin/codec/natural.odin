package codec

// JAM general naturals. Pinned normative definition: spec/codec.md.
// A protocol natural, distinct from u64 so ordinary integer variables require an explicit conversion.
Natural :: distinct u64
// Owns the encoded bytes; length selects the wire prefix from the nine-byte storage.
Encoded_Natural :: struct {
	bytes:  [9]u8,
	length: int,
}
// None indicates success; the other tags distinguish missing bytes from an overlong representation.
Decode_Error :: enum {
	Uninitialized, // A default result is a failure with no validated payload.
	None,
	Truncated,
	Non_Canonical,
}
// Carries the decoded value and consumed count; check error before using them.
// These fields exist only in the successful alternative.
Decode_Success :: struct {
	value:    Natural,
	consumed: int,
}
// The failure alternative contains no success payload or metadata; nil is not an outcome.
Decode_Result :: Codec_Result(Decode_Success, Decode_Error)

// Returned storage belongs to the caller; no allocator is used.
// Encode the shortest JAM representation without using an allocator.
encode :: proc(value: Natural) -> (out: Encoded_Natural) {
	x := u64(value)
	// Large naturals use the ff marker and all eight little-endian payload bytes.
	if x >= u64(1) << 56 {
		out.length = 9
		out.bytes[0] = 255
	} else {
		// Smaller values use a compact header that also stores their high value bits.
		out.length = 1
		// Increase the total size until the value fits its seven-bits-per-step limit.
		// The preceding large-value branch guarantees this loop stops before a 64-bit shift.
		for x >= u64(1) << uint(7 * out.length) {
			out.length += 1
		}
		n := out.length - 1
		out.bytes[0] = u8(256 - (u64(1) << uint(8 - n)) + (x >> uint(8 * n)))
	}
	// Emit low bytes first; masking makes each conversion to u8 explicitly bounded.
	for i in 0 ..< out.length - 1 {
		out.bytes[i + 1] = u8((x >> uint(8 * i)) & 255)
	}
	return
}

// Borrows input only for this call. Decode one canonical prefix; trailing bytes
// belong to the caller. Errors carry no consumed/value fields and never allocate.
// Decode one canonical prefix from borrowed storage; leave any following bytes to the caller.
decode :: proc(input: []u8) -> Decode_Result {
	// Even zero requires a header byte, so an empty slice is truncated.
	if len(input) == 0 {
		return Decode_Error.Truncated
	}
	first := input[0]
	n := 0
	// Count leading one bits to determine the number of payload bytes.
	// A zero terminates the prefix; ff reaches the eight-byte case.
	for bit := u8(128); bit != 0 && (first & bit) != 0; bit >>= 1 {
		n += 1
	}
	// Validate the complete announced length before reading any payload byte.
	if len(input) < n + 1 {
		return Decode_Error.Truncated
	}
	x: u64
	// Compact headers contain the value bits above the payload; ff contains only the size marker.
	if n != 8 {
		x = u64(first & (u8(127) >> uint(n))) << uint(8 * n)
	}
	// Merge the little-endian payload into the value; shifts are bounded to 0..56 bits.
	for i in 0 ..< n {
		x |= u64(input[i + 1]) << uint(8 * i)
	}
	// Reject a value below this size threshold because a shorter encoding would suffice.
	if n != 0 && x < u64(1) << uint(7 * n) {
		return Decode_Error.Non_Canonical
	}
	return Decode_Success{value = Natural(x), consumed = n + 1}
}
