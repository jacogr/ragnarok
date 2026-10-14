// Typed synchronous primitives for the pinned historical JAM research profile; no implicit domains/codec.
package bandersnatch_crypto

// The runner builds the same Rust library for both languages before compiling either adapter.
when ODIN_OS == .Darwin {
	foreign import bridge "../../build/bandersnatch/target/release/libragnarok_bandersnatch.dylib"
} else {
	// Linux uses the same maintained ABI and pinned Cargo closure.
	foreign import bridge "../../build/bandersnatch/target/release/libragnarok_bandersnatch.so"
}
foreign bridge {
	// Own exactly one validated canonical nonzero secret scalar in Rust.
	@(link_name = "bs_key_new")
	key_new :: proc "c" (data: rawptr, length: uintptr, out: ^rawptr) -> u32 ---
	// Release one Rust secret owner; its scalar is zeroized on drop.
	@(link_name = "bs_key_free")
	key_free :: proc "c" (handle: rawptr) ---
	// Derive a full public encoding from the owner.
	@(link_name = "bs_public")
	native_public :: proc "c" (handle: rawptr, out: rawptr) -> u32 ---
	// Produce exactly 96 signature bytes with separate context/additional inputs.
	@(link_name = "bs_sign")
	native_sign :: proc "c" (handle, data: rawptr, length: uintptr, ad: rawptr, ad_len: uintptr, out: rawptr) -> u32 ---
	// Return only verified output bytes after complete contextual-proof validation.
	@(link_name = "bs_verify")
	native_verify :: proc "c" (key, signature: rawptr, sig_len: uintptr, data: rawptr, length: uintptr, ad: rawptr, ad_len: uintptr, out: rawptr) -> u32 ---
	// Own immutable trusted-SRS parameters for a bounded capacity.
	@(link_name = "bs_setup_new")
	setup_new :: proc "c" (size: uintptr, out: ^rawptr) -> u32 ---
	// Release one original Rust parameter allocation.
	@(link_name = "bs_setup_free")
	setup_free :: proc "c" (handle: rawptr) ---
	// Commit ordered normalized encoded points into a complete 144-byte root.
	@(link_name = "bs_commit")
	native_commit :: proc "c" (handle, keys: rawptr, length: uintptr, out: rawptr) -> u32 ---
	// Prove only matching in-range membership, borrowing input buffers for this call.
	@(link_name = "bs_ring_sign")
	native_ring_sign :: proc "c" (handle, key: rawptr, index: uintptr, keys: rawptr, keys_len: uintptr, data: rawptr, length: uintptr, ad: rawptr, ad_len: uintptr, out: rawptr) -> u32 ---
	// Verify root/domain-bound RingVRF and return its verified output.
	@(link_name = "bs_ring_verify")
	native_ring_verify :: proc "c" (handle, root, signature: rawptr, sig_len: uintptr, data: rawptr, length: uintptr, ad: rawptr, ad_len: uintptr, out: rawptr) -> u32 ---
	// Check canonical subgroup encoding before native invalid-member substitution.
	@(link_name = "bs_validate_public")
	native_validate :: proc "c" (data: rawptr, length: uintptr) -> u32 ---
	// Export the historical suite's exact encoded padding point.
	@(link_name = "bs_padding")
	native_padding :: proc "c" (out: rawptr) -> u32 ---
}
// Nominal encoded public keys prevent mixing Ed25519 keys and output hashes.
Bs_Public_Key :: distinct [32]u8
// Historical output||c||s signature; not a Tiny/Thin proof.
Bs_Signature :: distinct [96]u8
// Complete output/Pedersen/membership proof, owning its fixed bytes.
Bs_Ring_Proof :: distinct [784]u8
// Compressed root whose domain/SRS relationship is supplied by an explicit setup owner.
Bs_Ring_Root :: distinct [144]u8
// Only successful verification yields this nominal truncated VRF output hash.
Bs_Output :: distinct [32]u8
// Typed reasons; default outcomes fail and errors contain no default proof/hash.
Bs_Error :: enum {
	Uninitialized,
	None,
	Invalid_Length,
	Invalid_Encoding,
	Invalid_Owner,
	Verification_Failure,
	Backend_Failure,
	Backend_Panic,
}
// Select the completed-data alternative only after a successful status check.
Bs_Result :: union($T: typeid) #no_nil {
	Bs_Error,
	T,
}
// Opaque Rust key owner; copies borrow one allocation and exactly one owner destroys it.
Bs_Key :: distinct rawptr
// Opaque immutable SRS/domain owner, freed through Rust's original allocator.
Bs_Setup :: distinct rawptr

// Normalize error-only alternatives so a fabricated .None error never becomes success.
error_of :: proc(result: Bs_Result($T)) -> Bs_Error {
	switch item in result {
	case T:
		return .None // Only completed data is success.
	case Bs_Error:
		// Default/error-only alternatives cannot expose a value.
		if item == .None {return .Uninitialized}
		return item
	}
	unreachable()
}
// Checked selection traps on programmer misuse even in the optimized tested build.
success_of :: proc(result: Bs_Result($T)) -> T {return result.(T)}
// Preserve explicit ABI errors; unknown native statuses are failures.
reason :: proc(code: u32) -> Bs_Error {
	switch code {
	case 0:
		return .None // Native output was committed successfully.
	case 1:
		return .Invalid_Length // Width/capacity/resource budget failure.
	case 2:
		return .Invalid_Encoding // Canonical/subgroup/profile validation failed.
	case 3:
		return .Invalid_Owner // Missing or released owner.
	case 4:
		return .Verification_Failure // Decoded proof failed verification.
	case 6:
		return .Backend_Panic // Rust caught an unwind internally.
	case:
		return .Backend_Failure // Includes unexpected future status codes.
	}
}
// Borrow a stable input address synchronously; nil is the empty-context representation.
data :: proc(input: []u8) -> rawptr {return raw_data(input)}
// Import exact canonical nonzero scalar bytes (not a seed), retained privately by Rust.
import_scalar :: proc(input: []u8) -> Bs_Result(Bs_Key) {
	owner: rawptr
	error := reason(key_new(data(input), uintptr(len(input)), &owner))
	// Failed validation/allocation setup cannot expose a default key.
	if error != .None {return error}
	return Bs_Key(owner)
}
// Validate bounded capacity before passing it to Rust's unsigned domain arithmetic.
new_setup :: proc(capacity: int) -> Bs_Result(Bs_Setup) {
	// Unsupported/negative capacities cannot wrap, truncate or silently change domains.
	if capacity < 1 || capacity > 1023 {return Bs_Error.Invalid_Length}
	owner: rawptr
	error := reason(setup_new(uintptr(capacity), &owner))
	// Failed native initialization has no owner payload.
	if error != .None {return error}
	return Bs_Setup(owner)
}
// Destroy one Rust key allocation and nil its release owner's handle; borrowed aliases must stop being used.
destroy_key :: proc(key: ^Bs_Key) {
	// Nil owners are harmless; a copied live alias is never independently released.
	if key == nil || key^ == nil {return}
	key_free(rawptr(key^)); key^ = nil
}
// Destroy one setup allocation; its original allocator/lifetime are entirely within Rust.
destroy_setup :: proc(setup: ^Bs_Setup) {
	// Absent owners contain no native allocation.
	if setup == nil || setup^ == nil {return}
	setup_free(rawptr(setup^)); setup^ = nil
}
// Import canonical prime-subgroup public bytes; verifier identity guards are assessed separately.
import_public_key :: proc(input: []u8) -> Bs_Result(Bs_Public_Key) {
	error := reason(native_validate(data(input), uintptr(len(input))))
	// Invalid encoding/width yields no typed public key.
	if error != .None {return error}
	output: [32]u8; copy(output[:], input)
	return Bs_Public_Key(output)
}
// Normalize an ordered ring in Odin; returned allocation is owned by this helper's caller allocator.
@(private = "file")
normalize_ring :: proc(input: []u8) -> Bs_Result([]u8) {
	// Complete bounded members are required before allocating copied storage.
	if len(input) == 0 ||
	   len(input) % 32 != 0 ||
	   len(input) > 1023 * 32 {return Bs_Error.Invalid_Length}
	padding: [32]u8
	error := reason(native_padding(&padding[0]))
	// A backend failure must never silently substitute zeros.
	if error != .None {return error}
	output, alloc_error := make([]u8, len(input))
	// Refused native-language storage has no array payload.
	if alloc_error != .None || output == nil {return Bs_Error.Backend_Failure}
	// Retain every valid point in order; invalid canonical/subgroup encodings become suite padding.
	for index := 0; index < len(input); index += 32 {
		status := reason(native_validate(&input[index], 32))
		// Only bad encodings become padding; native failure/panic is not invalid-member policy.
		if status != .None && status != .Invalid_Encoding {delete(output); return status}
		valid := status == .None
		// Copy the full member rather than truncating or modifying the original buffer.
		for i in 0 ..< 32 {
			// Canonical points remain unchanged, including identities that the separate adapter guard rejects.
			if valid {output[index + i] = input[index + i]} else {
				// An invalid encoding has no usable subgroup point; substitute the exact suite padding.
				output[index + i] = padding[i]
			}
		}
	}
	return output
}

// Derive owned public bytes from a live Rust scalar owner.
public_key :: proc(key: Bs_Key) -> Bs_Result(Bs_Public_Key) {
	output: [32]u8
	error := reason(native_public(rawptr(key), &output[0]))
	// Failed operations return a reason-only alternative, never default scratch bytes.
	if error != .None {return error}
	return Bs_Public_Key(output)
}

// Sign raw context and additional data separately into a complete historical signature.
sign :: proc(key: Bs_Key, context_bytes, additional: []u8) -> Bs_Result(Bs_Signature) {
	output: [96]u8
	error := reason(
		native_sign(
			rawptr(key),
			data(context_bytes),
			uintptr(len(context_bytes)),
			data(additional),
			uintptr(len(additional)),
			&output[0],
		),
	)
	// Failed operations return a reason-only alternative, never default scratch bytes.
	if error != .None {return error}
	return Bs_Signature(output)
}

// Verify a complete typed contextual proof and return only the successful verified output.
verify :: proc(
	key: Bs_Public_Key,
	signature: Bs_Signature,
	context_bytes, additional: []u8,
) -> Bs_Result(Bs_Output) {
	public := cast([32]u8)key; proof := cast([96]u8)signature
	output: [32]u8
	error := reason(
		native_verify(
			&public[0],
			&proof[0],
			96,
			data(context_bytes),
			uintptr(len(context_bytes)),
			data(additional),
			uintptr(len(additional)),
			&output[0],
		),
	)
	// Failed operations return a reason-only alternative, never default scratch bytes.
	if error != .None {return error}
	return Bs_Output(output)
}

// Normalize invalid member encodings in Odin and commit with the explicit SRS/domain.
commit_ring :: proc(setup: Bs_Setup, members: []u8) -> Bs_Result(Bs_Ring_Root) {
	loaded := normalize_ring(members)
	// Select normalized bytes only after size/encoding policy succeeds.
	if error_of(loaded) != .None {return error_of(loaded)}
	normalized := success_of(loaded); defer delete(normalized)
	output: [144]u8
	error := reason(
		native_commit(rawptr(setup), data(normalized), uintptr(len(normalized)), &output[0]),
	)
	// Failed operations return a reason-only alternative, never default scratch bytes.
	if error != .None {return error}
	return Bs_Ring_Root(output)
}

// Prove membership for an in-range matching secret/index; borrow all input slices synchronously.
sign_ring :: proc(
	setup: Bs_Setup,
	key: Bs_Key,
	index: int,
	members, context_bytes, additional: []u8,
) -> Bs_Result(Bs_Ring_Proof) {
	loaded := normalize_ring(members)
	// Select normalized bytes only after size/encoding policy succeeds.
	if error_of(loaded) != .None {return error_of(loaded)}
	normalized := success_of(loaded); defer delete(normalized)
	// Reject negative positions before conversion to unsigned native size.
	if index < 0 {return Bs_Error.Invalid_Length}
	output: [784]u8
	error := reason(
		native_ring_sign(
			rawptr(setup),
			rawptr(key),
			uintptr(index),
			data(normalized),
			uintptr(len(normalized)),
			data(context_bytes),
			uintptr(len(context_bytes)),
			data(additional),
			uintptr(len(additional)),
			&output[0],
		),
	)
	// Failed operations return a reason-only alternative, never default scratch bytes.
	if error != .None {return error}
	return Bs_Ring_Proof(output)
}

// Verify a root-bound ring proof under this SRS/domain and expose only the verified output hash.
verify_ring :: proc(
	setup: Bs_Setup,
	root: Bs_Ring_Root,
	signature: Bs_Ring_Proof,
	context_bytes, additional: []u8,
) -> Bs_Result(Bs_Output) {
	commitment := cast([144]u8)root; proof := cast([784]u8)signature
	output: [32]u8
	error := reason(
		native_ring_verify(
			rawptr(setup),
			&commitment[0],
			&proof[0],
			784,
			data(context_bytes),
			uintptr(len(context_bytes)),
			data(additional),
			uintptr(len(additional)),
			&output[0],
		),
	)
	// Failed operations return a reason-only alternative, never default scratch bytes.
	if error != .None {return error}
	return Bs_Output(output)
}

// Own a complete fixed encoding; cryptographic validity is checked during verification.
import_signature :: proc(input: []u8) -> Bs_Result(Bs_Signature) {
	// Wrong widths have no typed payload and never discard trailing bytes.
	if len(input) != 96 {return Bs_Error.Invalid_Length}
	output: [96]u8; copy(output[:], input)
	return Bs_Signature(output)
}

// Own a complete fixed encoding; cryptographic validity is checked during verification.
import_ring_proof :: proc(input: []u8) -> Bs_Result(Bs_Ring_Proof) {
	// Wrong widths have no typed payload and never discard trailing bytes.
	if len(input) != 784 {return Bs_Error.Invalid_Length}
	output: [784]u8; copy(output[:], input)
	return Bs_Ring_Proof(output)
}

// Own a complete fixed encoding; cryptographic validity is checked during verification.
import_ring_root :: proc(input: []u8) -> Bs_Result(Bs_Ring_Root) {
	// Wrong widths have no typed payload and never discard trailing bytes.
	if len(input) != 144 {return Bs_Error.Invalid_Length}
	output: [144]u8; copy(output[:], input)
	return Bs_Ring_Root(output)
}
