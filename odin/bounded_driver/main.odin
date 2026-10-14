// Trusted batch adapter: BE/BD for bytes, SE/SD for fixed-width sequences.
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

// Give typed failures stable labels shared by both native test adapters.
print_error :: proc(error: codec.Container_Error) {
	switch error {
	case .Uninitialized:
		fmt.println("uninitialized") // An unvalidated result has no payload to print.
	// Wire does not include the complete prefix/payload.
	case .Truncated:
		fmt.println("truncated")
	// The encoded length uses unnecessary extra octets.
	case .Non_Canonical:
		fmt.println("noncanonical")
	// Caller policy disallows the declared size/count.
	case .Limit_Exceeded:
		fmt.println("limitexceeded")
	// The caller-owned destination cannot hold the complete result.
	case .Output_Too_Small:
		fmt.println("outputtoosmall")
	// Unsupported signed element width was rejected before reading or shifting.
	case .Invalid_Width:
		fmt.println("invalidwidth")
	// Some fixed-width value cannot be encoded without losing significant bits.
	case .Value_Out_Of_Range:
		fmt.println("valueoutofrange")
	// Input and written output spans overlap.
	case .Aliased_Buffers:
		fmt.println("aliasedbuffers")
	// A host memory-span size cannot be represented safely.
	case .Length_Overflow:
		fmt.println("lengthoverflow")
	// This helper is only for failures; success here indicates bad adapter routing.
	case .None:
		fmt.println("inputerror")
	}
}

// Parse bounded test-utility capacities, which are separate from uint64 production resource ceilings.
parse_capacity :: proc(text: string, maximum: int) -> (int, bool) {
	value, ok := parse_width(text)
	count := int(value)
	// Never let an adapter request choose an unbounded allocation or unsafe slice endpoint.
	if !ok || count < 0 || count > maximum {return 0, false}
	return count, true
}

// Execute a trusted local batch, retaining its source bytes until all borrowed line spans have been used.
main :: proc() {
	// Require the one request-file path before accessing it.
	if len(os.args) != 2 {os.exit(1)}
	data, err := os.read_entire_file(os.args[1], context.allocator)
	// Failure to read means there are no requests to process.
	if err != nil {os.exit(1)}
	defer delete(data)
	lines := string(data)
	// Each nonempty line routes to one of the four production operations.
	for line in strings.split_lines_iterator(&lines) {
		if len(line) == 0 {continue} 	// Ignore the trailing newline, not a request.
		parts: [5]string
		remaining := line
		n: int
		// Bound token storage and reject any extra field rather than dropping it silently.
		for part in strings.split_by_byte_iterator(&remaining, ' ') {
			if n >= len(parts) {n += 1; break} 	// Extra input cannot fit the documented protocol.
			parts[n] = part
			n += 1
		}
		input_storage: [32768]u8
		output_storage: [32768]u8
		values: [512]codec.Fixed_Unsigned
		// Byte encoding validates policy and supplied output capacity independently.
		if n == 4 && parts[0] == "BE" {
			limit, limit_ok := parse_decimal(parts[1])
			capacity, cap_ok := parse_capacity(parts[2], len(output_storage))
			value, hex_ok := parse_hex(parts[3], input_storage[:])
			if !limit_ok || !cap_ok || !hex_ok {fmt.println("inputerror"); continue} 	// Syntax precedes native work.
			for &b in output_storage {b = 77} 	// Sentinel exposes any partial writes on failure.
			encoded := codec.encode_bytes(
				value,
				codec.Byte_Limit(limit),
				output_storage[:capacity],
			)
			if codec.error_of(encoded) != .None {
				// Preserve the destination even when limits, capacity or alias policy reject encoding.
				for b in output_storage {assert(b == 77)}
				print_error(codec.error_of(encoded)); continue
			}
			print_hex(output_storage[:codec.success_of(encoded).written]); fmt.println()
		} else if n == 3 && parts[0] == "BD" {
			// Byte decode returns indices into retained stack input, without copying or allocating a payload.
			limit, ok := parse_decimal(parts[1])
			wire, hex_ok := parse_hex(parts[2], input_storage[:])
			if !ok || !hex_ok {fmt.println("inputerror"); continue} 	// Reject textual errors before binary decoding.
			decoded := codec.decode_bytes_borrowed(wire, codec.Byte_Limit(limit))
			if codec.error_of(decoded) != .None {print_error(codec.error_of(decoded)); continue} 	// A failed span has no payload to print.
			// Check owner-bound extraction and canonical bytes for every successful shared request.
			ownership_checks.check_bytes(wire, codec.Byte_Limit(limit), decoded)
			print_hex(
				wire[codec.success_of(decoded).offset:codec.success_of(decoded).offset +
				codec.success_of(decoded).length],
			); fmt.println("", codec.success_of(decoded).consumed)
		} else if n == 5 && parts[0] == "SE" {
			// Fixed-width sequence values are checked individually; the adapter supplies bounded stack storage.
			width, width_ok := parse_width(parts[1])
			limit, limit_ok := parse_decimal(parts[2])
			capacity, cap_ok := parse_capacity(parts[3], len(output_storage))
			count: int
			values_ok := true
			if parts[4] != "-" {
				// Dash means no items; otherwise parse every comma-separated unsigned decimal value.
				numbers := parts[4]
				for number in strings.split_by_byte_iterator(&numbers, ',') {
					value, ok := parse_decimal(number)
					if !ok || count >= len(values) {values_ok = false; break} 	// Stop before an overflowing write.
					values[count] = codec.Fixed_Unsigned(value)
					count += 1
				}
			}
			if !width_ok ||
			   !limit_ok ||
			   !cap_ok ||
			   !values_ok {fmt.println("inputerror"); continue} 	// Keep syntax errors out of APIs.
			for &b in output_storage {b = 77} 	// Failed encodes must preserve all caller-owned storage.
			encoded := codec.encode_sequence(
				values[:count],
				width,
				codec.Element_Limit(limit),
				output_storage[:capacity],
			)
			if codec.error_of(encoded) != .None {
				// Late element range failures must not leave even the length prefix in output.
				for b in output_storage {assert(b == 77)}
				print_error(codec.error_of(encoded)); continue
			}
			print_hex(output_storage[:codec.success_of(encoded).written]); fmt.println()
		} else if n == 5 && parts[0] == "SD" {
			// The wire count limit and the caller's typed output capacity are intentionally separate.
			width, width_ok := parse_width(parts[1])
			limit, limit_ok := parse_decimal(parts[2])
			capacity, cap_ok := parse_capacity(parts[3], len(values))
			wire, hex_ok := parse_hex(parts[4], input_storage[:])
			if !width_ok || !limit_ok || !cap_ok || !hex_ok {fmt.println("inputerror"); continue} 	// Reject malformed request fields.
			for &item in values {item = codec.Fixed_Unsigned(999)} 	// Detect partial writes on every failure path.
			decoded := codec.decode_sequence(
				wire,
				width,
				codec.Element_Limit(limit),
				values[:capacity],
			)
			if codec.error_of(decoded) != .None {
				// All destinations must remain unchanged if the complete container was rejected.
				for item in values {assert(u64(item) == 999)}
				print_error(codec.error_of(decoded)); continue
			}
			if codec.success_of(decoded).count == 0 {fmt.print("-")} 	// An empty initialized prefix needs an explicit token.
			for i in 0 ..< codec.success_of(decoded).count {
				if i > 0 {fmt.print(",")} 	// Delimit each initialized value without including unused capacity.
				fmt.print(u64(values[i]))
			}
			fmt.println("", codec.success_of(decoded).consumed)
		} else {
			// Unknown commands or token counts must not select a production operation accidentally.
			fmt.println("inputerror")
		}
	}
}
