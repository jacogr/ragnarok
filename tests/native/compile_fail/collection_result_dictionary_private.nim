# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Callers cannot bypass private/read-only collection result state.
import ../../../src/codec/[collections, natural]
var value = default(CollectionResult[CollectionRead[OwnedDictionary[JamNatural, JamNatural]]])
discard value.completed
