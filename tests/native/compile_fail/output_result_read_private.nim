# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Result success payloads cannot be read outside the guarded accessor.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "privacy", "expected": "completed"}

import ../../../src/codec/[state_outputs, state_trie]
let parsed = default(OutputLogResult[OutputLogRead])
discard parsed.completed
