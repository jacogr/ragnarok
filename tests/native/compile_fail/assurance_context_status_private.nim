# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Callers may inspect only the read-only error accessor.
import ../../../src/crypto/assurance_context
let parsed = default(AssuranceContextResult[VerifiedAssuranceCount])
discard parsed.status
