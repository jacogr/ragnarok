# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot mutate retained dictionary key/value storage.
import ../../../src/codec/[collections, natural]
var owner: OwnedDictionary[JamNatural, JamNatural]
discard owner.data
