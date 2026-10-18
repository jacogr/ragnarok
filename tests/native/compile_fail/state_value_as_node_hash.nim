# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A regular leaf value digest is not a child-node identity.
import ../../../src/codec/state_layout
let wrong = default(StateValueHash)
let right = default(StateNodeHash)
discard encodeStateBranch(wrong, right)
