// Batch test/fuzz adapter. Request file is trusted local harness input.
package main
import codec "../codec"
import "core:encoding/hex"
import "core:fmt"
import "core:os"
import "core:strings"

// Parse an unsigned decimal value with explicit overflow checks before arithmetic.
parse_decimal :: proc(text: string) -> (u64, bool) {
	// Reject an empty number rather than treating it as zero.
	if len(text) == 0 {return 0, false}
	x: u64
	// Accumulate the value one decimal digit at a time.
	for c in text {
		// Accept digits only; signs and other parser conveniences are outside the adapter protocol.
		if c < '0' || c > '9' {return 0, false}
		digit := u64(c - '0')
		// Ensure multiplying by ten and adding this digit cannot exceed uint64 max.
		if x > (max(u64) - digit) / 10 {return 0, false}
		x = x * 10 + digit
	}
	return x, true
}

// Run a trusted local batch of encode/decode requests, producing one response per nonempty line.
main :: proc() {
	// Require exactly one request-file path before accessing the argument.
	if len(os.args) != 2 {os.exit(1)}
	data, err := os.read_entire_file(os.args[1], context.allocator)
	// Abort when the file cannot be read; no batch requests are available to process.
	if err != nil {os.exit(1)}
	defer delete(data)
	lines := string(data)
	// Borrow lines from the loaded file; the deferred delete releases the owned file buffer at exit.
	for line in strings.split_lines_iterator(&lines) {
		// Skip blank lines, including the trailing newline at the end of a request file.
		if len(line) == 0 {continue}
		// Convert a checked decimal value into the distinct natural type, then encode it.
		if strings.has_prefix(line, "E ") {
			x, ok := parse_decimal(line[2:])
			// Reject malformed adapter input and continue with the next request.
			if !ok {fmt.println("inputerror"); continue}
			encoded := codec.encode(codec.Natural(x))
			digits := "0123456789abcdef"
			output: [18]u8
			// Convert each encoded byte into two lowercase hex digits without allocating an output string.
			for i in 0 ..< encoded.length {
				output[2 * i] = digits[encoded.bytes[i] >> 4]
				output[2 * i + 1] = digits[encoded.bytes[i] & 15]
			}
			fmt.println(string(output[:2 * encoded.length]))
		} else if strings.has_prefix(line, "D ") {
			// Decode a bounded hex request and report its value, consumed size or typed error.
			text := line[2:]
			bytes: [64]u8
			// Require whole byte pairs and cap the request to the fixed 64-byte adapter buffer.
			if len(text) % 2 != 0 || len(text) > 128 {
				fmt.println("inputerror"); continue
			}
			input, ok := hex.decode_into_buffer(transmute([]u8)text, bytes[:])
			// Reject malformed adapter input and continue with the next request.
			if !ok {fmt.println("inputerror"); continue}
			decoded := codec.decode(input)
			// Translate the typed decoder outcome into the stable text protocol expected by the harness.
			switch decoded.error {
			// Success reports both the value and its consumed prefix length.
			case .None:
				fmt.println(u64(decoded.value), decoded.consumed)
			// The header or its announced payload is incomplete.
			case .Truncated:
				fmt.println("truncated")
			// The representation uses more bytes than the value requires.
			case .Non_Canonical:
				fmt.println("noncanonical")
			}
			// Reject unrecognized commands so the harness can distinguish adapter errors from codec errors.
		} else {fmt.println("inputerror")}
	}
}
