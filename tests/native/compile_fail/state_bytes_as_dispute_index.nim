# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A byte resource ceiling cannot silently become an ordinal in a retained state set.
import ../../../src/codec/[state_disputes, bounded]
var owner: DisputeStateSnapshot
var bytes: ByteLimit
let key = stateOffenderAt(owner, bytes)
discard key
