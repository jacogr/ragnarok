# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject a different nominal time or ordinal as guarantee assignment selection.

# @@Verification={"group": "nominal", "expected": "GuarantorIndex", "early": ["computedGuarantorAt(", "[3] expected: GuarantorIndex but got: StateValidatorIndex"]}

import ../../../src/state/computed_guarantors as state_computed_guarantors
import ../../../src/codec/guarantees as codec_guarantees
import ../../../src/codec/state_safrole as codec_state_safrole
discard computedGuarantorAt(default(ComputedGuarantors), GuaranteeSlot(0), StateValidatorIndex(0))
