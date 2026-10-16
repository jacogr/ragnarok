## External callers cannot mutate immutable private packed bytes.
import ../../../src/bitstrings
var owner: OwnedBits
discard owner.data
