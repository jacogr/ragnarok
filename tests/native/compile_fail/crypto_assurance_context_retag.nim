# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Callers cannot retag failed/default results as success.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "status"}

import ../../../src/crypto/assurance_context as crypto_assurance_context
var parsed = default(AssuranceContextResult[VerifiedAssuranceCount])
parsed.status = AssuranceContextError.None
