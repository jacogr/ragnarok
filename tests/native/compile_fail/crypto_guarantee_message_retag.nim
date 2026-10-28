# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A caller cannot turn a default failure into a signing credential.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "status"}

import ../../../src/crypto/primitives as crypto_primitives
import ../../../src/crypto/guarantee as crypto_guarantee
var parsed = default(GuaranteeMessageResult)
parsed.status = CryptoError.None
