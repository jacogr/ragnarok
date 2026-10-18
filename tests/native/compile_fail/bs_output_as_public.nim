# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Verified output hashes cannot masquerade as public keys.
import ../../../src/bandersnatch/bandersnatch
let value: BsPublicKey = default(BsOutput)
discard value
