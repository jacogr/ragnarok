# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: PreparedCurrentChainUpdate but got: PreparedChainUpdate", "early": ["installCurrentChainUpdate(", "[3] expected: PreparedCurrentChainUpdate but got: PreparedChainUpdate"]}

## Legacy prepared owners cannot bypass current installation readiness.
import ../../../src/chain/provider
import ../../../src/state/[accumulation_current_update, accumulation_publication, store]
var state = default(StateStore)
var view = default(ChainView)
installCurrentChainUpdate(state, view, default(PreparedChainUpdate))
