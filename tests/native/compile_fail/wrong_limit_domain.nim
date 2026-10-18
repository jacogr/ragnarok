# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Deliberately invalid: bounded limits and fixed-element values require their own domain types.
import ../../../src/codec/[bounded, fixed_unsigned]
let limit = ElementLimit(1)
discard decodeBytesBorrowed([], limit)
