# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Fixed signing bytes stay private on every result alternative.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "completed"}

import ../../../src/crypto/primitives as crypto_primitives
import ../../../src/crypto/guarantee as crypto_guarantee
let parsed = default(GuaranteeMessageResult)
discard parsed.completed
