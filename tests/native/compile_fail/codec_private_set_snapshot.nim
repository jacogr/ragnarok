# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot mutate retained set scalar storage.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "data"}

import ../../../src/codec/collections as codec_collections
import ../../../src/codec/natural as codec_natural
var owner: OwnedSet[JamNatural]
discard owner.data
