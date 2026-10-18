# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A raw digest cannot substitute for the domain-prefixed message.
import ../../../src/crypto/[primitives, guarantee]
let value: GuaranteeMessage = default(Blake2bHash)
discard value
