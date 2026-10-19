# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Mutable referenced fields have no approved collection scalar codec or ownership contract.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "schemas", "expected": "string"}

import ../../../src/codec/collections
var input: array[1, byte] = default(array[1, byte])
discard decodeVariableSet[string](input, CollectionLimits())
