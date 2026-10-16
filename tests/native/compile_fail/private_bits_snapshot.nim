## External callers cannot mutate immutable private packed bytes.
import ../../../src/codec/bitstrings
var owner: OwnedBits
discard owner.data
