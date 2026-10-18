# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Intentional wrong-domain assignment must be rejected before runtime.
import ../../../src/crypto/[primitives, assurance_context]
import ../../../src/codec/assurances
let value: EdSignature = default(AssuranceSigningMessage)
discard value
