# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "reason"}

## No caller may forge a complete batch or rewrite private phase alternatives.
import ../../../src/state/supervision_table
var value = default(SupervisionTableResult[StateSupervisionTable])
discard value.reason
