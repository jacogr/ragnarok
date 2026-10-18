# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Count storage must remain private even on a default result.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

import ../../../src/crypto/assurance_context
let parsed = default(AssuranceContextResult[VerifiedAssuranceCount])
discard parsed.completed
