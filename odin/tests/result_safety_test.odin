package tests
import codec "../codec"
import "core:testing"

@(test)
// Match actual failure alternatives instead of reading fabricated zero payload or metadata fields.
result_failures :: proc(t: ^testing.T) {
	missing := codec.Digest_Result(codec.Composite_Error.None)
	testing.expect(t, codec.error_of(missing) == .Uninitialized) // Success is selected by its union alternative, not an enum value.
	unset: codec.Digest_Result
	testing.expect(t, codec.error_of(unset) == .Uninitialized) // No default decoded digest exists before validation.
	switch failure in codec.decode(nil) {
	case codec.Decode_Error:
		testing.expect(t, failure == .Truncated)
	case codec.Decode_Success:
		testing.expect(t, false) // Empty input must not fabricate zero success.
	}
	switch failure in codec.decode_fixed(nil, codec.Byte_Width(1)) {
	case codec.Fixed_Error:
		testing.expect(t, failure == .Truncated)
	case codec.Fixed_Decode_Success:
		testing.expect(t, false) // No payload on incomplete fixed-width data.
	}
	switch failure in codec.decode_bytes_borrowed(nil, codec.Byte_Limit(1)) {
	case codec.Container_Error:
		testing.expect(t, failure == .Truncated)
	case codec.Blob_Success:
		testing.expect(t, false) // No span on failed blob decoding.
	}
	output: [1]codec.Fixed_Unsigned
	switch failure in codec.decode_sequence(
		nil,
		codec.Byte_Width(1),
		codec.Element_Limit(1),
		output[:],
	) {
	case codec.Container_Error:
		testing.expect(t, failure == .Truncated)
	case codec.Sequence_Success:
		testing.expect(t, false) // No initialized prefix on failure.
	}
	switch failure in codec.decode_optional_borrowed(nil, codec.Byte_Limit(1)) {
	case codec.Composite_Error:
		testing.expect(t, failure == .Truncated)
	case codec.Optional_Success:
		testing.expect(t, false) // Missing input is not an absent optional value.
	}
	switch failure in codec.decode_work_borrowed(nil, codec.Byte_Limit(1)) {
	case codec.Composite_Error:
		testing.expect(t, failure == .Truncated)
	case codec.Work_Success:
		testing.expect(t, false) // A decoding failure is not a work-output variant.
	}
	limits := codec.Preimage_Limits {
		codec.Element_Limit(1),
		codec.Byte_Limit(1),
		codec.Byte_Limit(1),
	}
	records: [1]codec.Preimage
	switch failure in codec.decode_preimages_borrowed(nil, limits, records[:]) {
	case codec.Composite_Error:
		testing.expect(t, failure == .Truncated)
	case codec.Preimage_Success:
		testing.expect(t, false) // No record count on failure.
	}
	switch failure in codec.decode_digest_borrowed(nil, codec.Byte_Limit(1)) {
	case codec.Composite_Error:
		testing.expect(t, failure == .Truncated)
	case codec.Digest_Success:
		testing.expect(t, false) // No default digest can escape a failed frame.
	}
}

@(test)
// Preserve real zero/empty successes and distinguish a decoded work error from a decoder error.
result_zero_successes :: proc(t: ^testing.T) {
	switch value in codec.decode_fixed(nil, codec.Byte_Width(0)) {
	case codec.Fixed_Decode_Success:
		testing.expect(t, value.value == codec.Fixed_Unsigned(0) && value.consumed == 0)
	case codec.Fixed_Error:
		testing.expect(t, false) // Width zero is valid without reading input.
	}
	absent := [1]u8{0}
	switch value in codec.decode_optional_borrowed(absent[:], codec.Byte_Limit(0)) {
	case codec.Optional_Success:
		testing.expect(t, !value.value.present && value.consumed == 1)
	case codec.Composite_Error:
		testing.expect(t, false) // Absence is an explicit successful value.
	}
	wire := [1]u8{1}
	switch value in codec.decode_work_borrowed(wire[:], codec.Byte_Limit(0)) {
	case codec.Work_Success:
		testing.expect(t, value.value.(codec.Work_Error) == .Out_Of_Gas)
	case codec.Composite_Error:
		testing.expect(t, false) // A work error is a valid protocol payload.
	}
}
