# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "data"}

## Selected write ownership and tagged result storage stay private.
import ../../../src/state/accumulation/selected_writes as accumulation_selected_writes
import ../../../src/state/accumulation/account/selection as accumulation_account_selection
import ../../../src/state/accumulation/creation_union as accumulation_creation_union
discard default(PreparedSelectedAccountWrites).data
