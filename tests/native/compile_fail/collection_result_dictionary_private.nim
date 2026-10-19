# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Callers cannot bypass private/read-only collection result state.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "completed"}

import ../../../src/codec/[collections, natural]
var value = default(CollectionResult[CollectionRead[OwnedDictionary[JamNatural, JamNatural]]])
discard value.completed
