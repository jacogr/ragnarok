# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject incomplete context or mutable guarantee/metadata copies as verified source authority.

# @@Verification={"group": "nominal", "expected": "CredentialedComputedReport", "early": ["prepareComputedEnvelope(", "[1] expected: CredentialedComputedReport but got: Guarantee"]}

import ../../../src/state/computed/[envelope as computed_envelope,
    credentials as computed_credentials, guarantors as computed_guarantors]
import ../../../src/codec/guarantees
discard prepareComputedEnvelope(default(Guarantee), ComputedEnvelopeLimits())
