# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Mutable referenced fields have no approved collection scalar codec or ownership contract.
import ../../../src/codec/collections
var input: array[1, byte] = default(array[1, byte])
discard decodeVariableSet[string](input, CollectionLimits())
