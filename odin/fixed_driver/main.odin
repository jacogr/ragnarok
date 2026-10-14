// Trusted local batch adapter: FE <width> <value> or FD <width> <hex bytes>.
package main
import codec "../codec"
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

// Print a stable codec error label; valid results are printed by the request handler instead.
print_error :: proc(error: codec.Fixed_Error) {
	switch error {
	case .Uninitialized:
		fmt.println("uninitialized") // An unvalidated result has no payload to print.
	// Invalid widths take precedence over short input or values that do not fit.
	case .Invalid_Width:
		fmt.println("invalidwidth")
	// The requested representation would discard significant value bits.
	case .Value_Out_Of_Range:
		fmt.println("outofrange")
	// The entire fixed-width field is not available.
	case .Truncated:
		fmt.println("truncated")
	// Calling this helper on success is an adapter error, not a native codec outcome.
	case .None:
		fmt.println("inputerror")
	}
}

// Load a trusted request file, borrow its lines and release its owned buffer at exit.
main :: proc() {
	// Require the single request-file argument before indexing it.
	if len(os.args) != 2 {os.exit(1)}
	data, err := os.read_entire_file(os.args[1], context.allocator)
	// A read failure prevents any requests from being processed.
	if err != nil {os.exit(1)}
	defer delete(data)
	lines := string(data)
	// Process each nonempty request with a single response for the harness.
	for line in strings.split_lines_iterator(&lines) {
		// A final newline does not represent a request.
		if len(line) == 0 {continue}
		remaining := line
		command, command_ok := strings.split_by_byte_iterator(&remaining, ' ')
		width_text, width_ok := strings.split_by_byte_iterator(&remaining, ' ')
		width, ok := parse_width(width_text)
		// Require both routing fields and a syntactically valid signed width before decoding payload text.
		if !command_ok || !width_ok || !ok {fmt.println("inputerror"); continue}
		// Checked decimal input feeds the fixed-width encoder rather than a narrowing cast.
		if command == "FE" {
			x, value_ok := parse_decimal(remaining)
			// Values above uint64 max and malformed decimal input cannot enter the native API.
			if !value_ok {fmt.println("inputerror"); continue}
			encoded := codec.encode_fixed(codec.Fixed_Unsigned(x), width)
			// Native codec errors are separate from request syntax errors.
			if codec.error_of(encoded) != .None {print_error(codec.error_of(encoded)); continue}
			digits := "0123456789abcdef"
			output: [16]u8
			// Convert only the used octets; zero-width output is a successful empty line.
			for i in 0 ..< codec.success_of(encoded).encoded.length {
				output[2 * i] = digits[codec.success_of(encoded).encoded.bytes[i] >> 4]
				output[2 * i + 1] = digits[codec.success_of(encoded).encoded.bytes[i] & 15]
			}
			fmt.println(string(output[:2 * codec.success_of(encoded).encoded.length]))
		} else if command == "FD" {
			// Decode a bounded hex payload into stack storage before borrowing it for the codec.
			bytes: [64]u8
			// Require whole byte pairs and reject payloads larger than the adapter's buffer.
			if len(remaining) % 2 != 0 ||
			   len(remaining) > 128 {fmt.println("inputerror"); continue}
			input, hex_ok := hex.decode_into_buffer(transmute([]u8)remaining, bytes[:])
			// Invalid hex is an adapter input error, not an incomplete binary field.
			if !hex_ok {fmt.println("inputerror"); continue}
			decoded := codec.decode_fixed(input, width)
			// A native failure has no value or consumed prefix to report.
			if codec.error_of(decoded) != .None {print_error(codec.error_of(decoded)); continue}
			fmt.println(u64(codec.success_of(decoded).value), codec.success_of(decoded).consumed)
		} else {
			// Unknown commands must not accidentally select either codec operation.
			fmt.println("inputerror")
		}
	}
}
