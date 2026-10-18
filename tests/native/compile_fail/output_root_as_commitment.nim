# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Trie roots cannot silently become service output commitments.
import ../../../src/codec/[state_outputs, state_layout]
let value = AccumulationOutput(commitment: default(StateNodeHash))
discard value
