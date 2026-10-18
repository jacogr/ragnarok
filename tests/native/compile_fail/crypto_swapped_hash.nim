# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Equal widths never make distinct cryptographic domains interchangeable.
import ../../../src/crypto/primitives
let value: Blake2bHash = default(KeccakHash)
discard value
