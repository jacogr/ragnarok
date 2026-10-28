# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "normalizationReason"}

## Private terminal plan/result storage cannot bypass guarded extraction.

import ../../../src/state/accumulation_terminal_provisions as state_accumulation_terminal_provisions
var result: AccumulationTerminalProvisionResult[PreparedTerminalAccumulationProvisions]
discard result.normalizationReason
