# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## The physical zero-width storage unit is not part of the public scalar or wire schema.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

import ../../../src/codec/collections
var value = default(CollectionBytes[0])
discard value.unit
