package codec

// A byte resource ceiling, distinct from sequence counts. Gray Paper v0.7.1 C.1.2/C.1.3.
Byte_Limit :: distinct u64
// Counts remain bounded even for zero-width items; caller selects this resource policy.
Element_Limit :: distinct u64
// None marks success; errors distinguish wire failures, policy, storage, values and aliasing.
Container_Error :: enum {
	None,
	Truncated,
	Non_Canonical,
	Limit_Exceeded,
	Output_Too_Small,
	Invalid_Width,
	Value_Out_Of_Range,
	Aliased_Buffers,
	Length_Overflow,
}
// The caller owns encoded storage; written is zero on any failed operation.
Write_Result :: struct {
	written: int,
	error:   Container_Error,
}
// An index span into the original borrowed wire input; no pointer or allocation is retained.
Blob_Result :: struct {
	offset:   int,
	length:   int,
	consumed: int,
	error:    Container_Error,
}
// The initialized prefix of caller-owned typed output, or zero count/consumption on failure.
Sequence_Result :: struct {
	count:    int,
	consumed: int,
	error:    Container_Error,
}
// Internal validated frame; keep the untrusted count unsigned until capacity proves a host conversion safe.
Frame_Result :: struct {
	count:    u64,
	offset:   int,
	consumed: int,
	error:    Container_Error,
}

// Determine intersection using address differences, avoiding pointer-end overflow. Empty ranges do not alias.
container_overlaps :: proc(a: rawptr, a_len: int, b: rawptr, b_len: int) -> bool {
	// Empty buffers may have nil pointers and no bytes to overlap.
	if a_len == 0 || b_len == 0 {return false}
	left, right := uintptr(a), uintptr(b)
	// Measure from the earlier address so subtraction stays nonnegative without address-end addition.
	if left <= right {return right - left < uintptr(a_len)}
	return left - right < uintptr(b_len)
}

// Prove canonical length, resource limit and full payload before performing count * stride arithmetic.
read_frame :: proc(input: []u8, stride: int, limit: u64) -> Frame_Result {
	prefix := decode(input)
	// Map both natural-prefix failures without inspecting any payload bytes.
	switch prefix.error {
	// Missing prefix bytes make the complete container truncated too.
	case .Truncated:
		return {error = .Truncated}
	// Overlong counts are invalid even when the following payload would fit.
	case .Non_Canonical:
		return {error = .Non_Canonical}
	// A canonical natural permits the following count and resource checks.
	case .None:
	}
	count := u64(prefix.value)
	// Enforce policy before converting to int or allocating/writing any output.
	if count > limit {return {error = .Limit_Exceeded}}
	remaining := len(input) - prefix.consumed
	// Division prevents an attacker-controlled multiplication from overflowing before validation.
	if stride > 0 && count > u64(remaining / stride) {return {error = .Truncated}}
	payload: int
	// Positive stride proves count fits available host-indexed input; zero-width items occupy no payload.
	if stride > 0 {payload = int(count) * stride}
	return {count = count, offset = prefix.consumed, consumed = prefix.consumed + payload}
}

// Return a validated byte span; the caller keeps its input alive and advances only after success.
decode_bytes :: proc(input: []u8, limit: Byte_Limit) -> Blob_Result {
	frame := read_frame(input, 1, u64(limit))
	// Wire/policy failures expose no usable span and consume no bytes.
	if frame.error != .None {return {error = frame.error}}
	return {offset = frame.offset, length = int(frame.count), consumed = frame.consumed}
}

// Write a bounded byte string into separate caller-owned output, using no allocator.
encode_bytes :: proc(value: []u8, limit: Byte_Limit, output: []u8) -> Write_Result {
	// Resource policy precedes copying and host arithmetic.
	if u64(len(value)) > u64(limit) {return {error = .Limit_Exceeded}}
	prefix := encode(Natural(len(value)))
	// Subtraction validates prefix plus payload without summing unchecked lengths.
	if len(output) < prefix.length || len(value) > len(output) - prefix.length {
		return {error = .Output_Too_Small}
	}
	total := prefix.length + len(value)
	// Reject overlapping spans before writing the prefix, which could destroy borrowed payload bytes.
	if container_overlaps(raw_data(value), len(value), raw_data(output), total) {
		return {error = .Aliased_Buffers}
	}
	copy(output[:prefix.length], prefix.bytes[:prefix.length])
	copy(output[prefix.length:total], value)
	return {written = total}
}

// Encode fixed-width unsigned elements, preflighting every failure before writing any output byte.
encode_sequence :: proc(
	values: []Fixed_Unsigned,
	width: Byte_Width,
	limit: Element_Limit,
	output: []u8,
) -> Write_Result {
	stride := int(width)
	// Width validation is required even when values is empty.
	if stride < 0 || stride > 8 {return {error = .Invalid_Width}}
	// Width-zero elements still consume count resources and must satisfy the caller's limit.
	if u64(len(values)) > u64(limit) {return {error = .Limit_Exceeded}}
	prefix := encode(Natural(len(values)))
	// Prove output size by division before multiplying the count by stride.
	if len(output) < prefix.length ||
	   (stride > 0 && len(values) > (len(output) - prefix.length) / stride) {
		return {error = .Output_Too_Small}
	}
	// The input's typed-memory span must also have a representable byte size for alias detection.
	if len(values) > max(int) / size_of(Fixed_Unsigned) {return {error = .Length_Overflow}}
	total := prefix.length + len(values) * stride
	// Disallow output that can overwrite input elements during the later commit pass.
	if container_overlaps(
		raw_data(values),
		len(values) * size_of(Fixed_Unsigned),
		raw_data(output),
		total,
	) {
		return {error = .Aliased_Buffers}
	}
	// A late invalid value must not leave an encoded prefix or earlier element in the destination.
	for value in values {
		encoded := encode_fixed(value, width)
		// Width is already valid, so failure here means a value exceeds the element's domain.
		if encoded.error != .None {return {error = .Value_Out_Of_Range}}
	}
	copy(output[:prefix.length], prefix.bytes[:prefix.length])
	// Emit validated elements in order, retaining their fixed stride and required high-zero octets.
	for value, index in values {
		encoded := encode_fixed(value, width)
		start := prefix.length + index * stride
		copy(output[start:start + stride], encoded.encoded.bytes[:stride])
	}
	return {written = total}
}

// Decode into separate caller-owned typed storage; no allocation, partial result or retained pointer.
decode_sequence :: proc(
	input: []u8,
	width: Byte_Width,
	limit: Element_Limit,
	output: []Fixed_Unsigned,
) -> Sequence_Result {
	stride := int(width)
	// Invalid width takes priority over malformed/empty input.
	if stride < 0 || stride > 8 {return {error = .Invalid_Width}}
	frame := read_frame(input, stride, u64(limit))
	// Prefix, count and payload failures leave all output values unchanged.
	if frame.error != .None {return {error = frame.error}}
	// Prove the element count fits caller-owned host-indexed storage, even at zero stride.
	if frame.count > u64(len(output)) {return {error = .Output_Too_Small}}
	// Guard the memory-size product separately from the wire-payload-size proof.
	if frame.count > u64(max(int) / size_of(Fixed_Unsigned)) {return {error = .Length_Overflow}}
	count := int(frame.count)
	// Protect all borrowed input, including trailing fields, from decoded-value writes.
	if container_overlaps(
		raw_data(input),
		len(input),
		raw_data(output),
		count * size_of(Fixed_Unsigned),
	) {
		return {error = .Aliased_Buffers}
	}
	// Full fixed-width patterns are always valid; all possible failures were checked before this loop.
	for index in 0 ..< count {
		start := frame.offset + index * stride
		value := decode_fixed(input[start:start + stride], width)
		output[index] = value.value
	}
	return {count = count, consumed = frame.consumed}
}
