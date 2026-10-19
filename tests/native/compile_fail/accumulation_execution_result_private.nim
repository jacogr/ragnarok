# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "status"}

## Refuse access or substitution across the admitted execution certificate boundary.

import ../../../src/state/accumulation_execution
var result: AccumulationExecutionResult[CompletedBlockAccumulation]
discard result.status
