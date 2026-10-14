// Trusted local adapters for optional/work variants and complete nested preimages.
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

// Trusted local batch parser with fixed storage; production codecs themselves never allocate.
main :: proc() {
	if len(os.args) != 2 {os.exit(1)} 	// Require one batch-file path.
	data, err := os.read_entire_file(os.args[1], context.allocator)
	if err != nil {os.exit(1)} 	// No requests exist on read failure.
	defer delete(data)
	lines := string(data)
	for line in strings.split_lines_iterator(&lines) {
		if len(line) == 0 {continue} 	// Ignore the file's final newline.
		parts: [6]string
		remaining := line
		n: int
		for field in strings.split_by_byte_iterator(&remaining, ' ') {
			if n >= len(parts) {n += 1; break} 	// Never silently drop extra fields.
			parts[n] = field
			n += 1
		}
		wire_storage: [32768]u8
		output: [32768]u8
		for &b in output {b = 77} 	// Sentinel detects every failed encode's partial writes.
		if n == 5 && (parts[0] == "OE" || parts[0] == "WE") {
			tag, tag_ok := parse_width(parts[1])
			limit, limit_ok := parse_decimal(parts[2])
			capacity, cap_ok := parse_capacity(parts[3], len(output))
			pool, hex_ok := parse_hex(parts[4], wire_storage[:])
			if !tag_ok || !limit_ok || !cap_ok || !hex_ok {fmt.println("inputerror"); continue} 	// Textual ranges checked first.
			span := codec.Blob_Span {
				offset = 0,
				length = len(pool),
			}
			encoded: codec.Composite_Write
			if parts[0] == "OE" {
				if int(tag) < 0 || int(tag) > 1 {fmt.println("inputerror"); continue} 	// Only bool states can be constructed.
				encoded = codec.encode_optional_borrowed(
					{present = int(tag) == 1, blob = span},
					pool,
					codec.Byte_Limit(limit),
					output[:capacity],
				)
			} else {
				// Reject unsupported textual enum states before constructing the native work union.
				if int(tag) < 0 || int(tag) > 6 {fmt.println("invalidtag"); continue}
				value: codec.Work_Output
				if int(tag) == 0 {value = span} else {value = codec.Work_Error(tag)} 	// Success carries a span, errors only a tag.
				encoded = codec.encode_work_borrowed(
					value,
					pool,
					codec.Byte_Limit(limit),
					output[:capacity],
				)
			}
			if codec.error_of(encoded) != .None {
				for b in output {assert(b == 77)} 	// No failed operation may modify its destination.
				print_error(codec.error_of(encoded)); continue
			}
			print_hex(output[:codec.success_of(encoded).written]); fmt.println()
		} else if n == 3 && (parts[0] == "OD" || parts[0] == "WD") {
			// Decoded views refer only to this retained wire array; reconstruction uses separate output.
			limit, limit_ok := parse_decimal(parts[1])
			wire, hex_ok := parse_hex(parts[2], wire_storage[:])
			if !limit_ok || !hex_ok {fmt.println("inputerror"); continue} 	// Request syntax is not a binary-codec error.
			if parts[0] == "OD" {
				decoded := codec.decode_optional_borrowed(wire, codec.Byte_Limit(limit))
				if codec.error_of(decoded) !=
				   .None {print_error(codec.error_of(decoded)); continue} 	// No usable optional view on failure.
				// Match the owned snapshot to this independently checked conformance response.
				ownership_checks.check_optional(wire, codec.Byte_Limit(limit), decoded)
				same_prefix(
					wire,
					codec.encode_optional_borrowed(
						codec.success_of(decoded).value,
						wire,
						codec.Byte_Limit(limit),
						output[:],
					),
					output[:],
					codec.success_of(decoded).consumed,
				)
				if codec.success_of(decoded).value.present {
					span := codec.success_of(decoded).value.blob
					fmt.print(
						"present:",
					); print_hex(wire[span.offset:span.offset + span.length]); fmt.println("", codec.success_of(decoded).consumed)
				} else {fmt.println("absent", codec.success_of(decoded).consumed)} 	// Absence carries no payload bytes.
			} else {
				decoded := codec.decode_work_borrowed(wire, codec.Byte_Limit(limit))
				if codec.error_of(decoded) !=
				   .None {print_error(codec.error_of(decoded)); continue} 	// Invalid wire cannot be read as a union.
				// Match the owned snapshot to this independently checked conformance response.
				ownership_checks.check_work(wire, codec.Byte_Limit(limit), decoded)
				same_prefix(
					wire,
					codec.encode_work_borrowed(
						codec.success_of(decoded).value,
						wire,
						codec.Byte_Limit(limit),
						output[:],
					),
					output[:],
					codec.success_of(decoded).consumed,
				)
				switch value in codec.success_of(decoded).value {
				case codec.Blob_Span:
					fmt.print("0:"); print_hex(wire[value.offset:value.offset + value.length])
					fmt.println("", codec.success_of(decoded).consumed) // Success bytes.
				case codec.Work_Error:
					fmt.printf("%d:- %d\n", u8(value), codec.success_of(decoded).consumed) // Payload-free error.
				case:
					assert(false) // A successful decoder cannot return a nil/unknown union.
				}
			}
		} else if n == 6 && (parts[0] == "PE" || parts[0] == "PD") {
			items, items_ok := parse_decimal(parts[1])
			per_blob, per_ok := parse_decimal(parts[2])
			total, total_ok := parse_decimal(parts[3])
			if !items_ok || !per_ok || !total_ok {fmt.println("inputerror"); continue} 	// Preserve all policy bits.
			limits := codec.Preimage_Limits {
				codec.Element_Limit(items),
				codec.Byte_Limit(per_blob),
				codec.Byte_Limit(total),
			}
			records: [256]codec.Preimage
			if parts[0] == "PE" {
				// Build checked source descriptors from actual trusted text, never from a wire-claimed count.
				count, used: int
				ok := true
				text := parts[5]
				if text != "-" {
					for record in strings.split_by_byte_iterator(&text, ';') {
						fields := record
						service_text, service_field := strings.split_by_byte_iterator(&fields, ':')
						service, service_ok := parse_decimal(service_text)
						payload, hex_ok := parse_hex(fields, wire_storage[used:])
						if !service_field ||
						   !service_ok ||
						   service > u64(max(u32)) ||
						   !hex_ok ||
						   count >= len(records) {
							ok = false; break // Checked uint32 conversion and actual adapter-storage limits.
						}
						records[count] = {
							service = codec.Service_Index(service),
							blob = {offset = used, length = len(payload)},
						}
						count += 1; used += len(payload)
					}
				}
				capacity, cap_ok := parse_capacity(parts[4], len(output))
				if !ok || !cap_ok {fmt.println("inputerror"); continue} 	// No partial source descriptor list reaches production.
				encoded := codec.encode_preimages_borrowed(
					records[:count],
					wire_storage[:used],
					limits,
					output[:capacity],
				)
				if codec.error_of(encoded) != .None {
					for b in output {assert(b == 77)} 	// Even late nested failures preserve every output byte.
					print_error(codec.error_of(encoded)); continue
				}
				print_hex(output[:codec.success_of(encoded).written]); fmt.println()
			} else {
				// Caller record capacity is a separate constraint from its explicit maximum permitted count.
				capacity, cap_ok := parse_capacity(parts[4], len(records))
				wire, hex_ok := parse_hex(parts[5], wire_storage[:])
				if !cap_ok || !hex_ok {fmt.println("inputerror"); continue} 	// Checked utility endpoints.
				for &record in records {record = {
						service = codec.Service_Index(999),
						blob = {offset = 333, length = 444},
					}} // Failure sentinels.
				decoded := codec.decode_preimages_borrowed(wire, limits, records[:capacity])
				if codec.error_of(decoded) != .None {
					for record in records {assert(u32(record.service) == 999 && record.blob.offset == 333 && record.blob.length == 444)} 	// Atomic nested failures.
					print_error(codec.error_of(decoded)); continue
				}
				// Compare every owned service ID, nested payload and complete canonical frame.
				ownership_checks.check_preimages(wire, limits, decoded, records[:])
				same_prefix(
					wire,
					codec.encode_preimages_borrowed(
						records[:codec.success_of(decoded).count],
						wire,
						limits,
						output[:],
					),
					output[:],
					codec.success_of(decoded).consumed,
				)
				if codec.success_of(decoded).count == 0 {fmt.print("-")} 	// Explicit empty record prefix.
				for i in 0 ..< codec.success_of(decoded).count {
					if i > 0 {fmt.print(";")} 	// Delimit actual decoded tuples only.
					fmt.printf("%d:", u32(records[i].service))
					span := records[i].blob
					print_hex(wire[span.offset:span.offset + span.length])
				}
				fmt.println("", codec.success_of(decoded).consumed)
			}
		} else {fmt.println("inputerror")} 	// Unknown commands/token counts never select a production decoder.
	}
}
