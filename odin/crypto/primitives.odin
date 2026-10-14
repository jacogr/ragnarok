// GP v0.7.1 Cryptography: raw-byte Blake2b-256, legacy Keccak-256 and ordinary RFC 8032 Ed25519.
package ragnarok_crypto

import corecrypto "core:crypto"
import "core:crypto/blake2b"
import "core:crypto/ed25519"
import "core:crypto/legacy/keccak"
import "core:mem"

// Nominal owned hash types prevent swapping Blake2b/Keccak results or signing keys accidentally.
Blake2b_Hash :: distinct [32]u8
// Legacy Keccak digest, distinct from SHA3-256 and Blake2b-256 despite the same width.
Keccak_Hash :: distinct [32]u8
// Owned encoded public bytes; importing the right size does not assert subgroup membership.
Ed_Public_Key :: distinct [32]u8
// Owned ordinary Ed25519 signature bytes; contextual/prehashed algorithms are separate contracts.
Ed_Signature :: distinct [64]u8
// Default outcomes fail; operation errors contain no usable key/signature/hash fields.
Crypto_Error :: enum {
	Uninitialized,
	None,
	Invalid_Length,
	Invalid_Seed,
	Allocation_Failure,
	Backend_Failure,
}
// Allocation-free checked result; select success before reading the completed value.
Crypto_Result :: union($T: typeid) #no_nil {
	Crypto_Error,
	T,
}
// Opaque retained seed owner: copies borrow the same storage; one owner destroys it exactly once.
Ed_Seed :: distinct rawptr
// Private seed and allocator state; public operations never expose mutable secret bytes or core key internals.
@(private = "file")
Seed_Storage :: struct {
	bytes:     [32]u8,
	alive:     bool,
	allocator: mem.Allocator,
}

// Return successful status only for the completed-data alternative, never for a fabricated empty error.
error_of :: proc(outcome: Crypto_Result($T)) -> Crypto_Error {
	switch value in outcome {
	case T:
		return .None // This branch alone carries completed data.
	case Crypto_Error:
		if value == .None {return .Uninitialized} 	// A reason-only alternative is not success.
		return value
	}
	unreachable() // The no-nil union exhausts both alternatives.
}
// Select completed data after checking status; a checked assertion traps on caller misuse rather than returning defaults.
success_of :: proc(outcome: Crypto_Result($T)) -> T {return outcome.(T)}

// Own a seed copy using the chosen allocator; its state must outlive the returned owner and all borrowed aliases.
import_seed :: proc(input: []u8, allocator := context.allocator) -> Crypto_Result(Ed_Seed) {
	// Exact RFC width is required, including when all bytes are zero.
	if len(input) != 32 {return Crypto_Error.Invalid_Length}
	storage, error := mem.new(Seed_Storage, allocator)
	// Allocators can refuse storage with either an error or a nil pointer.
	if error != .None || storage == nil {return Crypto_Error.Allocation_Failure}
	copy(storage.bytes[:], input)
	storage.alive = true
	storage.allocator = allocator
	return Ed_Seed(rawptr(storage))
}

// Erase retained seed bytes and invalidate all aliases without freeing the still-owned storage.
clear_seed :: proc(seed: Ed_Seed) {
	// A default owner has no secret allocation to clear.
	if seed == nil {return}
	storage := cast(^Seed_Storage)seed
	corecrypto.zero_explicit(&storage.bytes, size_of(storage.bytes))
	storage.alive = false
}

// Release exactly one seed owner through its original allocator and clear the passed handle; aliases must stop being used.
destroy_seed :: proc(seed: ^Ed_Seed) {
	// Clearing/releasing a nil owner again is harmless.
	if seed == nil || seed^ == nil {return}
	storage := cast(^Seed_Storage)seed^
	allocator := storage.allocator
	corecrypto.zero_explicit(storage, size_of(Seed_Storage))
	mem.free(storage, allocator)
	seed^ = nil
}

// Import fixed public-key bytes without exposing core's mutable internal group/validation fields.
import_public_key :: proc(input: []u8) -> Crypto_Result(Ed_Public_Key) {
	// Wrong widths have no usable success payload.
	if len(input) != 32 {return Crypto_Error.Invalid_Length}
	value: [32]u8
	copy(value[:], input)
	return Ed_Public_Key(value)
}
// Import exact signature bytes; cryptographic validity is decided separately by verification.
import_signature :: proc(input: []u8) -> Crypto_Result(Ed_Signature) {
	// No truncation or padding is permitted for external signature encodings.
	if len(input) != 64 {return Crypto_Error.Invalid_Length}
	value: [64]u8
	copy(value[:], input)
	return Ed_Signature(value)
}

// Hash raw bytes with a 32-byte Blake2b parameter rather than truncating a 64-byte digest.
blake2b256 :: proc(input: []u8) -> Crypto_Result(Blake2b_Hash) {
	ctx: blake2b.Context
	blake2b.init(&ctx, 32)
	blake2b.update(&ctx, input)
	output: [32]u8
	blake2b.final(&ctx, output[:])
	return Blake2b_Hash(output)
}
// Hash using legacy Keccak padding; callers perform any required JAM codec/domain composition themselves.
keccak256 :: proc(input: []u8) -> Crypto_Result(Keccak_Hash) {
	ctx: keccak.Context
	keccak.init_256(&ctx)
	keccak.update(&ctx, input)
	output: [32]u8
	keccak.final(&ctx, output[:])
	return Keccak_Hash(output)
}

// Derive public bytes from a live retained seed; expanded core key state is private and cleared before return.
public_key :: proc(seed: Ed_Seed) -> Crypto_Result(Ed_Public_Key) {
	// Default or cleared owners cannot silently become an initialized zero seed.
	if seed == nil {return Crypto_Error.Invalid_Seed}
	storage := cast(^Seed_Storage)seed
	// A cleared retained allocation is still owned, but no longer a signing identity.
	if !storage.alive {return Crypto_Error.Invalid_Seed}
	private: ed25519.Private_Key
	defer ed25519.private_key_clear(&private)
	// Construct fresh core key state from retained seed bytes rather than allowing callers to mutate its internals.
	if !ed25519.private_key_set_bytes(
		&private,
		storage.bytes[:],
	) {return Crypto_Error.Backend_Failure}
	output: [32]u8
	ed25519.private_key_public_bytes(&private, output[:])
	return Ed_Public_Key(output)
}

// Sign an exact raw message with ordinary deterministic Ed25519; no implicit prehash or domain is selected.
sign :: proc(seed: Ed_Seed, message: []u8) -> Crypto_Result(Ed_Signature) {
	// All seed state/width invariants are established before any core function with initialization assertions.
	if seed == nil {return Crypto_Error.Invalid_Seed}
	storage := cast(^Seed_Storage)seed
	// A cleared retained allocation is still owned, but no longer a signing identity.
	if !storage.alive {return Crypto_Error.Invalid_Seed}
	private: ed25519.Private_Key
	defer ed25519.private_key_clear(&private)
	if !ed25519.private_key_set_bytes(
		&private,
		storage.bytes[:],
	) {return Crypto_Error.Backend_Failure} 	// Failed key construction exposes no signature.
	output: [64]u8
	ed25519.sign(&private, message, output[:])
	return Ed_Signature(output)
}

// Verify with pinned Odin core's documented cofactored/canonical/non-small-order-public-key policy.
// This primitive verdict is not a claim that all provider edge-case policies coincide with JAM consensus.
verify :: proc(key: Ed_Public_Key, signature: Ed_Signature, message: []u8) -> bool {
	public: ed25519.Public_Key
	bytes := cast([32]u8)key
	// Decode invalid public encodings as a normal false verdict before signature processing.
	if !ed25519.public_key_set_bytes(&public, bytes[:]) {return false}
	signature_bytes := cast([64]u8)signature
	return ed25519.verify(&public, message, signature_bytes[:])
}
