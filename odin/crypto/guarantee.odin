package ragnarok_crypto

// GP v0.7.1 guarantorsig message: ASCII $jam_guarantee followed by Blake2b-256(canonical report).
// Callers validate and serialize the complete report; this primitive composition does not authorize validators.
Guarantee_Message :: distinct [46]u8
// Hash exactly the supplied canonical report bytes; no timeslot or implicit prehash mode is appended.
guarantee_message :: proc(canonical_report: []u8) -> Crypto_Result(Guarantee_Message) {
	hashed := blake2b256(canonical_report)
	// A failed provider call exposes no all-zero or partial signing message.
	if error_of(hashed) != .None { return error_of(hashed) }
	message: Guarantee_Message
	domain := "$jam_guarantee"
	// The normative ASCII domain is copied literally, including the leading dollar sign.
	for i in 0 ..< len(domain) { message[i] = domain[i] }
	bytes := cast([32]u8)success_of(hashed)
	copy(message[14:], bytes[:])
	return message
}
