# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Fixed child observations do not expose the private original/candidate update graph.
# @@Verification={"group":"privacy","expected":"data"}
import ../../../src/state/accumulation_current_update as state_accumulation_current_update
var update: PreparedCurrentChainUpdate
discard update.data
