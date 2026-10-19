# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot access private credential certification storage.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "privacy", "expected": "structureReason"}

import ../../../src/state/guarantee_credentials
let owner = default(GuaranteeCredentialResult[VerifiedGuaranteeCredentials])
discard owner.structureReason # Must fail before native lowering.
