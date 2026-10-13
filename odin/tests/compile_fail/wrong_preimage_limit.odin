package main
import codec "../../codec"
// Deliberately invalid: enforce nominal fields, union arguments and record-count resource types.
main :: proc() {
	limit := codec.Byte_Limit(1)
	limits := codec.Preimage_Limits {
		items = limit,
	}
	_ = limits
}
