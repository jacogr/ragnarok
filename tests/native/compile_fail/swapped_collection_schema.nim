# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Equal logical numeric domains with different wire widths remain different owner schemas.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "nominal", "expected": "[1] expected: CollectionUInt but got: CollectionUInt"}

import ../../../src/codec/[collections, bounded]
var owner: OwnedSet[CollectionUInt[1]] = default(OwnedSet[CollectionUInt[1]])
var output: array[8, byte] = default(array[8, byte])
discard encodeOwnedVariableSet[CollectionUInt[2]](owner, CollectionLimits(), output)
