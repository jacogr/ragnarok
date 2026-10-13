package codec

// An unsigned wire value distinct from raw u64 and general Natural values.
// Definition: Gray Paper v0.7.1 C.1.7; see spec/fixed-unsigned.md.
Fixed_Unsigned :: distinct u64
// The signed byte count is validated by each API; supported counts are zero through eight.
Byte_Width :: distinct int
// Owns its storage; length selects the encoded prefix, which can be empty for zero width.
Encoded_Fixed :: struct {
	bytes:  [8]u8,
	length: int,
}
// None marks success; other tags distinguish invalid widths, overflowing values and short input.
Fixed_Error :: enum {
	None,
	Invalid_Width,
	Value_Out_Of_Range,
	Truncated,
}
// Check error before reading encoded; failure returns zero storage and produces no partial output.
Fixed_Encode_Result :: struct {
	encoded: Encoded_Fixed,
	error:   Fixed_Error,
}
// Check error before reading value/consumed; failure returns both as zero.
Fixed_Decode_Result :: struct {
	value:    Fixed_Unsigned,
	consumed: int,
	error:    Fixed_Error,
}

// Encode exactly width bytes in caller-owned value storage; no allocator is used.
encode_fixed :: proc(value: Fixed_Unsigned, width: Byte_Width) -> Fixed_Encode_Result {
	count := int(width)
	// Reject negative and unsupported widths before any conversion to an unsigned shift amount.
	if count < 0 || count > 8 {
		return {error = .Invalid_Width}
	}
	x := u64(value)
	// Width eight accepts all u64 values. For smaller widths check the upper bound first,
	// so no bits are silently discarded; width zero accepts only zero.
	if count < 8 && x >= u64(1) << uint(8 * count) {
		return {error = .Value_Out_Of_Range}
	}
	encoded := Encoded_Fixed {
		length = count,
	}
	// Extract low octets first. The zero-width case does not enter the loop,
	// and every narrowing conversion is bounded by the byte mask.
	for i in 0 ..< count {
		encoded.bytes[i] = u8((x >> uint(8 * i)) & 255)
	}
	return {encoded = encoded}
}

// Decode exactly width borrowed bytes. Input does not escape and no allocator is used.
decode_fixed :: proc(input: []u8, width: Byte_Width) -> Fixed_Decode_Result {
	count := int(width)
	// Reject invalid widths before inspecting the buffer, even when it contains many bytes.
	if count < 0 || count > 8 {
		return {error = .Invalid_Width}
	}
	// Require the entire fixed-width field before reading any of its octets.
	if len(input) < count {
		return {error = .Truncated}
	}
	x: u64
	// Merge little-endian octets with shifts no larger than 56 bits.
	// Zero width reads nothing and returns zero; trailing bytes always remain unread.
	for i in 0 ..< count {
		x |= u64(input[i]) << uint(8 * i)
	}
	return {value = Fixed_Unsigned(x), consumed = count}
}
