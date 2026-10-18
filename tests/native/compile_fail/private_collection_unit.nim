# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## The physical zero-width storage unit is not part of the public scalar or wire schema.
import ../../../src/codec/collections
var value = default(CollectionBytes[0])
discard value.unit
