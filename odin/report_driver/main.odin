// Trusted local adapter for complete work-digest encoding and decoding.
package main
import codec "../codec"
import "core:encoding/hex"
import "core:fmt"
import "core:os"
import "core:strings"

// Accumulate unsigned decimal digits, rejecting overflow before multiplication or addition.
parse_decimal :: proc(text: string) -> (u64, bool) {
	// Empty input is not a number, even when the requested wire width is zero.
	if len(text) == 0 { return 0, false }
	x: u64
	// Accept decimal digits only and accumulate them without silently wrapping.
	for c in text {
		// Signs and other parser conveniences are not part of the unsigned value protocol.
		if c < '0' || c > '9' { return 0, false }
		digit := u64(c - '0')
		// Check the next arithmetic operation against the full unsigned maximum.
		if x > (max(u64) - digit) / 10 { return 0, false }
		x = x * 10 + digit
	}
	return x, true
}

// Parse signed host-width counts so invalid negative widths can reach the production API safely.
parse_width :: proc(text: string) -> (codec.Byte_Width, bool) {
	negative := strings.has_prefix(text, "-")
	digits := text
	// Strip only an explicit minus; the unsigned parser handles the remaining digit validation.
	if negative { digits = text[1:] }
	magnitude, ok := parse_decimal(digits)
	limit := u64(max(int))
	// The most negative signed integer has one more unit of magnitude than the positive maximum.
	if negative { limit += 1 }
	// Reject a magnitude that cannot be converted to a host int without truncation.
	if !ok || magnitude > limit { return 0, false }
	// Handle the signed minimum before the ordinary unsigned-to-signed conversion.
	if negative && magnitude == limit { return codec.Byte_Width(min(int)), true }
	count := int(magnitude)
	// Remaining negative magnitudes fit a positive host int and can be negated safely.
	if negative { count = -count }
	return codec.Byte_Width(count), true
}

// Convert a bounded lowercase-hex request into supplied stack storage; dash represents an empty payload.
parse_hex :: proc(text: string, storage: []u8) -> ([]u8, bool) {
	// The empty token avoids ambiguous missing fields in the batch protocol.
	if text == "-" { return storage[:0], true }
	// Whole pairs must fit actual adapter capacity before the standard parser writes into storage.
	if len(text) % 2 != 0 || len(text) / 2 > len(storage) { return nil, false }
	// Match the Nim adapter's strict lowercase alphabet before conversion.
	for c in text {
		if !(c >= '0' && c <= '9') && !(c >= 'a' && c <= 'f') { return nil, false }
	}
	return hex.decode_into_buffer(transmute([]u8)text, storage)
}

// Print just a validated payload or frame; dash represents zero bytes and no heap string is needed.
print_hex :: proc(bytes: []u8) {
	// Keep empty payloads explicit in decode responses.
	if len(bytes) == 0 { fmt.print("-"); return }
	digits := "0123456789abcdef"
	// Emit each byte's two nibbles in order; callers add a newline or consumed count afterward.
	for b in bytes { fmt.printf("%c%c", digits[b >> 4], digits[b & 15]) }
}

// Parse bounded test-utility capacities, which are separate from uint64 production resource ceilings.
parse_capacity :: proc(text: string, maximum: int) -> (int, bool) {
	value, ok := parse_width(text)
	count := int(value)
	// Never let an adapter request choose an unbounded allocation or unsafe slice endpoint.
	if !ok || count < 0 || count > maximum { return 0, false }
	return count, true
}

// Stable shared error labels; None is never passed here by a successful operation.
print_error :: proc(error: codec.Composite_Error) {
	switch error {
	case .Uninitialized:
		fmt.println("uninitialized") // An unvalidated result has no payload to print.
	case .Truncated:
		fmt.println("truncated") // Missing count, field or payload bytes.
	case .Non_Canonical:
		fmt.println("noncanonical") // Overlong natural discriminator.
	case .Limit_Exceeded:
		fmt.println("limitexceeded") // Caller resource policy.
	case .Output_Too_Small:
		fmt.println("outputtoosmall") // Destination must fit the full result.
	case .Aliased_Buffers:
		fmt.println("aliasedbuffers") // Protect all borrowed input.
	case .Length_Overflow:
		fmt.println("lengthoverflow") // Typed memory-span size cannot fit.
	case .Invalid_Tag:
		fmt.println("invalidtag") // Undefined optional/work discriminator.
	case .Invalid_Span:
		fmt.println("invalidspan") // Invalid caller-owned source descriptor.
	case .None:
		fmt.println("inputerror") // A success routed here is an adapter mistake.
	}
}

// Render the named fixed fields independently of the production header encoder, detecting swapped-field bugs.
print_header :: proc(value: codec.Report_Header) {
	bytes: [234]u8
	// Inspect the declared package_hash domain directly, independently of encoder layout.
	for i in 0 ..< 32 { bytes[0 + i] = value.package_hash[i] }
	// Render the named bundle_length with independent fixed-width byte arithmetic.
	for i in 0 ..< 4 { bytes[32 + i] = u8((u64(value.bundle_length) >> uint(8 * i)) & 255) }
	// Inspect the declared erasure_root domain directly, independently of encoder layout.
	for i in 0 ..< 32 { bytes[36 + i] = value.erasure_root[i] }
	// Inspect the declared segment_root domain directly, independently of encoder layout.
	for i in 0 ..< 32 { bytes[68 + i] = value.segment_root[i] }
	// Render the named segment_count with independent fixed-width byte arithmetic.
	for i in 0 ..< 2 { bytes[100 + i] = u8((u64(value.segment_count) >> uint(8 * i)) & 255) }
	// Inspect the declared anchor domain directly, independently of encoder layout.
	for i in 0 ..< 32 { bytes[102 + i] = value.anchor[i] }
	// Inspect the declared state_root domain directly, independently of encoder layout.
	for i in 0 ..< 32 { bytes[134 + i] = value.state_root[i] }
	// Inspect the declared accumulation_root domain directly, independently of encoder layout.
	for i in 0 ..< 32 { bytes[166 + i] = value.accumulation_root[i] }
	// Inspect the declared lookup_anchor domain directly, independently of encoder layout.
	for i in 0 ..< 32 { bytes[198 + i] = value.lookup_anchor[i] }
	// Render the named lookup_slot with independent fixed-width byte arithmetic.
	for i in 0 ..< 4 { bytes[230 + i] = u8((u64(value.lookup_slot) >> uint(8 * i)) & 255) }
	print_hex(bytes[:])
}
// Print complete named report fields; nested digest encoding uses the independently verified existing codec.
print_report :: proc(source: codec.Work_Report, wire: []u8, consumed: int) {
	value := source
	print_header(value.header); fmt.print(" ")
	prerequisites: [256]u8
	// Preserve the exact set member values, not just its cardinality.
	for i in 0 ..< value.prerequisite_count { copy(prerequisites[32 * i:32 * i + 32], value.prerequisites[i][:]) }
	print_hex(
		prerequisites[:32 * value.prerequisite_count],
	); fmt.printf(" %d ", u64(value.core)); print_hex(value.authorizer[:])
	fmt.printf(" %d ", u64(value.auth_gas))
	print_hex(
		wire[value.auth_output.offset:value.auth_output.offset + value.auth_output.length],
	); fmt.print(" ")
	lookup: [512]u8
	// Dictionary key and value order both remain visible to the independent oracle.
	for i in 0 ..< value.lookup_count { copy(lookup[64 * i:64 * i + 32], value.lookup[i].package_hash[:]); copy(lookup[64 * i + 32:64 * i + 64], value.lookup[i].segment_root[:]) }
	print_hex(lookup[:64 * value.lookup_count]); fmt.print(" ")
	digests: [65536]u8
	cursor := 0
	// Reconstruct each complete nested digest from its typed decoded fields and original whole-input spans.
	for i in 0 ..< value.digest_count {
		written := codec.encode_digest_borrowed(
			value.digests[i],
			wire,
			codec.Byte_Limit(49152),
			digests[cursor:],
		)
		assert(codec.error_of(written) == .None); cursor += codec.success_of(written).written
	}
	print_hex(digests[:cursor]); fmt.printf(" %d %d\n", value.digest_count, consumed)
}
// Construct a typed report from independent fixed/variable adapter fields, without the new report decoder.
build_report :: proc(p: []string, storage: []u8) -> (codec.Work_Report, []u8, bool) {
	pool := storage
	value: codec.Work_Report
	header_bytes: [234]u8
	header, header_ok := parse_hex(p[3], header_bytes[:])
	prerequisites: [256]u8
	prereqs, prereq_ok := parse_hex(p[4], prerequisites[:])
	authorizer: [32]u8
	auth_hash, hash_ok := parse_hex(p[6], authorizer[:])
	auth_bytes, digest_bytes: [65536]u8
	auth, auth_ok := parse_hex(p[8], auth_bytes[:])
	lookup_bytes: [512]u8
	lookup, lookup_ok := parse_hex(p[9], lookup_bytes[:])
	digests, digest_ok := parse_hex(p[10], digest_bytes[:])
	core, core_ok := parse_decimal(
		p[5],
	); gas, gas_ok := parse_decimal(p[7]); count, count_ok := parse_decimal(p[11])
	// Trusted text still has explicit utility bounds and exact hash/stride widths.
	if !header_ok ||
	   len(header) != 234 ||
	   !prereq_ok ||
	   len(prereqs) % 32 != 0 ||
	   !hash_ok ||
	   len(auth_hash) != 32 ||
	   !auth_ok ||
	   !lookup_ok ||
	   len(lookup) % 64 != 0 ||
	   !digest_ok ||
	   !core_ok ||
	   !gas_ok ||
	   !count_ok ||
	   count < 1 ||
	   count > 16 ||
	   len(auth) + len(digests) > len(pool) { return value, nil, false }
	value.header = codec.success_of(codec.decode_report_header(header))
	value.prerequisite_count = len(prereqs) / 32; value.lookup_count = len(lookup) / 64
	value.core = codec.Core_Index(
		core,
	); value.authorizer = codec.Authorizer_Hash(authorizer); value.auth_gas = codec.Gas(gas)
	// Keep successful payload descriptors tied to this one original pool, including nested digest outputs.
	copy(pool[:len(auth)], auth); copy(pool[len(auth):len(auth) + len(digests)], digests)
	pool = pool[:len(auth) + len(digests)]
	value.auth_output = {0, len(auth)}
	// Construct each ordered set member independently of report parsing.
	for i in 0 ..< value.prerequisite_count { copy(value.prerequisites[i][:], prereqs[32 * i:32 * i + 32]) }
	// Construct each dictionary pair without interpreting it as a serialized report.
	for i in 0 ..< value.lookup_count { copy(value.lookup[i].package_hash[:], lookup[64 * i:64 * i + 32]); copy(value.lookup[i].segment_root[:], lookup[64 * i + 32:64 * i + 64]) }
	value.digest_count = int(count)
	cursor := len(auth)
	// Existing digest decoders provide typed child values; the new report codec is not involved.
	for i in 0 ..< value.digest_count {
		parsed := codec.decode_digest_borrowed(pool[cursor:], codec.Byte_Limit(49152))
		if codec.error_of(parsed) != .None { return value, nil, false } 	// Malformed trusted child fixtures are adapter errors.
		value.digests[i] = codec.success_of(parsed).value
		switch blob in value.digests[i].output {
		case codec.Blob_Span:
			value.digests[i].output = codec.Blob_Span{cursor + blob.offset, blob.length} // Rebase to the one shared pool.
		case codec.Work_Error: // Error children retain no pool descriptor.
		case:
			unreachable() // Successful child decoding has a defined variant.
		}
		cursor += codec.success_of(parsed).consumed
	}
	return value, pool, cursor == len(pool)
}
// Verify owner-bound extraction and retained bytes after caller mutation; no detached span leaves the owner.
check_owner :: proc(wire: []u8, parsed: codec.Report_Success, cores: u64) {
	captured := codec.decode_owned_report(wire, cores)
	assert(codec.error_of(captured) == .None)
	owner := codec.success_of(captured)
	defer codec.release_report(&owner)
	info := codec.success_of(codec.owned_report_info(owner))
	assert(
		info.consumed == parsed.consumed &&
		info.digest_count == parsed.value.digest_count &&
		info.core == parsed.value.core &&
		info.auth_gas == parsed.value.auth_gas,
	)
	// Owner metadata preserves every fixed field, dependency identity and digest metric without exposing coordinates.
	assert(
		info.header == parsed.value.header &&
		info.authorizer == parsed.value.authorizer &&
		info.prerequisite_count == parsed.value.prerequisite_count &&
		info.lookup_count == parsed.value.lookup_count,
	)
	for i in 0 ..< parsed.value.prerequisite_count {
		item := codec.owned_report_prerequisite(owner, i)
		assert(
			codec.error_of(item) == .None &&
			codec.success_of(item) == parsed.value.prerequisites[i],
		)
	}
	for i in 0 ..< parsed.value.lookup_count {
		item := codec.owned_report_lookup(owner, i)
		assert(codec.error_of(item) == .None && codec.success_of(item) == parsed.value.lookup[i])
	}
	for i in 0 ..< parsed.value.digest_count {
		item := codec.owned_report_digest(owner, i)
		assert(codec.error_of(item) == .None)
		digest := codec.success_of(item)
		expected := parsed.value.digests[i]
		assert(
			digest.service == expected.service &&
			digest.code_hash == expected.code_hash &&
			digest.payload_hash == expected.payload_hash &&
			digest.accumulate_gas == expected.accumulate_gas &&
			digest.refine == expected.refine,
		)
		switch output in expected.output {
		case codec.Blob_Span:
			assert(digest.output.(codec.Owned_Work_Blob).length == output.length) // Length-only successful metadata.
		case codec.Work_Error:
			assert(digest.output.(codec.Work_Error) == output) // Payload-free error metadata.
		case:
			unreachable() // Decoded report children cannot contain nil work unions.
		}
	}
	assert(
		codec.error_of(codec.owned_report_prerequisite(owner, parsed.value.prerequisite_count)) ==
		.Invalid_Index,
	)
	assert(
		codec.error_of(codec.owned_report_lookup(owner, parsed.value.lookup_count)) ==
		.Invalid_Index,
	)
	assert(
		codec.error_of(codec.owned_report_digest(owner, parsed.value.digest_count)) ==
		.Invalid_Index,
	)
	assert(codec.error_of(codec.owned_report_info(nil)) == .Invalid_Owner)
	output, payload: [65536]u8
	original: [65536]u8
	copy(original[:len(wire)], wire)
	// Mutate all source fields, payloads and trailing data after capture has completed.
	for &b in wire { b = 99 }
	encoded := codec.encode_owned_report(owner, output[:])
	assert(codec.error_of(encoded) == .None && codec.success_of(encoded) == parsed.consumed)
	assert(output[0] == original[0])
	// Retained storage must reproduce every consumed byte, not any trailing input frame.
	for i in 0 ..< parsed.consumed { assert(output[i] == original[i]) }
	// All payloads are copied through their owner, including empty success blobs and payload-free errors.
	for index in 0 ..= parsed.value.digest_count {
		span := parsed.value.auth_output
		has_blob := true
		if index > 0 {
			switch blob in parsed.value.digests[index - 1].output {
			case codec.Blob_Span:
				span = blob // Select the independently decoded expected payload.
			case codec.Work_Error:
				has_blob = false // Work errors must reject extraction.
			case:
				unreachable() // Valid report children cannot be nil.
			}
		}
		copied := codec.copy_report_blob(owner, index, payload[:])
		if has_blob {
			assert(codec.error_of(copied) == .None && codec.success_of(copied) == span.length)
			for i in 0 ..< span.length { assert(payload[i] == original[span.offset + i]) } 	// Check each retained byte.
		} else { assert(codec.error_of(copied) == .Invalid_Index) } 	// Errors are not empty success payloads.
	}
	// A short output must retain every sentinel, including bytes outside the requested capacity.
	for &b in output { b = 77 }
	too_small := codec.encode_owned_report(owner, output[:parsed.consumed - 1])
	assert(codec.error_of(too_small) == .Output_Too_Small)
	for b in output { assert(b == 77) } 	// Any partial owner re-emission is a contract violation.
	assert(codec.error_of(codec.copy_report_blob(owner, -1, payload[:])) == .Invalid_Index)
	// Restore the original borrowed input before its independent field printing and re-encoding.
	copy(wire, original[:len(wire)])
}
// Exercise report encoder failures after a complete decode, checking late validation and overlap atomicity.
mutation :: proc(kind: string, wire: []u8, cores: u64) {
	decoded := codec.decode_report_borrowed(wire, cores)
	assert(codec.error_of(decoded) == .None)
	value := codec.success_of(decoded).value
	output, saved: [65536]u8
	// Sentinel coverage includes unused destination capacity, not just the expected report length.
	for &b in output { b = 77 }
	switch kind {
	case "span":
		value.digests[value.digest_count - 1].output = codec.Blob_Span{len(wire), 1} // A late invalid descriptor must be atomic.
	case "count":
		value.digest_count = 0 // A report must contain at least one work digest.
	case "tag":
		value.digests[value.digest_count - 1].output = codec.Work_Error(255) // Undefined native enum casts must fail safely.
	case "core":
		value.core = codec.Core_Index(cores) // First out-of-range configured core.
	case "alias":
		// Protect the complete source pool even if only a smaller selected blob is used.
		copy(saved[:len(wire)], wire)
		encoded := codec.encode_report_borrowed(value, wire, cores, wire)
		assert(codec.error_of(encoded) == .Aliased_Buffers)
		for i in 0 ..< len(wire) { assert(saved[i] == wire[i]) } 	// No preflight header may overwrite input.
		print_error(codec.error_of(encoded)); return
	case:
		assert(false) // The harness sends only registered mutation operations.
	}
	encoded := codec.encode_report_borrowed(value, wire, cores, output[:])
	assert(codec.error_of(encoded) != .None)
	for b in output { assert(b == 77) } 	// Even an invalid last digest must leave the header untouched.
	print_error(codec.error_of(encoded))
}
// Trusted file adapter shares one bounded request protocol across all three independent implementations.
main :: proc() {
	// Benchmark operations are separate from conformance file parsing and utility allocations.
	if len(os.args) > 1 && os.args[1] == "bench" { report_benchmark(); return }
	if len(os.args) != 2 { os.exit(1) } 	// Require an explicit local request file.
	data, err := os.read_entire_file(os.args[1], context.allocator)
	if err != nil { os.exit(1) } 	// A missing corpus is infrastructure failure, never a passing test.
	defer delete(data)
	lines := string(data)
	// Process requests in one native process; production decoding remains allocation-free.
	for line in strings.split_lines_iterator(&lines) {
		if len(line) == 0 { continue } 	// Ignore the final newline.
		parts: [12]string
		count := 0
		remaining := line
		for part in strings.split_by_byte_iterator(&remaining, ' ') {
			if count >= len(parts) { count += 1; break } 	// Reject extra textual fields rather than truncating them.
			parts[count] = part; count += 1
		}
		assert(count == 3 || count == 4 || count == 12)
		cores, cores_ok := parse_decimal(parts[1]); assert(cores_ok)
		storage, output: [65536]u8
		for &b in output { b = 77 } 	// Detect all partial encoder writes.
		if parts[0] == "D" && count == 3 {
			wire, ok := parse_hex(parts[2], storage[:]); assert(ok)
			parsed := codec.decode_report_borrowed(wire, cores)
			if codec.error_of(parsed) != .None { print_error(codec.error_of(parsed)) } else { 	// Only success contains a report.
				value := codec.success_of(parsed)
				check_owner(wire, value, cores)
				encoded := codec.encode_report_borrowed(value.value, wire, cores, output[:])
				assert(
					codec.error_of(encoded) == .None &&
					codec.success_of(encoded).written == value.consumed,
				)
				for i in 0 ..< value.consumed { assert(output[i] == wire[i]) } 	// Exact prefix re-encoding includes all nested metrics.
				print_report(value.value, wire, value.consumed)
			}
		} else if parts[0] == "E" && count == 12 { 	// Construct input fields independently from report decoding.
			cap, cap_ok := parse_capacity(parts[2], len(output)); assert(cap_ok)
			value, pool, ok := build_report(parts[:], storage[:]); assert(ok)
			encoded := codec.encode_report_borrowed(value, pool, cores, output[:cap])
			if codec.error_of(encoded) ==
			   .None { print_hex(output[:codec.success_of(encoded).written]); fmt.println() } else { 	// Failed encodes expose only a reason.
				for b in output { assert(b == 77) } 	// Whole destination atomicity includes unused capacity.
				print_error(codec.error_of(encoded))
			}
		} else if parts[0] == "X" && count == 4 { 	// Registered misuse probes target the native encoder contract.
			wire, ok := parse_hex(
				parts[3],
				storage[:],
			); assert(ok); mutation(parts[2], wire, cores)
		} else { assert(false) } 	// Trusted harness drift must not masquerade as a codec verdict.
	}
}
