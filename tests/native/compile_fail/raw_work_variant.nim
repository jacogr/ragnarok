# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Deliberately invalid: service fields, work variants and record-count policies are nominal types.
import ../../../src/codec/[composite, bounded]
let value = 1'u8
var output = default(array[1, byte])
discard encodeWorkBorrowed(value, [], ByteLimit(0), output)
