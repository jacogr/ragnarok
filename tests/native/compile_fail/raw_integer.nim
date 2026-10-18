# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Deliberately invalid: proves a raw uint64 needs an explicit JamNatural conversion.
import ../../../src/codec/natural
let raw = 1'u64
discard encode(raw) # Must fail: raw uint64 is not a JamNatural.
