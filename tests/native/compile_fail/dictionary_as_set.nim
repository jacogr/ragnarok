# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A dictionary owner cannot stand in for a set, even with identical scalar key types.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "nominal", "expected": "[1] expected: OwnedSet[T] but got: OwnedDictionary"}

import ../../../src/codec/[collections, natural]
var owner: OwnedDictionary[JamNatural, JamNatural] = default(OwnedDictionary[JamNatural, JamNatural])
discard setCount(owner)
