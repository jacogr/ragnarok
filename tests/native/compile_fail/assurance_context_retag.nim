# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Callers cannot retag failed/default results as success.
import ../../../src/crypto/assurance_context
var parsed = default(AssuranceContextResult[VerifiedAssuranceCount])
parsed.status = AssuranceContextError.None
