# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Mutable referenced fields have no approved collection scalar codec or ownership contract.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group":"schemas","expected":"string","rationale":"The collection decoder admits only closed canonical scalar codecs; admitting mutable heap-backed strings would bypass the fixed scalar encoding/ownership contract for retained canonical sets.","reference":"src/codec/collections.nim"}

import ../../../src/codec/collections
var input: array[1, byte] = default(array[1, byte])
discard decodeVariableSet[string](input, CollectionLimits())
