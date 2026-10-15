package ragnarok_crypto
import codec "../codec"

// Expected parent cannot be confused implicitly with a record anchor or computed Blake2b digest.
Assurance_Parent :: distinct [32]u8
// Exactly the normative ASCII domain plus digest; this is neither a signature nor a raw hash.
Assurance_Signing_Message :: distinct [46]u8
// Completed context verification count does not certify state transition or report availability.
Verified_Assurance_Count :: distinct u64
// Context, structural and cryptographic failures retain separate reasons; default initialization fails.
Assurance_Context_Error :: enum {
	Uninitialized,
	None,
	Invalid_Config,
	Invalid_Key_Set,
	Limit_Exceeded,
	Invalid_Validator,
	Non_Canonical,
	Wrong_Parent,
	Invalid_Signature,
	Backend_Failure,
}
// Only success contains a complete owned transcript; failure contains its reason alone.
Assurance_Message_Result :: codec.Codec_Result(Assurance_Signing_Message, Assurance_Context_Error)
// Only success contains a verified count; default and failed results have no count field.
Assurance_Verify_Result :: codec.Codec_Result(Verified_Assurance_Count, Assurance_Context_Error)

// Validate complete native bit storage before hashing; callers have already checked the core count.
assurance_bits_canonical :: proc(bits: codec.Assurance_Bits, cores: codec.Core_Count) -> bool {
	width := (int(cores) + 7) / 8
	remainder := int(cores) % 8
	// High bits in a partial final octet refer to nonexistent cores.
	if remainder != 0 && int(bits[width - 1]) >> uint(remainder) != 0 { return false }
	// Do not silently omit nonzero caller data outside the selected profile.
	for i in width ..< 43 {
		// Unused native bytes must be zero even though they do not appear on the wire.
		if bits[i] != 0 { return false }
	}
	return true
}

// Build an owned $jam_available transcript, using fixed fields without an implicit length prefix.
assurance_message :: proc(
	parent: Assurance_Parent,
	bits: codec.Assurance_Bits,
	cores: codec.Core_Count,
) -> Assurance_Message_Result {
	// Validate unsigned configuration before host conversion or final-octet indexing.
	if cores < 1 || cores > 341 { return Assurance_Context_Error.Invalid_Config }
	// Noncanonical storage cannot produce a misleading credential over a silently reduced value.
	if !assurance_bits_canonical(bits, cores) { return Assurance_Context_Error.Non_Canonical }
	width := (int(cores) + 7) / 8
	transcript: [75]u8
	// Parent bytes precede the bitfield in identity order, with no discriminator.
	for i in 0 ..< 32 { transcript[i] = parent[i] }
	// Hash only actual profile bytes, never the unused native storage suffix.
	for i in 0 ..< width { transcript[32 + i] = bits[i] }
	hashed := blake2b256(transcript[:32 + width])
	// Backend failure cannot fabricate an all-zero or partial transcript.
	if error_of(hashed) != .None { return Assurance_Context_Error.Backend_Failure }
	message: Assurance_Signing_Message
	domain := "$jam_available"
	// The leading dollar sign is signed; no terminator or secondary prehash is added.
	for i in 0 ..< len(domain) { message[i] = domain[i] }
	digest := cast([32]u8)success_of(hashed)
	copy(message[14:], digest[:])
	return message
}

// Verify stable borrowed records against an exact caller-supplied validator-key table and parent.
verify_assurances :: proc(
	values: []codec.Assurance,
	config: codec.Assurance_Config,
	parent: Assurance_Parent,
	keys: []Ed_Public_Key,
) -> Assurance_Verify_Result {
	// The existing codec's profile predicate proves every following conversion and resource bound.
	if !codec.assurance_config_valid(config) { return Assurance_Context_Error.Invalid_Config }
	// Public keys are indexed by validator identity, not by position in this record batch.
	if u64(len(keys)) != u64(config.validators) { return Assurance_Context_Error.Invalid_Key_Set }
	// Protocol count bounds also cap all subsequent loops without input-driven allocation.
	if u64(len(values)) > u64(config.validators) { return Assurance_Context_Error.Limit_Exceeded }
	previous := -1
	expected := cast([32]u8)parent
	// Complete structural and parent checks before an early rejected signature can hide a late context error.
	for value in values {
		// Fixed E2 width alone does not establish validator membership in this profile.
		if u64(value.validator) >=
		   u64(config.validators) { return Assurance_Context_Error.Invalid_Validator }
		// Strict order enforces one assurance per validator.
		if int(value.validator) <= previous { return Assurance_Context_Error.Non_Canonical }
		// Native caller construction cannot bypass wire canonicality requirements.
		if !assurance_bits_canonical(
			value.bits,
			config.cores,
		) { return Assurance_Context_Error.Non_Canonical }
		// Each record binds to the externally supplied expected block parent.
		if cast([32]u8)value.anchor != expected { return Assurance_Context_Error.Wrong_Parent }
		previous = int(value.validator)
	}
	// Ordinary provider verification begins only after the complete context is valid.
	for value in values {
		message := assurance_message(parent, value.bits, config.cores)
		signature_bytes := value.signature
		signature := import_signature(signature_bytes[:])
		// Any unexpected hash/import failure remains a typed backend failure without fallback.
		if codec.error_of(message) != .None ||
		   error_of(signature) != .None { return Assurance_Context_Error.Backend_Failure }
		message_bytes := cast([46]u8)codec.success_of(message)
		// Preserve the existing provider's ordinary verdict and documented exceptional-point policy.
		if !verify(keys[int(value.validator)], success_of(signature), message_bytes[:]) {
			return Assurance_Context_Error.Invalid_Signature
		}
	}
	return Verified_Assurance_Count(len(values))
}
