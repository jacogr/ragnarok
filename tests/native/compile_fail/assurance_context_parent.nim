# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Intentional wrong-domain assignment must be rejected before runtime.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "nominal", "expected": "got: AssuranceAnchor but wanted: AssuranceParent"}

import ../../../src/crypto/[primitives, assurance_context]
import ../../../src/codec/assurances
let value: AssuranceParent = default(AssuranceAnchor)
discard value
