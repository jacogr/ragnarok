# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "captured"}

## Captured headers and refusal alternatives cannot be forged through raw fields.
import ../../../src/app/ancestor/inputs as ancestor_inputs
let owner = default(AncestorInputResult)
discard owner.captured
