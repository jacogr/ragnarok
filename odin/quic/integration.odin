// CE 143 test preimages are full C.2 digests; all codec/crypto policy remains in native Odin.
package main
import codec "../codec"
import crypto "../crypto"
import "core:fmt"
import "core:mem"
import "core:os"

INTEGRATION :: #config(INTEGRATION, false)
INTEGRATION_WIRE_CAP :: 1024 * 1024 + 256
// Nominal query key prevents accidentally treating a digest field as the preimage's computed Blake2b key.
Preimage_Key :: distinct [32]u8
// Reason-only failures contain no snapshot, serialization or consumed count; zero initialization fails.
Integration_Error :: enum {
	Uninitialized,
	None,
	Codec,
	Trailing,
	Hash_Mismatch,
	Owner,
	Crypto,
}
// One release owner retains the immutable codec snapshot; wire is separate caller-owned serialization storage.
Verified_Digest :: struct {
	owner: codec.Owned_Frame,
	wire:  []u8,
}
// Check the data alternative before accessing either owned resource.
Integration_Result :: union #no_nil {
	Integration_Error,
	Verified_Digest,
}
// Eight trusted public fixtures, owned by the peer until callbacks and native destruction have finished.
Integration_Bank :: struct {
	wires: [8][]u8,
	keys:  [8]Preimage_Key,
}

// Release bank storage once, after all stream owners have retired; borrowed aliases cannot outlive Peer.
destroy_bank :: proc(bank: ^Integration_Bank) {
	for &wire in bank.wires { delete(wire); wire = nil } 	// Every fixture allocation has one release owner.
}

// Load bounded public fixtures before callback registration; network requests cannot choose a path.
load_bank :: proc(bank: ^Integration_Bank, directory: string) -> bool {
	if len(directory) == 0 { return false } 	// Empty controls cannot silently select the current directory.
	for index in 0 ..< 8 {
		path := fmt.aprintf("%s/%d.bin", directory, index)
		data, err := os.read_entire_file(path, context.allocator)
		delete(path)
		// These are trusted harness files; reject their size before retaining data in the fixture bank.
		if err != nil ||
		   len(data) < 1 ||
		   len(data) > INTEGRATION_WIRE_CAP { delete(data); return false }
		bank.wires[index] = data
		digest := crypto.blake2b256(data)
		if crypto.error_of(digest) != .None { return false } 	// No fabricated key after backend failure.
		bank.keys[index] = Preimage_Key(crypto.success_of(digest))
	}
	return true
}

// Exact lookup returns minus one on a miss; callers check before indexing a trusted fixture.
find_fixture :: proc(bank: ^Integration_Bank, key: []u8) -> int {
	if len(key) != 32 { return -1 } 	// No narrowing or padding of malformed query keys.
	for expected, index in bank.keys {
		matches := true
		for value, i in expected { if key[i] != value { matches = false; break } } 	// Compare the whole key.
		if matches { return index } 	// Only exact content names select database fixtures.
	}
	return -1
}

// Own a standalone digest, overwrite borrowed source bytes, then serialize/hash through that immutable owner.
// On success the caller owns both returned allocations; every failure destroys all temporary resources.
capture_digest :: proc(input: []u8, expected: Preimage_Key) -> Integration_Result {
	parsed := codec.decode_owned_digest(input, codec.Byte_Limit(1024 * 1024))
	if codec.error_of(parsed) != .None { return Integration_Error.Codec } 	// Malformed wire has no snapshot.
	owner := codec.success_of(parsed)
	wire: []u8
	committed := false
	defer {
		if !committed { codec.destroy_owned(&owner); delete(wire) } 	// Late guards/backend failure retain nothing.
	}
	info := codec.owned_info(owner)
	if codec.error_of(info) != .None { return Integration_Error.Owner } 	// Missing owner has no consumed metadata.
	if codec.success_of(info).consumed != len(input) { return Integration_Error.Trailing } 	// Reject concatenated/trailing frames.
	for &value in input { value = 0xa5 } 	// Reuse receive storage before the later crypto operation.
	allocation_error: mem.Allocator_Error
	wire, allocation_error = make([]u8, len(input))
	if allocation_error != .None || raw_data(wire) == nil { return Integration_Error.Owner } 	// Temporary serialization failure retires the already captured snapshot.
	encoded := codec.encode_owned(owner, wire)
	if codec.error_of(encoded) != .None ||
	   codec.success_of(encoded) != len(wire) { return Integration_Error.Owner } 	// No partial serialization.
	digest := crypto.blake2b256(wire)
	if crypto.error_of(digest) != .None { return Integration_Error.Crypto } 	// Backend failure contains no usable hash.
	if Preimage_Key(crypto.success_of(digest)) !=
	   expected { return Integration_Error.Hash_Mismatch } 	// Bind the preimage to the CE request.
	committed = true
	return Verified_Digest{owner, wire}
}

// Fuzz the composition boundary with actual query hashes; each outcome releases its own application storage.
integration_self_test :: proc() {
	assert(INTEGRATION) // Ordinary binaries cannot claim linked integration coverage.
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	context.allocator = mem.tracking_allocator(&tracking)
	default_result: Integration_Result
	assert(default_result.(Integration_Error) == .Uninitialized)
	random := u64(0x494e544547524154)
	for iteration in 0 ..< 10000 {
		input: [128]u8
		for &value in input { random ~= random << 13; random ~= random >> 7; random ~= random << 17; value = u8(random & 255) } 	// Reproducible malformed bytes, not secret randomness.
		original := input
		length := iteration % 129
		hash := crypto.blake2b256(input[:length])
		assert(crypto.error_of(hash) == .None)
		checked := capture_digest(input[:length], Preimage_Key(crypto.success_of(hash)))
		switch value in checked {
		case Integration_Error:
			assert(value == .Codec || value == .Trailing) // The true query hash excludes a spurious mismatch error.
		case Verified_Digest:
			owner := value.owner
			for byte, i in value.wire { assert(byte == original[i]) } 	// Later serialization must retain the pre-mutation bytes.
			codec.destroy_owned(&owner)
			delete(value.wire)
		}
		assert(tracking.current_memory_allocated == 0) // Neither success nor a late failure retains an application owner.
	}
	fmt.println("Odin integration selftest: 10000 arbitrary digest captures passed")
}
