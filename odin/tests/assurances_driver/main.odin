// Independent trusted assurances adapter; production codecs use no test allocation or Python runtime.
package main
import codec "../../codec"
import "core:encoding/hex"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"

// Parse unsigned test fields without coercing signs or overflowing intermediate values.
unsigned :: proc(text: string) -> u64 {
	assert(len(text) > 0)
	value: u64
	// Prove each multiply/add before accepting its decimal digit.
	for c in text {
		assert(c >= '0' && c <= '9')
		digit := u64(c - '0')
		assert(value <= (max(u64) - digit) / 10)
		value = value * 10 + digit
	}
	return value
}

// Decode bounded lowercase test hex independently of the production wire decoder.
unhex :: proc(text: string, output: []u8) -> []u8 {
	// Dash keeps empty tokens explicit in the batch protocol.
	if text == "-" { return output[:0] }
	assert(len(text) % 2 == 0 && len(text) / 2 <= len(output))
	// Reject all alternate alphabets before handing the trusted token to the hex library.
	for c in text { assert(c >= '0' && c <= '9' || c >= 'a' && c <= 'f') }
	value, ok := hex.decode_into_buffer(transmute([]u8)text, output)
	assert(ok)
	return value
}

// Print all passed bytes in identity order, with a distinct token for an empty value.
print_hex :: proc(data: []u8) {
	// Empty logical sequences still occupy one field in the shared output protocol.
	if len(data) == 0 { fmt.print("-"); return }
	digits := "0123456789abcdef"
	// Emit every nibble rather than a checksum or a shortened preview.
	for b in data { fmt.printf("%c%c", digits[b >> 4], digits[b & 15]) }
}

// Translate only at the test boundary; production failure reasons remain a nominal enum.
print_error :: proc(error: codec.Assurance_Error) {
	text := strings.to_lower(fmt.aprintf("%v", error))
	defer delete(text)
	// Underscores reflect Odin identifiers, not shared wire-test diagnostic names.
	for c in text {
		if c != '_' {
			// Preserve every reason character except the language-specific identifier separator.
			fmt.printf("%c", c)
		}
	}
	fmt.println()
}

// Initialize every declared field so full failure atomicity is observable.
sentinel :: proc() -> codec.Assurance {
	value: codec.Assurance
	// All anchor bytes must survive failed output operations.
	for &b in value.anchor { b = 77 }
	// Padding outside the current profile is also caller-owned storage.
	for &b in value.bits { b = 77 }
	value.validator = 77
	// Signature bytes have an independent nominal identity domain.
	for &b in value.signature { b = 77 }
	return value
}

// Construct source records directly from logical fields, avoiding the new decoder as an oracle.
records :: proc(data: []u8, output: []codec.Assurance) -> []codec.Assurance {
	assert(len(data) % 141 == 0 && len(data) / 141 <= len(output))
	count := len(data) / 141
	// Logical input always exposes the entire 43-byte native bitset storage.
	for i in 0 ..< count {
		start := i * 141
		// Read the declared anchor bytes directly.
		for j in 0 ..< 32 { output[i].anchor[j] = data[start + j] }
		// Invalid unused octets intentionally reach encoder preflight.
		for j in 0 ..< 43 { output[i].bits[j] = data[start + 32 + j] }
		output[i].validator = codec.Validator_Index(
			u16(data[start + 75]) | u16(data[start + 76]) << 8,
		)
		// Preserve the declared opaque signature bytes.
		for j in 0 ..< 64 { output[i].signature[j] = data[start + 77 + j] }
	}
	return output[:count]
}

// Serialize actual named result fields for the independent Python oracle, including zero extension.
logical :: proc(values: []codec.Assurance, output: []u8) -> []u8 {
	assert(len(values) <= len(output) / 141)
	// Logical field order is independent of native struct padding and profile wire width.
	for value, i in values {
		start := i * 141
		// Inspect the declared anchor field.
		for j in 0 ..< 32 { output[start + j] = value.anchor[j] }
		// Inspect every native bitfield octet, including unused storage.
		for j in 0 ..< 43 { output[start + 32 + j] = value.bits[j] }
		output[start + 75] = u8(u16(value.validator) & 255)
		output[start + 76] = u8(u16(value.validator) >> 8)
		// Inspect the declared signature field.
		for j in 0 ..< 64 { output[start + 77 + j] = value.signature[j] }
	}
	return output[:len(values) * 141]
}

// Verify all sentinel bytes, including encoder storage past the written success extent.
unchanged :: proc(data: []u8) {
	// Any unexpected write violates the operation's atomic/capacity contract.
	for b in data { assert(b == 77) }
}

// Compare complete byte spans so alias tests also detect modifications of native padding.
equal :: proc(a, b: []u8) {
	assert(len(a) == len(b))
	// Compare every byte rather than relying on encoded checksums.
	for value, i in a { assert(value == b[i]) }
}

// Run one equivalent operation with independent field construction, sentinels and source erasure.
request :: proc(p: []string) {
	config := codec.Assurance_Config {
		cores      = codec.Core_Count(unsigned(p[1])),
		validators = codec.Validator_Count(unsigned(p[2])),
	}
	storage, saved, output, render: [150003]u8
	typed: [1027]codec.Assurance
	// Typed sentinels expose late failures and writes past successful output prefixes.
	for &value in typed { value = sentinel() }
	// Byte sentinels cover active capacity and the unused output suffix.
	for &b in output { b = 77 }
	if p[0] == "E" {
		// Independently constructed logical records must never pass through the new decoder first.
		data := unhex(p[4], storage[:])
		values := records(data, typed[:])
		cap := unsigned(p[3]); assert(cap <= 150000)
		encoded := codec.encode_assurances(values, config, output[:int(cap)])
		if codec.error_of(encoded) != .None {
			// A failure at the final source record must preserve the entire output allocation.
			unchanged(output[:]); print_error(codec.error_of(encoded))
		} else {
			// Success writes only its returned prefix.
			written := codec.success_of(encoded).written
			unchanged(output[written:]); print_hex(output[:written]); fmt.println()
		}
	} else if p[0] == "D" {
		// Capacity is a trusted adapter bound, independent of the production validator policy.
		data := unhex(p[4], storage[:]); copy(saved[:], data)
		cap := unsigned(p[3]); assert(cap <= 1024)
		decoded := codec.decode_assurances(data, config, typed[:int(cap)])
		if codec.error_of(decoded) != .None {
			// Inspect all records, including inactive destination storage, after any failure.
			for value in typed { assert(value == sentinel()) }
			print_error(codec.error_of(decoded))
		} else {
			// Erase original bytes before examining any owned decoded field.
			info := codec.success_of(decoded)
			for &b in data { b = 0 }
			// Unused caller elements must remain untouched on success.
			for value in typed[info.count:] { assert(value == sentinel()) }
			encoded := codec.encode_assurances(typed[:info.count], config, output[:info.consumed])
			assert(
				codec.error_of(encoded) == .None &&
				codec.success_of(encoded).written == info.consumed,
			)
			equal(output[:info.consumed], saved[:info.consumed])
			fmt.printf(
				"%d ",
				info.count,
			); print_hex(logical(typed[:info.count], render[:])); fmt.printf(" %d\n", info.consumed)
		}
	} else {
		// Explicit raw views manufacture illegal overlap only inside trusted tests.
		data := unhex(p[3], storage[:])
		count := 0
		if p[0] == "XE" {
			// Leave one extra aligned record for the encoded count prefix.
			count = len(records(data, typed[:]))
		} else {
			// An aligned typed allocation also backs the borrowed external wire image.
			assert(p[0] == "XD")
			count = len(data) / 99 + 2
		}
		raw := slice.bytes_from_ptr(raw_data(typed[:]), (count + 1) * size_of(codec.Assurance))
		if p[0] == "XD" {
			// Install the external bytes before taking the unchanged backing-store snapshot.
			copy(raw, data)
		}
		copy(saved[:], raw)
		if p[0] == "XE" {
			// Encoder must detect typed source metadata overlapping its byte destination.
			encoded := codec.encode_assurances(typed[:count], config, raw)
			assert(
				codec.error_of(encoded) == .Aliased_Buffers,
			); print_error(codec.error_of(encoded))
		} else {
			// Decoder must reject whole-input overlap before touching typed output.
			decoded := codec.decode_assurances(raw[:len(data)], config, typed[:count + 1])
			assert(
				codec.error_of(decoded) == .Aliased_Buffers,
			); print_error(codec.error_of(decoded))
		}
		equal(raw, saved[:len(raw)])
	}
}

// One native process reads the frozen shared corpus, with bounded per-request utility storage.
main :: proc() {
	assert(len(os.args) == 2)
	data, error := os.read_entire_file(os.args[1], context.allocator); assert(error == nil)
	defer delete(data)
	lines := string(data)
	// Iterate without allocating a separate collection of all request lines.
	for line in strings.split_lines_iterator(&lines) {
		// Ignore the final newline without inventing a codec request.
		if len(line) == 0 { continue }
		parts: [5]string
		count := 0; remaining := line
		// Keep token storage bounded and reject protocol drift.
		for part in strings.split_by_byte_iterator(&remaining, ' ') {
			assert(count < len(parts)); parts[count] = part; count += 1
		}
		assert(count == 4 || count == 5)
		request(parts[:count])
	}
}
