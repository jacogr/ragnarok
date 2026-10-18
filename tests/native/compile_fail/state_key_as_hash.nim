# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A 31-octet state key cannot stand in for a complete 32-octet child hash.
import ../../../src/codec/state_layout
let wrong = default(StateKey)
let right = default(StateNodeHash)
discard encodeStateBranch(wrong, right)
