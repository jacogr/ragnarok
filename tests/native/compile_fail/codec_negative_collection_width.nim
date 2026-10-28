# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Unsupported fixed scalar widths cannot instantiate a collection codec.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "schemas", "expected": "CollectionUInt"}

import ../../../src/codec/collections as codec_collections
var input: array[1, byte] = default(array[1, byte])
discard decodeVariableSet[CollectionUInt[-1]](input, CollectionLimits())
