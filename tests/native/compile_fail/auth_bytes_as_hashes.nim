# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A byte ceiling cannot silently become an aggregate authorizer-count ceiling.
import ../../../src/codec/[state_authorization, bounded]
let bytes = default(ByteLimit)
let policy = AuthorizationConfig(maxHashes: bytes)
discard policy
