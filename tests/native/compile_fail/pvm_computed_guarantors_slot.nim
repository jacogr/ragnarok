# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject a different nominal time or ordinal as guarantee assignment selection.

# @@Verification={"group": "nominal", "expected": "GuaranteeSlot", "early": ["computedGuarantorAt(", "[2] expected: GuaranteeSlot but got: StateTime"]}

import ../../../src/state/computed_guarantors
import ../../../src/codec/[guarantees, state_safrole]
discard computedGuarantorAt(default(ComputedGuarantors), StateTime(0), GuarantorIndex(0))
