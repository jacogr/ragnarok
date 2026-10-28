# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A signing transcript is not an Ed25519 signature.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "nominal", "expected": "got: GuaranteeMessage but wanted: EdSignature"}

import ../../../src/crypto/primitives as crypto_primitives
import ../../../src/crypto/guarantee as crypto_guarantee
let value: EdSignature = default(GuaranteeMessage)
discard value
