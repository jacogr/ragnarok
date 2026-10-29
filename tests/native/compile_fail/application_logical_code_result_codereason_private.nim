# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "codeReason"}

## Source, policies and tagged payload storage remain private and cannot be substituted externally.
import ../../../src/app/logical/code as logical_code
let source = default(LogicalCodeResult)
discard source.codeReason
