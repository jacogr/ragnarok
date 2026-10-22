# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "data"}

## Absence ownership and result storage stay private.
import ../../../src/state/[accumulation_absent, accumulation_inputs, store]
import ../../../src/codec/header
discard default(AbsentAccumulation).data
