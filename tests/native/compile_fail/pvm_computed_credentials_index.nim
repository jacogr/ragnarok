# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject incomplete transcript provenance or a different nominal slot/ordinal.

# @@Verification={"group": "nominal", "expected": "ComputedCredentialIndex", "early": ["computedCredentialAt(", "[2] expected: ComputedCredentialIndex but got: GuarantorIndex"]}

import ../../../src/state/computed_credentials as state_computed_credentials
import ../../../src/state/computed_guarantors as state_computed_guarantors
import ../../../src/state/computed_guarantee as state_computed_guarantee
import ../../../src/codec/guarantees as codec_guarantees
import ../../../src/codec/state_safrole as codec_state_safrole
discard computedCredentialAt(default(CredentialedComputedReport), GuarantorIndex(0))
