# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A chain view is not an authenticated prepared current update.
# @@Verification={"group":"nominal","expected":"PreparedCurrentChainUpdate","early":["currentUpdatePriorState(","[1] expected: PreparedCurrentChainUpdate but got: ChainView"]}
import ../../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../../src/chain/provider as chain_provider
var view: ChainView
discard currentUpdatePriorState(view)
