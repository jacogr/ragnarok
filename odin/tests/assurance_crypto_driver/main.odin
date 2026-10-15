// Independent named-field construction and ordinary provider verification for assurances context tests.
package main
import codec "../../codec"
import crypto "../../crypto"
import "core:encoding/hex"
import "core:fmt"
import "core:os"
import "core:strings"

// Parse trusted unsigned configuration without signs, coercion or arithmetic overflow.
unsigned :: proc(text: string) -> u64 {
	assert(len(text) > 0)
	value: u64
	// Prove each multiply/add before accepting the next decimal digit.
	for c in text {
		assert(c >= '0' && c <= '9')
		digit := u64(c - '0'); assert(value <= (max(u64) - digit) / 10)
		value = value * 10 + digit
	}
	return value
}

// Bounded lowercase tokens keep utility parsing separate from production crypto validation.
unhex :: proc(text: string, output: []u8) -> []u8 {
	// Dash preserves explicit empty key and record sequences.
	if text == "-" { return output[:0] }
	assert(len(text) % 2 == 0 && len(text) / 2 <= len(output))
	// Reject all alternate textual encodings before converting a complete byte span.
	for c in text { assert(c >= '0' && c <= '9' || c >= 'a' && c <= 'f') }
	value, ok := hex.decode_into_buffer(transmute([]u8)text, output); assert(ok)
	return value
}

// Render the entire owned message so the independent oracle can check every signed byte.
print_hex :: proc(data: []u8) {
	digits := "0123456789abcdef"
	// Transcripts always contain exactly 46 bytes, without truncation or hidden checksum substitution.
	for b in data { fmt.printf("%c%c", digits[b >> 4], digits[b & 15]) }
	fmt.println()
}

// Translate nominal enum names at the test boundary, preserving the common failure protocol.
print_error :: proc(error: crypto.Assurance_Context_Error) {
	text := strings.to_lower(fmt.aprintf("%v", error)); defer delete(text)
	// Odin underscores describe identifiers rather than the shared diagnostic token.
	for c in text {
		if c != '_' {
			// Keep every semantic character of the typed reason.
			fmt.printf("%c", c)
		}
	}
	fmt.println()
}

// Independently construct complete owned fields without using a candidate's wire decoder.
records :: proc(data: []u8, output: []codec.Assurance) -> []codec.Assurance {
	assert(len(data) % 141 == 0 && len(data) / 141 <= len(output))
	count := len(data) / 141
	// Full native bitset storage remains observable even outside the configured profile width.
	for i in 0 ..< count {
		start := i * 141
		// Anchor identity is independent of the externally supplied expected-parent domain.
		for j in 0 ..< 32 { output[i].anchor[j] = data[start + j] }
		// Do not mask invalid unused storage before the production check.
		for j in 0 ..< 43 { output[i].bits[j] = data[start + 32 + j] }
		output[i].validator = codec.Validator_Index(
			u16(data[start + 75]) | u16(data[start + 76]) << 8,
		)
		// Opaque signature imports preserve all original bytes.
		for j in 0 ..< 64 { output[i].signature[j] = data[start + 77 + j] }
	}
	return output[:count]
}

// Execute one frozen message or verification request and check borrowed input immutability.
request :: proc(p: []string) {
	default_message: crypto.Assurance_Message_Result
	default_verified: crypto.Assurance_Verify_Result
	assert(
		codec.error_of(default_message) == .Uninitialized &&
		codec.error_of(default_verified) == .Uninitialized,
	)
	storage: [150000]u8
	parent_bytes: [32]u8
	if p[0] == "M" {
		// Parent and bits are independently constructed typed values, not codec-decoded artifacts.
		assert(len(p) == 4)
		raw_parent := unhex(
			p[2],
			storage[:],
		); assert(len(raw_parent) == 32); copy(parent_bytes[:], raw_parent)
		raw_bits := unhex(p[3], storage[:]); assert(len(raw_bits) == 43)
		bits: codec.Assurance_Bits; copy(bits[:], raw_bits)
		saved := bits
		checked := crypto.assurance_message(
			crypto.Assurance_Parent(parent_bytes),
			bits,
			codec.Core_Count(unsigned(p[1])),
		)
		assert(bits == saved)
		if codec.error_of(checked) == .None {
			// Only a completed transcript can be rendered.
			message := cast([46]u8)codec.success_of(checked); print_hex(message[:])
		} else {
			// Failure carries no default transcript or partial progress.
			print_error(codec.error_of(checked))
		}
	} else {
		// Exact validator-key mapping is part of the caller-supplied verification context.
		assert(p[0] == "V" && len(p) == 6)
		config := codec.Assurance_Config {
			cores      = codec.Core_Count(unsigned(p[1])),
			validators = codec.Validator_Count(unsigned(p[2])),
		}
		raw_parent := unhex(
			p[3],
			storage[:],
		); assert(len(raw_parent) == 32); copy(parent_bytes[:], raw_parent)
		raw_keys := unhex(
			p[4],
			storage[:],
		); assert(len(raw_keys) % 32 == 0 && len(raw_keys) / 32 <= 1024)
		keys, saved_keys: [1024]crypto.Ed_Public_Key
		key_count := len(raw_keys) / 32
		// Import ordinary owned key encodings through the existing provider-neutral public API.
		for i in 0 ..< key_count {
			imported := crypto.import_public_key(
				raw_keys[i * 32:i * 32 + 32],
			); assert(crypto.error_of(imported) == .None)
			keys[i] = crypto.success_of(imported)
		}
		saved_keys = keys
		typed, saved: [1026]codec.Assurance
		values := records(unhex(p[5], storage[:]), typed[:]); saved = typed
		checked := crypto.verify_assurances(
			values,
			config,
			crypto.Assurance_Parent(parent_bytes),
			keys[:key_count],
		)
		assert(typed == saved && keys == saved_keys)
		if codec.error_of(checked) == .None {
			// Count certifies only the explicit stateless context and signatures.
			fmt.printf("ok %d\n", u64(codec.success_of(checked)))
		} else {
			// A failure alternative never supplies a partially verified count.
			print_error(codec.error_of(checked))
		}
	}
}

// Native batch processing keeps Python/OpenSSL fixture generation outside protocol execution.
main :: proc() {
	assert(len(os.args) == 2)
	data, error := os.read_entire_file(
		os.args[1],
		context.allocator,
	); assert(error == nil); defer delete(data)
	lines := string(data)
	// Iterate without allocating an unbounded collection of all input lines.
	for line in strings.split_lines_iterator(&lines) {
		// A final newline is not a production operation.
		if len(line) == 0 { continue }
		parts: [6]string
		count := 0; remaining := line
		// Keep trusted token storage bounded and fail visibly on protocol drift.
		for part in strings.split_by_byte_iterator(&remaining, ' ') {
			assert(count < len(parts)); parts[count] = part; count += 1
		}
		request(parts[:count])
	}
}
