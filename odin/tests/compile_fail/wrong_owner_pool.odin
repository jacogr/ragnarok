package main
import codec "../../codec"
// A same-sized unrelated pool cannot be paired with an owned payload extraction operation.
main :: proc() {
	frame: codec.Owned_Frame
	wrong_pool, output: [2]u8
	_ = codec.copy_owned_blob(frame, wrong_pool[:], 0, output[:])
}
