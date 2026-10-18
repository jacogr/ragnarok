# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot mutate retained set scalar storage.
import ../../../src/codec/[collections, natural]
var owner: OwnedSet[JamNatural]
discard owner.data
