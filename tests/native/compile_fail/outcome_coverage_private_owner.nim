# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "data"}

## Complete provider ownership and result storage stay private.
import ../../../src/state/accumulation/[coverage as accumulation_coverage,
    annulment as accumulation_annulment]
import ../../../src/codec/header
discard default(PreparedAccumulationCoverage).data
