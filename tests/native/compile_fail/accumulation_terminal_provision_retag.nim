# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "status"}

## Private terminal plan/result storage cannot bypass guarded extraction.

import ../../../src/state/accumulation/terminal_provisions as accumulation_terminal_provisions
var result: AccumulationTerminalProvisionResult[PreparedTerminalAccumulationProvisions]
result.status = AccumulationTerminalProvisionError.None
