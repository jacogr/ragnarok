package main
import codec "../../codec"
// Deliberately invalid: require explicit conversions to the fixed-value and width domain types.
main :: proc() {
	raw := u64(1)
	_ = codec.encode_fixed(raw, codec.Byte_Width(1))
}
