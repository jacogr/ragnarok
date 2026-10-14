package main
import codec "../../codec"
// The result union has no decoded field; callers must select its success alternative.
main :: proc() {
	outcome := codec.decode_digest(nil, codec.Byte_Limit(1))
	_ = outcome.value
}
