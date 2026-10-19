# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Callers may inspect only the read-only error accessor.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "privacy", "expected": "status"}

import ../../../src/crypto/assurance_context
let parsed = default(AssuranceContextResult[VerifiedAssuranceCount])
discard parsed.status
