package main
import codec "../../codec"
// Deliberately invalid: enforce nominal fields, union arguments and record-count resource types.
main :: proc() {
	service := u32(1)
	record := codec.Preimage {
		service = service,
	}
	_ = record
}
