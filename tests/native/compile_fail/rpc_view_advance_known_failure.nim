# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Negative compiler fixture: a known failed append cannot expose a replacement history.
# @@Verification={"group": "contracts", "expected": "outcome.status"}

import std/assertions
import ../../../src/chain/genesis as chain_genesis
import ../../../src/chain/provider as chain_provider
let view = default(ChainView)
let outcome = view.advanceView(unavailableGenesis())
assert outcome.error == ViewAdvanceError.Uninitialized
discard outcome.value
