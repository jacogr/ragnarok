# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Rejected misuse: retained snapshot and result/variant state remain private.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "isPresent"}

import ../../../src/codec/owned as codec_owned
import ../../../src/codec/composite as codec_composite
var value = default(OwnedOptionalInfo)
value.isPresent = true
