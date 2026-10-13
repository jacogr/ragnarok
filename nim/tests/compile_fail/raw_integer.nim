## Deliberately invalid: proves a raw uint64 needs an explicit JamNatural conversion.
import ../../src/natural
let raw = 1'u64
discard encode(raw) # Must fail: raw uint64 is not a JamNatural.
