package main
import codec "../../codec"
// Private storage is not exported, so callers cannot reach mutable snapshot bytes through the owner.
main :: proc() {
	storage: codec.Owned_Storage
	storage.wire[0] = 7
}
