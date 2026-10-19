# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Verified output hashes cannot masquerade as public keys.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "nominal", "expected": "got: BsOutput but wanted: BsPublicKey"}

import ../../../src/bandersnatch/bandersnatch
let value: BsPublicKey = default(BsOutput)
discard value
