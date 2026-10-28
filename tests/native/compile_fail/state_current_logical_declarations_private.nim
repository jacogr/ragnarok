# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot forge retained logical startup authority.
# @@Verification={"group": "privacy", "expected": "data"}
import ../../../src/app/current_logical_startup as app_current_logical_startup
var owner = default(CurrentLogicalDeclarations)
discard owner.data
