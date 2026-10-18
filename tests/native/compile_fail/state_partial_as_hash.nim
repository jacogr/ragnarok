# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A truncated left commitment cannot implicitly become a complete child-node hash.
import ../../../src/codec/state_layout
let wrong = default(LeftChildCommitment)
let right = default(StateNodeHash)
discard encodeStateBranch(wrong, right)
