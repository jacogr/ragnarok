package main
import codec "../../codec"
// Deliberately invalid: require explicit conversions to the fixed-value and width domain types.
main :: proc() {
	raw := int(1)
	_ = codec.encode_fixed(codec.Fixed_Unsigned(1), raw)
}
