package main
import codec "../../codec"
// This deliberately invalid program proves that a raw u64 cannot bypass the domain-type boundary.
main :: proc() {
	raw := u64(1)
	_ = codec.encode(raw) // Must fail: raw u64 is not a Natural.
}
