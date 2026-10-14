package ownership_checks

import codec "../codec"

// Compare a snapshot with the independently checked prefix and payloads; only copied bytes leave its owner.
verify :: proc(frame: codec.Owned_Frame, wire: []u8, consumed: int, spans: []codec.Blob_Span) {
	info := codec.owned_info(frame)
	assert(codec.error_of(info) == .None)
	assert(
		codec.success_of(info).consumed == consumed &&
		codec.success_of(info).blob_count == len(spans),
	)
	encoded := make([]u8, consumed)
	defer delete(encoded)
	written := codec.encode_owned(frame, encoded)
	assert(codec.error_of(written) == .None && codec.success_of(written) == consumed)
	// Unrelated trailing data must not enter retained storage or re-encoding.
	for value, index in encoded { assert(value == wire[index]) }
	// Each payload must remain associated with this owner's private source bytes.
	for span, index in spans {
		length := codec.owned_blob_length(frame, index)
		assert(codec.error_of(length) == .None && codec.success_of(length) == span.length)
		payload := make([]u8, codec.success_of(length))
		copied := codec.copy_owned_blob(frame, index, payload)
		assert(codec.error_of(copied) == .None && codec.success_of(copied) == span.length)
		// Compare complete blobs, including zero-length successes.
		for value, i in payload { assert(value == wire[span.offset + i]) }
		delete(payload)
	}
}

// Check owned byte strings against successful official vectors and random adapter requests.
check_bytes :: proc(wire: []u8, limit: codec.Byte_Limit, expected: codec.Blob_Result) {
	parsed := codec.decode_owned_bytes(wire, limit)
	assert(codec.error_of(parsed) == .None)
	frame := codec.success_of(parsed)
	defer codec.destroy_owned(&frame)
	value := codec.success_of(expected)
	spans := [1]codec.Blob_Span{{value.offset, value.length}}
	verify(frame, wire, value.consumed, spans[:])
}

// Check absent/present optionals, retaining a distinct payload for empty presence.
check_optional :: proc(wire: []u8, limit: codec.Byte_Limit, expected: codec.Optional_Result) {
	parsed := codec.decode_owned_optional(wire, limit)
	assert(codec.error_of(parsed) == .None)
	frame := codec.success_of(parsed)
	defer codec.destroy_owned(&frame)
	value := codec.success_of(expected)
	info := codec.owned_optional_info(frame)
	assert(codec.error_of(info) == .None)
	// Only the present union alternative has a length and copyable payload.
	if value.value.present {
		present, ok := codec.success_of(info).(codec.Owned_Present)
		assert(ok && present.length == value.value.blob.length)
		spans := [1]codec.Blob_Span{value.value.blob}
		verify(frame, wire, value.consumed, spans[:])
	} else {
		// Absence has no payload or default length to read.
		_, ok := codec.success_of(info).(codec.Owned_Absent)
		assert(ok)
		verify(frame, wire, value.consumed, nil)
	}
}

// Check successful work output and all six payload-free work errors as decoded values.
check_work :: proc(wire: []u8, limit: codec.Byte_Limit, expected: codec.Work_Result) {
	parsed := codec.decode_owned_work(wire, limit)
	assert(codec.error_of(parsed) == .None)
	frame := codec.success_of(parsed)
	defer codec.destroy_owned(&frame)
	value := codec.success_of(expected)
	info := codec.owned_work_info(frame)
	assert(codec.error_of(info) == .None)
	// Match each protocol union alternative without letting a borrowed descriptor escape the owner.
	switch output in value.value {
	case codec.Blob_Span:
		blob, ok := codec.success_of(info).(codec.Owned_Work_Blob)
		assert(ok && blob.length == output.length)
		spans := [1]codec.Blob_Span{output}
		verify(frame, wire, value.consumed, spans[:])
	case codec.Work_Error:
		error, ok := codec.success_of(info).(codec.Work_Error)
		assert(ok && error == output)
		verify(frame, wire, value.consumed, nil)
	case:
		panic("successful work decode has no alternative") // A nil work output is not a valid schema value.
	}
}

// Check every nominal service ID and nested payload in full preimage conformance requests.
check_preimages :: proc(
	wire: []u8,
	limits: codec.Preimage_Limits,
	expected: codec.Preimage_Result,
	records: []codec.Preimage,
) {
	parsed := codec.decode_owned_preimages(wire, limits)
	assert(codec.error_of(parsed) == .None)
	frame := codec.success_of(parsed)
	defer codec.destroy_owned(&frame)
	value := codec.success_of(expected)
	spans := make([]codec.Blob_Span, value.count)
	defer delete(spans)
	// Each initialized tuple has its own service and payload bound to the same immutable owner.
	for &span, index in spans {
		span = records[index].blob
		service := codec.owned_service(frame, index)
		assert(
			codec.error_of(service) == .None &&
			codec.success_of(service) == records[index].service,
		)
	}
	verify(frame, wire, value.consumed, spans)
}

// Check fixed digest fields, all metrics and the nested work alternative against official full vectors.
check_digest :: proc(wire: []u8, limit: codec.Byte_Limit, expected: codec.Digest_Result) {
	parsed := codec.decode_owned_digest(wire, limit)
	assert(codec.error_of(parsed) == .None)
	frame := codec.success_of(parsed)
	defer codec.destroy_owned(&frame)
	info := codec.owned_digest_info(frame)
	assert(codec.error_of(info) == .None)
	actual := codec.success_of(info)
	value := codec.success_of(expected).value
	assert(
		actual.service == value.service &&
		actual.code_hash == value.code_hash &&
		actual.payload_hash == value.payload_hash,
	)
	assert(actual.accumulate_gas == value.accumulate_gas && actual.refine == value.refine)
	// Work-error values carry no payload, while successful work retains exactly one blob.
	switch output in value.output {
	case codec.Blob_Span:
		blob, ok := actual.output.(codec.Owned_Work_Blob)
		assert(ok && blob.length == output.length)
		spans := [1]codec.Blob_Span{output}
		verify(frame, wire, codec.success_of(expected).consumed, spans[:])
	case codec.Work_Error:
		error, ok := actual.output.(codec.Work_Error)
		assert(ok && error == output)
		verify(frame, wire, codec.success_of(expected).consumed, nil)
	case:
		panic("successful digest has no work alternative") // The normative work tag always selects a defined alternative.
	}
}
