package main
import codec "../../codec"
// Deliberately invalid: reject raw/wrong-domain limits and raw u64 sequence elements.
main :: proc() {
	values := []u64{1}
	output: [10]u8
	_ = codec.encode_sequence(values, codec.Byte_Width(1), codec.Element_Limit(1), output[:])
}
