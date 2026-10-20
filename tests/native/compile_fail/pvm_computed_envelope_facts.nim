# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject incomplete context or mutable guarantee/metadata copies as verified source authority.

# @@Verification={"group": "nominal", "expected": "CredentialedComputedReport", "early": ["prepareComputedEnvelope(", "[1] expected: CredentialedComputedReport but got: ComputedCredentialInfo"]}

import ../../../src/state/[computed_envelope, computed_credentials, computed_guarantors]
import ../../../src/codec/guarantees
discard prepareComputedEnvelope(default(ComputedCredentialInfo), ComputedEnvelopeLimits())
