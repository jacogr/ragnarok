# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## The public success accessor does not expose mutable result storage.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "privacy", "expected": "value"}

import ../../../src/crypto/assurance_context
var parsed = default(AssuranceContextResult[VerifiedAssuranceCount])
parsed.value = VerifiedAssuranceCount(1)
