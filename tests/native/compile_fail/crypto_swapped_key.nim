# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Equal widths never make distinct cryptographic domains interchangeable.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "nominal", "expected": "got: EdSignature but wanted: EdPublicKey"}

import ../../../src/crypto/primitives
let value: EdPublicKey = default(EdSignature)
discard value
