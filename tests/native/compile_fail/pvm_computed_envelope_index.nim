# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject a credential ordinal as a reporter-set ordinal.

# @@Verification={"group": "nominal", "expected": "ComputedReporterIndex", "early": ["computedEnvelopeReporterAt(", "[2] expected: ComputedReporterIndex but got: ComputedCredentialIndex"]}

import ../../../src/state/computed/[envelope as computed_envelope,
    credentials as computed_credentials]
discard computedEnvelopeReporterAt(default(ComputedGuaranteeEnvelope), ComputedCredentialIndex(0))
