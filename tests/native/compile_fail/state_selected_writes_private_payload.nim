# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "completed"}

## Selected write ownership and tagged result storage stay private.
import ../../../src/state/accumulation_selected_writes as state_accumulation_selected_writes
import ../../../src/state/accumulation_account_selection as state_accumulation_account_selection
import ../../../src/state/accumulation_creation_union as state_accumulation_creation_union
let refused = prepareSelectedAccountWrites(default(PreparedAccumulationAccountSelection), default(
    PreparedAccumulationCreationUnion), default(SelectedAccountWriteLimits))
discard refused.completed
