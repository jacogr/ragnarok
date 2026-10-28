# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "data"}

## Complete provider ownership and result storage stay private.
import ../../../src/state/accumulation_coverage as state_accumulation_coverage
import ../../../src/state/accumulation_annulment as state_accumulation_annulment
import ../../../src/codec/header as codec_header
discard default(PreparedAccumulationCoverage).data
