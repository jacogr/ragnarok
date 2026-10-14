package codec

// Owned 32-byte code hash; identity encoding does not compute or validate a hash.
Code_Hash :: distinct [32]u8
// Owned payload hash, nominally separate from the service's code hash.
Payload_Hash :: distinct [32]u8
// Gas units: accumulation gas uses E8 and refinement gas uses a canonical natural.
Gas :: distinct u64
// Imported segment count, serialized as a general natural.
Import_Count :: distinct u64
// Extrinsic count, separate from aggregate extrinsic size.
Extrinsic_Count :: distinct u64
// Aggregate extrinsic size in bytes, serialized as a general natural.
Extrinsic_Bytes :: distinct u64
// Exported segment count, separate from import count.
Export_Count :: distinct u64
// Five metrics in the paper's wire order; each is general-natural encoded.
Refine_Load :: struct {
	gas_used:        Gas,
	imports:         Import_Count,
	extrinsic_count: Extrinsic_Count,
	extrinsic_size:  Extrinsic_Bytes,
	exports:         Export_Count,
}
// Owned fixed fields plus a work-output union whose successful span borrows the matching pool/input.
Work_Digest :: struct {
	service:        Service_Index,
	code_hash:      Code_Hash,
	payload_hash:   Payload_Hash,
	accumulate_gas: Gas,
	output:         Work_Output,
	refine:         Refine_Load,
}
// A usable digest exists only when error is None; failed decode consumes no input.
Digest_Success :: struct {
	value:    Work_Digest,
	consumed: int,
}
// The failure alternative contains no success payload or metadata; nil is not an outcome.
Digest_Result :: Codec_Result(Digest_Success, Composite_Error)

// Serialize the complete C.2 tuple without allocation or partial writes, using a value snapshot of fixed fields.
encode_digest :: proc(
	source: Work_Digest,
	pool: []u8,
	limit: Byte_Limit,
	output: []u8,
) -> Composite_Write {
	value := source
	work := measure_work(value.output, len(pool), limit)
	// Reject a bad union, span or resource policy before committing a fixed field.
	if error_of(work) != .None {return work}
	numbers := [5]u64 {
		u64(value.refine.gas_used),
		u64(value.refine.imports),
		u64(value.refine.extrinsic_count),
		u64(value.refine.extrinsic_size),
		u64(value.refine.exports),
	}
	suffix: [5]Encoded_Natural
	required := 76
	// Prove the fixed-prefix/work-output sum before adding it.
	if success_of(work).written > max(int) - required {return Composite_Error.Length_Overflow}
	required += success_of(work).written
	// Measure all five metrics before any destination write.
	for metric, index in numbers {
		suffix[index] = encode(Natural(metric))
		// Each bounded header still needs a checked host-size sum.
		if required > max(int) - suffix[index].length {return Composite_Error.Length_Overflow}
		required += suffix[index].length
	}
	// Even a missing final suffix byte must preserve the entire destination.
	if len(output) < required {return Composite_Error.Output_Too_Small}
	// Only the successful union member borrows the pool; error variants have no payload.
	if _, success := value.output.(Blob_Span); success {
		// Protect unused/trailing pool bytes as well as the selected blob.
		if container_overlaps(
			raw_data(pool),
			len(pool),
			raw_data(output),
			required,
		) {return Composite_Error.Aliased_Buffers}
	}
	service := encode_fixed(Fixed_Unsigned(value.service), Byte_Width(4))
	gas := encode_fixed(Fixed_Unsigned(value.accumulate_gas), Byte_Width(8))
	// Retain the checked fixed encoding in addressable value storage for this copy.
	service_bytes := success_of(service).encoded
	copy(output[:4], service_bytes.bytes[:4])
	code := cast([32]u8)value.code_hash
	payload := cast([32]u8)value.payload_hash
	copy(output[4:36], code[:])
	copy(output[36:68], payload[:])
	// Retain the checked fixed encoding in addressable value storage for this copy.
	gas_bytes := success_of(gas).encoded
	copy(output[68:76], gas_bytes.bytes[:8])
	_ = encode_work(value.output, pool, limit, output[76:76 + success_of(work).written])
	cursor := 76 + success_of(work).written
	// Append the measured canonical metrics in their original order.
	for &field in suffix {
		copy(output[cursor:cursor + field.length], field.bytes[:field.length])
		cursor += field.length
	}
	return Composite_Write_Success{written = required}
}

// Decode one complete prefix with owned fixed fields and successful blob coordinates in the original input.
decode_digest :: proc(input: []u8, limit: Byte_Limit) -> Digest_Result {
	// All fixed fields must be present before slicing their storage.
	if len(input) < 76 {return Composite_Error.Truncated}
	work := decode_work(input[76:], limit)
	// Invalid or incomplete variants expose no usable digest.
	if error_of(work) != .None {return error_of(work)}
	cursor := 76 + success_of(work).consumed
	numbers: [5]u64
	// Validate all suffix metrics, including the last one, before constructing public output.
	for &number in numbers {
		parsed := decode(input[cursor:])
		// Preserve missing-versus-overlong natural failures exactly.
		switch error_of(parsed) {
		case .Uninitialized:
			return Composite_Error.Uninitialized // A missing result must not be interpreted as validated data.
		case .Truncated:
			return Composite_Error.Truncated // No complete metric.
		case .Non_Canonical:
			return Composite_Error.Non_Canonical // Overlong metric.
		case .None: // Only a canonical metric may advance the cursor.
		}
		number = u64(success_of(parsed).value)
		cursor += success_of(parsed).consumed
	}
	value: Work_Digest
	value.service = Service_Index(success_of(decode_fixed(input[:4], Byte_Width(4))).value)
	value.accumulate_gas = Gas(success_of(decode_fixed(input[68:76], Byte_Width(8))).value)
	code, payload: [32]u8
	copy(code[:], input[4:36])
	copy(payload[:], input[36:68])
	value.code_hash = Code_Hash(code)
	value.payload_hash = Payload_Hash(payload)
	value.output = success_of(work).value
	// A successful work subframe's blob coordinates must be translated to the full input.
	if span, success := value.output.(Blob_Span); success {
		span.offset += 76
		value.output = span
	}
	value.refine = {
		Gas(numbers[0]),
		Import_Count(numbers[1]),
		Extrinsic_Count(numbers[2]),
		Extrinsic_Bytes(numbers[3]),
		Export_Count(numbers[4]),
	}
	return Digest_Success{value = value, consumed = cursor}
}
