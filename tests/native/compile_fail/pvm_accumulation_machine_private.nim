# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Callers cannot replace the retained bootstrap or CPU inside a prepared accumulation machine.

# @@Verification={"group": "privacy", "expected": "data"}

import ../../../src/state/accumulation_machine
var prepared: PreparedAccumulationMachine
discard prepared.data
