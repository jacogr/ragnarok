# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A byte ceiling cannot silently become an aggregate authorizer-count ceiling.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "nominal", "expected": "got: ByteLimit but wanted: ElementLimit"}

import ../../../src/codec/state/authorization as state_authorization
import ../../../src/codec/bounded
let bytes = default(ByteLimit)
let policy = AuthorizationConfig(maxHashes: bytes)
discard policy
