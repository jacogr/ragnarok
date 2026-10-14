package codec

import "core:mem"

// Each immutable snapshot contains exactly one validated pinned C.1.2/C.1.3/C.2 schema.
Owned_Kind :: enum {
	Bytes,
	Optional,
	Work,
	Preimages,
	Digest,
}
// Wire failures preserve their meaning; ownership errors describe missing owners, schema/index misuse and allocation failure.
Ownership_Error :: enum {
	Uninitialized,
	None,
	Truncated,
	Non_Canonical,
	Limit_Exceeded,
	Output_Too_Small,
	Aliased_Buffers,
	Length_Overflow,
	Invalid_Tag,
	Invalid_Span,
	Invalid_Owner,
	Wrong_Schema,
	Invalid_Index,
	Allocation_Failure,
}
// Opaque snapshot handle: no mutable slice or source coordinates can be accessed without an explicit unsafe cast.
// One owner must release this handle exactly once; copies are aliases, not independent ownership.
Owned_Frame :: distinct rawptr
// Success retains the frame; failure contains only a typed reason, including default results.
Owned_Result :: Codec_Result(Owned_Frame, Ownership_Error)
// Common metadata: every field has meaning for all five schemas, without detached source descriptors.
Owned_Info :: struct {
	kind:       Owned_Kind,
	consumed:   int,
	blob_count: int,
}
// Optional metadata is a native union: absence contains no length, while presence may have zero length.
Owned_Absent :: struct {}
// A present optional blob exposes only its scalar length.
Owned_Present :: struct {
	length: int,
}
// Selecting presence cannot expose a borrowed span or mutable byte slice.
Owned_Optional_Info :: union #no_nil {
	Owned_Absent,
	Owned_Present,
}
// Successful work metadata has a payload length; the other alternative is a valid protocol work error.
Owned_Work_Blob :: struct {
	length: int,
}
// Work-output failures are decoded values, distinct from an ownership/decoding error.
Owned_Work_Info :: union #no_nil {
	Owned_Work_Blob,
	Work_Error,
}
// Owned fixed fields and tag/length metadata; successful digest payload bytes remain inside their owner.
Owned_Digest_Info :: struct {
	service:        Service_Index,
	code_hash:      Code_Hash,
	payload_hash:   Payload_Hash,
	accumulate_gas: Gas,
	output:         Owned_Work_Info,
	refine:         Refine_Load,
}
// Private allocation state, reachable only through package operations on the opaque handle.
@(private = "file")
Owned_Storage :: struct {
	kind:              Owned_Kind,
	wire:              []u8,
	blob:              Blob_Span,
	has_blob, present: bool,
	work_error:        Work_Error,
	records:           []Preimage,
	digest:            Work_Digest,
	allocator:         mem.Allocator,
}

// Preserve composite wire failures rather than treating them as zero/default metadata.
@(private = "file")
owned_composite_error :: proc(error: Composite_Error) -> Ownership_Error {
	switch error {
	case .Uninitialized:
		return .Uninitialized // No validated outcome exists.
	case .None:
		return .None // Complete frame validation succeeded.
	case .Truncated:
		return .Truncated // A required field is incomplete.
	case .Non_Canonical:
		return .Non_Canonical // A natural encoding is overlong.
	case .Limit_Exceeded:
		return .Limit_Exceeded // Caller resource policy failed.
	case .Output_Too_Small:
		return .Output_Too_Small // Whole-result storage is required.
	case .Aliased_Buffers:
		return .Aliased_Buffers // Borrowed preflight rejected overlapping storage.
	case .Length_Overflow:
		return .Length_Overflow // A host extent is unrepresentable.
	case .Invalid_Tag:
		return .Invalid_Tag // The schema discriminator is unsupported.
	case .Invalid_Span:
		return .Invalid_Span // A borrowed descriptor is invalid.
	}
	unreachable() // Every composite status is mapped above.
}

// Byte decoding can produce only framing/policy errors; unrelated statuses indicate API misuse.
@(private = "file")
owned_container_error :: proc(error: Container_Error) -> Ownership_Error {
	switch error {
	case .Uninitialized:
		return .Uninitialized // No validated outcome exists.
	case .None:
		return .None // Byte framing validated.
	case .Truncated:
		return .Truncated // Prefix or payload is missing.
	case .Non_Canonical:
		return .Non_Canonical // The length is overlong.
	case .Limit_Exceeded:
		return .Limit_Exceeded // Blob policy failed.
	case .Output_Too_Small,
	     .Invalid_Width,
	     .Value_Out_Of_Range,
	     .Aliased_Buffers,
	     .Length_Overflow:
		return .Invalid_Span // Other container statuses are impossible in this path.
	}
	unreachable() // All byte-decoder status alternatives were mapped above.
}

// Validate before retaining bytes; all allocation failures clean up private temporary storage.
// Caller input must be stable during this call and allocator must outlive the returned owner.
@(private = "file")
owned_capture :: proc(
	input: []u8,
	kind: Owned_Kind,
	limit: Byte_Limit,
	limits: Preimage_Limits,
	allocator: mem.Allocator,
) -> Owned_Result {
	data := Owned_Storage {
		kind      = kind,
		allocator = allocator,
	}
	committed := false
	// Temporary allocations belong to this operation until the returned owner takes responsibility.
	defer {
		// Both malformed input and late allocator failure must leave no retained allocation.
		if !committed {
			delete(data.records, allocator)
			delete(data.wire, allocator)
		}
	}
	consumed := 0
	// Every branch validates exactly one schema before creating an immutable byte snapshot.
	switch kind {
	case .Bytes:
		parsed := decode_bytes_borrowed(input, limit)
		// Failed framing or policy cannot create an owner.
		if error_of(parsed) != .None {return owned_container_error(error_of(parsed))}
		value := success_of(parsed)
		consumed = value.consumed
		data.blob = {value.offset, value.length}
		data.has_blob = true
	case .Optional:
		parsed := decode_optional_borrowed(input, limit)
		// No payload metadata is retained from a malformed optional.
		if error_of(parsed) != .None {return owned_composite_error(error_of(parsed))}
		value := success_of(parsed)
		consumed = value.consumed
		data.present = value.value.present
		data.has_blob = data.present
		// Only a present optional refers to bytes.
		if data.present {data.blob = value.value.blob}
	case .Work:
		parsed := decode_work_borrowed(input, limit)
		// Work-error values are successful decodes, distinct from invalid framing.
		if error_of(parsed) != .None {return owned_composite_error(error_of(parsed))}
		value := success_of(parsed)
		consumed = value.consumed
		// Bind the active protocol alternative without exposing its descriptor.
		switch output in value.value {
		case Blob_Span:
			data.blob = output; data.has_blob = true // Successful payload.
		case Work_Error:
			data.work_error = output // Payload-free work error.
		case:
			unreachable() // A successful decoder never returns a nil work union.
		}
	case .Preimages:
		count := decode(input)
		// Prove the count before narrowing or allocating typed record storage.
		if error_of(count) != .None {
			// The natural decoder distinguishes missing and overlong prefixes.
			if error_of(count) == .Truncated {return Ownership_Error.Truncated}
			return Ownership_Error.Non_Canonical
		}
		claimed := u64(success_of(count).value)
		// Match borrowed policy precedence before the minimum record extent proof.
		if claimed > u64(limits.items) {return Ownership_Error.Limit_Exceeded}
		// Four service bytes and at least one length byte are required per record.
		if claimed >
		   u64((len(input) - success_of(count).consumed) / 5) {return Ownership_Error.Truncated}
		// Typed allocation sizes must remain representable on this host.
		if claimed > u64(max(int) / size_of(Preimage)) {return Ownership_Error.Length_Overflow}
		allocation_error: mem.Allocator_Error
		data.records, allocation_error = make([]Preimage, int(claimed), allocator)
		// Explicit allocators may refuse a policy-valid allocation.
		if allocation_error != .None ||
		   (claimed > 0 &&
				   raw_data(data.records) == nil) {return Ownership_Error.Allocation_Failure}
		parsed := decode_preimages_borrowed(input, limits, data.records)
		// A failing last record cannot expose the temporary prefix or leak its storage.
		if error_of(parsed) != .None {return owned_composite_error(error_of(parsed))}
		consumed = success_of(parsed).consumed
	case .Digest:
		parsed := decode_digest_borrowed(input, limit)
		// All suffix metrics must validate before retaining the complete frame.
		if error_of(parsed) != .None {return owned_composite_error(error_of(parsed))}
		value := success_of(parsed)
		consumed = value.consumed
		data.digest = value.value
		// Digest payload descriptors already use original full-frame coordinates.
		switch output in value.value.output {
		case Blob_Span:
			data.blob = output; data.has_blob = true // Successful nested payload.
		case Work_Error:
			data.work_error = output // Payload-free nested error.
		case:
			unreachable() // A successful digest has a defined work variant.
		}
	}
	allocation_error: mem.Allocator_Error
	data.wire, allocation_error = make([]u8, consumed, allocator)
	// Copy only the consumed prefix, never trailing input frames.
	if allocation_error != .None ||
	   raw_data(data.wire) == nil {return Ownership_Error.Allocation_Failure}
	copy(data.wire, input[:consumed])
	storage, header_error := mem.new(Owned_Storage, allocator)
	// Header allocation is also fallible; the deferred cleanup owns bytes/records until commit.
	if header_error != .None || storage == nil {return Ownership_Error.Allocation_Failure}
	storage^ = data
	committed = true
	return Owned_Frame(rawptr(storage))
}

// Own one canonical variable byte string; input can be released or mutated after return.
decode_owned_bytes :: proc(
	input: []u8,
	limit: Byte_Limit,
	allocator := context.allocator,
) -> Owned_Result {
	return owned_capture(input, .Bytes, limit, {}, allocator)
}
// Own an optional variable blob, including the valid payload-free absent alternative.
decode_owned_optional :: proc(
	input: []u8,
	limit: Byte_Limit,
	allocator := context.allocator,
) -> Owned_Result {
	return owned_capture(input, .Optional, limit, {}, allocator)
}
// Own a complete work-output variant; work errors remain valid decoded values.
decode_owned_work :: proc(
	input: []u8,
	limit: Byte_Limit,
	allocator := context.allocator,
) -> Owned_Result {
	return owned_capture(input, .Work, limit, {}, allocator)
}
// Own all tuples and payloads in a preimage extrinsic, with count/per-blob/aggregate policy limits.
decode_owned_preimages :: proc(
	input: []u8,
	limits: Preimage_Limits,
	allocator := context.allocator,
) -> Owned_Result {
	return owned_capture(input, .Preimages, Byte_Limit(0), limits, allocator)
}
// Own the full digest prefix and nested successful output; fixed fields are copied values.
decode_owned_digest :: proc(
	input: []u8,
	limit: Byte_Limit,
	allocator := context.allocator,
) -> Owned_Result {
	return owned_capture(input, .Digest, limit, {}, allocator)
}

// Release an owner with its original allocator and clear the passed handle; nil release is harmless.
// All copied aliases become invalid on release and must not be used or released again.
destroy_owned :: proc(frame: ^Owned_Frame) {
	// A cleared/default owner holds no allocation to release.
	if frame == nil || frame^ == nil {return}
	data := cast(^Owned_Storage)frame^
	allocator := data.allocator
	delete(data.wire, allocator)
	delete(data.records, allocator)
	mem.free(data, allocator)
	frame^ = nil
}

// Report schema, consumed prefix and number of copyable payloads without returning source coordinates.
owned_info :: proc(frame: Owned_Frame) -> Codec_Result(Owned_Info, Ownership_Error) {
	// A default owner cannot yield default decoded data.
	if frame == nil {return Ownership_Error.Invalid_Owner}
	data := cast(^Owned_Storage)frame
	count := int(data.has_blob)
	// Preimage payloads are selected independently by record index.
	if data.kind == .Preimages {count = len(data.records)}
	return Owned_Info{data.kind, len(data.wire), count}
}

// Read optional presence/length metadata; reject other schemas instead of interpreting default fields.
owned_optional_info :: proc(
	frame: Owned_Frame,
) -> Codec_Result(Owned_Optional_Info, Ownership_Error) {
	// Missing owners and wrong schemas are typed API errors.
	if frame == nil {return Ownership_Error.Invalid_Owner}
	data := cast(^Owned_Storage)frame
	if data.kind != .Optional {return Ownership_Error.Wrong_Schema}
	// Absence and empty presence remain distinct native union alternatives.
	if !data.present {return Owned_Optional_Info(Owned_Absent{})}
	return Owned_Optional_Info(Owned_Present{data.blob.length})
}

// Translate private work state to scalar/tag metadata without a payload descriptor.
@(private = "file")
owned_work_metadata :: proc(data: ^Owned_Storage) -> Owned_Work_Info {
	// Only the successful protocol alternative has a length.
	if data.has_blob {return Owned_Work_Blob{data.blob.length}}
	return data.work_error
}

// Read a work frame's tag and successful payload length as copied values.
owned_work_info :: proc(frame: Owned_Frame) -> Codec_Result(Owned_Work_Info, Ownership_Error) {
	// Validate owner and schema before interpreting private work state.
	if frame == nil {return Ownership_Error.Invalid_Owner}
	data := cast(^Owned_Storage)frame
	if data.kind != .Work {return Ownership_Error.Wrong_Schema}
	return owned_work_metadata(data)
}

// Copy the digest's fixed fields and work tag/length, keeping every payload inside its owner.
owned_digest_info :: proc(frame: Owned_Frame) -> Codec_Result(Owned_Digest_Info, Ownership_Error) {
	// A missing or differently typed frame cannot expose default digest fields.
	if frame == nil {return Ownership_Error.Invalid_Owner}
	data := cast(^Owned_Storage)frame
	if data.kind != .Digest {return Ownership_Error.Wrong_Schema}
	value := data.digest
	return Owned_Digest_Info {
		value.service,
		value.code_hash,
		value.payload_hash,
		value.accumulate_gas,
		owned_work_metadata(data),
		value.refine,
	}
}

// Select a preimage's nominal service ID without exposing its borrowed payload descriptor.
owned_service :: proc(
	frame: Owned_Frame,
	index: int,
) -> Codec_Result(Service_Index, Ownership_Error) {
	// Owner, schema and index validation precede every record read.
	if frame == nil {return Ownership_Error.Invalid_Owner}
	data := cast(^Owned_Storage)frame
	if data.kind != .Preimages {return Ownership_Error.Wrong_Schema}
	if index < 0 || index >= len(data.records) {return Ownership_Error.Invalid_Index}
	return data.records[index].service
}

// Query payload length before allocating a caller-owned copy, without exposing any source coordinate.
owned_blob_length :: proc(frame: Owned_Frame, index: int) -> Codec_Result(int, Ownership_Error) {
	// Default owners have no validated payload metadata.
	if frame == nil {return Ownership_Error.Invalid_Owner}
	data := cast(^Owned_Storage)frame
	count := int(data.has_blob)
	// Preimages provide one payload per private record, including empty blobs.
	if data.kind == .Preimages {count = len(data.records)}
	// Absent payloads are errors, distinct from valid zero-length blobs.
	if index < 0 || index >= count {return Ownership_Error.Invalid_Index}
	// Record indices stay bound to this frame's retained storage.
	if data.kind == .Preimages {return data.records[index].blob.length}
	return data.blob.length
}

// Atomically copy one payload to caller storage; the source is chosen exclusively by its owner.
copy_owned_blob :: proc(
	frame: Owned_Frame,
	index: int,
	output: []u8,
) -> Codec_Result(int, Ownership_Error) {
	// Missing owners cannot manufacture an empty success.
	if frame == nil {return Ownership_Error.Invalid_Owner}
	data := cast(^Owned_Storage)frame
	count := int(data.has_blob)
	// Preimages contain one payload per initialized record, including empty blobs.
	if data.kind == .Preimages {count = len(data.records)}
	// Payload-free variants and invalid indices expose no default payload.
	if index < 0 || index >= count {return Ownership_Error.Invalid_Index}
	span := data.blob
	// Select private record coordinates only inside their retained snapshot.
	if data.kind == .Preimages {span = data.records[index].blob}
	// Whole-payload capacity is required before mutation.
	if len(output) < span.length {return Ownership_Error.Output_Too_Small}
	copy(output[:span.length], data.wire[span.offset:span.offset + span.length])
	return span.length
}

// Re-emit the validated canonical frame, atomically, without any caller-supplied source pool.
encode_owned :: proc(frame: Owned_Frame, output: []u8) -> Codec_Result(int, Ownership_Error) {
	// Uninitialized owners cannot serialize default values.
	if frame == nil {return Ownership_Error.Invalid_Owner}
	data := cast(^Owned_Storage)frame
	// The entire retained frame must fit before the first output byte is written.
	if len(output) < len(data.wire) {return Ownership_Error.Output_Too_Small}
	copy(output[:len(data.wire)], data.wire)
	return len(data.wire)
}
