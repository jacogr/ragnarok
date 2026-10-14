package codec

// A validated descriptor into a caller-owned byte pool/original input; it retains no pointer.
Blob_Span :: struct {
	offset: int,
	length: int,
}
// Nominal four-byte service identifier, separate from ordinary integers and count policies.
Service_Index :: distinct u32
// Absence has no encoded payload; a present value's descriptor is checked against its matching pool.
Optional_Blob :: struct {
	present: bool,
	blob:    Blob_Span,
}
// Exact C.2 payload-free work-output variants; success is represented by a Blob_Span in Work_Output.
Work_Error :: enum u8 {
	Out_Of_Gas = 1,
	Panic,
	Bad_Exports,
	Oversize,
	Bad,
	Big,
}
// Odin's native union separates successful blob views from error variants; nil is not a valid work output.
Work_Output :: union {
	Blob_Span,
	Work_Error,
}
// C.2 tuple: a nominal service ID followed by one variable blob.
Preimage :: struct {
	service: Service_Index,
	blob:    Blob_Span,
}
// Independent limits for records, one nested blob, and aggregate blob payload bytes.
Preimage_Limits :: struct {
	items:            Element_Limit,
	per_blob:         Byte_Limit,
	total_blob_bytes: Byte_Limit,
}
// Complete typed failures; None denotes the success alternative; failures expose no metadata.
Composite_Error :: enum {
	Uninitialized, // A default result is a failure with no validated payload.
	None,
	Truncated,
	Non_Canonical,
	Limit_Exceeded,
	Output_Too_Small,
	Aliased_Buffers,
	Length_Overflow,
	Invalid_Tag,
	Invalid_Span,
}
// Completed encoder prefix in caller-owned storage; failed writes leave storage unchanged and expose no written field.
Composite_Write_Success :: struct {
	written: int,
}
// The failure alternative contains no success payload or metadata; nil is not an outcome.
Composite_Write :: Codec_Result(Composite_Write_Success, Composite_Error)
// Optional view with indices into input and a completed-prefix length, without heap allocation.
Optional_Success :: struct {
	value:    Optional_Blob,
	consumed: int,
}
// The failure alternative contains no success payload or metadata; nil is not an outcome.
Optional_Result :: Codec_Result(Optional_Success, Composite_Error)
// Work-output native union; check error before reading the active variant.
Work_Success :: struct {
	value:    Work_Output,
	consumed: int,
}
// The failure alternative contains no success payload or metadata; nil is not an outcome.
Work_Result :: Codec_Result(Work_Success, Composite_Error)
// Initialized record prefix in caller storage; nested blobs remain spans into original input.
Preimage_Success :: struct {
	count:    int,
	consumed: int,
}
// The failure alternative contains no success payload or metadata; nil is not an outcome.
Preimage_Result :: Codec_Result(Preimage_Success, Composite_Error)
// Internal discriminator proof before constructing public optional/union values.
Tagged_Success :: struct {
	tag:      u64,
	blob:     Blob_Span,
	consumed: int,
}
// The failure alternative contains no success payload or metadata; nil is not an outcome.
Tagged_Result :: Codec_Result(Tagged_Success, Composite_Error)

// Map only statuses possible from bounded byte-blob operations, retaining canonical/policy failures.
composite_blob_error :: proc(error: Container_Error) -> Composite_Error {
	switch error {
	case .Uninitialized:
		return Composite_Error.Uninitialized // A missing result must not be interpreted as validated data.
	case .None:
		return .None // Nested validation succeeded.
	case .Truncated:
		return .Truncated // Incomplete prefix or payload.
	case .Non_Canonical:
		return .Non_Canonical // Overlong nested count.
	case .Limit_Exceeded:
		return .Limit_Exceeded // Per-blob or aggregate policy.
	case .Output_Too_Small:
		return .Output_Too_Small // Whole result must fit.
	case .Aliased_Buffers:
		return .Aliased_Buffers // Borrowed source protection.
	case .Invalid_Width, .Value_Out_Of_Range, .Length_Overflow:
		return .Invalid_Span // Other container operations are not used by this blob-only path.
	}
	return .Invalid_Span // Safely reject explicit casts outside the declared container enum.
}

// Use subtraction before endpoint addition, accepting an empty span at the end of a valid pool.
valid_blob_span :: proc(span: Blob_Span, size: int) -> bool {
	return(
		span.offset >= 0 &&
		span.length >= 0 &&
		span.offset <= size &&
		span.length <= size - span.offset \
	)
}

// Validate and measure a work variant without mutation, enabling atomic enclosing-tuple preflight.
measure_work :: proc(value: Work_Output, pool_size: int, limit: Byte_Limit) -> Composite_Write {
	// The active union member selects the only fields that have wire meaning.
	switch item in value {
	case Blob_Span:
		// Validate signed endpoints before narrowing length or adding headers.
		if !valid_blob_span(item, pool_size) {return Composite_Error.Invalid_Span}
		// Blob policy applies only to the successful branch.
		if u64(item.length) > u64(limit) {return Composite_Error.Limit_Exceeded}
		length := encode(Natural(item.length))
		// A complete extent must be representable in the host integer.
		if item.length > max(int) - 1 - length.length {return Composite_Error.Length_Overflow}
		return Composite_Write_Success{written = 1 + length.length + item.length}
	case Work_Error:
		// Explicit enum casts cannot impersonate success or an undefined wire tag.
		if int(item) < 1 || int(item) > 6 {return Composite_Error.Invalid_Tag}
		return Composite_Write_Success{written = 1}
	case:
		// Nil unions are not work-output values.
		return Composite_Error.Invalid_Tag
	}
}

// Write a validated discriminator plus optional bounded blob, committing nothing until all checks pass.
write_composite_tag :: proc(
	tag: int,
	has_blob: bool,
	span: Blob_Span,
	pool: []u8,
	limit: Byte_Limit,
	output: []u8,
) -> Composite_Write {
	if tag < 0 || tag > 6 {return Composite_Error.Invalid_Tag} 	// Guard enum casts before byte narrowing.
	if !has_blob {
		if len(output) == 0 {return Composite_Error.Output_Too_Small} 	// The tag alone must fit.
		output[0] = u8(tag)
		return Composite_Write_Success{written = 1} // Payload-free variants never inspect pool contents.
	}
	if !valid_blob_span(span, len(pool)) {return Composite_Error.Invalid_Span} 	// Safe source endpoints.
	if u64(span.length) > u64(limit) {return Composite_Error.Limit_Exceeded} 	// Caller payload policy.
	length := encode(Natural(span.length))
	if len(output) < 1 + length.length || span.length > len(output) - 1 - length.length {
		return Composite_Error.Output_Too_Small // Prove the complete sum by subtraction before computing it.
	}
	total := 1 + length.length + span.length
	if container_overlaps(raw_data(pool), len(pool), raw_data(output), total) {
		return Composite_Error.Aliased_Buffers // Protect unused/trailing pool bytes too.
	}
	output[0] = u8(tag)
	copy(output[1:1 + length.length], length.bytes[:length.length])
	copy(output[1 + length.length:total], pool[span.offset:span.offset + span.length])
	return Composite_Write_Success{written = total}
}

// Read a canonical discriminator and only the payload branch specified by this schema.
read_composite_tag :: proc(
	input: []u8,
	maximum, blob_tag: u64,
	limit: Byte_Limit,
) -> Tagged_Result {
	tag := decode(input)
	switch error_of(tag) {
	case .Uninitialized:
		return Composite_Error.Uninitialized // A missing result must not be interpreted as validated data.
	case .Truncated:
		return Composite_Error.Truncated // No complete discriminator.
	case .Non_Canonical:
		return Composite_Error.Non_Canonical // Present but overlong discriminator.
	case .None: // A canonical count can now be checked against the schema tag set.
	}
	value := u64(success_of(tag).value)
	if value > maximum {return Composite_Error.Invalid_Tag} 	// Reject before narrowing into an enum.
	if value !=
	   blob_tag {return Tagged_Success{tag = value, consumed = success_of(tag).consumed}} 	// This variant has no payload.
	blob := decode_bytes_borrowed(input[success_of(tag).consumed:], limit)
	if error_of(blob) != .None {return composite_blob_error(error_of(blob))} 	// Nested payload preflight.
	return Tagged_Success {
		tag = value,
		blob = {
			offset = success_of(tag).consumed + success_of(blob).offset,
			length = success_of(blob).length,
		},
		consumed = success_of(tag).consumed + success_of(blob).consumed,
	}
}

// C.1.3 optional-blob schema: absent zero or present one followed by a variable blob.
encode_optional_borrowed :: proc(
	value: Optional_Blob,
	pool: []u8,
	limit: Byte_Limit,
	output: []u8,
) -> Composite_Write {
	if value.present {return write_composite_tag(1, true, value.blob, pool, limit, output)} 	// Present span.
	return write_composite_tag(0, false, {}, pool, limit, output) // Absence ignores all blob fields.
}

// Decode a typed optional view without copying or retaining the source bytes.
decode_optional_borrowed :: proc(input: []u8, limit: Byte_Limit) -> Optional_Result {
	parsed := read_composite_tag(input, 1, 1, limit)
	if error_of(parsed) != .None {return error_of(parsed)} 	// No usable value on failure.
	return Optional_Success {
		value = {present = success_of(parsed).tag == 1, blob = success_of(parsed).blob},
		consumed = success_of(parsed).consumed,
	}
}

// Encode the C.2 work-output native union: a successful blob or one of six payload-free error tags.
encode_work_borrowed :: proc(
	value: Work_Output,
	pool: []u8,
	limit: Byte_Limit,
	output: []u8,
) -> Composite_Write {
	switch item in value {
	case Blob_Span:
		return write_composite_tag(0, true, item, pool, limit, output) // Success payload.
	case Work_Error:
		if int(item) < 1 || int(item) > 6 {return Composite_Error.Invalid_Tag} 	// Explicit enum casts must not impersonate success.
		return write_composite_tag(int(item), false, {}, pool, limit, output) // Checked error tag.
	case:
		return Composite_Error.Invalid_Tag // An uninitialized/nil union is not a work-output value.
	}
}

// Decode C.2's exact variant set, constructing a native union only after tag and payload validation.
decode_work_borrowed :: proc(input: []u8, limit: Byte_Limit) -> Work_Result {
	parsed := read_composite_tag(input, 6, 0, limit)
	if error_of(parsed) != .None {return error_of(parsed)} 	// No enum cast on invalid wire values.
	if success_of(parsed).tag ==
	   0 {return Work_Success{value = success_of(parsed).blob, consumed = success_of(parsed).consumed}} 	// Success blob.
	return Work_Success {
		value = Work_Error(success_of(parsed).tag),
		consumed = success_of(parsed).consumed,
	}
}

// Validate a complete nested sequence or commit views after that validation has already succeeded.
walk_preimages :: proc(
	input: []u8,
	offset, count: int,
	limits: Preimage_Limits,
	output: []Preimage,
	commit: bool,
) -> Preimage_Result {
	cursor := offset
	budget := u64(limits.total_blob_bytes)
	// Traverse in wire order, charging each payload to the remaining aggregate budget.
	for index in 0 ..< count {
		if len(input) - cursor < 4 {return Composite_Error.Truncated} 	// Complete service field required.
		service := decode_fixed(input[cursor:cursor + 4], Byte_Width(4))
		cursor += 4
		blob := decode_bytes_borrowed(
			input[cursor:],
			Byte_Limit(min(u64(limits.per_blob), budget)),
		)
		if error_of(blob) != .None {return composite_blob_error(error_of(blob))} 	// Nested and aggregate policy before payload.
		if commit {
			// The validation pass makes no writes; an invalid last record cannot leave earlier partial views.
			output[index] = {
				service = Service_Index(success_of(service).value),
				blob = {
					offset = cursor + success_of(blob).offset,
					length = success_of(blob).length,
				},
			}
		}
		budget -= u64(success_of(blob).length)
		cursor += success_of(blob).consumed
	}
	return Preimage_Success{count = count, consumed = cursor}
}

// Full C.2 preimage extrinsic: bounded outer sequence of service-ID/variable-blob tuples.
decode_preimages_borrowed :: proc(
	input: []u8,
	limits: Preimage_Limits,
	output: []Preimage,
) -> Preimage_Result {
	prefix := decode(input)
	switch error_of(prefix) {
	case .Uninitialized:
		return Composite_Error.Uninitialized // A missing result must not be interpreted as validated data.
	case .Truncated:
		return Composite_Error.Truncated // No outer sequence count.
	case .Non_Canonical:
		return Composite_Error.Non_Canonical // Reject overlong counts before record reads.
	case .None: // Continue only after the count is canonical.
	}
	claimed := u64(success_of(prefix).value)
	if claimed > u64(limits.items) {return Composite_Error.Limit_Exceeded} 	// Outer policy precedes traversal.
	if claimed >
	   u64((len(input) - success_of(prefix).consumed) / 5) {return Composite_Error.Truncated} 	// Minimum record size, no product overflow.
	if claimed > u64(len(output)) {return Composite_Error.Output_Too_Small} 	// Caller record storage/host conversion proof.
	if claimed > u64(max(int) / size_of(Preimage)) {return Composite_Error.Length_Overflow} 	// Typed memory span proof.
	count := int(claimed)
	if container_overlaps(
		raw_data(input),
		len(input),
		raw_data(output),
		count * size_of(Preimage),
	) {
		return Composite_Error.Aliased_Buffers // Protect even later input fields from record initialization.
	}
	checked := walk_preimages(input, success_of(prefix).consumed, count, limits, output, false)
	if error_of(checked) != .None {return checked} 	// Entire-frame validation before any typed output write.
	return walk_preimages(input, success_of(prefix).consumed, count, limits, output, true)
}

// Encode validated source descriptors using a shared pool, preflighting each nested extent and policy.
encode_preimages_borrowed :: proc(
	values: []Preimage,
	pool: []u8,
	limits: Preimage_Limits,
	output: []u8,
) -> Composite_Write {
	if u64(len(values)) > u64(limits.items) {return Composite_Error.Limit_Exceeded} 	// Bounded outer count.
	prefix := encode(Natural(len(values)))
	if len(output) < prefix.length {return Composite_Error.Output_Too_Small} 	// Complete count header required.
	required := prefix.length
	budget := u64(limits.total_blob_bytes)
	// Validate all records before writing even the outer header.
	for value in values {
		if !valid_blob_span(value.blob, len(pool)) {return Composite_Error.Invalid_Span} 	// Source span proof before indexing.
		if u64(value.blob.length) > min(u64(limits.per_blob), budget) {
			return Composite_Error.Limit_Exceeded // Apply both blob budgets before copying.
		}
		length := encode(Natural(value.blob.length))
		if len(output) - required < 4 + length.length ||
		   value.blob.length > len(output) - required - 4 - length.length {
			return Composite_Error.Output_Too_Small // Subtraction proves the full addition safe.
		}
		required += 4 + length.length + value.blob.length
		budget -= u64(value.blob.length)
	}
	if len(values) > max(int) / size_of(Preimage) {return Composite_Error.Length_Overflow} 	// Source typed-memory extent.
	if container_overlaps(raw_data(pool), len(pool), raw_data(output), required) ||
	   container_overlaps(
		   raw_data(values),
		   len(values) * size_of(Preimage),
		   raw_data(output),
		   required,
	   ) {
		return Composite_Error.Aliased_Buffers // Both borrowed source kinds must remain stable through commit.
	}
	copy(output[:prefix.length], prefix.bytes[:prefix.length])
	cursor := prefix.length
	// Commit checked tuples from the same stable source descriptors and pool.
	for value in values {
		service := encode_fixed(Fixed_Unsigned(value.service), Byte_Width(4))
		// Retain the checked fixed encoding in addressable value storage for this copy.
		service_bytes := success_of(service).encoded
		copy(output[cursor:cursor + 4], service_bytes.bytes[:4])
		cursor += 4
		length := encode(Natural(value.blob.length))
		copy(output[cursor:cursor + length.length], length.bytes[:length.length])
		cursor += length.length
		copy(
			output[cursor:cursor + value.blob.length],
			pool[value.blob.offset:value.blob.offset + value.blob.length],
		)
		cursor += value.blob.length
	}
	return Composite_Write_Success{written = required}
}
