# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject incomplete transcript provenance or a different nominal slot/ordinal.

# @@Verification={"group": "nominal", "expected": "GuaranteeSlot", "early": ["verifyComputedCredentials(", "[2] expected: GuaranteeSlot but got: StateTime"]}

import ../../../src/state/computed/[credentials as computed_credentials,
    guarantors as computed_guarantors, guarantee as computed_guarantee]
import ../../../src/codec/guarantees
import ../../../src/codec/state/safrole as state_safrole
discard verifyComputedCredentials(default(ComputedGuarantors), StateTime(0), newSeq[
    GuaranteeCredential](0))
