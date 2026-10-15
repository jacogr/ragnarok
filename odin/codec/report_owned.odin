package codec
import "core:mem"

// An opaque immutable report has one release owner; copied handles are borrowed aliases.
// The allocator supplied at capture must outlive every use and the final release.
Owned_Report :: distinct rawptr
// Only successful capture contains an owner; default results are failures.
Owned_Report_Result :: Codec_Result(Owned_Report, Ownership_Error)
// Scalar report metadata retains owned fixed fields, never payload coordinates or mutable slices.
Owned_Report_Info :: struct {
	header:                                                   Report_Header,
	core:                                                     Core_Index,
	authorizer:                                               Authorizer_Hash,
	auth_gas:                                                 Gas,
	prerequisite_count, lookup_count, digest_count, consumed: int,
}
// Private storage binds validated metadata to its exact private immutable wire copy.
@(private = "file")
Report_Storage :: struct {
	value:     Work_Report,
	wire:      []u8,
	allocator: mem.Allocator,
}
// Preserve precise wire errors while adding the existing ownership failure domain.
@(private = "file")
report_owned_error :: proc(error: Composite_Error) -> Ownership_Error {
	switch error {
	case .Uninitialized:
		return .Uninitialized // No complete report exists.
	case .None:
		return .None // The report validated fully.
	case .Truncated:
		return .Truncated // A required field is missing.
	case .Non_Canonical:
		return .Non_Canonical // Count/order uniqueness is invalid.
	case .Limit_Exceeded:
		return .Limit_Exceeded // A structural resource bound failed.
	case .Output_Too_Small:
		return .Output_Too_Small // A complete destination is required.
	case .Aliased_Buffers:
		return .Aliased_Buffers // A borrowed source must remain stable.
	case .Length_Overflow:
		return .Length_Overflow // A host extent is unrepresentable.
	case .Invalid_Tag:
		return .Invalid_Tag // No such work variant exists.
	case .Invalid_Span:
		return .Invalid_Span // A borrowed descriptor is invalid.
	}
	return .Invalid_Span // Reject impossible explicit enum casts.
}
// Validate first, then retain only the consumed prefix; rejected frames allocate no retained storage.
decode_owned_report :: proc(
	input: []u8,
	core_count: u64,
	allocator := context.allocator,
) -> Owned_Report_Result {
	parsed := decode_report_borrowed(input, core_count)
	// Malformed final fields cannot create a partially valid snapshot.
	if error_of(parsed) != .None { return report_owned_error(error_of(parsed)) }
	value := success_of(parsed)
	wire, failure := make([]u8, value.consumed, allocator)
	// A fallible allocator may refuse even a structurally valid report.
	if failure != .None || raw_data(wire) == nil { return Ownership_Error.Allocation_Failure }
	copy(wire, input[:value.consumed])
	storage, storage_failure := mem.new(Report_Storage, allocator)
	// Retire the private byte copy if the separate metadata allocation fails.
	if storage_failure != .None ||
	   storage == nil { delete(wire, allocator); return Ownership_Error.Allocation_Failure }
	storage^ = {value.value, wire, allocator}
	return Owned_Report(rawptr(storage))
}
// Release exactly one original owner after all borrowed aliases stop using it.
release_report :: proc(owner: ^Owned_Report) {
	// A null/default owner has no storage to release.
	if owner^ == nil { return }
	storage := cast(^Report_Storage)owner^
	allocator := storage.allocator
	delete(storage.wire, allocator); mem.free(storage, allocator); owner^ = nil
}
// Return copied fixed metadata without exporting a detached span or mutable snapshot bytes.
owned_report_info :: proc(
	owner: Owned_Report,
) -> Codec_Result(Owned_Report_Info, Ownership_Error) {
	// Null handles must not fabricate an empty validated report.
	if owner == nil { return Ownership_Error.Invalid_Owner }
	storage := cast(^Report_Storage)owner
	value := storage.value
	return Owned_Report_Info {
		value.header,
		value.core,
		value.authorizer,
		value.auth_gas,
		value.prerequisite_count,
		value.lookup_count,
		value.digest_count,
		len(storage.wire),
	}
}
// Select authorization output at index zero, then each digest's successful payload at index i+1.
// Error-output digests reject extraction; an empty successful blob still copies successfully.
copy_report_blob :: proc(
	owner: Owned_Report,
	index: int,
	output: []u8,
) -> Codec_Result(int, Ownership_Error) {
	// Owner and signed index validation precede any storage access or descriptor indexing.
	if owner == nil { return Ownership_Error.Invalid_Owner }
	storage := cast(^Report_Storage)owner
	if index < 0 || index > storage.value.digest_count { return Ownership_Error.Invalid_Index }
	span := storage.value.auth_output
	// Only successful digests contain an extractable payload.
	if index > 0 {
		switch blob in storage.value.digests[index - 1].output {
		case Blob_Span:
			span = blob // This descriptor was bound to the private wire at capture.
		case Work_Error:
			return Ownership_Error.Invalid_Index // A work error is not an empty success blob.
		case:
			unreachable() // Complete report validation rejects undefined variants.
		}
	}
	// Capacity and overlap are proved before any destination mutation.
	if len(output) < span.length { return Ownership_Error.Output_Too_Small }
	if container_overlaps(
		raw_data(storage.wire),
		len(storage.wire),
		raw_data(output),
		span.length,
	) { return Ownership_Error.Aliased_Buffers }
	copy(output[:span.length], storage.wire[span.offset:span.offset + span.length])
	return span.length
}
// Atomically re-emit the owner's canonical consumed prefix without exposing its private backing slice.
encode_owned_report :: proc(
	owner: Owned_Report,
	output: []u8,
) -> Codec_Result(int, Ownership_Error) {
	// A missing owner cannot represent a validated report.
	if owner == nil { return Ownership_Error.Invalid_Owner }
	storage := cast(^Report_Storage)owner
	// Keep the entire destination unchanged on capacity or overlap failure.
	if len(output) < len(storage.wire) { return Ownership_Error.Output_Too_Small }
	if container_overlaps(
		raw_data(storage.wire),
		len(storage.wire),
		raw_data(output),
		len(storage.wire),
	) { return Ownership_Error.Aliased_Buffers }
	copy(output[:len(storage.wire)], storage.wire)
	return len(storage.wire)
}

// Return copied digest fields and length-only work metadata, keeping all payload coordinates private.
owned_report_digest :: proc(
	owner: Owned_Report,
	index: int,
) -> Codec_Result(Owned_Digest_Info, Ownership_Error) {
	// Null owners and signed invalid indices cannot expose invented digest fields.
	if owner == nil { return Ownership_Error.Invalid_Owner }
	storage := cast(^Report_Storage)owner
	if index < 0 || index >= storage.value.digest_count { return Ownership_Error.Invalid_Index }
	digest := storage.value.digests[index]
	output: Owned_Work_Info
	// Successful output retains a length; errors retain their payload-free protocol tag.
	switch blob in digest.output {
	case Blob_Span:
		output = Owned_Work_Blob{blob.length} // No detached source span escapes.
	case Work_Error:
		output = blob // Work errors are successfully decoded values.
	case:
		unreachable() // Captured reports cannot contain undefined output variants.
	}
	return Owned_Digest_Info {
		digest.service,
		digest.code_hash,
		digest.payload_hash,
		digest.accumulate_gas,
		output,
		digest.refine,
	}
}
// Return an owned prerequisite identity while preserving the snapshot's private backing storage.
owned_report_prerequisite :: proc(
	owner: Owned_Report,
	index: int,
) -> Codec_Result(Package_Hash, Ownership_Error) {
	// Membership is bounded by the decoded count, not unused fixed-array capacity.
	if owner == nil { return Ownership_Error.Invalid_Owner }
	storage := cast(^Report_Storage)owner
	if index < 0 ||
	   index >= storage.value.prerequisite_count { return Ownership_Error.Invalid_Index }
	return storage.value.prerequisites[index]
}
// Return one copied dictionary entry, without any mutable snapshot slice or source-buffer coordinates.
owned_report_lookup :: proc(
	owner: Owned_Report,
	index: int,
) -> Codec_Result(Segment_Lookup, Ownership_Error) {
	// A default owner and invalid signed indices expose only their reason.
	if owner == nil { return Ownership_Error.Invalid_Owner }
	storage := cast(^Report_Storage)owner
	if index < 0 || index >= storage.value.lookup_count { return Ownership_Error.Invalid_Index }
	return storage.value.lookup[index]
}
