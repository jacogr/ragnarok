# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Callers cannot bypass private/read-only collection result state.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "error"}

import ../../../src/codec/collections as codec_collections
import ../../../src/codec/natural as codec_natural
var value = default(CollectionResult[int])
value.error = CollectionError.None
