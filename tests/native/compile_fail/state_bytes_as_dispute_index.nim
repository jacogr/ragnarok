# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A byte resource ceiling cannot silently become an ordinal in a retained state set.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

import ../../../src/codec/[state_disputes, bounded]
var owner: DisputeStateSnapshot
var bytes: ByteLimit
let key = stateOffenderAt(owner, bytes)
discard key
