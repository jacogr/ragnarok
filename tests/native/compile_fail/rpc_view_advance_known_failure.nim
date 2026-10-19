# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Negative compiler fixture: a known failed append cannot expose a replacement history.
import std/assertions
import ../../../src/chain/[genesis, provider]
let view = default(ChainView)
let outcome = view.advanceView(unavailableGenesis())
assert outcome.error == ViewAdvanceError.Uninitialized
discard outcome.value
