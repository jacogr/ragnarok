# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Callers cannot bypass private/read-only Boolean and bitstring result state.
import ../../../src/codec/bitstrings
var value = default(BitResult[BooleanRead])
discard value.completed
