# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A signing transcript is not an Ed25519 signature.
import ../../../src/crypto/[primitives, guarantee]
let value: EdSignature = default(GuaranteeMessage)
discard value
