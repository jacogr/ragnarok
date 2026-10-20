# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject private canonical guarantee provenance or successful result selection.

# @@Verification={"group": "privacy", "expected": "status"}

import ../../../src/state/computed_envelope
var candidate: ComputedEnvelopeResult[ComputedGuaranteeEnvelope]
discard candidate.status
