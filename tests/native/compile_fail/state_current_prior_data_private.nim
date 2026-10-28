# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Current update original/candidate graphs stay private after adding read-only observations.
# @@Verification={"group":"privacy","expected":"data"}
import ../../../src/state/accumulation_current_update as state_accumulation_current_update
var value: PreparedCurrentChainUpdate
discard value.data
