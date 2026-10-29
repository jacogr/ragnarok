# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "data"}

## Absence ownership and result storage stay private.
import ../../../src/state/accumulation/[absent as accumulation_absent,
    inputs as accumulation_inputs]
import ../../../src/state/store
import ../../../src/codec/header
discard default(AbsentAccumulation).data
