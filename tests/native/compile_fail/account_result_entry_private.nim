# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Successful account payloads are private behind the guarded result accessor.
import ../../../src/codec/[state_accounts, state_trie]
let parsed = default(ServiceMetadataResult[StateEntry])
discard parsed.completed
