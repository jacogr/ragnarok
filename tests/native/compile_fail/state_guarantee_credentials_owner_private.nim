# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot access private credential certification storage.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "data"}

import ../../../src/state/guarantee_credentials as state_guarantee_credentials
let owner = default(VerifiedGuaranteeCredentials)
discard owner.data # Must fail before native lowering.
