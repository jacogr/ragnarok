# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject private computed publication authority and result selection.

# @@Verification={"group": "privacy", "expected": "publicationReason"}

import ../../../src/state/computed/state/publication as computed_state_publication
var candidate: ComputedStatePublicationResult[PublishedComputedState]
discard candidate.publicationReason
