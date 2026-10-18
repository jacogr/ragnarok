# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Transcript storage must remain private even on a default result.
import ../../../src/crypto/assurance_context
let parsed = default(AssuranceContextResult[AssuranceSigningMessage])
discard parsed.completed
