# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "source"}

## Source, policies and tagged payload storage remain private and cannot be substituted externally.
import ../../../src/app/logical_source_export as app_logical_source_export
let source = default(LogicalSourceExportPlan)
discard source.source
