# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Raw host counts cannot implicitly authorize a fixed collection cardinality.
import ../../../src/codec/[collections, natural]
var input: array[1, byte] = default(array[1, byte])
discard decodeSet[JamNatural](input, 1'u64, CollectionLimits())
