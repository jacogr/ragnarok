# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "data"}

## Private terminal plan/result storage cannot bypass guarded extraction.

import ../../../src/state/accumulation_terminal_provisions
var plan: PreparedTerminalAccumulationProvisions
discard plan.data
