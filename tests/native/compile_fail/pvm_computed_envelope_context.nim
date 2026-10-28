# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject incomplete context or mutable guarantee/metadata copies as verified source authority.

# @@Verification={"group": "nominal", "expected": "CredentialedComputedReport", "early": ["prepareComputedEnvelope(", "[1] expected: CredentialedComputedReport but got: ComputedGuarantors"]}

import ../../../src/state/computed_envelope as state_computed_envelope
import ../../../src/state/computed_credentials as state_computed_credentials
import ../../../src/state/computed_guarantors as state_computed_guarantors
import ../../../src/codec/guarantees as codec_guarantees
discard prepareComputedEnvelope(default(ComputedGuarantors), ComputedEnvelopeLimits())
