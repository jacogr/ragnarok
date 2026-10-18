# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot expose, retag or mutate state-layout result/metadata storage.
import ../../../src/codec/state_layout
let value = default(StateNodeInfo)
discard value.regularKey
