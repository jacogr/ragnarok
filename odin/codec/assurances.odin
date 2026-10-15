package codec

// Configuration domains are distinct from one another and from encoded validator indices.
Core_Count :: distinct u64
Validator_Count :: distinct u64
Validator_Index :: distinct u16
// Fixed identity domains own their bytes and prevent hash/signature substitution.
Assurance_Anchor :: distinct [32]u8
Assurance_Bits :: distinct [43]u8
Assurance_Signature :: distinct [64]u8
// Explicit profile configuration is validated before accessing untrusted input.
Assurance_Config :: struct {
	cores:      Core_Count,
	validators: Validator_Count,
}
// Entirely owned record: no allocator, borrowed pointer or reference cycle survives decoding.
Assurance :: struct {
	anchor:    Assurance_Anchor,
	bits:      Assurance_Bits,
	validator: Validator_Index,
	signature: Assurance_Signature,
}
// Default initialization is a failure; successful metadata belongs only to the success alternative.
Assurance_Error :: enum {
	Uninitialized,
	None,
	Invalid_Config,
	Truncated,
	Non_Canonical,
	Limit_Exceeded,
	Output_Too_Small,
	Aliased_Buffers,
	Length_Overflow,
	Invalid_Validator,
}
// Encoder success selects only the completed output prefix; failure contains its reason alone.
Assurance_Write_Result :: Codec_Result(Write_Success, Assurance_Error)
// Decoder success selects the initialized typed prefix and consumed bytes; failure has neither.
Assurance_Decode_Result :: Codec_Result(Sequence_Success, Assurance_Error)

// Prove all profile conversions and fixed wire arithmetic are within the supported resource envelope.
assurance_config_valid :: proc(config: Assurance_Config) -> bool {
	return(
		config.cores >= 1 &&
		config.cores <= 341 &&
		config.validators >= 1 &&
		config.validators <= 1023 \
	)
}

// Validate semantic fields in index/order/padding precedence without modifying caller storage.
assurance_record_error :: proc(
	value: Assurance,
	config: Assurance_Config,
	previous: int,
) -> Assurance_Error {
	// A valid E2 encoding may still index outside the configured validator set.
	if u64(value.validator) >= u64(config.validators) { return .Invalid_Validator }
	// Canonical assurances have unique, strictly ascending validator indices.
	if int(value.validator) <= previous { return .Non_Canonical }
	width := (int(config.cores) + 7) / 8
	remainder := int(config.cores) % 8
	// A partial final octet must not assign availability to nonexistent cores.
	if remainder != 0 &&
	   int(value.bits[width - 1]) >> uint(remainder) != 0 { return .Non_Canonical }
	// Unused owned storage must be rejected instead of silently disappearing from encoding.
	for i in width ..< 43 {
		// This profile has no wire representation for nonzero unused octets.
		if value.bits[i] != 0 { return .Non_Canonical }
	}
	return .None
}

// Read a complete extent-proved record into independent fields, zero-extending native bitset storage.
assurance_read_record :: proc(input: []u8, start, width: int) -> Assurance {
	value: Assurance
	// Anchor bytes retain identity order without numeric reinterpretation.
	for i in 0 ..< 32 { value.anchor[i] = input[start + i] }
	// Only the configured width appears on the wire; remaining native storage stays zero.
	for i in 0 ..< width { value.bits[i] = input[start + 32 + i] }
	position := start + 32 + width
	value.validator = Validator_Index(u16(input[position]) | u16(input[position + 1]) << 8)
	// Signature validity is a separate context-aware cryptographic concern.
	for i in 0 ..< 64 { value.signature[i] = input[position + 2 + i] }
	return value
}

// Encode stable borrowed records atomically into separate caller-owned bytes, with no allocations.
encode_assurances :: proc(
	values: []Assurance,
	config: Assurance_Config,
	output: []u8,
) -> Assurance_Write_Result {
	// Configuration precedes even empty-sequence handling.
	if !assurance_config_valid(config) { return Assurance_Error.Invalid_Config }
	// Protocol ceilings are checked before destination capacity and host arithmetic.
	if u64(len(values)) > u64(config.validators) { return Assurance_Error.Limit_Exceeded }
	width := (int(config.cores) + 7) / 8
	stride := 98 + width
	prefix := encode(Natural(len(values)))
	// Division proves the whole output product without overflowing it.
	if len(output) < prefix.length || len(values) > (len(output) - prefix.length) / stride {
		return Assurance_Error.Output_Too_Small
	}
	total := prefix.length + len(values) * stride
	// Typed metadata has a separate native byte extent that must be checked before multiplication.
	if len(values) > max(int) / size_of(Assurance) { return Assurance_Error.Length_Overflow }
	// Protect the entire typed source array against the complete encoded output prefix.
	if container_overlaps(
		raw_data(values),
		len(values) * size_of(Assurance),
		raw_data(output),
		total,
	) {
		return Assurance_Error.Aliased_Buffers
	}
	previous := -1
	// A failure in the final record must leave all earlier destination bytes unchanged.
	for value in values {
		error := assurance_record_error(value, config, previous)
		// Failure returns only its reason; no partial written metadata escapes.
		if error != .None { return error }
		previous = int(value.validator)
	}
	// All failure conditions are settled before this infallible commit phase.
	for i in 0 ..< prefix.length { output[i] = prefix.bytes[i] }
	// Every field index is covered by the complete output extent proof.
	for value, i in values {
		start := prefix.length + i * stride
		// Copy the declared anchor identity bytes.
		for j in 0 ..< 32 { output[start + j] = value.anchor[j] }
		// Fixed bitfields contain no nested length prefix or unused storage octets.
		for j in 0 ..< width { output[start + 32 + j] = value.bits[j] }
		position := start + 32 + width
		output[position] = u8(u16(value.validator) & 255)
		output[position + 1] = u8(u16(value.validator) >> 8)
		// Preserve the full opaque signature encoding.
		for j in 0 ..< 64 { output[position + 2 + j] = value.signature[j] }
	}
	return Write_Success{written = total}
}

// Decode a prefix into caller-owned typed records only after every record passes preflight.
decode_assurances :: proc(
	input: []u8,
	config: Assurance_Config,
	output: []Assurance,
) -> Assurance_Decode_Result {
	// Invalid configuration cannot be masked by a malformed count.
	if !assurance_config_valid(config) { return Assurance_Error.Invalid_Config }
	width := (int(config.cores) + 7) / 8
	stride := 98 + width
	frame := read_frame(input, stride, u64(config.validators))
	// Preserve frame failure precedence without casting between unrelated error domains.
	switch error_of(frame) {
	case .Truncated:
		// Missing count or fixed payload bytes provide no usable progress.
		return Assurance_Error.Truncated
	case .Non_Canonical:
		// Overlong naturals cannot describe canonical extrinsics.
		return Assurance_Error.Non_Canonical
	case .Limit_Exceeded:
		// Enforce configured validator count before typed capacity.
		return Assurance_Error.Limit_Exceeded
	case .None:
	// Only this alternative permits extraction of validated frame metadata.
	case .Uninitialized,
	     .Output_Too_Small,
	     .Invalid_Width,
	     .Value_Out_Of_Range,
	     .Aliased_Buffers,
	     .Length_Overflow:
		// An unexpected internal frame outcome cannot fabricate successful records.
		return Assurance_Error.Uninitialized
	}
	proof := success_of(frame)
	// Full input extent has been proved, but typed output capacity remains a caller constraint.
	if proof.count > u64(len(output)) { return Assurance_Error.Output_Too_Small }
	// Prove the native storage product before constructing overlap ranges.
	if proof.count > u64(max(int) / size_of(Assurance)) { return Assurance_Error.Length_Overflow }
	count := int(proof.count)
	// Protect the complete original input, including its trailing fields.
	if container_overlaps(
		raw_data(input),
		len(input),
		raw_data(output),
		count * size_of(Assurance),
	) {
		return Assurance_Error.Aliased_Buffers
	}
	previous := -1
	// Two passes guarantee a late semantic failure cannot partially initialize caller records.
	for i in 0 ..< count {
		value := assurance_read_record(input, proof.offset + i * stride, width)
		error := assurance_record_error(value, config, previous)
		// Failure has no count, value or consumed fields.
		if error != .None { return error }
		previous = int(value.validator)
	}
	// Stable disjoint source bytes make copying the validated prefix infallible.
	for i in 0 ..< count { output[i] = assurance_read_record(input, proof.offset + i * stride, width) }
	return Sequence_Success{count = count, consumed = proof.consumed}
}
