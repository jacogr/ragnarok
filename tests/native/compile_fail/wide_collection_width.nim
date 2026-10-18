# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Unsupported fixed scalar widths cannot instantiate a collection codec.
import ../../../src/codec/collections
var input: array[1, byte] = default(array[1, byte])
discard decodeVariableSet[CollectionUInt[9]](input, CollectionLimits())
