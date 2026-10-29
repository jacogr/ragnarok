# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A chain view is not an authenticated prepared current update.
# @@Verification={"group":"nominal","expected":"PreparedCurrentChainUpdate","early":["currentUpdatePriorState(","[1] expected: PreparedCurrentChainUpdate but got: ChainView"]}
import ../../../src/state/accumulation/current/update as accumulation_current_update
import ../../../src/chain/provider
var view: ChainView
discard currentUpdatePriorState(view)
