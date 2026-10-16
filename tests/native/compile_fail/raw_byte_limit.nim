## Deliberately invalid: bounded limits and fixed-element values require their own domain types.
import ../../../src/codec/[bounded, fixed_unsigned]
let limit = 1'u64
discard decodeBytesBorrowed([], limit)
