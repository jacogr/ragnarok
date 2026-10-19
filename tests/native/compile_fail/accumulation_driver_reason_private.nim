# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "selectionReason"}

## Driver and stopped alternatives expose no mutable construction or raw extraction fields.

import ../../../src/state/accumulation_driver
var outcome: AccumulationDriverResult
discard outcome.selectionReason
