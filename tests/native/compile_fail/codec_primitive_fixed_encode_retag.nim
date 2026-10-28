# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Rejected misuse: primitive result state is private and exposed only through read-only
## accessors.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "success"}

import ../../../src/codec/natural as codec_natural
import ../../../src/codec/fixed_unsigned as codec_fixed_unsigned
var value = default(FixedEncodeResult)
value.success = true
