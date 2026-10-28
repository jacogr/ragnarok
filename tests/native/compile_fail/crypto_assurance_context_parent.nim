# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Intentional wrong-domain assignment must be rejected before runtime.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "nominal", "expected": "got: AssuranceAnchor but wanted: AssuranceParent"}

import ../../../src/crypto/primitives as crypto_primitives
import ../../../src/crypto/assurance_context as crypto_assurance_context
import ../../../src/codec/assurances as codec_assurances
let value: AssuranceParent = default(AssuranceAnchor)
discard value
