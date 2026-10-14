// Trusted test adapter; command arguments carry public fixtures, never production secret material.
package main
import primitives "../crypto"
import "core:encoding/hex"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:thread"

// Decode fixture hex into owned bytes; a dash represents an empty message.
bytes :: proc(text: string) -> []u8 {
	// Empty fixture messages need no allocation.
	if text == "-" {return nil}
	result := make([]u8, len(text) / 2)
	_, ok := hex.decode_into_buffer(transmute([]u8)text, result)
	assert(ok && len(text) % 2 == 0)
	return result
}
// Print only the completed fixed array; failures have no default payload to encode.
output :: proc(value: primitives.Crypto_Result($T)) {
	// Check the tagged result before selecting its array alternative.
	if primitives.error_of(value) != .None {fmt.println("error"); return}
	raw := primitives.success_of(value)
	encoded := hex.encode(raw[:])
	defer delete(encoded)
	fmt.println(string(encoded))
}
// Prove seed copying, alias invalidation and explicit allocator failure without touching released aliases.
ownership :: proc() {
	empty: primitives.Ed_Seed
	assert(primitives.error_of(primitives.public_key(empty)) == .Invalid_Seed)
	initial: primitives.Crypto_Result(primitives.Ed_Public_Key)
	assert(primitives.error_of(initial) == .Uninitialized)
	input: [32]u8
	loaded := primitives.import_seed(input[:])
	assert(primitives.error_of(loaded) == .None)
	seed := primitives.success_of(loaded)
	defer primitives.destroy_seed(&seed)
	before := primitives.success_of(primitives.public_key(seed))
	input[0] = 42
	assert(before == primitives.success_of(primitives.public_key(seed)))
	alias := seed
	sig := primitives.success_of(primitives.sign(alias, nil))
	assert(primitives.verify(before, sig, nil))
	primitives.clear_seed(seed)
	assert(primitives.error_of(primitives.public_key(alias)) == .Invalid_Seed)
	assert(primitives.error_of(primitives.sign(seed, nil)) == .Invalid_Seed)
	assert(
		primitives.error_of(primitives.import_seed(input[:], mem.nil_allocator())) ==
		.Allocation_Failure,
	)
	// Wrong widths fail without allocating a seed or constructing a public key.
	for n in ([]int{0, 1, 31, 33, 63, 65}) {
		wrong := make([]u8, n)
		assert(primitives.error_of(primitives.import_seed(wrong)) == .Invalid_Length)
		assert(primitives.error_of(primitives.import_public_key(wrong)) == .Invalid_Length)
		delete(wrong)
	}
	signature: [65]u8
	assert(primitives.error_of(primitives.import_signature(signature[:63])) == .Invalid_Length)
	assert(primitives.error_of(primitives.import_signature(signature[:])) == .Invalid_Length)
	primitives.clear_seed(empty)
	// Track repeated retained-key allocations and ensure destruction returns every byte to its owner.
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	defer mem.tracking_allocator_destroy(&tracker)
	// Each iteration releases exactly once and never reads an alias after free.
	for _ in 0 ..< 256 {
		item := primitives.import_seed(input[:], mem.tracking_allocator(&tracker))
		assert(primitives.error_of(item) == .None)
		owned := primitives.success_of(item)
		primitives.destroy_seed(&owned)
		assert(owned == nil && tracker.current_memory_allocated == 0)
	}
	fmt.println("ok")
}
// Exercise independent seed owners and stack hash contexts in one native process.
worker :: proc(t: ^thread.Thread) {
	input: [32]u8
	input[0] = u8(uintptr(t.data))
	loaded := primitives.import_seed(input[:])
	assert(primitives.error_of(loaded) == .None)
	seed := primitives.success_of(loaded)
	defer primitives.destroy_seed(&seed)
	public := primitives.success_of(primitives.public_key(seed))
	expected_blake := primitives.success_of(primitives.blake2b256(input[:]))
	expected_keccak := primitives.success_of(primitives.keccak256(input[:]))
	// All contexts/allocations are worker-local; no opaque owner crosses threads.
	for _ in 0 ..< 128 {
		sig := primitives.success_of(primitives.sign(seed, input[:]))
		assert(primitives.verify(public, sig, input[:]))
		assert(primitives.success_of(primitives.blake2b256(input[:])) == expected_blake)
		assert(primitives.success_of(primitives.keccak256(input[:])) == expected_keccak)
	}
}
// Wait for all workers before releasing thread handles.
concurrent :: proc() {
	threads: [4]^thread.Thread
	// Assign independent fixture identities before starting a worker.
	for i in 0 ..< 4 {
		threads[i] = thread.create(worker)
		assert(threads[i] != nil)
		threads[i].data = rawptr(uintptr(i))
		thread.start(threads[i])
	}
	// Joining establishes completion before releasing each OS thread handle.
	for t in threads {thread.join(t); thread.destroy(t)}
	fmt.println("ok")
}
// Handle one request with scoped input buffers and exactly one seed release owner.
main :: proc() {
	assert(len(os.args) >= 2)
	// Deliberately selecting a failed result must trap even in optimized builds.
	if os.args[1] == "F" {
		failed: primitives.Crypto_Result(primitives.Ed_Public_Key)
		fmt.println(primitives.success_of(failed))
		return
	}
	// The ownership probe needs no fixture arguments.
	if os.args[1] == "O" {ownership(); return}
	// Same-process workers test that no global mutable crypto context is used.
	if os.args[1] == "T" {concurrent(); return}
	assert(len(os.args) >= 3)
	input := bytes(os.args[2])
	defer delete(input)
	switch os.args[1] {
	// Each hash function borrows the message synchronously and returns owned fixed bytes.
	case "B":
		output(primitives.blake2b256(input))
	case "K":
		output(primitives.keccak256(input))
	// Size checking precedes any public-key/signature selection or cryptographic call.
	case "V":
		signature_bytes := bytes(os.args[3]); defer delete(signature_bytes)
		message := bytes(os.args[4]); defer delete(message)
		key := primitives.import_public_key(input)
		sig := primitives.import_signature(signature_bytes)
		if primitives.error_of(key) != .None ||
		   primitives.error_of(sig) != .None {fmt.println("error")} else {
			// Completed encodings produce a normal true/false verification verdict.
			fmt.println(
				int(
					primitives.verify(
						primitives.success_of(key),
						primitives.success_of(sig),
						message,
					),
				),
			)
		}
	// Seed import owns a private copy, released even after printing an error from derivation/signing.
	case "P", "S":
		loaded := primitives.import_seed(input)
		if primitives.error_of(loaded) != .None {fmt.println("error"); return} 	// No seed payload exists on failure.
		seed := primitives.success_of(loaded); defer primitives.destroy_seed(&seed)
		if os.args[1] == "P" {output(primitives.public_key(seed))} else {
			// Signing applies no codec, domain prefix or prehash to the fixture.
			message := bytes(os.args[3]); defer delete(message)
			output(primitives.sign(seed, message))
		}
	// Unknown commands identify a harness mistake.
	case:
		os.exit(1)
	}
}
