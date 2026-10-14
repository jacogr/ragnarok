// Trusted local adapter for complete work-digest encoding and decoding.
package main
import codec "../codec"
import ownership_checks "../ownership_checks"
import "core:encoding/hex"
import "core:fmt"
import "core:os"
import "core:strings"

// Accumulate unsigned decimal digits, rejecting overflow before multiplication or addition.
parse_decimal :: proc(text: string) -> (u64, bool) {
	// Empty input is not a number, even when the requested wire width is zero.
	if len(text) == 0 {return 0, false}
	x: u64
	// Accept decimal digits only and accumulate them without silently wrapping.
	for c in text {
		// Signs and other parser conveniences are not part of the unsigned value protocol.
		if c < '0' || c > '9' {return 0, false}
		digit := u64(c - '0')
		// Check the next arithmetic operation against the full unsigned maximum.
		if x > (max(u64) - digit) / 10 {return 0, false}
		x = x * 10 + digit
	}
	return x, true
}

// Parse signed host-width counts so invalid negative widths can reach the production API safely.
parse_width :: proc(text: string) -> (codec.Byte_Width, bool) {
	negative := strings.has_prefix(text, "-")
	digits := text
	// Strip only an explicit minus; the unsigned parser handles the remaining digit validation.
	if negative {digits = text[1:]}
	magnitude, ok := parse_decimal(digits)
	limit := u64(max(int))
	// The most negative signed integer has one more unit of magnitude than the positive maximum.
	if negative {limit += 1}
	// Reject a magnitude that cannot be converted to a host int without truncation.
	if !ok || magnitude > limit {return 0, false}
	// Handle the signed minimum before the ordinary unsigned-to-signed conversion.
	if negative && magnitude == limit {return codec.Byte_Width(min(int)), true}
	count := int(magnitude)
	// Remaining negative magnitudes fit a positive host int and can be negated safely.
	if negative {count = -count}
	return codec.Byte_Width(count), true
}

// Convert a bounded lowercase-hex request into supplied stack storage; dash represents an empty payload.
parse_hex :: proc(text: string, storage: []u8) -> ([]u8, bool) {
	// The empty token avoids ambiguous missing fields in the batch protocol.
	if text == "-" {return storage[:0], true}
	// Whole pairs must fit actual adapter capacity before the standard parser writes into storage.
	if len(text) % 2 != 0 || len(text) / 2 > len(storage) {return nil, false}
	// Match the Nim adapter's strict lowercase alphabet before conversion.
	for c in text {
		if !(c >= '0' && c <= '9') && !(c >= 'a' && c <= 'f') {return nil, false}
	}
	return hex.decode_into_buffer(transmute([]u8)text, storage)
}

// Print just a validated payload or frame; dash represents zero bytes and no heap string is needed.
print_hex :: proc(bytes: []u8) {
	// Keep empty payloads explicit in decode responses.
	if len(bytes) == 0 {fmt.print("-"); return}
	digits := "0123456789abcdef"
	// Emit each byte's two nibbles in order; callers add a newline or consumed count afterward.
	for b in bytes {fmt.printf("%c%c", digits[b >> 4], digits[b & 15])}
}

// Parse bounded test-utility capacities, which are separate from uint64 production resource ceilings.
parse_capacity :: proc(text: string, maximum: int) -> (int, bool) {
	value, ok := parse_width(text)
	count := int(value)
	// Never let an adapter request choose an unbounded allocation or unsafe slice endpoint.
	if !ok || count < 0 || count > maximum {return 0, false}
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

// Check native decode/encode correspondence without aliasing source bytes or omitting nested fields.
same_prefix :: proc(wire: []u8, encoded: codec.Composite_Write, output: []u8, consumed: int) {
	assert(codec.error_of(encoded) == .None && codec.success_of(encoded).written == consumed)
	for i in 0 ..< consumed {assert(wire[i] == output[i])} 	// Every field, count and discriminator must agree.
}

// Print all decoded fields so the independent oracle verifies nominal values as well as wire reconstruction.
print_digest :: proc(value: codec.Work_Digest, wire: []u8, consumed: int) {
	fmt.print(u32(value.service)); fmt.print(" ")
	code := cast([32]u8)value.code_hash
	payload := cast([32]u8)value.payload_hash
	print_hex(code[:]); fmt.print(" "); print_hex(payload[:])
	fmt.printf(" %d ", u64(value.accumulate_gas))
	// The active union variant determines whether bytes follow the tag in this textual report.
	switch item in value.output {
	case codec.Blob_Span:
		fmt.print("0 "); print_hex(wire[item.offset:item.offset + item.length]) // Original-input-relative span.
	case codec.Work_Error:
		fmt.printf("%d -", int(item)) // Errors have no encoded blob.
	case:
		assert(false) // Successful decoder cannot produce a nil union.
	}
	fmt.printf(
		" %d %d %d %d %d %d\n",
		u64(value.refine.gas_used),
		u64(value.refine.imports),
		u64(value.refine.extrinsic_count),
		u64(value.refine.extrinsic_size),
		u64(value.refine.exports),
		consumed,
	)
}

// Trusted local batch adapter with explicit utility storage caps; the production codec itself allocates nothing.
main :: proc() {
	// Require a single readable request-file path.
	if len(os.args) != 2 {os.exit(1)}
	data, err := os.read_entire_file(os.args[1], context.allocator)
	if err != nil {os.exit(1)} 	// No requests exist on read failure.
	defer delete(data)
	lines := string(data)
	// Each nonempty line describes exactly one encode or decode request.
	for line in strings.split_lines_iterator(&lines) {
		if len(line) == 0 {continue} 	// Ignore the final newline.
		parts: [14]string
		remaining := line
		n: int
		// Reject extra fields instead of silently dropping unparsed text.
		for field in strings.split_by_byte_iterator(&remaining, ' ') {
			if n >= len(parts) {n += 1; break} 	// Resource bound on textual fields.
			parts[n] = field; n += 1
		}
		storage, output: [32768]u8
		// Whole-output sentinels detect any partial encoder commit.
		for &b in output {b = 77}
		if n == 14 && parts[0] == "E" {
			limit, limit_ok := parse_decimal(parts[1])
			cap, cap_ok := parse_capacity(parts[2], len(output))
			service, service_ok := parse_decimal(parts[3])
			code, payload_hash: [32]u8
			c, c_ok := parse_hex(parts[4], code[:])
			h, h_ok := parse_hex(parts[5], payload_hash[:])
			gas, gas_ok := parse_decimal(parts[6])
			tag, tag_ok := parse_decimal(parts[7])
			pool, pool_ok := parse_hex(parts[8], storage[:])
			metrics: [5]u64
			metrics_ok := true
			// Accumulate all five decimal metrics without narrowing or unchecked overflow.
			for &metric, index in metrics {
				parsed, ok := parse_decimal(parts[9 + index])
				metrics_ok = metrics_ok && ok
				metric = parsed
			}
			// Construct nominal fields only after exact widths and all textual domains are checked.
			if !limit_ok ||
			   !cap_ok ||
			   !service_ok ||
			   service > u64(max(u32)) ||
			   !c_ok ||
			   len(c) != 32 ||
			   !h_ok ||
			   len(h) != 32 ||
			   !gas_ok ||
			   !tag_ok ||
			   tag > 6 ||
			   !pool_ok ||
			   !metrics_ok {
				fmt.println("inputerror"); continue
			}
			work: codec.Work_Output
			if tag == 0 {work = codec.Blob_Span{0, len(pool)}} else // Success borrows the parsed payload.
			{work = codec.Work_Error(tag)} 	// Errors carry only their checked tag.
			value := codec.Work_Digest {
				codec.Service_Index(service),
				codec.Code_Hash(code),
				codec.Payload_Hash(payload_hash),
				codec.Gas(gas),
				work,
				{
					codec.Gas(metrics[0]),
					codec.Import_Count(metrics[1]),
					codec.Extrinsic_Count(metrics[2]),
					codec.Extrinsic_Bytes(metrics[3]),
					codec.Export_Count(metrics[4]),
				},
			}
			written := codec.encode_digest_borrowed(
				value,
				pool,
				codec.Byte_Limit(limit),
				output[:cap],
			)
			if codec.error_of(written) ==
			   .None {print_hex(output[:codec.success_of(written).written]); fmt.println()} else // Print only completed bytes.
			{
				// Every byte must remain untouched after any failure, including late suffix errors.
				for b in output {assert(b == 77)}
				print_error(codec.error_of(written))
			}
		} else if n == 3 && parts[0] == "D" {
			limit, limit_ok := parse_decimal(parts[1])
			wire, hex_ok := parse_hex(parts[2], storage[:])
			if !limit_ok || !hex_ok {fmt.println("inputerror"); continue} 	// Parse text before production decoding.
			parsed := codec.decode_digest_borrowed(wire, codec.Byte_Limit(limit))
			if codec.error_of(parsed) != .None {print_error(codec.error_of(parsed))} else // Failed tuple yields no public value.
			{
				// Verify the owned fixed fields, metrics and output against full official digest requests.
				ownership_checks.check_digest(wire, codec.Byte_Limit(limit), parsed)
				written := codec.encode_digest_borrowed(
					codec.success_of(parsed).value,
					wire,
					codec.Byte_Limit(limit),
					output[:],
				)
				same_prefix(wire, written, output[:], codec.success_of(parsed).consumed)
				print_digest(
					codec.success_of(parsed).value,
					wire,
					codec.success_of(parsed).consumed,
				)
			}
		} else {fmt.println("inputerror")} 	// Unknown operation or incorrect field count.
	}
}
