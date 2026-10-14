## Deliberately invalid: bounded limits and fixed-element values require their own domain types.
import ../../src/[bounded, fixed_unsigned]
let limit = ElementLimit(1)
discard decodeBytesBorrowed([], limit)
