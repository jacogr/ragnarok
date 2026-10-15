// GP v0.7.1 C.1/C.2 complete work reports; structural policy is specified in spec/work-report.md.
package codec

// Package identity is distinct from its roots and from historical block hashes.
Package_Hash :: distinct [32]u8
// Erasure commitment identifies the auditable bundle.
Erasure_Root :: distinct [32]u8
// Export commitment identifies the segment tree.
Segment_Root :: distinct [32]u8
// Historical block identity used by the refinement context.
Block_Hash :: distinct [32]u8
// Posterior state commitment at the refinement anchor.
State_Root :: distinct [32]u8
// Accumulation output log commitment at the refinement anchor.
Accumulation_Root :: distinct [32]u8
// Authorization-code identity is not a work-package identity.
Authorizer_Hash :: distinct [32]u8
// Serialized bundle byte count uses E4.
Bundle_Length :: distinct u32
// Exported segment count uses E2.
Segment_Count :: distinct u16
// Historical lookup timeslot uses E4.
Lookup_Slot :: distinct u32
// A core is a general natural with a chain-configuration-dependent bound.
Core_Index :: distinct u64
// Owned fixed availability/context fields; prerequisite hashes follow separately on the wire.
Report_Header :: struct {
	package_hash:      Package_Hash,
	bundle_length:     Bundle_Length,
	erasure_root:      Erasure_Root,
	segment_root:      Segment_Root,
	segment_count:     Segment_Count,
	anchor:            Block_Hash,
	state_root:        State_Root,
	accumulation_root: Accumulation_Root,
	lookup_anchor:     Block_Hash,
	lookup_slot:       Lookup_Slot,
}
// Lookup pairs are ordered strictly by package hash, with identity-encoded roots.
Segment_Lookup :: struct {
	package_hash: Package_Hash,
	segment_root: Segment_Root,
}
// Fixed metadata capacities follow protocol maxima, not attacker-controlled allocation requests.
// Payload spans borrow the exact matching original input/pool; unused array elements have no meaning.
Work_Report :: struct {
	header:             Report_Header,
	prerequisites:      [8]Package_Hash,
	prerequisite_count: int,
	core:               Core_Index,
	authorizer:         Authorizer_Hash,
	auth_gas:           Gas,
	auth_output:        Blob_Span,
	lookup:             [8]Segment_Lookup,
	lookup_count:       int,
	digests:            [16]Work_Digest,
	digest_count:       int,
}
// Only the success alternative contains a complete report and its consumed prefix.
Report_Success :: struct {
	value:    Work_Report,
	consumed: int,
}
// Default outcomes are failures, never reports with default fields.
Report_Result :: Codec_Result(Report_Success, Composite_Error)
// Fixed header decode result contains no borrowed byte references.
Report_Header_Result :: Codec_Result(Report_Header, Composite_Error)

// Read exactly the availability/context fixed prefix, leaving prerequisites to the enclosing codec.
decode_report_header :: proc(input: []u8) -> Report_Header_Result {
	// Prove all fixed extents before indexing or converting any field.
	if len(input) < 234 { return Composite_Error.Truncated }
	value: Report_Header
	// Copy the complete package_hash into its nominal owned domain.
	for i in 0 ..< 32 { value.package_hash[i] = input[0 + i] }
	value.bundle_length = Bundle_Length(
		success_of(decode_fixed(input[32:36], Byte_Width(4))).value,
	)
	// Copy the complete erasure_root into its nominal owned domain.
	for i in 0 ..< 32 { value.erasure_root[i] = input[36 + i] }
	// Copy the complete segment_root into its nominal owned domain.
	for i in 0 ..< 32 { value.segment_root[i] = input[68 + i] }
	value.segment_count = Segment_Count(
		success_of(decode_fixed(input[100:102], Byte_Width(2))).value,
	)
	// Copy the complete anchor into its nominal owned domain.
	for i in 0 ..< 32 { value.anchor[i] = input[102 + i] }
	// Copy the complete state_root into its nominal owned domain.
	for i in 0 ..< 32 { value.state_root[i] = input[134 + i] }
	// Copy the complete accumulation_root into its nominal owned domain.
	for i in 0 ..< 32 { value.accumulation_root[i] = input[166 + i] }
	// Copy the complete lookup_anchor into its nominal owned domain.
	for i in 0 ..< 32 { value.lookup_anchor[i] = input[198 + i] }
	value.lookup_slot = Lookup_Slot(success_of(decode_fixed(input[230:234], Byte_Width(4))).value)
	return value
}
// Emit a value snapshot of the fixed header atomically; no caller pool is retained.
encode_report_header :: proc(source: Report_Header, output: []u8) -> Composite_Write {
	value := source
	// Whole-prefix capacity precedes any write, including the first hash byte.
	if len(output) < 234 { return Composite_Error.Output_Too_Small }
	// Identity encoding retains the exact package_hash byte order.
	for i in 0 ..< 32 { output[0 + i] = value.package_hash[i] }
	encoded_bundle_length :=
		success_of(encode_fixed(Fixed_Unsigned(value.bundle_length), Byte_Width(4))).encoded
	copy(output[32:36], encoded_bundle_length.bytes[:4])
	// Identity encoding retains the exact erasure_root byte order.
	for i in 0 ..< 32 { output[36 + i] = value.erasure_root[i] }
	// Identity encoding retains the exact segment_root byte order.
	for i in 0 ..< 32 { output[68 + i] = value.segment_root[i] }
	encoded_segment_count :=
		success_of(encode_fixed(Fixed_Unsigned(value.segment_count), Byte_Width(2))).encoded
	copy(output[100:102], encoded_segment_count.bytes[:2])
	// Identity encoding retains the exact anchor byte order.
	for i in 0 ..< 32 { output[102 + i] = value.anchor[i] }
	// Identity encoding retains the exact state_root byte order.
	for i in 0 ..< 32 { output[134 + i] = value.state_root[i] }
	// Identity encoding retains the exact accumulation_root byte order.
	for i in 0 ..< 32 { output[166 + i] = value.accumulation_root[i] }
	// Identity encoding retains the exact lookup_anchor byte order.
	for i in 0 ..< 32 { output[198 + i] = value.lookup_anchor[i] }
	encoded_lookup_slot :=
		success_of(encode_fixed(Fixed_Unsigned(value.lookup_slot), Byte_Width(4))).encoded
	copy(output[230:234], encoded_lookup_slot.bytes[:4])
	return Composite_Write_Success{234}
}
// Compare hash bytes lexicographically; equality is deliberately not ordered (sets/maps are unique).
report_hash_less :: proc(a, b: [32]u8) -> bool {
	// The first differing octet decides order, independently of host integer endianness.
	for i in 0 ..< 32 {
		// A strict comparison rejects repeated keys as well as descending keys.
		if a[i] != b[i] { return a[i] < b[i] }
	}
	return false
}
// Consume one canonical natural without advancing on failure or exposing a partial report.
report_natural :: proc(input: []u8, cursor: ^int) -> Decode_Result {
	parsed := decode(input[cursor^:])
	// Failed canonicality/truncation leaves the enclosing cursor unchanged.
	if error_of(parsed) == .None { cursor^ += success_of(parsed).consumed }
	return parsed
}
// Preserve the only two malformed-natural reasons reachable during report parsing.
report_natural_error :: proc(error: Decode_Error) -> Composite_Error {
	// A missing payload is different from an overlong canonical representation.
	if error == .Truncated { return .Truncated }
	return .Non_Canonical
}
// Parse one complete bounded report without allocation; successful payloads use whole-input coordinates.
decode_report_borrowed :: proc(input: []u8, core_count: u64) -> Report_Result {
	header := decode_report_header(input)
	// Incomplete fixed fields cannot create a usable report.
	if error_of(header) != .None { return error_of(header) }
	value := Work_Report {
		header = success_of(header),
	}
	cursor := 234
	prerequisite_count := report_natural(input, &cursor)
	// Check canonical count before any count-driven indexing.
	if error_of(prerequisite_count) !=
	   .None { return report_natural_error(error_of(prerequisite_count)) }
	count := u64(success_of(prerequisite_count).value)
	// Check protocol count before narrowing; then prove the entire fixed-stride extent.
	if count > 8 { return Composite_Error.Limit_Exceeded }
	if count > u64((len(input) - cursor) / 32) { return Composite_Error.Truncated }
	value.prerequisite_count = int(count)
	// Set members must be strictly increasing; no implicit sorting of received data.
	for i in 0 ..< value.prerequisite_count {
		copy(value.prerequisites[i][:], input[cursor:cursor + 32]); cursor += 32
		// Reject both duplicates and descending keys before exposing any report fields.
		if i > 0 &&
		   !report_hash_less(
				   cast([32]u8)value.prerequisites[i - 1],
				   cast([32]u8)value.prerequisites[i],
			   ) { return Composite_Error.Non_Canonical }
	}
	core := report_natural(input, &cursor)
	// The core uses the general natural codec, followed by chain-specific range validation.
	if error_of(core) != .None { return report_natural_error(error_of(core)) }
	value.core = Core_Index(success_of(core).value)
	if u64(value.core) >= core_count { return Composite_Error.Limit_Exceeded }
	// Authorizer identity is fixed width, regardless of which core is selected.
	if len(input) - cursor < 32 { return Composite_Error.Truncated }
	copy(value.authorizer[:], input[cursor:cursor + 32]); cursor += 32
	gas := report_natural(input, &cursor)
	// Authorization gas must be complete and canonical before reading authorization output.
	if error_of(gas) != .None { return report_natural_error(error_of(gas)) }
	value.auth_gas = Gas(success_of(gas).value)
	auth := decode_bytes_borrowed(input[cursor:], Byte_Limit(49152))
	// Limit validation precedes proof of the actual authorization payload extent.
	if error_of(auth) != .None { return composite_blob_error(error_of(auth)) }
	value.auth_output = {cursor + success_of(auth).offset, success_of(auth).length}
	cursor += success_of(auth).consumed
	total := value.auth_output.length
	lookup_count := report_natural(input, &cursor)
	// Lookup counts share the eight-entry dependency budget with prerequisites.
	if error_of(lookup_count) != .None { return report_natural_error(error_of(lookup_count)) }
	count = u64(success_of(lookup_count).value)
	if count > u64(8 - value.prerequisite_count) { return Composite_Error.Limit_Exceeded }
	if count > u64((len(input) - cursor) / 64) { return Composite_Error.Truncated }
	value.lookup_count = int(count)
	// Dictionary entries retain their complete fixed key/root bytes in canonical key order.
	for i in 0 ..< value.lookup_count {
		copy(value.lookup[i].package_hash[:], input[cursor:cursor + 32])
		copy(value.lookup[i].segment_root[:], input[cursor + 32:cursor + 64]); cursor += 64
		// Duplicate keys are invalid even if the roots differ.
		if i > 0 &&
		   !report_hash_less(
				   cast([32]u8)value.lookup[i - 1].package_hash,
				   cast([32]u8)value.lookup[i].package_hash,
			   ) { return Composite_Error.Non_Canonical }
	}
	digest_count := report_natural(input, &cursor)
	// No typed digest storage is indexed before validating the bounded count.
	if error_of(digest_count) != .None { return report_natural_error(error_of(digest_count)) }
	count = u64(success_of(digest_count).value)
	if count < 1 || count > 16 { return Composite_Error.Limit_Exceeded }
	value.digest_count = int(count)
	// Decode every digest, including the final metric of the final digest, before returning success.
	for i in 0 ..< value.digest_count {
		parsed := decode_digest_borrowed(input[cursor:], Byte_Limit(49152 - total))
		// Enclosing reports preserve precise nested failure reasons.
		if error_of(parsed) != .None { return error_of(parsed) }
		value.digests[i] = success_of(parsed).value
		// Only successful work variants retain a span, rebased to the complete input.
		switch blob in value.digests[i].output {
		case Blob_Span:
			total += blob.length
			value.digests[i].output = Blob_Span{blob.offset + cursor, blob.length}
		case Work_Error: // Payload-free work errors consume no aggregate blob budget.
		case:
			unreachable() // The nested decoder never returns an undefined work union.
		}
		cursor += success_of(parsed).consumed
	}
	return Report_Success{value, cursor}
}
// Preflight every descriptor, count, ordering and resource bound before report encoding can mutate output.
measure_report_borrowed :: proc(
	value: Work_Report,
	pool_size: int,
	core_count: u64,
) -> Composite_Write {
	// Signed API counts must fit their fixed metadata arrays before indexing.
	if value.prerequisite_count < 0 ||
	   value.lookup_count < 0 ||
	   value.prerequisite_count > 8 ||
	   value.lookup_count > 8 ||
	   value.lookup_count > 8 - value.prerequisite_count ||
	   value.digest_count < 1 ||
	   value.digest_count > 16 ||
	   u64(value.core) >= core_count { return Composite_Error.Limit_Exceeded }
	// Caller spans are validated by subtraction, including empty spans at the pool end.
	if !valid_blob_span(value.auth_output, pool_size) { return Composite_Error.Invalid_Span }
	total := value.auth_output.length
	if total > 49152 { return Composite_Error.Limit_Exceeded }
	// Canonical input ordering is required instead of silently sorting caller-owned records.
	for i in 1 ..< value.prerequisite_count {
		if !report_hash_less(
			cast([32]u8)value.prerequisites[i - 1],
			cast([32]u8)value.prerequisites[i],
		) { return Composite_Error.Non_Canonical }
	}
	// Segment roots do not affect dictionary order; only package keys do.
	for i in 1 ..< value.lookup_count {
		if !report_hash_less(
			cast([32]u8)value.lookup[i - 1].package_hash,
			cast([32]u8)value.lookup[i].package_hash,
		) { return Composite_Error.Non_Canonical }
	}
	required :=
		234 +
		encode(Natural(value.prerequisite_count)).length +
		32 * value.prerequisite_count +
		encode(Natural(value.core)).length +
		32 +
		encode(Natural(value.auth_gas)).length +
		encode(Natural(total)).length +
		total +
		encode(Natural(value.lookup_count)).length +
		64 * value.lookup_count +
		encode(Natural(value.digest_count)).length
	// All fixed report fields are protocol-bounded; nested lengths are proved before host additions.
	for i in 0 ..< value.digest_count {
		digest := value.digests[i]
		measured := measure_work(digest.output, pool_size, Byte_Limit(49152 - total))
		// A late invalid span/tag/payload must not commit the earlier report header.
		if error_of(measured) != .None { return measured }
		switch blob in digest.output {
		case Blob_Span:
			total += blob.length // Count only successful payloads against the common budget.
		case Work_Error: // Error variants add no payload bytes.
		case:
			unreachable() // measure_work already rejected an undefined union.
		}
		numbers := [5]u64 {
			u64(digest.refine.gas_used),
			u64(digest.refine.imports),
			u64(digest.refine.extrinsic_count),
			u64(digest.refine.extrinsic_size),
			u64(digest.refine.exports),
		}
		size := 76 + success_of(measured).written
		// Each natural contributes at most nine bytes to the checked bounded digest.
		for number in numbers { size += encode(Natural(number)).length }
		// Subtraction protects this addition even on hosts with narrower address spaces.
		if size > max(int) - required { return Composite_Error.Length_Overflow }
		required += size
	}
	return Composite_Write_Success{required}
}
// Commit one previously measured natural into a proven output extent; this helper never allocates.
report_put_natural :: proc(number: u64, output: []u8, cursor: ^int) {
	encoded := encode(Natural(number))
	copy(
		output[cursor^:cursor^ + encoded.length],
		encoded.bytes[:encoded.length],
	); cursor^ += encoded.length
}
// Encode a value snapshot atomically, protecting the entire borrowed pool against overlap.
encode_report_borrowed :: proc(
	source: Work_Report,
	pool: []u8,
	core_count: u64,
	output: []u8,
) -> Composite_Write {
	value := source
	measured := measure_report_borrowed(value, len(pool), core_count)
	// No writes are permitted until every nested field and aggregate policy has validated.
	if error_of(measured) != .None { return measured }
	required := success_of(measured).written
	if len(output) < required { return Composite_Error.Output_Too_Small }
	if container_overlaps(
		raw_data(pool),
		len(pool),
		raw_data(output),
		required,
	) { return Composite_Error.Aliased_Buffers }
	_ = encode_report_header(value.header, output[:234])
	cursor := 234
	report_put_natural(u64(value.prerequisite_count), output, &cursor)
	// Copy ordered prerequisites without changing caller-owned metadata.
	for i in 0 ..< value.prerequisite_count { copy(output[cursor:cursor + 32], value.prerequisites[i][:]); cursor += 32 }
	report_put_natural(u64(value.core), output, &cursor)
	copy(output[cursor:cursor + 32], value.authorizer[:]); cursor += 32
	report_put_natural(u64(value.auth_gas), output, &cursor)
	report_put_natural(u64(value.auth_output.length), output, &cursor)
	copy(
		output[cursor:cursor + value.auth_output.length],
		pool[value.auth_output.offset:value.auth_output.offset + value.auth_output.length],
	); cursor += value.auth_output.length
	report_put_natural(u64(value.lookup_count), output, &cursor)
	// Commit complete dictionary entries after their order and extents have validated.
	for i in 0 ..< value.lookup_count {
		copy(
			output[cursor:cursor + 32],
			value.lookup[i].package_hash[:],
		); copy(output[cursor + 32:cursor + 64], value.lookup[i].segment_root[:]); cursor += 64
	}
	report_put_natural(u64(value.digest_count), output, &cursor)
	// Nested encoders retain their own checked result contracts; preflight has proved each must succeed.
	for i in 0 ..< value.digest_count {
		encoded := encode_digest_borrowed(
			value.digests[i],
			pool,
			Byte_Limit(49152),
			output[cursor:required],
		)
		assert(error_of(encoded) == .None)
		cursor += success_of(encoded).written
	}
	return Composite_Write_Success{cursor}
}
