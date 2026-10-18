# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Callers cannot manufacture a verified credential count.
import ../../../src/crypto/assurance_context
discard AssuranceContextResult[VerifiedAssuranceCount](status: AssuranceContextError.None,
    completed: VerifiedAssuranceCount(1))
