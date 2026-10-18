# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Deliberately invalid: bounded limits and fixed-element values require their own domain types.
import ../../../src/codec/[bounded, fixed_unsigned]
let limit = 1'u64
discard decodeBytesBorrowed([], limit)
