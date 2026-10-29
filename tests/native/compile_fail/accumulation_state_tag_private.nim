# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "status"}

## Atomic state application keeps result discriminators and retained alternatives private.

import ../../../src/state/accumulation/state as accumulation_state
var outcome: AccumulationStateResult
discard outcome.status
