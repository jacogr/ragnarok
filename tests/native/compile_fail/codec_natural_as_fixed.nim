# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Deliberately invalid: a raw value/width or general natural is not the required fixed domain
## type.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "nominal", "expected": "[1] expected: FixedUnsigned but got: JamNatural", "early": ["encodeFixed(", "[1] expected: FixedUnsigned but got: JamNatural"]}

import ../../../src/codec/fixed_unsigned as codec_fixed_unsigned
import ../../../src/codec/natural as codec_natural
let value = JamNatural(1)
discard encodeFixed(value, ByteWidth(1))
