# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: PreparedCurrentChainUpdate but got: PreparedChainUpdate", "early": ["installCurrentChainUpdate(", "[3] expected: PreparedCurrentChainUpdate but got: PreparedChainUpdate"]}

## Legacy prepared owners cannot bypass current installation readiness.
import ../../../src/chain/provider as chain_provider
import ../../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../../src/state/accumulation_publication as state_accumulation_publication
import ../../../src/state/store as state_store
var state = default(StateStore)
var view = default(ChainView)
installCurrentChainUpdate(state, view, default(PreparedChainUpdate))
