# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Core ordinals cannot silently become positions inside a pool or queue.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "nominal", "expected": "AuthorizationCoreIndex"}

import ../../../src/codec/state_authorization
let owner = default(AuthorizationSnapshot)
let core = default(AuthorizationCoreIndex)
let hash = authorizerAt(owner, core, core)
discard hash
