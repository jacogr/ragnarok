# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Payload-byte policy cannot silently replace a trie-node work budget.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

import ../../../src/codec/[state_trie, bounded]
let bytes = default(ByteLimit)
let limits = StateTrieLimits(nodes: bytes)
discard limits
