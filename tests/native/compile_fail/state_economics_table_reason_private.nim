# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "reason"}

## Callers cannot forge complete report authority or rewrite failed alternatives.
import ../../../src/state/economics_table
var value = default(EconomicsTableResult[StateEconomicsTable])
discard value.reason
