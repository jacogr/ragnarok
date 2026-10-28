# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "completed"}

## Source, policies and tagged payload storage remain private and cannot be substituted externally.
import ../../../src/app/logical_code as app_logical_code
let source = default(LogicalCodeResult)
discard source.completed
