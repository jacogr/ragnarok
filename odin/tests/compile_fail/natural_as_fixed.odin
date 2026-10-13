package main
import codec "../../codec"
// Deliberately invalid: require explicit conversions to the fixed-value and width domain types.
main :: proc() {
	value := codec.Natural(1)
	_ = codec.encode_fixed(value, codec.Byte_Width(1))
}
