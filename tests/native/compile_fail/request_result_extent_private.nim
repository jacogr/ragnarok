# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Successful request payloads remain private behind the guarded result accessor.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "privacy", "expected": "completed"}

import ../../../src/codec/[state_requests, state_trie]
let parsed = default(RequestResult[int])
discard parsed.completed
