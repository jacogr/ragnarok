package main
import codec "../../codec"
// Deliberately invalid: enforce nominal fields, union arguments and record-count resource types.
main :: proc() {
	value := u8(1)
	output: [1]u8
	_ = codec.encode_work(value, nil, codec.Byte_Limit(0), output[:])
}
