# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Assurance and guarantor identities require deliberate domain conversion.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "nominal", "expected": "got: ValidatorIndex but wanted: GuarantorIndex"}

import ../../../src/codec/[guarantees, assurances]
let wrong = GuaranteeCredential(validator: ValidatorIndex(1))
discard wrong
