package main
import codec "../../codec"
// Deliberately invalid: reject raw/wrong-domain limits and raw u64 sequence elements.
main :: proc() {
	limit := u64(1)
	_ = codec.decode_bytes(nil, limit)
}
