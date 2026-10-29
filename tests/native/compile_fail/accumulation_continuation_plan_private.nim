# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "data"}

## Refuse access or substitution across the admitted continuation planning boundary.

import ../../../src/state/accumulation/continuation as accumulation_continuation
var plan: PreparedAccumulationContinuation
discard plan.data
