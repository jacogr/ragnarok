# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Only the read-only reason accessor exposes result status.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "status"}

import ../../../src/crypto/[primitives, guarantee]
let parsed = default(GuaranteeMessageResult)
discard parsed.status
