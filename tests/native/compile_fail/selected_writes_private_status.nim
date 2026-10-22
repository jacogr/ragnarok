# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "status"}

## Selected write ownership and tagged result storage stay private.
import ../../../src/state/[accumulation_selected_writes, accumulation_account_selection,
    accumulation_creation_union]
let refused = prepareSelectedAccountWrites(default(PreparedAccumulationAccountSelection), default(
    PreparedAccumulationCreationUnion), default(SelectedAccountWriteLimits))
discard refused.status
