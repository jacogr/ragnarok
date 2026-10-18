# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Successful request payloads remain private behind the guarded result accessor.
import ../../../src/codec/[state_requests, state_trie]
let parsed = default(RequestResult[RequestHistoryRead])
discard parsed.completed
