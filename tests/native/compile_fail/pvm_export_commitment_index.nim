# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Keep proof-page ordinals distinct from segment ordinals.

# @@Verification={"group": "nominal", "expected": "ExportPageIndex", "early": ["commitmentPage(", "[2] expected: ExportPageIndex but got: ExportCount"]}

import "../../../src/state/export/commitment" as export_commitment
import ../../../src/codec/work/digest as work_digest
discard commitmentPage(default(ExportCommitment), ExportCount(0))
