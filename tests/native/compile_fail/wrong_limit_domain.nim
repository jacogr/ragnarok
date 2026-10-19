# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Deliberately invalid: bounded limits and fixed-element values require their own domain types.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "nominal", "expected": "[2] expected: ByteLimit but got: ElementLimit", "early": ["decodeBytesBorrowed(", "[2] expected: ByteLimit but got: ElementLimit"]}

import ../../../src/codec/[bounded, fixed_unsigned]
let limit = ElementLimit(1)
discard decodeBytesBorrowed([], limit)
