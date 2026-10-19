# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot mutate retained dictionary key/value storage.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "privacy", "expected": "data"}

import ../../../src/codec/[collections, natural]
var owner: OwnedDictionary[JamNatural, JamNatural]
discard owner.data
