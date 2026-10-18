# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Public failure reasons are read-only.
import ../../../src/crypto/assurance_context
var parsed = default(AssuranceContextResult[VerifiedAssuranceCount])
parsed.error = AssuranceContextError.None
